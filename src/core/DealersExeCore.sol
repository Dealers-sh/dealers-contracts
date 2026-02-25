// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
contract DealersExeCore is Ownable, ReentrancyGuard {
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

    // $CASH system constants (non-configurable)
    uint256 public constant STARTER_CASH = 100;
    uint256 public constant STASH_DIVISOR = 100;

    // Starter drug amounts
    uint256 public constant STARTER_WEED = 100;
    uint256 public constant STARTER_XTC = 5;
    uint256 public constant STARTER_COCAINE = 1;

    // Configuration limits
    uint256 public constant MAX_TIERS = 20;

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
     * @dev Boost data structure for temporary player bonuses
     */
    struct BoostData {
        uint64 expiresAt;
        uint8 drugMultiplier;
        uint8 repMultiplier;
        uint8 extraAttempts;
        bool freeAreaMovement;
        bool doubleHeistEntries;
        uint8 cashMultiplier;
        uint8 tierId;
    }

    /**
     * @dev Reputation tier structure for scaling rewards/penalties
     */
    struct ReputationTier {
        uint256 minReputation;
        int16 winBonus;
        int16 tieBonus;
        int16 lossPenalty;
        int16 repCap;
        string tierName;
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
    bool public paused;

    // Boosts
    mapping(uint256 => BoostData) public dealerBoosts;                    // tokenId => boost data

    // Combat stats (for Items/PVP)
    mapping(uint256 => uint8) public dealerThreatStat;                    // tokenId => 0-25
    mapping(uint256 => uint8) public dealerArmorStat;                     // tokenId => 0-25

    // $CASH balances
    mapping(uint256 => uint256) public dealerCash;                        // tokenId => $CASH balance

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
    event DealerBailed(uint256 indexed tokenId, uint256 bailPaid, uint8 newArea);
    event BreakoutAttempted(uint256 indexed tokenId, bool success, uint8 exitArea);
    event HeatLevelChanged(uint256 indexed tokenId, uint8 newHeatLevel);
    event AttemptsUsed(uint256 indexed tokenId, uint8 remaining);
    event AttemptsReset(uint256 indexed tokenId, uint8 newAmount);
    event BoostApplied(uint256 indexed tokenId, uint64 expiresAt);
    event BoostExpired(uint256 indexed tokenId);
    event DealerStatsUpdated(uint256 indexed tokenId, uint8 threat, uint8 armor);
    event WantedPosterRemoved(uint256 indexed tokenId, bool success);
    event CopBribed(uint256 indexed tokenId, uint256 feePaid);
    event NFTContractUpdated(address indexed newAddress);
    event PaymentHandlerUpdated(address indexed newAddress);
    event DrugRegistryUpdated(address indexed newAddress);
    event AreaRegistryUpdated(address indexed newAddress);
    event RandomnessUpdated(address indexed newAddress);

    event CashUpdated(uint256 indexed tokenId, uint256 newBalance, int256 change);
    event CashPurchased(uint256 indexed tokenId, uint256 amount, uint256 ethPaid);
    event MaxReputationUpdated(uint256 oldMax, uint256 newMax);
    event Paused(address account);
    event Unpaused(address account);
    event DealerTraveled(uint256 indexed tokenId, uint8 fromArea, uint8 toArea, uint256 feePaid, bool wasFreeMovement);
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
    error DealerInJail();
    error NotInJail();
    error InsufficientBail();
    error BreakoutAlreadyAttemptedToday();
    error NoAttemptsRemaining();
    error NoHeatToReduce();
    error InsufficientPayment();
    error NotDealerOwner();
    error NFTContractNotSet();
    error RegistryNotSet();

    error CashBalanceTooHigh();
    error InsufficientCash();
    error InsufficientReputation();
    error ETHTransferFailed();
    error NoTiersConfigured();
    error InvalidBoostMultiplier();
    error TooManyTiers();
    error TiersNotSorted();
    error ContractPaused();

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
            jailDrugConfiscationPercent: 3
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
        dealerCash[tokenId] = STARTER_CASH;

        // Starter drugs: 100 Weed (ID=1), 5 XTC (ID=2), 1 Cocaine (ID=3)
        drugBalances[tokenId][1] = STARTER_WEED;
        drugBalances[tokenId][2] = STARTER_XTC;
        drugBalances[tokenId][3] = STARTER_COCAINE;

        drugRegistry.incrementSupply(1, STARTER_WEED);
        drugRegistry.incrementSupply(2, STARTER_XTC);
        drugRegistry.incrementSupply(3, STARTER_COCAINE);

        areaRegistry.updateDealerLocation(tokenId, 0, STARTING_AREA);

        emit DealerInitialized(tokenId, STARTING_AREA);
        emit CashUpdated(tokenId, STARTER_CASH, int256(STARTER_CASH));
        emit DrugBalanceUpdated(tokenId, 1, STARTER_WEED, int256(STARTER_WEED));
        emit DrugBalanceUpdated(tokenId, 2, STARTER_XTC, int256(STARTER_XTC));
        emit DrugBalanceUpdated(tokenId, 3, STARTER_COCAINE, int256(STARTER_COCAINE));
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
            bool isInitialized
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
    function getCurrentTier(uint256 reputation) public view returns (ReputationTier memory) {
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
     * @notice Calculate reputation change based on game outcome and current tier
     */
    function getReputationChange(uint256 tokenId, uint8 outcome)
        external
        view
        dealerExists(tokenId)
        returns (int16)
    {
        uint256 rep = dealers[tokenId].reputation;
        ReputationTier memory tier = getCurrentTier(rep);
        if (outcome == 0) return tier.winBonus;
        if (outcome == 1) return tier.tieBonus;
        return tier.lossPenalty;
    }

    function getRepCap(uint256 tokenId) external view dealerExists(tokenId) returns (int16) {
        return getCurrentTier(dealers[tokenId].reputation).repCap;
    }

    /**
     * @notice Get the tier name for a given reputation score
     */
    function getReputationTitle(uint256 reputation) external view returns (string memory) {
        return getCurrentTier(reputation).tierName;
    }

    /**
     * @notice Get the complete tier information for a specific dealer
     */
    function getPlayerTier(uint256 tokenId) external view dealerExists(tokenId) returns (ReputationTier memory) {
        return getCurrentTier(dealers[tokenId].reputation);
    }

    /**
     * @notice Calculate stash bonus from drug holdings
     * @dev Stash bonus = sum(drugBalance * baseCashValue) / STASH_DIVISOR
     */
    function getStashBonus(uint256 tokenId) public view dealerExists(tokenId) registriesSet returns (uint256) {
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
    function getTotalReputation(uint256 tokenId) public view dealerExists(tokenId) returns (uint256) {
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
        DealerData storage d = dealers[tokenId];

        if (change < 0) {
            uint256 dec = uint256(-change);
            unchecked {
                d.reputation = dec >= d.reputation ? 0 : d.reputation - dec;
            }
        } else if (change > 0) {
            unchecked {
                d.reputation += uint256(change);
            }
            if (d.reputation > MAX_REPUTATION) d.reputation = MAX_REPUTATION;
        }
        emit ReputationUpdated(tokenId, d.reputation, change);
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
        if (!drugRegistry.isValidDrug(drugId)) revert InvalidDrug();

        uint256 bal = drugBalances[tokenId][drugId];

        if (change < 0) {
            uint256 dec = uint256(-change);
            if (dec > bal) revert InsufficientDrugBalance();
            drugBalances[tokenId][drugId] = bal - dec;
            drugRegistry.decrementSupply(drugId, dec);
        } else if (change > 0) {
            uint256 inc = uint256(change);
            drugBalances[tokenId][drugId] = bal + inc;
            drugRegistry.incrementSupply(drugId, inc);
        }

        emit DrugBalanceUpdated(tokenId, drugId, drugBalances[tokenId][drugId], change);
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

        d.currentArea = newAreaId;
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

    /**
     * @notice Get the number of reputation tiers configured
     */
    function getTierCount() external view returns (uint256) {
        return reputationTiers.length;
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
        if (d.heatLevel < MAX_HEAT_LEVEL) {
            unchecked { d.heatLevel++; }
            emit HeatLevelChanged(tokenId, d.heatLevel);
        }
    }

    /**
     * @notice Get the jail chance for a dealer
     */
    function getJailChance(uint256 tokenId)
        external
        view
        dealerExists(tokenId)
        returns (uint8)
    {
        return dealers[tokenId].heatLevel;
    }

    /**
     * @notice Get the heat level for a dealer
     */
    function getHeatLevel(uint256 tokenId)
        external
        view
        dealerExists(tokenId)
        returns (uint8)
    {
        return dealers[tokenId].heatLevel;
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
        DealerData storage d = dealers[tokenId];

        if (d.currentArea == JAIL_AREA) return;

        uint8 priorArea = d.currentArea;

        // Calculate capped rep loss: min(rep * penalty%, cap)
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

        // Confiscate a percentage of one random drug type
        (uint256 confiscatedDrugId, uint256 confiscatedAmount) = _confiscateDrug(tokenId);

        emit DealerJailed(tokenId, priorArea, repLoss, confiscatedDrugId, confiscatedAmount);
    }

    /**
     * @notice Pay bail to exit jail (returns to previous area, resets heat)
     */
    function payBail(uint256 tokenId)
        external
        payable
        nonReentrant
        dealerExists(tokenId)
        registriesSet
        whenNotPaused
    {
        DealerData storage d = dealers[tokenId];

        if (d.currentArea != JAIL_AREA) revert NotInJail();

        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        uint256 bail = areaRegistry.getMovementFee(JAIL_AREA);
        if (msg.value < bail) revert InsufficientBail();

        uint8 returnArea = d.previousArea;

        if (!areaRegistry.isValidArea(returnArea) || areaRegistry.isJail(returnArea)) {
            returnArea = 1;
        }

        d.currentArea = returnArea;
        d.heatLevel = 0;
        areaRegistry.updateDealerLocation(tokenId, JAIL_AREA, returnArea);

        if (address(paymentHandler) != address(0) && bail > 0) {
            paymentHandler.processMovementFee{value: bail}(msg.sender, bail);
        }

        if (msg.value > bail) {
            _safeTransferETH(msg.sender, msg.value - bail);
        }

        emit DealerBailed(tokenId, bail, returnArea);
    }

    /**
     * @notice Attempt to break out of jail (once per day, 33% success, keeps heat)
     */
    function attemptBreakout(uint256 tokenId)
        external
        nonReentrant
        dealerExists(tokenId)
        registriesSet
        whenNotPaused
    {
        DealerData storage d = dealers[tokenId];

        if (d.currentArea != JAIL_AREA) revert NotInJail();

        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        uint256 dayStart = (block.timestamp / 1 days) * 1 days;
        if (d.lastBreakoutAttempt >= dayStart) revert BreakoutAlreadyAttemptedToday();

        d.lastBreakoutAttempt = uint32(block.timestamp);

        bytes32 seed = keccak256(abi.encodePacked(tokenId, "BREAKOUT", block.timestamp, block.prevrandao));
        uint256 roll = randomness.getRandomness(seed) % 100;

        bool success = roll < config.breakoutSuccessChance;

        uint8 returnArea = d.previousArea;

        if (!areaRegistry.isValidArea(returnArea) || areaRegistry.isJail(returnArea)) {
            returnArea = 1;
        }

        if (success) {
            d.currentArea = returnArea;
            areaRegistry.updateDealerLocation(tokenId, JAIL_AREA, returnArea);
        }

        emit BreakoutAttempted(tokenId, success, success ? returnArea : JAIL_AREA);
    }

    /**
     * @notice Check if a dealer is currently in jail
     */
    function isInJail(uint256 tokenId)
        external
        view
        dealerExists(tokenId)
        returns (bool)
    {
        return dealers[tokenId].currentArea == JAIL_AREA;
    }

    /**
     * @notice Check if a dealer is currently in the safe house
     */
    function isInSafeHouse(uint256 tokenId)
        external
        view
        dealerExists(tokenId)
        returns (bool)
    {
        return dealers[tokenId].currentArea == SAFE_HOUSE_AREA;
    }

    /**
     * @notice Player-callable function to move dealer to a new area
     * @param tokenId The dealer's token ID
     * @param destinationArea The area ID to travel to
     */
    function travel(uint256 tokenId, uint8 destinationArea)
        external
        payable
        nonReentrant
        dealerExists(tokenId)
        registriesSet
        whenNotPaused
    {
        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        if (!areaRegistry.isValidArea(destinationArea)) revert InvalidArea();
        if (areaRegistry.isJail(destinationArea)) revert CannotEnterJail();

        uint256 minRep = areaRegistry.getMinReputation(destinationArea);
        if (minRep > 0 && getTotalReputation(tokenId) < minRep) {
            revert InsufficientReputation();
        }

        DealerData storage d = dealers[tokenId];

        if (d.currentArea == JAIL_AREA) revert DealerInJail();

        uint8 oldArea = d.currentArea;
        if (oldArea == destinationArea) {
            if (msg.value > 0) {
                _safeTransferETH(msg.sender, msg.value);
            }
            return;
        }

        uint256 movementFee = 0;
        bool hasFreeMovement = hasActiveBoost(tokenId) && dealerBoosts[tokenId].freeAreaMovement;
        bool enteringSafeHouse = areaRegistry.isSafeHouse(destinationArea);
        bool isFirstMove = d.currentArea == STARTING_AREA && d.previousArea == STARTING_AREA;

        if (!hasFreeMovement && !enteringSafeHouse && !isFirstMove) {
            movementFee = areaRegistry.getMovementFee(destinationArea);
            if (msg.value < movementFee) revert InsufficientPayment();
        }

        d.currentArea = destinationArea;
        areaRegistry.updateDealerLocation(tokenId, oldArea, destinationArea);

        if (movementFee > 0 && address(paymentHandler) != address(0)) {
            paymentHandler.processMovementFee{value: movementFee}(msg.sender, movementFee);
        }

        if (msg.value > movementFee) {
            _safeTransferETH(msg.sender, msg.value - movementFee);
        }

        emit DealerTraveled(tokenId, oldArea, destinationArea, movementFee, hasFreeMovement || enteringSafeHouse || isFirstMove);
    }

    /**
     * @notice Pay to fully reset heat level to 0
     */
    function bribeCop(uint256 tokenId)
        external
        payable
        nonReentrant
        dealerExists(tokenId)
        whenNotPaused
    {
        uint256 fee = config.bribeCopFee;
        if (msg.value < fee) revert InsufficientPayment();

        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        dealers[tokenId].heatLevel = 0;

        if (address(paymentHandler) != address(0)) {
            paymentHandler.processMarketplaceFee{value: fee}(msg.sender, fee);
        }

        if (msg.value > fee) {
            _safeTransferETH(msg.sender, msg.value - fee);
        }

        emit HeatLevelChanged(tokenId, 0);
        emit CopBribed(tokenId, fee);
    }

    /**
     * @notice Use 1 attempt for 50% chance to reduce heat to 0 (auto-resets at midnight UTC)
     */
    function removeWantedPoster(uint256 tokenId)
        external
        nonReentrant
        dealerExists(tokenId)
        whenNotPaused
    {
        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (address(randomness) == address(0)) revert RegistryNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        DealerData storage d = dealers[tokenId];

        // Lazy reset: if last play was before today, reset attempts
        if (_shouldResetAttempts(tokenId)) {
            d.dailyAttemptsRemaining = getMaxAttempts(tokenId);
        }

        if (d.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();
        if (d.heatLevel == 0) revert NoHeatToReduce();

        unchecked { d.dailyAttemptsRemaining--; }
        d.lastPlayTimestamp = uint32(block.timestamp);

        bytes32 seed = keccak256(abi.encodePacked(tokenId, "WANTED_POSTER", block.timestamp, block.prevrandao));
        uint256 roll = randomness.getRandomness(seed) % 100;

        if (roll < config.wantedPosterSuccessChance) {
            d.heatLevel = 0;
            emit HeatLevelChanged(tokenId, 0);
            emit WantedPosterRemoved(tokenId, true);
        } else {
            emit WantedPosterRemoved(tokenId, false);
        }
    }

    // =============================================================
    //                     ATTEMPT FUNCTIONS
    // =============================================================

    /**
     * @notice Get the max attempts for a dealer
     */
    function getMaxAttempts(uint256 tokenId) public view returns (uint8) {
        BoostData storage boost = dealerBoosts[tokenId];
        if (boost.expiresAt > block.timestamp) {
            return BASE_MAX_ATTEMPTS + boost.extraAttempts;
        }
        return BASE_MAX_ATTEMPTS;
    }

    /**
     * @notice Pay to reset attempts to current max
     */
    function purchaseAttemptReset(uint256 tokenId)
        external
        payable
        nonReentrant
        dealerExists(tokenId)
        whenNotPaused
    {
        bool isAdmin = msg.sender == owner();
        uint256 fee = config.attemptResetFee;

        if (!isAdmin) {
            if (msg.value < fee) revert InsufficientPayment();
        }

        DealerData storage d = dealers[tokenId];
        d.dailyAttemptsRemaining = getMaxAttempts(tokenId);
        d.lastPlayTimestamp = uint32(block.timestamp);

        if (!isAdmin) {
            if (address(paymentHandler) != address(0)) {
                paymentHandler.processMarketplaceFee{value: fee}(msg.sender, fee);
            }
            if (msg.value > fee) {
                _safeTransferETH(msg.sender, msg.value - fee);
            }
        }

        emit AttemptsReset(tokenId, getMaxAttempts(tokenId));
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
        bool doubleHeistEntries,
        uint8 cashMultiplier,
        uint8 tierId
    )
        external
        onlyAuthorized
        dealerExists(tokenId)
        whenNotPaused
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
            doubleHeistEntries: doubleHeistEntries,
            cashMultiplier: cashMultiplier,
            tierId: tierId
        });

        dealers[tokenId].dailyAttemptsRemaining = getMaxAttempts(tokenId);

        emit BoostApplied(tokenId, newExpiry);
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

    /**
     * @notice Get drug multiplier for a dealer
     */
    function getDrugMultiplier(uint256 tokenId) external view returns (uint8) {
        if (!hasActiveBoost(tokenId)) return 100;
        return dealerBoosts[tokenId].drugMultiplier;
    }

    /**
     * @notice Get rep multiplier for a dealer
     */
    function getRepMultiplier(uint256 tokenId) external view returns (uint8) {
        if (!hasActiveBoost(tokenId)) return 100;
        return dealerBoosts[tokenId].repMultiplier;
    }

    /**
     * @notice Get total daily attempts
     */
    function getTotalDailyAttempts(uint256 tokenId) external view returns (uint8) {
        uint8 base = BASE_MAX_ATTEMPTS;
        if (!hasActiveBoost(tokenId)) return base;
        return base + dealerBoosts[tokenId].extraAttempts;
    }

    /**
     * @notice Check if dealer has free area movement
     */
    function hasFreeAreaMovement(uint256 tokenId) external view returns (bool) {
        if (!hasActiveBoost(tokenId)) return false;
        return dealerBoosts[tokenId].freeAreaMovement;
    }

    /**
     * @notice Check if dealer has double heist entries
     */
    function hasDoubleHeistEntries(uint256 tokenId) external view returns (bool) {
        if (!hasActiveBoost(tokenId)) return false;
        return dealerBoosts[tokenId].doubleHeistEntries;
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

    /**
     * @notice Purchase $CASH with ETH (safety net)
     */
    function purchaseCash(uint256 tokenId)
        external
        payable
        nonReentrant
        dealerExists(tokenId)
        whenNotPaused
    {
        bool isAdmin = msg.sender == owner();
        uint256 price = config.cashTopupPrice;
        uint256 amount = config.cashTopupAmount;

        if (dealerCash[tokenId] >= config.cashPurchaseThreshold) revert CashBalanceTooHigh();

        if (!isAdmin) {
            if (msg.value < price) revert InsufficientPayment();
        }

        dealerCash[tokenId] += amount;

        emit CashPurchased(tokenId, amount, price);
        emit CashUpdated(tokenId, dealerCash[tokenId], int256(amount));

        if (!isAdmin) {
            if (address(paymentHandler) != address(0)) {
                paymentHandler.processMarketplaceFee{value: price}(msg.sender, price);
            }
            if (msg.value > price) {
                _safeTransferETH(msg.sender, msg.value - price);
            }
        }
    }

    /**
     * @notice Get cash multiplier for a dealer
     */
    function getCashMultiplier(uint256 tokenId) external view returns (uint8) {
        if (!hasActiveBoost(tokenId)) return 100;
        return dealerBoosts[tokenId].cashMultiplier;
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

        uint256 pick = uint256(keccak256(abi.encodePacked(block.prevrandao, tokenId))) % heldCount;
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

    /**
     * @notice Safe ETH transfer using .call()
     */
    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }
}
