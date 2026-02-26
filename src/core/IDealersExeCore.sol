// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDealersExeCore - Interface for DealersExeCore
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for all game modules to interact with core state.
 *      Drug and Area configuration has been moved to separate registries.
 * @author Dealers.Exe Team
 */
interface IDealersExeCore {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    /**
     * @dev Core dealer state stored per tokenId
     */
    struct DealerData {
        uint256 reputation;
        uint32 lastPlayTimestamp;
        uint8 currentArea;
        uint8 previousArea;
        uint8 dailyAttemptsRemaining;
        uint8 heatLevel;
        bool isInitialized;
    }

    /**
     * @dev Time-limited boost configuration applied to a dealer
     */
    struct BoostData {
        uint64 expiresAt;
        uint8 drugMultiplier;
        uint8 repMultiplier;
        uint8 extraAttempts;
        bool freeAreaMovement;
        bool doubleHeistEntries;
        uint8 cashMultiplier;
    }

    /**
     * @dev Reputation tier thresholds and associated bonuses/penalties
     */
    struct ReputationTier {
        uint256 minReputation;
        int16 winBonus;
        int16 tieBonus;
        int16 lossPenalty;
        int16 repCap;
        string tierName;
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Get all dealer data for a token
    function getDealerData(uint256 tokenId) external view returns (
        uint8 currentArea,
        uint256 reputation,
        uint8 dailyAttemptsRemaining,
        uint8 heatLevel,
        uint32 lastPlayTimestamp,
        bool isInitialized
    );

    /// @notice Get the drug balance for a dealer
    function getDrugBalance(uint256 tokenId, uint256 drugId) external view returns (uint256);

    /// @notice Get the threat and armor stats for a dealer
    function getDealerStats(uint256 tokenId) external view returns (uint8 threat, uint8 armor);

    /// @notice Get the reputation tier for a dealer
    function getPlayerTier(uint256 tokenId) external view returns (ReputationTier memory);

    /// @notice Get the reputation change for a given outcome
    function getReputationChange(uint256 tokenId, uint8 outcome) external view returns (int16);

    /// @notice Get the rep cap for a dealer's current tier
    function getRepCap(uint256 tokenId) external view returns (int16);

    /// @notice Get the title string for a reputation value
    function getReputationTitle(uint256 reputation) external view returns (string memory);

    /// @notice Get the tier data for a given reputation value
    function getCurrentTier(uint256 reputation) external view returns (ReputationTier memory);

    /// @notice Get the total reputation for a dealer
    function getTotalReputation(uint256 tokenId) external view returns (uint256);

    /// @notice Get the stash bonus multiplier for a dealer
    function getStashBonus(uint256 tokenId) external view returns (uint256);

    /// @notice Check if a dealer is in jail
    function isInJail(uint256 tokenId) external view returns (bool);

    /// @notice Check if a dealer is in the safe house
    function isInSafeHouse(uint256 tokenId) external view returns (bool);

    /// @notice Get the current heat level for a dealer
    function getHeatLevel(uint256 tokenId) external view returns (uint8);

    /// @notice Get the jail chance percentage based on heat level
    function getJailChance(uint256 tokenId) external view returns (uint8);

    /// @notice Check if a dealer has an active boost
    function hasActiveBoost(uint256 tokenId) external view returns (bool);

    /// @notice Get the boost data for a dealer
    function getBoost(uint256 tokenId) external view returns (BoostData memory);

    /// @notice Get the drug multiplier from active boost
    function getDrugMultiplier(uint256 tokenId) external view returns (uint8);

    /// @notice Get the reputation multiplier from active boost
    function getRepMultiplier(uint256 tokenId) external view returns (uint8);

    /// @notice Get the maximum attempts including boost bonus
    function getMaxAttempts(uint256 tokenId) external view returns (uint8);

    /// @notice Get total daily attempts available for a dealer
    function getTotalDailyAttempts(uint256 tokenId) external view returns (uint8);

    /// @notice Check if dealer has free area movement from boost
    function hasFreeAreaMovement(uint256 tokenId) external view returns (bool);

    /// @notice Check if dealer has double heist entries from boost
    function hasDoubleHeistEntries(uint256 tokenId) external view returns (bool);

    /// @notice Get the $CASH balance for a dealer
    function getCashBalance(uint256 tokenId) external view returns (uint256);

    /// @notice Get the $CASH multiplier from active boost
    function getCashMultiplier(uint256 tokenId) external view returns (uint8);

    /// @notice Get the total number of reputation tiers
    function getTierCount() external view returns (uint256);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Initialize a dealer for a newly minted token
    function initializeDealer(uint256 tokenId) external;

    /// @notice Update a dealer's reputation by a signed amount
    function updateReputation(uint256 tokenId, int256 change) external;

    /// @notice Update a dealer's drug balance by a signed amount
    function updateDrugBalance(uint256 tokenId, uint256 drugId, int256 change) external;

    /// @notice Move a dealer to a new area
    function moveToArea(uint256 tokenId, uint8 newAreaId) external;

    /// @notice Consume one daily attempt for a dealer
    function useAttempt(uint256 tokenId) external;

    /// @notice Update the number of daily plays used
    function updateDailyPlays(uint256 tokenId, uint8 attemptsUsed) external;

    /// @notice Increment a dealer's heat level
    function incrementHeatLevel(uint256 tokenId) external;

    /// @notice Send a dealer to jail
    function sendToJail(uint256 tokenId) external;

    /// @notice Set a dealer's threat and armor stats
    function setDealerStats(uint256 tokenId, uint8 threat, uint8 armor) external;

    /// @notice Apply a boost to a dealer
    function applyBoost(
        uint256 tokenId,
        uint64 duration,
        uint8 drugMultiplier,
        uint8 repMultiplier,
        uint8 extraAttempts,
        bool freeAreaMovement,
        bool doubleHeistEntries,
        uint8 cashMultiplier,
        uint8 tierId
    ) external;

    /// @notice Add $CASH to a dealer's balance
    function addCash(uint256 tokenId, uint256 amount) external;

    /// @notice Spend $CASH from a dealer's balance
    function spendCash(uint256 tokenId, uint256 amount) external;

    /// @notice Purchase $CASH with ETH
    function purchaseCash(uint256 tokenId) external payable;

    /// @notice Pay bail to exit jail (returns to previous area, resets heat)
    function payBail(uint256 tokenId) external payable;

    /// @notice Attempt to break out of jail (once per day, 33% success, keeps heat)
    function attemptBreakout(uint256 tokenId) external;

    /// @notice Player-callable function to move dealer to a new area
    function travel(uint256 tokenId, uint8 destinationArea) external payable;

    /// @notice Purchase an attempt reset for a dealer
    function purchaseAttemptReset(uint256 tokenId) external payable;

    /// @notice Bribe a cop to reduce heat level
    function bribeCop(uint256 tokenId) external payable;

    /// @notice Remove a wanted poster to clear heat
    function removeWantedPoster(uint256 tokenId) external;

    // =============================================================
    //                          CONSTANTS
    // =============================================================

    /// @notice Starting area ID for new dealers
    function STARTING_AREA() external view returns (uint8);

    /// @notice Safe house area ID
    function SAFE_HOUSE_AREA() external view returns (uint8);

    /// @notice Jail area ID
    function JAIL_AREA() external view returns (uint8);

    /// @notice Base maximum daily attempts
    function BASE_MAX_ATTEMPTS() external view returns (uint8);

    /// @notice Maximum heat level
    function MAX_HEAT_LEVEL() external view returns (uint8);

    /// @notice Fee to reset daily attempts
    function ATTEMPT_RESET_FEE() external view returns (uint256);

    /// @notice Fee to bribe a cop
    function BRIBE_COP_FEE() external view returns (uint256);

    /// @notice Jail reputation penalty percentage
    function JAIL_REP_PENALTY_PERCENT() external view returns (uint8);

    /// @notice Maximum jail reputation penalty
    function JAIL_REP_PENALTY_CAP() external view returns (uint256);

    /// @notice Maximum stat modifier value
    function MAX_STAT_MODIFIER() external view returns (uint8);

    /// @notice Starting reputation for new dealers
    function STARTING_REPUTATION() external view returns (uint256);

    /// @notice Price to top up $CASH
    function CASH_TOPUP_PRICE() external view returns (uint256);

    /// @notice Amount of $CASH received per top up
    function CASH_TOPUP_AMOUNT() external view returns (uint256);

    /// @notice Threshold below which $CASH purchase is allowed
    function CASH_PURCHASE_THRESHOLD() external view returns (uint256);

    /// @notice Divisor for stash bonus calculation
    function STASH_DIVISOR() external view returns (uint256);
}
