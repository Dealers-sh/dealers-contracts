// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IDrugRegistry.sol";

/**
 * @title DealersExeDrugRegistry - Global Drug Registry
 * @dev Manages all drug definitions, supply tracking, and base values
 *      Designed to support 15+ drug types with different rarities
 * @author Dealers.Exe Team
 */
contract DealersExeDrugRegistry is Ownable, IDrugRegistry {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    /// @notice Supply caps per rarity tier
    uint256 public constant COMMON_SUPPLY_CAP = 10_000_000;
    uint256 public constant UNCOMMON_SUPPLY_CAP = 1_000_000;
    uint256 public constant RARE_SUPPLY_CAP = 100_000;
    uint256 public constant LEGENDARY_SUPPLY_CAP = 10_000;

    /// @notice Initial drug IDs (for backward compatibility)
    uint256 public constant DRUG_WEED = 1;
    uint256 public constant DRUG_XTC = 2;
    uint256 public constant DRUG_COCAINE = 3;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Drug ID => Drug Info
    mapping(uint256 => DrugInfo) private _drugs;

    /// @notice Total number of drugs registered
    uint256 private _totalDrugs;

    /// @notice Array of all drug IDs for iteration
    uint256[] private _drugIds;

    /// @notice Authorized contracts that can modify supply
    mapping(address => bool) public authorizedContracts;

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotAuthorized();
    error InvalidDrugId();
    error DrugNotActive();
    error DrugAlreadyExists();
    error SupplyCapExceeded();
    error InsufficientSupply();
    error InvalidBaseCashValue();
    error DrugNameTooLong();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the Drug Registry with default drugs
     * @dev Creates Weed, XTC, and Cocaine as the initial 3 drugs
     */
    constructor() {
        _initializeOwner(msg.sender);
        _createInitialDrugs();
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }

    modifier validDrug(uint256 drugId) {
        if (drugId == 0 || drugId > _totalDrugs) revert InvalidDrugId();
        if (!_drugs[drugId].isActive) revert DrugNotActive();
        _;
    }

    // =============================================================
    //                        INITIALIZATION
    // =============================================================

    /**
     * @notice Create the initial 3 drugs
     * @dev Called during construction
     */
    function _createInitialDrugs() private {
        // Drug 1: Weed - Common, baseCashValue: 1
        _createDrug("Weed", DrugRarity.COMMON, 1);

        // Drug 2: XTC - Uncommon, baseCashValue: 10
        _createDrug("XTC", DrugRarity.UNCOMMON, 10);

        // Drug 3: Cocaine - Rare, baseCashValue: 100
        _createDrug("Cocaine", DrugRarity.RARE, 100);
    }

    /**
     * @notice Internal function to create a drug
     * @param name Drug display name
     * @param rarity Drug rarity tier
     * @param baseCashValue Base $CASH value for trading
     */
    function _createDrug(
        string memory name,
        DrugRarity rarity,
        uint256 baseCashValue
    ) private {
        if (bytes(name).length > 32) revert DrugNameTooLong();
        if (baseCashValue == 0) revert InvalidBaseCashValue();

        uint256 supplyCap = _getSupplyCapForRarity(rarity);

        unchecked {
            ++_totalDrugs;
        }

        uint256 drugId = _totalDrugs;

        _drugs[drugId] = DrugInfo({
            name: name,
            rarity: rarity,
            baseCashValue: baseCashValue,
            totalSupply: 0,
            supplyCap: supplyCap,
            isActive: true
        });

        _drugIds.push(drugId);

        emit DrugCreated(drugId, name, rarity, baseCashValue);
    }

    /**
     * @notice Get supply cap based on rarity
     * @param rarity The drug rarity
     * @return The supply cap for that rarity
     */
    function _getSupplyCapForRarity(DrugRarity rarity) private pure returns (uint256) {
        if (rarity == DrugRarity.COMMON) return COMMON_SUPPLY_CAP;
        if (rarity == DrugRarity.UNCOMMON) return UNCOMMON_SUPPLY_CAP;
        if (rarity == DrugRarity.RARE) return RARE_SUPPLY_CAP;
        return LEGENDARY_SUPPLY_CAP;
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
    function getDrugSupply(uint256 drugId) external view validDrug(drugId) returns (uint256) {
        return _drugs[drugId].totalSupply;
    }

    /// @inheritdoc IDrugRegistry
    function getDrugSupplyCap(uint256 drugId) external view validDrug(drugId) returns (uint256) {
        return _drugs[drugId].supplyCap;
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
        for (uint256 i = 0; i < _drugIds.length; ) {
            if (_drugs[_drugIds[i]].rarity == rarity && _drugs[_drugIds[i]].isActive) {
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        // Second pass: populate array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _drugIds.length; ) {
            if (_drugs[_drugIds[i]].rarity == rarity && _drugs[_drugIds[i]].isActive) {
                result[index] = _drugIds[i];
                unchecked { ++index; }
            }
            unchecked { ++i; }
        }

        return result;
    }

    /// @inheritdoc IDrugRegistry
    function isValidDrug(uint256 drugId) external view returns (bool) {
        if (drugId == 0 || drugId > _totalDrugs) return false;
        return _drugs[drugId].isActive;
    }

    // =============================================================
    //                    SUPPLY MANAGEMENT
    // =============================================================

    /// @inheritdoc IDrugRegistry
    function incrementSupply(uint256 drugId, uint256 amount) external onlyAuthorized validDrug(drugId) {
        DrugInfo storage drug = _drugs[drugId];

        uint256 newSupply = drug.totalSupply + amount;
        if (newSupply > drug.supplyCap) revert SupplyCapExceeded();

        drug.totalSupply = newSupply;

        emit SupplyIncremented(drugId, amount, newSupply);
    }

    /// @inheritdoc IDrugRegistry
    function decrementSupply(uint256 drugId, uint256 amount) external onlyAuthorized validDrug(drugId) {
        DrugInfo storage drug = _drugs[drugId];

        if (amount > drug.totalSupply) revert InsufficientSupply();

        unchecked {
            drug.totalSupply -= amount;
        }

        emit SupplyDecremented(drugId, amount, drug.totalSupply);
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
    function createDrug(
        string calldata name,
        DrugRarity rarity,
        uint256 baseCashValue
    ) external onlyOwner returns (uint256 drugId) {
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

    /**
     * @notice Update supply cap for a drug (emergency use)
     * @dev Only callable by owner
     * @param drugId The drug ID to update
     * @param newCap The new supply cap
     */
    function updateSupplyCap(uint256 drugId, uint256 newCap) external onlyOwner {
        if (drugId == 0 || drugId > _totalDrugs) revert InvalidDrugId();
        _drugs[drugId].supplyCap = newCap;
    }

    /**
     * @notice Authorize a contract to modify supply
     * @dev Only callable by owner
     * @param contractAddress The contract to authorize
     * @param authorized Whether to grant or revoke authorization
     */
    function authorizeContract(address contractAddress, bool authorized) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
    }

    /**
     * @notice Check if a contract is authorized
     * @param contractAddress The contract to check
     * @return Whether the contract is authorized
     */
    function isAuthorized(address contractAddress) external view returns (bool) {
        return authorizedContracts[contractAddress] || contractAddress == owner();
    }
}
