// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/src/auth/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IDrugRegistry.sol";
import "./IAreaRegistry.sol";

interface IERC721Minimal {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IDEPaymentHandler {
    function processGameFee(uint256 amount) external payable;
    function processMarketplaceFee(uint256 amount) external payable;
}

/**
 * @title DealersExeCore - Game State Management Hub
 * @dev Centralized data management contract for all game modules
 *      Uses external DrugRegistry and AreaRegistry for configuration
 * @author Dealers.Exe Team
 */
contract DealersExeCore is Ownable, ReentrancyGuard {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    // Starting game configuration
    uint8 public constant STARTING_AREA = 0;          // Safe House
    uint8 public constant SAFE_HOUSE_AREA = 0;
    uint8 public constant JAIL_AREA = 255;
    uint256 public constant STARTING_REPUTATION = 25;
    uint8 public constant BASE_MAX_ATTEMPTS = 5;      // Base daily max (boosts add more)

    // Fee constants
    uint256 public constant ATTEMPT_RESET_FEE = 0.005 ether;  // Buy mid-day reset
    uint256 public constant BRIBE_COP_FEE = 0.002 ether;      // Full heat reset

    // Heat and Jail constants
    uint8 public constant MAX_HEAT_LEVEL = 5;                 // Max jail chance = 5%
    uint8 public constant JAIL_REP_PENALTY_PERCENT = 10;      // Lose 10% rep when jailed
    uint256 public constant JAIL_REP_PENALTY_CAP = 50;        // Max rep loss capped at 50
    uint8 public constant WANTED_POSTER_SUCCESS_CHANCE = 50;  // 50% chance

    // Combat stat constants
    uint8 public constant MAX_STAT_MODIFIER = 25;     // Cap for threat/armor

    // $CASH system constants
    uint256 public constant STARTER_CASH = 100;
    uint256 public constant CASH_TOPUP_PRICE = 0.001 ether;
    uint256 public constant CASH_TOPUP_AMOUNT = 100;
    uint256 public constant CASH_PURCHASE_THRESHOLD = 10;
    uint256 public constant STASH_DIVISOR = 100;

    // Starter drug amount
    uint256 public constant STARTER_DRUG_AMOUNT = 50;

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /**
     * @dev Core dealer data structure (packed to 2 slots)
     */
    struct DealerData {
        uint256 reputation;              // Slot 0
        uint32 lastPlayTimestamp;        // Slot 1 (below are tightly packed)
        uint8 currentArea;
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
    }

    /**
     * @dev Reputation tier structure for scaling rewards/penalties
     */
    struct ReputationTier {
        uint256 minReputation;
        int16 winBonus;
        int16 tieBonus;
        int16 lossPenalty;
        string tierName;
        bool canHeist;
        uint256 pvpRange;
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

    // Updateable parameters
    uint32 public lastGlobalReset;
    uint256 public MAX_REPUTATION = 1200;

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

    // =============================================================
    //                            EVENTS
    // =============================================================

    event DealerInitialized(uint256 indexed tokenId, uint8 startingArea);
    event ReputationUpdated(uint256 indexed tokenId, uint256 newReputation, int256 change);
    event DrugBalanceUpdated(uint256 indexed tokenId, uint256 indexed drugId, uint256 newBalance, int256 change);
    event AreaMoved(uint256 indexed tokenId, uint8 fromArea, uint8 toArea);
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event DailyPlaysUpdated(uint256 indexed tokenId, uint8 playsRemaining);
    event GlobalDailyReset(uint32 timestamp);
    event ReputationTiersUpdated(uint256 tierCount);

    event DealerJailed(uint256 indexed tokenId, uint8 previousArea, uint256 repLost);
    event DealerBailed(uint256 indexed tokenId, uint256 bailPaid, uint8 newArea);
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

    event CashUpdated(uint256 indexed tokenId, uint256 newBalance, int256 change);
    event CashPurchased(uint256 indexed tokenId, uint256 amount, uint256 ethPaid);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotAuthorized();
    error DealerNotInitialized();
    error DealerAlreadyInitialized();
    error InvalidArea();
    error InvalidDrug();
    error InsufficientDrugBalance();
    error SupplyCapExceeded();
    error InvalidTokenId();
    error InvalidAddress();
    error InvalidMaxReputation();

    error CannotEnterSafeHouse();
    error CannotEnterJail();
    error DealerInJail();
    error NotInJail();
    error InsufficientBail();
    error NoAttemptsRemaining();
    error NoHeatToReduce();
    error InsufficientPayment();
    error NotDealerOwner();
    error AreaNotActive();
    error PaymentHandlerNotSet();
    error NFTContractNotSet();
    error RegistryNotSet();

    error CashBalanceTooHigh();
    error InsufficientCash();
    error InsufficientReputation();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the contract with owner
     * @dev Registries must be set after deployment
     */
    constructor() {
        _initializeOwner(msg.sender);
        lastGlobalReset = uint32(block.timestamp);
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

    // =============================================================
    //                        INITIALIZATION
    // =============================================================

    /**
     * @notice Initialize a new dealer with starting configuration
     * @dev Dealers start in Safe House with starter $CASH and drugs
     * @param tokenId The token ID to initialize as a dealer
     */
    function initializeDealer(uint256 tokenId) external onlyAuthorized registriesSet {
        if (dealers[tokenId].isInitialized) revert DealerAlreadyInitialized();

        dealers[tokenId] = DealerData({
            reputation: STARTING_REPUTATION,
            lastPlayTimestamp: uint32(block.timestamp),
            currentArea: STARTING_AREA,
            dailyAttemptsRemaining: BASE_MAX_ATTEMPTS,
            heatLevel: 0,
            isInitialized: true
        });

        // Starter $CASH
        dealerCash[tokenId] = STARTER_CASH;

        // Starter drugs: 50 Weed (Drug ID 1)
        uint256 starterDrugId = drugRegistry.DRUG_WEED();
        drugBalances[tokenId][starterDrugId] = STARTER_DRUG_AMOUNT;
        drugRegistry.incrementSupply(starterDrugId, STARTER_DRUG_AMOUNT);

        emit DealerInitialized(tokenId, STARTING_AREA);
        emit CashUpdated(tokenId, STARTER_CASH, int256(STARTER_CASH));
        emit DrugBalanceUpdated(tokenId, starterDrugId, STARTER_DRUG_AMOUNT, int256(STARTER_DRUG_AMOUNT));
    }

    // =============================================================
    //                        CORE DATA ACCESS
    // =============================================================

    /**
     * @notice Get complete dealer data for a token ID
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
        return (d.currentArea, d.reputation, d.dailyAttemptsRemaining, d.heatLevel, d.lastPlayTimestamp, d.isInitialized);
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
    {
        DealerData storage d = dealers[tokenId];

        if (change < 0) {
            uint256 dec = uint256(-change);
            d.reputation = dec >= d.reputation ? 0 : d.reputation - dec;
        } else if (change > 0) {
            d.reputation += uint256(change);
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
        delete reputationTiers;
        uint256 len = _tiers.length;
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
        MAX_REPUTATION = newMax;
    }

    /**
     * @notice Reset daily plays for all dealers
     */
    function resetDailyPlays() external onlyOwner {
        uint32 nowTs = uint32(block.timestamp);
        lastGlobalReset = nowTs;
        emit GlobalDailyReset(nowTs);
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
     * @notice Use one attempt
     */
    function useAttempt(uint256 tokenId)
        external
        onlyAuthorized
        dealerExists(tokenId)
    {
        DealerData storage d = dealers[tokenId];
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
    {
        DealerData storage d = dealers[tokenId];

        if (d.currentArea == JAIL_AREA) return;

        uint8 previousArea = d.currentArea;

        // Calculate capped rep loss: min(rep * 10%, 50)
        uint256 percentLoss = (d.reputation * JAIL_REP_PENALTY_PERCENT) / 100;
        uint256 repLoss = percentLoss > JAIL_REP_PENALTY_CAP ? JAIL_REP_PENALTY_CAP : percentLoss;

        d.currentArea = JAIL_AREA;

        if (repLoss >= d.reputation) {
            d.reputation = 0;
        } else {
            d.reputation -= repLoss;
        }

        emit DealerJailed(tokenId, previousArea, repLoss);
    }

    /**
     * @notice Pay bail to exit jail
     */
    function payBail(uint256 tokenId, uint8 exitArea)
        external
        payable
        nonReentrant
        dealerExists(tokenId)
        registriesSet
    {
        DealerData storage d = dealers[tokenId];

        if (d.currentArea != JAIL_AREA) revert NotInJail();

        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        // Validate exit area via registry
        if (!areaRegistry.isValidArea(exitArea)) revert InvalidArea();
        if (areaRegistry.isSafeHouse(exitArea)) revert CannotEnterSafeHouse();
        if (areaRegistry.isJail(exitArea)) revert CannotEnterJail();

        // Get bail amount from jail's movement fee
        uint256 bail = areaRegistry.getMovementFee(JAIL_AREA);
        if (msg.value < bail) revert InsufficientBail();

        d.currentArea = exitArea;

        if (address(paymentHandler) != address(0) && bail > 0) {
            paymentHandler.processGameFee{value: bail}(bail);
        }

        if (msg.value > bail) {
            _safeTransferETH(msg.sender, msg.value - bail);
        }

        emit DealerBailed(tokenId, bail, exitArea);
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
     * @notice Pay to fully reset heat level to 0
     */
    function bribeCop(uint256 tokenId)
        external
        payable
        nonReentrant
        dealerExists(tokenId)
    {
        if (msg.value < BRIBE_COP_FEE) revert InsufficientPayment();

        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        dealers[tokenId].heatLevel = 0;

        if (address(paymentHandler) != address(0)) {
            paymentHandler.processMarketplaceFee{value: BRIBE_COP_FEE}(BRIBE_COP_FEE);
        }

        if (msg.value > BRIBE_COP_FEE) {
            _safeTransferETH(msg.sender, msg.value - BRIBE_COP_FEE);
        }

        emit HeatLevelChanged(tokenId, 0);
        emit CopBribed(tokenId, BRIBE_COP_FEE);
    }

    /**
     * @notice Use 1 attempt for 50% chance to reduce heat by 1
     */
    function removeWantedPoster(uint256 tokenId)
        external
        nonReentrant
        dealerExists(tokenId)
    {
        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        DealerData storage d = dealers[tokenId];

        if (d.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();
        if (d.heatLevel == 0) revert NoHeatToReduce();

        unchecked { d.dailyAttemptsRemaining--; }

        uint256 roll = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            tokenId,
            "WANTED_POSTER"
        ))) % 100;

        if (roll < WANTED_POSTER_SUCCESS_CHANCE) {
            d.heatLevel--;
            emit HeatLevelChanged(tokenId, d.heatLevel);
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
    {
        if (msg.value < ATTEMPT_RESET_FEE) revert InsufficientPayment();

        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        dealers[tokenId].dailyAttemptsRemaining = getMaxAttempts(tokenId);

        if (address(paymentHandler) != address(0)) {
            paymentHandler.processGameFee{value: ATTEMPT_RESET_FEE}(ATTEMPT_RESET_FEE);
        }

        if (msg.value > ATTEMPT_RESET_FEE) {
            _safeTransferETH(msg.sender, msg.value - ATTEMPT_RESET_FEE);
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
        uint8 cashMultiplier
    )
        external
        onlyAuthorized
        dealerExists(tokenId)
    {
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
            cashMultiplier: cashMultiplier
        });

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
    {
        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();

        if (dealerCash[tokenId] >= CASH_PURCHASE_THRESHOLD) revert CashBalanceTooHigh();
        if (msg.value < CASH_TOPUP_PRICE) revert InsufficientPayment();

        dealerCash[tokenId] += CASH_TOPUP_AMOUNT;

        emit CashPurchased(tokenId, CASH_TOPUP_AMOUNT, CASH_TOPUP_PRICE);
        emit CashUpdated(tokenId, dealerCash[tokenId], int256(CASH_TOPUP_AMOUNT));

        if (address(paymentHandler) != address(0)) {
            paymentHandler.processGameFee{value: CASH_TOPUP_PRICE}(CASH_TOPUP_PRICE);
        }

        if (msg.value > CASH_TOPUP_PRICE) {
            _safeTransferETH(msg.sender, msg.value - CASH_TOPUP_PRICE);
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

    // =============================================================
    //                     INTERNAL HELPER FUNCTIONS
    // =============================================================

    /**
     * @notice Safe ETH transfer using .call()
     */
    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert InvalidAddress();
    }
}
