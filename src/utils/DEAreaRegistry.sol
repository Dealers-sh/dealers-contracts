// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IAreaRegistry.sol";
import "./IDrugRegistry.sol";

/**
 * @title DEAreaRegistry - Area and Drug Pricing Registry
 * @dev Manages area definitions, drug availability per area, and buy/sell pricing
 *      Supports flexible drug configurations per area (not limited to 3)
 * @author Dealers.Exe Team
 */
contract DEAreaRegistry is Ownable, IAreaRegistry {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    /// @notice Safe House area ID
    uint8 public constant SAFE_HOUSE_AREA = 0;

    /// @notice Jail area ID
    uint8 public constant JAIL_AREA = 255;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Area ID => Area Info
    mapping(uint8 => AreaInfo) private _areas;

    /// @notice Area ID => Drug ID => Drug Config
    mapping(uint8 => mapping(uint256 => AreaDrugConfig)) private _areaDrugs;

    /// @notice Area ID => Array of drug IDs available in that area
    mapping(uint8 => uint256[]) private _areaDrugIds;

    /// @notice Total number of regular areas (excludes Safe House and Jail)
    uint8 private _totalAreas;

    /// @notice Reference to the Drug Registry for validation
    IDrugRegistry public drugRegistry;

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidAreaId();
    error AreaNotActive();
    error AreaAlreadyExists();
    error InvalidDrugId();
    error DrugNotInArea();
    error AreaNameTooLong();
    error DrugRegistryNotSet();
    error DrugAlreadyInArea();
    error InvalidPricing();

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
        _createManhattan();
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier validArea(uint8 areaId) {
        if (!_isValidAreaId(areaId)) revert InvalidAreaId();
        if (!_areas[areaId].isActive) revert AreaNotActive();
        _;
    }

    // =============================================================
    //                        INITIALIZATION
    // =============================================================

    /**
     * @notice Create the Safe House area (ID 0)
     */
    function _createSafeHouse() private {
        _areas[SAFE_HOUSE_AREA] = AreaInfo({
            name: "Safe House",
            movementFee: 0,
            minReputation: 0,
            isActive: true,
            isSafeHouse: true,
            isJail: false
        });

        emit AreaCreated(SAFE_HOUSE_AREA, "Safe House", true, false);
    }

    /**
     * @notice Create the Jail area (ID 255)
     */
    function _createJail() private {
        _areas[JAIL_AREA] = AreaInfo({
            name: "Jail",
            movementFee: 0.005 ether,  // Bail amount
            minReputation: 0,
            isActive: true,
            isSafeHouse: false,
            isJail: true
        });

        emit AreaCreated(JAIL_AREA, "Jail", false, true);
    }

    /**
     * @notice Create Manhattan as the first regular area (ID 1)
     */
    function _createManhattan() private {
        _totalAreas = 1;

        _areas[1] = AreaInfo({
            name: "Manhattan",
            movementFee: 0.001 ether,
            minReputation: 0,  // Starting area
            isActive: true,
            isSafeHouse: false,
            isJail: false
        });

        // Configure drugs for Manhattan with pricing
        // Weed (ID 1): Common - base value 1
        _configureAreaDrug(1, 1, 1, 1);      // Buy: 1, Sell: 1

        // XTC (ID 2): Uncommon - base value 10, 20% markup
        _configureAreaDrug(1, 2, 12, 10);    // Buy: 12, Sell: 10

        // Cocaine (ID 3): Rare - base value 100, 20% markup
        _configureAreaDrug(1, 3, 120, 100);  // Buy: 120, Sell: 100

        emit AreaCreated(1, "Manhattan", false, false);
    }

    /**
     * @notice Internal function to configure a drug for an area
     * @param areaId The area ID
     * @param drugId The drug ID
     * @param buyPrice Buy price in $CASH
     * @param sellPrice Sell price in $CASH
     */
    function _configureAreaDrug(
        uint8 areaId,
        uint256 drugId,
        uint256 buyPrice,
        uint256 sellPrice
    ) private {
        _areaDrugs[areaId][drugId] = AreaDrugConfig({
            drugId: drugId,
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            isAvailable: true
        });

        _areaDrugIds[areaId].push(drugId);

        emit AreaDrugConfigured(areaId, drugId, buyPrice, sellPrice);
    }

    /**
     * @notice Check if an area ID is valid
     * @param areaId The area ID to check
     * @return Whether the area ID is valid
     */
    function _isValidAreaId(uint8 areaId) private view returns (bool) {
        // Safe House (0) and Jail (255) are always valid if active
        if (areaId == SAFE_HOUSE_AREA || areaId == JAIL_AREA) {
            return true;
        }
        // Regular areas: must be between 1 and _totalAreas
        return areaId > 0 && areaId <= _totalAreas;
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /// @inheritdoc IAreaRegistry
    function getAreaInfo(uint8 areaId) external view validArea(areaId) returns (AreaInfo memory) {
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
    function getAreaDrugConfig(uint8 areaId, uint256 drugId) external view validArea(areaId) returns (AreaDrugConfig memory) {
        AreaDrugConfig memory config = _areaDrugs[areaId][drugId];
        if (!config.isAvailable) revert DrugNotInArea();
        return config;
    }

    /// @inheritdoc IAreaRegistry
    function getAreaDrugIds(uint8 areaId) external view validArea(areaId) returns (uint256[] memory) {
        return _areaDrugIds[areaId];
    }

    /// @inheritdoc IAreaRegistry
    function getDrugPricing(uint8 areaId, uint256 drugId) external view validArea(areaId) returns (uint256 buyPrice, uint256 sellPrice) {
        AreaDrugConfig memory config = _areaDrugs[areaId][drugId];
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

        unchecked {
            ++_totalAreas;
        }

        areaId = _totalAreas;

        _areas[areaId] = AreaInfo({
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

        _areaDrugs[areaId][drugId] = AreaDrugConfig({
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
        drugRegistry = IDrugRegistry(_drugRegistry);
    }
}
