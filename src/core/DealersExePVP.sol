// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDealersExePVP} from "./IDealersExePVP.sol";
import {IDealersExeCore} from "./IDealersExeCore.sol";
import {IAreaRegistry} from "../utils/IAreaRegistry.sol";
import {IDrugRegistry} from "../utils/IDrugRegistry.sol";
import {IERC721Minimal} from "../utils/IERC721Minimal.sol";
import {IDERandomness} from "../utils/IDERandomness.sol";

/**
 * @title DealersExePVP - Player vs Player Combat Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Handles PVP gameplay with stat-based win chances, drug/cash stealing, and defender protection
 *      Uses AreaRegistry for drug availability per area
 * @author Dealers.Exe Team
 */
contract DealersExePVP is IDealersExePVP, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersExeCore public core;
    IERC721Minimal public nftContract;
    IAreaRegistry public areaRegistry;
    IDrugRegistry public drugRegistry;
    IDERandomness public randomness;

    bool public paused;
    PVPConfig public config;

    mapping(uint256 => uint256) public lastAttackDay;
    mapping(uint256 => uint256) public attacksReceivedToday;
    mapping(uint256 => PvpStats) public dealerPvpStats;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event PVPBattleResult(
        uint256 indexed attacker,
        uint256 indexed defender,
        bool attackerWon,
        uint256 drugIdStolen,
        uint256 drugsStolen,
        uint256 cashStolen,
        int16 attackerRepChange,
        int16 defenderRepChange
    );

    event DealerArrested(uint256 indexed tokenId, uint16 jailChance);
    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event AreaRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event DrugRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event RandomnessUpdated(address indexed oldRandomness, address indexed newRandomness);
    event Paused(address account);
    event Unpaused(address account);
    event PVPConfigUpdated(PVPConfig oldConfig, PVPConfig newConfig);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotDealerOwner();
    error DealerNotInitialized();
    error DealerInJail();
    error DealerInSafeHouse();
    error SameDealer();
    error DifferentArea();
    error ContractNotSet();
    error ContractPaused();
    error DefenderExhausted();
    error InsufficientReputation();
    error OutOfRepRange();

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

        config = PVPConfig({
            minReputation: 100,
            baseWinChance: 50,
            minWinChance: 25,
            maxWinChance: 75,
            maxAttacksPerDay: 3,
            drugStealPercent: 2,
            cashStealPercent: 1,
            rarityWeightCommon: 50,
            rarityWeightUncommon: 30,
            rarityWeightRare: 20,
            repRangePercent: 25,
            defenderRepBonus: 2
        });
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(core) == address(0) ||
            address(nftContract) == address(0) ||
            address(areaRegistry) == address(0) ||
            address(drugRegistry) == address(0) ||
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

    modifier reputable(uint256 tokenId) {
        if (config.minReputation > 0) {
            if (core.getTotalReputation(tokenId) < config.minReputation) revert InsufficientReputation();
        }
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
        reputable(attackerId)
        reputable(defenderId)
    {
        if (attackerId == defenderId) revert SameDealer();
        if (!_isInRepRange(core.getTotalReputation(attackerId), core.getTotalReputation(defenderId))) {
            revert OutOfRepRange();
        }

        uint8 area = _validateLocationsAndGetArea(attackerId, defenderId);

        _checkDefenderProtection(defenderId);

        core.useAttempt(attackerId);
        core.incrementHeatLevel(attackerId);

        _executeBattle(attackerId, defenderId, area);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    function getDealerPvpStats(uint256 tokenId) external view returns (PvpStats memory) {
        return dealerPvpStats[tokenId];
    }

    function calculateWinChance(uint256 attackerId, uint256 defenderId) public view returns (uint256) {
        (uint8 attackerThreat, ) = core.getDealerStats(attackerId);
        (, uint8 defenderArmor) = core.getDealerStats(defenderId);

        int256 statModifier = int256(uint256(attackerThreat)) - int256(uint256(defenderArmor));
        int256 finalChance = int256(uint256(config.baseWinChance)) + statModifier;

        if (finalChance < int256(uint256(config.minWinChance))) {
            return config.minWinChance;
        }
        if (finalChance > int256(uint256(config.maxWinChance))) {
            return config.maxWinChance;
        }

        return uint256(finalChance);
    }

    /**
     * @notice Check if an attack is possible between two dealers
     * @param attackerId The attacker's token ID
     * @param defenderId The defender's token ID
     * @return canFight Whether the attack can proceed
     * @return reason Error code: 0=OK, 1=same dealer, 2=attacker not init, 3=defender not init,
     *         4=attacker in jail, 5=attacker in safe house, 6=defender in jail, 7=defender in safe house,
     *         8=different areas, 9=no attempts, 10=defender exhausted,
     *         11=out of rep range, 12=below min reputation
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

        if (attackerAttempts == 0) return (false, 9);

        uint256 currentDay = block.timestamp / 1 days;
        if (lastAttackDay[defenderId] == currentDay && attacksReceivedToday[defenderId] >= config.maxAttacksPerDay) {
            return (false, 10);
        }

        uint256 attackerTotalRep = core.getTotalReputation(attackerId);
        uint256 defenderTotalRep = core.getTotalReputation(defenderId);

        if (!_isInRepRange(attackerTotalRep, defenderTotalRep)) return (false, 11);

        if (config.minReputation > 0) {
            if (attackerTotalRep < config.minReputation || defenderTotalRep < config.minReputation) {
                return (false, 12);
            }
        }

        return (true, 0);
    }

    function getPotentialTargets(
        uint256 attackerId,
        uint256 offset,
        uint256 limit
    ) external view returns (PVPTarget[] memory targets, uint256 totalInArea) {
        (uint8 attackerArea, , , , , bool attackerInit) = core.getDealerData(attackerId);
        if (!attackerInit) return (new PVPTarget[](0), 0);

        uint256 attackerRep = core.getTotalReputation(attackerId);

        (uint256[] memory dealersInArea, uint256 total) = areaRegistry.getDealersInArea(attackerArea, 0, type(uint256).max);
        totalInArea = total;

        if (total == 0 || limit == 0) return (new PVPTarget[](0), total);

        PVPTarget[] memory tempTargets = new PVPTarget[](total);
        uint256 matchCount = 0;

        for (uint256 i = 0; i < dealersInArea.length;) {
            uint256 tokenId = dealersInArea[i];

            if (tokenId == attackerId) {
                unchecked { ++i; }
                continue;
            }

            (,, uint8 attempts, , , bool init) = core.getDealerData(tokenId);

            if (!init) {
                unchecked { ++i; }
                continue;
            }

            uint256 rep = core.getTotalReputation(tokenId);

            if (config.minReputation > 0 && rep < config.minReputation) {
                unchecked { ++i; }
                continue;
            }

            if (!_isInRepRange(attackerRep, rep)) {
                unchecked { ++i; }
                continue;
            }

            if (core.isInJail(tokenId) || core.isInSafeHouse(tokenId)) {
                unchecked { ++i; }
                continue;
            }

            (uint8 threat, uint8 armor) = core.getDealerStats(tokenId);
            uint256 winChance = calculateWinChance(attackerId, tokenId);

            bool attackable = _canAttackTarget(attackerId, tokenId);

            tempTargets[matchCount] = PVPTarget({
                tokenId: tokenId,
                reputation: rep,
                threat: threat,
                armor: armor,
                attemptsRemaining: attempts,
                winChance: winChance,
                lossChance: 100 - winChance,
                canAttackNow: attackable
            });

            unchecked { ++matchCount; }
            unchecked { ++i; }
        }

        if (matchCount == 0) return (new PVPTarget[](0), total);

        if (offset >= matchCount) return (new PVPTarget[](0), total);

        uint256 end = offset + limit;
        if (end > matchCount) end = matchCount;
        uint256 resultLength = end - offset;

        targets = new PVPTarget[](resultLength);
        for (uint256 i = 0; i < resultLength;) {
            targets[i] = tempTargets[offset + i];
            unchecked { ++i; }
        }

        return (targets, total);
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
     * @notice Updates the Drug Registry address
     * @param _drugRegistry New Drug Registry address
     */
    function setDrugRegistry(address _drugRegistry) external onlyOwner {
        if (_drugRegistry == address(0)) revert ContractNotSet();
        address old = address(drugRegistry);
        drugRegistry = IDrugRegistry(_drugRegistry);
        emit DrugRegistryUpdated(old, _drugRegistry);
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
     * @notice Updates all PVP configuration parameters
     * @param _config New PVP configuration
     */
    function setPVPConfig(PVPConfig calldata _config) external onlyOwner {
        PVPConfig memory oldConfig = config;
        config = _config;
        emit PVPConfigUpdated(oldConfig, _config);
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

    function _canAttackTarget(uint256 attackerId, uint256 defenderId) private view returns (bool) {
        if (core.isInJail(attackerId) || core.isInSafeHouse(attackerId)) return false;

        (, , uint8 attackerAttempts, , , ) = core.getDealerData(attackerId);
        if (attackerAttempts == 0) return false;

        uint256 attackerTotalRep = core.getTotalReputation(attackerId);
        uint256 defenderTotalRep = core.getTotalReputation(defenderId);

        if (!_isInRepRange(attackerTotalRep, defenderTotalRep)) return false;

        if (config.minReputation > 0) {
            if (attackerTotalRep < config.minReputation || defenderTotalRep < config.minReputation) return false;
        }

        uint256 currentDay = block.timestamp / 1 days;
        if (lastAttackDay[defenderId] == currentDay && attacksReceivedToday[defenderId] >= config.maxAttacksPerDay) {
            return false;
        }

        return true;
    }

    function _isInRepRange(uint256 attackerRep, uint256 defenderRep) private view returns (bool) {
        uint256 range = attackerRep * config.repRangePercent / 100;
        uint256 minRep = attackerRep > range ? attackerRep - range : 0;
        uint256 maxRep = attackerRep + range;
        return defenderRep >= minRep && defenderRep <= maxRep;
    }

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
            if (attacksReceivedToday[defenderId] >= config.maxAttacksPerDay) {
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
            return;
        }

        uint256 winChance = calculateWinChance(attackerId, defenderId);
        bool attackerWon = ((battleRandomness >> 8) % 100) < winChance;

        unchecked {
            if (attackerWon) {
                dealerPvpStats[attackerId].attackWins++;
                dealerPvpStats[defenderId].defendLosses++;
            } else {
                dealerPvpStats[attackerId].attackLosses++;
                dealerPvpStats[defenderId].defendWins++;
            }
        }

        (uint256 drugIdStolen, uint256 drugsStolen, uint256 cashStolen, int16 attackerRepChange, int16 defenderRepChange) =
            _processBattleOutcome(attackerId, defenderId, attackerWon, area, battleRandomness);

        emit PVPBattleResult(
            attackerId,
            defenderId,
            attackerWon,
            drugIdStolen,
            drugsStolen,
            cashStolen,
            attackerRepChange,
            defenderRepChange
        );
    }

    function _checkAndProcessArrest(uint256 attackerId, uint256 rng) private returns (bool) {
        uint16 jailChance = core.getJailChance(attackerId);
        uint16 jailRoll = uint16(rng % 1000);

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
        uint8 area,
        uint256 battleRandomness
    ) private returns (uint256 drugIdStolen, uint256 drugsStolen, uint256 cashStolen, int16 attackerRepChange, int16 defenderRepChange) {
        if (attackerWon) {
            (drugIdStolen, drugsStolen) = _stealDrugs(attackerId, defenderId, area, battleRandomness);
            cashStolen = _stealCash(attackerId, defenderId);

            int16 attackerBaseRep = core.getReputationChange(attackerId, 0);
            uint8 attackerRepMultiplier = core.getRepMultiplier(attackerId);
            attackerRepChange = int16((int256(attackerBaseRep) * int256(uint256(attackerRepMultiplier))) / 100);
            defenderRepChange = core.getReputationChange(defenderId, 2);

            core.updateReputation(attackerId, int256(attackerRepChange));
            core.updateReputation(defenderId, int256(defenderRepChange));
        } else {
            attackerRepChange = core.getReputationChange(attackerId, 2);
            defenderRepChange = int16(int8(config.defenderRepBonus));

            core.updateReputation(attackerId, int256(attackerRepChange));
            core.updateReputation(defenderId, int256(defenderRepChange));
        }

        return (drugIdStolen, drugsStolen, cashStolen, attackerRepChange, defenderRepChange);
    }

    function _stealDrugs(
        uint256 winnerId,
        uint256 loserId,
        uint8 area,
        uint256 rng
    ) private returns (uint256 selectedDrugId, uint256 totalStolen) {
        uint256[] memory areaDrugIds = areaRegistry.getAreaDrugIds(area);

        uint256[] memory commonDrugs = new uint256[](areaDrugIds.length);
        uint256[] memory uncommonDrugs = new uint256[](areaDrugIds.length);
        uint256[] memory rareDrugs = new uint256[](areaDrugIds.length);
        uint256 commonCount;
        uint256 uncommonCount;
        uint256 rareCount;

        for (uint256 i = 0; i < areaDrugIds.length;) {
            uint256 drugId = areaDrugIds[i];
            if (drugId == 0) {
                unchecked { ++i; }
                continue;
            }

            uint256 balance = core.getDrugBalance(loserId, drugId);
            if (balance == 0) {
                unchecked { ++i; }
                continue;
            }

            IDrugRegistry.DrugRarity rarity = drugRegistry.getDrugRarity(drugId);

            if (rarity == IDrugRegistry.DrugRarity.COMMON) {
                commonDrugs[commonCount] = drugId;
                unchecked { ++commonCount; }
            } else if (rarity == IDrugRegistry.DrugRarity.UNCOMMON) {
                uncommonDrugs[uncommonCount] = drugId;
                unchecked { ++uncommonCount; }
            } else {
                rareDrugs[rareCount] = drugId;
                unchecked { ++rareCount; }
            }

            unchecked { ++i; }
        }

        if (commonCount == 0 && uncommonCount == 0 && rareCount == 0) {
            return (0, 0);
        }

        selectedDrugId = _selectDrugByRarity(
            rng,
            commonDrugs, commonCount,
            uncommonDrugs, uncommonCount,
            rareDrugs, rareCount
        );

        uint256 loserBalance = core.getDrugBalance(loserId, selectedDrugId);
        uint256 stolen = _ceilDiv(loserBalance * config.drugStealPercent, 100);

        if (stolen > 0) {
            core.updateDrugBalance(loserId, selectedDrugId, -int256(stolen));
            core.updateDrugBalance(winnerId, selectedDrugId, int256(stolen));
        }

        return (selectedDrugId, stolen);
    }

    function _stealCash(uint256 winnerId, uint256 loserId) private returns (uint256 stolen) {
        uint256 loserCash = core.getCashBalance(loserId);
        if (loserCash == 0) return 0;

        stolen = _ceilDiv(loserCash * config.cashStealPercent, 100);

        if (stolen > 0) {
            core.spendCash(loserId, stolen);
            core.addCash(winnerId, stolen);
        }

        return stolen;
    }

    function _selectDrugByRarity(
        uint256 rng,
        uint256[] memory commonDrugs,
        uint256 commonCount,
        uint256[] memory uncommonDrugs,
        uint256 uncommonCount,
        uint256[] memory rareDrugs,
        uint256 rareCount
    ) private view returns (uint256) {
        uint256 roll = (rng >> 16) % 100;

        if (roll < config.rarityWeightCommon && commonCount > 0) {
            return commonDrugs[(rng >> 24) % commonCount];
        } else if (roll < uint256(config.rarityWeightCommon) + uint256(config.rarityWeightUncommon) && uncommonCount > 0) {
            return uncommonDrugs[(rng >> 32) % uncommonCount];
        } else if (rareCount > 0) {
            return rareDrugs[(rng >> 40) % rareCount];
        }

        if (commonCount > 0) return commonDrugs[(rng >> 24) % commonCount];
        if (uncommonCount > 0) return uncommonDrugs[(rng >> 32) % uncommonCount];
        return rareDrugs[(rng >> 40) % rareCount];
    }

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
    }
}
