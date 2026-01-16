// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDealersExeCore - Interface for DealersExeCore
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for all game modules to interact with core state
 *      Drug and Area configuration has been moved to separate registries
 */
interface IDealersExeCore {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct DealerData {
        uint256 reputation;
        uint32 lastPlayTimestamp;
        uint8 currentArea;
        uint8 dailyAttemptsRemaining;
        uint8 heatLevel;
        bool isInitialized;
    }

    struct BoostData {
        uint64 expiresAt;
        uint8 drugMultiplier;
        uint8 repMultiplier;
        uint8 extraAttempts;
        bool freeAreaMovement;
        bool doubleHeistEntries;
        uint8 cashMultiplier;
    }

    struct ReputationTier {
        uint256 minReputation;
        int16 winBonus;
        int16 tieBonus;
        int16 lossPenalty;
        string tierName;
        bool canHeist;
        uint256 pvpRange;
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    // Dealer Data
    function getDealerData(uint256 tokenId) external view returns (
        uint8 currentArea,
        uint256 reputation,
        uint8 dailyAttemptsRemaining,
        uint8 heatLevel,
        uint32 lastPlayTimestamp,
        bool isInitialized
    );
    function getDrugBalance(uint256 tokenId, uint256 drugId) external view returns (uint256);
    function getDealerStats(uint256 tokenId) external view returns (uint8 threat, uint8 armor);
    function getPlayerTier(uint256 tokenId) external view returns (ReputationTier memory);
    function getReputationChange(uint256 tokenId, uint8 outcome) external view returns (int16);
    function getReputationTitle(uint256 reputation) external view returns (string memory);
    function getCurrentTier(uint256 reputation) external view returns (ReputationTier memory);
    function getTotalReputation(uint256 tokenId) external view returns (uint256);
    function getStashBonus(uint256 tokenId) external view returns (uint256);

    // Location checks
    function isInJail(uint256 tokenId) external view returns (bool);
    function isInSafeHouse(uint256 tokenId) external view returns (bool);

    // Heat & Jail
    function getHeatLevel(uint256 tokenId) external view returns (uint8);
    function getJailChance(uint256 tokenId) external view returns (uint8);

    // Boost Functions
    function hasActiveBoost(uint256 tokenId) external view returns (bool);
    function getBoost(uint256 tokenId) external view returns (BoostData memory);
    function getDrugMultiplier(uint256 tokenId) external view returns (uint8);
    function getRepMultiplier(uint256 tokenId) external view returns (uint8);
    function getMaxAttempts(uint256 tokenId) external view returns (uint8);
    function getTotalDailyAttempts(uint256 tokenId) external view returns (uint8);
    function hasFreeAreaMovement(uint256 tokenId) external view returns (bool);
    function hasDoubleHeistEntries(uint256 tokenId) external view returns (bool);

    // $CASH Functions
    function getCashBalance(uint256 tokenId) external view returns (uint256);
    function getCashMultiplier(uint256 tokenId) external view returns (uint8);

    // General
    function getTierCount() external view returns (uint256);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    // Authorized Module Functions
    function initializeDealer(uint256 tokenId) external;
    function updateReputation(uint256 tokenId, int256 change) external;
    function updateDrugBalance(uint256 tokenId, uint256 drugId, int256 change) external;
    function moveToArea(uint256 tokenId, uint8 newAreaId) external;
    function useAttempt(uint256 tokenId) external;
    function updateDailyPlays(uint256 tokenId, uint8 attemptsUsed) external;
    function incrementHeatLevel(uint256 tokenId) external;
    function sendToJail(uint256 tokenId) external;
    function setDealerStats(uint256 tokenId, uint8 threat, uint8 armor) external;
    function applyBoost(
        uint256 tokenId,
        uint64 duration,
        uint8 drugMultiplier,
        uint8 repMultiplier,
        uint8 extraAttempts,
        bool freeAreaMovement,
        bool doubleHeistEntries,
        uint8 cashMultiplier
    ) external;

    // $CASH Functions
    function addCash(uint256 tokenId, uint256 amount) external;
    function spendCash(uint256 tokenId, uint256 amount) external;
    function purchaseCash(uint256 tokenId) external payable;

    // Public Payable Functions (callable by dealer owner)
    function payBail(uint256 tokenId, uint8 exitArea) external payable;
    function purchaseAttemptReset(uint256 tokenId) external payable;
    function bribeCop(uint256 tokenId) external payable;
    function removeWantedPoster(uint256 tokenId) external;

    // Constants (view functions for constants)
    function STARTING_AREA() external view returns (uint8);
    function SAFE_HOUSE_AREA() external view returns (uint8);
    function JAIL_AREA() external view returns (uint8);
    function BASE_MAX_ATTEMPTS() external view returns (uint8);
    function MAX_HEAT_LEVEL() external view returns (uint8);
    function ATTEMPT_RESET_FEE() external view returns (uint256);
    function BRIBE_COP_FEE() external view returns (uint256);
    function JAIL_REP_PENALTY_PERCENT() external view returns (uint8);
    function JAIL_REP_PENALTY_CAP() external view returns (uint256);
    function MAX_STAT_MODIFIER() external view returns (uint8);
    function STARTING_REPUTATION() external view returns (uint256);

    // $CASH Constants
    function STARTER_CASH() external view returns (uint256);
    function CASH_TOPUP_PRICE() external view returns (uint256);
    function CASH_TOPUP_AMOUNT() external view returns (uint256);
    function CASH_PURCHASE_THRESHOLD() external view returns (uint256);
    function STASH_DIVISOR() external view returns (uint256);
}
