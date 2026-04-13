// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IAreaRegistry - Interface for Area Registry
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for area definitions, drug availability per area, and pricing
 * @author Berny0x
 */
interface IAreaRegistry {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    /**
     * @dev Area-specific drug pricing configuration
     */
    struct AreaDrugConfig {
        uint256 drugId;
        uint256 buyPrice;
        uint256 sellPrice;
        bool isAvailable;
    }

    /**
     * @dev Area configuration structure
     */
    struct AreaInfo {
        string name;
        uint256 movementFee;
        uint256 minReputation;
        bool isActive;
        bool isSafeHouse;
        bool isJail;
    }

    // =============================================================
    //                           EVENTS
    // =============================================================

    event AreaCreated(uint8 indexed areaId, string name, bool isSafeHouse, bool isJail);
    event AreaUpdated(uint8 indexed areaId, uint256 movementFee, uint256 minReputation, bool isActive);
    event AreaDrugConfigured(uint8 indexed areaId, uint256 indexed drugId, uint256 buyPrice, uint256 sellPrice);
    event AreaDrugRemoved(uint8 indexed areaId, uint256 indexed drugId);
    event DrugRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event DealerLocationUpdated(uint256 indexed tokenId, uint8 indexed oldArea, uint8 indexed newArea);
    event CoreContractUpdated(address indexed oldCore, address indexed newCore);

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Get detailed information about an area
    function getAreaInfo(uint8 areaId) external view returns (AreaInfo memory);

    /// @notice Get the movement fee for an area
    function getMovementFee(uint8 areaId) external view returns (uint256);

    /// @notice Get the minimum reputation to enter an area
    function getMinReputation(uint8 areaId) external view returns (uint256);

    /// @notice Check if an area is active
    function isAreaActive(uint8 areaId) external view returns (bool);

    /// @notice Check if an area is a safe house
    function isSafeHouse(uint8 areaId) external view returns (bool);

    /// @notice Check if an area is jail
    function isJail(uint8 areaId) external view returns (bool);

    /// @notice Check if an area is the Black Market
    function isBlackMarket(uint8 areaId) external view returns (bool);

    /// @notice Get total number of areas (excluding special areas)
    function getTotalAreas() external view returns (uint8);

    /// @notice Check if an area ID is valid
    function isValidArea(uint8 areaId) external view returns (bool);

    // =============================================================
    //                    DRUG PRICING FUNCTIONS
    // =============================================================

    /// @notice Get drug configuration for a specific drug in an area
    function getAreaDrugConfig(uint8 areaId, uint256 drugId) external view returns (AreaDrugConfig memory);

    /// @notice Get all drug IDs available in an area
    function getAreaDrugIds(uint8 areaId) external view returns (uint256[] memory);

    /// @notice Get buy and sell prices for a drug in an area
    function getDrugPricing(uint8 areaId, uint256 drugId) external view returns (uint256 buyPrice, uint256 sellPrice);

    /// @notice Check if a drug is available in an area
    function isDrugAvailableInArea(uint8 areaId, uint256 drugId) external view returns (bool);

    /// @notice Get the number of drugs available in an area
    function getAreaDrugCount(uint8 areaId) external view returns (uint256);

    // =============================================================
    //                    DEALER LOCATION FUNCTIONS
    // =============================================================

    /// @notice Update a dealer's location (called by Core contract)
    function updateDealerLocation(uint256 tokenId, uint8 oldArea, uint8 newArea) external;

    /// @notice Get all dealer token IDs in an area (paginated)
    function getDealersInArea(uint8 areaId, uint256 offset, uint256 limit) external view returns (uint256[] memory tokenIds, uint256 total);

    /// @notice Get the count of dealers in an area
    function getDealerCountInArea(uint8 areaId) external view returns (uint256);

    // =============================================================
    //                          CONSTANTS
    // =============================================================

    /// @notice Safe House area ID (always 0)
    function SAFE_HOUSE_AREA() external view returns (uint8);

    /// @notice Jail area ID (always 255)
    function JAIL_AREA() external view returns (uint8);

    /// @notice Black Market area ID (always 254)
    function BLACK_MARKET_AREA() external view returns (uint8);
}
