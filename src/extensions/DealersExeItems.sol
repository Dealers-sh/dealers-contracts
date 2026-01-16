// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";
import "../IDealersExeCore.sol";
import "../IDrugRegistry.sol";
import "../IAreaRegistry.sol";
import "../IERC721Minimal.sol";
import "../IDEPaymentHandler.sol";

/**
 * @title DealersExeItems - ERC-1155 Equipment System
 * @dev Equipment items that modify dealer combat stats (Threat & Armor)
 *      - Weapons increase Threat stat (attack bonus)
 *      - Armor increases Armor stat (defense bonus)
 *      - Items can be purchased with ETH or by burning drugs
 *      - Each dealer has 1 weapon slot and 1 armor slot
 *      - Equipment stats sync to Core via setDealerStats()
 * @author Dealers.Exe Team
 */
contract DealersExeItems is ERC1155, ReentrancyGuard, Ownable {
    using LibString for uint256;

    // =============================================================
    //                            ENUMS
    // =============================================================

    /// @notice Type of item - determines which slot it equips to
    enum ItemType {
        WEAPON,     // Increases Threat stat
        ARMOR       // Increases Armor stat
    }

    /// @notice Rarity tier of item - affects stat bonus and price
    enum ItemRarity {
        COMMON,     // +1 to +5 stats
        UNCOMMON,   // +6 to +10 stats
        RARE,       // +11 to +15 stats
        LEGENDARY   // +16 to +20 stats
    }

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /**
     * @dev Item definition structure
     * @param name Display name of the item
     * @param itemType Whether item is WEAPON or ARMOR
     * @param rarity Item rarity tier
     * @param statBonus Stat bonus (+1 to +20)
     * @param ethPrice Price in wei for ETH purchase
     * @param drugPriceCommon Common drug cost for purchase
     * @param drugPriceUncommon Uncommon drug cost for purchase
     * @param drugPriceRare Rare drug cost for purchase
     * @param maxSupply Maximum supply (0 = unlimited)
     * @param currentSupply Current number minted
     * @param isActive Whether item can be purchased
     */
    struct ItemDefinition {
        string name;
        ItemType itemType;
        ItemRarity rarity;
        uint8 statBonus;
        uint256 ethPrice;
        uint256 drugPriceCommon;
        uint256 drugPriceUncommon;
        uint256 drugPriceRare;
        uint256 maxSupply;
        uint256 currentSupply;
        bool isActive;
    }

    // =============================================================
    //                            CONSTANTS
    // =============================================================

    /// @notice Drug rarity constants (must match Core)
    uint8 public constant COMMON_RARITY = 0;
    uint8 public constant UNCOMMON_RARITY = 1;
    uint8 public constant RARE_RARITY = 2;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Reference to the core dealers contract
    IDealersExeCore public core;

    /// @notice Reference to the NFT contract for ownership checks
    IERC721Minimal public nftContract;

    /// @notice Reference to payment handler for fee processing
    IDEPaymentHandler public paymentHandler;

    /// @notice Reference to the Drug Registry for rarity lookups
    IDrugRegistry public drugRegistry;

    /// @notice Reference to the Area Registry for availability checks
    IAreaRegistry public areaRegistry;

    /// @notice Item definitions: itemId => ItemDefinition
    mapping(uint256 => ItemDefinition) public items;

    /// @notice Next item ID to assign
    uint256 public nextItemId = 1;

    /// @notice Equipped weapon per dealer: dealerId => itemId (0 = none)
    mapping(uint256 => uint256) public equippedWeapon;

    /// @notice Equipped armor per dealer: dealerId => itemId (0 = none)
    mapping(uint256 => uint256) public equippedArmor;

    /// @notice Track which dealer has an item equipped: itemId => dealerId => equipped
    /// @dev Prevents transferring equipped items
    mapping(uint256 => mapping(uint256 => bool)) public itemEquippedByDealer;

    // Statistics
    uint256 public totalItemsPurchased;
    uint256 public totalETHRevenue;
    uint256 public totalDrugsBurned;

    // =============================================================
    //                            EVENTS
    // =============================================================

    /// @notice Emitted when a new item is created
    event ItemCreated(
        uint256 indexed itemId,
        string name,
        ItemType itemType,
        ItemRarity rarity,
        uint8 statBonus
    );

    /// @notice Emitted when an item is purchased
    event ItemPurchased(
        uint256 indexed itemId,
        uint256 indexed dealerId,
        address indexed buyer,
        bool paidWithETH,
        uint256 amount
    );

    /// @notice Emitted when an item is equipped
    event ItemEquipped(
        uint256 indexed dealerId,
        uint256 indexed itemId,
        ItemType itemType
    );

    /// @notice Emitted when an item is unequipped
    event ItemUnequipped(
        uint256 indexed dealerId,
        uint256 indexed itemId,
        ItemType itemType
    );

    /// @notice Emitted when dealer stats are synced to core
    event DealerStatsUpdated(
        uint256 indexed dealerId,
        uint8 threat,
        uint8 armor
    );

    /// @notice Emitted when item active status changes
    event ItemStatusChanged(uint256 indexed itemId, bool isActive);

    /// @notice Emitted when core contract is updated
    event CoreContractUpdated(address indexed oldCore, address indexed newCore);

    /// @notice Emitted when NFT contract is updated
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);

    /// @notice Emitted when payment handler is updated
    event PaymentHandlerUpdated(address indexed oldHandler, address indexed newHandler);

    /// @notice Emitted when drug registry is updated
    event DrugRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when area registry is updated
    event AreaRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error RegistryNotSet();
    error NoDrugOfRarityInArea();
    error NotDealerOwner();
    error DealerNotInitialized();
    error ItemNotFound();
    error ItemNotActive();
    error InsufficientPayment();
    error InsufficientDrugBalance();
    error InvalidDrugType();
    error LegendaryRequiresRareDrugs();
    error MaxSupplyReached();
    error ItemNotOwned();
    error ItemAlreadyEquipped();
    error ItemNotEquipped();
    error WrongItemType();
    error InvalidStatBonus();
    error InvalidAddress();
    error TransferFailed();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the items contract with default equipment
     * @param _core Address of the core dealers contract
     * @param _nftContract Address of the NFT contract
     * @param _paymentHandler Address of the payment handler
     * @param _drugRegistry Address of the drug registry
     * @param _areaRegistry Address of the area registry
     */
    constructor(
        address _core,
        address _nftContract,
        address _paymentHandler,
        address _drugRegistry,
        address _areaRegistry
    ) ERC1155("") {
        _initializeOwner(msg.sender);
        core = IDealersExeCore(_core);
        nftContract = IERC721Minimal(_nftContract);
        paymentHandler = IDEPaymentHandler(_paymentHandler);
        drugRegistry = IDrugRegistry(_drugRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);

        // Create default items
        _createDefaultItems();
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (address(core) == address(0) || address(nftContract) == address(0)) {
            revert ContractNotSet();
        }
        _;
    }

    modifier registriesSet() {
        if (address(drugRegistry) == address(0) || address(areaRegistry) == address(0)) {
            revert RegistryNotSet();
        }
        _;
    }

    modifier onlyDealerOwner(uint256 dealerId) {
        if (nftContract.ownerOf(dealerId) != msg.sender) revert NotDealerOwner();
        _;
    }

    modifier dealerExists(uint256 dealerId) {
        (, , , , , bool isInitialized) = core.getDealerData(dealerId);
        if (!isInitialized) revert DealerNotInitialized();
        _;
    }

    modifier itemExists(uint256 itemId) {
        if (itemId == 0 || itemId >= nextItemId) revert ItemNotFound();
        _;
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Create a new item type
     * @dev Only callable by owner
     * @param name Item name
     * @param itemType WEAPON or ARMOR
     * @param rarity Item rarity
     * @param statBonus Stat bonus (+1 to +20)
     * @param ethPrice ETH price in wei
     * @param drugPriceCommon Common drug cost
     * @param drugPriceUncommon Uncommon drug cost
     * @param drugPriceRare Rare drug cost
     * @param maxSupply Maximum supply (0 = unlimited)
     * @return itemId The created item's ID
     */
    function createItem(
        string calldata name,
        ItemType itemType,
        ItemRarity rarity,
        uint8 statBonus,
        uint256 ethPrice,
        uint256 drugPriceCommon,
        uint256 drugPriceUncommon,
        uint256 drugPriceRare,
        uint256 maxSupply
    ) external onlyOwner returns (uint256 itemId) {
        // Validate stat bonus based on rarity
        _validateStatBonus(rarity, statBonus);

        itemId = nextItemId++;

        items[itemId] = ItemDefinition({
            name: name,
            itemType: itemType,
            rarity: rarity,
            statBonus: statBonus,
            ethPrice: ethPrice,
            drugPriceCommon: drugPriceCommon,
            drugPriceUncommon: drugPriceUncommon,
            drugPriceRare: drugPriceRare,
            maxSupply: maxSupply,
            currentSupply: 0,
            isActive: true
        });

        emit ItemCreated(itemId, name, itemType, rarity, statBonus);
        return itemId;
    }

    /**
     * @notice Set item active status
     * @param itemId The item ID
     * @param active Whether item can be purchased
     */
    function setItemActive(uint256 itemId, bool active) external onlyOwner itemExists(itemId) {
        items[itemId].isActive = active;
        emit ItemStatusChanged(itemId, active);
    }

    /**
     * @notice Update item prices
     * @param itemId The item ID
     * @param ethPrice New ETH price
     * @param drugPriceCommon New common drug price
     * @param drugPriceUncommon New uncommon drug price
     * @param drugPriceRare New rare drug price
     */
    function updateItemPrices(
        uint256 itemId,
        uint256 ethPrice,
        uint256 drugPriceCommon,
        uint256 drugPriceUncommon,
        uint256 drugPriceRare
    ) external onlyOwner itemExists(itemId) {
        ItemDefinition storage item = items[itemId];
        item.ethPrice = ethPrice;
        item.drugPriceCommon = drugPriceCommon;
        item.drugPriceUncommon = drugPriceUncommon;
        item.drugPriceRare = drugPriceRare;
    }

    // =============================================================
    //                        PURCHASE FUNCTIONS
    // =============================================================

    /**
     * @notice Purchase an item with ETH
     * @param itemId The item to purchase
     * @param dealerId The dealer to assign the item to (for tracking/stats)
     */
    function purchaseItemWithETH(uint256 itemId, uint256 dealerId)
        external
        payable
        nonReentrant
        contractsSet
        itemExists(itemId)
        dealerExists(dealerId)
        onlyDealerOwner(dealerId)
    {
        ItemDefinition storage item = items[itemId];

        if (!item.isActive) revert ItemNotActive();
        if (item.maxSupply > 0 && item.currentSupply >= item.maxSupply) {
            revert MaxSupplyReached();
        }
        if (msg.value < item.ethPrice) revert InsufficientPayment();

        // Update supply
        unchecked { item.currentSupply++; }

        // Mint item to buyer
        _mint(msg.sender, itemId, 1, "");

        // Process payment through payment handler
        if (address(paymentHandler) != address(0) && item.ethPrice > 0) {
            paymentHandler.processMarketplaceFee{value: item.ethPrice}(item.ethPrice);
        }

        // Refund excess
        if (msg.value > item.ethPrice) {
            _safeTransferETH(msg.sender, msg.value - item.ethPrice);
        }

        // Update statistics
        unchecked {
            totalItemsPurchased++;
            totalETHRevenue += item.ethPrice;
        }

        emit ItemPurchased(itemId, dealerId, msg.sender, true, item.ethPrice);
    }

    /**
     * @notice Purchase an item by burning drugs from dealer's balance
     * @param itemId The item to purchase
     * @param dealerId The dealer to burn drugs from
     * @param drugType Which drug type to use (0=Common, 1=Uncommon, 2=Rare)
     */
    function purchaseItemWithDrugs(uint256 itemId, uint256 dealerId, uint8 drugType)
        external
        nonReentrant
        contractsSet
        registriesSet
        itemExists(itemId)
        dealerExists(dealerId)
        onlyDealerOwner(dealerId)
    {
        ItemDefinition storage item = items[itemId];

        if (!item.isActive) revert ItemNotActive();
        if (item.maxSupply > 0 && item.currentSupply >= item.maxSupply) {
            revert MaxSupplyReached();
        }
        if (drugType > RARE_RARITY) revert InvalidDrugType();

        // Legendary items can only be purchased with rare drugs
        if (item.rarity == ItemRarity.LEGENDARY && drugType != RARE_RARITY) {
            revert LegendaryRequiresRareDrugs();
        }

        // Get required drug amount based on type
        uint256 requiredAmount;
        if (drugType == COMMON_RARITY) {
            requiredAmount = item.drugPriceCommon;
        } else if (drugType == UNCOMMON_RARITY) {
            requiredAmount = item.drugPriceUncommon;
        } else {
            requiredAmount = item.drugPriceRare;
        }

        if (requiredAmount == 0) revert InvalidDrugType();

        // Get dealer's current area
        (uint8 currentArea, , , , , ) = core.getDealerData(dealerId);

        // Find a drug of the requested rarity that's available in the area
        uint256 drugId = _findDrugByRarityInArea(drugType, currentArea);
        if (drugId == 0) revert NoDrugOfRarityInArea();

        // Check dealer has enough drugs
        uint256 dealerBalance = core.getDrugBalance(dealerId, drugId);
        if (dealerBalance < requiredAmount) revert InsufficientDrugBalance();

        // Burn drugs from dealer's balance
        core.updateDrugBalance(dealerId, drugId, -int256(requiredAmount));

        // Update supply
        unchecked { item.currentSupply++; }

        // Mint item to buyer
        _mint(msg.sender, itemId, 1, "");

        // Update statistics
        unchecked {
            totalItemsPurchased++;
            totalDrugsBurned += requiredAmount;
        }

        emit ItemPurchased(itemId, dealerId, msg.sender, false, requiredAmount);
    }

    // =============================================================
    //                        EQUIPMENT FUNCTIONS
    // =============================================================

    /**
     * @notice Equip an item to a dealer
     * @dev If dealer already has an item in that slot, it gets unequipped first
     * @param itemId The item to equip
     * @param dealerId The dealer to equip the item to
     */
    function equipItem(uint256 itemId, uint256 dealerId)
        external
        nonReentrant
        contractsSet
        itemExists(itemId)
        dealerExists(dealerId)
        onlyDealerOwner(dealerId)
    {
        // Check msg.sender owns the item
        if (balanceOf(msg.sender, itemId) == 0) revert ItemNotOwned();

        ItemDefinition memory item = items[itemId];

        if (item.itemType == ItemType.WEAPON) {
            // If already has weapon equipped, unequip it first
            uint256 currentWeapon = equippedWeapon[dealerId];
            if (currentWeapon != 0) {
                _unequipInternal(currentWeapon, dealerId);
            }

            // Equip new weapon
            equippedWeapon[dealerId] = itemId;
            itemEquippedByDealer[itemId][dealerId] = true;

            emit ItemEquipped(dealerId, itemId, ItemType.WEAPON);
        } else {
            // ARMOR
            // If already has armor equipped, unequip it first
            uint256 currentArmor = equippedArmor[dealerId];
            if (currentArmor != 0) {
                _unequipInternal(currentArmor, dealerId);
            }

            // Equip new armor
            equippedArmor[dealerId] = itemId;
            itemEquippedByDealer[itemId][dealerId] = true;

            emit ItemEquipped(dealerId, itemId, ItemType.ARMOR);
        }

        // Sync stats to core
        _syncDealerStats(dealerId);
    }

    /**
     * @notice Unequip an item from a dealer
     * @param itemId The item to unequip
     * @param dealerId The dealer to unequip from
     */
    function unequipItem(uint256 itemId, uint256 dealerId)
        external
        nonReentrant
        contractsSet
        itemExists(itemId)
        dealerExists(dealerId)
        onlyDealerOwner(dealerId)
    {
        // Verify item is equipped by this dealer
        if (!itemEquippedByDealer[itemId][dealerId]) revert ItemNotEquipped();

        _unequipInternal(itemId, dealerId);

        // Sync stats to core
        _syncDealerStats(dealerId);
    }

    /**
     * @notice Internal unequip logic
     * @param itemId The item to unequip
     * @param dealerId The dealer to unequip from
     */
    function _unequipInternal(uint256 itemId, uint256 dealerId) private {
        ItemDefinition memory item = items[itemId];

        if (item.itemType == ItemType.WEAPON) {
            if (equippedWeapon[dealerId] != itemId) revert ItemNotEquipped();
            equippedWeapon[dealerId] = 0;
        } else {
            if (equippedArmor[dealerId] != itemId) revert ItemNotEquipped();
            equippedArmor[dealerId] = 0;
        }

        itemEquippedByDealer[itemId][dealerId] = false;

        emit ItemUnequipped(dealerId, itemId, item.itemType);
    }

    /**
     * @notice Sync dealer's combat stats to core based on equipped items
     * @param dealerId The dealer to sync
     */
    function _syncDealerStats(uint256 dealerId) private {
        uint8 totalThreat = 0;
        uint8 totalArmor = 0;

        // Calculate threat from weapon
        uint256 weaponId = equippedWeapon[dealerId];
        if (weaponId != 0) {
            totalThreat = items[weaponId].statBonus;
        }

        // Calculate armor from equipped armor
        uint256 armorId = equippedArmor[dealerId];
        if (armorId != 0) {
            totalArmor = items[armorId].statBonus;
        }

        // Update core stats
        core.setDealerStats(dealerId, totalThreat, totalArmor);

        emit DealerStatsUpdated(dealerId, totalThreat, totalArmor);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get item definition
     * @param itemId The item ID
     * @return The item definition struct
     */
    function getItemDefinition(uint256 itemId) external view itemExists(itemId) returns (ItemDefinition memory) {
        return items[itemId];
    }

    /**
     * @notice Get equipped items for a dealer
     * @param dealerId The dealer's token ID
     * @return weaponId The equipped weapon ID (0 if none)
     * @return armorId The equipped armor ID (0 if none)
     */
    function getEquippedItems(uint256 dealerId) external view returns (uint256 weaponId, uint256 armorId) {
        return (equippedWeapon[dealerId], equippedArmor[dealerId]);
    }

    /**
     * @notice Get dealer's combat stats from equipped items
     * @param dealerId The dealer's token ID
     * @return threat Total threat from equipped weapon
     * @return armor Total armor from equipped armor
     */
    function getDealerCombatStats(uint256 dealerId) external view returns (uint8 threat, uint8 armor) {
        uint256 weaponId = equippedWeapon[dealerId];
        uint256 armorId = equippedArmor[dealerId];

        if (weaponId != 0) {
            threat = items[weaponId].statBonus;
        }

        if (armorId != 0) {
            armor = items[armorId].statBonus;
        }

        return (threat, armor);
    }

    /**
     * @notice Check if a dealer can purchase an item with drugs
     * @param itemId The item to check
     * @param dealerId The dealer
     * @param drugType The drug type to use
     * @return canPurchase Whether purchase is possible
     * @return requiredAmount The required drug amount
     * @return dealerBalance The dealer's current balance of that drug
     */
    function canPurchaseWithDrugs(uint256 itemId, uint256 dealerId, uint8 drugType)
        external
        view
        itemExists(itemId)
        returns (bool canPurchase, uint256 requiredAmount, uint256 dealerBalance)
    {
        ItemDefinition memory item = items[itemId];

        if (!item.isActive) return (false, 0, 0);
        if (item.maxSupply > 0 && item.currentSupply >= item.maxSupply) return (false, 0, 0);
        if (drugType > RARE_RARITY) return (false, 0, 0);
        if (item.rarity == ItemRarity.LEGENDARY && drugType != RARE_RARITY) return (false, 0, 0);

        // Get required amount
        if (drugType == COMMON_RARITY) {
            requiredAmount = item.drugPriceCommon;
        } else if (drugType == UNCOMMON_RARITY) {
            requiredAmount = item.drugPriceUncommon;
        } else {
            requiredAmount = item.drugPriceRare;
        }

        if (requiredAmount == 0) return (false, 0, 0);

        // Check registries are set
        if (address(drugRegistry) == address(0) || address(areaRegistry) == address(0)) {
            return (false, requiredAmount, 0);
        }

        // Get dealer's drug balance
        (uint8 currentArea, , , , , bool isInit) = core.getDealerData(dealerId);
        if (!isInit) return (false, requiredAmount, 0);

        // Find a drug of the requested rarity that's available in the area
        uint256 drugId = _findDrugByRarityInArea(drugType, currentArea);
        if (drugId == 0) return (false, requiredAmount, 0);

        dealerBalance = core.getDrugBalance(dealerId, drugId);
        canPurchase = dealerBalance >= requiredAmount;

        return (canPurchase, requiredAmount, dealerBalance);
    }

    /**
     * @notice Get total item count
     * @return The number of items created
     */
    function getTotalItems() external view returns (uint256) {
        return nextItemId - 1;
    }

    /**
     * @notice Get all items owned by an address
     * @param owner The address to check
     * @return itemIds Array of owned item IDs
     * @return balances Array of balances for each item
     */
    function getOwnedItems(address owner) external view returns (uint256[] memory itemIds, uint256[] memory balances) {
        uint256 count = 0;

        // First pass: count owned items
        for (uint256 i = 1; i < nextItemId; ) {
            if (balanceOf(owner, i) > 0) {
                unchecked { count++; }
            }
            unchecked { ++i; }
        }

        // Allocate arrays
        itemIds = new uint256[](count);
        balances = new uint256[](count);

        // Second pass: fill arrays
        uint256 index = 0;
        for (uint256 i = 1; i < nextItemId; ) {
            uint256 bal = balanceOf(owner, i);
            if (bal > 0) {
                itemIds[index] = i;
                balances[index] = bal;
                unchecked { index++; }
            }
            unchecked { ++i; }
        }

        return (itemIds, balances);
    }

    /**
     * @notice Get statistics
     * @return purchased Total items purchased
     * @return ethRev Total ETH revenue
     * @return drugsBurned Total drugs burned
     */
    function getStats() external view returns (
        uint256 purchased,
        uint256 ethRev,
        uint256 drugsBurned
    ) {
        return (totalItemsPurchased, totalETHRevenue, totalDrugsBurned);
    }

    // =============================================================
    //                        URI FUNCTIONS
    // =============================================================

    /**
     * @notice Returns metadata URI for an item
     * @param itemId The item ID
     * @return Base64 encoded JSON metadata
     */
    function uri(uint256 itemId) public view override returns (string memory) {
        if (itemId == 0 || itemId >= nextItemId) return "";

        ItemDefinition memory item = items[itemId];

        string memory itemTypeStr = item.itemType == ItemType.WEAPON ? "Weapon" : "Armor";
        string memory rarityStr;
        if (item.rarity == ItemRarity.COMMON) rarityStr = "Common";
        else if (item.rarity == ItemRarity.UNCOMMON) rarityStr = "Uncommon";
        else if (item.rarity == ItemRarity.RARE) rarityStr = "Rare";
        else rarityStr = "Legendary";

        bytes memory json = abi.encodePacked(
            '{"name":"', item.name,
            '","description":"Drug Wars Equipment Item - ', itemTypeStr, ' (', rarityStr, ')',
            '","attributes":[',
            '{"trait_type":"Type","value":"', itemTypeStr, '"},',
            '{"trait_type":"Rarity","value":"', rarityStr, '"},',
            '{"trait_type":"Stat Bonus","value":"', uint256(item.statBonus).toString(), '"},',
            '{"trait_type":"Supply","value":"', item.currentSupply.toString(),
            item.maxSupply > 0 ? string(abi.encodePacked('/', item.maxSupply.toString())) : '/Unlimited',
            '"}]}'
        );

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(json)
        ));
    }

    // =============================================================
    //                        TRANSFER HOOKS
    // =============================================================

    /**
     * @notice Hook called before any token transfer
     * @dev Note: Equipped items are tracked per dealer via itemEquippedByDealer mapping.
     *      Users must unequip items before transferring them to ensure stats remain consistent.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override {
        super._update(from, to, ids, values);
    }

    // =============================================================
    //                     ADMIN CONTRACT SETTERS
    // =============================================================

    /**
     * @notice Update core contract reference
     * @param _core New core contract address
     */
    function setCore(address _core) external onlyOwner {
        if (_core == address(0)) revert InvalidAddress();
        address old = address(core);
        core = IDealersExeCore(_core);
        emit CoreContractUpdated(old, _core);
    }

    /**
     * @notice Update NFT contract reference
     * @param _nftContract New NFT contract address
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert InvalidAddress();
        address old = address(nftContract);
        nftContract = IERC721Minimal(_nftContract);
        emit NFTContractUpdated(old, _nftContract);
    }

    /**
     * @notice Update payment handler reference
     * @param _paymentHandler New payment handler address
     */
    function setPaymentHandler(address _paymentHandler) external onlyOwner {
        if (_paymentHandler == address(0)) revert InvalidAddress();
        address old = address(paymentHandler);
        paymentHandler = IDEPaymentHandler(_paymentHandler);
        emit PaymentHandlerUpdated(old, _paymentHandler);
    }

    /**
     * @notice Update drug registry reference
     * @param _drugRegistry New drug registry address
     */
    function setDrugRegistry(address _drugRegistry) external onlyOwner {
        if (_drugRegistry == address(0)) revert InvalidAddress();
        address old = address(drugRegistry);
        drugRegistry = IDrugRegistry(_drugRegistry);
        emit DrugRegistryUpdated(old, _drugRegistry);
    }

    /**
     * @notice Update area registry reference
     * @param _areaRegistry New area registry address
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert InvalidAddress();
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Find a drug of the specified rarity that's available in an area
     * @param drugType The drug rarity (0=Common, 1=Uncommon, 2=Rare)
     * @param areaId The area to check
     * @return drugId The drug ID if found, 0 if not found
     */
    function _findDrugByRarityInArea(uint8 drugType, uint8 areaId) private view returns (uint256 drugId) {
        // Map drugType (0,1,2) to DrugRarity enum
        IDrugRegistry.DrugRarity rarity;
        if (drugType == COMMON_RARITY) {
            rarity = IDrugRegistry.DrugRarity.COMMON;
        } else if (drugType == UNCOMMON_RARITY) {
            rarity = IDrugRegistry.DrugRarity.UNCOMMON;
        } else {
            rarity = IDrugRegistry.DrugRarity.RARE;
        }

        // Get all drugs of this rarity
        uint256[] memory drugsOfRarity = drugRegistry.getDrugsByRarity(rarity);

        // Find one that's available in the area
        for (uint256 i = 0; i < drugsOfRarity.length; ) {
            if (areaRegistry.isDrugAvailableInArea(areaId, drugsOfRarity[i])) {
                return drugsOfRarity[i];
            }
            unchecked { ++i; }
        }

        return 0; // No drug found
    }

    /**
     * @notice Validate stat bonus is within range for rarity
     * @param rarity The item rarity
     * @param statBonus The stat bonus value
     */
    function _validateStatBonus(ItemRarity rarity, uint8 statBonus) private pure {
        if (rarity == ItemRarity.COMMON) {
            if (statBonus < 1 || statBonus > 5) revert InvalidStatBonus();
        } else if (rarity == ItemRarity.UNCOMMON) {
            if (statBonus < 6 || statBonus > 10) revert InvalidStatBonus();
        } else if (rarity == ItemRarity.RARE) {
            if (statBonus < 11 || statBonus > 15) revert InvalidStatBonus();
        } else {
            // LEGENDARY
            if (statBonus < 16 || statBonus > 20) revert InvalidStatBonus();
        }
    }

    /**
     * @notice Safe ETH transfer using .call() for Abstract Chain compatibility
     * @param to Recipient address
     * @param amount Amount to send
     */
    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Create default item set
     * @dev Called during construction
     */
    function _createDefaultItems() private {
        // === WEAPONS ===

        // Common Weapons (+1 to +5)
        _createItemInternal(
            "Brass Knuckles",
            ItemType.WEAPON,
            ItemRarity.COMMON,
            3,
            0.005 ether,
            5000,    // common drugs
            500,     // uncommon drugs
            50,      // rare drugs
            0        // unlimited
        );

        // Uncommon Weapons (+6 to +10)
        _createItemInternal(
            "Switchblade",
            ItemType.WEAPON,
            ItemRarity.UNCOMMON,
            7,
            0.03 ether,
            20000,
            2000,
            200,
            0
        );

        // Rare Weapons (+11 to +15)
        _createItemInternal(
            "Glock 19",
            ItemType.WEAPON,
            ItemRarity.RARE,
            12,
            0.15 ether,
            100000,
            10000,
            1000,
            0
        );

        // Legendary Weapons (+16 to +20)
        _createItemInternal(
            "Golden AK-47",
            ItemType.WEAPON,
            ItemRarity.LEGENDARY,
            18,
            0.75 ether,
            0,       // Legendary can't be bought with common
            0,       // Legendary can't be bought with uncommon
            5000,    // Only rare drugs
            100      // Limited supply
        );

        // === ARMOR ===

        // Common Armor (+1 to +5)
        _createItemInternal(
            "Leather Jacket",
            ItemType.ARMOR,
            ItemRarity.COMMON,
            3,
            0.005 ether,
            5000,
            500,
            50,
            0
        );

        // Uncommon Armor (+6 to +10)
        _createItemInternal(
            "Kevlar Vest",
            ItemType.ARMOR,
            ItemRarity.UNCOMMON,
            8,
            0.04 ether,
            20000,
            2000,
            200,
            0
        );

        // Rare Armor (+11 to +15)
        _createItemInternal(
            "Full Body Armor",
            ItemType.ARMOR,
            ItemRarity.RARE,
            14,
            0.18 ether,
            100000,
            10000,
            1000,
            0
        );

        // Legendary Armor (+16 to +20)
        _createItemInternal(
            "Diamond Suit",
            ItemType.ARMOR,
            ItemRarity.LEGENDARY,
            20,
            1 ether,
            0,
            0,
            5000,
            50       // Limited supply
        );
    }

    /**
     * @notice Internal function to create items during construction
     */
    function _createItemInternal(
        string memory name,
        ItemType itemType,
        ItemRarity rarity,
        uint8 statBonus,
        uint256 ethPrice,
        uint256 drugPriceCommon,
        uint256 drugPriceUncommon,
        uint256 drugPriceRare,
        uint256 maxSupply
    ) private {
        uint256 itemId = nextItemId++;

        items[itemId] = ItemDefinition({
            name: name,
            itemType: itemType,
            rarity: rarity,
            statBonus: statBonus,
            ethPrice: ethPrice,
            drugPriceCommon: drugPriceCommon,
            drugPriceUncommon: drugPriceUncommon,
            drugPriceRare: drugPriceRare,
            maxSupply: maxSupply,
            currentSupply: 0,
            isActive: true
        });

        emit ItemCreated(itemId, name, itemType, rarity, statBonus);
    }
}
