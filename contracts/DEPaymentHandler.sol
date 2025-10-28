// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DEPaymentHandler - ETH Management and Fee Distribution
 * @dev Handles all monetary transactions and fee splitting for the game ecosystem
 * Abstract Chain Compatible - Uses .call() instead of .transfer()
 */

contract DEPaymentHandler is ReentrancyGuard, Ownable {

    // =============================================================
    //                            CONSTANTS
    // =============================================================
    
    // Game outcomes
    uint8 public constant WIN = 0;
    uint8 public constant TIE = 1;
    uint8 public constant LOSS = 2;
    
    // Fee structure (basis points - 10000 = 100%)
    uint256 public constant GAME_FEE_PERCENT = 1000;    // 10% total fee
    uint256 public constant DEV_FEE_PERCENT = 500;      // 5% to dev wallet
    uint256 public constant BANK_FEE_PERCENT = 500;     // 5% to bank vault

    // =============================================================
    //                            STORAGE
    // =============================================================
    
    // Authorized game contracts
    mapping(address => bool) public authorizedContracts;
    
    // Fee destinations
    address public devWallet;
    address public bankVault;
    
    // Financial tracking
    uint256 public totalProcessed;       // Total ETH processed
    uint256 public totalDevFees;        // Total fees to dev wallet
    uint256 public totalBankFees;       // Total fees to bank vault
    uint256 public totalPayouts;        // Total payouts to players
    
    // Pending withdrawals for dev wallet
    uint256 public pendingDevWithdrawal;

    // =============================================================
    //                            EVENTS
    // =============================================================
    
    event StakedBetProcessed(address indexed player, uint256 amount, uint256 devFee, uint256 bankFee);
    event GamePayoutProcessed(address indexed player, uint8 outcome, uint256 stakeAmount, uint256 payout);
    event MovementFeeProcessed(address indexed player, uint256 fee, uint256 devFee, uint256 bankFee);
    event MarketplaceFeeProcessed(address indexed player, uint256 fee, uint256 devFee, uint256 bankFee);
    event DevFeesWithdrawn(address indexed devWallet, uint256 amount);
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event DevWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event BankVaultUpdated(address indexed oldVault, address indexed newVault);
    event EmergencyWithdrawal(address indexed to, uint256 amount);

    // =============================================================
    //                            ERRORS
    // =============================================================
    
    error NotAuthorized();
    error InvalidAddress();
    error InvalidAmount();
    error TransferFailed();
    error InsufficientBalance();
    error NoFeesToWithdraw();

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
    
    /**
     * @notice Safe ETH transfer using .call() for Abstract Chain compatibility
     * @dev All accounts on Abstract are smart contracts, so .transfer() fails due to 2300 gas limit
     */
    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();
        
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // =============================================================
    //                        CORE PAYMENT FUNCTIONS
    // =============================================================
    
    /**
     * @notice Process staked bet payment and split fees
     * @param amount Bet amount in wei
     */
    function processStakedBet(uint256 amount) external payable onlyAuthorized nonReentrant {
        if (msg.value != amount || amount == 0) revert InvalidAmount();
        
        // Calculate fees
        uint256 devFee = (amount * DEV_FEE_PERCENT) / 10000;
        uint256 bankFee = (amount * BANK_FEE_PERCENT) / 10000;
        
        // Update tracking
        totalProcessed += amount;
        totalDevFees += devFee;
        totalBankFees += bankFee;
        pendingDevWithdrawal += devFee;
        
        // Send bank fee immediately to vault using Abstract-compatible transfer
        if (bankFee > 0) {
            _safeTransferETH(bankVault, bankFee);
        }
        
        emit StakedBetProcessed(tx.origin, amount, devFee, bankFee);
    }
    
    /**
     * @notice Process game payout based on outcome
     * @param player Player address to receive payout
     * @param outcome Game outcome (0=WIN, 1=TIE, 2=LOSS)
     * @param stakeAmount Original stake amount
     */
    function processGamePayout(
        address player, 
        uint8 outcome, 
        uint256 stakeAmount
    ) external onlyAuthorized nonReentrant {
        if (player == address(0)) revert InvalidAddress();
        if (stakeAmount == 0) revert InvalidAmount();
        
        uint256 payout = 0;
        
        if (outcome == WIN) {
            // WIN: 2x stake minus total fee (already deducted in processStakedBet)
            uint256 totalFee = (stakeAmount * GAME_FEE_PERCENT) / 10000;
            payout = (stakeAmount * 2) - totalFee;
        } else if (outcome == TIE) {
            // TIE: Return stake minus total fee
            uint256 totalFee = (stakeAmount * GAME_FEE_PERCENT) / 10000;
            payout = stakeAmount - totalFee;
        }
        // LOSS: No payout (house keeps the stake)
        
        if (payout > 0) {
            if (address(this).balance < payout) revert InsufficientBalance();
            
            totalPayouts += payout;
            _safeTransferETH(player, payout);
        }
        
        emit GamePayoutProcessed(player, outcome, stakeAmount, payout);
    }
    
    /**
     * @notice Process area movement fee
     * @param amount Movement fee amount
     */
    function processMovementFee(uint256 amount) external payable onlyAuthorized nonReentrant {
        if (msg.value != amount || amount == 0) revert InvalidAmount();
        
        // Split movement fee same as game fees
        uint256 devFee = (amount * DEV_FEE_PERCENT) / 10000;
        uint256 bankFee = (amount * BANK_FEE_PERCENT) / 10000;
        
        // Update tracking
        totalProcessed += amount;
        totalDevFees += devFee;
        totalBankFees += bankFee;
        pendingDevWithdrawal += devFee;
        
        // Send bank fee to vault
        if (bankFee > 0) {
            _safeTransferETH(bankVault, bankFee);
        }
        
        emit MovementFeeProcessed(tx.origin, amount, devFee, bankFee);
    }
    
    /**
     * @notice Process marketplace transaction fee
     * @param amount Marketplace fee amount (10% of sale price)
     */
    function processMarketplaceFee(uint256 amount) external payable onlyAuthorized nonReentrant {
        if (msg.value != amount || amount == 0) revert InvalidAmount();
        
        // Split marketplace fee same as game fees
        uint256 devFee = (amount * DEV_FEE_PERCENT) / 10000;
        uint256 bankFee = (amount * BANK_FEE_PERCENT) / 10000;
        
        // Update tracking
        totalProcessed += amount;
        totalDevFees += devFee;
        totalBankFees += bankFee;
        pendingDevWithdrawal += devFee;
        
        // Send bank fee to vault
        if (bankFee > 0) {
            _safeTransferETH(bankVault, bankFee);
        }
        
        emit MarketplaceFeeProcessed(tx.origin, amount, devFee, bankFee);
    }

    // =============================================================
    //                        WITHDRAWAL FUNCTIONS
    // =============================================================
    
    /**
     * @notice Withdraw accumulated dev fees
     */
    function withdrawDevFees() external nonReentrant {
        if (msg.sender != devWallet && msg.sender != owner()) revert NotAuthorized();
        if (pendingDevWithdrawal == 0) revert NoFeesToWithdraw();
        
        uint256 amount = pendingDevWithdrawal;
        pendingDevWithdrawal = 0;
        
        _safeTransferETH(devWallet, amount);
        
        emit DevFeesWithdrawn(devWallet, amount);
    }
    
    /**
     * @notice Emergency withdrawal (owner only)
     * @param to Address to send funds to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientBalance();
        
        _safeTransferETH(to, amount);
        
        emit EmergencyWithdrawal(to, amount);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================
    
    /**
     * @notice Get current bank vault balance
     */
    function getBankBalance() external view returns (uint256) {
        return bankVault.balance;
    }
    
    /**
     * @notice Get contract ETH balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @notice Get pending dev fees
     */
    function getPendingDevFees() external view returns (uint256) {
        return pendingDevWithdrawal;
    }
    
    /**
     * @notice Get comprehensive financial stats
     */
    function getFinancialStats() external view returns (
        uint256 processed,
        uint256 devFees,
        uint256 bankFees,
        uint256 payouts,
        uint256 pendingDev,
        uint256 contractBalance,
        uint256 bankBalance
    ) {
        processed = totalProcessed;
        devFees = totalDevFees;
        bankFees = totalBankFees;
        payouts = totalPayouts;
        pendingDev = pendingDevWithdrawal;
        contractBalance = address(this).balance;
        bankBalance = bankVault.balance;
    }
    
    /**
     * @notice Calculate fees for a given amount
     */
    function calculateFees(uint256 amount) external pure returns (
        uint256 devFee,
        uint256 bankFee,
        uint256 totalFee,
        uint256 netAmount
    ) {
        devFee = (amount * DEV_FEE_PERCENT) / 10000;
        bankFee = (amount * BANK_FEE_PERCENT) / 10000;
        totalFee = devFee + bankFee;
        netAmount = amount - totalFee;
    }
    
    /**
     * @notice Calculate payout for a stake and outcome
     */
    function calculatePayout(uint256 stakeAmount, uint8 outcome) external pure returns (uint256 payout) {
        if (outcome == WIN) {
            uint256 totalFee = (stakeAmount * GAME_FEE_PERCENT) / 10000;
            payout = (stakeAmount * 2) - totalFee;
        } else if (outcome == TIE) {
            uint256 totalFee = (stakeAmount * GAME_FEE_PERCENT) / 10000;
            payout = stakeAmount - totalFee;
        } else {
            payout = 0; // LOSS
        }
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================
    
    /**
     * @notice Authorize/deauthorize contracts to process payments
     */
    function authorizeContract(address contractAddress, bool authorized) external onlyOwner {
        if (contractAddress == address(0)) revert InvalidAddress();
        
        authorizedContracts[contractAddress] = authorized;
        
        emit ContractAuthorized(contractAddress, authorized);
    }
    
    /**
     * @notice Update dev wallet address
     */
    function setDevWallet(address _devWallet) external onlyOwner {
        if (_devWallet == address(0)) revert InvalidAddress();
        
        address oldWallet = devWallet;
        devWallet = _devWallet;
        
        emit DevWalletUpdated(oldWallet, _devWallet);
    }
    
    /**
     * @notice Update bank vault address
     */
    function setBankVault(address _bankVault) external onlyOwner {
        if (_bankVault == address(0)) revert InvalidAddress();
        
        address oldVault = bankVault;
        bankVault = _bankVault;
        
        emit BankVaultUpdated(oldVault, _bankVault);
    }
    
    // =============================================================
    //                        FALLBACK FUNCTIONS
    // =============================================================
    
    /**
     * @notice Accept ETH deposits
     */
    receive() external payable {
        // Allow contract to receive ETH
        totalProcessed += msg.value;
    }
    
    /**
     * @notice Fallback function
     */
    fallback() external payable {
        // Allow contract to receive ETH via fallback
        totalProcessed += msg.value;
    }
}