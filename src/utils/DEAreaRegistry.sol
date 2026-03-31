// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IAreaRegistry} from "./IAreaRegistry.sol";
import {IDrugRegistry} from "./IDrugRegistry.sol";

/**
 * @title DEAreaRegistry - Area and Drug Pricing Registry
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Manages area definitions, drug availability per area, and buy/sell pricing
 * @author HeadmasterBerny
 */
contract DEAreaRegistry is Ownable, IAreaRegistry {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    /// @notice Safe House area ID
    uint8 public constant SAFE_HOUSE_AREA = 0;
    uint8 public constant BLACK_MARKET_AREA = 254;

    /// @notice Jail area ID
    uint8 public constant JAIL_AREA = 255;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Area ID => Area Info
    mapping(uint8 => IAreaRegistry.AreaInfo) private _areas;

    /// @notice Area ID => Drug ID => Drug Config
    mapping(uint8 => mapping(uint256 => IAreaRegistry.AreaDrugConfig)) private _areaDrugs;

    /// @notice Area ID => Array of drug IDs available in that area
    mapping(uint8 => uint256[]) private _areaDrugIds;

    /// @notice Total number of regular areas (excludes Safe House and Jail)
    uint8 private _totalAreas;

    /// @notice Reference to the Drug Registry for validation
    IDrugRegistry public drugRegistry;

    /// @notice Reference to the Core contract (authorized to update dealer locations)
    address public coreContract;

    /// @notice Area ID => Array of dealer tokenIds in that area
    mapping(uint8 => uint256[]) private _dealersInArea;

    /// @notice TokenId => Index position in the area's dealer array
    mapping(uint256 => uint256) private _dealerAreaIndex;

    /// @notice TokenId => Current area (to validate oldArea in updates)
    mapping(uint256 => uint8) private _dealerCurrentArea;

    /// @notice TokenId => Whether dealer has been registered
    mapping(uint256 => bool) private _dealerRegistered;

    /// @notice Area ID => Whether this area is the Black Market
    mapping(uint8 => bool) private _isBlackMarket;

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidAreaId();
    error AreaNotActive();
    error InvalidDrugId();
    error DrugNotInArea();
    error AreaNameTooLong();
    error DrugRegistryNotSet();
    error InvalidPricing();
    error MaxAreasReached();
    error InvalidAddress();
    error ArrayLengthMismatch();
    error NotAuthorized();
    error CoreContractNotSet();
    error InvalidOldArea();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the Area Registry with Safe House, Jail, and Manhattan
     * @param _drugRegistry Address of the Drug Registry contract
     */
    constructor(address _drugRegistry) {
        _initializeOwner(msg.sender);
        drugRegistry = IDrugRegistry(_drugRegistry);

        _createSafeHouse();
        _createJail();
        _createBlackMarket();
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier validArea(uint8 areaId) {
        if (!_isValidAreaId(areaId)) revert InvalidAreaId();
        if (!_areas[areaId].isActive) revert AreaNotActive();
        _;
    }

    modifier onlyCore() {
        if (coreContract == address(0)) revert CoreContractNotSet();
        if (msg.sender != coreContract) revert NotAuthorized();
        _;
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /// @inheritdoc IAreaRegistry
    function getAreaInfo(uint8 areaId) external view validArea(areaId) returns (IAreaRegistry.AreaInfo memory) {
        return _areas[areaId];
    }

    /// @inheritdoc IAreaRegistry
    function getMovementFee(uint8 areaId) external view validArea(areaId) returns (uint256) {
        return _areas[areaId].movementFee;
    }

    /// @inheritdoc IAreaRegistry
    function getMinReputation(uint8 areaId) external view validArea(areaId) returns (uint256) {
        return _areas[areaId].minReputation;
    }

    /// @inheritdoc IAreaRegistry
    function isAreaActive(uint8 areaId) external view returns (bool) {
        if (!_isValidAreaId(areaId)) return false;
        return _areas[areaId].isActive;
    }

    /// @inheritdoc IAreaRegistry
    function isSafeHouse(uint8 areaId) external view returns (bool) {
        return _areas[areaId].isSafeHouse;
    }

    /// @inheritdoc IAreaRegistry
    function isJail(uint8 areaId) external view returns (bool) {
        return _areas[areaId].isJail;
    }

    /// @inheritdoc IAreaRegistry
    function isBlackMarket(uint8 areaId) external view returns (bool) {
        return _isBlackMarket[areaId];
    }

    /// @inheritdoc IAreaRegistry
    function getTotalAreas() external view returns (uint8) {
        return _totalAreas;
    }

    /// @inheritdoc IAreaRegistry
    function isValidArea(uint8 areaId) external view returns (bool) {
        if (!_isValidAreaId(areaId)) return false;
        return _areas[areaId].isActive;
    }

    // =============================================================
    //                    DRUG PRICING FUNCTIONS
    // =============================================================

    /// @inheritdoc IAreaRegistry
    function getAreaDrugConfig(uint8 areaId, uint256 drugId) external view validArea(areaId) returns (IAreaRegistry.AreaDrugConfig memory) {
        IAreaRegistry.AreaDrugConfig memory config = _areaDrugs[areaId][drugId];
        if (!config.isAvailable) revert DrugNotInArea();
        return config;
    }

    /// @inheritdoc IAreaRegistry
    function getAreaDrugIds(uint8 areaId) external view validArea(areaId) returns (uint256[] memory) {
        return _areaDrugIds[areaId];
    }

    /// @inheritdoc IAreaRegistry
    function getDrugPricing(uint8 areaId, uint256 drugId) external view validArea(areaId) returns (uint256 buyPrice, uint256 sellPrice) {
        IAreaRegistry.AreaDrugConfig memory config = _areaDrugs[areaId][drugId];
        if (!config.isAvailable) revert DrugNotInArea();
        return (config.buyPrice, config.sellPrice);
    }

    /// @inheritdoc IAreaRegistry
    function isDrugAvailableInArea(uint8 areaId, uint256 drugId) external view returns (bool) {
        if (!_isValidAreaId(areaId)) return false;
        return _areaDrugs[areaId][drugId].isAvailable;
    }

    /// @inheritdoc IAreaRegistry
    function getAreaDrugCount(uint8 areaId) external view validArea(areaId) returns (uint256) {
        return _areaDrugIds[areaId].length;
    }

    // =============================================================
    //                   DEALER LOCATION FUNCTIONS
    // =============================================================

    /// @inheritdoc IAreaRegistry
    function updateDealerLocation(uint256 tokenId, uint8 oldArea, uint8 newArea) external onlyCore {
        if (oldArea == newArea) return;

        if (_dealerRegistered[tokenId] && _dealerCurrentArea[tokenId] != oldArea) {
            revert InvalidOldArea();
        }

        if (_dealerRegistered[tokenId]) {
            uint256[] storage oldList = _dealersInArea[oldArea];
            uint256 index = _dealerAreaIndex[tokenId];
            uint256 lastIdx = oldList.length - 1;

            if (index != lastIdx) {
                uint256 lastTokenId = oldList[lastIdx];
                oldList[index] = lastTokenId;
                _dealerAreaIndex[lastTokenId] = index;
            }
            oldList.pop();
        }

        _dealersInArea[newArea].push(tokenId);
        _dealerAreaIndex[tokenId] = _dealersInArea[newArea].length - 1;
        _dealerCurrentArea[tokenId] = newArea;
        _dealerRegistered[tokenId] = true;

        emit DealerLocationUpdated(tokenId, oldArea, newArea);
    }

    /// @notice Seed the dealer-in-area reverse index after redeploying this contract.
    ///         Call in batches (e.g. 500) to avoid gas limits. Skips already-registered dealers.
    function seedDealerLocations(uint256[] calldata tokenIds, uint8[] calldata areas) external onlyOwner {
        if (tokenIds.length != areas.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];
            uint8 area = areas[i];

            if (!_dealerRegistered[tokenId]) {
                _dealersInArea[area].push(tokenId);
                _dealerAreaIndex[tokenId] = _dealersInArea[area].length - 1;
                _dealerCurrentArea[tokenId] = area;
                _dealerRegistered[tokenId] = true;
            }

            unchecked { ++i; }
        }
    }

    /// @inheritdoc IAreaRegistry
    function getDealersInArea(uint8 areaId, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory tokenIds, uint256 total)
    {
        uint256[] storage allInArea = _dealersInArea[areaId];
        total = allInArea.length;

        if (offset >= total || limit == 0) {
            return (new uint256[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 resultLength = end - offset;

        tokenIds = new uint256[](resultLength);
        for (uint256 i = 0; i < resultLength;) {
            tokenIds[i] = allInArea[offset + i];
            unchecked { ++i; }
        }
    }

    /// @inheritdoc IAreaRegistry
    function getDealerCountInArea(uint8 areaId) external view returns (uint256) {
        return _dealersInArea[areaId].length;
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Create a new area
     * @dev Only callable by owner
     * @param name Area display name (max 32 chars)
     * @param movementFee Cost in wei to move to this area
     * @param minReputation Minimum reputation to enter
     * @param isSafeHouseArea Whether this is a safe house
     * @param isJailArea Whether this is jail
     * @return areaId The ID of the newly created area
     */
    function createArea(
        string calldata name,
        uint256 movementFee,
        uint256 minReputation,
        bool isSafeHouseArea,
        bool isJailArea
    ) external onlyOwner returns (uint8 areaId) {
        if (bytes(name).length > 32) revert AreaNameTooLong();
        if (_totalAreas >= 254) revert MaxAreasReached();

        unchecked {
            ++_totalAreas;
        }

        areaId = _totalAreas;

        _areas[areaId] = IAreaRegistry.AreaInfo({
            name: name,
            movementFee: movementFee,
            minReputation: minReputation,
            isActive: true,
            isSafeHouse: isSafeHouseArea,
            isJail: isJailArea
        });

        emit AreaCreated(areaId, name, isSafeHouseArea, isJailArea);
        return areaId;
    }

    /**
     * @notice Configure a drug for an area
     * @dev Only callable by owner. Validates drug exists in DrugRegistry
     * @param areaId The area ID
     * @param drugId The drug ID (must exist in DrugRegistry)
     * @param buyPrice Buy price in $CASH
     * @param sellPrice Sell price in $CASH
     */
    function configureAreaDrug(
        uint8 areaId,
        uint256 drugId,
        uint256 buyPrice,
        uint256 sellPrice
    ) external onlyOwner validArea(areaId) {
        // Validate drug exists in registry
        if (address(drugRegistry) == address(0)) revert DrugRegistryNotSet();
        if (!drugRegistry.isValidDrug(drugId)) revert InvalidDrugId();

        // Validate pricing
        if (buyPrice == 0 || sellPrice == 0) revert InvalidPricing();

        // Check if drug already exists in area
        bool exists = _areaDrugs[areaId][drugId].isAvailable;

        _areaDrugs[areaId][drugId] = IAreaRegistry.AreaDrugConfig({
            drugId: drugId,
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            isAvailable: true
        });

        // Only add to array if new
        if (!exists) {
            _areaDrugIds[areaId].push(drugId);
        }

        emit AreaDrugConfigured(areaId, drugId, buyPrice, sellPrice);
    }

    /**
     * @notice Remove a drug from an area
     * @dev Only callable by owner
     * @param areaId The area ID
     * @param drugId The drug ID to remove
     */
    function removeAreaDrug(uint8 areaId, uint256 drugId) external onlyOwner validArea(areaId) {
        if (!_areaDrugs[areaId][drugId].isAvailable) revert DrugNotInArea();

        _areaDrugs[areaId][drugId].isAvailable = false;

        // Remove from array (swap and pop)
        uint256[] storage drugIds = _areaDrugIds[areaId];
        for (uint256 i = 0; i < drugIds.length; ) {
            if (drugIds[i] == drugId) {
                drugIds[i] = drugIds[drugIds.length - 1];
                drugIds.pop();
                break;
            }
            unchecked { ++i; }
        }

        emit AreaDrugRemoved(areaId, drugId);
    }

    /**
     * @notice Update area movement fee
     * @dev Only callable by owner
     * @param areaId The area ID
     * @param newFee The new movement fee in wei
     */
    function updateMovementFee(uint8 areaId, uint256 newFee) external onlyOwner validArea(areaId) {
        _areas[areaId].movementFee = newFee;
        emit AreaUpdated(areaId, newFee, _areas[areaId].minReputation, _areas[areaId].isActive);
    }

    /**
     * @notice Update area minimum reputation
     * @dev Only callable by owner
     * @param areaId The area ID
     * @param newMinRep The new minimum reputation
     */
    function updateMinReputation(uint8 areaId, uint256 newMinRep) external onlyOwner validArea(areaId) {
        _areas[areaId].minReputation = newMinRep;
        emit AreaUpdated(areaId, _areas[areaId].movementFee, newMinRep, _areas[areaId].isActive);
    }

    /**
     * @notice Activate or deactivate an area
     * @dev Only callable by owner
     * @param areaId The area ID
     * @param active Whether the area should be active
     */
    function setAreaActive(uint8 areaId, bool active) external onlyOwner {
        if (!_isValidAreaId(areaId)) revert InvalidAreaId();
        _areas[areaId].isActive = active;
        emit AreaUpdated(areaId, _areas[areaId].movementFee, _areas[areaId].minReputation, active);
    }

    /**
     * @notice Update drug pricing for an area
     * @dev Only callable by owner
     * @param areaId The area ID
     * @param drugId The drug ID
     * @param buyPrice New buy price
     * @param sellPrice New sell price
     */
    function updateDrugPricing(
        uint8 areaId,
        uint256 drugId,
        uint256 buyPrice,
        uint256 sellPrice
    ) external onlyOwner validArea(areaId) {
        if (!_areaDrugs[areaId][drugId].isAvailable) revert DrugNotInArea();
        if (buyPrice == 0 || sellPrice == 0) revert InvalidPricing();

        _areaDrugs[areaId][drugId].buyPrice = buyPrice;
        _areaDrugs[areaId][drugId].sellPrice = sellPrice;

        emit AreaDrugConfigured(areaId, drugId, buyPrice, sellPrice);
    }

    /**
     * @notice Update the Drug Registry reference
     * @dev Only callable by owner
     * @param _drugRegistry The new Drug Registry address
     */
    function setDrugRegistry(address _drugRegistry) external onlyOwner {
        if (_drugRegistry == address(0)) revert InvalidAddress();
        address oldRegistry = address(drugRegistry);
        drugRegistry = IDrugRegistry(_drugRegistry);
        emit DrugRegistryUpdated(oldRegistry, _drugRegistry);
    }

    /**
     * @notice Set the Core contract address (authorized to update dealer locations)
     * @dev Only callable by owner
     * @param _coreContract The Core contract address
     */
    function setCoreContract(address _coreContract) external onlyOwner {
        if (_coreContract == address(0)) revert InvalidAddress();
        address oldCore = coreContract;
        coreContract = _coreContract;
        emit CoreContractUpdated(oldCore, _coreContract);
    }

    /**
     * @notice Batch configure multiple drugs for an area
     * @dev Only callable by owner. Validates drugs exist in DrugRegistry
     * @param areaId The area ID
     * @param drugIds Array of drug IDs (must exist in DrugRegistry)
     * @param buyPrices Array of buy prices in $CASH
     * @param sellPrices Array of sell prices in $CASH
     */
    function batchConfigureAreaDrugs(
        uint8 areaId,
        uint256[] calldata drugIds,
        uint256[] calldata buyPrices,
        uint256[] calldata sellPrices
    ) external onlyOwner validArea(areaId) {
        uint256 length = drugIds.length;
        if (length != buyPrices.length || length != sellPrices.length) {
            revert ArrayLengthMismatch();
        }
        if (address(drugRegistry) == address(0)) revert DrugRegistryNotSet();

        for (uint256 i = 0; i < length; ) {
            uint256 drugId = drugIds[i];
            uint256 buyPrice = buyPrices[i];
            uint256 sellPrice = sellPrices[i];

            if (!drugRegistry.isValidDrug(drugId)) revert InvalidDrugId();
            if (buyPrice == 0 || sellPrice == 0) revert InvalidPricing();

            bool exists = _areaDrugs[areaId][drugId].isAvailable;

            _areaDrugs[areaId][drugId] = IAreaRegistry.AreaDrugConfig({
                drugId: drugId,
                buyPrice: buyPrice,
                sellPrice: sellPrice,
                isAvailable: true
            });

            if (!exists) {
                _areaDrugIds[areaId].push(drugId);
            }

            emit AreaDrugConfigured(areaId, drugId, buyPrice, sellPrice);

            unchecked { ++i; }
        }
    }

    // =============================================================
    //                   INTERNAL/PRIVATE HELPER FUNCTIONS
    // =============================================================

    function _createSafeHouse() private {
        _areas[SAFE_HOUSE_AREA] = IAreaRegistry.AreaInfo({
            name: "Safe House",
            movementFee: 0,
            minReputation: 0,
            isActive: true,
            isSafeHouse: true,
            isJail: false
        });

        emit AreaCreated(SAFE_HOUSE_AREA, "Safe House", true, false);
    }

    function _createJail() private {
        _areas[JAIL_AREA] = IAreaRegistry.AreaInfo({
            name: "Jail",
            movementFee: 0.001 ether,
            minReputation: 0,
            isActive: true,
            isSafeHouse: false,
            isJail: true
        });

        emit AreaCreated(JAIL_AREA, "Jail", false, true);
    }

    function _createBlackMarket() private {
        _areas[BLACK_MARKET_AREA] = IAreaRegistry.AreaInfo({
            name: "Black Market",
            movementFee: 0,
            minReputation: 100,
            isActive: true,
            isSafeHouse: false,
            isJail: false
        });

        _isBlackMarket[BLACK_MARKET_AREA] = true;

        _configureAreaDrug(BLACK_MARKET_AREA, 1, 75, 75);
        _configureAreaDrug(BLACK_MARKET_AREA, 2, 500, 500);
        _configureAreaDrug(BLACK_MARKET_AREA, 3, 2500, 2500);

        emit AreaCreated(BLACK_MARKET_AREA, "Black Market", false, false);
    }

    function _configureAreaDrug(
        uint8 areaId,
        uint256 drugId,
        uint256 buyPrice,
        uint256 sellPrice
    ) private {
        _areaDrugs[areaId][drugId] = IAreaRegistry.AreaDrugConfig({
            drugId: drugId,
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            isAvailable: true
        });

        _areaDrugIds[areaId].push(drugId);

        emit AreaDrugConfigured(areaId, drugId, buyPrice, sellPrice);
    }

    function _isValidAreaId(uint8 areaId) private view returns (bool) {
        if (areaId == SAFE_HOUSE_AREA || areaId == JAIL_AREA || areaId == BLACK_MARKET_AREA) {
            return true;
        }
        return areaId > 0 && areaId <= _totalAreas;
    }
}
