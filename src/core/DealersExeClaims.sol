// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IDealersExeCore.sol";
import "./DealersExePVE.sol";
import "./DealersExePVP.sol";
import "../utils/IERC721Minimal.sol";

/**
 * @title DealersExeClaims - Hybrid achievement & signature-based reward claims
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Two claim paths:
 *      1. On-chain achievements: contract reads PVE/PVP/Core stats, verifies threshold
 *      2. Signature claims: backend signs claims for off-chain actions
 * @author Dealers.Exe Team
 */
contract DealersExeClaims is ReentrancyGuard, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // =============================================================
    //                            ENUMS
    // =============================================================

    enum RewardType { REPUTATION, CASH, DRUG, ATTEMPTS }

    enum ConditionType {
        NONE,               // 0 - signature-only (no on-chain check)
        PVE_WINS,           // 1
        PVE_LOSSES,         // 2
        PVE_TIES,           // 3
        PVE_TOTAL,          // 4 - wins + losses + ties
        PVP_ATTACK_WINS,    // 5
        PVP_DEFEND_WINS,    // 6
        PVP_TOTAL_WINS,     // 7 - attackWins + defendWins
        REPUTATION,         // 8
        CASH_BALANCE,       // 9
        DRUG_BALANCE        // 10 - uses conditionValue as drugId
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

    // =============================================================
    //                           STORAGE
    // =============================================================

    IDealersExeCore public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    DealersExePVE public pveContract;
    DealersExePVP public pvpContract;
    address public signer;

    mapping(uint256 => Achievement) public achievements;
    uint256 public achievementCount;

    mapping(uint256 achievementId => mapping(uint256 tokenId => bool)) public achievementClaimed;
    mapping(uint256 claimId => mapping(uint256 tokenId => bool)) public signatureClaimed;

    // =============================================================
    //                           EVENTS
    // =============================================================

    event AchievementClaimed(uint256 indexed tokenId, uint256 indexed achievementId, uint8 rewardType, uint256 rewardAmount);
    event SignatureRewardClaimed(uint256 indexed tokenId, uint256 indexed claimId, uint8 rewardType, uint256 rewardId, uint256 amount);
    event AchievementSet(uint256 indexed achievementId, uint8 conditionType, uint256 threshold, uint8 rewardType, uint256 rewardAmount);
    event AchievementRemoved(uint256 indexed achievementId);
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error NotTokenOwner();
    error AlreadyClaimed();
    error InvalidSignature();
    error InvalidRewardType();
    error InvalidAddress();
    error AchievementNotActive();
    error ThresholdNotMet();
    error InvalidConditionForAchievement();

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    constructor(
        address _dealersExeCore,
        address _dealersExeNFT,
        address _pve,
        address _pvp,
        address _signer
    ) {
        _initializeOwner(msg.sender);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        pveContract = DealersExePVE(_pve);
        pvpContract = DealersExePVP(_pvp);
        signer = _signer;
    }

    // =============================================================
    //                   ON-CHAIN ACHIEVEMENT CLAIMS
    // =============================================================

    function claimAchievement(uint256 tokenId, uint256 achievementId) external nonReentrant {
        if (dealersExeNFT.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (achievementClaimed[achievementId][tokenId]) revert AlreadyClaimed();

        Achievement storage a = achievements[achievementId];
        if (!a.active) revert AchievementNotActive();
        if (a.conditionType == uint8(ConditionType.NONE)) revert InvalidConditionForAchievement();

        uint256 statValue = _getStatValue(tokenId, a.conditionType, a.conditionValue);
        if (statValue < a.threshold) revert ThresholdNotMet();

        achievementClaimed[achievementId][tokenId] = true;
        _grantReward(tokenId, a.rewardType, a.rewardId, a.rewardAmount);

        emit AchievementClaimed(tokenId, achievementId, a.rewardType, a.rewardAmount);
    }

    // =============================================================
    //                    SIGNATURE-BASED CLAIMS
    // =============================================================

    function claimWithSignature(
        uint256 tokenId,
        uint256 claimId,
        uint8 rewardType,
        uint256 rewardId,
        uint256 amount,
        bytes calldata signature
    ) external nonReentrant {
        if (dealersExeNFT.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (signatureClaimed[claimId][tokenId]) revert AlreadyClaimed();

        bytes32 messageHash = keccak256(
            abi.encodePacked(tokenId, claimId, rewardType, rewardId, amount)
        );
        address recovered = messageHash.toEthSignedMessageHash().recover(signature);
        if (recovered != signer) revert InvalidSignature();

        signatureClaimed[claimId][tokenId] = true;
        _grantReward(tokenId, rewardType, rewardId, amount);

        emit SignatureRewardClaimed(tokenId, claimId, rewardType, rewardId, amount);
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function hasClaimedAchievement(uint256 achievementId, uint256 tokenId) external view returns (bool) {
        return achievementClaimed[achievementId][tokenId];
    }

    function hasClaimedSignature(uint256 claimId, uint256 tokenId) external view returns (bool) {
        return signatureClaimed[claimId][tokenId];
    }

    function getAchievement(uint256 achievementId) external view returns (Achievement memory) {
        return achievements[achievementId];
    }

    function canClaimAchievement(uint256 tokenId, uint256 achievementId) external view returns (bool) {
        Achievement storage a = achievements[achievementId];
        if (!a.active || a.conditionType == uint8(ConditionType.NONE)) return false;
        if (achievementClaimed[achievementId][tokenId]) return false;
        uint256 statValue = _getStatValue(tokenId, a.conditionType, a.conditionValue);
        return statValue >= a.threshold;
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    function _getStatValue(uint256 tokenId, uint8 conditionType, uint256 conditionValue) internal view returns (uint256) {
        if (conditionType == uint8(ConditionType.PVE_WINS)) {
            (uint32 wins,,,,,) = pveContract.dealerPveStats(tokenId);
            return wins;
        } else if (conditionType == uint8(ConditionType.PVE_LOSSES)) {
            (, uint32 losses,,,,) = pveContract.dealerPveStats(tokenId);
            return losses;
        } else if (conditionType == uint8(ConditionType.PVE_TIES)) {
            (,, uint32 ties,,,) = pveContract.dealerPveStats(tokenId);
            return ties;
        } else if (conditionType == uint8(ConditionType.PVE_TOTAL)) {
            (uint32 wins, uint32 losses, uint32 ties,,,) = pveContract.dealerPveStats(tokenId);
            return uint256(wins) + uint256(losses) + uint256(ties);
        } else if (conditionType == uint8(ConditionType.PVP_ATTACK_WINS)) {
            (uint32 attackWins,,,) = pvpContract.dealerPvpStats(tokenId);
            return attackWins;
        } else if (conditionType == uint8(ConditionType.PVP_DEFEND_WINS)) {
            (,, uint32 defendWins,) = pvpContract.dealerPvpStats(tokenId);
            return defendWins;
        } else if (conditionType == uint8(ConditionType.PVP_TOTAL_WINS)) {
            (uint32 attackWins,, uint32 defendWins,) = pvpContract.dealerPvpStats(tokenId);
            return uint256(attackWins) + uint256(defendWins);
        } else if (conditionType == uint8(ConditionType.REPUTATION)) {
            return dealersExeCore.getTotalReputation(tokenId);
        } else if (conditionType == uint8(ConditionType.CASH_BALANCE)) {
            return dealersExeCore.getCashBalance(tokenId);
        } else if (conditionType == uint8(ConditionType.DRUG_BALANCE)) {
            return dealersExeCore.getDrugBalance(tokenId, conditionValue);
        }
        return 0;
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
        achievements[achievementId] = achievement;
        if (achievementId >= achievementCount) achievementCount = achievementId + 1;
        emit AchievementSet(achievementId, achievement.conditionType, achievement.threshold, achievement.rewardType, achievement.rewardAmount);
    }

    function removeAchievement(uint256 achievementId) external onlyOwner {
        delete achievements[achievementId];
        emit AchievementRemoved(achievementId);
    }

    function setSigner(address _signer) external onlyOwner {
        if (_signer == address(0)) revert InvalidAddress();
        address old = signer;
        signer = _signer;
        emit SignerUpdated(old, _signer);
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
        pveContract = DealersExePVE(_pve);
    }

    function setPVP(address _pvp) external onlyOwner {
        if (_pvp == address(0)) revert InvalidAddress();
        pvpContract = DealersExePVP(_pvp);
    }
}
