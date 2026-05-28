// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IDrugRegistry} from "./IDrugRegistry.sol";

/**
 * @title DealersDrugRegistry - Global Drug Registry
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Manages all drug definitions and base values
 * @author Berny0x
 */
contract DealersDrugRegistry is Ownable, IDrugRegistry {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    /// @notice Maximum length for drug names
    uint256 public constant MAX_DRUG_NAME_LENGTH = 32;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Drug ID => Drug Info
    mapping(uint256 => DrugInfo) private _drugs;

    /// @notice Total number of drugs registered
    uint256 private _totalDrugs;

    /// @notice Array of all drug IDs for iteration
    uint256[] private _drugIds;

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidDrugId();
    error DrugNotActive();
    error InvalidBaseCashValue();
    error DrugNameTooLong();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor() {
        _initializeOwner(msg.sender);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier validDrug(uint256 drugId) {
        if (drugId == 0 || drugId > _totalDrugs) revert InvalidDrugId();
        if (!_drugs[drugId].isActive) revert DrugNotActive();
        _;
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /// @inheritdoc IDrugRegistry
    function getDrugInfo(uint256 drugId) external view validDrug(drugId) returns (DrugInfo memory) {
        return _drugs[drugId];
    }

    /// @inheritdoc IDrugRegistry
    function getDrugBaseCashValue(uint256 drugId) external view validDrug(drugId) returns (uint256) {
        return _drugs[drugId].baseCashValue;
    }

    /// @inheritdoc IDrugRegistry
    function getDrugRarity(uint256 drugId) external view validDrug(drugId) returns (DrugRarity) {
        return _drugs[drugId].rarity;
    }

    /// @inheritdoc IDrugRegistry
    function isDrugActive(uint256 drugId) external view returns (bool) {
        if (drugId == 0 || drugId > _totalDrugs) return false;
        return _drugs[drugId].isActive;
    }

    /// @inheritdoc IDrugRegistry
    function getTotalDrugs() external view returns (uint256) {
        return _totalDrugs;
    }

    /// @inheritdoc IDrugRegistry
    function getAllDrugIds() external view returns (uint256[] memory) {
        return _drugIds;
    }

    /// @inheritdoc IDrugRegistry
    function getDrugsByRarity(DrugRarity rarity) external view returns (uint256[] memory) {
        // First pass: count matching drugs
        uint256 count = 0;
        for (uint256 i = 0; i < _drugIds.length;) {
            if (_drugs[_drugIds[i]].rarity == rarity && _drugs[_drugIds[i]].isActive) {
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Second pass: populate array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _drugIds.length;) {
            if (_drugs[_drugIds[i]].rarity == rarity && _drugs[_drugIds[i]].isActive) {
                result[index] = _drugIds[i];
                unchecked {
                    ++index;
                }
            }
            unchecked {
                ++i;
            }
        }

        return result;
    }

    /// @inheritdoc IDrugRegistry
    function isValidDrug(uint256 drugId) external view returns (bool) {
        if (drugId == 0 || drugId > _totalDrugs) return false;
        return _drugs[drugId].isActive;
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Create a new drug type
     * @dev Only callable by owner
     * @param name Drug display name (max 32 chars)
     * @param rarity Drug rarity tier
     * @param baseCashValue Base $CASH value for trading
     * @return drugId The ID of the newly created drug
     */
    function createDrug(string calldata name, DrugRarity rarity, uint256 baseCashValue)
        external
        onlyOwner
        returns (uint256 drugId)
    {
        _createDrug(name, rarity, baseCashValue);
        return _totalDrugs;
    }

    /**
     * @notice Update a drug's base cash value
     * @dev Only callable by owner
     * @param drugId The drug ID to update
     * @param newBaseCashValue The new base cash value
     */
    function updateDrugBaseCashValue(uint256 drugId, uint256 newBaseCashValue) external onlyOwner validDrug(drugId) {
        if (newBaseCashValue == 0) revert InvalidBaseCashValue();
        _drugs[drugId].baseCashValue = newBaseCashValue;
        emit DrugUpdated(drugId, newBaseCashValue, _drugs[drugId].isActive);
    }

    /**
     * @notice Activate or deactivate a drug
     * @dev Only callable by owner
     * @param drugId The drug ID to update
     * @param active Whether the drug should be active
     */
    function setDrugActive(uint256 drugId, bool active) external onlyOwner {
        if (drugId == 0 || drugId > _totalDrugs) revert InvalidDrugId();
        _drugs[drugId].isActive = active;
        emit DrugUpdated(drugId, _drugs[drugId].baseCashValue, active);
    }

    // =============================================================
    //                    INTERNAL HELPER FUNCTIONS
    // =============================================================

    /**
     * @dev Internal function to create a drug
     * @param name Drug display name
     * @param rarity Drug rarity tier
     * @param baseCashValue Base $CASH value for trading
     */
    function _createDrug(string memory name, DrugRarity rarity, uint256 baseCashValue) private {
        if (bytes(name).length > MAX_DRUG_NAME_LENGTH) revert DrugNameTooLong();
        if (baseCashValue == 0) revert InvalidBaseCashValue();

        ++_totalDrugs;

        uint256 drugId = _totalDrugs;

        _drugs[drugId] = DrugInfo({
            name: name,
            rarity: rarity,
            baseCashValue: baseCashValue,
            isActive: true
        });

        _drugIds.push(drugId);

        emit DrugCreated(drugId, name, rarity, baseCashValue);
    }
}
