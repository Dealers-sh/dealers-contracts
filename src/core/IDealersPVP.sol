// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IDealersPVP {
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
        uint256 repRangeThreshold;
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function getDealerPvpStats(uint256 tokenId) external view returns (PvpStats memory);

    function attacksReceivedToday(uint256 tokenId) external view returns (uint256);

    function lastAttackDay(uint256 tokenId) external view returns (uint256);

    function config() external view returns (PVPConfig memory);

    /**
     * @notice Raw mapping getter — returns tuple (for Claims compatibility)
     */
    function dealerPvpStats(uint256 tokenId)
        external
        view
        returns (uint32 attackWins, uint32 attackLosses, uint32 defendWins, uint32 defendLosses);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /**
     * @notice Commit a PVP attack; outcome is revealed in a later tx
     */
    function commitAttack(uint256 attackerId, uint256 defenderId) external returns (uint64 seq);

    /**
     * @notice Resolve a previously committed PVP attack (anyone may call)
     */
    function resolveAttack(uint64 seq) external;
}
