// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DealersExeCore - Game State Management Hub
 * @dev Centralized data management contract for all game modules
 *      (optimized for minimal casting and simpler types)
 * @author Your Team
 */
contract DealersExeCore is Ownable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    // Starting game configuration
    uint8 public constant STARTING_AREA = 1;
    uint256 public constant STARTING_REPUTATION = 25;
    uint8 public constant DAILY_FREE_PLAYS = 3;

    // Drug system constants
    uint8 public constant COMMON_RARITY = 0;
    uint8 public constant UNCOMMON_RARITY = 1;
    uint8 public constant RARE_RARITY = 2;

    // Starter drugs for new dealers
    uint256 public constant STARTER_COMMON = 100;
    uint256 public constant STARTER_UNCOMMON = 10;
    uint256 public constant STARTER_RARE = 1;

    // Supply caps per drug type
    uint256 public constant COMMON_SUPPLY_CAP = 10_000_000;
    uint256 public constant UNCOMMON_SUPPLY_CAP = 1_000_000;
    uint256 public constant RARE_SUPPLY_CAP = 100_000;

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /**
     * @dev Core dealer data structure (packed to 2 slots; no extra casts)
     * @param reputation Player's current reputation score
     * @param lastPlayTimestamp Unix timestamp of last game interaction
     * @param currentArea Current area ID where dealer is located (1-255)
     * @param dailyPlaysRemaining Number of free daily plays remaining (0-3)
     * @param pvpEnabled Whether player has opted into PvP mode
     * @param isInitialized Whether this dealer has been properly initialized
     */
    struct DealerData {
        uint256 reputation;          // Slot 0
        uint32 lastPlayTimestamp;    // Slot 1 (below are tightly packed)
        uint8 currentArea;
        uint8 dailyPlaysRemaining;
        bool pvpEnabled;
        bool isInitialized;
    }

    /**
     * @dev Area configuration structure
     * @param name Display name of the area
     * @param movementFee Cost in wei to move to this area
     * @param isActive Whether the area is accessible to players
     * @param drugIds Array of 3 drug IDs [common, uncommon, rare]
     * @param drugNames Array of 3 drug names corresponding to drugIds
     */
    struct AreaData {
        string name;                 // Area display name
        uint256 movementFee;         // Cost to move to this area (in wei)
        bool isActive;               // Whether area is accessible
        uint256[3] drugIds;          // [common, uncommon, rare]
        string[3] drugNames;         // Names of the 3 drugs in this area
    }

    /**
     * @dev Drug information structure
     * @param name Display name of the drug
     * @param rarity Rarity level (0=Common, 1=Uncommon, 2=Rare)
     * @param areaId ID of the area this drug belongs to
     * @param totalSupply Current total circulating supply
     * @param supplyCap Maximum allowed supply for this drug
     * @param isActive Whether this drug can currently be obtained
     */
    struct DrugInfo {
        string name;                 // Drug display name
        uint8 rarity;                // 0=Common, 1=Uncommon, 2=Rare
        uint8 areaId;                // Area this drug belongs to
        uint256 totalSupply;         // Current circulating supply
        uint256 supplyCap;           // Maximum supply allowed
        bool isActive;               // Whether this drug can be obtained
    }

    /**
     * @dev Reputation tier structure for scaling rewards/penalties
     * @param minReputation Minimum reputation required for this tier
     * @param winBonus Reputation points gained on win
     * @param tieBonus Reputation points gained on tie
     * @param lossPenalty Reputation points lost on defeat (negative value)
     * @param tierName Display name for this tier (e.g., "Prospect", "Don")
     * @param canHeist Whether players in this tier can participate in heists
     * @param pvpRange PvP attack range percentage for this tier
     */
    struct ReputationTier {
        uint256 minReputation;       // Minimum reputation for this tier
        int16 winBonus;              // Reputation gain on win
        int16 tieBonus;              // Reputation gain on tie
        int16 lossPenalty;           // Reputation loss on defeat
        string tierName;             // Display name for tier
        bool canHeist;               // Whether this tier can heist
        uint256 pvpRange;            // PvP attack range percentage
    }

    // =============================================================
    //                            STORAGE
    // =============================================================

    // Core game data
    mapping(uint256 => DealerData) public dealers;                        // tokenId => dealer data
    mapping(uint256 => mapping(uint256 => uint256)) public drugBalances;  // tokenId => drugId => amount

    // Area management
    mapping(uint8 => AreaData) public areas;                              // areaId => area data
    uint8 public totalAreas = 0;

    // Drug system
    mapping(uint256 => DrugInfo) public drugs;                            // drugId => drug info
    uint256 public totalDrugs = 0;

    // Authorization for future modules
    mapping(address => bool) public authorizedContracts;

    // Reputation tiers
    ReputationTier[] public reputationTiers;

    // Updateable parameters
    uint256 public pvpReputationRange = 20;                               // Default 20%
    uint32 public lastGlobalReset;                                        // store as uint32 to avoid repeated casts

    // Max reputation
    uint256 public MAX_REPUTATION = 1200;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event DealerInitialized(uint256 indexed tokenId, uint8 startingArea);
    event ReputationUpdated(uint256 indexed tokenId, uint256 newReputation, int256 change);
    event DrugBalanceUpdated(uint256 indexed tokenId, uint256 indexed drugId, uint256 newBalance, int256 change);
    event AreaMoved(uint256 indexed tokenId, uint8 fromArea, uint8 toArea);
    event PvPToggled(uint256 indexed tokenId, bool enabled);
    event AreaCreated(uint8 indexed areaId, string name);
    event DrugCreated(uint256 indexed drugId, string name, uint8 rarity, uint8 areaId);
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event DailyPlaysUpdated(uint256 indexed tokenId, uint8 playsRemaining);
    event GlobalDailyReset(uint32 timestamp);
    event ReputationTiersUpdated(uint256 tierCount);
    event PvPRangeUpdated(uint256 newRange);

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
    error InvalidRarity();
    error AreaNameTooLong();
    error DrugNameTooLong();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the contract with owner and creates the first area
     * @dev Sets up Manhattan as the starting area with 3 drugs
     */
    constructor() {
        _initializeOwner(msg.sender);
        lastGlobalReset = uint32(block.timestamp);
        _createInitialArea();
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    /**
     * @dev Ensures only authorized contracts or owner can call function
     */
    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender] && msg.sender != owner()) revert NotAuthorized();
        _;
    }

    /**
     * @dev Ensures the dealer exists and is initialized
     * @param tokenId The token ID to check
     */
    modifier dealerExists(uint256 tokenId) {
        if (!dealers[tokenId].isInitialized) revert DealerNotInitialized();
        _;
    }

    /**
     * @dev Ensures the area ID is valid and active
     * @param areaId The area ID to validate
     */
    modifier validArea(uint8 areaId) {
        if (areaId == 0 || areaId > totalAreas || !areas[areaId].isActive) revert InvalidArea();
        _;
    }

    /**
     * @dev Ensures the drug ID is valid and active
     * @param drugId The drug ID to validate
     */
    modifier validDrug(uint256 drugId) {
        if (!drugs[drugId].isActive) revert InvalidDrug();
        _;
    }

    // =============================================================
    //                        INITIALIZATION
    // =============================================================

    /**
     * @notice Initialize a new dealer with starting configuration
     * @dev Can only be called by authorized contracts (typically NFT contract)
     * @param tokenId The token ID to initialize as a dealer
     */
    function initializeDealer(uint256 tokenId) external onlyAuthorized {
        if (dealers[tokenId].isInitialized) revert DealerAlreadyInitialized();

        dealers[tokenId] = DealerData({
            reputation: STARTING_REPUTATION,
            lastPlayTimestamp: uint32(block.timestamp),
            currentArea: STARTING_AREA,
            dailyPlaysRemaining: DAILY_FREE_PLAYS,
            pvpEnabled: false,
            isInitialized: true
        });

        // Starter drugs from Area 1
        uint256 commonDrugId = areas[STARTING_AREA].drugIds[COMMON_RARITY];
        uint256 uncommonDrugId = areas[STARTING_AREA].drugIds[UNCOMMON_RARITY];
        uint256 rareDrugId = areas[STARTING_AREA].drugIds[RARE_RARITY];

        drugBalances[tokenId][commonDrugId] = STARTER_COMMON;
        drugBalances[tokenId][uncommonDrugId] = STARTER_UNCOMMON;
        drugBalances[tokenId][rareDrugId] = STARTER_RARE;

        drugs[commonDrugId].totalSupply += STARTER_COMMON;
        drugs[uncommonDrugId].totalSupply += STARTER_UNCOMMON;
        drugs[rareDrugId].totalSupply += STARTER_RARE;

        emit DealerInitialized(tokenId, STARTING_AREA);
        emit DrugBalanceUpdated(tokenId, commonDrugId, STARTER_COMMON, int256(STARTER_COMMON));
        emit DrugBalanceUpdated(tokenId, uncommonDrugId, STARTER_UNCOMMON, int256(STARTER_UNCOMMON));
        emit DrugBalanceUpdated(tokenId, rareDrugId, STARTER_RARE, int256(STARTER_RARE));
    }

    /**
     * @notice Create the initial Manhattan area with 3 starter drugs
     * @dev Private function called during contract deployment
     */
    function _createInitialArea() private {
        string memory areaName = "Manhattan";
        string[3] memory drugNames = ["Weed", "XTC", "Cocaine"];

        totalAreas = 1;
        areas[1] = AreaData({
            name: areaName,
            movementFee: 0.001 ether,
            isActive: true,
            drugIds: [uint256(1000), uint256(1001), uint256(1002)],
            drugNames: drugNames
        });

        _createDrug(1000, drugNames[0], COMMON_RARITY, 1);
        _createDrug(1001, drugNames[1], UNCOMMON_RARITY, 1);
        _createDrug(1002, drugNames[2], RARE_RARITY, 1);

        emit AreaCreated(1, areaName);
    }

    /**
     * @notice Create a new drug type with specified parameters
     * @dev Private function used during area creation
     * @param drugId Unique identifier for the drug
     * @param name Display name for the drug
     * @param rarity Rarity level (0=Common, 1=Uncommon, 2=Rare)
     * @param areaId Area ID this drug belongs to
     */
    function _createDrug(uint256 drugId, string memory name, uint8 rarity, uint8 areaId) private {
        if (rarity > 2) revert InvalidRarity();
        if (bytes(name).length > 32) revert DrugNameTooLong();

        uint256 cap = rarity == COMMON_RARITY
            ? COMMON_SUPPLY_CAP
            : (rarity == UNCOMMON_RARITY ? UNCOMMON_SUPPLY_CAP : RARE_SUPPLY_CAP);

        drugs[drugId] = DrugInfo({
            name: name,
            rarity: rarity,
            areaId: areaId,
            totalSupply: 0,
            supplyCap: cap,
            isActive: true
        });

        unchecked {
            ++totalDrugs;
        }

        emit DrugCreated(drugId, name, rarity, areaId);
    }

    // =============================================================
    //                        CORE DATA ACCESS
    // =============================================================

    /**
     * @notice Get complete dealer data for a token ID
     * @param tokenId The dealer's token ID
     * @return currentArea The area where dealer is currently located
     * @return reputation The dealer's current reputation score
     * @return pvpEnabled Whether dealer has PvP enabled
     * @return dailyPlaysRemaining Number of free daily plays left
     * @return lastPlayTimestamp Unix timestamp of last game interaction
     * @return isInitialized Whether dealer has been initialized
     */
    function getDealerData(uint256 tokenId)
        external
        view
        returns (
            uint8 currentArea,
            uint256 reputation,
            bool pvpEnabled,
            uint8 dailyPlaysRemaining,
            uint32 lastPlayTimestamp,
            bool isInitialized
        )
    {
        DealerData memory d = dealers[tokenId];
        return (d.currentArea, d.reputation, d.pvpEnabled, d.dailyPlaysRemaining, d.lastPlayTimestamp, d.isInitialized);
    }

    /**
     * @notice Get drug balance for a specific dealer and drug
     * @param tokenId The dealer's token ID
     * @param drugId The drug ID to query
     * @return The amount of the specified drug the dealer owns
     */
    function getDrugBalance(uint256 tokenId, uint256 drugId) external view returns (uint256) {
        return drugBalances[tokenId][drugId];
    }

    /**
     * @notice Get detailed information about an area
     * @param areaId The area ID to query
     * @return Complete area data structure
     */
    function getAreaInfo(uint8 areaId) external view validArea(areaId) returns (AreaData memory) {
        return areas[areaId];
    }

    /**
     * @notice Get detailed information about a drug
     * @param drugId The drug ID to query
     * @return Complete drug information structure
     */
    function getDrugInfo(uint256 drugId) external view validDrug(drugId) returns (DrugInfo memory) {
        return drugs[drugId];
    }

    /**
     * @notice Get all drug IDs available in a specific area
     * @param areaId The area ID to query
     * @return Array of 3 drug IDs [common, uncommon, rare]
     */
    function getAreaDrugIds(uint8 areaId) external view validArea(areaId) returns (uint256[3] memory) {
        return areas[areaId].drugIds;
    }

    // =============================================================
    //                        REPUTATION TIER SYSTEM
    // =============================================================

    /**
     * @notice Get the current reputation tier for a given reputation score
     * @param reputation The reputation score to evaluate
     * @return The reputation tier data structure
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
     * @param tokenId The dealer's token ID
     * @param outcome Game outcome (0=WIN, 1=TIE, 2=LOSS)
     * @return Reputation points to add/subtract (negative for loss)
     */
    function getReputationChange(uint256 tokenId, uint8 outcome)
        external
        view
        dealerExists(tokenId)
        returns (int16)
    {
        uint256 rep = dealers[tokenId].reputation;
        ReputationTier memory tier = getCurrentTier(rep);
        if (outcome == 0) return tier.winBonus; // WIN
        if (outcome == 1) return tier.tieBonus; // TIE
        return tier.lossPenalty;               // LOSS
    }

    /**
     * @notice Get the tier name for a given reputation score
     * @param reputation The reputation score to evaluate
     * @return The tier name (e.g., "Prospect", "Fixer", "Don")
     */
    function getReputationTitle(uint256 reputation) external view returns (string memory) {
        return getCurrentTier(reputation).tierName;
    }

    /**
     * @notice Get the complete tier information for a specific dealer
     * @param tokenId The dealer's token ID
     * @return The complete reputation tier structure
     */
    function getPlayerTier(uint256 tokenId) external view dealerExists(tokenId) returns (ReputationTier memory) {
        return getCurrentTier(dealers[tokenId].reputation);
    }

    // =============================================================
    //                        MODULE FUNCTIONS
    // =============================================================

    /**
     * @notice Update a dealer's reputation (for authorized game modules)
     * @dev Reputation cannot go below 0, no upper limit enforced
     * @param tokenId The dealer's token ID
     * @param change The reputation change (positive or negative)
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
     * @notice Update a dealer's drug balance (for authorized game modules)
     * @dev Enforces supply caps and prevents negative balances
     * @param tokenId The dealer's token ID
     * @param drugId The drug ID to modify
     * @param change The balance change (positive or negative)
     */
    function updateDrugBalance(uint256 tokenId, uint256 drugId, int256 change)
        external
        onlyAuthorized
        dealerExists(tokenId)
        validDrug(drugId)
    {
        uint256 bal = drugBalances[tokenId][drugId];

        if (change < 0) {
            uint256 dec = uint256(-change);
            if (dec > bal) revert InsufficientDrugBalance();
            drugBalances[tokenId][drugId] = bal - dec;
            drugs[drugId].totalSupply -= dec;
        } else if (change > 0) {
            uint256 inc = uint256(change);
            uint256 newSupply = drugs[drugId].totalSupply + inc;
            if (newSupply > drugs[drugId].supplyCap) revert SupplyCapExceeded();
            drugBalances[tokenId][drugId] = bal + inc;
            drugs[drugId].totalSupply = newSupply;
        }

        emit DrugBalanceUpdated(tokenId, drugId, drugBalances[tokenId][drugId], change);
    }

    /**
     * @notice Move a dealer to a different area (for authorized modules)
     * @param tokenId The dealer's token ID
     * @param newAreaId The target area ID to move to
     */
    function moveToArea(uint256 tokenId, uint8 newAreaId)
        external
        onlyAuthorized
        dealerExists(tokenId)
        validArea(newAreaId)
    {
        DealerData storage d = dealers[tokenId];
        uint8 oldArea = d.currentArea;
        if (oldArea == newAreaId) return;

        d.currentArea = newAreaId;
        emit AreaMoved(tokenId, oldArea, newAreaId);
    }

    /**
     * @notice Toggle PvP status for a dealer (controlled by PvP module)
     * @param tokenId The dealer's token ID
     */
    function togglePvP(uint256 tokenId)
        external
        onlyAuthorized
        dealerExists(tokenId)
    {
        bool newState = !dealers[tokenId].pvpEnabled;
        dealers[tokenId].pvpEnabled = newState;
        emit PvPToggled(tokenId, newState);
    }

    /**
     * @notice Update daily plays remaining for a dealer (for game modules)
     * @param tokenId The dealer's token ID
     * @param playsUsed Number of plays to deduct
     */
    function updateDailyPlays(uint256 tokenId, uint8 playsUsed)
        external
        onlyAuthorized
        dealerExists(tokenId)
    {
        DealerData storage d = dealers[tokenId];
        d.dailyPlaysRemaining = playsUsed > d.dailyPlaysRemaining ? 0 : d.dailyPlaysRemaining - playsUsed;
        d.lastPlayTimestamp = uint32(block.timestamp);
        emit DailyPlaysUpdated(tokenId, d.dailyPlaysRemaining);
    }

    // =============================================================
    //                        AREA FACTORY
    // =============================================================

    /**
     * @notice Create a new area with 3 unique drugs (owner only)
     * @param name The display name for the new area
     * @param drugNames Array of 3 drug names [common, uncommon, rare]
     * @param movementFee Cost in wei to move to this area
     */
    function createArea(
        string calldata name,
        string[3] calldata drugNames,
        uint256 movementFee
    ) external onlyOwner {
        if (bytes(name).length > 32) revert AreaNameTooLong();

        unchecked {
            ++totalAreas;
        }
        uint8 newAreaId = totalAreas;

        // Base computation avoids repeated implicit widening
        uint256 base = uint256(newAreaId) * 1000;
        uint256 commonId = base + COMMON_RARITY;
        uint256 uncommonId = base + UNCOMMON_RARITY;
        uint256 rareId = base + RARE_RARITY;

        areas[newAreaId] = AreaData({
            name: name,
            movementFee: movementFee,
            isActive: true,
            drugIds: [commonId, uncommonId, rareId],
            drugNames: drugNames
        });

        _createDrug(commonId, drugNames[0], COMMON_RARITY, newAreaId);
        _createDrug(uncommonId, drugNames[1], UNCOMMON_RARITY, newAreaId);
        _createDrug(rareId, drugNames[2], RARE_RARITY, newAreaId);

        emit AreaCreated(newAreaId, name);
    }

    /**
     * @notice Update the movement fee for an existing area (owner only)
     * @param areaId The area ID to update
     * @param newFee The new movement fee in wei
     */
    function updateMovementFee(uint8 areaId, uint256 newFee) external onlyOwner validArea(areaId) {
        areas[areaId].movementFee = newFee;
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Authorize or deauthorize contracts to modify game state
     * @param contractAddress The contract address to modify
     * @param authorized Whether to grant or revoke authorization
     */
    function authorizeContract(address contractAddress, bool authorized) external onlyOwner {
        if (contractAddress == address(0)) revert InvalidAddress();
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorized(contractAddress, authorized);
    }

    /**
     * @notice Set the reputation tier system (owner only)
     * @param _tiers Array of reputation tiers to set
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
     * @notice Update PvP reputation range percentage (owner only)
     * @param newRange New PvP range percentage (e.g., 20 for 20%)
     */
    function setPvPReputationRange(uint256 newRange) external onlyOwner {
        pvpReputationRange = newRange;
        emit PvPRangeUpdated(newRange);
    }

    /**
     * @notice Set maximum reputation limit (owner only)
     * @param newMax New maximum reputation value
     */
    function setMaxReputation(uint256 newMax) external onlyOwner {
        if (newMax < 1000) revert InvalidAddress();
        MAX_REPUTATION = newMax;
    }

    /**
     * @notice Reset daily plays for all dealers (admin function)
     * @dev Updates the global reset timestamp
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
     * @notice Get the total number of active areas
     * @return The total number of areas created
     */
    function getTotalAreas() external view returns (uint8) {
        return totalAreas;
    }

    /**
     * @notice Get the total number of drug types
     * @return The total number of drugs created
     */
    function getTotalDrugs() external view returns (uint256) {
        return totalDrugs;
    }

    /**
     * @notice Get the number of reputation tiers configured
     * @return The number of reputation tiers
     */
    function getTierCount() external view returns (uint256) {
        return reputationTiers.length;
    }
}