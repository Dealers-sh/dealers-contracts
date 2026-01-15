// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IDealersExeCore.sol";
import "./IAreaRegistry.sol";

interface IERC721Minimal {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @title DealersExePVP - Player vs Player Combat Module
 * @dev Handles PVP gameplay with stat-based win chances, drug stealing, and cooldowns
 *      Uses AreaRegistry for drug availability per area
 * @author Dealers.Exe Team
 */
contract DealersExePVP is ReentrancyGuard, Ownable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant BASE_WIN_CHANCE = 50;
    uint256 public constant MIN_WIN_CHANCE = 25;
    uint256 public constant MAX_WIN_CHANCE = 75;
    uint256 public constant DRUG_STEAL_PERCENT = 10;
    uint256 public constant ATTACK_COOLDOWN = 1 hours;

    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersExeCore public core;
    IERC721Minimal public nftContract;
    IAreaRegistry public areaRegistry;

    mapping(uint256 => mapping(uint256 => uint256)) public lastAttackTime;

    // Statistics per dealer
    mapping(uint256 => uint256) public attacksWon;
    mapping(uint256 => uint256) public attacksLost;
    mapping(uint256 => uint256) public defensesWon;
    mapping(uint256 => uint256) public defensesLost;
    mapping(uint256 => uint256) public totalDrugsStolen;
    mapping(uint256 => uint256) public totalDrugsLost;
    mapping(uint256 => uint256) public timesArrested;

    // Global statistics
    uint256 public totalPVPBattles;
    uint256 public totalArrestsInPVP;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event PVPBattleResult(
        uint256 indexed attacker,
        uint256 indexed defender,
        bool attackerWon,
        uint256 drugsStolen,
        int16 attackerRepChange,
        int16 defenderRepChange
    );

    event DealerArrested(uint256 indexed tokenId, uint8 heatLevel);
    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event AreaRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotDealerOwner();
    error DealerNotInitialized();
    error DealerInJail();
    error DealerInSafeHouse();
    error SameDealer();
    error DifferentArea();
    error CooldownActive();
    error NoAttemptsRemaining();
    error ContractNotSet();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the PVP contract
     * @param _core Address of the core dealers contract
     * @param _nftContract Address of the NFT contract for ownership checks
     * @param _areaRegistry Address of the area registry
     */
    constructor(address _core, address _nftContract, address _areaRegistry) {
        _initializeOwner(msg.sender);
        core = IDealersExeCore(_core);
        nftContract = IERC721Minimal(_nftContract);
        areaRegistry = IAreaRegistry(_areaRegistry);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(core) == address(0) ||
            address(nftContract) == address(0) ||
            address(areaRegistry) == address(0)
        ) {
            revert ContractNotSet();
        }
        _;
    }

    modifier dealerExists(uint256 tokenId) {
        (, , , , , bool isInitialized) = core.getDealerData(tokenId);
        if (!isInitialized) revert DealerNotInitialized();
        _;
    }

    modifier onlyDealerOwner(uint256 tokenId) {
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();
        _;
    }

    // =============================================================
    //                        MAIN ATTACK FUNCTION
    // =============================================================

    /**
     * @notice Attack another dealer in the same area
     * @param attackerId Your dealer's token ID
     * @param defenderId Target dealer's token ID
     */
    function attack(uint256 attackerId, uint256 defenderId)
        external
        nonReentrant
        contractsSet
        dealerExists(attackerId)
        dealerExists(defenderId)
        onlyDealerOwner(attackerId)
    {
        if (attackerId == defenderId) revert SameDealer();

        uint8 area = _validateLocationsAndGetArea(attackerId, defenderId);

        if (block.timestamp < lastAttackTime[attackerId][defenderId] + ATTACK_COOLDOWN) {
            revert CooldownActive();
        }

        core.useAttempt(attackerId);
        core.incrementHeatLevel(attackerId);

        _executeBattle(attackerId, defenderId, area);
    }

    /**
     * @notice Validate that both dealers are not in jail/safe house and are in the same area
     */
    function _validateLocationsAndGetArea(uint256 attackerId, uint256 defenderId) private view returns (uint8) {
        if (core.isInJail(attackerId)) revert DealerInJail();
        if (core.isInSafeHouse(attackerId)) revert DealerInSafeHouse();
        if (core.isInJail(defenderId)) revert DealerInJail();
        if (core.isInSafeHouse(defenderId)) revert DealerInSafeHouse();

        (uint8 attackerArea, , , , , ) = core.getDealerData(attackerId);
        (uint8 defenderArea, , , , , ) = core.getDealerData(defenderId);
        if (attackerArea != defenderArea) revert DifferentArea();

        return attackerArea;
    }

    /**
     * @notice Execute the battle after validations
     */
    function _executeBattle(uint256 attackerId, uint256 defenderId, uint8 area) private {
        uint256 randomness = _generateRandomness(attackerId, defenderId);

        if (_checkAndProcessArrest(attackerId, randomness)) {
            lastAttackTime[attackerId][defenderId] = block.timestamp;
            return;
        }

        uint256 winChance = calculateWinChance(attackerId, defenderId);
        bool attackerWon = ((randomness >> 8) % 100) < winChance;

        (uint256 drugsStolen, int16 attackerRepChange, int16 defenderRepChange) =
            _processBattleOutcome(attackerId, defenderId, attackerWon, area);

        lastAttackTime[attackerId][defenderId] = block.timestamp;

        _updateStatistics(attackerId, defenderId, attackerWon, drugsStolen);

        emit PVPBattleResult(
            attackerId,
            defenderId,
            attackerWon,
            drugsStolen,
            attackerRepChange,
            defenderRepChange
        );
    }

    // =============================================================
    //                        INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Generate randomness for battle
     */
    function _generateRandomness(uint256 attackerId, uint256 defenderId) private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            attackerId,
            defenderId,
            msg.sender,
            totalPVPBattles
        )));
    }

    /**
     * @notice Check if attacker gets arrested
     */
    function _checkAndProcessArrest(uint256 attackerId, uint256 randomness) private returns (bool) {
        uint8 jailChance = core.getJailChance(attackerId);
        uint8 jailRoll = uint8(randomness % 100);

        if (jailRoll < jailChance) {
            core.sendToJail(attackerId);

            unchecked {
                ++timesArrested[attackerId];
                ++totalArrestsInPVP;
            }

            emit DealerArrested(attackerId, jailChance);
            return true;
        }
        return false;
    }

    /**
     * @notice Process battle outcome
     */
    function _processBattleOutcome(
        uint256 attackerId,
        uint256 defenderId,
        bool attackerWon,
        uint8 area
    ) private returns (uint256 drugsStolen, int16 attackerRepChange, int16 defenderRepChange) {
        uint256 winnerId;
        uint256 loserId;

        if (attackerWon) {
            winnerId = attackerId;
            loserId = defenderId;
        } else {
            winnerId = defenderId;
            loserId = attackerId;
        }

        drugsStolen = _stealDrugs(winnerId, loserId, area);

        int16 winnerBaseRep = core.getReputationChange(winnerId, 0);
        int16 loserBaseRep = core.getReputationChange(loserId, 2);

        uint8 winnerRepMultiplier = core.getRepMultiplier(winnerId);
        int16 winnerRepChange = int16((int256(winnerBaseRep) * int256(uint256(winnerRepMultiplier))) / 100);

        core.updateReputation(winnerId, int256(winnerRepChange));
        core.updateReputation(loserId, int256(loserBaseRep));

        if (attackerWon) {
            attackerRepChange = winnerRepChange;
            defenderRepChange = loserBaseRep;
        } else {
            attackerRepChange = loserBaseRep;
            defenderRepChange = winnerRepChange;
        }

        return (drugsStolen, attackerRepChange, defenderRepChange);
    }

    /**
     * @notice Steal drugs from loser to winner using AreaRegistry for drug IDs
     */
    function _stealDrugs(uint256 winnerId, uint256 loserId, uint8 area) private returns (uint256 totalStolen) {
        // Get area's drug IDs from AreaRegistry
        uint256[] memory drugIds = areaRegistry.getAreaDrugIds(area);

        for (uint256 i = 0; i < drugIds.length; ) {
            uint256 drugId = drugIds[i];

            if (drugId == 0) {
                unchecked { ++i; }
                continue;
            }

            uint256 loserBalance = core.getDrugBalance(loserId, drugId);

            if (loserBalance > 0) {
                uint256 stolen = (loserBalance * DRUG_STEAL_PERCENT) / 100;

                if (stolen > 0) {
                    core.updateDrugBalance(loserId, drugId, -int256(stolen));
                    core.updateDrugBalance(winnerId, drugId, int256(stolen));

                    unchecked { totalStolen += stolen; }
                }
            }

            unchecked { ++i; }
        }

        return totalStolen;
    }

    /**
     * @notice Update battle statistics
     */
    function _updateStatistics(
        uint256 attackerId,
        uint256 defenderId,
        bool attackerWon,
        uint256 drugsStolen
    ) private {
        unchecked {
            ++totalPVPBattles;

            if (attackerWon) {
                ++attacksWon[attackerId];
                ++defensesLost[defenderId];
                totalDrugsStolen[attackerId] += drugsStolen;
                totalDrugsLost[defenderId] += drugsStolen;
            } else {
                ++attacksLost[attackerId];
                ++defensesWon[defenderId];
                totalDrugsStolen[defenderId] += drugsStolen;
                totalDrugsLost[attackerId] += drugsStolen;
            }
        }
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Calculate win chance for an attack
     */
    function calculateWinChance(uint256 attackerId, uint256 defenderId) public view returns (uint256) {
        (uint8 attackerThreat, ) = core.getDealerStats(attackerId);
        (, uint8 defenderArmor) = core.getDealerStats(defenderId);

        int256 statModifier = int256(uint256(attackerThreat)) - int256(uint256(defenderArmor));
        int256 finalChance = int256(BASE_WIN_CHANCE) + statModifier;

        if (finalChance < int256(MIN_WIN_CHANCE)) {
            return MIN_WIN_CHANCE;
        }
        if (finalChance > int256(MAX_WIN_CHANCE)) {
            return MAX_WIN_CHANCE;
        }

        return uint256(finalChance);
    }

    /**
     * @notice Check if an attack is possible
     */
    function canAttack(uint256 attackerId, uint256 defenderId) external view returns (bool canFight, uint8 reason) {
        if (attackerId == defenderId) return (false, 1);

        (, , uint8 attackerAttempts, , , bool attackerInit) = core.getDealerData(attackerId);
        if (!attackerInit) return (false, 2);

        (, , , , , bool defenderInit) = core.getDealerData(defenderId);
        if (!defenderInit) return (false, 3);

        if (core.isInJail(attackerId)) return (false, 4);
        if (core.isInSafeHouse(attackerId)) return (false, 5);
        if (core.isInJail(defenderId)) return (false, 6);
        if (core.isInSafeHouse(defenderId)) return (false, 7);

        (uint8 attackerArea, , , , , ) = core.getDealerData(attackerId);
        (uint8 defenderArea, , , , , ) = core.getDealerData(defenderId);
        if (attackerArea != defenderArea) return (false, 8);

        if (block.timestamp < lastAttackTime[attackerId][defenderId] + ATTACK_COOLDOWN) {
            return (false, 9);
        }

        if (attackerAttempts == 0) return (false, 10);

        return (true, 0);
    }

    /**
     * @notice Get remaining cooldown time for an attack
     */
    function getCooldownRemaining(uint256 attackerId, uint256 defenderId) external view returns (uint256) {
        uint256 lastAttack = lastAttackTime[attackerId][defenderId];
        uint256 cooldownEnd = lastAttack + ATTACK_COOLDOWN;

        if (block.timestamp >= cooldownEnd) {
            return 0;
        }

        return cooldownEnd - block.timestamp;
    }

    /**
     * @notice Get PVP statistics for a specific dealer
     */
    function getPlayerPVPStats(uint256 tokenId) external view returns (
        uint256 _attacksWon,
        uint256 _attacksLost,
        uint256 _defensesWon,
        uint256 _defensesLost,
        uint256 _totalDrugsStolen,
        uint256 _totalDrugsLost,
        uint256 _timesArrested
    ) {
        return (
            attacksWon[tokenId],
            attacksLost[tokenId],
            defensesWon[tokenId],
            defensesLost[tokenId],
            totalDrugsStolen[tokenId],
            totalDrugsLost[tokenId],
            timesArrested[tokenId]
        );
    }

    /**
     * @notice Get global PVP statistics
     */
    function getGlobalStats() external view returns (
        uint256 _totalBattles,
        uint256 _totalArrests
    ) {
        return (totalPVPBattles, totalArrestsInPVP);
    }

    /**
     * @notice Preview battle stats for UI
     */
    function previewBattle(uint256 attackerId, uint256 defenderId) external view returns (
        uint8 attackerThreat,
        uint8 defenderArmor,
        uint256 winChance,
        uint256 potentialDrugSteal
    ) {
        (attackerThreat, ) = core.getDealerStats(attackerId);
        (, defenderArmor) = core.getDealerStats(defenderId);
        winChance = calculateWinChance(attackerId, defenderId);

        (uint8 defenderArea, , , , , ) = core.getDealerData(defenderId);
        uint256[] memory drugIds = areaRegistry.getAreaDrugIds(defenderArea);

        for (uint256 i = 0; i < drugIds.length; ) {
            uint256 drugId = drugIds[i];
            if (drugId != 0) {
                uint256 balance = core.getDrugBalance(defenderId, drugId);
                potentialDrugSteal += (balance * DRUG_STEAL_PERCENT) / 100;
            }
            unchecked { ++i; }
        }

        return (attackerThreat, defenderArmor, winChance, potentialDrugSteal);
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Updates the core contract address
     */
    function setCore(address _core) external onlyOwner {
        address old = address(core);
        core = IDealersExeCore(_core);
        emit CoreContractUpdated(old, _core);
    }

    /**
     * @notice Updates the NFT contract address
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        address old = address(nftContract);
        nftContract = IERC721Minimal(_nftContract);
        emit NFTContractUpdated(old, _nftContract);
    }

    /**
     * @notice Updates the Area Registry address
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }
}
