// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDrugRegistry - Interface for Drug Registry
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Interface for global drug definitions, supply tracking, and base values
 * @author HeadmasterBerny
 */
interface IDrugRegistry {
    // =============================================================
    //                           ENUMS
    // =============================================================

    enum DrugRarity { COMMON, UNCOMMON, RARE, LEGENDARY }

    // =============================================================
    //                           STRUCTS
    // =============================================================

    /**
     * @dev Drug information structure
     */
    struct DrugInfo {
        string name;
        DrugRarity rarity;
        uint256 baseCashValue;
        uint256 totalSupply;
        bool isActive;
    }

    // =============================================================
    //                           EVENTS
    // =============================================================

    event DrugCreated(uint256 indexed drugId, string name, DrugRarity rarity, uint256 baseCashValue);
    event DrugUpdated(uint256 indexed drugId, uint256 newBaseCashValue, bool isActive);
    event SupplyIncremented(uint256 indexed drugId, uint256 amount, uint256 newSupply);
    event SupplyDecremented(uint256 indexed drugId, uint256 amount, uint256 newSupply);

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /// @notice Get detailed information about a drug
    function getDrugInfo(uint256 drugId) external view returns (DrugInfo memory);

    /// @notice Get the base cash value for a drug
    function getDrugBaseCashValue(uint256 drugId) external view returns (uint256);

    /// @notice Get the current supply of a drug
    function getDrugSupply(uint256 drugId) external view returns (uint256);

    /// @notice Get the rarity of a drug
    function getDrugRarity(uint256 drugId) external view returns (DrugRarity);

    /// @notice Check if a drug is active
    function isDrugActive(uint256 drugId) external view returns (bool);

    /// @notice Get total number of drugs registered
    function getTotalDrugs() external view returns (uint256);

    /// @notice Get all drug IDs
    function getAllDrugIds() external view returns (uint256[] memory);

    /// @notice Get drugs by rarity
    function getDrugsByRarity(DrugRarity rarity) external view returns (uint256[] memory);

    /// @notice Check if a drug ID is valid
    function isValidDrug(uint256 drugId) external view returns (bool);

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /// @notice Increment drug supply (called when drugs are minted/awarded)
    function incrementSupply(uint256 drugId, uint256 amount) external;

    /// @notice Decrement drug supply (called when drugs are burned/consumed)
    function decrementSupply(uint256 drugId, uint256 amount) external;

}
