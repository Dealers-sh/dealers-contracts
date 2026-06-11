// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDealersHeists} from "./IDealersHeists.sol";
import {IDealersCore} from "./IDealersCore.sol";
import {IDrugRegistry} from "../utils/IDrugRegistry.sol";
import {IAreaRegistry} from "../utils/IAreaRegistry.sol";
import {IERC721Minimal} from "../utils/IERC721Minimal.sol";
import {IDealersRandomness} from "../utils/IDealersRandomness.sol";
import {IDealersPaymentHandler} from "../utils/IDealersPaymentHandler.sol";
import {IActionsArrest} from "../utils/IActionsArrest.sol";
import {IEntropyConsumer} from "../utils/pyth/IEntropyConsumer.sol";
import {IEntropyV2} from "../utils/pyth/IEntropyV2.sol";

/**
 * @title DealersHeists - Daily push-your-luck heist module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Solo five-stage push-your-luck runs. Each run pays its difficulty's $CASH stake
 *      (which sizes the drug/$CASH pot) and costs one daily attempt. Win/loss per stage
 *      uses the in-house commit-reveal randomness. An optional 0.001 ETH add-on makes a
 *      run jackpot-eligible: each cleared stage rolls for the jackpot until the first one
 *      fires (at most one per run), and Pyth Entropy decides the value within the stage's
 *      configured band. Surfaced to players as a "compensation" — the shipped config pays a
 *      partial refund (0.7-0.9x the add-on) frequently rather than a rare multiple, but the
 *      band is config-driven (minMultBps may sit above or below the add-on).
 *
 *      Standalone module — integrates with existing contracts only through their public
 *      interfaces and the authorized-contract registration pattern. No existing source edits.
 * @author Berny0x
 */
contract DealersHeists is IDealersHeists, IEntropyConsumer, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersCore public core;
    IERC721Minimal public nftContract;
    IDealersRandomness public randomness;
    IDealersPaymentHandler public paymentHandler;
    IDrugRegistry public drugRegistry;
    IEntropyV2 public entropy;
    IActionsArrest public actions; // optional: when set, a bust may roll for arrest (heat-scaled)

    bool public paused;

    uint64 public constant IDLE_TIMEOUT = 24 hours;

    /**
     * @dev Grace period after a Pyth jackpot request before its escrow can be reclaimed if no callback arrives.
     */
    uint64 public constant JACKPOT_TIMEOUT = 24 hours;
    uint16 internal constant BPS = 10000;
    uint8 internal constant STAGES = 5;
    uint8 internal constant DIFFICULTIES = 3;

    // --- config ---
    mapping(uint8 difficulty => DifficultyConfig) public difficultyConfigs;
    uint8[STAGES] public stageWinOdds; // CLEAN (advance) chance per stage (0-100)
    uint8[STAGES] public stageSetbackOdds; // SETBACK band width per stage; BUST = 100 - clean - setback
    uint16[STAGES] public stageSetbackKeepBps; // fraction of the stage pot kept on a setback
    uint32[STAGES] public stagePotMinBps; // pot multiplier range (bps of stake) — rolled per reveal
    uint32[STAGES] public stagePotMaxBps;
    uint16[STAGES] public stageRepReward; // small Rep granted on payout at this stage (0 on bust)
    uint8[3][STAGES] public supplyMix; // [common%, uncommon%, rare%] per stage
    JackpotStage[STAGES] public jackpotConfig;
    uint96 public ethAddOn = 0.001 ether;
    uint16 public jackpotReserveBps = 4000; // share of ETH add-on kept as jackpot reserve
    uint8 public minCashStage = 2; // earliest stage a player may voluntarily cash out (stage 1 = prep)
    uint16 public bustRepPenalty = 3; // small Rep loss when a run busts (floors at 0 in Core)

    // --- heists ---
    mapping(uint256 heistId => DailyHeist) public dailyHeists;
    mapping(uint256 tokenId => uint256 heistId) public activeHeist;
    mapping(uint256 tokenId => HeistStats) public dealerHeistStats;
    mapping(uint64 seq => uint256 heistId) public heistOfSeq;
    uint256 public nextHeistId = 1;

    // --- jackpot ETH accounting (all wei held by this contract) ---
    uint256 public jackpotReserve; // free reserve available to back future jackpots
    uint256 public escrowedJackpot; // max payouts reserved for in-flight Pyth requests
    mapping(uint256 tokenId => uint256) public jackpotOwed; // claimable winnings
    uint256 public totalJackpotOwed; // running sum of jackpotOwed, for the backedEth() solvency view

    struct PendingJackpot {
        uint256 tokenId;
        uint96 maxValue; // escrowed ceiling for this request
        uint8 stage;
        uint64 requestedAt; // timestamp of the Pyth request, for the stuck-callback reclaim
    }

    mapping(uint64 pythSeq => PendingJackpot) public pendingJackpots;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event ReserveFunded(address indexed from, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event ContractsUpdated();
    event DifficultyConfigUpdated(uint8 indexed difficulty, DifficultyConfig config);
    event StageTablesUpdated();
    event JackpotConfigUpdated();
    event Paused(address account);
    event Unpaused(address account);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error ContractPaused();
    error NotDealerOwner();
    error DealerNotInitialized();
    error DealerInJail();
    error DealerInSafeHouse();
    error HeistActive();
    error InvalidDifficulty();
    error RepTooLow();
    error InvalidEthAmount();
    error InvalidHeistState();
    error CannotCashYet();
    error UnknownSeq();
    error NotIdleYet();
    error NothingToClaim();
    error InvalidConfig();
    error InvalidAddress();
    error InsufficientReserve();
    error TransferFailed();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        address _core,
        address _nftContract,
        address _randomness,
        address _paymentHandler,
        address _drugRegistry,
        address _entropy
    ) {
        _initializeOwner(msg.sender);
        core = IDealersCore(_core);
        nftContract = IERC721Minimal(_nftContract);
        randomness = IDealersRandomness(_randomness);
        paymentHandler = IDealersPaymentHandler(_paymentHandler);
        drugRegistry = IDrugRegistry(_drugRegistry);
        entropy = IEntropyV2(_entropy);

        stageWinOdds = [uint8(72), 62, 52, 42, 32];
        stageSetbackOdds = [uint8(20), 28, 33, 38, 40]; // bust = 8 / 10 / 15 / 20 / 28
        stageSetbackKeepBps = [uint16(5000), 4500, 4000, 3500, 3000];
        // Pot multiplier rolled within [min,max] each reveal. Stage 1 ~1.0-1.4x (prep, not cashable).
        stagePotMinBps = [uint32(10000), 18000, 30000, 52000, 100000];
        stagePotMaxBps = [uint32(14000), 28000, 46000, 78000, 160000];
        stageRepReward = [uint16(0), 2, 4, 7, 12]; // prep gives none; deeper = more (PVP-ish, << PVE)
        supplyMix =
            [[uint8(100), 0, 0], [uint8(70), 30, 0], [uint8(40), 60, 0], [uint8(10), 50, 40], [uint8(0), 0, 100]];
        // Compensation model: a frequent partial-refund (0.7-0.9x the add-on), not a rare windfall.
        // 25% per cleared stage keeps the per-run fire rate ~1-in-3; the 40% reserve cut self-funds it.
        jackpotConfig[0] = JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jackpotConfig[1] = JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jackpotConfig[2] = JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jackpotConfig[3] = JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
        jackpotConfig[4] = JackpotStage({triggerPct: 25, minMultBps: 7000, maxMultBps: 9000});
    }

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(core) == address(0) || address(nftContract) == address(0) || address(randomness) == address(0)
                || address(paymentHandler) == address(0) || address(drugRegistry) == address(0)
                || address(entropy) == address(0)
        ) revert ContractNotSet();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyDealerOwner(uint256 tokenId) {
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();
        _;
    }

    // =============================================================
    //                        ENTRY / EXIT
    // =============================================================

    /**
     * @notice Start a heist run — debits the difficulty's $CASH stake and one daily attempt.
     * @dev The optional ETH add-on must equal {ethAddOn} exactly: jackpotReserveBps is kept as
     *      jackpot reserve and the remainder is routed to the PaymentHandler as a marketplace fee.
     * @param tokenId The dealer NFT token ID
     * @param family Whether the run pays out drugs (SUPPLY) or $CASH
     * @param difficulty The configured difficulty tier to enter
     * @param ethJackpot Whether to pay the ETH add-on that makes the run jackpot-eligible
     * @return heistId The new run's identifier
     */
    function startHeist(uint256 tokenId, HeistFamily family, uint8 difficulty, bool ethJackpot)
        external
        payable
        nonReentrant
        whenNotPaused
        contractsSet
        onlyDealerOwner(tokenId)
        returns (uint256 heistId)
    {
        if (activeHeist[tokenId] != 0) revert HeistActive();

        DifficultyConfig memory cfg = difficultyConfigs[difficulty];
        if (!cfg.active) revert InvalidDifficulty();

        IDealersCore.GameState memory s = core.getGameState(tokenId);
        if (!s.isInitialized) revert DealerNotInitialized();
        if (s.isJailed) revert DealerInJail();
        if (s.isInSafeHouse) revert DealerInSafeHouse();
        if (s.totalReputation < cfg.repGate) revert RepTooLow();

        if (ethJackpot) {
            if (msg.value != ethAddOn) revert InvalidEthAmount();
            uint256 toReserve = (msg.value * jackpotReserveBps) / BPS;
            jackpotReserve += toReserve;
            uint256 toFee = msg.value - toReserve;
            paymentHandler.processMarketplaceFee{value: toFee}(msg.sender, toFee);
        } else {
            if (msg.value != 0) revert InvalidEthAmount();
        }

        // Atomic: consume one attempt and debit the $CASH stake (reverts on either shortfall).
        IDealersCore.GameOutcome memory o;
        o.useAttempt = true;
        o.cashDelta = -int256(uint256(cfg.cashEntry));
        core.applyGameOutcome(tokenId, o);

        heistId = nextHeistId++;
        dailyHeists[heistId] = DailyHeist({
            family: family,
            difficulty: difficulty,
            currentStage: 0,
            status: HeistStatus.PRE_STAGE,
            ethJackpot: ethJackpot,
            jackpotFired: false,
            entryStake: cfg.cashEntry,
            currentPot: 0,
            commitSeq: 0,
            commitTimestamp: 0,
            lastActionTime: uint64(block.timestamp),
            tokenId: tokenId
        });
        activeHeist[tokenId] = heistId;
        unchecked {
            dealerHeistStats[tokenId].runs++;
        }

        emit HeistStarted(heistId, tokenId, msg.sender, family, difficulty, ethJackpot, cfg.cashEntry);
    }

    /**
     * @notice Abandon a not-yet-staged run for a full $CASH refund.
     * @dev Only valid in PRE_STAGE; the ETH add-on and the consumed attempt are forfeit.
     */
    function abandonHeist(uint256 heistId) external nonReentrant {
        DailyHeist storage h = dailyHeists[heistId];
        if (h.status != HeistStatus.PRE_STAGE) revert InvalidHeistState();
        if (nftContract.ownerOf(h.tokenId) != msg.sender) revert NotDealerOwner();

        core.addCash(h.tokenId, h.entryStake); // full $CASH refund; ETH add-on and attempt are forfeit
        h.status = HeistStatus.ABANDONED;
        delete activeHeist[h.tokenId];
        emit HeistAbandoned(heistId, h.tokenId);
    }

    // =============================================================
    //                        STAGE FLOW
    // =============================================================

    /**
     * @notice Commit the next stage — opens a commit-reveal round to be settled by {resolveStage}.
     * @dev Valid from PRE_STAGE (starts stage 1) or REVEALED_WIN (the "continue, push deeper" action).
     *      A jailed dealer pauses the run; it can resume after release.
     */
    function commitStage(uint256 heistId) external nonReentrant whenNotPaused contractsSet {
        DailyHeist storage h = dailyHeists[heistId];
        if (h.status != HeistStatus.PRE_STAGE && h.status != HeistStatus.REVEALED_WIN) revert InvalidHeistState();
        if (nftContract.ownerOf(h.tokenId) != msg.sender) revert NotDealerOwner();

        IDealersCore.GameState memory s = core.getGameState(h.tokenId);
        if (s.isJailed) revert DealerInJail(); // jail pauses the run; resume after release

        unchecked {
            h.currentStage++;
        }
        uint64 seq = randomness.commit();
        h.commitSeq = seq;
        h.commitTimestamp = uint64(block.timestamp);
        h.lastActionTime = uint64(block.timestamp);
        h.status = HeistStatus.COMMITTED;
        heistOfSeq[seq] = heistId;

        emit StageCommitted(heistId, seq, h.tokenId, h.currentStage);
    }

    /**
     * @notice Resolve a committed stage (anyone may call). Settles to CLEAN (pot grows, advance or
     *         auto-pay on the final stage), SETBACK (run ends with a partial pot), or BUST (lose all).
     * @dev A committed stage only ever resolves to win or bust — it can never be rewound. A missed
     *      reveal window busts the run (same terminal-loss rule as PVE/PVP expiry), but as an infra
     *      timeout it skips the arrest roll: bust with heat/rep, never "caught at the scene".
     * @param seq The randomness sequence returned by the matching {commitStage}
     */
    function resolveStage(uint64 seq) external nonReentrant {
        uint256 heistId = heistOfSeq[seq];
        if (heistId == 0) revert UnknownSeq();
        DailyHeist storage h = dailyHeists[heistId];
        if (h.status != HeistStatus.COMMITTED) revert InvalidHeistState();
        delete heistOfSeq[seq];

        // A missed reveal window busts the run — same terminal-loss rule as PVE/PVP expiry.
        // A committed stage only ever resolves to win or bust; it can never be rewound.
        // Expiry is an infra timeout, not "caught at the scene": bust with heat/rep, no arrest roll.
        if (randomness.isExpired(seq)) {
            _bust(heistId, h, 0, false);
            return;
        }

        uint256 rand = randomness.reveal(seq);
        h.commitSeq = 0;
        uint8 stage = h.currentStage;

        uint256 roll = rand % 100;
        uint256 cleanOdds = stageWinOdds[stage - 1];
        uint256 stagePot = (uint256(h.entryStake) * _rollMult(stage, rand)) / BPS;

        if (roll < cleanOdds) {
            // CLEAN — pot grows; jackpot eligible; advance (or auto-pay on the final stage).
            h.currentPot = uint96(stagePot);
            h.lastActionTime = uint64(block.timestamp);
            unchecked {
                dealerHeistStats[h.tokenId].stagesCleared++;
            }

            if (h.ethJackpot && !h.jackpotFired) {
                JackpotStage memory jc = jackpotConfig[stage - 1];
                if ((rand >> 16) % 100 < jc.triggerPct) {
                    if (_fireJackpot(heistId, h.tokenId, stage, jc)) h.jackpotFired = true;
                }
            }

            if (stage >= STAGES) {
                _finalizePayout(heistId, h);
            } else {
                h.status = HeistStatus.REVEALED_WIN;
                emit StageWon(heistId, h.tokenId, stage, h.currentPot);
            }
        } else if (roll < cleanOdds + stageSetbackOdds[stage - 1]) {
            // SETBACK — the run ends here with a partial pot. No jackpot, no heat.
            _setback(heistId, h, stage, uint96((stagePot * stageSetbackKeepBps[stage - 1]) / BPS));
        } else {
            // BUST — lose everything; heat + rep hit, and a heat-scaled arrest roll.
            _bust(heistId, h, rand, true);
        }
    }

    /**
     * @dev Pot multiplier for a stage, rolled uniformly in [min,max] bps from an unused slice of the reveal.
     */
    function _rollMult(uint8 stage, uint256 rand) private view returns (uint256) {
        uint256 lo = stagePotMinBps[stage - 1];
        uint256 hi = stagePotMaxBps[stage - 1];
        if (hi <= lo) return lo;
        return lo + ((rand >> 32) % (hi - lo + 1));
    }

    /**
     * @notice Voluntarily cash out a revealed-win run at its current pot.
     * @dev Only allowed from {minCashStage} onward (stage 1 is prep — there is nothing to bank yet).
     */
    function cashOut(uint256 heistId) external nonReentrant {
        DailyHeist storage h = dailyHeists[heistId];
        if (h.status != HeistStatus.REVEALED_WIN) revert InvalidHeistState();
        if (h.currentStage < minCashStage) revert CannotCashYet(); // stage 1 is prep — push on
        if (nftContract.ownerOf(h.tokenId) != msg.sender) revert NotDealerOwner();
        _finalizePayout(heistId, h);
    }

    /**
     * @notice Permissionless finalize of a revealed-win run left idle past {IDLE_TIMEOUT}, paying its pot.
     * @dev Prevents winnings being stranded if a player walks away without cashing out.
     */
    function forceFinalize(uint256 heistId) external nonReentrant {
        DailyHeist storage h = dailyHeists[heistId];
        if (h.status != HeistStatus.REVEALED_WIN) revert InvalidHeistState();
        if (block.timestamp < h.lastActionTime + IDLE_TIMEOUT) revert NotIdleYet();
        _finalizePayout(heistId, h);
        emit HeistForceFinalized(heistId, h.tokenId, h.currentPot);
    }

    // =============================================================
    //                        JACKPOT (ETH, Pyth)
    // =============================================================

    /**
     * @dev Returns true only when a Pyth request is actually made; a reserve-skip returns false so the run stays jackpot-eligible for a later stage.
     */
    function _fireJackpot(uint256 heistId, uint256 tokenId, uint8 stage, JackpotStage memory jc)
        private
        returns (bool)
    {
        uint256 maxVal = (uint256(ethAddOn) * jc.maxMultBps) / BPS;
        uint256 fee = entropy.getFeeV2();
        if (jackpotReserve < maxVal + fee) {
            emit JackpotSkipped(heistId, tokenId, stage);
            return false;
        }
        jackpotReserve -= (maxVal + fee);
        escrowedJackpot += maxVal;

        uint64 pseq = entropy.requestV2{value: fee}();
        pendingJackpots[pseq] = PendingJackpot({
            tokenId: tokenId,
            maxValue: uint96(maxVal),
            stage: stage,
            requestedAt: uint64(block.timestamp)
        });
        emit JackpotRolling(pseq, heistId, tokenId, stage);
        return true;
    }

    /**
     * @inheritdoc IEntropyConsumer
     */
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    /**
     * @dev Pyth callback. Kept minimal & pull-based: credits owed winnings, no transfer.
     */
    function entropyCallback(uint64 sequence, address, bytes32 randomNumber) internal override {
        PendingJackpot memory p = pendingJackpots[sequence];
        if (p.tokenId == 0) return;
        delete pendingJackpots[sequence];

        JackpotStage memory jc = jackpotConfig[p.stage - 1];
        uint256 range = uint256(jc.maxMultBps) - uint256(jc.minMultBps);
        uint256 mult = uint256(jc.minMultBps) + (range == 0 ? 0 : uint256(randomNumber) % (range + 1));
        uint256 value = (uint256(ethAddOn) * mult) / BPS;
        if (value > p.maxValue) value = p.maxValue; // invariant guard

        escrowedJackpot -= p.maxValue;
        jackpotReserve += (uint256(p.maxValue) - value); // return the unused escrow
        jackpotOwed[p.tokenId] += value;
        totalJackpotOwed += value;
        unchecked {
            dealerHeistStats[p.tokenId].jackpotsWon++;
        }

        emit JackpotWon(sequence, p.tokenId, value);
    }

    /**
     * @notice Claim a dealer's owed jackpot winnings to the current NFT owner (pull-based).
     */
    function claimJackpot(uint256 tokenId) external nonReentrant {
        uint256 owed = jackpotOwed[tokenId];
        if (owed == 0) revert NothingToClaim();
        jackpotOwed[tokenId] = 0;
        totalJackpotOwed -= owed;
        address to = nftContract.ownerOf(tokenId);
        _safeTransferETH(to, owed);
        emit JackpotClaimed(tokenId, to, owed);
    }

    /**
     * @notice Permissionless rescue for a jackpot whose Pyth callback never arrived. After
     *         JACKPOT_TIMEOUT the escrowed ceiling is returned to the free reserve.
     * @dev A late callback for a reclaimed sequence is a no-op (entropyCallback ignores tokenId 0).
     */
    function reclaimStuckJackpot(uint64 pythSeq) external nonReentrant {
        PendingJackpot memory p = pendingJackpots[pythSeq];
        if (p.tokenId == 0) revert UnknownSeq();
        if (block.timestamp < uint256(p.requestedAt) + JACKPOT_TIMEOUT) revert NotIdleYet();
        delete pendingJackpots[pythSeq];
        escrowedJackpot -= p.maxValue;
        jackpotReserve += p.maxValue;
        emit JackpotReclaimed(pythSeq, p.tokenId, p.maxValue);
    }

    // =============================================================
    //                     INTERNAL HELPERS
    // =============================================================

    /**
     * @dev End a busted run. Effects are settled before any external (trusted) core/actions call.
     *      `allowArrest` is false for expiry/timeout busts (infra, not "caught"). When arrest is
     *      enabled and the heat-scaled jail check hits, the shared Actions path jails the dealer and
     *      applies ITS OWN heat + rep loss + drug confiscation — so we skip the plain bust penalties
     *      to avoid double-dipping. Otherwise the bust costs +1 heat and a small Rep hit (Rep floors
     *      at 0 in Core, never reverts, so the slot is always freed).
     */
    function _bust(uint256 heistId, DailyHeist storage h, uint256 rand, bool allowArrest) private {
        uint256 tokenId = h.tokenId;
        h.currentPot = 0;
        h.commitSeq = 0;
        h.status = HeistStatus.BUSTED;
        h.lastActionTime = uint64(block.timestamp);
        delete activeHeist[tokenId];
        unchecked {
            dealerHeistStats[tokenId].busts++;
        }

        if (allowArrest && address(actions) != address(0) && core.rollJailCheck(tokenId, (rand >> 64) & 0xFFFF)) {
            actions.arrest(tokenId, (rand >> 96) & 0xFFFF);
            emit HeistArrest(heistId, tokenId);
        } else {
            IDealersCore.GameOutcome memory o;
            o.incrementHeat = true;
            o.repDelta = -int256(uint256(bustRepPenalty));
            core.applyGameOutcome(tokenId, o);
        }

        emit HeistBusted(heistId, tokenId, h.currentStage);
    }

    /**
     * @dev A failed-but-survived stage: end the run, pay a partial pot, raise heat. No Rep.
     *      Only a fully clean cash-out/getaway leaves no trail; any messy exit (setback/bust) raises heat.
     */
    function _setback(uint256 heistId, DailyHeist storage h, uint8 stage, uint96 partialPot) private {
        uint256 tokenId = h.tokenId;
        h.currentPot = partialPot;
        h.commitSeq = 0;
        h.status = HeistStatus.SETBACK;
        h.lastActionTime = uint64(block.timestamp);
        delete activeHeist[tokenId];
        unchecked {
            dealerHeistStats[tokenId].setbacks++;
        }
        uint256 cashPaid = _payout(h);
        IDealersCore.GameOutcome memory o;
        o.incrementHeat = true;
        core.applyGameOutcome(tokenId, o);
        emit HeistSetback(heistId, tokenId, stage, partialPot);
        emit HeistPaid(heistId, tokenId, h.family, cashPaid);
    }

    function _finalizePayout(uint256 heistId, DailyHeist storage h) private {
        uint256 tokenId = h.tokenId;
        uint256 cashPaid = _payout(h);
        _grantRep(tokenId, stageRepReward[h.currentStage - 1]);
        h.status = HeistStatus.CASHED_OUT;
        delete activeHeist[tokenId];
        unchecked {
            dealerHeistStats[tokenId].cashOuts++;
        }
        emit HeistCashedOut(heistId, tokenId, h.currentPot);
        emit HeistPaid(heistId, tokenId, h.family, cashPaid);
    }

    /**
     * @dev Small Rep grant on a successful payout. Heists pay far less Rep than PVE so PVE stays
     *      the primary growth path; this is a modest, PVP-scale bonus on top of the cash/drug haul.
     */
    function _grantRep(uint256 tokenId, uint256 rep) private {
        if (rep != 0) core.updateReputation(tokenId, int256(rep));
    }

    function _payout(DailyHeist storage h) private returns (uint256 cashPaid) {
        IDealersCore.GameState memory s = core.getGameState(h.tokenId);
        uint256 pot = h.currentPot;
        if (h.family == HeistFamily.CASH) {
            uint256 amt = (pot * _boostMult(s.boostActive, s.cashMultiplier)) / 100;
            core.addCash(h.tokenId, amt);
            cashPaid = amt;
        } else {
            uint256 amt = (pot * _boostMult(s.boostActive, s.drugMultiplier)) / 100;
            _allocateDrugs(h.tokenId, amt, h.currentStage, s.currentArea);
            cashPaid = amt;
        }
    }

    function _boostMult(bool active, uint8 mult) private pure returns (uint256) {
        if (!active || mult < 100) return 100;
        return mult;
    }

    /**
     * @dev Supply Run payout: convert the pot to drug units by the per-stage rarity mix, drawing
     *      **only from drugs sold in the dealer's current area** (you rob the local supply). A rarity
     *      the area doesn't deal — or division dust — settles as residual $CASH.
     */
    function _allocateDrugs(uint256 tokenId, uint256 potCashEquiv, uint8 stage, uint8 area) private {
        uint8[3] memory mix = supplyMix[stage - 1];
        uint256[] memory areaDrugIds = core.areaRegistry().getAreaDrugIds(area);
        uint256 seed = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), tokenId, stage)));
        uint256 residualCash;

        for (uint256 r = 0; r < 3;) {
            uint8 pct = mix[r];
            if (pct != 0) {
                uint256 bucketValue = (potCashEquiv * pct) / 100;
                if (bucketValue != 0) {
                    uint256 drugId = _pickAreaDrugByRarity(areaDrugIds, IDrugRegistry.DrugRarity(r), seed, r);
                    uint256 price = drugId == 0 ? 0 : drugRegistry.getDrugBaseCashValue(drugId);
                    uint256 units = price == 0 ? 0 : bucketValue / price;
                    if (units != 0) {
                        core.updateDrugBalance(tokenId, drugId, int256(units));
                        residualCash += bucketValue - (units * price);
                    } else {
                        residualCash += bucketValue; // area lacks this rarity (or no whole unit) → pay $CASH
                    }
                }
            }
            unchecked {
                ++r;
            }
        }

        if (residualCash != 0) core.addCash(tokenId, residualCash);
    }

    /**
     * @dev Pick one drug of `rarity` that the dealer's current area deals; 0 if the area has none.
     */
    function _pickAreaDrugByRarity(
        uint256[] memory areaDrugIds,
        IDrugRegistry.DrugRarity rarity,
        uint256 seed,
        uint256 salt
    ) private view returns (uint256) {
        uint256 count;
        uint256[] memory matched = new uint256[](areaDrugIds.length);
        for (uint256 i = 0; i < areaDrugIds.length;) {
            uint256 id = areaDrugIds[i];
            if (id != 0 && drugRegistry.getDrugRarity(id) == rarity) {
                matched[count] = id;
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (count == 0) return 0;
        return matched[uint256(keccak256(abi.encodePacked(seed, salt))) % count];
    }

    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    function getHeist(uint256 heistId) external view returns (DailyHeist memory) {
        return dailyHeists[heistId];
    }

    /**
     * @notice Lifetime heist counters for a dealer (runs, cleared stages, cashouts, setbacks, busts, jackpots).
     */
    function getDealerHeistStats(uint256 tokenId) external view returns (HeistStats memory) {
        return dealerHeistStats[tokenId];
    }

    /**
     * @notice Lifetime run count — thin view over {dealerHeistStats} (kept for the bank heist's activity weighting).
     */
    function heistRuns(uint256 tokenId) external view returns (uint32) {
        return dealerHeistStats[tokenId].runs;
    }

    /**
     * @notice ETH that must be backed by contract balance (reserve + in-flight + owed jackpots).
     */
    function backedEth() external view returns (uint256) {
        return jackpotReserve + escrowedJackpot + totalJackpotOwed;
    }

    // =============================================================
    //                        ADMIN
    // =============================================================

    function fundReserve() external payable onlyOwner {
        jackpotReserve += msg.value;
        emit ReserveFunded(msg.sender, msg.value);
    }

    /**
     * @dev Owner may pull only the free reserve, never escrowed or owed jackpot ETH.
     */
    function withdrawReserve(address to, uint256 amount) external onlyOwner nonReentrant {
        if (amount > jackpotReserve) revert InsufficientReserve();
        jackpotReserve -= amount;
        _safeTransferETH(to, amount);
        emit ReserveWithdrawn(to, amount);
    }

    function setDifficultyConfig(uint8 difficulty, DifficultyConfig calldata cfg) external onlyOwner {
        if (difficulty >= DIFFICULTIES) revert InvalidConfig();
        difficultyConfigs[difficulty] = cfg;
        emit DifficultyConfigUpdated(difficulty, cfg);
    }

    function setStageOdds(
        uint8[STAGES] calldata cleanOdds,
        uint8[STAGES] calldata setbackOdds,
        uint16[STAGES] calldata setbackKeepBps
    ) external onlyOwner {
        for (uint256 i = 0; i < STAGES;) {
            if (uint256(cleanOdds[i]) + setbackOdds[i] > 100) revert InvalidConfig(); // bust = remainder
            if (setbackKeepBps[i] > BPS) revert InvalidConfig();
            unchecked {
                ++i;
            }
        }
        stageWinOdds = cleanOdds;
        stageSetbackOdds = setbackOdds;
        stageSetbackKeepBps = setbackKeepBps;
        emit StageTablesUpdated();
    }

    function setStageRewards(
        uint32[STAGES] calldata potMinBps,
        uint32[STAGES] calldata potMaxBps,
        uint16[STAGES] calldata repReward
    ) external onlyOwner {
        for (uint256 i = 0; i < STAGES;) {
            if (potMaxBps[i] < potMinBps[i]) revert InvalidConfig();
            unchecked {
                ++i;
            }
        }
        stagePotMinBps = potMinBps;
        stagePotMaxBps = potMaxBps;
        stageRepReward = repReward;
        emit StageTablesUpdated();
    }

    function setSupplyMix(uint8[3][STAGES] calldata mix) external onlyOwner {
        for (uint256 i = 0; i < STAGES;) {
            if (uint256(mix[i][0]) + mix[i][1] + mix[i][2] != 100) revert InvalidConfig();
            unchecked {
                ++i;
            }
        }
        supplyMix = mix;
        emit StageTablesUpdated();
    }

    function setMinCashStage(uint8 stage) external onlyOwner {
        if (stage == 0 || stage > STAGES) revert InvalidConfig();
        minCashStage = stage;
    }

    /**
     * @notice Set (or clear, with address(0)) the Actions contract used to roll arrests on bust.
     */
    function setActions(address _actions) external onlyOwner {
        actions = IActionsArrest(_actions);
        emit ContractsUpdated();
    }

    function setBustRepPenalty(uint16 penalty) external onlyOwner {
        bustRepPenalty = penalty;
    }

    function setJackpotConfig(JackpotStage[STAGES] calldata cfg) external onlyOwner {
        for (uint256 i = 0; i < STAGES;) {
            if (cfg[i].triggerPct > 100 || cfg[i].minMultBps == 0 || cfg[i].maxMultBps < cfg[i].minMultBps) {
                revert InvalidConfig();
            }
            jackpotConfig[i] = cfg[i];
            unchecked {
                ++i;
            }
        }
        emit JackpotConfigUpdated();
    }

    function setEthAddOn(uint96 amount) external onlyOwner {
        if (amount == 0) revert InvalidConfig();
        ethAddOn = amount;
    }

    function setJackpotReserveBps(uint16 bps) external onlyOwner {
        if (bps > BPS) revert InvalidConfig();
        jackpotReserveBps = bps;
    }

    function setContracts(
        address _core,
        address _nftContract,
        address _randomness,
        address _paymentHandler,
        address _drugRegistry,
        address _entropy
    ) external onlyOwner {
        if (_core != address(0)) core = IDealersCore(_core);
        if (_nftContract != address(0)) nftContract = IERC721Minimal(_nftContract);
        if (_randomness != address(0)) randomness = IDealersRandomness(_randomness);
        if (_paymentHandler != address(0)) paymentHandler = IDealersPaymentHandler(_paymentHandler);
        if (_drugRegistry != address(0)) drugRegistry = IDrugRegistry(_drugRegistry);
        if (_entropy != address(0)) entropy = IEntropyV2(_entropy);
        emit ContractsUpdated();
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
