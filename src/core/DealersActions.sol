// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IDealersCore} from "./IDealersCore.sol";
import {DealersCore} from "./DealersCore.sol";
import "../utils/IAreaRegistry.sol";
import "../utils/IERC721Minimal.sol";
import "../utils/IDealersPaymentHandler.sol";
import "../utils/IDealersRandomness.sol";

/**
 * @title DealersActions - Player Action Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Handles non-combat player actions: jail bail/breakout, travel between areas,
 *      heat reduction (bribe/wanted poster), attempt resets, cash purchases, and drug sales
 * @author Berny0x
 */
contract DealersActions is ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    uint256 public constant BLACK_MARKET_MIN_INFAMY = 10;

    DealersCore public core;
    IERC721Minimal public nftContract;
    IDealersPaymentHandler public paymentHandler;
    IAreaRegistry public areaRegistry;
    IDealersRandomness public randomness;


    // =============================================================
    //                            EVENTS
    // =============================================================

    event DealerBailed(uint256 indexed tokenId, uint256 bailPaid, uint8 newArea);
    event BreakoutAttempted(uint256 indexed tokenId, bool success, uint8 exitArea);
    event WantedPosterRemoved(uint256 indexed tokenId, bool success);
    event CopBribed(uint256 indexed tokenId, uint256 feePaid);
    event CashPurchased(uint256 indexed tokenId, uint256 amount, uint256 ethPaid);
    event DealerTraveled(uint256 indexed tokenId, uint8 fromArea, uint8 toArea, uint256 feePaid, bool wasFreeMovement);
    event DropsConverted(uint256 indexed tokenId, uint256 indexed drugId, uint256 amount, uint256 cashEarned);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidAddress();
    error NotDealerOwner();
    error NFTContractNotSet();
    error DealerInJail();
    error NotInJail();
    error InsufficientBail();
    error BreakoutAlreadyAttemptedToday();
    error NoHeatToReduce();
    error NoAttemptsRemaining();
    error InsufficientPayment();
    error CashBalanceTooHigh();
    error ETHTransferFailed();
    error ContractNotSet();
    error NotInBlackMarket();
    error NotSellableDrop();
    error InvalidAmount();
    error AlreadyInArea();
    error InsufficientInfamy();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        address _core,
        address _nftContract,
        address _areaRegistry
    ) {
        if (_core == address(0)) revert InvalidAddress();
        if (_nftContract == address(0)) revert InvalidAddress();
        if (_areaRegistry == address(0)) revert InvalidAddress();

        _initializeOwner(msg.sender);

        core = DealersCore(_core);
        nftContract = IERC721Minimal(_nftContract);
        areaRegistry = IAreaRegistry(_areaRegistry);
    }

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    modifier onlyDealerOwner(uint256 tokenId) {
        if (address(nftContract) == address(0)) revert NFTContractNotSet();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();
        _;
    }

    // =============================================================
    //                      PLAYER ACTIONS
    // =============================================================

    /**
     * @notice Pay bail to release a jailed dealer, resetting heat and returning to previous area
     * @param tokenId The dealer NFT token ID
     */
    function payBail(uint256 tokenId)
        external
        payable
        nonReentrant
        onlyDealerOwner(tokenId)
    {
        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (!gs.isJailed) revert NotInJail();

        uint256 bail = areaRegistry.getMovementFee(core.JAIL_AREA());
        if (msg.value < bail) revert InsufficientBail();

        uint8 returnArea = gs.previousArea;
        if (!areaRegistry.isValidArea(returnArea) || areaRegistry.isJail(returnArea)) {
            returnArea = 1;
        }

        core.setHeatLevel(tokenId, 0);
        core.forceMove(tokenId, returnArea);

        if (address(paymentHandler) != address(0) && bail > 0) {
            paymentHandler.processMovementFee{value: bail}(msg.sender, bail);
        }

        if (msg.value > bail) {
            _safeTransferETH(msg.sender, msg.value - bail);
        }

        emit DealerBailed(tokenId, bail, returnArea);
    }

    /**
     * @notice Attempt a free jailbreak once per day with a random success chance
     * @param tokenId The dealer NFT token ID
     */
    function attemptBreakout(uint256 tokenId)
        external
        nonReentrant
        onlyDealerOwner(tokenId)
    {
        if (address(randomness) == address(0)) revert ContractNotSet();

        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (!gs.isJailed) revert NotInJail();

        uint256 dayStart = (block.timestamp / 1 days) * 1 days;
        if (gs.lastBreakoutAttempt >= dayStart) revert BreakoutAlreadyAttemptedToday();

        core.setLastBreakoutAttempt(tokenId, uint32(block.timestamp));

        bytes32 seed = keccak256(abi.encodePacked(tokenId, "BREAKOUT", block.timestamp, block.prevrandao));
        uint256 roll = randomness.getRandomness(seed) % 100;

        (, , , , , , , , uint8 breakoutSuccessChance, , , ) = core.config();
        bool success = roll < breakoutSuccessChance;

        uint8 returnArea = gs.previousArea;
        if (!areaRegistry.isValidArea(returnArea) || areaRegistry.isJail(returnArea)) {
            returnArea = 1;
        }

        if (success) {
            core.forceMove(tokenId, returnArea);
        }

        emit BreakoutAttempted(tokenId, success, success ? returnArea : core.JAIL_AREA());
    }

    /**
     * @notice Move a dealer to a different area, paying the movement fee unless exempt
     * @param tokenId The dealer NFT token ID
     * @param destinationArea The target area ID (ignored when exiting black market)
     */
    function travel(uint256 tokenId, uint8 destinationArea)
        external
        payable
        nonReentrant
        onlyDealerOwner(tokenId)
    {
        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (gs.isJailed) revert DealerInJail();

        uint8 oldArea = gs.currentArea;
        bool exitingBlackMarket = areaRegistry.isBlackMarket(oldArea);

        if (exitingBlackMarket) {
            destinationArea = gs.previousArea;
            if (
                !areaRegistry.isValidArea(destinationArea) ||
                areaRegistry.isJail(destinationArea) ||
                areaRegistry.isBlackMarket(destinationArea)
            ) {
                destinationArea = core.STARTING_AREA();
            }
        } else {
            if (!areaRegistry.isValidArea(destinationArea)) revert DealersCore.InvalidArea();
            if (areaRegistry.isJail(destinationArea)) revert DealersCore.CannotEnterJail();
            uint256 minRep = areaRegistry.getMinReputation(destinationArea);
            if (minRep > 0 && gs.totalReputation < minRep) revert DealersCore.InsufficientReputation();
        }

        if (oldArea == destinationArea) revert AlreadyInArea();

        bool enteringBlackMarket = areaRegistry.isBlackMarket(destinationArea);
        if (enteringBlackMarket) {
            uint256 infamy = core.getInfamy(tokenId);
            if (infamy < BLACK_MARKET_MIN_INFAMY) revert InsufficientInfamy();
        }
        bool hasFreeMovement = gs.boostActive && gs.freeAreaMovement;
        bool enteringSafeHouse = areaRegistry.isSafeHouse(destinationArea);
        bool isFirstMove = oldArea == core.STARTING_AREA() && gs.previousArea == core.STARTING_AREA();
        bool noFee = hasFreeMovement || enteringSafeHouse || isFirstMove || enteringBlackMarket || exitingBlackMarket;

        uint256 movementFee = 0;
        if (!noFee) {
            movementFee = areaRegistry.getMovementFee(destinationArea);
            if (msg.value < movementFee) revert InsufficientPayment();
        }

        core.forceMove(tokenId, destinationArea);

        if (movementFee > 0 && address(paymentHandler) != address(0)) {
            paymentHandler.processMovementFee{value: movementFee}(msg.sender, movementFee);
        }

        if (msg.value > movementFee) {
            _safeTransferETH(msg.sender, msg.value - movementFee);
        }

        emit DealerTraveled(tokenId, oldArea, destinationArea, movementFee, noFee);
    }

    /**
     * @notice Pay a fee to reset heat level to zero
     * @param tokenId The dealer NFT token ID
     */
    function bribeCop(uint256 tokenId)
        external
        payable
        nonReentrant
        onlyDealerOwner(tokenId)
    {
        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (gs.isJailed) revert DealerInJail();
        if (gs.heatLevel == 0) revert NoHeatToReduce();

        (, uint256 bribeCopFee, , , , , , , , , , ) = core.config();
        if (msg.value < bribeCopFee) revert InsufficientPayment();

        core.setHeatLevel(tokenId, 0);

        if (address(paymentHandler) != address(0)) {
            paymentHandler.processMarketplaceFee{value: bribeCopFee}(msg.sender, bribeCopFee);
        }

        if (msg.value > bribeCopFee) {
            _safeTransferETH(msg.sender, msg.value - bribeCopFee);
        }

        emit CopBribed(tokenId, bribeCopFee);
    }

    /**
     * @notice Spend an attempt to randomly clear heat (no ETH cost)
     * @param tokenId The dealer NFT token ID
     */
    function removeWantedPoster(uint256 tokenId)
        external
        nonReentrant
        onlyDealerOwner(tokenId)
    {
        if (address(randomness) == address(0)) revert ContractNotSet();

        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (gs.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();
        if (gs.heatLevel == 0) revert NoHeatToReduce();

        core.useAttempt(tokenId);

        bytes32 seed = keccak256(abi.encodePacked(tokenId, "WANTED_POSTER", block.timestamp, block.prevrandao));
        uint256 roll = randomness.getRandomness(seed) % 100;

        (, , , , , , , uint8 wantedPosterSuccessChance, , , , ) = core.config();

        if (roll < wantedPosterSuccessChance) {
            core.setHeatLevel(tokenId, 0);
            emit WantedPosterRemoved(tokenId, true);
        } else {
            emit WantedPosterRemoved(tokenId, false);
        }
    }

    /**
     * @notice Purchase a daily attempt reset for a dealer (free for contract owner)
     * @param tokenId The dealer NFT token ID
     */
    function purchaseAttemptReset(uint256 tokenId)
        external
        payable
        nonReentrant
    {
        bool isAdmin = msg.sender == owner();
        (uint256 attemptResetFee, , , , , , , , , , , ) = core.config();

        if (!isAdmin) {
            if (msg.value < attemptResetFee) revert InsufficientPayment();
        }

        core.resetDailyAttempts(tokenId);

        if (!isAdmin) {
            if (address(paymentHandler) != address(0)) {
                paymentHandler.processMarketplaceFee{value: attemptResetFee}(msg.sender, attemptResetFee);
            }
            if (msg.value > attemptResetFee) {
                _safeTransferETH(msg.sender, msg.value - attemptResetFee);
            }
        }
    }

    /**
     * @notice Purchase $CASH for a dealer with ETH (free for contract owner, capped by threshold)
     * @param tokenId The dealer NFT token ID
     */
    function purchaseCash(uint256 tokenId)
        external
        payable
        nonReentrant
    {
        bool isAdmin = msg.sender == owner();
        (, , uint256 cashTopupPrice, uint256 cashTopupAmount, uint256 cashPurchaseThreshold, , , , , , , ) = core.config();

        if (core.getCashBalance(tokenId) >= cashPurchaseThreshold) revert CashBalanceTooHigh();

        if (!isAdmin) {
            if (msg.value < cashTopupPrice) revert InsufficientPayment();
        }

        core.addCash(tokenId, cashTopupAmount);

        emit CashPurchased(tokenId, cashTopupAmount, cashTopupPrice);

        if (!isAdmin) {
            if (address(paymentHandler) != address(0)) {
                paymentHandler.processMarketplaceFee{value: cashTopupPrice}(msg.sender, cashTopupPrice);
            }
            if (msg.value > cashTopupPrice) {
                _safeTransferETH(msg.sender, msg.value - cashTopupPrice);
            }
        }
    }

    /**
     * @notice Sell drugs for $CASH at the black market
     * @param tokenId The dealer NFT token ID
     * @param drugId The drug to sell
     * @param amount Quantity to sell
     */
    function sellDrop(uint256 tokenId, uint256 drugId, uint256 amount)
        external
        nonReentrant
        onlyDealerOwner(tokenId)
    {
        if (amount == 0) revert InvalidAmount();

        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (!areaRegistry.isBlackMarket(gs.currentArea)) revert NotInBlackMarket();
        if (!areaRegistry.isDrugAvailableInArea(gs.currentArea, drugId)) revert NotSellableDrop();

        (, uint256 sellPrice) = areaRegistry.getDrugPricing(gs.currentArea, drugId);
        uint256 cashEarned = sellPrice * amount;

        core.updateDrugBalance(tokenId, drugId, -int256(amount));
        core.addCash(tokenId, cashEarned);

        emit DropsConverted(tokenId, drugId, amount, cashEarned);
    }

    // =============================================================
    //                      ADMIN SETTERS
    // =============================================================

    /**
     * @notice Set the payment handler contract
     * @param _paymentHandler Address of the DealersPaymentHandler
     */
    function setPaymentHandler(address _paymentHandler) external onlyOwner {
        if (_paymentHandler == address(0)) revert InvalidAddress();
        paymentHandler = IDealersPaymentHandler(_paymentHandler);
    }

    /**
     * @notice Set the randomness provider contract
     * @param _randomness Address of the DealersRandomness contract
     */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert InvalidAddress();
        randomness = IDealersRandomness(_randomness);
    }

    /**
     * @notice Set the NFT contract used for ownership checks
     * @param _nftContract Address of the DealersNFT contract
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert InvalidAddress();
        nftContract = IERC721Minimal(_nftContract);
    }

    /**
     * @notice Set the area registry contract
     * @param _areaRegistry Address of the DealersAreaRegistry contract
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert InvalidAddress();
        areaRegistry = IAreaRegistry(_areaRegistry);
    }

    // =============================================================
    //                      INTERNAL HELPERS
    // =============================================================

    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }
}
