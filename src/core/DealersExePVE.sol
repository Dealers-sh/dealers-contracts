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
 * @title DealersExePVE - Simplified Player vs Environment Game Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Handles PVE gameplay with jail/heat mechanics and boost multipliers
 *      Uses AreaRegistry for drug pricing per area
 * @author Dealers.Exe Team
 */
contract DealersExePVE is IDealersExePVE, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersExeCore public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    IAreaRegistry public areaRegistry;
    IDERandomness public randomness;

    // Configurable outcome odds (tie + win <= 100, loss is derived)
    uint8 public tieChance = 50;    // Default 50%
    uint8 public winChance = 20;    // Default 20%

    // Stake-scaled reputation: stakeValue / divisor = scaling factor (50 = $50 for full base rep)
    uint256 public repStakeDivisor = 50;

    // Pause state
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

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
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
        whenNotPaused
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
        bytes32 seed = keccak256(abi.encodePacked(tokenId, msg.sender, block.timestamp));
        uint256 gameRandomness = randomness.getRandomness(seed);
        if (gameRandomness == 0) revert RandomnessError();

        // 8. Check jail - if arrested, lose stake
        if (_checkAndProcessArrest(tokenId, gameRandomness, hustleType, drugId, amount, stakeValue)) {
            return;
        }

        // 9. Process game outcome
        _processHustleGame(tokenId, choice, hustleType, drugId, amount, buyPrice, sellPrice, gameRandomness);
    }

    /**
     * @notice Checks if dealer gets arrested and processes stake loss if so
     * @param tokenId The dealer token ID
     * @param rng Random number for jail roll
     * @param hustleType Whether buying or selling
     * @param drugId The drug being traded
     * @param amount The amount of drugs/cash at stake
     * @param stakeValue The cash value of the stake
     * @return True if arrested, false otherwise
     */
    function _checkAndProcessArrest(
        uint256 tokenId,
        uint256 rng,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount,
        uint256 stakeValue
    ) private returns (bool) {
        uint16 jailChance = dealersExeCore.getJailChance(tokenId);
        uint16 jailRoll = uint16(rng % 1000);

        if (jailRoll < jailChance) {
            // Arrested! Lose stake
            if (hustleType == HustleType.BUY) {
                dealersExeCore.spendCash(tokenId, stakeValue);
            } else {
                dealersExeCore.updateDrugBalance(tokenId, drugId, -int256(amount));
            }

            dealersExeCore.sendToJail(tokenId);

            emit DealerArrested(tokenId, msg.sender, jailChance);
            return true;
        }
        return false;
    }

    /**
     * @notice Processes the hustle game outcome after avoiding arrest
     * @param tokenId The dealer token ID
     * @param choice The player's game choice
     * @param hustleType Whether buying or selling
     * @param drugId The drug being traded
     * @param amount The amount of drugs being traded
     * @param buyPrice The buy price per unit
     * @param sellPrice The sell price per unit
     * @param rng Random number for outcome determination
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
        uint8 roll = uint8(gameRng % 100);
        (uint8 houseChoice, uint8 outcome) = _calculateBiasedHouseChoice(roll, choice);

        unchecked {
            PveStats storage stats = dealerPveStats[tokenId];
            if (outcome == 0) stats.wins++;
            else if (outcome == 1) stats.ties++;
            else stats.losses++;
            if (choice == 0) stats.dealChoices++;
            else if (choice == 1) stats.threatenChoices++;
            else stats.bailChoices++;
        }

        int256 repChange;
        int256 cashChange;
        int256 drugChange;

        if (hustleType == HustleType.BUY) {
            (repChange, cashChange, drugChange) = _processBuyOutcome(
                tokenId, outcome, drugId, amount, buyPrice
            );
        } else {
            (repChange, cashChange, drugChange) = _processSellOutcome(
                tokenId, outcome, drugId, amount, sellPrice
            );
        }

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
            repChange,
            drugChange,
            dealersExeCore.getHeatLevel(tokenId)
        );
    }

    // =============================================================
    //                   INTERNAL/PRIVATE HELPER FUNCTIONS
    // =============================================================

    /**
     * @notice Calculates biased house choice based on player choice and configurable odds
     * @dev RPS rules: DEAL(0) beats THREATEN(1), THREATEN(1) beats BAIL(2), BAIL(2) beats DEAL(0)
     * @param roll Random number 0-99
     * @param playerChoice The player's choice (0=DEAL, 1=THREATEN, 2=BAIL)
     * @return houseChoice The house's biased choice
     * @return outcome The game outcome (0=WIN, 1=TIE, 2=LOSS)
     */
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

    /**
     * @notice Processes BUY hustle outcome
     * @dev WIN: Keep $CASH + Get drugs + Big rep
     *      TIE: Lose $CASH + Get drugs + Small rep
     *      LOSE: Lose $CASH + No drugs + Lose rep
     * @param tokenId The dealer token ID
     * @param outcome The game outcome (0=WIN, 1=TIE, 2=LOSS)
     * @param drugId The drug being purchased
     * @param amount The amount of drugs to buy
     * @param buyPrice The buy price per unit
     * @return repChange The reputation change applied
     * @return cashChange The cash change applied
     * @return drugChange The drug balance change applied
     */
    function _processBuyOutcome(
        uint256 tokenId,
        uint8 outcome,
        uint256 drugId,
        uint256 amount,
        uint256 buyPrice
    ) private returns (int256 repChange, int256 cashChange, int256 drugChange) {
        uint256 cashCost = amount * buyPrice;

        repChange = _calculateScaledRep(tokenId, outcome, cashCost);

        if (outcome == 0) {
            // WIN: Keep $CASH + Get drugs + Big rep
            uint8 drugMultiplier = dealersExeCore.getDrugMultiplier(tokenId);
            uint256 boostedAmount = (amount * uint256(drugMultiplier)) / 100;

            dealersExeCore.updateDrugBalance(tokenId, drugId, int256(boostedAmount));
            drugChange = int256(boostedAmount);
            cashChange = 0;

        } else if (outcome == 1) {
            // TIE: Lose $CASH + Get drugs + Small rep
            dealersExeCore.spendCash(tokenId, cashCost);
            cashChange = -int256(cashCost);

            uint8 drugMultiplier = dealersExeCore.getDrugMultiplier(tokenId);
            uint256 boostedAmount = (amount * uint256(drugMultiplier)) / 100;

            dealersExeCore.updateDrugBalance(tokenId, drugId, int256(boostedAmount));
            drugChange = int256(boostedAmount);

        } else {
            // LOSE: Lose $CASH + No drugs + Lose rep
            dealersExeCore.spendCash(tokenId, cashCost);
            cashChange = -int256(cashCost);
            drugChange = 0;
        }

        dealersExeCore.updateReputation(tokenId, repChange);
    }

    function _processSellOutcome(
        uint256 tokenId,
        uint8 outcome,
        uint256 drugId,
        uint256 amount,
        uint256 sellPrice
    ) private returns (int256 repChange, int256 cashChange, int256 drugChange) {
        uint256 cashReward = amount * sellPrice;

        repChange = _calculateScaledRep(tokenId, outcome, cashReward);

        if (outcome == 0) {
            // WIN: Keep drugs + Get $CASH + Big rep
            uint8 cashMultiplier = dealersExeCore.getCashMultiplier(tokenId);
            uint256 boostedCash = (cashReward * uint256(cashMultiplier)) / 100;

            dealersExeCore.addCash(tokenId, boostedCash);
            cashChange = int256(boostedCash);
            drugChange = 0;

        } else if (outcome == 1) {
            // TIE: Lose drugs + Get $CASH + Small rep
            uint8 cashMultiplier = dealersExeCore.getCashMultiplier(tokenId);
            uint256 boostedCash = (cashReward * uint256(cashMultiplier)) / 100;

            dealersExeCore.updateDrugBalance(tokenId, drugId, -int256(amount));
            drugChange = -int256(amount);

            dealersExeCore.addCash(tokenId, boostedCash);
            cashChange = int256(boostedCash);

        } else {
            // LOSE: Lose drugs + No $CASH + Lose rep
            dealersExeCore.updateDrugBalance(tokenId, drugId, -int256(amount));
            drugChange = -int256(amount);
            cashChange = 0;
        }

        dealersExeCore.updateReputation(tokenId, repChange);
    }

    /**
     * @notice Scales rep by stake value, applies boost multiplier, and caps at tier repCap
     * @dev Formula: min(baseRep * stakeValue / divisor * boostMult / 100, repCap)
     *      Losses are also scaled (capped at -repCap)
     */
    function _calculateScaledRep(
        uint256 tokenId,
        uint8 outcome,
        uint256 stakeValue
    ) private view returns (int256) {
        int16 baseRep = dealersExeCore.getReputationChange(tokenId, outcome);
        int16 repCap = dealersExeCore.getRepCap(tokenId);

        int256 scaled = (int256(baseRep) * int256(stakeValue)) / int256(repStakeDivisor);

        // Apply boost multiplier for wins and ties
        if (outcome <= 1) {
            uint8 repMultiplier = dealersExeCore.getRepMultiplier(tokenId);
            scaled = (scaled * int256(uint256(repMultiplier))) / 100;
        }

        // Cap gains and losses
        if (scaled > int256(repCap)) return int256(repCap);
        if (scaled < -int256(repCap)) return -int256(repCap);
        return scaled;
    }

    /**
     * @notice Gets drug pricing for an area from AreaRegistry
     * @param areaId The area to check pricing for
     * @param drugId The drug ID to get pricing for
     * @return buyPrice The buy price per unit
     * @return sellPrice The sell price per unit
     * @return found Whether the drug is available in this area
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

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Check if a dealer can play a game
     */
    function getDealerPveStats(uint256 tokenId) external view returns (PveStats memory) {
        return dealerPveStats[tokenId];
    }

    function canPlay(uint256 tokenId) external view returns (bool isPlayable, uint8 reason) {
        (, , uint8 attemptsRemaining, , , bool isInitialized) = dealersExeCore.getDealerData(tokenId);
        if (!isInitialized) return (false, 1);
        if (dealersExeCore.isInJail(tokenId)) return (false, 2);
        if (dealersExeCore.isInSafeHouse(tokenId)) return (false, 3);
        if (attemptsRemaining == 0) return (false, 4);
        return (true, 0);
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
        if (_dealersExeCore == address(0)) revert InvalidAddress();
        address old = address(dealersExeCore);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        emit CoreContractUpdated(old, _dealersExeCore);
    }

    /**
     * @notice Updates the NFT contract address
     */
    function setDealersExeNFT(address _dealersExeNFT) external onlyOwner {
        if (_dealersExeNFT == address(0)) revert InvalidAddress();
        address old = address(dealersExeNFT);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        emit NFTContractUpdated(old, _dealersExeNFT);
    }

    /**
     * @notice Updates the Area Registry address
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert InvalidAddress();
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    /**
     * @notice Updates the Randomness contract address
     */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert InvalidAddress();
        address old = address(randomness);
        randomness = IDERandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }

    /**
     * @notice Sets the outcome odds for the biased house choice system
     * @param _tieChance Percentage chance for a tie (0-100)
     * @param _winChance Percentage chance for player win (0-100)
     */
    function setOutcomeOdds(uint8 _tieChance, uint8 _winChance) external onlyOwner {
        if (_tieChance + _winChance > 100) revert InvalidOdds();
        tieChance = _tieChance;
        winChance = _winChance;
        emit OutcomeOddsUpdated(_tieChance, _winChance);
    }

    function setRepStakeDivisor(uint256 _divisor) external onlyOwner {
        if (_divisor == 0) revert InvalidDivisor();
        uint256 old = repStakeDivisor;
        repStakeDivisor = _divisor;
        emit RepStakeDivisorUpdated(old, _divisor);
    }

    /**
     * @notice Pauses the contract
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
