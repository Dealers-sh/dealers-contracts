// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDealersExePVP {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct PvpStats {
        uint32 attackWins;
        uint32 attackLosses;
        uint32 defendWins;
        uint32 defendLosses;
    }

    struct PVPConfig {
        uint256 minReputation;
        uint8 baseWinChance;
        uint8 minWinChance;
        uint8 maxWinChance;
        uint8 maxAttacksPerDay;
        uint8 drugStealPercent;
        uint8 cashStealPercent;
        uint8 rarityWeightCommon;
        uint8 rarityWeightUncommon;
        uint8 rarityWeightRare;
        uint8 repRangePercent;
        uint8 defenderRepBonus;
    }

    struct PVPTarget {
        uint256 tokenId;
        uint256 reputation;
        uint8 threat;
        uint8 armor;
        uint8 attemptsRemaining;
        uint256 winChance;
        uint256 lossChance;
        bool canAttackNow;
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function getDealerPvpStats(uint256 tokenId) external view returns (PvpStats memory);

    function calculateWinChance(uint256 attackerId, uint256 defenderId) external view returns (uint256);

    function canAttack(uint256 attackerId, uint256 defenderId) external view returns (bool canFight, uint8 reason);

    function attacksReceivedToday(uint256 tokenId) external view returns (uint256);

    function lastAttackDay(uint256 tokenId) external view returns (uint256);

    function config() external view returns (
        uint256 minReputation,
        uint8 baseWinChance,
        uint8 minWinChance,
        uint8 maxWinChance,
        uint8 maxAttacksPerDay,
        uint8 drugStealPercent,
        uint8 cashStealPercent,
        uint8 rarityWeightCommon,
        uint8 rarityWeightUncommon,
        uint8 rarityWeightRare,
        uint8 repRangePercent,
        uint8 defenderRepBonus
    );

    function getPotentialTargets(
        uint256 attackerId,
        uint256 offset,
        uint256 limit
    ) external view returns (PVPTarget[] memory targets, uint256 totalInArea);

    /// @notice Raw mapping getter — returns tuple (for Claims compatibility)
    function dealerPvpStats(uint256 tokenId) external view returns (
        uint32 attackWins,
        uint32 attackLosses,
        uint32 defendWins,
        uint32 defendLosses
    );

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    function attack(uint256 attackerId, uint256 defenderId) external;
}
