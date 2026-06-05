// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealersBankHeist - Interface for the recurring community bank-heist event
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @custom:status CONCEPT — OUT OF AUDIT SCOPE. Paired with DealersBankHeist (not deployed,
 *      ships later via DeployBankHeist.s.sol). Provisional and subject to change before launch.
 *
 * @author Berny0x
 */
interface IDealersBankHeist {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct HeistEvent {
        uint64 closesAt;     // end of the preparation window
        uint32 entryCount;
        uint96 cashSunk;     // total $CASH paid into this event
        bytes32 seed;        // Pyth random seed (0 until callback)
        uint64 pythSeq;      // Pyth request sequence (0 until requested)
        bool seeded;
        bool settled;
        bool skipped;        // terminal: below-min skip OR refund-mode — blocks requestDraw/settle
        uint64 drawRequestedAt; // timestamp requestDraw fired (0 until requested); bounds the stuck-draw refund
        uint32 weightCursor;    // entrants whose draw weight is frozen so far (must reach entryCount before settle)
        uint256 totalWeight;    // sum of frozen weights, accrued during snapshotWeights
    }

    // =============================================================
    //                            EVENTS
    // =============================================================

    event Received(address indexed from, uint256 amount);
    event Entered(uint256 indexed eventId, uint256 indexed tokenId, address indexed player, uint64 activitySnapshot);
    event DrawRequested(uint256 indexed eventId, uint64 indexed pythSeq, address caller);
    event WeightsSnapshotted(uint256 indexed eventId, uint32 cursor, uint256 totalWeight);
    event DrawSeeded(uint256 indexed eventId, uint64 indexed pythSeq);
    event EventSkipped(uint256 indexed eventId, uint32 entryCount);
    event EventSettled(uint256 indexed eventId, uint256 prize, uint256 winnerCount);
    event WinnerSelected(uint256 indexed eventId, uint256 indexed tokenId, uint256 rank, uint256 amount);
    event WinningsClaimed(uint256 indexed tokenId, address indexed to, uint256 amount);
    event Refunded(uint256 indexed eventId, uint256 indexed tokenId, uint256 cash);

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /** @notice The id of the currently open preparation window, derived from elapsed time. */
    function currentEventId() external view returns (uint256);

    /**
     * @notice Read the full state of a heist event.
     * @param eventId The event identifier
     * @return The event's HeistEvent record
     */
    function getEvent(uint256 eventId) external view returns (HeistEvent memory);

    /** @notice Total lifetime PVE + PVP + heist plays for a dealer (the activity metric). */
    function activityOf(uint256 tokenId) external view returns (uint64);

    /** @notice The dealer's activity accrued inside an event window (settlement weight). */
    function eventWeight(uint256 eventId, uint256 tokenId) external view returns (uint256);

    /** @notice Vault ETH available for prizes (balance minus unclaimed winnings). */
    function availableVault() external view returns (uint256);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /** @notice Enter the current cycle by paying the $CASH entry fee (a sink — no attempt, no ETH). */
    function enter(uint256 tokenId) external;

    /** @notice Request the Pyth Entropy draw for a closed event (pays the entropy fee; excess refunded). */
    function requestDraw(uint256 eventId) external payable;

    /**
     * @notice Freeze entrants' draw weights for a requested event, up to `maxCount` per call.
     * @dev Paginated; must cover every entrant before {settle}. Freezing here (not at settle)
     *      stops activity ground out during the Pyth callback wait from inflating a winner's odds.
     * @param eventId The event identifier
     * @param maxCount Max entrants to process this call
     */
    function snapshotWeights(uint256 eventId, uint256 maxCount) external;

    /** @notice Settle a seeded event — picks activity-weighted winners and credits their pull-based winnings. */
    function settle(uint256 eventId) external;

    /** @notice Claim a dealer's credited winnings to the current NFT owner. */
    function claimWinnings(uint256 tokenId) external;

    /** @notice Reclaim the $CASH entry for a skipped or stuck (past refundTimeout) event. */
    function claimRefund(uint256 eventId, uint256 tokenId) external;
}
