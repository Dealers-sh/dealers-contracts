// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
contract DealersExePVP is ReentrancyGuard, Ownable {
    // =============================================================
    //                            STRUCTS
    // =============================================================

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

    // =============================================================
    //                            EVENTS
    // =============================================================

    event PVPBattleResult(
        uint256 indexed attacker,
        uint256 indexed defender,
        bool attackerWon,
        uint256 drugsStolen,
        uint256 cashStolen,
        int16 attackerRepChange,
        int16 defenderRepChange
    );

    event DealerArrested(uint256 indexed tokenId, uint8 heatLevel);
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
            rarityWeightRare: 20
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
            (, uint256 rep,,,,) = core.getDealerData(tokenId);
            if (rep < config.minReputation) revert InsufficientReputation();
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

        uint8 area = _validateLocationsAndGetArea(attackerId, defenderId);

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
     *         11=attacker low rep, 12=defender low rep
     */
    function canAttack(uint256 attackerId, uint256 defenderId) external view returns (bool canFight, uint8 reason) {
        if (attackerId == defenderId) return (false, 1);

        (, uint256 attackerRep, uint8 attackerAttempts, , , bool attackerInit) = core.getDealerData(attackerId);
        if (!attackerInit) return (false, 2);

        (, uint256 defenderRep, , , , bool defenderInit) = core.getDealerData(defenderId);
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

        if (config.minReputation > 0) {
            if (attackerRep < config.minReputation) return (false, 11);
            if (defenderRep < config.minReputation) return (false, 12);
        }

        return (true, 0);
    }

    /**
     * @notice Get potential PVP targets for a dealer
     * @param attackerId The attacker's token ID
     * @param minReputation Minimum reputation filter (0 for no minimum)
     * @param maxReputation Maximum reputation filter (0 for no maximum)
     * @param offset Pagination offset
     * @param limit Maximum number of results to return
     * @return targets Array of potential targets with full stats
     * @return totalInArea Total number of dealers in the attacker's area
     */
    function getPotentialTargets(
        uint256 attackerId,
        uint256 minReputation,
        uint256 maxReputation,
        uint256 offset,
        uint256 limit
    ) external view returns (PVPTarget[] memory targets, uint256 totalInArea) {
        (uint8 attackerArea, , , , , bool attackerInit) = core.getDealerData(attackerId);
        if (!attackerInit) return (new PVPTarget[](0), 0);

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

            (, uint256 rep, uint8 attempts, , , bool init) = core.getDealerData(tokenId);

            if (!init) {
                unchecked { ++i; }
                continue;
            }

            if (config.minReputation > 0 && rep < config.minReputation) {
                unchecked { ++i; }
                continue;
            }

            if (minReputation > 0 && rep < minReputation) {
                unchecked { ++i; }
                continue;
            }
            if (maxReputation > 0 && rep > maxReputation) {
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

        (, uint256 attackerRep, uint8 attackerAttempts, , , ) = core.getDealerData(attackerId);
        if (attackerAttempts == 0) return false;

        if (config.minReputation > 0) {
            if (attackerRep < config.minReputation) return false;
            (, uint256 defenderRep,,,,) = core.getDealerData(defenderId);
            if (defenderRep < config.minReputation) return false;
        }

        uint256 currentDay = block.timestamp / 1 days;
        if (lastAttackDay[defenderId] == currentDay && attacksReceivedToday[defenderId] >= config.maxAttacksPerDay) {
            return false;
        }

        return true;
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

        (uint256 drugsStolen, uint256 cashStolen, int16 attackerRepChange, int16 defenderRepChange) =
            _processBattleOutcome(attackerId, defenderId, attackerWon, area, battleRandomness);

        emit PVPBattleResult(
            attackerId,
            defenderId,
            attackerWon,
            drugsStolen,
            cashStolen,
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
        uint8 area,
        uint256 battleRandomness
    ) private returns (uint256 drugsStolen, uint256 cashStolen, int16 attackerRepChange, int16 defenderRepChange) {
        uint256 winnerId;
        uint256 loserId;

        if (attackerWon) {
            winnerId = attackerId;
            loserId = defenderId;
        } else {
            winnerId = defenderId;
            loserId = attackerId;
        }

        drugsStolen = _stealDrugs(winnerId, loserId, area, battleRandomness);
        cashStolen = _stealCash(winnerId, loserId);

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

        return (drugsStolen, cashStolen, attackerRepChange, defenderRepChange);
    }

    function _stealDrugs(
        uint256 winnerId,
        uint256 loserId,
        uint8 area,
        uint256 rng
    ) private returns (uint256 totalStolen) {
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
            return 0;
        }

        uint256 selectedDrugId = _selectDrugByRarity(
            rng,
            commonDrugs, commonCount,
            uncommonDrugs, uncommonCount,
            rareDrugs, rareCount
        );

        uint256 loserBalance = core.getDrugBalance(loserId, selectedDrugId);
        uint256 stolen = _ceilDiv(loserBalance * config.drugStealPercent, 100);

        if (stolen > 0) {
            uint256 transferred = stolen / 2;

            core.updateDrugBalance(loserId, selectedDrugId, -int256(stolen));
            if (transferred > 0) {
                core.updateDrugBalance(winnerId, selectedDrugId, int256(transferred));
            }
        }

        return stolen;
    }

    function _stealCash(uint256 winnerId, uint256 loserId) private returns (uint256 stolen) {
        uint256 loserCash = core.getCashBalance(loserId);
        if (loserCash == 0) return 0;

        stolen = _ceilDiv(loserCash * config.cashStealPercent, 100);

        if (stolen > 0) {
            uint256 transferred = stolen / 2;

            core.spendCash(loserId, stolen);
            if (transferred > 0) {
                core.addCash(winnerId, transferred);
            }
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
