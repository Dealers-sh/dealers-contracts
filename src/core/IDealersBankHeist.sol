// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealersBankHeist - Interface for the seasonal community bank-heist distribution
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @author Berny0x
 */
interface IDealersBankHeist {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    /**
     * @dev Index order of the per-season `weights` / `minThresholds` arrays. PVP counts the
     *      attacker side only (anti-wash: score follows who sends the tx). TOTAL is the sum of
     *      the other three, useful mainly as a qualification threshold.
     */
    enum Metric {
        PVE,
        PVP,
        HEISTS,
        TOTAL
    }

    /**
     * @dev Season parameters, locked immutably at {openSeason}.
     */
    struct SeasonConfig {
        uint64 duration; // closesAt = opensAt + duration
        uint96 entryFee; // $CASH sink to enter (no attempt, no ETH)
        uint256 entryRepGate; // totalReputation required to enter (0 = open)
        uint32 minEntrants; // below this at close the season is skipped and refunds open
        uint32 maxEntrants; // bounds the score-freeze loop
        uint16 potBps; // share of availableVault distributed at settle
        uint64 claimWindow; // seconds after settle before unclaimed shares sweep back to the vault
        uint64 refundTimeout; // post-close grace: settle must land within it, after which entries refund
        uint32 freezeWindow; // post-close window in which scores must freeze; bounds the grind gap, must be < refundTimeout
        uint64[4] weights; // score weight per Metric
        uint32[4] minThresholds; // per-Metric minimum delta to qualify (all must be met)
        uint16 focusBonusBps; // per-focus-point score bonus: score x (BPS + focus x this) / BPS (0 disables)
        bool zeroBaseline; // genesis mode: entry keeps a zero baseline so all lifetime play counts
    }

    struct Season {
        SeasonConfig config;
        uint64 opensAt;
        uint64 closesAt;
        uint32 entryCount;
        uint32 scoreCursor; // entrants whose score is frozen so far (must reach entryCount before settle)
        bool settled;
        bool skipped; // terminal: below-min skip, cancel, or refund-mode — blocks freeze/settle
        bool swept; // claim window expired and the unclaimed remainder returned to the vault
        uint64 settledAt; // anchors the claim window
        uint96 cashSunk; // total $CASH paid into this season
        uint256 totalScore; // sum of frozen scores
        uint256 pot; // ETH reserved for this season at settle
        uint256 claimedTotal; // ETH claimed so far (pot - claimedTotal sweeps back after expiry)
    }

    /**
     * @dev A dealer's raw lifetime counters at entry; season score is the delta against these.
     */
    struct Baseline {
        uint64 pveGames; // wins + losses + ties
        uint64 pvpGames; // attackWins + attackLosses (attacker side only)
        uint64 heistRuns;
    }

    /**
     * @dev Daily check-in state, per season per dealer.
     */
    struct Focus {
        uint32 count; // focus points earned (entry grants the first)
        uint32 lastDay; // UTC epoch day of the last check-in (block.timestamp / 1 days)
        uint32 entryDay; // UTC epoch day of entry — denominator anchor for focus-rate UIs (count / daysSinceEntry)
    }

    // =============================================================
    //                            EVENTS
    // =============================================================

    event Received(address indexed from, uint256 amount);
    event SeasonOpened(uint256 indexed seasonId, uint64 opensAt, uint64 closesAt);
    event Entered(uint256 indexed seasonId, uint256 indexed tokenId, address indexed player);
    event CheckedIn(uint256 indexed seasonId, uint256 indexed tokenId, uint32 focus);
    event ScoresFrozen(uint256 indexed seasonId, uint32 cursor, uint256 totalScore);
    event SeasonSkipped(uint256 indexed seasonId, uint32 entryCount);
    event SeasonCancelled(uint256 indexed seasonId);
    event SeasonSettled(uint256 indexed seasonId, uint256 pot, uint256 totalScore);
    event Claimed(uint256 indexed seasonId, uint256 indexed tokenId, address indexed to, uint256 amount);
    event SeasonSwept(uint256 indexed seasonId, uint256 returned);
    event Refunded(uint256 indexed seasonId, uint256 indexed tokenId, uint256 cash);

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Number of seasons ever opened; the latest is seasonCount() - 1.
     */
    function seasonCount() external view returns (uint256);

    /**
     * @notice Read the full state of a season.
     */
    function getSeason(uint256 seasonId) external view returns (Season memory);

    /**
     * @notice Entrant token ID at `index` in entry order (indices [0, entryCount)).
     */
    function entryAt(uint256 seasonId, uint256 index) external view returns (uint256);

    /**
     * @notice Whether a dealer has entered a season.
     */
    function entered(uint256 seasonId, uint256 tokenId) external view returns (bool);

    /**
     * @notice A dealer's raw daily-focus state for a season (see {Focus}).
     */
    function focusState(uint256 seasonId, uint256 tokenId)
        external
        view
        returns (uint32 count, uint32 lastDay, uint32 entryDay);

    /**
     * @notice Whether a dealer's payout for a settled season has been claimed.
     */
    function claimed(uint256 seasonId, uint256 tokenId) external view returns (bool);

    /**
     * @notice Whether a dealer's $CASH entry for a season has been refunded.
     */
    function refunded(uint256 seasonId, uint256 tokenId) external view returns (bool);

    /**
     * @notice ETH tip paid to the {settle} caller, capped at 1% of the available vault.
     */
    function settleFee() external view returns (uint256);

    /**
     * @notice A dealer's live lifetime counters for the three scored games.
     */
    function metricsOf(uint256 tokenId) external view returns (uint64 pveGames, uint64 pvpGames, uint64 heistRuns);

    /**
     * @notice A dealer's LIVE score for a season (informational; settlement uses the frozen score).
     */
    function pendingScore(uint256 seasonId, uint256 tokenId) external view returns (uint256);

    /**
     * @notice A dealer's frozen settlement score (0 until {freezeScores} covers them).
     */
    function scoreOf(uint256 seasonId, uint256 tokenId) external view returns (uint256);

    /**
     * @notice A dealer's focus points for a season (entry grants the first).
     */
    function focusOf(uint256 seasonId, uint256 tokenId) external view returns (uint32);

    /**
     * @notice Vault ETH available for future pots (balance minus ETH reserved for settled seasons).
     */
    function availableVault() external view returns (uint256);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /**
     * @notice Enter the latest season by paying its $CASH entry fee; snapshots the dealer's
     *         counter baseline so only activity from this moment on scores (unless the season
     *         is zeroBaseline, in which case all lifetime play counts). Jailed dealers can't
     *         join the crew.
     */
    function enter(uint256 tokenId) external;

    /**
     * @notice Daily focus check-in for the latest season — one per UTC day (resets 00:00 UTC),
     *         no play required. Each point multiplies the final score by the season's
     *         focusBonusBps. Jailed dealers can't check in with the crew.
     */
    function checkIn(uint256 tokenId) external;

    /**
     * @notice Freeze entrants' scores for a closed season, up to `maxCount` per call.
     * @dev Paginated in entry order; must cover every entrant before {settle}. A
     *      below-minEntrants season is skipped here, enabling refunds. Anyone may call, but only
     *      within the post-close freezeWindow — that bounds the close-to-freeze grind gap so no
     *      entrant can lock rivals early and keep inflating their own live score.
     * @param seasonId The season identifier
     * @param maxCount Max entrants to process this call
     */
    function freezeScores(uint256 seasonId, uint256 maxCount) external;

    /**
     * @notice Settle a fully-frozen season: reserve potBps of the available vault as the pot.
     */
    function settle(uint256 seasonId) external;

    /**
     * @notice Claim a dealer's pro-rata share (score / totalScore x pot) to the current NFT
     *         owner.
     * @dev Permissionless — batch distribution is anyone multicalling claims.
     */
    function claim(uint256 seasonId, uint256 tokenId) external;

    /**
     * @notice Return a settled season's unclaimed remainder to the vault after the claim window.
     */
    function sweepExpired(uint256 seasonId) external;

    /**
     * @notice Reclaim the $CASH entry for a season that will never pay out (skipped, cancelled,
     *         or abandoned past the refund timeout).
     */
    function claimRefund(uint256 seasonId, uint256 tokenId) external;
}
