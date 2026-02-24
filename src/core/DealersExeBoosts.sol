// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IDealersExeCore.sol";
import "../utils/IERC721Minimal.sol";
import "../utils/IDEPaymentHandler.sol";

/**
 * @title DealersExeBoosts - Boost Purchase Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Allows players to purchase temporary boosts for their dealers
 *      Boosts provide drug/rep multipliers, extra attempts, and special abilities
 * @author Dealers.Exe Team
 */
contract DealersExeBoosts is ReentrancyGuard, Ownable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    // Time durations
    uint64 public constant DURATION_24_HOURS = 24 hours;
    uint64 public constant DURATION_3_DAYS = 3 days;
    uint64 public constant DURATION_7_DAYS = 7 days;
    uint64 public constant DURATION_30_DAYS = 30 days;

    // Maximum number of tiers allowed
    uint256 public constant MAX_TIERS = 10;

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /**
     * @dev Boost tier configuration
     * @param price Price in wei to purchase
     * @param duration Duration in seconds
     * @param drugMultiplier Drug reward multiplier (100 = 1x, 200 = 2x)
     * @param repMultiplier Rep reward multiplier (100 = 1x, 150 = 1.5x, 200 = 2x)
     * @param extraAttempts Added to BASE_MAX_ATTEMPTS (5)
     * @param freeAreaMovement Whether to skip movement fees
     * @param doubleHeistEntries Whether to get 2x heist entries
     * @param cashMultiplier Cash reward multiplier (100 = 1x, 150 = 1.5x, 200 = 2x)
     * @param isActive Whether this tier is available for purchase
     */
    struct BoostTier {
        uint256 price;
        uint64 duration;
        uint8 drugMultiplier;
        uint8 repMultiplier;
        uint8 extraAttempts;
        bool freeAreaMovement;
        bool doubleHeistEntries;
        uint8 cashMultiplier;
        bool isActive;
    }

    // =============================================================
    //                            STORAGE
    // =============================================================

    // Contract references
    IDealersExeCore public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    IDEPaymentHandler public paymentHandler;

    // Boost tier configuration
    mapping(uint256 => BoostTier) public boostTiers;
    uint256 public totalTiers;

    // Pause state
    bool public paused;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event BoostPurchased(
        uint256 indexed dealerId,
        uint256 indexed tierId,
        address indexed buyer,
        uint64 expiresAt
    );

    event BoostTierUpdated(
        uint256 indexed tierId,
        uint256 price,
        uint64 duration,
        bool isActive
    );

    event BoostTierActiveStatusChanged(uint256 indexed tierId, bool isActive);

    event BoostTierPriceUpdated(uint256 indexed tierId, uint256 oldPrice, uint256 newPrice);

    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event PaymentHandlerUpdated(address indexed oldHandler, address indexed newHandler);
    event Paused(address account);
    event Unpaused(address account);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error ContractPaused();
    error InvalidTier();
    error TierNotActive();
    error InsufficientPayment();
    error NotDealerOwner();
    error DealerNotInitialized();
    error InvalidAddress();
    error TransferFailed();
    error EmptyBatch();
    error BoostAlreadyActive();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the Boosts contract with default tiers
     * @param _dealersExeCore Address of the core dealers contract
     * @param _dealersExeNFT Address of the NFT contract
     * @param _paymentHandler Address of the payment handler
     */
    constructor(
        address _dealersExeCore,
        address _dealersExeNFT,
        address _paymentHandler
    ) {
        if (_dealersExeCore == address(0)) revert InvalidAddress();
        if (_dealersExeNFT == address(0)) revert InvalidAddress();
        if (_paymentHandler == address(0)) revert InvalidAddress();

        _initializeOwner(msg.sender);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        paymentHandler = IDEPaymentHandler(_paymentHandler);

        // Initialize default boost tiers
        _initializeDefaultTiers();
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(dealersExeCore) == address(0) ||
            address(dealersExeNFT) == address(0) ||
            address(paymentHandler) == address(0)
        ) {
            revert ContractNotSet();
        }
        _;
    }

    modifier validTier(uint256 tierId) {
        if (tierId == 0 || tierId > totalTiers) revert InvalidTier();
        if (boostTiers[tierId].price == 0) revert InvalidTier();
        _;
    }

    modifier tierActive(uint256 tierId) {
        if (!boostTiers[tierId].isActive) revert TierNotActive();
        _;
    }

    modifier dealerExists(uint256 dealerId) {
        (, , , , , bool isInitialized) = dealersExeCore.getDealerData(dealerId);
        if (!isInitialized) revert DealerNotInitialized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // =============================================================
    //                        INITIALIZATION
    // =============================================================

    /**
     * @notice Initialize the three default boost tiers
     * @dev Called during construction
     */
    function _initializeDefaultTiers() private {
        // Tier 1: Grinder - 0.0025 ETH, 3 days
        boostTiers[1] = BoostTier({
            price: 0.0025 ether,
            duration: DURATION_3_DAYS,
            drugMultiplier: 125,     // 1.25x drugs
            repMultiplier: 125,      // 1.25x rep
            extraAttempts: 3,        // 5 base + 3 = 8 max
            freeAreaMovement: false,
            doubleHeistEntries: false,
            cashMultiplier: 125,     // 1.25x cash
            isActive: true
        });

        // Tier 2: Hustler - 0.005 ETH, 7 days
        boostTiers[2] = BoostTier({
            price: 0.005 ether,
            duration: DURATION_7_DAYS,
            drugMultiplier: 150,     // 1.5x drugs
            repMultiplier: 150,      // 1.5x rep
            extraAttempts: 5,        // 5 base + 5 = 10 max
            freeAreaMovement: false,
            doubleHeistEntries: false,
            cashMultiplier: 150,     // 1.5x cash
            isActive: true
        });

        // Tier 3: Kingpin - 0.01 ETH, 30 days
        boostTiers[3] = BoostTier({
            price: 0.01 ether,
            duration: DURATION_30_DAYS,
            drugMultiplier: 175,     // 1.75x drugs
            repMultiplier: 200,      // 2x rep
            extraAttempts: 10,       // 5 base + 10 = 15 max
            freeAreaMovement: true,  // Free area movement
            doubleHeistEntries: true, // 2x heist entries
            cashMultiplier: 175,     // 1.75x cash
            isActive: true
        });

        totalTiers = 3;
    }

    // =============================================================
    //                    ABSTRACT CHAIN COMPATIBLE TRANSFERS
    // =============================================================

    /**
     * @notice Safely transfers ETH to a recipient address
     * @dev Uses low-level call to handle transfer failures gracefully
     * @param to The address to send ETH to
     * @param amount The amount of ETH to send in wei
     */
    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // =============================================================
    //                        PURCHASE FUNCTIONS
    // =============================================================

    /**
     * @notice Purchase a boost for a single dealer
     * @param dealerId The ID of the dealer NFT to apply boost to
     * @param tierId The tier of boost to purchase (1, 2, or 3)
     */
    function purchaseBoost(uint256 dealerId, uint256 tierId)
        external
        payable
        nonReentrant
        whenNotPaused
        contractsSet
        validTier(tierId)
        tierActive(tierId)
        dealerExists(dealerId)
    {
        bool isAdmin = msg.sender == owner();

        if (dealersExeCore.hasActiveBoost(dealerId)) revert BoostAlreadyActive();

        BoostTier memory tier = boostTiers[tierId];

        if (!isAdmin) {
            if (msg.value < tier.price) revert InsufficientPayment();
        }

        dealersExeCore.applyBoost(
            dealerId,
            tier.duration,
            tier.drugMultiplier,
            tier.repMultiplier,
            tier.extraAttempts,
            tier.freeAreaMovement,
            tier.doubleHeistEntries,
            tier.cashMultiplier
        );

        IDealersExeCore.BoostData memory boost = dealersExeCore.getBoost(dealerId);

        emit BoostPurchased(dealerId, tierId, msg.sender, boost.expiresAt);

        if (!isAdmin) {
            paymentHandler.processMarketplaceFee{value: tier.price}(msg.sender, tier.price);
            if (msg.value > tier.price) {
                _safeTransferETH(msg.sender, msg.value - tier.price);
            }
        }
    }

    /**
     * @notice Purchase boost for multiple dealers at once
     * @dev Skips dealers not owned by caller (no revert)
     * @param dealerIds Array of dealer IDs to apply boost to
     * @param tierId The tier of boost to purchase
     */
    function purchaseBoostBatch(uint256[] calldata dealerIds, uint256 tierId)
        external
        payable
        nonReentrant
        whenNotPaused
        contractsSet
        validTier(tierId)
        tierActive(tierId)
    {
        uint256 len = dealerIds.length;
        if (len == 0) revert EmptyBatch();

        BoostTier memory tier = boostTiers[tierId];
        uint256 totalCost = tier.price * len;

        // Check total payment upfront
        if (msg.value < totalCost) revert InsufficientPayment();

        uint256 successfulPurchases = 0;

        for (uint256 i = 0; i < len; ) {
            uint256 dealerId = dealerIds[i];

            // Skip if not owner (don't revert for batch operations)
            if (dealersExeNFT.ownerOf(dealerId) != msg.sender) {
                unchecked { ++i; }
                continue;
            }

            // Skip if dealer not initialized
            (, , , , , bool isInitialized) = dealersExeCore.getDealerData(dealerId);
            if (!isInitialized) {
                unchecked { ++i; }
                continue;
            }

            // Skip if dealer already has an active boost
            if (dealersExeCore.hasActiveBoost(dealerId)) {
                unchecked { ++i; }
                continue;
            }

            // Apply boost
            dealersExeCore.applyBoost(
                dealerId,
                tier.duration,
                tier.drugMultiplier,
                tier.repMultiplier,
                tier.extraAttempts,
                tier.freeAreaMovement,
                tier.doubleHeistEntries,
                tier.cashMultiplier
            );

            unchecked {
                ++successfulPurchases;
            }

            // Get the new expiry for the event
            IDealersExeCore.BoostData memory boost = dealersExeCore.getBoost(dealerId);
            emit BoostPurchased(dealerId, tierId, msg.sender, boost.expiresAt);

            unchecked { ++i; }
        }

        // Calculate actual cost based on successful purchases
        uint256 actualCost = tier.price * successfulPurchases;

        // Process payment for successful purchases
        if (actualCost > 0) {
            paymentHandler.processMarketplaceFee{value: actualCost}(msg.sender, actualCost);
        }

        // Refund excess (including for skipped dealers)
        if (msg.value > actualCost) {
            _safeTransferETH(msg.sender, msg.value - actualCost);
        }
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get details of a specific boost tier
     * @param tierId The tier ID to query
     * @return The boost tier data
     */
    function getBoostTier(uint256 tierId) external view returns (BoostTier memory) {
        return boostTiers[tierId];
    }

    /**
     * @notice Get all active boost tiers
     * @return tiers Array of all active boost tiers
     * @return tierIds Array of tier IDs corresponding to the tiers
     */
    function getActiveTiers() external view returns (
        BoostTier[] memory tiers,
        uint256[] memory tierIds
    ) {
        // First, count active tiers
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= totalTiers; ) {
            if (boostTiers[i].isActive) {
                unchecked { ++activeCount; }
            }
            unchecked { ++i; }
        }

        // Allocate arrays
        tiers = new BoostTier[](activeCount);
        tierIds = new uint256[](activeCount);

        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 1; i <= totalTiers; ) {
            if (boostTiers[i].isActive) {
                tiers[index] = boostTiers[i];
                tierIds[index] = i;
                unchecked { ++index; }
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Check if a dealer currently has an active boost
     * @param dealerId The dealer ID to check
     * @return hasBoost Whether the dealer has an active boost
     * @return expiresAt When the boost expires (0 if no boost)
     */
    function checkBoostStatus(uint256 dealerId) external view returns (
        bool hasBoost,
        uint64 expiresAt
    ) {
        hasBoost = dealersExeCore.hasActiveBoost(dealerId);
        if (hasBoost) {
            IDealersExeCore.BoostData memory boost = dealersExeCore.getBoost(dealerId);
            expiresAt = boost.expiresAt;
        }
    }

    /**
     * @notice Calculate total cost for a batch purchase
     * @param dealerCount Number of dealers to boost
     * @param tierId The tier to purchase
     * @return totalCost Total ETH required
     */
    function calculateBatchCost(uint256 dealerCount, uint256 tierId)
        external
        view
        validTier(tierId)
        returns (uint256 totalCost)
    {
        return boostTiers[tierId].price * dealerCount;
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Set or update a boost tier configuration
     * @dev Can update existing tiers or add new ones
     * @param tierId The tier ID to set (use totalTiers + 1 for new tier)
     * @param tier The tier configuration
     */
    function setBoostTier(uint256 tierId, BoostTier calldata tier) external onlyOwner {
        if (tierId == 0) revert InvalidTier();
        if (tierId > MAX_TIERS) revert InvalidTier();
        if (tier.price == 0) revert InvalidTier();
        if (tier.duration == 0) revert InvalidTier();
        if (tier.drugMultiplier == 0 || tier.repMultiplier == 0) revert InvalidTier();

        // If this is a new tier, update totalTiers
        if (tierId > totalTiers) {
            // Only allow sequential tier creation
            if (tierId != totalTiers + 1) revert InvalidTier();
            totalTiers = tierId;
        }

        boostTiers[tierId] = tier;

        emit BoostTierUpdated(
            tierId,
            tier.price,
            tier.duration,
            tier.isActive
        );
    }

    /**
     * @notice Enable or disable a boost tier
     * @param tierId The tier ID to modify
     * @param active Whether the tier should be active
     */
    function setTierActive(uint256 tierId, bool active) external onlyOwner validTier(tierId) {
        boostTiers[tierId].isActive = active;
        emit BoostTierActiveStatusChanged(tierId, active);
    }

    /**
     * @notice Update the price of a boost tier
     * @param tierId The tier ID to modify
     * @param newPrice The new price in wei
     */
    function setTierPrice(uint256 tierId, uint256 newPrice) external onlyOwner validTier(tierId) {
        if (newPrice == 0) revert InvalidTier();
        uint256 oldPrice = boostTiers[tierId].price;
        boostTiers[tierId].price = newPrice;
        emit BoostTierPriceUpdated(tierId, oldPrice, newPrice);
    }

    /**
     * @notice Updates the core dealers contract address
     * @param _dealersExeCore The new core dealers contract address
     */
    function setDealersExeCore(address _dealersExeCore) external onlyOwner {
        if (_dealersExeCore == address(0)) revert InvalidAddress();
        address old = address(dealersExeCore);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        emit CoreContractUpdated(old, _dealersExeCore);
    }

    /**
     * @notice Updates the NFT contract address
     * @param _dealersExeNFT The new NFT contract address
     */
    function setDealersExeNFT(address _dealersExeNFT) external onlyOwner {
        if (_dealersExeNFT == address(0)) revert InvalidAddress();
        address old = address(dealersExeNFT);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        emit NFTContractUpdated(old, _dealersExeNFT);
    }

    /**
     * @notice Updates the payment handler contract address
     * @param _paymentHandler The new payment handler address
     */
    function setPaymentHandler(address _paymentHandler) external onlyOwner {
        if (_paymentHandler == address(0)) revert InvalidAddress();
        address old = address(paymentHandler);
        paymentHandler = IDEPaymentHandler(_paymentHandler);
        emit PaymentHandlerUpdated(old, _paymentHandler);
    }

    /**
     * @notice Pauses the contract, preventing boost purchases
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the contract, allowing boost purchases
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Emergency function to recover stuck ETH
     * @dev Only callable by owner in case of stuck funds
     * @param to Address to send ETH to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientPayment();
        _safeTransferETH(to, amount);
    }

    /**
     * @notice Get the current contract balance
     * @return The ETH balance of this contract
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Allows the contract to receive ETH
     */
    receive() external payable {}
}
