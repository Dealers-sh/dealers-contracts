// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../utils/IAreaRegistry.sol";

/**
 * @title IDealersCore - Interface for DealersCore
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Interface for all game modules to interact with core state.
 *      Drug and Area configuration has been moved to separate registries.
 * @author Berny0x
 */
interface IDealersCore {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct BoostData {
        uint64 expiresAt;
        uint8 drugMultiplier;
        uint8 repMultiplier;
        uint8 extraAttempts;
        bool freeAreaMovement;
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
    //                     BATCHED API STRUCTS
    // =============================================================

    struct GameState {
        uint8 currentArea;
        uint8 previousArea;
        uint8 heatLevel;
        uint8 dailyAttemptsRemaining;
        uint256 reputation;
        uint256 totalReputation;
        bool isInitialized;
        bool isJailed;
        bool isInSafeHouse;
        uint256 cashBalance;
        bool boostActive;
        uint64 boostExpiresAt;
        bool freeAreaMovement;
        uint8 drugMultiplier;
        uint8 repMultiplier;
        uint8 cashMultiplier;
        uint8 extraAttempts;
        uint16 jailChance;
        int16 repWinBonus;
        int16 repTieBonus;
        int16 repLossPenalty;
        int16 repCap;
        uint8 threat;
        uint8 armor;
        uint32 lastBreakoutAttempt;
        uint256 infamy;
    }

    struct GameOutcome {
        int256 repDelta;
        uint256 drugId;
        int256 drugDelta;
        int256 cashDelta;
        bool incrementHeat;
        bool useAttempt;
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Single read replacing all pre-flight calls for a dealer
    function getGameState(uint256 tokenId) external view returns (GameState memory);

    /// @notice Get game states for two dealers (for PVP)
    function getBothGameStates(uint256 t1, uint256 t2) external view returns (GameState memory, GameState memory);

    /// @notice Batch drug balance lookup for a dealer
    function getAreaDrugBalances(uint256 tokenId, uint256[] calldata drugIds) external view returns (uint256[] memory);

    /// @notice Check if a dealer is initialized (cheap single-field getter)
    function isInitialized(uint256 tokenId) external view returns (bool);

    function getTotalReputation(uint256 tokenId) external view returns (uint256);

    function getStashBonus(uint256 tokenId) external view returns (uint256);

    function getDealerData(uint256 tokenId) external view returns (
        uint8 currentArea,
        uint256 reputation,
        uint8 dailyAttemptsRemaining,
        uint8 heatLevel,
        uint32 lastPlayTimestamp,
        bool initialized
    );

    /// @notice Check if a dealer gets arrested based on heat and RNG
    function rollJailCheck(uint256 tokenId, uint256 rng) external view returns (bool);

    /// @notice Get the drug balance for a dealer
    function getDrugBalance(uint256 tokenId, uint256 drugId) external view returns (uint256);

    /// @notice Get the threat and armor stats for a dealer
    function getDealerStats(uint256 tokenId) external view returns (uint8 threat, uint8 armor);

    /// @notice Get the title string for a reputation value
    function getReputationTitle(uint256 reputation) external view returns (string memory);

    /// @notice Check if a dealer has an active boost
    function hasActiveBoost(uint256 tokenId) external view returns (bool);

    /// @notice Get the boost data for a dealer
    function getBoost(uint256 tokenId) external view returns (BoostData memory);

    /// @notice Get the $CASH balance for a dealer
    function getCashBalance(uint256 tokenId) external view returns (uint256);

    /// @notice Get a dealer's infamy score with lazy decay applied (view only, no write)
    function getInfamy(uint256 tokenId) external view returns (uint256);

    /// @notice Get a dealer's effective heat level with lazy decay applied (view only, no write)
    function getEffectiveHeat(uint256 tokenId) external view returns (uint8);

    /// @notice Get the area registry reference
    function areaRegistry() external view returns (IAreaRegistry);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Single write replacing all state mutation calls for one dealer
    function applyGameOutcome(uint256 tokenId, GameOutcome calldata outcome) external;

    /// @notice Single write for PVP: applies outcomes to both attacker and defender
    function applyPVPOutcome(uint256 atk, uint256 def, GameOutcome calldata atkOut, GameOutcome calldata defOut) external;

    /// @notice Initialize a dealer for a newly minted token
    function initializeDealer(uint256 tokenId) external;

    /// @notice Update a dealer's reputation by a signed amount
    function updateReputation(uint256 tokenId, int256 change) external;

    /// @notice Update a dealer's drug balance by a signed amount
    function updateDrugBalance(uint256 tokenId, uint256 drugId, int256 change) external;

    /// @notice Move a dealer to a new area (validates area, blocks safe house/jail)
    function moveToArea(uint256 tokenId, uint8 newAreaId) external;

    /// @notice Force-move a dealer to any area (no validation, for bail/breakout)
    function forceMove(uint256 tokenId, uint8 newAreaId) external;

    /// @notice Consume one daily attempt for a dealer
    function useAttempt(uint256 tokenId) external;

    /// @notice Update the number of daily plays used
    function updateDailyPlays(uint256 tokenId, uint8 attemptsUsed) external;

    /// @notice Increment a dealer's heat level
    function incrementHeatLevel(uint256 tokenId) external;

    /// @notice Set a dealer's threat and armor stats
    function setDealerStats(uint256 tokenId, uint8 threat, uint8 armor) external;

    /// @notice Pick one drug a dealer is currently holding, indexed by `rng`
    /// @dev Returns (0, 0) if the dealer holds no drugs. Caller supplies entropy.
    function pickHeldDrugByRng(uint256 tokenId, uint256 rng) external view returns (uint256 drugId, uint256 balance);

    /// @notice Apply a boost to a dealer, returns the expiry timestamp
    function applyBoost(
        uint256 tokenId,
        uint64 duration,
        uint8 drugMultiplier,
        uint8 repMultiplier,
        uint8 extraAttempts,
        bool freeAreaMovement,
        uint8 cashMultiplier
    ) external returns (uint64 expiresAt);

    /// @notice Add $CASH to a dealer's balance
    function addCash(uint256 tokenId, uint256 amount) external;

    /// @notice Spend $CASH from a dealer's balance
    function spendCash(uint256 tokenId, uint256 amount) external;

    // =============================================================
    //                     NEW CORE PRIMITIVES
    // =============================================================

    /// @notice Set a dealer's heat level directly
    function setHeatLevel(uint256 tokenId, uint8 level) external;

    /// @notice Set a dealer's last breakout attempt timestamp
    function setLastBreakoutAttempt(uint256 tokenId, uint32 timestamp) external;

    /// @notice Reset a dealer's daily attempts to max
    function resetDailyAttempts(uint256 tokenId) external;

    /// @notice Update a dealer's infamy score by a signed delta (settles decay first)
    function updateInfamy(uint256 tokenId, int256 delta) external;

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

    /// @notice Maximum stat modifier value
    function MAX_STAT_MODIFIER() external view returns (uint8);

    /// @notice Starting reputation for new dealers
    function STARTING_REPUTATION() external view returns (uint256);

    /// @notice Divisor for stash bonus calculation
    function STASH_DIVISOR() external view returns (uint256);
}
