// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDealersExeCore} from "./IDealersExeCore.sol";
import {IAreaRegistry} from "../utils/IAreaRegistry.sol";
import {IERC721Minimal} from "../utils/IERC721Minimal.sol";
import {IDERandomness} from "../utils/IDERandomness.sol";

/**
 * @title DealersExePVP - Player vs Player Combat Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
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
    uint256 public constant DRUG_STEAL_PERCENT = 1;
    uint256 public constant ATTACK_COOLDOWN = 1 hours;
    uint256 public constant MAX_ATTACKS_PER_DAY = 3;

    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersExeCore public core;
    IERC721Minimal public nftContract;
    IAreaRegistry public areaRegistry;
    IDERandomness public randomness;

    bool public paused;

    mapping(uint256 => mapping(uint256 => uint256)) public lastAttackTime;

    mapping(uint256 => uint256) public lastAttackDay;
    mapping(uint256 => uint256) public attacksReceivedToday;

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
    event RandomnessUpdated(address indexed oldRandomness, address indexed newRandomness);
    event Paused(address account);
    event Unpaused(address account);

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
    error ContractPaused();
    error DefenderExhausted();

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
        if (_core == address(0) || _nftContract == address(0) || _areaRegistry == address(0)) {
            revert ContractNotSet();
        }
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
            address(areaRegistry) == address(0) ||
            address(randomness) == address(0)
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

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
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
        whenNotPaused
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

        _checkDefenderProtection(defenderId);

        core.useAttempt(attackerId);
        core.incrementHeatLevel(attackerId);

        _executeBattle(attackerId, defenderId, area);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Calculate win chance for an attack
     * @param attackerId The attacker's token ID
     * @param defenderId The defender's token ID
     * @return Win chance percentage (25-75)
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
     * @notice Check if an attack is possible between two dealers
     * @param attackerId The attacker's token ID
     * @param defenderId The defender's token ID
     * @return canFight Whether the attack can proceed
     * @return reason Error code if canFight is false (0=OK, 1=same dealer, 2=attacker not init, etc.)
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
     * @param attackerId The attacker's token ID
     * @param defenderId The defender's token ID
     * @return Seconds remaining until attack is allowed (0 if ready)
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
     * @notice Preview battle stats for UI
     * @param attackerId The attacker's token ID
     * @param defenderId The defender's token ID
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
     * @param _core New core contract address
     */
    function setCore(address _core) external onlyOwner {
        if (_core == address(0)) revert ContractNotSet();
        address old = address(core);
        core = IDealersExeCore(_core);
        emit CoreContractUpdated(old, _core);
    }

    /**
     * @notice Updates the NFT contract address
     * @param _nftContract New NFT contract address
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert ContractNotSet();
        address old = address(nftContract);
        nftContract = IERC721Minimal(_nftContract);
        emit NFTContractUpdated(old, _nftContract);
    }

    /**
     * @notice Updates the Area Registry address
     * @param _areaRegistry New Area Registry address
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert ContractNotSet();
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    /**
     * @notice Updates the Randomness contract address
     * @param _randomness New Randomness contract address
     */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert ContractNotSet();
        address old = address(randomness);
        randomness = IDERandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }

    /**
     * @notice Pauses the contract, preventing attacks
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the contract, allowing attacks
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // =============================================================
    //                     INTERNAL/PRIVATE HELPER FUNCTIONS
    // =============================================================

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

    function _checkDefenderProtection(uint256 defenderId) private {
        uint256 currentDay = block.timestamp / 1 days;

        if (lastAttackDay[defenderId] != currentDay) {
            lastAttackDay[defenderId] = currentDay;
            attacksReceivedToday[defenderId] = 1;
        } else {
            if (attacksReceivedToday[defenderId] >= MAX_ATTACKS_PER_DAY) {
                revert DefenderExhausted();
            }
            unchecked {
                ++attacksReceivedToday[defenderId];
            }
        }
    }

    function _executeBattle(uint256 attackerId, uint256 defenderId, uint8 area) private {
        bytes32 seed = keccak256(abi.encodePacked(attackerId, defenderId, block.timestamp));
        uint256 battleRandomness = randomness.getRandomness(seed);

        if (_checkAndProcessArrest(attackerId, battleRandomness)) {
            lastAttackTime[attackerId][defenderId] = block.timestamp;
            return;
        }

        uint256 winChance = calculateWinChance(attackerId, defenderId);
        bool attackerWon = ((battleRandomness >> 8) % 100) < winChance;

        (uint256 drugsStolen, int16 attackerRepChange, int16 defenderRepChange) =
            _processBattleOutcome(attackerId, defenderId, attackerWon, area);

        lastAttackTime[attackerId][defenderId] = block.timestamp;

        emit PVPBattleResult(
            attackerId,
            defenderId,
            attackerWon,
            drugsStolen,
            attackerRepChange,
            defenderRepChange
        );
    }

    function _checkAndProcessArrest(uint256 attackerId, uint256 rng) private returns (bool) {
        uint8 jailChance = core.getJailChance(attackerId);
        uint8 jailRoll = uint8(rng % 100);

        if (jailRoll < jailChance) {
            core.sendToJail(attackerId);

            emit DealerArrested(attackerId, jailChance);
            return true;
        }
        return false;
    }

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

    function _stealDrugs(uint256 winnerId, uint256 loserId, uint8 area) private returns (uint256 totalStolen) {
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
}
