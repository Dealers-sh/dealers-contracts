// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IDealersExePVE} from "./IDealersExePVE.sol";
import "./IDealersExeCore.sol";
import "../utils/IAreaRegistry.sol";
import "../utils/IERC721Minimal.sol";
import "../utils/IDERandomness.sol";

/**
 * @title DealersExePVE - Player vs Environment Game Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Rock-paper-scissors style hustle game where dealers buy or sell drugs.
 *      Outcomes (win/tie/loss) are determined by biased house odds, with jail
 *      checks on every play. Reputation scales with stake value.
 * @author Berny0x
 */
contract DealersExePVE is IDealersExePVE, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersExeCore public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    IAreaRegistry public areaRegistry;
    IDERandomness public randomness;

    uint8 public tieChance = 50;
    uint8 public winChance = 20;

    uint256 public repStakeDivisor = 50;

    bool public paused;

    mapping(uint256 => PveStats) public dealerPveStats;

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
        int256 reputationChange,
        int256 drugBalanceChange,
        uint8 newHeatLevel
    );

    event DealerArrested(
        uint256 indexed tokenId,
        address indexed player,
        uint16 jailChance
    );

    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event AreaRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event RandomnessUpdated(address indexed oldRandomness, address indexed newRandomness);

    event Paused(address account);
    event Unpaused(address account);
    event OutcomeOddsUpdated(uint8 tieChance, uint8 winChance);
    event RepStakeDivisorUpdated(uint256 oldDivisor, uint256 newDivisor);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error ContractPaused();
    error InvalidGameChoice();
    error DealerNotInitialized();
    error DealerInJail();
    error DealerInSafeHouse();
    error NotDealerOwner();
    error InsufficientCash();
    error InsufficientDrugs();
    error DrugNotAvailableInArea();
    error InvalidAmount();
    error RandomnessError();
    error InvalidAddress();
    error InvalidOdds();
    error InvalidDivisor();
    error NoAttemptsRemaining();
    error DealerInBlackMarket();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

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

    modifier onlyDealerOwner(uint256 tokenId) {
        if (dealersExeNFT.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // =============================================================
    //                        PVE GAME FUNCTION
    // =============================================================

    /**
     * @notice Play a hustle round — pick a move, buy or sell drugs, and face the house
     * @param tokenId The dealer NFT token ID
     * @param choice Player's move: 0 = DEAL, 1 = THREATEN, 2 = BAIL
     * @param hustleType Whether the dealer is buying or selling drugs
     * @param drugId The drug being traded
     * @param amount Quantity of drugs to stake
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
        whenNotPaused
        contractsSet
        validChoice(choice)
        onlyDealerOwner(tokenId)
    {
        IDealersExeCore.GameState memory state = dealersExeCore.getGameState(tokenId);

        if (!state.isInitialized) revert DealerNotInitialized();
        if (state.isJailed) revert DealerInJail();
        if (state.isInSafeHouse) revert DealerInSafeHouse();
        if (areaRegistry.isBlackMarket(state.currentArea)) revert DealerInBlackMarket();
        if (state.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();
        if (amount == 0) revert InvalidAmount();

        (uint256 buyPrice, uint256 sellPrice, bool found) = _getDrugPricing(state.currentArea, drugId);
        if (!found) revert DrugNotAvailableInArea();

        uint256 stakeValue;
        if (hustleType == HustleType.BUY) {
            stakeValue = amount * buyPrice;
            if (state.cashBalance < stakeValue) revert InsufficientCash();
        } else {
            if (dealersExeCore.getDrugBalance(tokenId, drugId) < amount) revert InsufficientDrugs();
            stakeValue = amount * sellPrice;
        }

        bytes32 seed = keccak256(abi.encodePacked(tokenId, msg.sender, block.timestamp));
        uint256[] memory rngValues = randomness.getRandomValues(seed, 2);
        if (rngValues[0] == 0) revert RandomnessError();

        if (_checkAndProcessArrest(tokenId, state, rngValues[0], hustleType, drugId, amount, stakeValue)) {
            return;
        }

        _processHustleGame(tokenId, state, choice, hustleType, drugId, amount, buyPrice, sellPrice, rngValues[1]);
    }

    function _checkAndProcessArrest(
        uint256 tokenId,
        IDealersExeCore.GameState memory state,
        uint256 rng,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount,
        uint256 stakeValue
    ) private returns (bool) {
        if (dealersExeCore.rollJailCheck(tokenId, rng)) {
            IDealersExeCore.GameOutcome memory outcome;
            outcome.useAttempt = true;
            outcome.incrementHeat = true;
            outcome.sendToJail = true;

            if (hustleType == HustleType.BUY) {
                outcome.cashDelta = -int256(stakeValue);
            } else {
                outcome.drugId = drugId;
                outcome.drugDelta = -int256(amount);
            }

            dealersExeCore.applyGameOutcome(tokenId, outcome);

            emit DealerArrested(tokenId, msg.sender, state.jailChance);
            return true;
        }
        return false;
    }

    function _processHustleGame(
        uint256 tokenId,
        IDealersExeCore.GameState memory state,
        uint8 choice,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 rng
    ) private {
        uint8 roll = uint8(rng % 100);
        (uint8 houseChoice, uint8 gameOutcome) = _calculateBiasedHouseChoice(roll, choice);

        unchecked {
            PveStats storage stats = dealerPveStats[tokenId];
            if (gameOutcome == 0) stats.wins++;
            else if (gameOutcome == 1) stats.ties++;
            else stats.losses++;
            if (choice == 0) stats.dealChoices++;
            else if (choice == 1) stats.threatenChoices++;
            else stats.bailChoices++;
        }

        IDealersExeCore.GameOutcome memory outcome;
        outcome.useAttempt = true;
        outcome.incrementHeat = true;
        outcome.drugId = drugId;

        int256 repChange;
        int256 cashChange;
        int256 drugChange;

        if (hustleType == HustleType.BUY) {
            (repChange, cashChange, drugChange) = _computeBuyOutcome(
                state, gameOutcome, amount, buyPrice
            );
        } else {
            (repChange, cashChange, drugChange) = _computeSellOutcome(
                state, gameOutcome, amount, sellPrice
            );
        }

        outcome.repDelta = repChange;
        outcome.cashDelta = cashChange;
        outcome.drugDelta = drugChange;

        dealersExeCore.applyGameOutcome(tokenId, outcome);

        uint8 newHeatLevel = dealersExeCore.getEffectiveHeat(tokenId);

        emit GamePlayed(
            tokenId,
            msg.sender,
            choice,
            houseChoice,
            gameOutcome,
            hustleType,
            drugId,
            amount,
            cashChange,
            repChange,
            drugChange,
            newHeatLevel
        );
    }

    // =============================================================
    //                   INTERNAL/PRIVATE HELPER FUNCTIONS
    // =============================================================

    function _calculateBiasedHouseChoice(uint8 roll, uint8 playerChoice) internal view returns (uint8 houseChoice, uint8 outcome) {
        if (roll < tieChance) {
            houseChoice = playerChoice;
            outcome = 1; // TIE
        } else if (roll < tieChance + winChance) {
            houseChoice = (playerChoice + 1) % 3;
            outcome = 0; // WIN
        } else {
            houseChoice = (playerChoice + 2) % 3;
            outcome = 2; // LOSS
        }
    }

    function _computeBuyOutcome(
        IDealersExeCore.GameState memory state,
        uint8 outcome,
        uint256 amount,
        uint256 buyPrice
    ) private view returns (int256 repChange, int256 cashChange, int256 drugChange) {
        uint256 cashCost = amount * buyPrice;

        repChange = _calculateScaledRep(state, outcome, cashCost);

        if (outcome == 0) {
            // WIN: Keep $CASH + Get drugs
            uint256 boostedAmount = (amount * uint256(state.drugMultiplier)) / 100;
            drugChange = int256(boostedAmount);
            cashChange = 0;
        } else if (outcome == 1) {
            // TIE: Lose $CASH + Get drugs
            cashChange = -int256(cashCost);
            uint256 boostedAmount = (amount * uint256(state.drugMultiplier)) / 100;
            drugChange = int256(boostedAmount);
        } else {
            // LOSE: Lose $CASH + No drugs
            cashChange = -int256(cashCost);
            drugChange = 0;
        }
    }

    function _computeSellOutcome(
        IDealersExeCore.GameState memory state,
        uint8 outcome,
        uint256 amount,
        uint256 sellPrice
    ) private view returns (int256 repChange, int256 cashChange, int256 drugChange) {
        uint256 cashReward = amount * sellPrice;

        repChange = _calculateScaledRep(state, outcome, cashReward);

        if (outcome == 0) {
            // WIN: Keep drugs + Get $CASH
            uint256 boostedCash = (cashReward * uint256(state.cashMultiplier)) / 100;
            cashChange = int256(boostedCash);
            drugChange = 0;
        } else if (outcome == 1) {
            // TIE: Lose drugs + Get $CASH
            uint256 boostedCash = (cashReward * uint256(state.cashMultiplier)) / 100;
            drugChange = -int256(amount);
            cashChange = int256(boostedCash);
        } else {
            // LOSE: Lose drugs + No $CASH
            drugChange = -int256(amount);
            cashChange = 0;
        }
    }

    function _calculateScaledRep(
        IDealersExeCore.GameState memory state,
        uint8 outcome,
        uint256 stakeValue
    ) private view returns (int256) {
        int16 baseRep;
        if (outcome == 0) baseRep = state.repWinBonus;
        else if (outcome == 1) baseRep = state.repTieBonus;
        else baseRep = state.repLossPenalty;

        int256 scaled = (int256(baseRep) * int256(stakeValue)) / int256(repStakeDivisor);

        if (outcome <= 1) {
            scaled = (scaled * int256(uint256(state.repMultiplier))) / 100;
        }

        int16 repCap = state.repCap;
        if (scaled > int256(repCap)) return int256(repCap);
        if (scaled < -int256(repCap)) return -int256(repCap);
        return scaled;
    }

    function _getDrugPricing(uint8 areaId, uint256 drugId)
        private
        view
        returns (uint256 buyPrice, uint256 sellPrice, bool found)
    {
        if (!areaRegistry.isDrugAvailableInArea(areaId, drugId)) {
            return (0, 0, false);
        }

        (buyPrice, sellPrice) = areaRegistry.getDrugPricing(areaId, drugId);
        return (buyPrice, sellPrice, true);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get a dealer's PVE win/loss/tie record and choice history
     * @param tokenId The dealer NFT token ID
     * @return PVE statistics for the dealer
     */
    function getDealerPveStats(uint256 tokenId) external view returns (PveStats memory) {
        return dealerPveStats[tokenId];
    }

    /**
     * @notice Check whether a dealer can play a hustle round
     * @param tokenId The dealer NFT token ID
     * @return isPlayable True if the dealer can play
     * @return reason 0 = playable, 1 = not initialized, 2 = jailed, 3 = safe house, 4 = no attempts
     */
    function canPlay(uint256 tokenId) external view returns (bool isPlayable, uint8 reason) {
        IDealersExeCore.GameState memory state = dealersExeCore.getGameState(tokenId);
        if (!state.isInitialized) return (false, 1);
        if (state.isJailed) return (false, 2);
        if (state.isInSafeHouse) return (false, 3);
        if (state.dailyAttemptsRemaining == 0) return (false, 4);
        return (true, 0);
    }

    /**
     * @notice Preview reputation and cash outcomes for a potential hustle
     * @param tokenId The dealer NFT token ID
     * @param drugId The drug to preview
     * @param amount Quantity to preview
     * @return winRep Reputation gained on win
     * @return tieRep Reputation gained on tie
     * @return lossRep Reputation lost on loss (negative)
     * @return cashValueOnSell Cash earned if selling this amount
     * @return cashCostOnBuy Cash spent if buying this amount
     */
    function previewHustle(uint256 tokenId, uint256 drugId, uint256 amount) external view returns (
        int16 winRep,
        int16 tieRep,
        int16 lossRep,
        uint256 cashValueOnSell,
        uint256 cashCostOnBuy
    ) {
        IDealersExeCore.GameState memory state = dealersExeCore.getGameState(tokenId);

        winRep = state.repWinBonus;
        tieRep = state.repTieBonus;
        lossRep = state.repLossPenalty;

        (uint256 buyPrice, uint256 sellPrice, bool found) = _getDrugPricing(state.currentArea, drugId);

        if (found) {
            cashValueOnSell = amount * sellPrice;
            cashCostOnBuy = amount * buyPrice;
        }
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Set the core state contract
     * @param _dealersExeCore Address of the DealersExeCore contract
     */
    function setDealersExeCore(address _dealersExeCore) external onlyOwner {
        if (_dealersExeCore == address(0)) revert InvalidAddress();
        address old = address(dealersExeCore);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        emit CoreContractUpdated(old, _dealersExeCore);
    }

    /**
     * @notice Set the NFT contract used for ownership checks
     * @param _dealersExeNFT Address of the DealersExeNFT contract
     */
    function setDealersExeNFT(address _dealersExeNFT) external onlyOwner {
        if (_dealersExeNFT == address(0)) revert InvalidAddress();
        address old = address(dealersExeNFT);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        emit NFTContractUpdated(old, _dealersExeNFT);
    }

    /**
     * @notice Set the area registry contract
     * @param _areaRegistry Address of the DEAreaRegistry contract
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert InvalidAddress();
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    /**
     * @notice Set the randomness provider contract
     * @param _randomness Address of the DERandomness contract
     */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert InvalidAddress();
        address old = address(randomness);
        randomness = IDERandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }

    /**
     * @notice Update the tie/win/loss probability distribution
     * @param _tieChance Percentage chance of a tie (loss chance = 100 - tie - win)
     * @param _winChance Percentage chance of a player win
     */
    function setOutcomeOdds(uint8 _tieChance, uint8 _winChance) external onlyOwner {
        if (_tieChance + _winChance > 100) revert InvalidOdds();
        tieChance = _tieChance;
        winChance = _winChance;
        emit OutcomeOddsUpdated(_tieChance, _winChance);
    }

    /**
     * @notice Set the divisor that scales reputation gains relative to stake value
     * @param _divisor New divisor (higher = less rep per unit staked)
     */
    function setRepStakeDivisor(uint256 _divisor) external onlyOwner {
        if (_divisor == 0) revert InvalidDivisor();
        uint256 old = repStakeDivisor;
        repStakeDivisor = _divisor;
        emit RepStakeDivisorUpdated(old, _divisor);
    }

    /** @notice Pause all PVE gameplay */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /** @notice Unpause PVE gameplay */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
