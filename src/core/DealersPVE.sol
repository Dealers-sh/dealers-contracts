// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IDealersPVE} from "./IDealersPVE.sol";
import "./IDealersCore.sol";
import "../utils/IAreaRegistry.sol";
import "../utils/IERC721Minimal.sol";
import "../utils/IDealersRandomness.sol";
import {IActionsArrest} from "../utils/IActionsArrest.sol";

/**
 * @title DealersPVE - Player vs Environment Game Module
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Rock-paper-scissors style hustle game where dealers buy or sell drugs.
 *      Outcomes (win/tie/loss) are determined by biased house odds, with jail
 *      checks on every play. Reputation scales with stake value.
 * @author Berny0x
 */
contract DealersPVE is IDealersPVE, ReentrancyGuard, Ownable {
    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersCore public dealersCore;
    IERC721Minimal public dealersNFT;
    IAreaRegistry public areaRegistry;
    IDealersRandomness public randomness;
    IActionsArrest public actions;

    uint8 public tieChance = 50;
    uint8 public winChance = 20;

    uint256 public repStakeDivisor = 50;

    bool public paused;

    mapping(uint256 => PveStats) public dealerPveStats;

    struct PveRound {
        uint256 tokenId;
        address player;
        uint8 choice;
        HustleType hustleType;
        uint256 drugId;
        uint256 amount;
        uint256 buyPrice;
        uint256 sellPrice;
        uint8 areaAtCommit;
    }

    mapping(uint64 => PveRound) public pendingRounds;
    mapping(uint256 => uint64) public activePveRoundOf;

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
        uint8 newHeatLevel,
        uint256 stakedCash,
        uint256 stakedDrug
    );

    event DealerArrested(
        uint256 indexed tokenId,
        address indexed player,
        uint16 jailChance
    );

    event GameCommitted(
        uint64 indexed seq,
        uint256 indexed tokenId,
        address indexed player,
        uint8 choice,
        HustleType hustleType,
        uint256 drugId,
        uint256 amount,
        uint256 price,
        int256 cashDelta,
        int256 drugDelta
    );
    event GameExpired(uint64 indexed seq, uint256 indexed tokenId);

    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event AreaRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event RandomnessUpdated(address indexed oldRandomness, address indexed newRandomness);
    event ActionsUpdated(address indexed oldActions, address indexed newActions);

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
    error RoundPending();
    error UnknownRound();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor(address _dealersCore, address _dealersNFT, address _areaRegistry) {
        _initializeOwner(msg.sender);
        dealersCore = IDealersCore(_dealersCore);
        dealersNFT = IERC721Minimal(_dealersNFT);
        areaRegistry = IAreaRegistry(_areaRegistry);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(dealersCore) == address(0) ||
            address(dealersNFT) == address(0) ||
            address(areaRegistry) == address(0) ||
            address(randomness) == address(0) ||
            address(actions) == address(0)
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
        if (dealersNFT.ownerOf(tokenId) != msg.sender) revert NotDealerOwner();
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
     * @notice Commit to a hustle round — debits stake + attempt; outcome resolved later.
     * @param tokenId The dealer NFT token ID
     * @param choice Player's move: 0 = DEAL, 1 = THREATEN, 2 = BAIL
     * @param hustleType Whether the dealer is buying or selling drugs
     * @param drugId The drug being traded
     * @param amount Quantity of drugs to stake
     * @return seq Sequence number to pass to resolveGame
     */
    function commitGame(
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
        returns (uint64 seq)
    {
        if (activePveRoundOf[tokenId] != 0) revert RoundPending();

        IDealersCore.GameState memory state = dealersCore.getGameState(tokenId);

        if (!state.isInitialized) revert DealerNotInitialized();
        if (state.isJailed) revert DealerInJail();
        if (state.isInSafeHouse) revert DealerInSafeHouse();
        if (areaRegistry.isBlackMarket(state.currentArea)) revert DealerInBlackMarket();
        if (state.dailyAttemptsRemaining == 0) revert NoAttemptsRemaining();
        if (amount == 0) revert InvalidAmount();

        (uint256 buyPrice, uint256 sellPrice, bool found) = _getDrugPricing(state.currentArea, drugId);
        if (!found) revert DrugNotAvailableInArea();

        IDealersCore.GameOutcome memory commitOutcome;
        commitOutcome.useAttempt = true;
        commitOutcome.drugId = drugId;

        if (hustleType == HustleType.BUY) {
            uint256 stakeValue = amount * buyPrice;
            if (state.cashBalance < stakeValue) revert InsufficientCash();
            commitOutcome.cashDelta = -int256(stakeValue);
        } else {
            if (dealersCore.getDrugBalance(tokenId, drugId) < amount) revert InsufficientDrugs();
            commitOutcome.drugDelta = -int256(amount);
        }

        dealersCore.applyGameOutcome(tokenId, commitOutcome);

        seq = randomness.commit();
        pendingRounds[seq] = PveRound({
            tokenId: tokenId,
            player: msg.sender,
            choice: choice,
            hustleType: hustleType,
            drugId: drugId,
            amount: amount,
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            areaAtCommit: state.currentArea
        });
        activePveRoundOf[tokenId] = seq;

        emit GameCommitted(
            seq,
            tokenId,
            msg.sender,
            choice,
            hustleType,
            drugId,
            amount,
            hustleType == HustleType.BUY ? buyPrice : sellPrice,
            commitOutcome.cashDelta,
            commitOutcome.drugDelta
        );
    }

    /**
     * @notice Resolve a previously committed round. Anyone may call.
     * @dev Expiry is settled as a LOSS — closes the simulate-then-skip refund loophole.
     */
    function resolveGame(uint64 seq) external nonReentrant {
        PveRound memory r = pendingRounds[seq];
        if (r.tokenId == 0) revert UnknownRound();

        delete pendingRounds[seq];
        delete activePveRoundOf[r.tokenId];

        if (randomness.isExpired(seq)) {
            _applyExpiryAsLoss(r);
            emit GameExpired(seq, r.tokenId);
            return;
        }

        uint256 rand = randomness.reveal(seq);
        uint256 arrestRng = rand & 0xFFFF;
        uint256 outcomeRng = (rand >> 16) & 0xFFFF;
        uint256 confiscRng = (rand >> 64) & 0xFFFF;

        if (dealersCore.rollJailCheck(r.tokenId, arrestRng)) {
            uint16 jailChanceAtResolve = dealersCore.getGameState(r.tokenId).jailChance;
            actions.arrest(r.tokenId, confiscRng);
            emit DealerArrested(r.tokenId, r.player, jailChanceAtResolve);
            return;
        }

        IDealersCore.GameState memory live = dealersCore.getGameState(r.tokenId);
        uint8 roll = uint8(outcomeRng % 100);
        (uint8 houseChoice, uint8 gameOutcome) = _calculateBiasedHouseChoice(roll, r.choice);

        unchecked {
            PveStats storage stats = dealerPveStats[r.tokenId];
            if (gameOutcome == 0) stats.wins++;
            else if (gameOutcome == 1) stats.ties++;
            else stats.losses++;
            if (r.choice == 0) stats.dealChoices++;
            else if (r.choice == 1) stats.threatenChoices++;
            else stats.bailChoices++;
        }

        int256 repChange;
        int256 cashChange;
        int256 drugChange;

        if (r.hustleType == HustleType.BUY) {
            (repChange, cashChange, drugChange) = _computeBuyOutcome(live, gameOutcome, r.amount, r.buyPrice);
            // Stake was debited at commit. On WIN we keep cash (refund stake);
            // on TIE/LOSS the stake stays gone, so the post-commit cash debit becomes 0.
            if (gameOutcome == 0) {
                cashChange = int256(r.amount * r.buyPrice);
            } else {
                cashChange = 0;
            }
        } else {
            (repChange, cashChange, drugChange) = _computeSellOutcome(live, gameOutcome, r.amount, r.sellPrice);
            // Drugs were debited at commit. On LOSS, drugs stay gone; on WIN we keep drugs (refund).
            // _computeSellOutcome returns drugChange = 0 (WIN) or -amount (TIE/LOSS).
            if (drugChange == 0) {
                drugChange = int256(r.amount);
            } else {
                drugChange = 0;
            }
        }

        IDealersCore.GameOutcome memory outcome;
        outcome.incrementHeat = true;
        outcome.drugId = r.drugId;
        outcome.repDelta = repChange;
        outcome.cashDelta = cashChange;
        outcome.drugDelta = drugChange;

        dealersCore.applyGameOutcome(r.tokenId, outcome);

        uint8 newHeatLevel = dealersCore.getEffectiveHeat(r.tokenId);

        emit GamePlayed(
            r.tokenId,
            r.player,
            r.choice,
            houseChoice,
            gameOutcome,
            r.hustleType,
            r.drugId,
            r.amount,
            cashChange,
            repChange,
            drugChange,
            newHeatLevel,
            r.hustleType == HustleType.BUY ? r.amount * r.buyPrice : 0,
            r.hustleType == HustleType.BUY ? 0 : r.amount
        );
    }

    // =============================================================
    //                   INTERNAL/PRIVATE HELPER FUNCTIONS
    // =============================================================

    function _applyExpiryAsLoss(PveRound memory r) private {
        IDealersCore.GameState memory live = dealersCore.getGameState(r.tokenId);

        uint256 stakeValue = r.hustleType == HustleType.BUY
            ? r.amount * r.buyPrice
            : r.amount * r.sellPrice;

        int256 repChange = _calculateScaledRep(live, 2, stakeValue);

        unchecked {
            PveStats storage stats = dealerPveStats[r.tokenId];
            stats.losses++;
            if (r.choice == 0) stats.dealChoices++;
            else if (r.choice == 1) stats.threatenChoices++;
            else stats.bailChoices++;
        }

        IDealersCore.GameOutcome memory outcome;
        outcome.incrementHeat = true;
        outcome.drugId = r.drugId;
        outcome.repDelta = repChange;

        dealersCore.applyGameOutcome(r.tokenId, outcome);
    }

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
        IDealersCore.GameState memory state,
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
        IDealersCore.GameState memory state,
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
        IDealersCore.GameState memory state,
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
        IDealersCore.GameState memory state = dealersCore.getGameState(tokenId);
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
        IDealersCore.GameState memory state = dealersCore.getGameState(tokenId);

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
     * @param _dealersCore Address of the DealersCore contract
     */
    function setDealersCore(address _dealersCore) external onlyOwner {
        if (_dealersCore == address(0)) revert InvalidAddress();
        address old = address(dealersCore);
        dealersCore = IDealersCore(_dealersCore);
        emit CoreContractUpdated(old, _dealersCore);
    }

    /**
     * @notice Set the NFT contract used for ownership checks
     * @param _dealersNFT Address of the DealersNFT contract
     */
    function setDealersNFT(address _dealersNFT) external onlyOwner {
        if (_dealersNFT == address(0)) revert InvalidAddress();
        address old = address(dealersNFT);
        dealersNFT = IERC721Minimal(_dealersNFT);
        emit NFTContractUpdated(old, _dealersNFT);
    }

    /**
     * @notice Set the area registry contract
     * @param _areaRegistry Address of the DealersAreaRegistry contract
     */
    function setAreaRegistry(address _areaRegistry) external onlyOwner {
        if (_areaRegistry == address(0)) revert InvalidAddress();
        address old = address(areaRegistry);
        areaRegistry = IAreaRegistry(_areaRegistry);
        emit AreaRegistryUpdated(old, _areaRegistry);
    }

    /**
     * @notice Set the randomness provider contract
     * @param _randomness Address of the DealersRandomness contract
     */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert InvalidAddress();
        address old = address(randomness);
        randomness = IDealersRandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }

    /**
     * @notice Set the DealersActions contract used to delegate arrest policy
     * @param _actions Address of the DealersActions contract
     */
    function setActions(address _actions) external onlyOwner {
        if (_actions == address(0)) revert InvalidAddress();
        address old = address(actions);
        actions = IActionsArrest(_actions);
        emit ActionsUpdated(old, _actions);
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
