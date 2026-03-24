// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IDealersExeCore.sol";
import "../utils/IDrugRegistry.sol";
import "../utils/IAreaRegistry.sol";
import "../utils/IERC721Minimal.sol";
import "../utils/IDEPaymentHandler.sol";
import "../utils/IDERandomness.sol";

/**
 * @title DealersExeCore - Game State Management Hub
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Centralized data management contract for all game modules
 *      Uses external DrugRegistry and AreaRegistry for configuration
 * @author Dealers.Exe Team
 */
contract DealersExeCore is IDealersExeCore, Ownable, ReentrancyGuard {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    // Starting game configuration
    uint8 public constant STARTING_AREA = 1;          // Manhattan
    uint8 public constant SAFE_HOUSE_AREA = 0;
    uint8 public constant JAIL_AREA = 255;
    uint256 public constant STARTING_REPUTATION = 25;
    uint8 public constant BASE_MAX_ATTEMPTS = 5;      // Base daily max (boosts add more)

    // Heat and Jail constants (non-configurable)
    uint8 public constant MAX_HEAT_LEVEL = 5;         // Max jail chance = 5%

    // Combat stat constants
    uint8 public constant MAX_STAT_MODIFIER = 25;     // Cap for threat/armor

    // $CASH system constants
    uint256 public constant STASH_DIVISOR = 100;

    // Starter drug amounts
    uint256 public constant STARTER_WEED = 100;
    uint256 public constant STARTER_XTC = 5;
    uint256 public constant STARTER_COCAINE = 1;

    // Configuration limits
    uint256 public constant MAX_TIERS = 20;

    // Infamy / heat decay constants
    uint256 public constant DECAY_GRACE_PERIOD = 7 days;
    uint256 public constant DECAY_RATE_PER_DAY = 1;

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /**
     * @dev Core dealer data structure (packed to 2 slots)
     */
    struct DealerData {
        uint256 reputation;              // Slot 0
        uint32 lastPlayTimestamp;        // Slot 1 (below are tightly packed)
        uint32 lastBreakoutAttempt;      // Timestamp of last breakout attempt
        uint8 currentArea;
        uint8 previousArea;              // Area before jail (for automatic return)
        uint8 dailyAttemptsRemaining;
        uint8 heatLevel;
        bool isInitialized;
    }

    /**
     * @dev Configurable game parameters
     */
    struct CoreConfig {
        uint256 attemptResetFee;          // 0.001 ether - Buy mid-day reset
        uint256 bribeCopFee;              // 0.002 ether - Full heat reset
        uint256 cashTopupPrice;           // 0.001 ether - Price to buy $CASH
        uint256 cashTopupAmount;          // 100 - Amount of $CASH received
        uint256 cashPurchaseThreshold;    // 10 - Max balance to allow purchase
        uint8 jailRepPenaltyPercent;      // 10 - % rep lost when jailed
        uint256 jailRepPenaltyCap;        // 50 - Max rep loss when jailed
        uint8 wantedPosterSuccessChance;  // 50 - % chance to clear heat
        uint8 breakoutSuccessChance;      // 33 - % chance to escape jail
        uint8 jailDrugConfiscationPercent; // 3 - % of one random drug confiscated on jail
        uint256 starterCash;              // 250 - Starting $CASH for new dealers
        uint16 jailChancePerHeat;         // 5 - Jail chance per heat level (out of 1000, so 5 = 0.5%)
    }

    // =============================================================
    //                            STORAGE
    // =============================================================

    // Core game data
    mapping(uint256 => DealerData) public dealers;                        // tokenId => dealer data
    mapping(uint256 => mapping(uint256 => uint256)) public drugBalances;  // tokenId => drugId => amount

    // Authorization for game modules
    mapping(address => bool) public authorizedContracts;

    // Reputation tiers
    ReputationTier[] public reputationTiers;

    // Configurable parameters
    CoreConfig public config;
    uint256 public MAX_REPUTATION = 1200;
    uint256 public MAX_INFAMY = 10000;
    bool public paused;

    // Boosts
    mapping(uint256 => BoostData) public dealerBoosts;                    // tokenId => boost data

    // Combat stats (for Items/PVP)
    mapping(uint256 => uint8) public dealerThreatStat;                    // tokenId => 0-25
    mapping(uint256 => uint8) public dealerArmorStat;                     // tokenId => 0-25

    // $CASH balances
    mapping(uint256 => uint256) public dealerCash;                        // tokenId => $CASH balance

    // Infamy scores (PVP identity)
    mapping(uint256 => uint256) public dealerInfamy;                      // tokenId => infamy score

    // External contract references
    IERC721Minimal public nftContract;
    IDEPaymentHandler public paymentHandler;
    IDrugRegistry public drugRegistry;
    IAreaRegistry public areaRegistry;
    IDERandomness public randomness;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event DealerInitialized(uint256 indexed tokenId, uint8 startingArea);
    event ReputationUpdated(uint256 indexed tokenId, uint256 newReputation, int256 change);
    event DrugBalanceUpdated(uint256 indexed tokenId, uint256 indexed drugId, uint256 newBalance, int256 change);
    event AreaMoved(uint256 indexed tokenId, uint8 fromArea, uint8 toArea);
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event DailyPlaysUpdated(uint256 indexed tokenId, uint8 playsRemaining);
    event ReputationTiersUpdated(uint256 tierCount);

    event DealerJailed(uint256 indexed tokenId, uint8 previousArea, uint256 repLost, uint256 confiscatedDrugId, uint256 confiscatedAmount);
    event HeatLevelChanged(uint256 indexed tokenId, uint8 newHeatLevel);
    event AttemptsUsed(uint256 indexed tokenId, uint8 remaining);
    event AttemptsReset(uint256 indexed tokenId, uint8 newAmount);
    event BoostApplied(uint256 indexed tokenId, uint64 expiresAt);
    event DealerStatsUpdated(uint256 indexed tokenId, uint8 threat, uint8 armor);
    event NFTContractUpdated(address indexed newAddress);
    event PaymentHandlerUpdated(address indexed newAddress);
    event DrugRegistryUpdated(address indexed newAddress);
    event AreaRegistryUpdated(address indexed newAddress);
    event RandomnessUpdated(address indexed newAddress);

    event CashUpdated(uint256 indexed tokenId, uint256 newBalance, int256 change);
    event InfamyUpdated(uint256 indexed tokenId, uint256 newInfamy, int256 delta);
    event MaxReputationUpdated(uint256 oldMax, uint256 newMax);
    event Paused(address account);
    event Unpaused(address account);
    event CoreConfigUpdated(CoreConfig oldConfig, CoreConfig newConfig);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotAuthorized();
    error DealerNotInitialized();
    error DealerAlreadyInitialized();
    error InvalidArea();
    error InvalidDrug();
    error InsufficientDrugBalance();
    error InvalidAddress();
    error InvalidMaxReputation();

    error CannotEnterSafeHouse();
    error CannotEnterJail();
    error NoAttemptsRemaining();
    error RegistryNotSet();

    error InsufficientCash();
    error InsufficientReputation();
    error NoTiersConfigured();
    error InvalidBoostMultiplier();
    error TooManyTiers();
    error TiersNotSorted();
    error ContractPaused();
    error InvalidCoreConfig();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the contract with owner
     * @dev Registries must be set after deployment
     */
    constructor() {
        _initializeOwner(msg.sender);

        config = CoreConfig({
            attemptResetFee: 0.001 ether,
            bribeCopFee: 0.001 ether,
            cashTopupPrice: 0.001 ether,
            cashTopupAmount: 100,
            cashPurchaseThreshold: 10,
            jailRepPenaltyPercent: 10,
            jailRepPenaltyCap: 50,
            wantedPosterSuccessChance: 50,
            breakoutSuccessChance: 50,
            jailDrugConfiscationPercent: 3,
            starterCash: 250,
            jailChancePerHeat: 5
        });
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender] && msg.sender != owner()) revert NotAuthorized();
        _;
    }

    modifier dealerExists(uint256 tokenId) {
        if (!dealers[tokenId].isInitialized) revert DealerNotInitialized();
        _;
    }

    modifier registriesSet() {
        if (address(drugRegistry) == address(0) || address(areaRegistry) == address(0)) {
            revert RegistryNotSet();
        }
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // =============================================================
    //                        INITIALIZATION
    // =============================================================

    /**
     * @notice Initialize a new dealer with starting configuration
     * @dev Dealers start in Safe House with starter $CASH and drugs
     * @param tokenId The token ID to initialize as a dealer
     */
    function initializeDealer(uint256 tokenId) external onlyAuthorized registriesSet whenNotPaused {
        if (dealers[tokenId].isInitialized) revert DealerAlreadyInitialized();

        dealers[tokenId] = DealerData({
            reputation: STARTING_REPUTATION,
            lastPlayTimestamp: uint32(block.timestamp),
            lastBreakoutAttempt: 0,
            currentArea: STARTING_AREA,
            previousArea: STARTING_AREA,
            dailyAttemptsRemaining: BASE_MAX_ATTEMPTS,
            heatLevel: 0,
            isInitialized: true
        });

        // Starter $CASH
        dealerCash[tokenId] = config.starterCash;

        // Starter drugs: 100 Weed (ID=4), 5 XTC (ID=5), 1 Cocaine (ID=6)
        drugBalances[tokenId][4] = STARTER_WEED;
        drugBalances[tokenId][5] = STARTER_XTC;
        drugBalances[tokenId][6] = STARTER_COCAINE;

        drugRegistry.incrementSupply(4, STARTER_WEED);
        drugRegistry.incrementSupply(5, STARTER_XTC);
        drugRegistry.incrementSupply(6, STARTER_COCAINE);

        areaRegistry.updateDealerLocation(tokenId, 0, STARTING_AREA);

        emit DealerInitialized(tokenId, STARTING_AREA);
        emit CashUpdated(tokenId, config.starterCash, int256(config.starterCash));
        emit DrugBalanceUpdated(tokenId, 4, STARTER_WEED, int256(STARTER_WEED));
        emit DrugBalanceUpdated(tokenId, 5, STARTER_XTC, int256(STARTER_XTC));
        emit DrugBalanceUpdated(tokenId, 6, STARTER_COCAINE, int256(STARTER_COCAINE));
    }

    // =============================================================
    //                     BATCHED READ API
    // =============================================================

    function getGameState(uint256 tokenId) external view returns (GameState memory state) {
        state = _buildGameState(tokenId);
    }

    function getBothGameStates(uint256 t1, uint256 t2) external view returns (GameState memory s1, GameState memory s2) {
        s1 = _buildGameState(t1);
        s2 = _buildGameState(t2);
    }

    function getAreaDrugBalances(uint256 tokenId, uint256[] calldata drugIds) external view returns (uint256[] memory balances) {
        balances = new uint256[](drugIds.length);
        for (uint256 i = 0; i < drugIds.length;) {
            balances[i] = drugBalances[tokenId][drugIds[i]];
            unchecked { ++i; }
        }
    }

    function isInitialized(uint256 tokenId) external view returns (bool) {
        return dealers[tokenId].isInitialized;
    }

    function _buildGameState(uint256 tokenId) private view returns (GameState memory state) {
        DealerData memory d = dealers[tokenId];
        uint8 effectiveHeat = _calcEffectiveHeat(tokenId);
        state.currentArea = d.currentArea;
        state.previousArea = d.previousArea;
        state.heatLevel = effectiveHeat;
        state.dailyAttemptsRemaining = _getEffectiveAttempts(tokenId);
        state.reputation = d.reputation;
        state.isInitialized = d.isInitialized;
        state.isJailed = d.currentArea == JAIL_AREA;
        state.isInSafeHouse = d.currentArea == SAFE_HOUSE_AREA;
        state.cashBalance = dealerCash[tokenId];

        BoostData storage boost = dealerBoosts[tokenId];
        state.boostActive = boost.expiresAt > block.timestamp;
        if (state.boostActive) {
            state.boostExpiresAt = boost.expiresAt;
            state.freeAreaMovement = boost.freeAreaMovement;
            state.drugMultiplier = boost.drugMultiplier;
            state.repMultiplier = boost.repMultiplier;
            state.cashMultiplier = boost.cashMultiplier;
            state.extraAttempts = boost.extraAttempts;
        } else {
            state.drugMultiplier = 100;
            state.repMultiplier = 100;
            state.cashMultiplier = 100;
        }

        state.jailChance = uint16(effectiveHeat) * config.jailChancePerHeat;

        state.threat = dealerThreatStat[tokenId];
        state.armor = dealerArmorStat[tokenId];
        state.lastBreakoutAttempt = d.lastBreakoutAttempt;

        if (d.isInitialized) {
            if (address(drugRegistry) != address(0)) {
                state.totalReputation = d.reputation + getStashBonus(tokenId);
            } else {
                state.totalReputation = d.reputation;
            }

            if (reputationTiers.length > 0) {
                ReputationTier memory tier = getCurrentTier(d.reputation);
                state.repWinBonus = tier.winBonus;
                state.repTieBonus = tier.tieBonus;
                state.repLossPenalty = tier.lossPenalty;
                state.repCap = tier.repCap;
            }
        }
    }

    // =============================================================
    //                     BATCHED WRITE API
    // =============================================================

    function applyGameOutcome(uint256 tokenId, GameOutcome calldata outcome)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        _applyOutcome(tokenId, outcome);
    }

    function applyPVPOutcome(
        uint256 atk,
        uint256 def,
        GameOutcome calldata atkOut,
        GameOutcome calldata defOut
    )
        external
        onlyAuthorized
        dealerExists(atk)
        dealerExists(def)
        whenNotPaused
    {
        _applyOutcome(atk, atkOut);
        _applyOutcome(def, defOut);
    }

    function _applyOutcome(uint256 tokenId, GameOutcome calldata outcome) private {
        DealerData storage d = dealers[tokenId];

        if (outcome.useAttempt) {
            if (_shouldResetAttempts(tokenId)) {
                d.dailyAttemptsRemaining = getMaxAttempts(tokenId);
            }
            if (d.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();
            unchecked { d.dailyAttemptsRemaining--; }
            d.lastPlayTimestamp = uint32(block.timestamp);
            emit AttemptsUsed(tokenId, d.dailyAttemptsRemaining);
        }

        if (outcome.incrementHeat) {
            d.heatLevel = _calcEffectiveHeat(tokenId);
            if (d.heatLevel < MAX_HEAT_LEVEL) {
                unchecked { d.heatLevel++; }
                emit HeatLevelChanged(tokenId, d.heatLevel);
            }
        }

        if (outcome.repDelta != 0) {
            _updateRep(tokenId, outcome.repDelta);
        }

        if (outcome.drugDelta != 0) {
            _updateDrug(tokenId, outcome.drugId, outcome.drugDelta);
        }

        if (outcome.cashDelta != 0) {
            _updateCash(tokenId, outcome.cashDelta);
        }

        if (outcome.sendToJail) {
            _sendToJailInternal(tokenId);
        }
    }

    // =============================================================
    //                        CORE DATA ACCESS
    // =============================================================

    /**
     * @notice Get complete dealer data for a token ID
     * @dev Returns effective attempts remaining (accounts for daily reset)
     */
    function getDealerData(uint256 tokenId)
        external
        view
        returns (
            uint8 currentArea,
            uint256 reputation,
            uint8 dailyAttemptsRemaining,
            uint8 heatLevel,
            uint32 lastPlayTimestamp,
            bool initialized
        )
    {
        DealerData memory d = dealers[tokenId];
        uint8 effectiveAttempts = _getEffectiveAttempts(tokenId);
        return (d.currentArea, d.reputation, effectiveAttempts, d.heatLevel, d.lastPlayTimestamp, d.isInitialized);
    }

    /**
     * @notice Get drug balance for a specific dealer and drug
     */
    function getDrugBalance(uint256 tokenId, uint256 drugId) external view returns (uint256) {
        return drugBalances[tokenId][drugId];
    }

    // =============================================================
    //                        REPUTATION TIER SYSTEM
    // =============================================================

    /**
     * @notice Get the current reputation tier for a given reputation score
     */
    function getCurrentTier(uint256 reputation) internal view returns (ReputationTier memory) {
        if (reputationTiers.length == 0) revert NoTiersConfigured();
        ReputationTier memory currentTier = reputationTiers[0];
        for (uint256 i = reputationTiers.length; i > 0; ) {
            if (reputation >= reputationTiers[i - 1].minReputation) {
                currentTier = reputationTiers[i - 1];
                break;
            }
            unchecked {
                --i;
            }
        }
        return currentTier;
    }

/**
     * @notice Get the tier name for a given reputation score
     */
    function getReputationTitle(uint256 reputation) external view returns (string memory) {
        return getCurrentTier(reputation).tierName;
    }

    /**
     * @notice Calculate stash bonus from drug holdings
     * @dev Stash bonus = sum(drugBalance * baseCashValue) / STASH_DIVISOR
     */
    function getStashBonus(uint256 tokenId) internal view dealerExists(tokenId) registriesSet returns (uint256) {
        uint256 totalValue = 0;

        // Get all drug IDs from registry and calculate value
        uint256[] memory drugIds = drugRegistry.getAllDrugIds();
        for (uint256 i = 0; i < drugIds.length; ) {
            uint256 drugId = drugIds[i];
            uint256 balance = drugBalances[tokenId][drugId];
            if (balance > 0) {
                uint256 baseCashValue = drugRegistry.getDrugBaseCashValue(drugId);
                totalValue += balance * baseCashValue;
            }
            unchecked { ++i; }
        }

        return totalValue / STASH_DIVISOR;
    }

    /**
     * @notice Get total reputation including stash bonus
     */
    function getTotalReputation(uint256 tokenId) internal view dealerExists(tokenId) returns (uint256) {
        return dealers[tokenId].reputation + getStashBonus(tokenId);
    }

    // =============================================================
    //                        MODULE FUNCTIONS
    // =============================================================

    /**
     * @notice Update a dealer's reputation
     */
    function updateReputation(uint256 tokenId, int256 change)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        _updateRep(tokenId, change);
    }

    /**
     * @notice Update a dealer's drug balance
     * @dev Calls DrugRegistry for supply tracking
     */
    function updateDrugBalance(uint256 tokenId, uint256 drugId, int256 change)
        external
        onlyAuthorized
        dealerExists(tokenId)
        registriesSet
        whenNotPaused
    {
        _updateDrug(tokenId, drugId, change);
    }

    // =============================================================
    //                    SHARED STATE HELPERS
    // =============================================================

    function _updateRep(uint256 tokenId, int256 delta) private {
        DealerData storage d = dealers[tokenId];
        if (delta < 0) {
            uint256 dec = uint256(-delta);
            unchecked {
                d.reputation = dec >= d.reputation ? 0 : d.reputation - dec;
            }
        } else if (delta > 0) {
            unchecked {
                d.reputation += uint256(delta);
            }
            if (d.reputation > MAX_REPUTATION) d.reputation = MAX_REPUTATION;
        }
        emit ReputationUpdated(tokenId, d.reputation, delta);
    }

    function _updateDrug(uint256 tokenId, uint256 drugId, int256 delta) private {
        if (!drugRegistry.isValidDrug(drugId)) revert InvalidDrug();
        uint256 bal = drugBalances[tokenId][drugId];
        if (delta < 0) {
            uint256 dec = uint256(-delta);
            if (dec > bal) revert InsufficientDrugBalance();
            drugBalances[tokenId][drugId] = bal - dec;
            drugRegistry.decrementSupply(drugId, dec);
        } else if (delta > 0) {
            uint256 inc = uint256(delta);
            drugBalances[tokenId][drugId] = bal + inc;
            drugRegistry.incrementSupply(drugId, inc);
        }
        emit DrugBalanceUpdated(tokenId, drugId, drugBalances[tokenId][drugId], delta);
    }

    function _updateCash(uint256 tokenId, int256 delta) private {
        if (delta < 0) {
            uint256 dec = uint256(-delta);
            if (dealerCash[tokenId] < dec) revert InsufficientCash();
            dealerCash[tokenId] -= dec;
        } else {
            dealerCash[tokenId] += uint256(delta);
        }
        emit CashUpdated(tokenId, dealerCash[tokenId], delta);
    }

    /**
     * @notice Move a dealer to a different area
     * @dev Checks area requirements via AreaRegistry
     */
    function moveToArea(uint256 tokenId, uint8 newAreaId)
        external
        onlyAuthorized
        dealerExists(tokenId)
        registriesSet
        whenNotPaused
    {
        if (!areaRegistry.isValidArea(newAreaId)) revert InvalidArea();
        if (areaRegistry.isSafeHouse(newAreaId)) revert CannotEnterSafeHouse();
        if (areaRegistry.isJail(newAreaId)) revert CannotEnterJail();

        // Check reputation requirement
        uint256 minRep = areaRegistry.getMinReputation(newAreaId);
        if (minRep > 0 && getTotalReputation(tokenId) < minRep) {
            revert InsufficientReputation();
        }

        DealerData storage d = dealers[tokenId];
        uint8 oldArea = d.currentArea;
        if (oldArea == newAreaId) return;

        d.previousArea = oldArea;
        d.currentArea = newAreaId;
        areaRegistry.updateDealerLocation(tokenId, oldArea, newAreaId);
        emit AreaMoved(tokenId, oldArea, newAreaId);
    }

    function forceMove(uint256 tokenId, uint8 newAreaId)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        DealerData storage d = dealers[tokenId];
        uint8 oldArea = d.currentArea;
        d.previousArea = oldArea;
        d.currentArea = newAreaId;
        areaRegistry.updateDealerLocation(tokenId, oldArea, newAreaId);
        emit AreaMoved(tokenId, oldArea, newAreaId);
    }

    /**
     * @notice Update daily attempts remaining for a dealer
     */
    function updateDailyPlays(uint256 tokenId, uint8 attemptsUsed)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        DealerData storage d = dealers[tokenId];
        d.dailyAttemptsRemaining = attemptsUsed > d.dailyAttemptsRemaining ? 0 : d.dailyAttemptsRemaining - attemptsUsed;
        d.lastPlayTimestamp = uint32(block.timestamp);
        emit DailyPlaysUpdated(tokenId, d.dailyAttemptsRemaining);
    }

    function setHeatLevel(uint256 tokenId, uint8 level)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        if (level > MAX_HEAT_LEVEL) level = MAX_HEAT_LEVEL;
        dealers[tokenId].heatLevel = level;
        emit HeatLevelChanged(tokenId, level);
    }

    function setLastBreakoutAttempt(uint256 tokenId, uint32 timestamp)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        dealers[tokenId].lastBreakoutAttempt = timestamp;
    }

    function resetDailyAttempts(uint256 tokenId)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        DealerData storage d = dealers[tokenId];
        d.dailyAttemptsRemaining = getMaxAttempts(tokenId);
        d.lastPlayTimestamp = uint32(block.timestamp);
        emit AttemptsReset(tokenId, d.dailyAttemptsRemaining);
    }

    function updateInfamy(uint256 tokenId, int256 delta)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        uint256 settled = _calcEffectiveInfamy(tokenId);

        if (delta < 0) {
            uint256 dec = uint256(-delta);
            settled = dec >= settled ? 0 : settled - dec;
        } else {
            unchecked { settled += uint256(delta); }
            if (settled > MAX_INFAMY) settled = MAX_INFAMY;
        }

        dealerInfamy[tokenId] = settled;
        emit InfamyUpdated(tokenId, settled, delta);
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Authorize or deauthorize contracts to modify game state
     */
    function authorizeContract(address contractAddress, bool authorized) external onlyOwner {
        if (contractAddress == address(0)) revert InvalidAddress();
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorized(contractAddress, authorized);
    }

    /**
     * @notice Set the reputation tier system
     */
    function setReputationTiers(ReputationTier[] calldata _tiers) external onlyOwner {
        uint256 len = _tiers.length;
        if (len > MAX_TIERS) revert TooManyTiers();

        for (uint256 i = 1; i < len; ) {
            if (_tiers[i].minReputation <= _tiers[i - 1].minReputation) {
                revert TiersNotSorted();
            }
            unchecked { ++i; }
        }

        delete reputationTiers;
        for (uint256 i = 0; i < len; ) {
            reputationTiers.push(_tiers[i]);
            unchecked {
                ++i;
            }
        }
        emit ReputationTiersUpdated(len);
    }

    /**
     * @notice Set maximum reputation limit
     */
    function setMaxReputation(uint256 newMax) external onlyOwner {
        if (newMax < 1000) revert InvalidMaxReputation();
        uint256 oldMax = MAX_REPUTATION;
        MAX_REPUTATION = newMax;
        emit MaxReputationUpdated(oldMax, newMax);
    }

    /**
     * @notice Set configurable game parameters
     */
    function setCoreConfig(CoreConfig calldata _config) external onlyOwner {
        if (_config.jailRepPenaltyPercent > 100) revert InvalidCoreConfig();
        if (_config.wantedPosterSuccessChance > 100) revert InvalidCoreConfig();
        if (_config.breakoutSuccessChance > 100) revert InvalidCoreConfig();
        if (_config.jailDrugConfiscationPercent > 100) revert InvalidCoreConfig();
        if (_config.jailChancePerHeat > 1000) revert InvalidCoreConfig();

        CoreConfig memory oldConfig = config;
        config = _config;
        emit CoreConfigUpdated(oldConfig, _config);
    }

    /**
     * @notice Pause the contract, disabling state-changing functions
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause the contract, re-enabling state-changing functions
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    function rollJailCheck(uint256 tokenId, uint256 rng) external view returns (bool) {
        uint16 jailChance = uint16(_calcEffectiveHeat(tokenId)) * config.jailChancePerHeat;
        return uint16(rng % 1000) < jailChance;
    }

    function getInfamy(uint256 tokenId) external view returns (uint256) {
        return _calcEffectiveInfamy(tokenId);
    }

    function getEffectiveHeat(uint256 tokenId) external view returns (uint8) {
        return _calcEffectiveHeat(tokenId);
    }

    // =============================================================
    //                     HEAT LEVEL & JAIL FUNCTIONS
    // =============================================================

    /**
     * @notice Use one attempt (auto-resets at midnight UTC)
     */
    function useAttempt(uint256 tokenId)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        DealerData storage d = dealers[tokenId];

        // Lazy reset: if last play was before today, reset attempts
        if (_shouldResetAttempts(tokenId)) {
            d.dailyAttemptsRemaining = getMaxAttempts(tokenId);
        }

        if (d.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();

        unchecked { d.dailyAttemptsRemaining--; }
        d.lastPlayTimestamp = uint32(block.timestamp);

        emit AttemptsUsed(tokenId, d.dailyAttemptsRemaining);
    }

    /**
     * @notice Increment heat level by 1
     */
    function incrementHeatLevel(uint256 tokenId)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        DealerData storage d = dealers[tokenId];
        d.heatLevel = _calcEffectiveHeat(tokenId);
        if (d.heatLevel < MAX_HEAT_LEVEL) {
            unchecked { d.heatLevel++; }
            emit HeatLevelChanged(tokenId, d.heatLevel);
        }
    }


    /**
     * @notice Send dealer to jail with capped reputation penalty
     */
    function sendToJail(uint256 tokenId)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        _sendToJailInternal(tokenId);
    }

    function _sendToJailInternal(uint256 tokenId) private {
        DealerData storage d = dealers[tokenId];

        if (d.currentArea == JAIL_AREA) return;

        uint8 priorArea = d.currentArea;

        uint256 percentLoss = (d.reputation * config.jailRepPenaltyPercent) / 100;
        uint256 repLoss = percentLoss > config.jailRepPenaltyCap ? config.jailRepPenaltyCap : percentLoss;

        d.previousArea = priorArea;
        d.currentArea = JAIL_AREA;
        areaRegistry.updateDealerLocation(tokenId, priorArea, JAIL_AREA);

        if (repLoss >= d.reputation) {
            d.reputation = 0;
        } else {
            d.reputation -= repLoss;
        }

        (uint256 confiscatedDrugId, uint256 confiscatedAmount) = _confiscateDrug(tokenId);

        emit DealerJailed(tokenId, priorArea, repLoss, confiscatedDrugId, confiscatedAmount);
    }


    // =============================================================
    //                     ATTEMPT FUNCTIONS
    // =============================================================

    /**
     * @notice Get the max attempts for a dealer
     */
    function getMaxAttempts(uint256 tokenId) internal view returns (uint8) {
        BoostData storage boost = dealerBoosts[tokenId];
        if (boost.expiresAt > block.timestamp) {
            return BASE_MAX_ATTEMPTS + boost.extraAttempts;
        }
        return BASE_MAX_ATTEMPTS;
    }

    // =============================================================
    //                     BOOST FUNCTIONS
    // =============================================================

    /**
     * @notice Apply or extend a boost on a dealer
     */
    function applyBoost(
        uint256 tokenId,
        uint64 duration,
        uint8 drugMultiplier,
        uint8 repMultiplier,
        uint8 extraAttempts,
        bool freeAreaMovement,
        uint8 cashMultiplier
    )
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
        returns (uint64)
    {
        if (drugMultiplier < 100 || repMultiplier < 100 || cashMultiplier < 100) {
            revert InvalidBoostMultiplier();
        }

        BoostData storage boost = dealerBoosts[tokenId];

        uint64 newExpiry;
        if (boost.expiresAt > block.timestamp) {
            newExpiry = boost.expiresAt + duration;
        } else {
            newExpiry = uint64(block.timestamp) + duration;
        }

        dealerBoosts[tokenId] = BoostData({
            expiresAt: newExpiry,
            drugMultiplier: drugMultiplier,
            repMultiplier: repMultiplier,
            extraAttempts: extraAttempts,
            freeAreaMovement: freeAreaMovement,
            cashMultiplier: cashMultiplier
        });

        dealers[tokenId].dailyAttemptsRemaining = getMaxAttempts(tokenId);

        emit BoostApplied(tokenId, newExpiry);

        return newExpiry;
    }

    /**
     * @notice Check if a dealer has an active boost
     */
    function hasActiveBoost(uint256 tokenId) public view returns (bool) {
        return dealerBoosts[tokenId].expiresAt > block.timestamp;
    }

    /**
     * @notice Get boost data for a dealer
     */
    function getBoost(uint256 tokenId) external view returns (BoostData memory) {
        return dealerBoosts[tokenId];
    }


    // =============================================================
    //                     COMBAT STAT FUNCTIONS
    // =============================================================

    /**
     * @notice Set combat stats for a dealer
     */
    function setDealerStats(uint256 tokenId, uint8 threat, uint8 armor)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        if (threat > MAX_STAT_MODIFIER) threat = MAX_STAT_MODIFIER;
        if (armor > MAX_STAT_MODIFIER) armor = MAX_STAT_MODIFIER;

        dealerThreatStat[tokenId] = threat;
        dealerArmorStat[tokenId] = armor;

        emit DealerStatsUpdated(tokenId, threat, armor);
    }

    /**
     * @notice Get combat stats for a dealer
     */
    function getDealerStats(uint256 tokenId)
        external
        view
        dealerExists(tokenId)
        returns (uint8 threat, uint8 armor)
    {
        return (dealerThreatStat[tokenId], dealerArmorStat[tokenId]);
    }

    // =============================================================
    //                     $CASH FUNCTIONS
    // =============================================================

    /**
     * @notice Get the $CASH balance for a dealer
     */
    function getCashBalance(uint256 tokenId) external view dealerExists(tokenId) returns (uint256) {
        return dealerCash[tokenId];
    }

    /**
     * @notice Add $CASH to a dealer's balance
     */
    function addCash(uint256 tokenId, uint256 amount)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        dealerCash[tokenId] += amount;
        emit CashUpdated(tokenId, dealerCash[tokenId], int256(amount));
    }

    /**
     * @notice Spend $CASH from a dealer's balance
     */
    function spendCash(uint256 tokenId, uint256 amount)
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
    {
        if (dealerCash[tokenId] < amount) revert InsufficientCash();
        dealerCash[tokenId] -= amount;
        emit CashUpdated(tokenId, dealerCash[tokenId], -int256(amount));
    }

    // =============================================================
    //                     CONTRACT REFERENCE SETTERS
    // =============================================================

    /**
     * @notice Set the NFT contract reference
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert InvalidAddress();
        nftContract = IERC721Minimal(_nftContract);
        emit NFTContractUpdated(_nftContract);
    }

    /**
     * @notice Set the payment handler contract reference
     */
    function setPaymentHandler(address _paymentHandler) external onlyOwner {
        if (_paymentHandler == address(0)) revert InvalidAddress();
        paymentHandler = IDEPaymentHandler(_paymentHandler);
        emit PaymentHandlerUpdated(_paymentHandler);
    }

    /**
     * @notice Set the Drug Registry reference
     */
    function setDrugRegistry(address _drugRegistry) external onlyOwner {
        if (_drugRegistry == address(0)) revert InvalidAddress();
        drugRegistry = IDrugRegistry(_drugRegistry);
        emit DrugRegistryUpdated(_drugRegistry);
    }

    /**
     * @notice Set the Area Registry reference
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert InvalidAddress();
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(_areaRegistry);
    }

    /**
     * @notice Set the Randomness contract reference
     */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert InvalidAddress();
        randomness = IDERandomness(_randomness);
        emit RandomnessUpdated(_randomness);
    }

    // =============================================================
    //                     INTERNAL HELPER FUNCTIONS
    // =============================================================

    /**
     * @notice Confiscate a percentage of one random drug from a dealer
     * @return drugId The drug type confiscated (0 if none)
     * @return amount The amount confiscated
     */
    function _confiscateDrug(uint256 tokenId) private returns (uint256 drugId, uint256 amount) {
        uint8 confiscationPercent = config.jailDrugConfiscationPercent;
        if (confiscationPercent == 0 || address(drugRegistry) == address(0)) return (0, 0);

        uint256[] memory allDrugIds = drugRegistry.getAllDrugIds();
        uint256 len = allDrugIds.length;

        // Collect drug IDs where dealer has balance > 0
        uint256[] memory heldDrugs = new uint256[](len);
        uint256 heldCount;

        for (uint256 i = 0; i < len; ) {
            if (drugBalances[tokenId][allDrugIds[i]] > 0) {
                heldDrugs[heldCount] = allDrugIds[i];
                unchecked { ++heldCount; }
            }
            unchecked { ++i; }
        }

        if (heldCount == 0) return (0, 0);

        bytes32 seed = keccak256(abi.encodePacked(tokenId, block.timestamp, "CONFISCATE"));
        uint256 pick = randomness.getRandomness(seed) % heldCount;
        drugId = heldDrugs[pick];

        uint256 balance = drugBalances[tokenId][drugId];
        amount = _ceilDiv(balance * confiscationPercent, 100);

        drugBalances[tokenId][drugId] = balance - amount;
        drugRegistry.decrementSupply(drugId, amount);

        emit DrugBalanceUpdated(tokenId, drugId, drugBalances[tokenId][drugId], -int256(amount));
    }

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        if (a == 0) return 0;
        return (a - 1) / b + 1;
    }

    function _pendingDecay(uint256 tokenId) private view returns (uint256) {
        uint256 lastPlay = uint256(dealers[tokenId].lastPlayTimestamp);
        uint256 graceEnd = lastPlay + DECAY_GRACE_PERIOD;
        if (block.timestamp <= graceEnd) return 0;
        return (block.timestamp - graceEnd) / 1 days;
    }

    function _calcEffectiveInfamy(uint256 tokenId) private view returns (uint256) {
        uint256 stored = dealerInfamy[tokenId];
        if (stored == 0) return 0;
        uint256 decay = _pendingDecay(tokenId);
        return decay >= stored ? 0 : stored - decay;
    }

    function _calcEffectiveHeat(uint256 tokenId) private view returns (uint8) {
        uint8 stored = dealers[tokenId].heatLevel;
        if (stored == 0) return 0;
        uint256 decay = _pendingDecay(tokenId);
        if (decay >= uint256(stored)) return 0;
        return stored - uint8(decay);
    }

    /**
     * @notice Get the start of the current day (midnight UTC)
     */
    function _getDayStart() private view returns (uint256) {
        return (block.timestamp / 1 days) * 1 days;
    }

    /**
     * @notice Check if a dealer's attempts should be reset (new day)
     * @param tokenId The dealer token ID
     * @return True if last play was before today
     */
    function _shouldResetAttempts(uint256 tokenId) private view returns (bool) {
        return dealers[tokenId].lastPlayTimestamp < _getDayStart();
    }

    /**
     * @notice Get effective attempts remaining (accounts for daily reset)
     * @param tokenId The dealer token ID
     * @return Effective attempts remaining
     */
    function _getEffectiveAttempts(uint256 tokenId) private view returns (uint8) {
        if (_shouldResetAttempts(tokenId)) {
            return getMaxAttempts(tokenId);
        }
        return dealers[tokenId].dailyAttemptsRemaining;
    }
}
