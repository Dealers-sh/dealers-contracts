// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IDealersExeCore.sol";
import {IDealersExePVE} from "./IDealersExePVE.sol";
import {IDealersExePVP} from "./IDealersExePVP.sol";
import "../utils/IERC721Minimal.sol";

/**
 * @title DealersExeClaims - Achievement & admin reward claims
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Two claim paths:
 *      1. On-chain achievements: contract reads PVE/PVP/Core stats, verifies threshold
 *      2. Admin grants: owner distributes rewards for off-chain events via script
 * @author Dealers.Exe Team
 */
contract DealersExeClaims is ReentrancyGuard, Ownable {
    // =============================================================
    //                            ENUMS
    // =============================================================

    enum RewardType { REPUTATION, CASH, DRUG, ATTEMPTS }

    enum ConditionType {
        NONE,               // 0 - unused (reserved)
        PVE_WINS,           // 1
        PVE_LOSSES,         // 2
        PVE_TIES,           // 3
        PVE_TOTAL,          // 4 - wins + losses + ties
        PVP_ATTACK_WINS,    // 5
        PVP_DEFEND_WINS,    // 6
        PVP_TOTAL_WINS,     // 7 - attackWins + defendWins
        REPUTATION,         // 8
        CASH_BALANCE,       // 9
        DRUG_BALANCE,       // 10 - uses conditionValue as drugId
        PVE_DEAL_CHOICES,   // 11
        PVE_THREATEN_CHOICES, // 12
        PVE_BAIL_CHOICES    // 13
    }

    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct Achievement {
        uint8 conditionType;
        uint256 conditionValue;
        uint256 threshold;
        uint8 rewardType;
        uint256 rewardId;
        uint256 rewardAmount;
        bool active;
    }

    struct CachedStats {
        uint32 pveWins;
        uint32 pveLosses;
        uint32 pveTies;
        uint32 dealChoices;
        uint32 threatenChoices;
        uint32 bailChoices;
        uint32 pvpAttackWins;
        uint32 pvpAttackLosses;
        uint32 pvpDefendWins;
        uint32 pvpDefendLosses;
        uint256 totalReputation;
        uint256 cashBalance;
    }

    // =============================================================
    //                           STORAGE
    // =============================================================

    IDealersExeCore public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    IDealersExePVE public pveContract;
    IDealersExePVP public pvpContract;

    mapping(uint256 => Achievement) public achievements;
    uint256 public achievementCount;

    mapping(uint256 achievementId => mapping(uint256 tokenId => bool)) public achievementClaimed;

    // =============================================================
    //                           EVENTS
    // =============================================================

    event AchievementClaimed(uint256 indexed tokenId, uint256 indexed achievementId, uint8 rewardType, uint256 rewardAmount);
    event RewardGranted(uint256 indexed tokenId, uint8 rewardType, uint256 rewardId, uint256 amount);
    event BatchRewardGranted(uint256 count, uint8 rewardType, uint256 rewardId, uint256 amount);
    event AchievementSet(uint256 indexed achievementId, uint8 conditionType, uint256 threshold, uint8 rewardType, uint256 rewardAmount);
    event AchievementRemoved(uint256 indexed achievementId);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error NotTokenOwner();
    error AlreadyClaimed();
    error InvalidRewardType();
    error InvalidAddress();
    error AchievementNotActive();
    error ThresholdNotMet();
    error InvalidConditionForAchievement();
    error InvalidAchievementConfig();
    error LengthMismatch();

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    constructor(
        address _dealersExeCore,
        address _dealersExeNFT,
        address _pve,
        address _pvp
    ) {
        if (_dealersExeCore == address(0) || _dealersExeNFT == address(0) || _pve == address(0) || _pvp == address(0)) {
            revert InvalidAddress();
        }
        _initializeOwner(msg.sender);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        pveContract = IDealersExePVE(_pve);
        pvpContract = IDealersExePVP(_pvp);
    }

    // =============================================================
    //                   ON-CHAIN ACHIEVEMENT CLAIMS
    // =============================================================

    function claimAchievement(uint256 tokenId, uint256 achievementId) external nonReentrant {
        if (dealersExeNFT.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        CachedStats memory cached = _buildCachedStats(tokenId);
        _claimAchievement(tokenId, achievementId, cached);
    }

    function claimAchievements(uint256 tokenId, uint256[] calldata achievementIds) external nonReentrant {
        if (dealersExeNFT.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        CachedStats memory cached = _buildCachedStats(tokenId);
        for (uint256 i; i < achievementIds.length;) {
            _claimAchievement(tokenId, achievementIds[i], cached);
            unchecked { ++i; }
        }
    }

    // =============================================================
    //                      ADMIN GRANT REWARDS
    // =============================================================

    function grantReward(
        uint256 tokenId,
        uint8 rewardType,
        uint256 rewardId,
        uint256 amount
    ) external onlyOwner {
        _grantReward(tokenId, rewardType, rewardId, amount);
        emit RewardGranted(tokenId, rewardType, rewardId, amount);
    }

    function batchGrantReward(
        uint256[] calldata tokenIds,
        uint8 rewardType,
        uint256 rewardId,
        uint256 amount
    ) external onlyOwner {
        for (uint256 i; i < tokenIds.length;) {
            _grantReward(tokenIds[i], rewardType, rewardId, amount);
            unchecked { ++i; }
        }
        emit BatchRewardGranted(tokenIds.length, rewardType, rewardId, amount);
    }

    function batchGrantRewards(
        uint256[] calldata tokenIds,
        uint8[] calldata rewardTypes,
        uint256[] calldata rewardIds,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (tokenIds.length != rewardTypes.length || tokenIds.length != rewardIds.length || tokenIds.length != amounts.length) {
            revert LengthMismatch();
        }
        for (uint256 i; i < tokenIds.length;) {
            _grantReward(tokenIds[i], rewardTypes[i], rewardIds[i], amounts[i]);
            emit RewardGranted(tokenIds[i], rewardTypes[i], rewardIds[i], amounts[i]);
            unchecked { ++i; }
        }
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function hasClaimedAchievement(uint256 achievementId, uint256 tokenId) external view returns (bool) {
        return achievementClaimed[achievementId][tokenId];
    }

    function getAchievement(uint256 achievementId) external view returns (Achievement memory) {
        return achievements[achievementId];
    }

    function canClaimAchievement(uint256 tokenId, uint256 achievementId) external view returns (bool) {
        Achievement storage a = achievements[achievementId];
        if (!a.active || a.conditionType == uint8(ConditionType.NONE)) return false;
        if (achievementClaimed[achievementId][tokenId]) return false;
        CachedStats memory cached = _buildCachedStats(tokenId);
        uint256 statValue = _getStatValue(tokenId, a.conditionType, a.conditionValue, cached);
        return statValue >= a.threshold;
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    function _claimAchievement(uint256 tokenId, uint256 achievementId, CachedStats memory cached) internal {
        if (achievementClaimed[achievementId][tokenId]) revert AlreadyClaimed();

        Achievement storage a = achievements[achievementId];
        if (!a.active) revert AchievementNotActive();
        if (a.conditionType == uint8(ConditionType.NONE)) revert InvalidConditionForAchievement();

        uint256 statValue = _getStatValue(tokenId, a.conditionType, a.conditionValue, cached);
        if (statValue < a.threshold) revert ThresholdNotMet();

        achievementClaimed[achievementId][tokenId] = true;
        _grantReward(tokenId, a.rewardType, a.rewardId, a.rewardAmount);

        emit AchievementClaimed(tokenId, achievementId, a.rewardType, a.rewardAmount);
    }

    function _buildCachedStats(uint256 tokenId) internal view returns (CachedStats memory cached) {
        (uint32 pveWins, uint32 pveLosses, uint32 pveTies, uint32 dealChoices, uint32 threatenChoices, uint32 bailChoices) =
            pveContract.dealerPveStats(tokenId);
        (uint32 pvpAttackWins, uint32 pvpAttackLosses, uint32 pvpDefendWins, uint32 pvpDefendLosses) =
            pvpContract.dealerPvpStats(tokenId);
        IDealersExeCore.GameState memory gameState = dealersExeCore.getGameState(tokenId);

        cached = CachedStats({
            pveWins: pveWins,
            pveLosses: pveLosses,
            pveTies: pveTies,
            dealChoices: dealChoices,
            threatenChoices: threatenChoices,
            bailChoices: bailChoices,
            pvpAttackWins: pvpAttackWins,
            pvpAttackLosses: pvpAttackLosses,
            pvpDefendWins: pvpDefendWins,
            pvpDefendLosses: pvpDefendLosses,
            totalReputation: gameState.totalReputation,
            cashBalance: gameState.cashBalance
        });
    }

    function _getStatValue(uint256 tokenId, uint8 conditionType, uint256 conditionValue, CachedStats memory cached) internal view returns (uint256) {
        if (conditionType == uint8(ConditionType.PVE_WINS)) return cached.pveWins;
        if (conditionType == uint8(ConditionType.PVE_LOSSES)) return cached.pveLosses;
        if (conditionType == uint8(ConditionType.PVE_TIES)) return cached.pveTies;
        if (conditionType == uint8(ConditionType.PVE_TOTAL)) return uint256(cached.pveWins) + uint256(cached.pveLosses) + uint256(cached.pveTies);
        if (conditionType == uint8(ConditionType.PVP_ATTACK_WINS)) return cached.pvpAttackWins;
        if (conditionType == uint8(ConditionType.PVP_DEFEND_WINS)) return cached.pvpDefendWins;
        if (conditionType == uint8(ConditionType.PVP_TOTAL_WINS)) return uint256(cached.pvpAttackWins) + uint256(cached.pvpDefendWins);
        if (conditionType == uint8(ConditionType.REPUTATION)) return cached.totalReputation;
        if (conditionType == uint8(ConditionType.CASH_BALANCE)) return cached.cashBalance;
        if (conditionType == uint8(ConditionType.DRUG_BALANCE)) return dealersExeCore.getDrugBalance(tokenId, conditionValue);
        if (conditionType == uint8(ConditionType.PVE_DEAL_CHOICES)) return cached.dealChoices;
        if (conditionType == uint8(ConditionType.PVE_THREATEN_CHOICES)) return cached.threatenChoices;
        if (conditionType == uint8(ConditionType.PVE_BAIL_CHOICES)) return cached.bailChoices;
        revert InvalidConditionForAchievement();
    }

    function _grantReward(uint256 tokenId, uint8 rewardType, uint256 rewardId, uint256 amount) internal {
        if (rewardType == uint8(RewardType.REPUTATION)) {
            dealersExeCore.updateReputation(tokenId, int256(amount));
        } else if (rewardType == uint8(RewardType.CASH)) {
            dealersExeCore.addCash(tokenId, amount);
        } else if (rewardType == uint8(RewardType.DRUG)) {
            dealersExeCore.updateDrugBalance(tokenId, rewardId, int256(amount));
        } else if (rewardType == uint8(RewardType.ATTEMPTS)) {
            dealersExeCore.updateDailyPlays(tokenId, 0);
        } else {
            revert InvalidRewardType();
        }
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    function setAchievement(uint256 achievementId, Achievement calldata achievement) external onlyOwner {
        if (achievement.conditionType == uint8(ConditionType.NONE) || achievement.conditionType > uint8(ConditionType.PVE_BAIL_CHOICES)) {
            revert InvalidAchievementConfig();
        }
        if (achievement.rewardType > uint8(RewardType.ATTEMPTS)) revert InvalidAchievementConfig();

        achievements[achievementId] = achievement;
        if (achievementId >= achievementCount) achievementCount = achievementId + 1;
        emit AchievementSet(achievementId, achievement.conditionType, achievement.threshold, achievement.rewardType, achievement.rewardAmount);
    }

    function batchMarkClaimed(uint256 achievementId, uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i; i < tokenIds.length;) {
            achievementClaimed[achievementId][tokenIds[i]] = true;
            unchecked { ++i; }
        }
    }

    function removeAchievement(uint256 achievementId) external onlyOwner {
        delete achievements[achievementId];
        emit AchievementRemoved(achievementId);
    }

    function setDealersExeCore(address _core) external onlyOwner {
        if (_core == address(0)) revert InvalidAddress();
        dealersExeCore = IDealersExeCore(_core);
    }

    function setDealersExeNFT(address _nft) external onlyOwner {
        if (_nft == address(0)) revert InvalidAddress();
        dealersExeNFT = IERC721Minimal(_nft);
    }

    function setPVE(address _pve) external onlyOwner {
        if (_pve == address(0)) revert InvalidAddress();
        pveContract = IDealersExePVE(_pve);
    }

    function setPVP(address _pvp) external onlyOwner {
        if (_pvp == address(0)) revert InvalidAddress();
        pvpContract = IDealersExePVP(_pvp);
    }
}
