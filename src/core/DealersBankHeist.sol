// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDealersBankHeist} from "./IDealersBankHeist.sol";
import {IDealersCore} from "./IDealersCore.sol";
import {IDealersPVE} from "./IDealersPVE.sol";
import {IDealersPVP} from "./IDealersPVP.sol";
import {IDealersHeists} from "./IDealersHeists.sol";
import {IERC721Minimal} from "../utils/IERC721Minimal.sol";
import {IEntropyConsumer} from "../utils/pyth/IEntropyConsumer.sol";
import {IEntropyV2} from "../utils/pyth/IEntropyV2.sol";

/**
 * @title DealersBankHeist - Recurring community bank-heist event
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @custom:status CONCEPT — OUT OF AUDIT SCOPE. NOT deployed (mainnet `bankHeist` stays
 *      address(0)); it ships later via DeployBankHeist.s.sol. Included for design context only —
 *      accounting, interfaces, and config are provisional and subject to change before launch.
 *      Do NOT treat this module as production-ready or audit it as in-scope.
 *
 * @dev This contract IS the bank vault: set it as `PaymentHandler.bankVault` so it accrues the
 *      game-wide bank-fee share, then pays a capped slice back to active players each cycle.
 *
 *      Each cycle has a preparation window: dealers enter by paying $CASH (a sink — no attempt,
 *      no ETH). When the window closes the heist "happens": a Pyth Entropy draw picks N winners
 *      weighted by how much each entrant played during the window. Activity is measured by
 *      snapshotting existing PVE/PVP/heist counters at entry and diffing them at settlement —
 *      no changes to any existing contract.
 *
 *      All ETH leaves only via pull-based {claimWinnings}; CASH refunds via {claimRefund}.
 * @author Berny0x
 */
contract DealersBankHeist is IDealersBankHeist, IEntropyConsumer, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersCore public core;
    IERC721Minimal public nftContract;
    IDealersPVE public pve;
    IDealersPVP public pvp;
    IDealersHeists public heists;
    IEntropyV2 public entropy;

    bool public paused;
    uint16 internal constant BPS = 10000;

    // --- cycle config ---
    /**
     * @dev Immutable: currentEventId() derives event boundaries from (genesisStart, prepDuration);
     *      changing it post-genesis would retroactively shift every window and can brick entry.
     */
    uint64 public immutable prepDuration;
    uint64 public immutable genesisStart;
    uint96 public entryFee = 5000;          // $CASH sink to enter
    uint256 public entryRepGate;            // totalReputation required (0 = open)
    uint16 public eventCapBps = 2500;       // ≤25% of available vault per cycle
    uint256 public vaultFloor = 1 ether;    // skip entries while vault below this
    uint32 public minEntrants = 10;
    uint32 public maxEntrants = 5000;       // bounds the settlement loop
    uint256 public baseWeight;              // floor weight per paying entrant (0 = pure activity)
    uint256 public settleFee;               // ETH paid to settle() caller (0 = keeper-run)
    uint64 public refundTimeout = 7 days;   // post-close grace before a stuck draw is refundable
    uint16[] public prizeSplitBps;          // winner split, e.g. [6000,3000,1000]

    // --- events / entries ---
    mapping(uint256 eventId => HeistEvent) public events;
    mapping(uint256 eventId => uint96) public eventEntryFee; // entry fee locked at event creation
    mapping(uint256 eventId => mapping(uint256 index => uint256 tokenId)) public entryAt;
    mapping(uint256 eventId => mapping(uint256 tokenId => bool)) public entered;
    mapping(uint256 eventId => mapping(uint256 tokenId => uint64)) public activityAtEntry;
    mapping(uint256 eventId => mapping(uint256 tokenId => bool)) public refunded;
    mapping(uint64 pythSeq => uint256 eventId) public eventOfSeq;
    mapping(uint256 eventId => mapping(uint256 index => uint256 weight)) public weightAt; // frozen draw weights

    // --- payouts ---
    mapping(uint256 tokenId => uint256) public winnings;
    uint256 public totalUnclaimedWinnings;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event ContractsUpdated();
    event ConfigUpdated();
    event EmergencyWithdrawn(address indexed to, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error ContractPaused();
    error NotDealerOwner();
    error DealerNotInitialized();
    error VaultBelowFloor();
    error EventClosed();
    error EventNotClosed();
    error DrawWindowClosed();
    error AlreadyEntered();
    error AlreadyResolved();
    error DrawAlreadyRequested();
    error DrawNotRequested();
    error WeightsAlreadyDone();
    error WeightsNotReady();
    error NotSeeded();
    error RepTooLow();
    error EntrantsFull();
    error InsufficientFee();
    error NothingToClaim();
    error NotRefundable();
    error NotEntered();
    error AlreadyRefunded();
    error InvalidConfig();
    error InvalidAddress();
    error TransferFailed();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        address _core,
        address _nftContract,
        address _pve,
        address _pvp,
        address _heists,
        address _entropy,
        uint64 _prepDuration
    ) {
        if (_prepDuration == 0) revert InvalidConfig();

        _initializeOwner(msg.sender);
        core = IDealersCore(_core);
        nftContract = IERC721Minimal(_nftContract);
        pve = IDealersPVE(_pve);
        pvp = IDealersPVP(_pvp);
        heists = IDealersHeists(_heists);
        entropy = IEntropyV2(_entropy);

        prepDuration = _prepDuration;
        genesisStart = uint64(block.timestamp);
        prizeSplitBps = [6000, 3000, 1000];
    }

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyDealerOwner(uint256 tokenId) {
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();
        _;
    }

    // =============================================================
    //                        FUND INTAKE
    // =============================================================

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // =============================================================
    //                        PREPARATION
    // =============================================================

    /**
     * @notice Enter the current cycle by paying the locked $CASH entry fee (a sink — no attempt, no ETH).
     */
    function enter(uint256 tokenId) external nonReentrant whenNotPaused onlyDealerOwner(tokenId) {
        if (availableVault() < vaultFloor) revert VaultBelowFloor();

        uint256 eid = currentEventId();
        HeistEvent storage e = events[eid];
        if (e.closesAt == 0) {
            e.closesAt = uint64(genesisStart + (eid + 1) * prepDuration);
            eventEntryFee[eid] = entryFee; // lock the fee for this event so refunds match what was paid
        }
        if (block.timestamp >= e.closesAt) revert EventClosed();
        if (entered[eid][tokenId]) revert AlreadyEntered();
        if (e.entryCount >= maxEntrants) revert EntrantsFull();

        IDealersCore.GameState memory s = core.getGameState(tokenId);
        if (!s.isInitialized) revert DealerNotInitialized();
        if (s.totalReputation < entryRepGate) revert RepTooLow();

        uint96 fee = eventEntryFee[eid];
        core.spendCash(tokenId, fee); // $CASH sink (locked per-event fee, not the mutable global)

        uint64 snapshot = activityOf(tokenId);
        entered[eid][tokenId] = true;
        entryAt[eid][e.entryCount] = tokenId;
        activityAtEntry[eid][tokenId] = snapshot;
        unchecked { e.entryCount++; }
        e.cashSunk += fee;

        emit Entered(eid, tokenId, msg.sender, snapshot);
    }

    // =============================================================
    //                        DRAW / SETTLE
    // =============================================================

    /**
     * @notice Request the Pyth Entropy draw for a closed event within the grace window; pays the
     *         entropy fee (excess refunded). A below-min event is skipped here, enabling refunds.
     */
    function requestDraw(uint256 eventId) external payable nonReentrant {
        HeistEvent storage e = events[eventId];
        if (e.closesAt == 0 || block.timestamp < e.closesAt) revert EventNotClosed();
        if (e.settled || e.skipped) revert AlreadyResolved();
        if (e.seeded || e.pythSeq != 0) revert DrawAlreadyRequested();
        // Past the grace window the event is refund-only; a draw can no longer be started. This is
        // what makes refund and settlement mutually exclusive — no refund-then-draw free-roll.
        if (block.timestamp > uint256(e.closesAt) + refundTimeout) revert DrawWindowClosed();

        if (e.entryCount < minEntrants) {
            e.skipped = true; // enables CASH refunds
            emit EventSkipped(eventId, e.entryCount);
            _refundExcess(msg.value);
            return;
        }

        uint256 fee = entropy.getFeeV2();
        if (msg.value < fee) revert InsufficientFee();

        uint64 pseq = entropy.requestV2{value: fee}();
        e.pythSeq = pseq;
        e.drawRequestedAt = uint64(block.timestamp);
        eventOfSeq[pseq] = eventId;

        _refundExcess(msg.value - fee);
        emit DrawRequested(eventId, pseq, msg.sender);
    }

    /**
     * @inheritdoc IEntropyConsumer
     */
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    /**
     * @dev Pyth callback — minimal: store the seed, settlement happens in {settle}.
     */
    function entropyCallback(uint64 sequence, address, bytes32 randomNumber) internal override {
        uint256 eid = eventOfSeq[sequence];
        HeistEvent storage e = events[eid];
        // Ignore a late callback for an event that was turned refund-only (skipped) after a stuck draw.
        if (e.pythSeq != sequence || e.seeded || e.skipped) return;
        e.seed = randomNumber;
        e.seeded = true;
        emit DrawSeeded(eid, sequence);
    }

    /**
     * @notice Freeze entrants' draw weights for a requested event, up to `maxCount` per call.
     * @dev Paginated — call repeatedly until weightCursor == entryCount, then {settle}. Weights are
     *      frozen HERE rather than read live at settle, so activity ground out after the prep window
     *      (during the Pyth callback wait) cannot inflate a winner's odds (V-001). Refunded entrants
     *      are frozen at weight 0. Anyone may call.
     * @param eventId The event identifier
     * @param maxCount Max entrants to process this call
     */
    function snapshotWeights(uint256 eventId, uint256 maxCount) external nonReentrant {
        HeistEvent storage e = events[eventId];
        if (e.pythSeq == 0) revert DrawNotRequested();
        if (e.settled || e.skipped) revert AlreadyResolved();

        uint256 count = e.entryCount;
        uint256 i = e.weightCursor;
        if (i >= count) revert WeightsAlreadyDone();
        uint256 end = i + maxCount;
        if (end > count) end = count;

        uint256 added;
        for (; i < end; ) {
            uint256 tid = entryAt[eventId][i];
            uint256 w;
            if (!refunded[eventId][tid]) {
                uint64 cur = activityOf(tid);
                uint64 snap = activityAtEntry[eventId][tid];
                w = (cur > snap ? uint256(cur - snap) : 0) + baseWeight;
            }
            weightAt[eventId][i] = w;
            added += w;
            unchecked { ++i; }
        }
        e.weightCursor = uint32(i);
        e.totalWeight += added;
        emit WeightsSnapshotted(eventId, uint32(i), e.totalWeight);
    }

    /**
     * @notice Settle a seeded event whose weights are fully frozen: pick activity-weighted winners
     *         and credit their pull-based winnings. The keeper fee is capped to spendable ETH.
     */
    function settle(uint256 eventId) external nonReentrant {
        HeistEvent storage e = events[eventId];
        if (!e.seeded) revert NotSeeded();
        if (e.settled || e.skipped) revert AlreadyResolved();
        if (e.weightCursor != e.entryCount) revert WeightsNotReady();
        e.settled = true;

        // Snapshot once; cap the keeper fee to spendable ETH so it can never be paid out of the
        // balance reserved for prior winners (totalUnclaimedWinnings). prize is a fraction of what
        // remains after the fee, so prize + fee <= availableVault and the solvency invariant holds.
        uint256 avail = availableVault();
        uint256 fee = settleFee > avail ? avail : settleFee;
        uint256 prize = ((avail - fee) * eventCapBps) / BPS;

        uint256 winnerCount = _distribute(eventId, e.seed, prize);

        emit EventSettled(eventId, prize, winnerCount);

        if (fee != 0) _safeTransferETH(msg.sender, fee);
    }

    /**
     * @dev Selects up to `prizeSplitBps.length` distinct winners weighted by the weights FROZEN in
     *      {snapshotWeights}, credits each its split. Pull-based: no ETH transfer here, and no live
     *      activity reads — settlement cannot be influenced by post-close grinding (V-001).
     */
    function _distribute(uint256 eventId, bytes32 seed, uint256 prize) private returns (uint256 winnerCount) {
        uint256 count = events[eventId].entryCount;
        uint256 totalWeight = events[eventId].totalWeight;
        if (totalWeight == 0) return 0; // no activity → prize rolls over
        uint256 n = prizeSplitBps.length;

        uint256[] memory weights = new uint256[](count);
        for (uint256 i = 0; i < count; ) {
            weights[i] = weightAt[eventId][i];
            unchecked { ++i; }
        }

        uint256 picks = n < count ? n : count;
        for (uint256 k = 0; k < picks; ) {
            uint256 r = uint256(keccak256(abi.encodePacked(seed, k))) % totalWeight;
            uint256 acc;
            for (uint256 i = 0; i < count; ) {
                acc += weights[i];
                if (r < acc && weights[i] != 0) {
                    uint256 tid = entryAt[eventId][i];
                    uint256 amount = (prize * prizeSplitBps[k]) / BPS;
                    if (amount != 0) {
                        winnings[tid] += amount;
                        totalUnclaimedWinnings += amount;
                    }
                    emit WinnerSelected(eventId, tid, k, amount);
                    totalWeight -= weights[i];
                    weights[i] = 0;
                    unchecked { ++winnerCount; }
                    break;
                }
                unchecked { ++i; }
            }
            if (totalWeight == 0) break;
            unchecked { ++k; }
        }
    }

    // =============================================================
    //                        CLAIMS
    // =============================================================

    /**
     * @notice Claim a dealer's credited ETH winnings to the current NFT owner.
     */
    function claimWinnings(uint256 tokenId) external nonReentrant {
        uint256 amt = winnings[tokenId];
        if (amt == 0) revert NothingToClaim();
        winnings[tokenId] = 0;
        totalUnclaimedWinnings -= amt;
        address to = nftContract.ownerOf(tokenId);
        _safeTransferETH(to, amt);
        emit WinningsClaimed(tokenId, to, amt);
    }

    /**
     * @notice Reclaim the $CASH entry for an event that will never pay out: a below-min skip, an
     *         abandoned event (closed, no draw requested within the grace window), or a stuck draw
     *         (requested but never seeded within the grace window).
     * @dev A seeded event is NEVER refundable — settlement pays its winners. The first refund on an
     *      abandoned/stuck event flips it to `skipped` (terminal), permanently blocking requestDraw
     *      and settle, so refunds and prizes can never both be claimed for the same entry (V-002).
     */
    function claimRefund(uint256 eventId, uint256 tokenId) external nonReentrant onlyDealerOwner(tokenId) {
        if (!entered[eventId][tokenId]) revert NotEntered();
        if (refunded[eventId][tokenId]) revert AlreadyRefunded();

        HeistEvent storage e = events[eventId];
        bool abandoned = e.pythSeq == 0 && e.closesAt != 0 && block.timestamp > uint256(e.closesAt) + refundTimeout;
        bool stuckDraw = e.pythSeq != 0 && !e.seeded && block.timestamp > uint256(e.drawRequestedAt) + refundTimeout;
        if (!e.skipped && !abandoned && !stuckDraw) revert NotRefundable();

        if (!e.skipped) e.skipped = true; // terminal — no requestDraw / settle after refunds open

        refunded[eventId][tokenId] = true;
        uint96 fee = eventEntryFee[eventId];
        core.addCash(tokenId, fee);
        emit Refunded(eventId, tokenId, fee);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /** @notice The id of the currently open preparation window, derived from elapsed time. */
    function currentEventId() public view returns (uint256) {
        return (block.timestamp - genesisStart) / prepDuration;
    }

    /** @notice Read the full state of a heist event. */
    function getEvent(uint256 eventId) external view returns (HeistEvent memory) {
        return events[eventId];
    }

    /** @notice A dealer's lifetime PVE + PVP + heist plays — the raw activity metric. */
    function activityOf(uint256 tokenId) public view returns (uint64) {
        IDealersPVE.PveStats memory p = pve.getDealerPveStats(tokenId);
        IDealersPVP.PvpStats memory v = pvp.getDealerPvpStats(tokenId);
        uint256 total = uint256(p.wins) + p.losses + p.ties
            + uint256(v.attackWins) + v.attackLosses + v.defendWins + v.defendLosses
            + uint256(heists.heistRuns(tokenId));
        return uint64(total);
    }

    /** @notice A dealer's LIVE in-window activity weight (informational; settlement uses the frozen snapshot). */
    function eventWeight(uint256 eventId, uint256 tokenId) external view returns (uint256) {
        if (!entered[eventId][tokenId]) return 0;
        uint64 cur = activityOf(tokenId);
        uint64 snap = activityAtEntry[eventId][tokenId];
        return (cur > snap ? uint256(cur - snap) : 0) + baseWeight;
    }

    /** @notice Vault ETH available for prizes and fees (balance minus unclaimed winnings). */
    function availableVault() public view returns (uint256) {
        uint256 bal = address(this).balance;
        return bal > totalUnclaimedWinnings ? bal - totalUnclaimedWinnings : 0;
    }

    /** @notice Number of winner ranks per event (the length of the prize split). */
    function winnerCountTarget() external view returns (uint256) {
        return prizeSplitBps.length;
    }

    // =============================================================
    //                     INTERNAL HELPERS
    // =============================================================

    function _refundExcess(uint256 amount) private {
        if (amount != 0) _safeTransferETH(msg.sender, amount);
    }

    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // =============================================================
    //                        ADMIN
    // =============================================================

    /** @notice Update module references; zero-address args are left unchanged. */
    function setContracts(
        address _core,
        address _nftContract,
        address _pve,
        address _pvp,
        address _heists,
        address _entropy
    ) external onlyOwner {
        if (_core != address(0)) core = IDealersCore(_core);
        if (_nftContract != address(0)) nftContract = IERC721Minimal(_nftContract);
        if (_pve != address(0)) pve = IDealersPVE(_pve);
        if (_pvp != address(0)) pvp = IDealersPVP(_pvp);
        if (_heists != address(0)) heists = IDealersHeists(_heists);
        if (_entropy != address(0)) entropy = IEntropyV2(_entropy);
        emit ContractsUpdated();
    }

    /** @notice Set the $CASH entry fee and reputation gate applied to FUTURE events (existing events keep their locked fee). */
    function setCycleConfig(uint96 _entryFee, uint256 _entryRepGate) external onlyOwner {
        entryFee = _entryFee;
        entryRepGate = _entryRepGate;
        emit ConfigUpdated();
    }

    /** @notice Configure prize cap, vault floor, entrant bounds, base weight, settle fee, refund timeout, and winner split. */
    function setPrizeConfig(
        uint16 _eventCapBps,
        uint256 _vaultFloor,
        uint32 _minEntrants,
        uint32 _maxEntrants,
        uint256 _baseWeight,
        uint256 _settleFee,
        uint64 _refundTimeout,
        uint16[] calldata _prizeSplitBps
    ) external onlyOwner {
        if (_eventCapBps > BPS || _maxEntrants == 0 || _prizeSplitBps.length == 0) revert InvalidConfig();
        uint256 sum;
        for (uint256 i = 0; i < _prizeSplitBps.length; ) {
            sum += _prizeSplitBps[i];
            unchecked { ++i; }
        }
        if (sum > BPS) revert InvalidConfig();

        eventCapBps = _eventCapBps;
        vaultFloor = _vaultFloor;
        minEntrants = _minEntrants;
        maxEntrants = _maxEntrants;
        baseWeight = _baseWeight;
        settleFee = _settleFee;
        refundTimeout = _refundTimeout;
        prizeSplitBps = _prizeSplitBps;
        emit ConfigUpdated();
    }

    /**
     * @notice Owner escape hatch — withdraw spendable vault ETH.
     * @dev Bounded by availableVault(), so it can never touch ETH owed to winners.
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        if (amount > availableVault()) revert InvalidConfig();
        _safeTransferETH(to, amount);
        emit EmergencyWithdrawn(to, amount);
    }

    /** @notice Pause entries (accrual and claims continue). */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /** @notice Resume entries. */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
