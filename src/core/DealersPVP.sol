// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDealersPVP} from "./IDealersPVP.sol";
import {IDealersCore} from "./IDealersCore.sol";
import {IAreaRegistry} from "../utils/IAreaRegistry.sol";
import {IDrugRegistry} from "../utils/IDrugRegistry.sol";
import {IERC721Minimal} from "../utils/IERC721Minimal.sol";
import {IDealersRandomness} from "../utils/IDealersRandomness.sol";
import {IActionsArrest} from "../utils/IActionsArrest.sol";

/**
 * @title DealersPVP - Player vs Player Battle Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Same-area PVP battles where dealers steal drugs and cash from each other.
 *      Win chance is 50% + (threat - armor), capped between 25-75%.
 *      Defenders have daily attack limits. Winners earn infamy and loot drops.
 * @author Berny0x
 */
contract DealersPVP is IDealersPVP, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersCore public core;
    IERC721Minimal public nftContract;
    IAreaRegistry public areaRegistry;
    IDrugRegistry public drugRegistry;
    IDealersRandomness public randomness;
    IActionsArrest public actions;

    bool public paused;
    PVPConfig internal _config;

    /**
     * @notice Drug-registry IDs reserved as PVP loot-drop rewards
     * @dev Mirrors the order drugs are seeded in the deployment script (Goods/Contraband/Jewels).
 */
    uint256 public constant LOOT_DRUG_GOODS = 1;
    uint256 public constant LOOT_DRUG_CONTRABAND = 2;
    uint256 public constant LOOT_DRUG_JEWELS = 3;

    mapping(uint256 => uint256) public lastAttackDay;
    mapping(uint256 => uint256) public attacksReceivedToday;
    mapping(uint256 => PvpStats) public dealerPvpStats;

    uint256[3] public dropDrugIds;

    /** @dev Only `areaAtCommit` is snapshotted — it locks which drug catalog the steal */
    /**      is computed against so a defender can't dodge by travelling. Combat stats */
    /**      (threat/armor/jailChance/infamy/rep) and balances (cash/drugs) are read */
    /**      live at resolve. Intentional: the protocol's paid heat-reduction */
    /**      (bribeCop / payBail) is revenue, and any defender self-mitigation via PVE */
    /**      escrow is economically worse than the 2% steal it would dodge. */
    struct PvpRound {
        uint256 attackerId;
        uint256 defenderId;
        uint8 areaAtCommit;
    }

    mapping(uint64 => PvpRound) public pendingPvpRounds;
    mapping(uint256 => uint64) public activePvpRoundOf;

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
        int16 defenderRepChange,
        int16 attackerInfamyChange,
        uint16 winChancePct,
        uint8 newHeatLevelAttacker
    );

    event LootDropped(uint256 indexed attackerId, uint256 indexed drugId);

    event PvpCommitted(
        uint64 indexed seq,
        uint256 indexed attackerId,
        uint256 indexed defenderId,
        uint8 attackerThreat,
        uint8 defenderArmor,
        uint16 winChancePct,
        uint16 attackerJailChance
    );
    event PvpExpired(uint64 indexed seq, uint256 indexed attackerId);
    event PvpAttackerJailedExternally(uint64 indexed seq, uint256 indexed attackerId);

    event DealerArrested(uint256 indexed tokenId, uint16 jailChance);
    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event AreaRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event DrugRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event RandomnessUpdated(address indexed oldRandomness, address indexed newRandomness);
    event ActionsUpdated(address indexed oldActions, address indexed newActions);
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
    error InvalidAddress();
    error RoundPending();
    error UnknownRound();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor(address _core, address _nftContract, address _areaRegistry) {
        if (_core == address(0) || _nftContract == address(0) || _areaRegistry == address(0)) {
            revert ContractNotSet();
        }
        _initializeOwner(msg.sender);
        core = IDealersCore(_core);
        nftContract = IERC721Minimal(_nftContract);
        areaRegistry = IAreaRegistry(_areaRegistry);

        _config = PVPConfig({
            minReputation: 200,
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
            defenderRepBonus: 2,
            repRangeThreshold: 22000
        });

        dropDrugIds = [LOOT_DRUG_GOODS, LOOT_DRUG_CONTRABAND, LOOT_DRUG_JEWELS];
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
            address(randomness) == address(0) ||
            address(actions) == address(0)
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

    /**
     * @notice Commit a PVP attack; outcome resolved later. Debits attacker's attempt
     *         and applies the per-defender daily-attack-rate limiter at commit time.
 */
    function commitAttack(uint256 attackerId, uint256 defenderId)
        external
        nonReentrant
        whenNotPaused
        contractsSet
        onlyDealerOwner(attackerId)
        returns (uint64 seq)
    {
        (IDealersCore.GameState memory atkState, IDealersCore.GameState memory defState) =
            _validateCommitAttack(attackerId, defenderId);

        _checkDefenderProtection(defenderId);

        IDealersCore.GameOutcome memory commitOutcome;
        commitOutcome.useAttempt = true;
        core.applyGameOutcome(attackerId, commitOutcome);

        seq = randomness.commit();
        pendingPvpRounds[seq] = PvpRound({
            attackerId: attackerId,
            defenderId: defenderId,
            areaAtCommit: atkState.currentArea
        });
        activePvpRoundOf[attackerId] = seq;

        emit PvpCommitted(
            seq,
            attackerId,
            defenderId,
            atkState.threat,
            defState.armor,
            uint16(_calcWinChance(atkState.threat, defState.armor)),
            atkState.jailChance
        );
    }

    function _validateCommitAttack(uint256 attackerId, uint256 defenderId)
        private
        view
        returns (IDealersCore.GameState memory atkState, IDealersCore.GameState memory defState)
    {
        if (attackerId == defenderId) revert SameDealer();
        if (activePvpRoundOf[attackerId] != 0) revert RoundPending();

        (atkState, defState) = core.getBothGameStates(attackerId, defenderId);

        if (!atkState.isInitialized) revert DealerNotInitialized();
        if (!defState.isInitialized) revert DealerNotInitialized();

        if (atkState.isJailed) revert DealerInJail();
        if (atkState.isInSafeHouse) revert DealerInSafeHouse();
        if (defState.isJailed) revert DealerInJail();
        if (defState.isInSafeHouse) revert DealerInSafeHouse();

        if (atkState.currentArea != defState.currentArea) revert DifferentArea();
        if (atkState.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();

        if (_config.minReputation > 0) {
            if (atkState.totalReputation < _config.minReputation) revert InsufficientReputation();
            if (defState.totalReputation < _config.minReputation) revert InsufficientReputation();
        }

        if (!_isInRepRange(atkState.totalReputation, defState.totalReputation)) {
            revert OutOfRepRange();
        }
    }

    /**
     * @notice Resolve a previously committed PVP attack. Anyone may call.
     * @dev Combat stats and balances are read live — see `PvpRound` natspec for why.
     *      Expiry is settled as an attacker LOSS — closes the simulate-then-skip flaw
     *      that let the attacker dodge rep loss / heat / infamy by waiting out a bad roll.
     *      If the attacker is jailed by some other action between commit and resolve,
     *      the round is cleaned up with no payout.
 */
    function resolveAttack(uint64 seq) external nonReentrant {
        PvpRound memory r = pendingPvpRounds[seq];
        if (r.attackerId == 0) revert UnknownRound();

        delete pendingPvpRounds[seq];
        delete activePvpRoundOf[r.attackerId];

        if (randomness.isExpired(seq)) {
            _refundDefenderSlot(r.defenderId);
            _applyExpiryAsLoss(r);
            emit PvpExpired(seq, r.attackerId);
            return;
        }

        (IDealersCore.GameState memory atk, IDealersCore.GameState memory def) =
            core.getBothGameStates(r.attackerId, r.defenderId);
        if (atk.isJailed) {
            _refundDefenderSlot(r.defenderId);
            emit PvpAttackerJailedExternally(seq, r.attackerId);
            return;
        }

        uint256 rand = randomness.reveal(seq);
        _executeBattle(r, atk, def, rand);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Read the PVP config struct
     * @dev Returns the struct (not a positional tuple) so consumers reference fields by name.
 */
    function config() external view returns (PVPConfig memory) {
        return _config;
    }

    /**
     * @notice Get a dealer's PVP attack/defend win/loss record
     * @param tokenId The dealer NFT token ID
     * @return PVP statistics for the dealer
 */
    function getDealerPvpStats(uint256 tokenId) external view returns (PvpStats memory) {
        return dealerPvpStats[tokenId];
    }

    /**
     * @notice Calculate the attacker's win probability against a defender
     * @param attackerId The attacker's dealer NFT token ID
     * @param defenderId The defender's dealer NFT token ID
     * @return Win chance as a percentage (25-75)
 */
    function calculateWinChance(uint256 attackerId, uint256 defenderId) public view returns (uint256) {
        (uint8 attackerThreat, ) = core.getDealerStats(attackerId);
        (, uint8 defenderArmor) = core.getDealerStats(defenderId);

        return _calcWinChance(attackerThreat, defenderArmor);
    }

    /**
     * @notice Check whether an attack is possible between two dealers
     * @param attackerId The attacker's dealer NFT token ID
     * @param defenderId The defender's dealer NFT token ID
     * @return canFight True if the attack can proceed
     * @return reason 0 = can attack, 1-12 = specific blocker (same dealer, not init, jailed, etc.)
 */
    function canAttack(uint256 attackerId, uint256 defenderId) external view returns (bool canFight, uint8 reason) {
        if (attackerId == defenderId) return (false, 1);

        (IDealersCore.GameState memory atkState, IDealersCore.GameState memory defState) =
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
        if (lastAttackDay[defenderId] == currentDay && attacksReceivedToday[defenderId] >= _config.maxAttacksPerDay) {
            return (false, 10);
        }

        if (!_isInRepRange(atkState.totalReputation, defState.totalReputation)) return (false, 11);

        if (_config.minReputation > 0) {
            if (atkState.totalReputation < _config.minReputation || defState.totalReputation < _config.minReputation) {
                return (false, 12);
            }
        }

        return (true, 0);
    }

    /**
     * @notice Get paginated list of valid PVP targets in the attacker's current area
     * @param attackerId The attacker's dealer NFT token ID
     * @param offset Number of matches to skip (for pagination)
     * @param limit Maximum number of targets to return
     * @return targets Array of attackable dealers with stats and win chances
     * @return totalInArea Total dealers in the area (before filtering)
 */
    function getPotentialTargets(
        uint256 attackerId,
        uint256 offset,
        uint256 limit
    ) external view returns (PVPTarget[] memory targets, uint256 totalInArea) {
        IDealersCore.GameState memory atkState = core.getGameState(attackerId);
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

            IDealersCore.GameState memory candState = core.getGameState(tokenId);

            if (!candState.isInitialized || candState.isJailed || candState.isInSafeHouse) {
                unchecked { ++i; }
                continue;
            }

            if (_config.minReputation > 0 && candState.totalReputation < _config.minReputation) {
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

    /**
     * @notice Set the core state contract
     * @param _core Address of the DealersCore contract
 */
    function setCore(address _core) external onlyOwner {
        if (_core == address(0)) revert ContractNotSet();
        address old = address(core);
        core = IDealersCore(_core);
        emit CoreContractUpdated(old, _core);
    }

    /**
     * @notice Set the NFT contract used for ownership checks
     * @param _nftContract Address of the DealersNFT contract
 */
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert ContractNotSet();
        address old = address(nftContract);
        nftContract = IERC721Minimal(_nftContract);
        emit NFTContractUpdated(old, _nftContract);
    }

    /**
     * @notice Set the area registry contract
     * @param _areaRegistry Address of the DealersAreaRegistry contract
 */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert ContractNotSet();
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    /**
     * @notice Set the drug registry contract
     * @param _drugRegistry Address of the DealersDrugRegistry contract
 */
    function setDrugRegistry(address _drugRegistry) external onlyOwner {
        if (_drugRegistry == address(0)) revert ContractNotSet();
        address old = address(drugRegistry);
        drugRegistry = IDrugRegistry(_drugRegistry);
        emit DrugRegistryUpdated(old, _drugRegistry);
    }

    /**
     * @notice Set the randomness provider contract
     * @param _randomness Address of the DealersRandomness contract
 */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert ContractNotSet();
        address old = address(randomness);
        randomness = IDealersRandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }

    /**
     * @notice Set the DealersActions contract used to delegate arrest policy
     * @param _actions Address of the DealersActions contract
 */
    function setActions(address _actions) external onlyOwner {
        if (_actions == address(0)) revert InvalidAddress();
        address old = address(actions);
        actions = IActionsArrest(_actions);
        emit ActionsUpdated(old, _actions);
    }

    /**
     * @notice Update the full PVP configuration (win chances, steal rates, rep range, etc.)
     * @param newConfig New PVP config struct
 */
    function setPVPConfig(PVPConfig calldata newConfig) external onlyOwner {
        if (newConfig.maxWinChance > 100) revert InvalidPVPConfig();

        PVPConfig memory oldConfig = _config;
        _config = newConfig;
        emit PVPConfigUpdated(oldConfig, newConfig);
    }

    /** @notice Pause all PVP battles */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /** @notice Unpause PVP battles */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // =============================================================
    //                     INTERNAL/PRIVATE HELPER FUNCTIONS
    // =============================================================

    function _isDefenderAvailable(uint256 defenderId) private view returns (bool) {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastAttackDay[defenderId] == currentDay && attacksReceivedToday[defenderId] >= _config.maxAttacksPerDay) {
            return false;
        }
        return true;
    }

    function _isInRepRange(uint256 attackerRep, uint256 defenderRep) private view returns (bool) {
        uint256 threshold = _config.repRangeThreshold;
        if (threshold > 0 && attackerRep >= threshold && defenderRep >= threshold) {
            return true;
        }

        uint256 range = attackerRep * _config.repRangePercent / 100;
        uint256 minRep = attackerRep > range ? attackerRep - range : 0;
        uint256 maxRep = (threshold > 0 && attackerRep >= threshold)
            ? type(uint256).max
            : attackerRep + range;
        return defenderRep >= minRep && defenderRep <= maxRep;
    }

    function _calcWinChance(uint8 attackerThreat, uint8 defenderArmor) private view returns (uint256) {
        int256 statModifier = int256(uint256(attackerThreat)) - int256(uint256(defenderArmor));
        int256 finalChance = int256(uint256(_config.baseWinChance)) + statModifier;
        if (finalChance < int256(uint256(_config.minWinChance))) return _config.minWinChance;
        if (finalChance > int256(uint256(_config.maxWinChance))) return _config.maxWinChance;
        return uint256(finalChance);
    }

    function _rollPvpJailCheck(uint16 jailChance, uint256 infamy, uint256 rng) private pure returns (bool) {
        uint256 bonus = (infamy / 10) * 5;
        uint16 infamyChance = bonus > 20 ? 20 : uint16(bonus);
        uint16 totalChance = jailChance + infamyChance;
        return uint16(rng % 1000) < totalChance;
    }

    function _clampInt16Result(int16 winBonus, uint8 multiplier) private pure returns (int16) {
        int256 repResult = (int256(winBonus) * int256(uint256(multiplier))) / 100;
        if (repResult > type(int16).max) repResult = type(int16).max;
        if (repResult < type(int16).min) repResult = type(int16).min;
        return int16(repResult);
    }

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
    }

    function _getInfamyDropWeights(uint256 infamy) private pure returns (uint8[4] memory) {
        if (infamy >= 50) return [uint8(15), 30, 35, 20];
        if (infamy >= 40) return [uint8(20), 35, 30, 15];
        if (infamy >= 30) return [uint8(25), 40, 25, 10];
        if (infamy >= 20) return [uint8(30), 45, 20, 5];
        if (infamy >= 10) return [uint8(35), 50, 15, 0];
        return [uint8(40), 60, 0, 0];
    }

    function _refundDefenderSlot(uint256 defenderId) private {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastAttackDay[defenderId] == currentDay && attacksReceivedToday[defenderId] > 0) {
            unchecked { --attacksReceivedToday[defenderId]; }
        }
    }

    function _checkDefenderProtection(uint256 defenderId) private {
        uint256 currentDay = block.timestamp / 1 days;

        if (lastAttackDay[defenderId] != currentDay) {
            lastAttackDay[defenderId] = currentDay;
            attacksReceivedToday[defenderId] = 1;
        } else {
            if (attacksReceivedToday[defenderId] >= _config.maxAttacksPerDay) {
                revert DefenderExhausted();
            }
            unchecked {
                ++attacksReceivedToday[defenderId];
            }
        }
    }

    struct _BattleResult {
        IDealersCore.GameOutcome atkOut;
        IDealersCore.GameOutcome defOut;
        uint256 drugIdStolen;
        uint256 drugsStolen;
        uint256 cashStolen;
        int16 attackerRepChange;
        int16 defenderRepChange;
        bool attackerWon;
        uint16 winChancePct;
    }

    function _applyExpiryAsLoss(PvpRound memory r) private {
        (IDealersCore.GameState memory atk, IDealersCore.GameState memory def) =
            core.getBothGameStates(r.attackerId, r.defenderId);

        if (atk.isJailed) {
            return;
        }

        IDealersCore.GameOutcome memory atkOut;
        IDealersCore.GameOutcome memory defOut;
        atkOut.incrementHeat = true;
        atkOut.repDelta = int256(atk.repLossPenalty);
        defOut.repDelta = int256(int16(uint16(_config.defenderRepBonus)));

        _recordPvpStats(r.attackerId, r.defenderId, false);
        core.applyPVPOutcome(r.attackerId, r.defenderId, atkOut, defOut);
        core.updateInfamy(r.attackerId, -1);
    }

    function _executeBattle(
        PvpRound memory r,
        IDealersCore.GameState memory atk,
        IDealersCore.GameState memory def,
        uint256 rand
    ) private {
        uint256 jailRng    = rand & 0xFFFF;
        uint256 winRng     = (rand >> 16) & 0xFFFF;
        uint256 drugRng    = (rand >> 32) & 0xFFFF;
        uint256 dropRng    = (rand >> 48) & 0xFFFF;
        uint256 confiscRng = (rand >> 64) & 0xFFFF;

        if (_rollPvpJailCheck(atk.jailChance, atk.infamy, jailRng)) {
            actions.arrest(r.attackerId, confiscRng);
            emit DealerArrested(r.attackerId, atk.jailChance);
            return;
        }

        _BattleResult memory br = _buildBattleResult(r, atk, def, winRng, drugRng);
        _recordPvpStats(r.attackerId, r.defenderId, br.attackerWon);

        core.applyPVPOutcome(r.attackerId, r.defenderId, br.atkOut, br.defOut);

        int16 attackerInfamyChange;
        if (br.attackerWon) {
            core.updateInfamy(r.attackerId, 3);
            attackerInfamyChange = 3;
            _applyDropReward(r.attackerId, dropRng, atk.infamy);
        } else {
            core.updateInfamy(r.attackerId, -1);
            attackerInfamyChange = -1;
        }

        emit PVPBattleResult(
            r.attackerId,
            r.defenderId,
            br.attackerWon,
            br.drugIdStolen,
            br.drugsStolen,
            br.cashStolen,
            br.attackerRepChange,
            br.defenderRepChange,
            attackerInfamyChange,
            br.winChancePct,
            core.getEffectiveHeat(r.attackerId)
        );
    }

    function _buildBattleResult(
        PvpRound memory r,
        IDealersCore.GameState memory atk,
        IDealersCore.GameState memory def,
        uint256 winRng,
        uint256 drugRng
    ) private view returns (_BattleResult memory br) {
        br.atkOut.incrementHeat = true;
        uint256 winChancePct = _calcWinChance(atk.threat, def.armor);
        br.winChancePct = uint16(winChancePct);
        br.attackerWon = (winRng % 100) < winChancePct;

        if (br.attackerWon) {
            (br.drugIdStolen, br.drugsStolen) = _computeDrugSteal(r.defenderId, r.areaAtCommit, drugRng);
            br.cashStolen = _computeCashSteal(def.cashBalance);

            br.attackerRepChange = _clampInt16Result(atk.repWinBonus, atk.repMultiplier);
            br.defenderRepChange = def.repLossPenalty;

            br.atkOut.repDelta = int256(br.attackerRepChange);
            br.defOut.repDelta = int256(br.defenderRepChange);

            if (br.drugsStolen > 0) {
                br.atkOut.drugId = br.drugIdStolen;
                br.atkOut.drugDelta = int256(br.drugsStolen);
                br.defOut.drugId = br.drugIdStolen;
                br.defOut.drugDelta = -int256(br.drugsStolen);
            }
            if (br.cashStolen > 0) {
                br.atkOut.cashDelta = int256(br.cashStolen);
                br.defOut.cashDelta = -int256(br.cashStolen);
            }
        } else {
            br.attackerRepChange = atk.repLossPenalty;
            br.defenderRepChange = int16(uint16(_config.defenderRepBonus));
            br.atkOut.repDelta = int256(br.attackerRepChange);
            br.defOut.repDelta = int256(br.defenderRepChange);
        }
    }

    function _recordPvpStats(uint256 attackerId, uint256 defenderId, bool attackerWon) private {
        unchecked {
            if (attackerWon) {
                dealerPvpStats[attackerId].attackWins++;
                dealerPvpStats[defenderId].defendLosses++;
            } else {
                dealerPvpStats[attackerId].attackLosses++;
                dealerPvpStats[defenderId].defendWins++;
            }
        }
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

        uint256 stolen = _ceilDiv(loserBalance * _config.drugStealPercent, 100);

        return (selectedDrugId, stolen);
    }

    function _computeCashSteal(uint256 loserCash) private view returns (uint256) {
        if (loserCash == 0) return 0;
        return _ceilDiv(loserCash * _config.cashStealPercent, 100);
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

        if (roll < _config.rarityWeightCommon && commonCount > 0) {
            idx = pickRng % commonCount;
            return (commonDrugs[idx], commonBalances[idx]);
        } else if (roll < uint256(_config.rarityWeightCommon) + uint256(_config.rarityWeightUncommon) && uncommonCount > 0) {
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

}
