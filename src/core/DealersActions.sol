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

    /// @dev Modules permitted to call arrest() — typically PVE and PVP
    mapping(address => bool) public authorizedJailers;


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
    event JailerAuthorized(address indexed module, bool authorized);
    event DealerJailed(
        uint256 indexed tokenId,
        uint8 fromArea,
        uint256 repLoss,
        uint256 confiscatedDrugId,
        uint256 confiscatedAmount
    );

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
    error NotAuthorizedJailer();

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

    // =============================================================
    //                    BREAKOUT (commit-reveal)
    // =============================================================

    struct BreakoutRound {
        uint256 tokenId;
        uint8 returnArea;
    }

    mapping(uint64 => BreakoutRound) public pendingBreakouts;
    mapping(uint256 => uint64) public activeBreakoutOf;

    error RoundPending();
    error UnknownRound();

    event BreakoutCommitted(uint64 indexed seq, uint256 indexed tokenId);
    event BreakoutExpired(uint64 indexed seq, uint256 indexed tokenId);

    /**
     * @notice Commit to a free daily jailbreak attempt; the outcome is revealed in a later tx.
     */
    function commitBreakout(uint256 tokenId)
        external
        nonReentrant
        onlyDealerOwner(tokenId)
        returns (uint64 seq)
    {
        if (address(randomness) == address(0)) revert ContractNotSet();
        if (activeBreakoutOf[tokenId] != 0) revert RoundPending();

        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (!gs.isJailed) revert NotInJail();

        uint256 dayStart = (block.timestamp / 1 days) * 1 days;
        if (gs.lastBreakoutAttempt >= dayStart) revert BreakoutAlreadyAttemptedToday();

        core.setLastBreakoutAttempt(tokenId, uint32(block.timestamp));

        uint8 returnArea = gs.previousArea;
        if (!areaRegistry.isValidArea(returnArea) || areaRegistry.isJail(returnArea)) {
            returnArea = 1;
        }

        seq = randomness.commit();
        pendingBreakouts[seq] = BreakoutRound({tokenId: tokenId, returnArea: returnArea});
        activeBreakoutOf[tokenId] = seq;

        emit BreakoutCommitted(seq, tokenId);
    }

    /**
     * @notice Resolve a previously committed breakout. Anyone may call.
     * @dev If the reveal block has expired, the daily lockout still stands; this is a
     *      locked design decision (no attempt refund on expiry).
     */
    function resolveBreakout(uint64 seq) external nonReentrant {
        BreakoutRound memory r = pendingBreakouts[seq];
        if (r.tokenId == 0) revert UnknownRound();

        delete pendingBreakouts[seq];
        delete activeBreakoutOf[r.tokenId];

        if (randomness.isExpired(seq)) {
            emit BreakoutExpired(seq, r.tokenId);
            return;
        }

        uint256 rand = randomness.reveal(seq);
        ( , , , , , , , , uint8 breakoutSuccessChance, , , ) = core.config();
        bool success = (rand % 100) < breakoutSuccessChance;

        // If the dealer paid bail (or otherwise left jail) between commit and resolve,
        // skip the teleport — a successful breakout shouldn't yank them out of wherever
        // they chose to be.
        uint8 jailArea = core.JAIL_AREA();
        bool stillJailed = core.getGameState(r.tokenId).currentArea == jailArea;
        if (success && stillJailed) {
            core.forceMove(r.tokenId, r.returnArea);
        }

        emit BreakoutAttempted(r.tokenId, success, success && stillJailed ? r.returnArea : jailArea);
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
        bool isFirstMove = oldArea == core.STARTING_AREA() && gs.previousArea == core.STARTING_AREA();
        bool noFee = hasFreeMovement || isFirstMove || enteringBlackMarket || exitingBlackMarket;

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

    // =============================================================
    //                  WANTED POSTER (commit-reveal)
    // =============================================================

    struct WantedPosterRound {
        uint256 tokenId;
    }

    mapping(uint64 => WantedPosterRound) public pendingWantedPosters;
    mapping(uint256 => uint64) public activeWantedPosterOf;

    event WantedPosterCommitted(uint64 indexed seq, uint256 indexed tokenId);
    event WantedPosterExpired(uint64 indexed seq, uint256 indexed tokenId);

    /**
     * @notice Commit to spending an attempt to randomly clear heat. Outcome revealed later.
     */
    function commitWantedPoster(uint256 tokenId)
        external
        nonReentrant
        onlyDealerOwner(tokenId)
        returns (uint64 seq)
    {
        if (address(randomness) == address(0)) revert ContractNotSet();
        if (activeWantedPosterOf[tokenId] != 0) revert RoundPending();

        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        if (gs.isJailed) revert DealerInJail();
        if (gs.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();
        if (gs.heatLevel == 0) revert NoHeatToReduce();

        core.useAttempt(tokenId);

        seq = randomness.commit();
        pendingWantedPosters[seq] = WantedPosterRound({tokenId: tokenId});
        activeWantedPosterOf[tokenId] = seq;

        emit WantedPosterCommitted(seq, tokenId);
    }

    /**
     * @notice Resolve a previously committed wanted-poster round. Anyone may call.
     * @dev On expiry the attempt is forfeit (locked decision).
     */
    function resolveWantedPoster(uint64 seq) external nonReentrant {
        WantedPosterRound memory r = pendingWantedPosters[seq];
        if (r.tokenId == 0) revert UnknownRound();

        delete pendingWantedPosters[seq];
        delete activeWantedPosterOf[r.tokenId];

        if (randomness.isExpired(seq)) {
            emit WantedPosterExpired(seq, r.tokenId);
            return;
        }

        uint256 rand = randomness.reveal(seq);
        ( , , , , , , , uint8 wantedPosterSuccessChance, , , , ) = core.config();
        bool success = (rand % 100) < wantedPosterSuccessChance;

        if (success) {
            core.setHeatLevel(r.tokenId, 0);
        }
        emit WantedPosterRemoved(r.tokenId, success);
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
    //                       ARREST (centralized)
    // =============================================================

    /**
     * @notice Apply jail policy to a dealer: rep loss, drug confiscation, move to jail
     * @dev Auth-gated to modules registered via authorizeJailer (typically PVE/PVP).
     *      Heat is incremented as part of the jail outcome. Stake handling is the caller's
     *      responsibility (already debited at commit in PVE; not relevant for PVP).
     * @param tokenId Dealer being arrested
     * @param confiscRng Caller-supplied entropy used to pick a held drug for confiscation
     * @return confiscDrugId Drug confiscated (0 if none)
     * @return confiscAmt Amount confiscated
     */
    function arrest(uint256 tokenId, uint256 confiscRng)
        external
        nonReentrant
        returns (uint256 confiscDrugId, uint256 confiscAmt)
    {
        if (!authorizedJailers[msg.sender]) revert NotAuthorizedJailer();

        IDealersCore.GameState memory s = core.getGameState(tokenId);
        if (s.currentArea == core.JAIL_AREA()) return (0, 0);

        ( , , , , , uint8 jailRepPct, uint256 jailRepCap, , , uint8 jailDrugPct, , ) = core.config();

        uint256 repLoss = (s.reputation * jailRepPct) / 100;
        if (repLoss > jailRepCap) repLoss = jailRepCap;

        IDealersCore.GameOutcome memory ao;
        ao.repDelta = -int256(repLoss);
        ao.incrementHeat = true;

        if (jailDrugPct > 0) {
            (uint256 drugId, uint256 bal) = core.pickHeldDrugByRng(tokenId, confiscRng);
            if (drugId != 0 && bal > 0) {
                confiscAmt = (bal * jailDrugPct + 99) / 100;
                ao.drugId = drugId;
                ao.drugDelta = -int256(confiscAmt);
                confiscDrugId = drugId;
            }
        }

        core.applyGameOutcome(tokenId, ao);
        core.forceMove(tokenId, core.JAIL_AREA());

        emit DealerJailed(tokenId, s.currentArea, repLoss, confiscDrugId, confiscAmt);
    }

    // =============================================================
    //                      ADMIN SETTERS
    // =============================================================

    /**
     * @notice Authorize or revoke a module's permission to call arrest()
     */
    function authorizeJailer(address module, bool authorized) external onlyOwner {
        if (module == address(0)) revert InvalidAddress();
        authorizedJailers[module] = authorized;
        emit JailerAuthorized(module, authorized);
    }

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
