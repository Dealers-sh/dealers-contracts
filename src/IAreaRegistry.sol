// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAreaRegistry - Interface for Area Registry
 * @dev Manages area definitions, drug availability per area, and pricing
 * @author Dealers.Exe Team
 */
interface IAreaRegistry {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    /**
     * @dev Area-specific drug pricing configuration
     * @param drugId Reference to global drug ID
     * @param buyPrice $CASH cost to buy in this area
     * @param sellPrice $CASH received when selling in this area
     * @param isAvailable Whether this drug is available in this area
     */
    struct AreaDrugConfig {
        uint256 drugId;
        uint256 buyPrice;
        uint256 sellPrice;
        bool isAvailable;
    }

    /**
     * @dev Area configuration structure
     * @param name Display name of the area
     * @param movementFee Cost in wei to move to this area (also bail for Jail)
     * @param minReputation Minimum total reputation required to enter
     * @param isActive Whether the area is accessible to players
     * @param isSafeHouse Whether this is a safe house (cannot farm, one-way exit)
     * @param isJail Whether this is jail (random event destination, pay bail to exit)
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
    //                      CONSTANTS
    // =============================================================

    /// @notice Safe House area ID (always 0)
    function SAFE_HOUSE_AREA() external view returns (uint8);

    /// @notice Jail area ID (always 255)
    function JAIL_AREA() external view returns (uint8);
}
