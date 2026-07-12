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

/**
 * @title DealersBankHeist - Seasonal community bank-heist distribution
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev This contract IS the bank vault: set it as `PaymentHandler.bankVault` so it accrues the
 *      game-wide bank-fee share, then pays a capped slice back to active players each season.
 *
 *      The owner opens a season with its criteria locked in. Dealers opt in by paying $CASH
 *      (a sink); entry snapshots their lifetime PVE/PVP/heist counters. After close, scores are
 *      frozen permissionlessly (delta vs baseline, weighted per config, amplified by daily-focus
 *      check-ins) and the season settles a pot of potBps x availableVault. Payouts are
 *      pari-mutuel — claim = score / totalScore x pot — so the pot never scales with activity
 *      and the vault structurally cannot overpay. No randomness anywhere; all ETH leaves via
 *      pull-based {claim}.
 * @author Berny0x
 */
contract DealersBankHeist is IDealersBankHeist, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersCore public core;
    IERC721Minimal public nftContract;
    IDealersPVE public pve;
    IDealersPVP public pvp;
    IDealersHeists public heists;

    bool public paused;
    uint16 internal constant BPS = 10000;
    uint16 internal constant MAX_SETTLE_FEE_BPS = 100; // keeper tip ceiling: 1% of the available vault

    // --- global config ---
    uint256 public settleFee; // ETH paid to settle() caller (0 = keeper-run), capped at MAX_SETTLE_FEE_BPS

    // --- seasons / entries ---
    uint256 public seasonCount;
    mapping(uint256 seasonId => Season) internal seasons;
    mapping(uint256 seasonId => mapping(uint256 index => uint256 tokenId)) public entryAt;
    mapping(uint256 seasonId => mapping(uint256 tokenId => bool)) public entered;
    mapping(uint256 seasonId => mapping(uint256 tokenId => Baseline)) public baselines;
    mapping(uint256 seasonId => mapping(uint256 tokenId => uint256)) public scoreOf;
    mapping(uint256 seasonId => mapping(uint256 tokenId => Focus)) public focusState;
    mapping(uint256 seasonId => mapping(uint256 tokenId => bool)) public claimed;
    mapping(uint256 seasonId => mapping(uint256 tokenId => bool)) public refunded;

    // --- payouts ---
    /** @dev ETH reserved for settled-but-unswept pots; balance >= reservedETH always. */
    uint256 public reservedETH;

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

    error ContractPaused();
    error NotDealerOwner();
    error DealerNotInitialized();
    error DealerInJail();
    error NoOpenSeason();
    error SeasonClosed();
    error SeasonNotClosed();
    error PreviousSeasonUnresolved();
    error AlreadyEntered();
    error AlreadyCheckedInToday();
    error EntrantsFull();
    error RepTooLow();
    error AlreadyResolved();
    error ScoresAlreadyFrozen();
    error ScoresNotReady();
    error FreezeWindowClosed();
    error BelowMinEntrants();
    error SettleWindowClosed();
    error EmptyVault();
    error SeasonInFlight();
    error NotSettled();
    error ClaimWindowClosed();
    error ClaimWindowOpen();
    error AlreadyClaimed();
    error NothingToClaim();
    error AlreadySwept();
    error NotEntered();
    error AlreadyRefunded();
    error NotRefundable();
    error InvalidConfig();
    error InvalidAddress();
    error InsufficientVault();
    error TransferFailed();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(address _core, address _nftContract, address _pve, address _pvp, address _heists) {
        if (
            _core == address(0) || _nftContract == address(0) || _pve == address(0) || _pvp == address(0)
                || _heists == address(0)
        ) revert InvalidAddress();
        _initializeOwner(msg.sender);
        core = IDealersCore(_core);
        nftContract = IERC721Minimal(_nftContract);
        pve = IDealersPVE(_pve);
        pvp = IDealersPVP(_pvp);
        heists = IDealersHeists(_heists);
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
    //                          SEASONS
    // =============================================================

    /**
     * @notice Open a new season with its criteria locked in — players can verify exactly what
     *         they are grinding for.
     * @dev Requires the previous season terminal (settled or skipped), so activity can never
     *      count toward two seasons at once.
     */
    function openSeason(SeasonConfig calldata cfg) external onlyOwner {
        if (cfg.duration == 0 || cfg.potBps > BPS || cfg.claimWindow == 0 || cfg.refundTimeout == 0) {
            revert InvalidConfig();
        }
        if (cfg.freezeWindow == 0 || cfg.freezeWindow >= cfg.refundTimeout) revert InvalidConfig();
        if (cfg.maxEntrants == 0 || cfg.maxEntrants < cfg.minEntrants) revert InvalidConfig();
        if (uint256(cfg.entryFee) * cfg.maxEntrants > type(uint96).max) revert InvalidConfig(); // cashSunk fits uint96
        if (cfg.weights[0] == 0 && cfg.weights[1] == 0 && cfg.weights[2] == 0 && cfg.weights[3] == 0) {
            revert InvalidConfig();
        }
        uint256 count = seasonCount;
        if (count != 0) {
            Season storage prev = seasons[count - 1];
            if (!prev.settled && !prev.skipped) revert PreviousSeasonUnresolved();
        }

        Season storage s = seasons[count];
        s.config = cfg;
        s.opensAt = uint64(block.timestamp);
        s.closesAt = uint64(block.timestamp) + cfg.duration;
        seasonCount = count + 1;

        emit SeasonOpened(count, s.opensAt, s.closesAt);
    }

    /**
     * @notice Owner escape hatch — terminate an unsettled season; entrants reclaim their $CASH
     *         via {claimRefund}, no ETH moves.
     */
    function cancelSeason(uint256 seasonId) external onlyOwner {
        Season storage s = seasons[seasonId];
        if (s.closesAt == 0) revert NoOpenSeason();
        if (s.settled || s.skipped) revert AlreadyResolved();
        s.skipped = true;
        emit SeasonCancelled(seasonId);
    }

    /**
     * @notice Enter the latest season by paying its locked $CASH entry fee (a sink — no attempt,
     *         no ETH). Snapshots the dealer's counter baseline: only play from here on scores.
     *         Jailed dealers can't join the crew.
     * @dev A zeroBaseline season keeps the baseline at zero instead, crediting all lifetime play —
     *      the retroactive genesis mode for seeding season one with pre-launch activity.
     */
    function enter(uint256 tokenId) external nonReentrant whenNotPaused onlyDealerOwner(tokenId) {
        uint256 count = seasonCount;
        if (count == 0) revert NoOpenSeason();
        uint256 sid = count - 1;
        Season storage s = seasons[sid];
        if (s.skipped || block.timestamp >= s.closesAt) revert SeasonClosed();
        if (entered[sid][tokenId]) revert AlreadyEntered();
        if (s.entryCount >= s.config.maxEntrants) revert EntrantsFull();

        IDealersCore.GameState memory g = core.getGameState(tokenId);
        if (!g.isInitialized) revert DealerNotInitialized();
        if (g.isJailed) revert DealerInJail();
        if (g.totalReputation < s.config.entryRepGate) revert RepTooLow();

        uint96 fee = s.config.entryFee;
        if (fee != 0) core.spendCash(tokenId, fee);

        if (!s.config.zeroBaseline) {
            (uint64 pveGames, uint64 pvpGames, uint64 heistRuns) = metricsOf(tokenId);
            baselines[sid][tokenId] = Baseline({pveGames: pveGames, pvpGames: pvpGames, heistRuns: heistRuns});
        }
        uint32 today = uint32(block.timestamp / 1 days);
        focusState[sid][tokenId] = Focus({
            count: 1, // entry is the first check-in
            lastDay: today,
            entryDay: today
        });
        entered[sid][tokenId] = true;
        entryAt[sid][s.entryCount] = tokenId;
        unchecked {
            s.entryCount++;
        }
        s.cashSunk += fee;

        emit Entered(sid, tokenId, msg.sender);
    }

    /**
     * @notice Daily focus check-in for the latest season — one per UTC day (block.timestamp /
     *         1 days resets exactly at 00:00 UTC), no play required. Each point multiplies the
     *         final score by the season's focusBonusBps. Jailed dealers can't check in with
     *         the crew.
     * @dev Dealer-owner-only so a communal keeper can't max every dealer's focus. Focus alone
     *      earns nothing — it only amplifies a score that still requires real play.
     */
    function checkIn(uint256 tokenId) external whenNotPaused onlyDealerOwner(tokenId) {
        uint256 count = seasonCount;
        if (count == 0) revert NoOpenSeason();
        uint256 sid = count - 1;
        Season storage s = seasons[sid];
        if (s.skipped || block.timestamp >= s.closesAt) revert SeasonClosed();
        if (!entered[sid][tokenId]) revert NotEntered();
        if (core.getGameState(tokenId).isJailed) revert DealerInJail();

        Focus storage f = focusState[sid][tokenId];
        uint32 today = uint32(block.timestamp / 1 days);
        if (today <= f.lastDay) revert AlreadyCheckedInToday();

        unchecked {
            f.count++;
        }
        f.lastDay = today;
        emit CheckedIn(sid, tokenId, f.count);
    }

    // =============================================================
    //                      FREEZE / SETTLE
    // =============================================================

    /**
     * @notice Freeze entrants' scores for a closed season, up to `maxCount` per call.
     * @dev Paginated in entry order — call repeatedly until scoreCursor == entryCount, then
     *      {settle}. A below-minEntrants season is skipped here, enabling refunds. Anyone may
     *      call, but scoring is only open during (closesAt, closesAt + freezeWindow]: since
     *      _scoreFor reads live counters, an unbounded window would let a late-frozen entrant
     *      grind post-close and inflate their share; the window bounds that gap for everyone.
     *      Miss it and the season falls to the refund path. The below-min skip is not gated —
     *      refunds can always open.
     * @param seasonId The season identifier
     * @param maxCount Max entrants to process this call
     */
    function freezeScores(uint256 seasonId, uint256 maxCount) external nonReentrant {
        Season storage s = seasons[seasonId];
        if (s.closesAt == 0 || block.timestamp < s.closesAt) revert SeasonNotClosed();
        if (s.settled || s.skipped) revert AlreadyResolved();

        uint256 count = s.entryCount;
        if (count < s.config.minEntrants) {
            s.skipped = true; // enables $CASH refunds
            emit SeasonSkipped(seasonId, uint32(count));
            return;
        }

        if (block.timestamp > uint256(s.closesAt) + s.config.freezeWindow) revert FreezeWindowClosed();

        uint256 i = s.scoreCursor;
        if (i >= count) revert ScoresAlreadyFrozen();
        uint256 end = i + maxCount;
        if (end > count) end = count;

        uint256 added;
        for (; i < end;) {
            uint256 tid = entryAt[seasonId][i];
            uint256 score = _scoreFor(s, seasonId, tid);
            scoreOf[seasonId][tid] = score;
            added += score;
            unchecked {
                ++i;
            }
        }
        s.scoreCursor = uint32(i);
        s.totalScore += added;
        emit ScoresFrozen(seasonId, uint32(i), s.totalScore);
    }

    /**
     * @notice Settle a fully-frozen season: reserve potBps of the available vault as the pot and
     *         open the claim window.
     * @dev Must land within closesAt + refundTimeout; past it the season is refund-only, keeping
     *      settle and {claimRefund} mutually exclusive. Zero total score routes to the skip/refund
     *      path instead. The keeper fee is capped so it can never drain the vault.
     */
    function settle(uint256 seasonId) external nonReentrant {
        Season storage s = seasons[seasonId];
        if (s.closesAt == 0 || block.timestamp < s.closesAt) revert SeasonNotClosed();
        if (s.settled || s.skipped) revert AlreadyResolved();
        if (block.timestamp > uint256(s.closesAt) + s.config.refundTimeout) revert SettleWindowClosed();
        if (s.entryCount < s.config.minEntrants) revert BelowMinEntrants(); // freezeScores skips it
        if (s.scoreCursor != s.entryCount) revert ScoresNotReady();

        if (s.totalScore == 0) {
            s.skipped = true;
            emit SeasonSkipped(seasonId, s.entryCount);
            return;
        }

        // pot + fee <= availableVault, preserving the reservedETH solvency invariant
        uint256 avail = availableVault();
        uint256 maxFee = (avail * MAX_SETTLE_FEE_BPS) / BPS;
        uint256 fee = settleFee > maxFee ? maxFee : settleFee;
        uint256 pot = ((avail - fee) * s.config.potBps) / BPS;
        // A zero pot would trap entrants' $CASH (settled is never refundable); left unsettled,
        // the season falls to the refund path after the grace window.
        if (pot == 0) revert EmptyVault();

        s.settled = true;
        s.settledAt = uint64(block.timestamp);
        s.pot = pot;
        reservedETH += pot;

        emit SeasonSettled(seasonId, pot, s.totalScore);

        if (fee != 0) _safeTransferETH(msg.sender, fee);
    }

    // =============================================================
    //                          CLAIMS
    // =============================================================

    /**
     * @notice Claim a dealer's pro-rata share — score / totalScore x pot — to the current NFT
     *         owner. Permissionless: batch distribution is anyone multicalling claims.
     */
    function claim(uint256 seasonId, uint256 tokenId) external nonReentrant {
        Season storage s = seasons[seasonId];
        if (!s.settled) revert NotSettled();
        if (block.timestamp > uint256(s.settledAt) + s.config.claimWindow) revert ClaimWindowClosed();
        if (claimed[seasonId][tokenId]) revert AlreadyClaimed();

        uint256 score = scoreOf[seasonId][tokenId];
        if (score == 0) revert NothingToClaim();

        claimed[seasonId][tokenId] = true;
        uint256 amount = (s.pot * score) / s.totalScore;
        s.claimedTotal += amount;
        reservedETH -= amount;

        address to = nftContract.ownerOf(tokenId);
        _safeTransferETH(to, amount);
        emit Claimed(seasonId, tokenId, to, amount);
    }

    /**
     * @notice Return a settled season's unclaimed remainder (including rounding dust) to the
     *         vault once its claim window has expired.
     */
    function sweepExpired(uint256 seasonId) external nonReentrant {
        Season storage s = seasons[seasonId];
        if (!s.settled) revert NotSettled();
        if (s.swept) revert AlreadySwept();
        if (block.timestamp <= uint256(s.settledAt) + s.config.claimWindow) revert ClaimWindowOpen();

        s.swept = true;
        uint256 remainder = s.pot - s.claimedTotal;
        reservedETH -= remainder;
        emit SeasonSwept(seasonId, remainder);
    }

    /**
     * @notice Reclaim the $CASH entry for a season that will never pay out: a below-min skip, an
     *         owner cancel, or an abandoned season (closed but not settled within the grace
     *         window).
     * @dev A settled season is NEVER refundable. The first refund on an abandoned season flips it
     *      to `skipped` (terminal), so refunds and payouts can never both be claimed.
     */
    function claimRefund(uint256 seasonId, uint256 tokenId) external nonReentrant onlyDealerOwner(tokenId) {
        if (!entered[seasonId][tokenId]) revert NotEntered();
        if (refunded[seasonId][tokenId]) revert AlreadyRefunded();

        Season storage s = seasons[seasonId];
        bool abandoned = !s.settled && block.timestamp > uint256(s.closesAt) + s.config.refundTimeout;
        if (!s.skipped && !abandoned) revert NotRefundable();

        if (!s.skipped) s.skipped = true; // terminal — no freeze / settle after refunds open

        refunded[seasonId][tokenId] = true;
        uint96 fee = s.config.entryFee;
        core.addCash(tokenId, fee);
        emit Refunded(seasonId, tokenId, fee);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Read the full state of a season.
     */
    function getSeason(uint256 seasonId) external view returns (Season memory) {
        return seasons[seasonId];
    }

    /**
     * @notice A dealer's live lifetime counters for the three scored games.
     * @return pveGames PVE wins + losses + ties
     * @return pvpGames PVP attacker-side games only (attackWins + attackLosses)
     * @return heistRuns Lifetime heist runs
     */
    function metricsOf(uint256 tokenId) public view returns (uint64 pveGames, uint64 pvpGames, uint64 heistRuns) {
        IDealersPVE.PveStats memory p = pve.getDealerPveStats(tokenId);
        IDealersPVP.PvpStats memory v = pvp.getDealerPvpStats(tokenId);
        pveGames = uint64(uint256(p.wins) + p.losses + p.ties);
        pvpGames = uint64(uint256(v.attackWins) + v.attackLosses);
        heistRuns = heists.heistRuns(tokenId);
    }

    /**
     * @notice A dealer's LIVE score for a season (informational; settlement uses the frozen score).
     */
    function pendingScore(uint256 seasonId, uint256 tokenId) external view returns (uint256) {
        if (!entered[seasonId][tokenId]) return 0;
        return _scoreFor(seasons[seasonId], seasonId, tokenId);
    }

    /**
     * @notice A dealer's focus points for a season (entry grants the first).
     */
    function focusOf(uint256 seasonId, uint256 tokenId) external view returns (uint32) {
        return focusState[seasonId][tokenId].count;
    }

    /**
     * @notice Vault ETH available for future pots (balance minus ETH reserved for settled seasons).
     */
    function availableVault() public view returns (uint256) {
        uint256 bal = address(this).balance;
        return bal > reservedETH ? bal - reservedETH : 0;
    }

    // =============================================================
    //                     INTERNAL HELPERS
    // =============================================================

    /**
     * @dev Delta-vs-baseline score: qualify iff every per-metric minimum is met, then the score
     *      is the weighted sum across metrics, amplified by the focus multiplier
     *      (BPS + focus x focusBonusBps). Deltas are clamped at zero defensively — counters are
     *      monotonic today, but a module swap via {setContracts} must not brick freezing.
     */
    function _scoreFor(Season storage s, uint256 seasonId, uint256 tokenId) private view returns (uint256) {
        Baseline memory b = baselines[seasonId][tokenId];
        (uint64 pveGames, uint64 pvpGames, uint64 heistRuns) = metricsOf(tokenId);

        uint256 dPve = pveGames > b.pveGames ? pveGames - b.pveGames : 0;
        uint256 dPvp = pvpGames > b.pvpGames ? pvpGames - b.pvpGames : 0;
        uint256 dHeist = heistRuns > b.heistRuns ? heistRuns - b.heistRuns : 0;
        uint256 dTotal = dPve + dPvp + dHeist;

        uint32[4] memory t = s.config.minThresholds;
        if (dPve < t[0] || dPvp < t[1] || dHeist < t[2] || dTotal < t[3]) return 0;

        uint64[4] memory w = s.config.weights;
        uint256 score = w[0] * dPve + w[1] * dPvp + w[2] * dHeist + w[3] * dTotal;

        uint16 bonus = s.config.focusBonusBps;
        if (bonus != 0 && score != 0) {
            score = (score * (BPS + uint256(focusState[seasonId][tokenId].count) * bonus)) / BPS;
        }
        return score;
    }

    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // =============================================================
    //                            ADMIN
    // =============================================================

    /**
     * @notice Update module references; zero-address args are left unchanged.
     * @dev Blocked while a season is in flight — swapping a scored module mid-season could
     *      distort deltas or revert freezing; {cancelSeason} first, then swap.
     */
    function setContracts(address _core, address _nftContract, address _pve, address _pvp, address _heists)
        external
        onlyOwner
    {
        _requireNoSeasonInFlight();
        if (_core != address(0)) core = IDealersCore(_core);
        if (_nftContract != address(0)) nftContract = IERC721Minimal(_nftContract);
        if (_pve != address(0)) pve = IDealersPVE(_pve);
        if (_pvp != address(0)) pvp = IDealersPVP(_pvp);
        if (_heists != address(0)) heists = IDealersHeists(_heists);
        emit ContractsUpdated();
    }

    /**
     * @notice Set the keeper tip paid to whoever calls {settle} (capped at MAX_SETTLE_FEE_BPS of the
     *         vault at settle time). The refund grace window is per-season, baked at {openSeason}.
     */
    function setSettleFee(uint256 _settleFee) external onlyOwner {
        settleFee = _settleFee;
        emit ConfigUpdated();
    }

    /**
     * @notice Owner escape hatch — withdraw spendable vault ETH.
     * @dev Bounded by availableVault() and blocked while a season is in flight: to pull ETH out
     *      from under live entrants the owner must first {cancelSeason}, opening their refunds.
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        _requireNoSeasonInFlight();
        if (amount > availableVault()) revert InsufficientVault();
        _safeTransferETH(to, amount);
        emit EmergencyWithdrawn(to, amount);
    }

    /** @dev Latest season must be terminal (settled or skipped); earlier seasons always are. */
    function _requireNoSeasonInFlight() private view {
        uint256 count = seasonCount;
        if (count != 0) {
            Season storage s = seasons[count - 1];
            if (!s.settled && !s.skipped) revert SeasonInFlight();
        }
    }

    /**
     * @notice Pause entries and check-ins (accrual, freezing, settlement, and claims continue).
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Resume entries.
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
