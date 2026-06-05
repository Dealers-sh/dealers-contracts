// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealersHeists - Interface for the daily push-your-luck heist module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @author Berny0x
 */
interface IDealersHeists {
    // =============================================================
    //                            ENUMS
    // =============================================================

    enum HeistFamily { SUPPLY, CASH }

    enum HeistStatus { NONE, PRE_STAGE, COMMITTED, REVEALED_WIN, BUSTED, CASHED_OUT, ABANDONED, SETBACK }

    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct DifficultyConfig {
        uint256 repGate;   // totalReputation required to enter
        uint96 cashEntry;  // $CASH stake (sizes the drug/$CASH pot)
        bool active;
    }

    /** @dev Per-stage jackpot tuning. minMultBps > 10000 guarantees a payout above stake. */
    struct JackpotStage {
        uint16 triggerPct;  // 0-100, chance the jackpot triggers on a winning stage
        uint32 minMultBps;  // value floor as bps of the ETH add-on (>10000)
        uint32 maxMultBps;  // value ceiling as bps of the ETH add-on
    }

    struct DailyHeist {
        HeistFamily family;
        uint8 difficulty;
        uint8 currentStage;   // 0 = pre-stage, 1..5
        HeistStatus status;
        bool ethJackpot;      // ETH add-on active for this run
        bool jackpotFired;    // one-shot: set once a jackpot has fired this run (at most one per run)
        uint96 entryStake;    // $CASH stake
        uint96 currentPot;    // banked $CASH-equivalent if cashed now
        uint64 commitSeq;     // active randomness sequence (0 if none)
        uint64 commitTimestamp;
        uint64 lastActionTime;
        uint256 tokenId;
    }

    // =============================================================
    //                            EVENTS
    // =============================================================

    event HeistStarted(
        uint256 indexed heistId,
        uint256 indexed tokenId,
        address indexed player,
        HeistFamily family,
        uint8 difficulty,
        bool ethJackpot,
        uint96 cashStake
    );
    event HeistAbandoned(uint256 indexed heistId, uint256 indexed tokenId);
    event StageCommitted(uint256 indexed heistId, uint64 indexed seq, uint256 indexed tokenId, uint8 stage);
    event StageWon(uint256 indexed heistId, uint256 indexed tokenId, uint8 stage, uint96 pot);
    /** @notice A stage went sideways: the run ends and a partial pot is paid out. */
    event HeistSetback(uint256 indexed heistId, uint256 indexed tokenId, uint8 stage, uint96 partialPot);
    event HeistBusted(uint256 indexed heistId, uint256 indexed tokenId, uint8 stage);
    /** @notice A bust escalated to an arrest — the dealer was jailed via the shared Actions path. */
    event HeistArrest(uint256 indexed heistId, uint256 indexed tokenId);
    event HeistCashedOut(uint256 indexed heistId, uint256 indexed tokenId, uint96 pot);
    event HeistForceFinalized(uint256 indexed heistId, uint256 indexed tokenId, uint96 pot);
    event HeistPaid(uint256 indexed heistId, uint256 indexed tokenId, HeistFamily family, uint256 cashPaid);

    event JackpotRolling(uint64 indexed pythSeq, uint256 indexed heistId, uint256 indexed tokenId, uint8 stage);
    event JackpotSkipped(uint256 indexed heistId, uint256 indexed tokenId, uint8 stage);
    event JackpotWon(uint64 indexed pythSeq, uint256 indexed tokenId, uint256 value);
    event JackpotClaimed(uint256 indexed tokenId, address indexed to, uint256 value);
    event JackpotReclaimed(uint64 indexed pythSeq, uint256 indexed tokenId, uint256 escrowReturned);

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /** @notice Lifetime count of heist runs started by a dealer (read by the bank heist for activity weighting). */
    function heistRuns(uint256 tokenId) external view returns (uint32);

    /** @notice The active heist id for a dealer, or 0 if none. */
    function activeHeist(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Read the full state of a heist run.
     * @param heistId The heist run identifier
     * @return The run's DailyHeist record
     */
    function getHeist(uint256 heistId) external view returns (DailyHeist memory);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /**
     * @notice Start a heist run — pays the difficulty's $CASH stake and one daily attempt.
     * @param tokenId The dealer NFT token ID
     * @param family Whether the run pays out drugs (SUPPLY) or $CASH
     * @param difficulty The configured difficulty tier to enter
     * @param ethJackpot Whether to pay the ETH add-on that makes the run jackpot-eligible
     * @return heistId The new run's identifier
     */
    function startHeist(uint256 tokenId, HeistFamily family, uint8 difficulty, bool ethJackpot)
        external
        payable
        returns (uint256 heistId);

    /** @notice Abandon a not-yet-staged run for a full $CASH refund; the ETH add-on and attempt are forfeit. */
    function abandonHeist(uint256 heistId) external;

    /** @notice Commit the next stage. From PRE_STAGE starts stage 1; from REVEALED_WIN this is the "continue" action. */
    function commitStage(uint256 heistId) external;

    /**
     * @notice Resolve a committed stage (anyone may call). Resolves to one of three terminal-or-advance
     *         outcomes — CLEAN (advance/cash), SETBACK (end with partial pot), or BUST (lose all + heat).
     *         A committed stage can never be rewound; an expired commit busts.
     */
    function resolveStage(uint64 seq) external;

    /** @notice Cash out a revealed-win run at its current pot (only from minCashStage onward). */
    function cashOut(uint256 heistId) external;

    /** @notice Force-finalize a revealed-win run left idle past IDLE_TIMEOUT, paying its current pot. */
    function forceFinalize(uint256 heistId) external;

    /** @notice Claim a dealer's owed jackpot winnings to the current NFT owner. */
    function claimJackpot(uint256 tokenId) external;

    /** @notice Return the escrow of a jackpot whose Pyth callback never arrived (after JACKPOT_TIMEOUT). */
    function reclaimStuckJackpot(uint64 pythSeq) external;
}
