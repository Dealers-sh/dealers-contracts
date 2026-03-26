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

    uint256[3] public dropDrugIds;

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

    event LootDropped(uint256 indexed attackerId, uint256 indexed drugId);

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
    error NoAttemptsRemaining();
    error InvalidPVPConfig();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

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
            rarityWeightCommon: 75,
            rarityWeightUncommon: 20,
            rarityWeightRare: 5,
            repRangePercent: 25,
            defenderRepBonus: 2
        });

        dropDrugIds = [uint256(1), 2, 3];
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

    function attack(uint256 attackerId, uint256 defenderId)
        external
        nonReentrant
        whenNotPaused
        contractsSet
        onlyDealerOwner(attackerId)
    {
        if (attackerId == defenderId) revert SameDealer();

        (IDealersExeCore.GameState memory atkState, IDealersExeCore.GameState memory defState) =
            core.getBothGameStates(attackerId, defenderId);

        if (!atkState.isInitialized) revert DealerNotInitialized();
        if (!defState.isInitialized) revert DealerNotInitialized();

        if (atkState.isJailed) revert DealerInJail();
        if (atkState.isInSafeHouse) revert DealerInSafeHouse();
        if (defState.isJailed) revert DealerInJail();
        if (defState.isInSafeHouse) revert DealerInSafeHouse();

        if (atkState.currentArea != defState.currentArea) revert DifferentArea();
        if (atkState.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();

        if (config.minReputation > 0) {
            if (atkState.totalReputation < config.minReputation) revert InsufficientReputation();
            if (defState.totalReputation < config.minReputation) revert InsufficientReputation();
        }

        if (!_isInRepRange(atkState.totalReputation, defState.totalReputation)) {
            revert OutOfRepRange();
        }

        _checkDefenderProtection(defenderId);

        _executeBattle(attackerId, defenderId, atkState, defState);
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

        return _calcWinChance(attackerThreat, defenderArmor);
    }

    function canAttack(uint256 attackerId, uint256 defenderId) external view returns (bool canFight, uint8 reason) {
        if (attackerId == defenderId) return (false, 1);

        (IDealersExeCore.GameState memory atkState, IDealersExeCore.GameState memory defState) =
            core.getBothGameStates(attackerId, defenderId);

        if (!atkState.isInitialized) return (false, 2);
        if (!defState.isInitialized) return (false, 3);

        if (atkState.isJailed) return (false, 4);
        if (atkState.isInSafeHouse) return (false, 5);
        if (defState.isJailed) return (false, 6);
        if (defState.isInSafeHouse) return (false, 7);

        if (atkState.currentArea != defState.currentArea) return (false, 8);

        if (atkState.dailyAttemptsRemaining == 0) return (false, 9);

        uint256 currentDay = block.timestamp / 1 days;
        if (lastAttackDay[defenderId] == currentDay && attacksReceivedToday[defenderId] >= config.maxAttacksPerDay) {
            return (false, 10);
        }

        if (!_isInRepRange(atkState.totalReputation, defState.totalReputation)) return (false, 11);

        if (config.minReputation > 0) {
            if (atkState.totalReputation < config.minReputation || defState.totalReputation < config.minReputation) {
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
        IDealersExeCore.GameState memory atkState = core.getGameState(attackerId);
        if (!atkState.isInitialized) return (new PVPTarget[](0), 0);

        (uint256[] memory dealersInArea, uint256 total) = areaRegistry.getDealersInArea(atkState.currentArea, 0, type(uint256).max);
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

            IDealersExeCore.GameState memory candState = core.getGameState(tokenId);

            if (!candState.isInitialized || candState.isJailed || candState.isInSafeHouse) {
                unchecked { ++i; }
                continue;
            }

            if (config.minReputation > 0 && candState.totalReputation < config.minReputation) {
                unchecked { ++i; }
                continue;
            }

            if (!_isInRepRange(atkState.totalReputation, candState.totalReputation)) {
                unchecked { ++i; }
                continue;
            }

            uint256 winChancePct = _calcWinChance(atkState.threat, candState.armor);

            bool attackable = _isDefenderAvailable(tokenId);

            tempTargets[matchCount] = PVPTarget({
                tokenId: tokenId,
                reputation: candState.totalReputation,
                threat: candState.threat,
                armor: candState.armor,
                attemptsRemaining: candState.dailyAttemptsRemaining,
                winChance: winChancePct,
                lossChance: 100 - winChancePct,
                canAttackNow: attackable,
                infamy: candState.infamy
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

    function setCore(address _core) external onlyOwner {
        if (_core == address(0)) revert ContractNotSet();
        address old = address(core);
        core = IDealersExeCore(_core);
        emit CoreContractUpdated(old, _core);
    }

    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert ContractNotSet();
        address old = address(nftContract);
        nftContract = IERC721Minimal(_nftContract);
        emit NFTContractUpdated(old, _nftContract);
    }

    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert ContractNotSet();
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    function setDrugRegistry(address _drugRegistry) external onlyOwner {
        if (_drugRegistry == address(0)) revert ContractNotSet();
        address old = address(drugRegistry);
        drugRegistry = IDrugRegistry(_drugRegistry);
        emit DrugRegistryUpdated(old, _drugRegistry);
    }

    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert ContractNotSet();
        address old = address(randomness);
        randomness = IDERandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }

    function setPVPConfig(PVPConfig calldata _config) external onlyOwner {
        if (_config.maxWinChance > 100) revert InvalidPVPConfig();

        PVPConfig memory oldConfig = config;
        config = _config;
        emit PVPConfigUpdated(oldConfig, _config);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // =============================================================
    //                     INTERNAL/PRIVATE HELPER FUNCTIONS
    // =============================================================

    function _isDefenderAvailable(uint256 defenderId) private view returns (bool) {
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

    function _calcWinChance(uint8 attackerThreat, uint8 defenderArmor) private view returns (uint256) {
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

    function _executeBattle(
        uint256 attackerId,
        uint256 defenderId,
        IDealersExeCore.GameState memory atkState,
        IDealersExeCore.GameState memory defState
    ) private {
        bytes32 seed = keccak256(abi.encodePacked(attackerId, defenderId, block.timestamp));
        uint256[] memory rng = randomness.getRandomValues(seed, 4);

        IDealersExeCore.GameOutcome memory atkOut;
        atkOut.useAttempt = true;
        atkOut.incrementHeat = true;

        if (_rollPvpJailCheck(atkState, rng[0])) {
            atkOut.sendToJail = true;
            core.applyGameOutcome(attackerId, atkOut);
            emit DealerArrested(attackerId, atkState.jailChance);
            return;
        }

        uint256 winChancePct = _calcWinChance(atkState.threat, defState.armor);
        bool attackerWon = (rng[1] % 100) < winChancePct;

        unchecked {
            if (attackerWon) {
                dealerPvpStats[attackerId].attackWins++;
                dealerPvpStats[defenderId].defendLosses++;
            } else {
                dealerPvpStats[attackerId].attackLosses++;
                dealerPvpStats[defenderId].defendWins++;
            }
        }

        IDealersExeCore.GameOutcome memory defOut;

        uint256 drugIdStolen;
        uint256 drugsStolen;
        uint256 cashStolen;
        int16 attackerRepChange;
        int16 defenderRepChange;

        if (attackerWon) {
            (drugIdStolen, drugsStolen) = _computeDrugSteal(defenderId, atkState.currentArea, rng[2]);
            cashStolen = _computeCashSteal(defState.cashBalance);

            int256 repResult = (int256(atkState.repWinBonus) * int256(uint256(atkState.repMultiplier))) / 100;
            if (repResult > type(int16).max) repResult = type(int16).max;
            if (repResult < type(int16).min) repResult = type(int16).min;
            attackerRepChange = int16(repResult);
            defenderRepChange = defState.repLossPenalty;

            atkOut.repDelta = int256(attackerRepChange);

            defOut.repDelta = int256(defenderRepChange);

            if (drugsStolen > 0) {
                atkOut.drugId = drugIdStolen;
                atkOut.drugDelta = int256(drugsStolen);
                defOut.drugId = drugIdStolen;
                defOut.drugDelta = -int256(drugsStolen);
            }

            if (cashStolen > 0) {
                atkOut.cashDelta = int256(cashStolen);
                defOut.cashDelta = -int256(cashStolen);
            }
        } else {
            attackerRepChange = int16(atkState.repLossPenalty);
            defenderRepChange = int16(uint16(config.defenderRepBonus));

            atkOut.repDelta = int256(attackerRepChange);
            defOut.repDelta = int256(defenderRepChange);
        }

        core.applyPVPOutcome(attackerId, defenderId, atkOut, defOut);

        if (attackerWon) {
            core.updateInfamy(attackerId, 3);
            _applyDropReward(attackerId, rng[3], atkState.infamy);
        } else {
            core.updateInfamy(attackerId, -1);
        }

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

    function _rollPvpJailCheck(IDealersExeCore.GameState memory state, uint256 rng) private pure returns (bool) {
        uint16 heatChance = state.jailChance;
        uint16 infamyChance = _calcInfamyJailBonus(state.infamy);
        uint16 totalChance = heatChance + infamyChance;
        return uint16(rng % 1000) < totalChance;
    }

    function _calcInfamyJailBonus(uint256 infamy) private pure returns (uint16) {
        uint256 bonus = (infamy / 10) * 5;
        return bonus > 25 ? 25 : uint16(bonus);
    }

    function _getInfamyDropWeights(uint256 infamy) private pure returns (uint8[4] memory) {
        if (infamy >= 50) return [uint8(15), 30, 35, 20];
        if (infamy >= 40) return [uint8(20), 35, 30, 15];
        if (infamy >= 30) return [uint8(25), 40, 25, 10];
        if (infamy >= 20) return [uint8(30), 45, 20, 5];
        if (infamy >= 10) return [uint8(35), 50, 15, 0];
        return [uint8(40), 60, 0, 0];
    }

    function _applyDropReward(uint256 attackerId, uint256 rng, uint256 infamy) private {
        uint8[4] memory weights = _getInfamyDropWeights(infamy);
        uint256 roll = rng % 100;
        if (roll < weights[0]) return;

        uint256 cumulative = weights[0];
        for (uint256 i = 0; i < 3;) {
            cumulative += weights[i + 1];
            if (roll < cumulative) {
                uint256 drugId = dropDrugIds[i];
                if (drugId != 0) {
                    core.updateDrugBalance(attackerId, drugId, 1);
                    emit LootDropped(attackerId, drugId);
                }
                return;
            }
            unchecked { ++i; }
        }
    }

    function _computeDrugSteal(
        uint256 loserId,
        uint8 area,
        uint256 rng
    ) private view returns (uint256 selectedDrugId, uint256 totalStolen) {
        uint256[] memory areaDrugIds = areaRegistry.getAreaDrugIds(area);
        uint256[] memory balances = core.getAreaDrugBalances(loserId, areaDrugIds);

        uint256[] memory commonDrugs = new uint256[](areaDrugIds.length);
        uint256[] memory commonBalances = new uint256[](areaDrugIds.length);
        uint256[] memory uncommonDrugs = new uint256[](areaDrugIds.length);
        uint256[] memory uncommonBalances = new uint256[](areaDrugIds.length);
        uint256[] memory rareDrugs = new uint256[](areaDrugIds.length);
        uint256[] memory rareBalances = new uint256[](areaDrugIds.length);
        uint256 commonCount;
        uint256 uncommonCount;
        uint256 rareCount;

        for (uint256 i = 0; i < areaDrugIds.length;) {
            uint256 drugId = areaDrugIds[i];
            if (drugId == 0 || balances[i] == 0) {
                unchecked { ++i; }
                continue;
            }

            IDrugRegistry.DrugRarity rarity = drugRegistry.getDrugRarity(drugId);

            if (rarity == IDrugRegistry.DrugRarity.COMMON) {
                commonDrugs[commonCount] = drugId;
                commonBalances[commonCount] = balances[i];
                unchecked { ++commonCount; }
            } else if (rarity == IDrugRegistry.DrugRarity.UNCOMMON) {
                uncommonDrugs[uncommonCount] = drugId;
                uncommonBalances[uncommonCount] = balances[i];
                unchecked { ++uncommonCount; }
            } else {
                rareDrugs[rareCount] = drugId;
                rareBalances[rareCount] = balances[i];
                unchecked { ++rareCount; }
            }

            unchecked { ++i; }
        }

        if (commonCount == 0 && uncommonCount == 0 && rareCount == 0) {
            return (0, 0);
        }

        uint256 loserBalance;
        (selectedDrugId, loserBalance) = _selectDrugByRarity(
            rng,
            commonDrugs, commonBalances, commonCount,
            uncommonDrugs, uncommonBalances, uncommonCount,
            rareDrugs, rareBalances, rareCount
        );

        uint256 stolen = _ceilDiv(loserBalance * config.drugStealPercent, 100);

        return (selectedDrugId, stolen);
    }

    function _computeCashSteal(uint256 loserCash) private view returns (uint256) {
        if (loserCash == 0) return 0;
        return _ceilDiv(loserCash * config.cashStealPercent, 100);
    }

    function _selectDrugByRarity(
        uint256 rng,
        uint256[] memory commonDrugs,
        uint256[] memory commonBalances,
        uint256 commonCount,
        uint256[] memory uncommonDrugs,
        uint256[] memory uncommonBalances,
        uint256 uncommonCount,
        uint256[] memory rareDrugs,
        uint256[] memory rareBalances,
        uint256 rareCount
    ) private view returns (uint256, uint256) {
        uint256 roll = rng % 100;
        uint256 pickRng = uint256(keccak256(abi.encodePacked(rng)));
        uint256 idx;

        if (roll < config.rarityWeightCommon && commonCount > 0) {
            idx = pickRng % commonCount;
            return (commonDrugs[idx], commonBalances[idx]);
        } else if (roll < uint256(config.rarityWeightCommon) + uint256(config.rarityWeightUncommon) && uncommonCount > 0) {
            idx = pickRng % uncommonCount;
            return (uncommonDrugs[idx], uncommonBalances[idx]);
        } else if (rareCount > 0) {
            idx = pickRng % rareCount;
            return (rareDrugs[idx], rareBalances[idx]);
        }

        if (commonCount > 0) {
            idx = pickRng % commonCount;
            return (commonDrugs[idx], commonBalances[idx]);
        }
        if (uncommonCount > 0) {
            idx = pickRng % uncommonCount;
            return (uncommonDrugs[idx], uncommonBalances[idx]);
        }
        idx = pickRng % rareCount;
        return (rareDrugs[idx], rareBalances[idx]);
    }

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
    }
}
