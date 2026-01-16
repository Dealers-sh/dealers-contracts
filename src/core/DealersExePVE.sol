// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IDealersExeCore.sol";
import "../utils/IAreaRegistry.sol";
import "../utils/IERC721Minimal.sol";
import "../utils/IDERandomness.sol";

/**
 * @title DealersExePVE - Simplified Player vs Environment Game Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Handles PVE gameplay with jail/heat mechanics and boost multipliers
 *      Uses AreaRegistry for drug pricing per area
 * @author Dealers.Exe Team
 */
contract DealersExePVE is ReentrancyGuard, Ownable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    // Game choices and types
    enum GameChoice { DEAL, THREATEN, BAIL }   // 0,1,2
    enum GameOutcome { WIN, TIE, LOSS }        // 0,1,2
    enum HustleType { BUY, SELL }              // 0=BUY, 1=SELL

    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersExeCore public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    IAreaRegistry public areaRegistry;
    IDERandomness public randomness;

    // Statistics
    mapping(uint256 => uint256) public playerGamesPlayed;   // tokenId => total games
    mapping(uint256 => uint256) public playerGamesWon;      // tokenId => games won
    mapping(uint256 => uint256) public playerTimesJailed;   // tokenId => times jailed during PVE
    uint256 public totalGamesPlayed;
    uint256 public totalGamesWon;
    uint256 public totalArrestsInPVE;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event GamePlayed(
        uint256 indexed tokenId,
        address indexed player,
        uint8 playerChoice,
        uint8 houseChoice,
        uint8 outcome,
        HustleType hustleType,
        uint256 drugId,
        uint256 drugAmount,
        int256 cashChange,
        int256 reputationChange
    );

    event DealerArrested(
        uint256 indexed tokenId,
        address indexed player,
        uint8 heatLevel
    );

    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event AreaRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event RandomnessUpdated(address indexed oldRandomness, address indexed newRandomness);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error InvalidGameChoice();
    error DealerNotInitialized();
    error DealerInJail();
    error DealerInSafeHouse();
    error NoAttemptsRemaining();
    error NotDealerOwner();
    error InsufficientCash();
    error InsufficientDrugs();
    error InvalidDrug();
    error DrugNotAvailableInArea();
    error InvalidAmount();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the simplified PVE contract
     * @param _dealersExeCore Address of the core dealers contract
     * @param _dealersExeNFT Address of the NFT contract for ownership checks
     * @param _areaRegistry Address of the area registry for drug pricing
     */
    constructor(address _dealersExeCore, address _dealersExeNFT, address _areaRegistry) {
        _initializeOwner(msg.sender);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        areaRegistry = IAreaRegistry(_areaRegistry);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(dealersExeCore) == address(0) ||
            address(dealersExeNFT) == address(0) ||
            address(areaRegistry) == address(0) ||
            address(randomness) == address(0)
        ) {
            revert ContractNotSet();
        }
        _;
    }

    modifier validChoice(uint8 choice) {
        if (choice > 2) revert InvalidGameChoice();
        _;
    }

    modifier dealerExists(uint256 tokenId) {
        (, , , , , bool isInitialized) = dealersExeCore.getDealerData(tokenId);
        if (!isInitialized) revert DealerNotInitialized();
        _;
    }

    modifier onlyDealerOwner(uint256 tokenId) {
        if (dealersExeNFT.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();
        _;
    }

    // =============================================================
    //                        PVE GAME FUNCTION
    // =============================================================

    /**
     * @notice Play a PVE hustle game (buy or sell drugs)
     * @param tokenId The ID of the dealer NFT to use for the game
     * @param choice The player's choice: 0=DEAL, 1=THREATEN, 2=BAIL
     * @param hustleType 0=BUY (stake $CASH), 1=SELL (stake drugs)
     * @param drugId The drug ID to trade
     * @param amount The amount to stake
     */
    function playGame(
        uint256 tokenId,
        uint8 choice,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount
    )
        external
        nonReentrant
        contractsSet
        dealerExists(tokenId)
        validChoice(choice)
        onlyDealerOwner(tokenId)
    {
        // 1. Validate dealer location
        if (dealersExeCore.isInJail(tokenId)) revert DealerInJail();
        if (dealersExeCore.isInSafeHouse(tokenId)) revert DealerInSafeHouse();

        // 2. Validate amount
        if (amount == 0) revert InvalidAmount();

        // 3. Validate drug is available in current area and get pricing
        (uint8 currentArea, , , , , ) = dealersExeCore.getDealerData(tokenId);
        (uint256 buyPrice, uint256 sellPrice, bool found) = _getDrugPricing(currentArea, drugId);
        if (!found) revert DrugNotAvailableInArea();

        // 4. Calculate stake value and validate balance
        uint256 stakeValue;
        if (hustleType == HustleType.BUY) {
            stakeValue = amount * buyPrice;
            if (dealersExeCore.getCashBalance(tokenId) < stakeValue) revert InsufficientCash();
        } else {
            if (dealersExeCore.getDrugBalance(tokenId, drugId) < amount) revert InsufficientDrugs();
            stakeValue = amount * sellPrice;
        }

        // 5. Use 1 attempt
        dealersExeCore.useAttempt(tokenId);

        // 6. Increment heat level
        dealersExeCore.incrementHeatLevel(tokenId);

        // 7. Generate randomness
        bytes32 seed = keccak256(abi.encodePacked(tokenId, msg.sender, totalGamesPlayed));
        uint256 gameRandomness = randomness.getRandomness(seed);

        // 8. Check jail - if arrested, lose stake
        if (_checkAndProcessArrest(tokenId, gameRandomness, hustleType, drugId, amount, stakeValue)) {
            return;
        }

        // 9. Process game outcome
        _processHustleGame(tokenId, choice, hustleType, drugId, amount, buyPrice, sellPrice, gameRandomness);
    }

    /**
     * @notice Check if dealer gets arrested and process stake loss
     */
    function _checkAndProcessArrest(
        uint256 tokenId,
        uint256 rng,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount,
        uint256 stakeValue
    ) private returns (bool) {
        uint8 jailChance = dealersExeCore.getJailChance(tokenId);
        uint8 jailRoll = uint8(rng % 100);

        if (jailRoll < jailChance) {
            // Arrested! Lose stake
            if (hustleType == HustleType.BUY) {
                dealersExeCore.spendCash(tokenId, stakeValue);
            } else {
                dealersExeCore.updateDrugBalance(tokenId, drugId, -int256(amount));
            }

            dealersExeCore.sendToJail(tokenId);

            unchecked {
                ++playerTimesJailed[tokenId];
                ++totalArrestsInPVE;
            }

            emit DealerArrested(tokenId, msg.sender, jailChance);
            return true;
        }
        return false;
    }

    /**
     * @notice Process hustle game outcome
     */
    function _processHustleGame(
        uint256 tokenId,
        uint8 choice,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 rng
    ) private {
        uint256 gameRng = uint256(keccak256(abi.encodePacked(rng, "GAME")));
        uint8 houseChoice = uint8(gameRng % 3);
        uint8 outcome = _calculateGameOutcome(choice, houseChoice);

        int256 repChange;
        int256 cashChange;

        if (hustleType == HustleType.BUY) {
            (repChange, cashChange, ) = _processBuyOutcome(
                tokenId, outcome, drugId, amount, buyPrice
            );
        } else {
            (repChange, cashChange, ) = _processSellOutcome(
                tokenId, outcome, drugId, amount, sellPrice
            );
        }

        _updateStatistics(tokenId, outcome);

        emit GamePlayed(
            tokenId,
            msg.sender,
            choice,
            houseChoice,
            outcome,
            hustleType,
            drugId,
            amount,
            cashChange,
            repChange
        );
    }

    // =============================================================
    //                        INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Calculates the game outcome based on player and house choices
     */
    function _calculateGameOutcome(uint8 playerChoice, uint8 houseChoice) internal pure returns (uint8) {
        if (playerChoice == houseChoice) return 1; // TIE

        if (
            (playerChoice == 0 && houseChoice == 1) ||
            (playerChoice == 1 && houseChoice == 2) ||
            (playerChoice == 2 && houseChoice == 0)
        ) {
            return 0; // WIN
        }

        return 2; // LOSS
    }

    /**
     * @notice Process BUY hustle outcome
     * WIN: Keep $CASH + Get drugs + Big rep
     * TIE: Lose $CASH + Get drugs + Small rep
     * LOSE: Lose $CASH + No drugs + Lose rep
     */
    function _processBuyOutcome(
        uint256 tokenId,
        uint8 outcome,
        uint256 drugId,
        uint256 amount,
        uint256 buyPrice
    ) private returns (int256 repChange, int256 cashChange, int256 drugChange) {
        uint256 cashCost = amount * buyPrice;

        int16 baseRepChange = dealersExeCore.getReputationChange(tokenId, outcome);

        if (outcome == 0) {
            // WIN: Keep $CASH + Get drugs + Big rep
            uint8 repMultiplier = dealersExeCore.getRepMultiplier(tokenId);
            repChange = (int256(baseRepChange) * int256(uint256(repMultiplier))) / 100;

            uint8 drugMultiplier = dealersExeCore.getDrugMultiplier(tokenId);
            uint256 boostedAmount = (amount * uint256(drugMultiplier)) / 100;

            dealersExeCore.updateDrugBalance(tokenId, drugId, int256(boostedAmount));
            drugChange = int256(boostedAmount);
            cashChange = 0;

        } else if (outcome == 1) {
            // TIE: Lose $CASH + Get drugs + Small rep
            repChange = int256(baseRepChange);

            dealersExeCore.spendCash(tokenId, cashCost);
            cashChange = -int256(cashCost);

            uint8 drugMultiplier = dealersExeCore.getDrugMultiplier(tokenId);
            uint256 boostedAmount = (amount * uint256(drugMultiplier)) / 100;

            dealersExeCore.updateDrugBalance(tokenId, drugId, int256(boostedAmount));
            drugChange = int256(boostedAmount);

        } else {
            // LOSE: Lose $CASH + No drugs + Lose rep
            repChange = int256(baseRepChange);

            dealersExeCore.spendCash(tokenId, cashCost);
            cashChange = -int256(cashCost);
            drugChange = 0;
        }

        dealersExeCore.updateReputation(tokenId, repChange);
    }

    /**
     * @notice Process SELL hustle outcome
     * WIN: Keep drugs + Get $CASH + Big rep
     * TIE: Lose drugs + Get $CASH + Small rep
     * LOSE: Lose drugs + No $CASH + Lose rep
     */
    function _processSellOutcome(
        uint256 tokenId,
        uint8 outcome,
        uint256 drugId,
        uint256 amount,
        uint256 sellPrice
    ) private returns (int256 repChange, int256 cashChange, int256 drugChange) {
        uint256 cashReward = amount * sellPrice;

        int16 baseRepChange = dealersExeCore.getReputationChange(tokenId, outcome);

        if (outcome == 0) {
            // WIN: Keep drugs + Get $CASH + Big rep
            uint8 repMultiplier = dealersExeCore.getRepMultiplier(tokenId);
            repChange = (int256(baseRepChange) * int256(uint256(repMultiplier))) / 100;

            uint8 cashMultiplier = dealersExeCore.getCashMultiplier(tokenId);
            uint256 boostedCash = (cashReward * uint256(cashMultiplier)) / 100;

            dealersExeCore.addCash(tokenId, boostedCash);
            cashChange = int256(boostedCash);
            drugChange = 0;

        } else if (outcome == 1) {
            // TIE: Lose drugs + Get $CASH + Small rep
            repChange = int256(baseRepChange);

            uint8 cashMultiplier = dealersExeCore.getCashMultiplier(tokenId);
            uint256 boostedCash = (cashReward * uint256(cashMultiplier)) / 100;

            dealersExeCore.updateDrugBalance(tokenId, drugId, -int256(amount));
            drugChange = -int256(amount);

            dealersExeCore.addCash(tokenId, boostedCash);
            cashChange = int256(boostedCash);

        } else {
            // LOSE: Lose drugs + No $CASH + Lose rep
            repChange = int256(baseRepChange);

            dealersExeCore.updateDrugBalance(tokenId, drugId, -int256(amount));
            drugChange = -int256(amount);
            cashChange = 0;
        }

        dealersExeCore.updateReputation(tokenId, repChange);
    }

    /**
     * @notice Get drug pricing for an area from AreaRegistry
     */
    function _getDrugPricing(uint8 areaId, uint256 drugId)
        private
        view
        returns (uint256 buyPrice, uint256 sellPrice, bool found)
    {
        // Check if drug is available in this area
        if (!areaRegistry.isDrugAvailableInArea(areaId, drugId)) {
            return (0, 0, false);
        }

        // Get pricing from registry
        (buyPrice, sellPrice) = areaRegistry.getDrugPricing(areaId, drugId);
        return (buyPrice, sellPrice, true);
    }

    /**
     * @notice Updates game statistics
     */
    function _updateStatistics(uint256 tokenId, uint8 outcome) internal {
        unchecked {
            ++playerGamesPlayed[tokenId];
            ++totalGamesPlayed;
            if (outcome == 0) {
                ++playerGamesWon[tokenId];
                ++totalGamesWon;
            }
        }
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Check if a dealer can play a game
     */
    function canPlay(uint256 tokenId) external view returns (bool isPlayable, uint8 reason) {
        (, , uint8 attemptsRemaining, , , bool isInitialized) = dealersExeCore.getDealerData(tokenId);
        if (!isInitialized) return (false, 1);
        if (dealersExeCore.isInJail(tokenId)) return (false, 2);
        if (dealersExeCore.isInSafeHouse(tokenId)) return (false, 3);
        if (attemptsRemaining == 0) return (false, 4);
        return (true, 0);
    }

    /**
     * @notice Gets game statistics for a specific dealer NFT
     */
    function getPlayerStats(uint256 tokenId) external view returns (
        uint256 gamesPlayed,
        uint256 gamesWon,
        uint256 winRate,
        uint256 timesJailed
    ) {
        gamesPlayed = playerGamesPlayed[tokenId];
        gamesWon = playerGamesWon[tokenId];
        winRate = gamesPlayed == 0 ? 0 : (gamesWon * 100) / gamesPlayed;
        timesJailed = playerTimesJailed[tokenId];
    }

    /**
     * @notice Gets global game statistics
     */
    function getGlobalStats() external view returns (
        uint256 totalPlayed,
        uint256 totalWon,
        uint256 globalWinRate,
        uint256 totalArrests
    ) {
        totalPlayed = totalGamesPlayed;
        totalWon = totalGamesWon;
        globalWinRate = totalPlayed == 0 ? 0 : (totalWon * 100) / totalPlayed;
        totalArrests = totalArrestsInPVE;
    }

    /**
     * @notice Preview potential outcomes for a hustle
     */
    function previewHustle(uint256 tokenId, uint256 drugId, uint256 amount) external view returns (
        int16 winRep,
        int16 tieRep,
        int16 lossRep,
        uint256 cashValueOnSell,
        uint256 cashCostOnBuy
    ) {
        winRep = dealersExeCore.getReputationChange(tokenId, 0);
        tieRep = dealersExeCore.getReputationChange(tokenId, 1);
        lossRep = dealersExeCore.getReputationChange(tokenId, 2);

        (uint8 currentArea, , , , , ) = dealersExeCore.getDealerData(tokenId);
        (uint256 buyPrice, uint256 sellPrice, bool found) = _getDrugPricing(currentArea, drugId);

        if (found) {
            cashValueOnSell = amount * sellPrice;
            cashCostOnBuy = amount * buyPrice;
        }
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Updates the core dealers contract address
     */
    function setDealersExeCore(address _dealersExeCore) external onlyOwner {
        address old = address(dealersExeCore);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        emit CoreContractUpdated(old, _dealersExeCore);
    }

    /**
     * @notice Updates the NFT contract address
     */
    function setDealersExeNFT(address _dealersExeNFT) external onlyOwner {
        address old = address(dealersExeNFT);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        emit NFTContractUpdated(old, _dealersExeNFT);
    }

    /**
     * @notice Updates the Area Registry address
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    /**
     * @notice Updates the Randomness contract address
     */
    function setRandomness(address _randomness) external onlyOwner {
        address old = address(randomness);
        randomness = IDERandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }
}
