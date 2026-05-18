// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DealersPaymentHandler
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Handles all monetary transactions and fee splitting for the game ecosystem
 * @author Berny0x
 */
contract DealersPaymentHandler is ReentrancyGuard, Ownable {

    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant MIN_AMOUNT = 0.0001 ether;
    uint256 public constant MAX_FEE_PERCENT = 10000;

    // =============================================================
    //                            STORAGE
    // =============================================================

    // Fee split (basis points, e.g. 8000 = 80% to bank, 20% to dev)
    uint256 public bankFeePercent = 8000;

    // Authorized game contracts
    mapping(address => bool) public authorizedContracts;

    // Fee destinations
    address public devWallet;
    address public bankVault;

    // Financial tracking
    uint256 public totalProcessed;
    uint256 public totalDevFees;
    uint256 public totalBankFees;
    uint256 public totalDirectDeposits;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event FeeProcessed(address indexed player, uint256 amount, uint256 devFee, uint256 bankFee);
    event DevFeesWithdrawn(address indexed devWallet, uint256 amount);
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event DevWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event BankVaultUpdated(address indexed oldVault, address indexed newVault);
    event EmergencyWithdrawal(address indexed to, uint256 amount);
    event DirectDeposit(address indexed sender, uint256 amount);
    event FeeSplitUpdated(uint256 oldBankPercent, uint256 newBankPercent);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotAuthorized();
    error InvalidAddress();
    error InvalidAmount();
    error AmountTooSmall();
    error TransferFailed();
    error InsufficientBalance();
    error NoFeesToWithdraw();
    error InvalidFeePercent();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor(address _devWallet, address _bankVault) {
        _initializeOwner(msg.sender);

        if (_devWallet == address(0) || _bankVault == address(0)) {
            revert InvalidAddress();
        }

        devWallet = _devWallet;
        bankVault = _bankVault;
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender]) revert NotAuthorized();
        _;
    }

    // =============================================================
    //                    ABSTRACT CHAIN COMPATIBLE TRANSFERS
    // =============================================================

    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // =============================================================
    //                        CORE PAYMENT FUNCTIONS
    // =============================================================

    function _processFee(address player, uint256 amount) private {
        uint256 bankFee = (amount * bankFeePercent) / 10000;
        uint256 devFee = amount - bankFee;

        totalProcessed += amount;
        totalDevFees += devFee;
        totalBankFees += bankFee;

        if (bankFee > 0) {
            _safeTransferETH(bankVault, bankFee);
        }

        emit FeeProcessed(player, amount, devFee, bankFee);
    }

    /**
     * @notice Process area movement fee
     * @param player The player address (for event tracking)
     * @param amount Fee amount
     */
    function processMovementFee(address player, uint256 amount) external payable onlyAuthorized nonReentrant {
        if (msg.value != amount || amount == 0) revert InvalidAmount();
        if (amount < MIN_AMOUNT) revert AmountTooSmall();
        _processFee(player, amount);
    }

    /**
     * @notice Process marketplace/boost fee
     * @param player The player address (for event tracking)
     * @param amount Fee amount
     */
    function processMarketplaceFee(address player, uint256 amount) external payable onlyAuthorized nonReentrant {
        if (msg.value != amount || amount == 0) revert InvalidAmount();
        if (amount < MIN_AMOUNT) revert AmountTooSmall();
        _processFee(player, amount);
    }

    // =============================================================
    //                        WITHDRAWAL FUNCTIONS
    // =============================================================

    function withdrawDevFees() external nonReentrant {
        if (msg.sender != devWallet && msg.sender != owner()) revert NotAuthorized();

        uint256 amount = address(this).balance;
        if (amount == 0) revert NoFeesToWithdraw();

        _safeTransferETH(devWallet, amount);

        emit DevFeesWithdrawn(devWallet, amount);
    }

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientBalance();

        _safeTransferETH(to, amount);

        emit EmergencyWithdrawal(to, amount);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    function getBankBalance() external view returns (uint256) {
        return bankVault.balance;
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getFinancialStats() external view returns (
        uint256 processed,
        uint256 devFees,
        uint256 bankFees,
        uint256 contractBalance,
        uint256 bankBalance
    ) {
        processed = totalProcessed;
        devFees = totalDevFees;
        bankFees = totalBankFees;
        contractBalance = address(this).balance;
        bankBalance = bankVault.balance;
    }

    function calculateFees(uint256 amount) external view returns (
        uint256 bankFee,
        uint256 devFee
    ) {
        bankFee = (amount * bankFeePercent) / 10000;
        devFee = amount - bankFee;
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    function authorizeContract(address contractAddress, bool authorized) external onlyOwner {
        if (contractAddress == address(0)) revert InvalidAddress();
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorized(contractAddress, authorized);
    }

    function setDevWallet(address _devWallet) external onlyOwner {
        if (_devWallet == address(0)) revert InvalidAddress();
        address oldWallet = devWallet;
        devWallet = _devWallet;
        emit DevWalletUpdated(oldWallet, _devWallet);
    }

    function setBankVault(address _bankVault) external onlyOwner {
        if (_bankVault == address(0)) revert InvalidAddress();
        address oldVault = bankVault;
        bankVault = _bankVault;
        emit BankVaultUpdated(oldVault, _bankVault);
    }

    function setFeeSplit(uint256 _bankFeePercent) external onlyOwner {
        if (_bankFeePercent < 2500 || _bankFeePercent > MAX_FEE_PERCENT) revert InvalidFeePercent();
        uint256 oldPercent = bankFeePercent;
        bankFeePercent = _bankFeePercent;
        emit FeeSplitUpdated(oldPercent, _bankFeePercent);
    }

    // =============================================================
    //                        FALLBACK FUNCTIONS
    // =============================================================

    receive() external payable {
        totalDirectDeposits += msg.value;
        emit DirectDeposit(msg.sender, msg.value);
    }

    fallback() external payable {
        totalDirectDeposits += msg.value;
        emit DirectDeposit(msg.sender, msg.value);
    }
}
