// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import "./IDealersExeCore.sol";

interface IRandomProvider {
    function requestRandomness(bytes32 gameId) external returns (bytes32 requestId);
}

interface IPaymentHandler {
    function processStakedBet(uint256 amount) external payable;
    function processGamePayout(address player, uint8 outcome, uint256 stakeAmount) external;
}

contract DealersExePVE is ReentrancyGuard, Ownable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant MIN_STAKE = 0.001 ether;
    uint256 public constant MAX_STAKE = 0.01 ether;
    uint256 public constant GAME_TIMEOUT = 300; // 5 minutes

    // Drop rates (out of 100)
    uint8 public constant COMMON_DROP_RATE = 75;
    uint8 public constant UNCOMMON_DROP_RATE = 20;
    uint8 public constant RARE_DROP_RATE = 5;

    // Game choices
    enum GameChoice { DEAL, THREATEN, BAIL }   // 0,1,2
    enum GameOutcome { WIN, TIE, LOSS }        // 0,1,2

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /// Flags layout (uint8):
    /// bit0: isStaked, bit1: isResolved, bit2: paymentProcessed
    struct GameData {
        // slot 0
        uint128 tokenId;
        uint128 stakeAmount;
        // slot 1
        uint128 drugIdUsed;
        uint128 drugAmountUsed;
        // slot 2
        address player;       // 20 bytes
        uint40 timestamp;     // enough for centuries
        uint8 playerChoice;   // 0..2
        uint8 areaId;         // 0..255
        uint8 flags;          // bit flags
    }

    // =============================================================
    //                            STORAGE
    // =============================================================

    IDealersExeCore public dealersExeCore;
    IRandomProvider public randomProvider;
    IPaymentHandler public paymentHandler;

    mapping(bytes32 => GameData) public pendingGames;       // VRF request ID => game data
    mapping(address => bytes32[]) public playerActiveGames; // active games per player

    mapping(uint256 => uint256) public playerGamesPlayed;   // tokenId => total games
    mapping(uint256 => uint256) public playerGamesWon;      // tokenId => games won
    uint256 public totalGamesPlayed;
    uint256 public totalGamesWon;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event GameStarted(
        bytes32 indexed requestId,
        uint256 indexed tokenId,
        address indexed player,
        uint8 choice,
        bool isStaked,
        uint256 stakeAmount
    );

    event GameResolved(
        bytes32 indexed requestId,
        uint256 indexed tokenId,
        address indexed player,
        uint8 outcome,
        uint8 playerChoice,
        uint8 houseChoice,
        int16 reputationChange,
        uint256 drugReward,
        uint256 drugAmount
    );

    event GameTimeout(bytes32 indexed requestId, uint256 indexed tokenId);
    event GameRefunded(bytes32 indexed requestId, address indexed player, uint256 amount);
    event RandomProviderUpdated(address indexed oldProvider, address indexed newProvider);
    event PaymentHandlerUpdated(address indexed oldHandler, address indexed newHandler);
    event CoreContractUpdated(address indexed oldCore, address indexed newCore);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error InvalidStakeAmount();
    error InvalidGameChoice();
    error InvalidDrugAmount();
    error NoFreePlaysRemaining();
    error InsufficientDrugBalance();
    error DrugNotFromCurrentArea();
    error GameAlreadyResolved();
    error GameNotFound();
    error UnauthorizedResolver();
    error DealerNotInitialized();
    error GameTimedOut();
    error PaymentAlreadyProcessed();
    error TransferFailed();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the DealersExePVE contract with required dependencies
     * @param _dealersExeCore Address of the core dealers contract that manages NFT data
     * @param _randomProvider Address of the random number provider for game resolution
     * @param _paymentHandler Address of the payment handler for processing stakes and payouts
     */
    constructor(address _dealersExeCore, address _randomProvider, address _paymentHandler) {
        _initializeOwner(msg.sender);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        randomProvider = IRandomProvider(_randomProvider);
        paymentHandler = IPaymentHandler(_paymentHandler);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(dealersExeCore) == address(0) ||
            address(randomProvider) == address(0) ||
            address(paymentHandler) == address(0)
        ) revert ContractNotSet();
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
        (bool success,) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // =============================================================
    //                        PVE GAME FUNCTIONS
    // =============================================================

    /**
     * @notice Starts a staked PvE game where the player risks ETH for potential rewards
     * @param tokenId The ID of the dealer NFT to use for the game
     * @param choice The player's choice: 0=DEAL, 1=THREATEN, 2=BAIL
     * @return requestId The VRF request ID for tracking the game resolution
     */
    function playPvEStaked(uint256 tokenId, uint8 choice)
        external
        payable
        nonReentrant
        contractsSet
        dealerExists(tokenId)
        validChoice(choice)
        returns (bytes32 requestId)
    {
        uint256 v = msg.value;
        if (v < MIN_STAKE || v > MAX_STAKE) revert InvalidStakeAmount();

        (uint8 currentArea,, , , ,) = dealersExeCore.getDealerData(tokenId);

        // gameId: packed, no string literals
        bytes32 gameId = keccak256(abi.encodePacked(block.timestamp, msg.sender, tokenId, choice, uint8(1)));

        requestId = randomProvider.requestRandomness(gameId);

        pendingGames[requestId] = GameData({
            tokenId: uint128(tokenId),
            stakeAmount: uint128(v),
            drugIdUsed: 0,
            drugAmountUsed: 0,
            player: msg.sender,
            timestamp: uint40(block.timestamp),
            playerChoice: choice,
            areaId: currentArea,
            flags: _packFlags(true, false, false) // staked, not resolved, payment not processed
        });

        playerActiveGames[msg.sender].push(requestId);

        emit GameStarted(requestId, tokenId, msg.sender, choice, true, v);
    }

    /**
     * @notice Starts a free PvE game using drugs as ante instead of ETH
     * @param tokenId The ID of the dealer NFT to use for the game
     * @param choice The player's choice: 0=DEAL, 1=THREATEN, 2=BAIL
     * @param drugId The ID of the drug to use as ante (must be from current area)
     * @param drugAmount The amount of drugs to risk in the game
     * @return requestId The VRF request ID for tracking the game resolution
     */
    function playPvEFree(
        uint256 tokenId,
        uint8 choice,
        uint256 drugId,
        uint256 drugAmount
    )
        external
        nonReentrant
        contractsSet
        dealerExists(tokenId)
        validChoice(choice)
        returns (bytes32 requestId)
    {
        if (drugAmount == 0) revert InvalidDrugAmount();

        (uint8 currentArea,, , uint8 dailyPlays, ,) = dealersExeCore.getDealerData(tokenId);
        if (dailyPlays == 0) revert NoFreePlaysRemaining();

        if (dealersExeCore.getDrugBalance(tokenId, drugId) < drugAmount) revert InsufficientDrugBalance();

        IDealersExeCore.DrugInfo memory di = dealersExeCore.getDrugInfo(drugId);
        if (di.areaId != currentArea) revert DrugNotFromCurrentArea();

        bytes32 gameId = keccak256(
            abi.encodePacked(block.timestamp, msg.sender, tokenId, choice, drugId, drugAmount, uint8(0))
        );

        requestId = randomProvider.requestRandomness(gameId);

        pendingGames[requestId] = GameData({
            tokenId: uint128(tokenId),
            stakeAmount: 0,
            drugIdUsed: uint128(drugId),
            drugAmountUsed: uint128(drugAmount),
            player: msg.sender,
            timestamp: uint40(block.timestamp),
            playerChoice: choice,
            areaId: currentArea,
            flags: _packFlags(false, false, false) // free, not resolved, payment not processed
        });

        playerActiveGames[msg.sender].push(requestId);

        // Consume inputs immediately
        dealersExeCore.updateDrugBalance(tokenId, drugId, -int256(drugAmount));
        dealersExeCore.updateDailyPlays(tokenId, 1);

        emit GameStarted(requestId, tokenId, msg.sender, choice, false, 0);
    }

    /**
     * @notice Resolves a pending game using VRF randomness
     * @dev Only callable by the randomProvider contract
     * @param requestId The VRF request ID of the game to resolve
     * @param randomness The random number provided by VRF for game resolution
     */
    function resolveGame(bytes32 requestId, uint256 randomness) external {
        GameData storage g = pendingGames[requestId];

        if (g.timestamp == 0) revert GameNotFound();
        if (_isResolved(g)) revert GameAlreadyResolved();
        if (msg.sender != address(randomProvider)) revert UnauthorizedResolver();

        if (_timedOut(g)) {
            _handleGameTimeout(requestId);
            return;
        }

        uint8 houseChoice = uint8(randomness % 3);
        uint8 outcome = _calculateGameOutcome(g.playerChoice, houseChoice);

        if (_isStaked(g) && !_paymentProcessed(g)) {
            uint256 amt = uint256(g.stakeAmount);
            paymentHandler.processStakedBet{value: amt}(amt);
            paymentHandler.processGamePayout(g.player, outcome, amt);
            _setPaymentProcessed(g);
        }

        _processGameRewards(requestId, outcome, randomness, houseChoice);
        _updateStatistics(uint256(g.tokenId), outcome);
        _setResolved(g);
        _removeActiveGame(g.player, requestId);
    }

    // =============================================================
    //                        TIMEOUT HANDLING
    // =============================================================

    /**
     * @notice Handles cleanup and refunds for games that have timed out
     * @dev Refunds stakes for staked games and restores consumed resources for free games
     * @param requestId The VRF request ID of the timed-out game
     */
    function _handleGameTimeout(bytes32 requestId) internal {
        GameData storage g = pendingGames[requestId];

        if (_isStaked(g) && !_paymentProcessed(g) && g.stakeAmount > 0) {
            uint256 amt = uint256(g.stakeAmount);
            _safeTransferETH(g.player, amt);
            emit GameRefunded(requestId, g.player, amt);
        }

        if (!_isStaked(g) && g.drugAmountUsed > 0) {
            dealersExeCore.updateDrugBalance(uint256(g.tokenId), uint256(g.drugIdUsed), int256(uint256(g.drugAmountUsed)));
            // Refund daily play (core decides exact semantics)
            dealersExeCore.updateDailyPlays(uint256(g.tokenId), 0);
        }

        _setResolved(g);
        _removeActiveGame(g.player, requestId);
        emit GameTimeout(requestId, uint256(g.tokenId));
    }

    /**
     * @notice Cleans up multiple timed-out games in a single transaction
     * @dev Only callable by the contract owner for gas-efficient batch cleanup
     * @param requestIds Array of VRF request IDs to check and clean up if timed out
     */
    function cleanupTimedOutGames(bytes32[] calldata requestIds) external onlyOwner {
        uint256 len = requestIds.length;
        for (uint256 i; i < len; ) {
            GameData storage g = pendingGames[requestIds[i]];
            if (!_isResolved(g) && g.timestamp > 0 && _timedOut(g)) {
                _handleGameTimeout(requestIds[i]);
            }
            unchecked { ++i; }
        }
    }

    // =============================================================
    //                        INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Calculates the game outcome based on player and house choices
     * @dev Uses rock-paper-scissors logic: DEAL beats THREATEN, THREATEN beats BAIL, BAIL beats DEAL
     * @param playerChoice The player's choice (0=DEAL, 1=THREATEN, 2=BAIL)
     * @param houseChoice The house's choice (0=DEAL, 1=THREATEN, 2=BAIL)
     * @return outcome The game result (0=WIN, 1=TIE, 2=LOSS)
     */
    function _calculateGameOutcome(uint8 playerChoice, uint8 houseChoice) internal pure returns (uint8) {
        if (playerChoice == houseChoice) return 1; // TIE
        if ((playerChoice == 0 && houseChoice == 1) || (playerChoice == 1 && houseChoice == 2) || (playerChoice == 2 && houseChoice == 0)) {
            return 0; // WIN
        }
        return 2; // LOSS
    }

    /**
     * @notice Processes game rewards including reputation changes and drug drops
     * @dev Updates dealer reputation and grants drug rewards based on game outcome
     * @param requestId The VRF request ID of the resolved game
     * @param outcome The game outcome (0=WIN, 1=TIE, 2=LOSS)
     * @param randomness The VRF randomness used for reward generation
     * @param houseChoice The house's choice for event emission
     */
    function _processGameRewards(bytes32 requestId, uint8 outcome, uint256 randomness, uint8 houseChoice) internal {
        GameData memory g = pendingGames[requestId];

        int16 repChange = dealersExeCore.getReputationChange(uint256(g.tokenId), outcome);
        dealersExeCore.updateReputation(uint256(g.tokenId), repChange);

        uint256 drugReward;
        uint256 drugAmount;

        if (outcome <= 1) {
            (uint8 rarity, uint256 amount) = _generateDrugReward(randomness);
            if (amount > 0) {
                uint256[3] memory areaDrugs = dealersExeCore.getAreaDrugIds(g.areaId);
                uint256 drugId = areaDrugs[rarity];
                dealersExeCore.updateDrugBalance(uint256(g.tokenId), drugId, int256(amount));
                drugReward = rarity;
                drugAmount = amount;
            }
        }

        emit GameResolved(
            requestId,
            uint256(g.tokenId),
            g.player,
            outcome,
            g.playerChoice,
            houseChoice,
            repChange,
            drugReward,
            drugAmount
        );
    }

    /**
     * @notice Generates random drug rewards based on drop rates and outcome
     * @dev Only generates rewards for WIN or TIE outcomes with predefined drop rates
     * @param randomness The VRF randomness used for reward calculation
     * @return rarity The rarity tier of the dropped drug (0=COMMON, 1=UNCOMMON, 2=RARE)
     * @return amount The amount of drugs to reward
     */
    function _generateDrugReward(uint256 randomness)
        internal
        pure
        returns (uint8 rarity, uint256 amount)
    {
        uint8 roll = uint8(randomness % 100);

        if (roll < COMMON_DROP_RATE) {
            rarity = 0; // COMMON
            amount = (randomness % 401) + 100; // 100-500
        } else if (roll < COMMON_DROP_RATE + UNCOMMON_DROP_RATE) {
            rarity = 1; // UNCOMMON
            amount = (randomness % 16) + 10;   // 10-25
        } else {
            rarity = 2; // RARE
            amount = (randomness % 2) + 1;     // 1-2
        }
    }

    /**
     * @notice Updates game statistics for both individual dealer and global counters
     * @param tokenId The dealer NFT ID to update statistics for
     * @param outcome The game outcome (0=WIN updates win counters, other outcomes only update play counters)
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

    /**
     * @notice Removes a completed game from the player's active games list
     * @param player The address of the player whose active game list to update
     * @param requestId The VRF request ID to remove from the active games
     */
    function _removeActiveGame(address player, bytes32 requestId) internal {
        bytes32[] storage arr = playerActiveGames[player];
        uint256 n = arr.length;
        for (uint256 i; i < n; ) {
            if (arr[i] == requestId) {
                arr[i] = arr[n - 1];
                arr.pop();
                break;
            }
            unchecked { ++i; }
        }
    }

    // --- Flags helpers ---
    function _packFlags(bool isStaked, bool isResolved, bool paymentProcessed) private pure returns (uint8 f) {
        if (isStaked) f |= 1;
        if (isResolved) f |= 2;
        if (paymentProcessed) f |= 4;
    }
    function _isStaked(GameData storage g) private view returns (bool) { return (g.flags & 1) != 0; }
    function _isResolved(GameData storage g) private view returns (bool) { return (g.flags & 2) != 0; }
    function _paymentProcessed(GameData storage g) private view returns (bool) { return (g.flags & 4) != 0; }
    function _setResolved(GameData storage g) private { g.flags |= 2; }
    function _setPaymentProcessed(GameData storage g) private { g.flags |= 4; }

    // --- Timeouts ---
    function _timedOut(GameData storage g) private view returns (bool) {
        // uint40 promotes to uint256 automatically; no casts needed
        return g.timestamp > 0 && (block.timestamp > uint256(g.timestamp) + GAME_TIMEOUT);
    }

    // =============================================================
    //                        VALIDATION / VIEWS
    // =============================================================

    /**
     * @notice Checks if a dealer NFT can play a free game
     * @param tokenId The ID of the dealer NFT to check
     * @return canPlay True if the dealer has remaining daily free plays
     */
    function canPlayFree(uint256 tokenId) external view returns (bool) {
        (, , , uint8 dailyPlays, ,) = dealersExeCore.getDealerData(tokenId);
        return dailyPlays > 0;
    }

    /**
     * @notice Validates if a specific drug can be used for a free play game
     * @param tokenId The ID of the dealer NFT
     * @param drugId The ID of the drug to validate
     * @param amount The amount of the drug to use
     * @return canUse True if the dealer has sufficient drug balance and the drug is from the current area
     */
    function canUseDrugForFreePlay(uint256 tokenId, uint256 drugId, uint256 amount)
        external
        view
        returns (bool)
    {
        if (dealersExeCore.getDrugBalance(tokenId, drugId) < amount) return false;
        (uint8 currentArea, , , , ,) = dealersExeCore.getDealerData(tokenId);
        IDealersExeCore.DrugInfo memory di = dealersExeCore.getDrugInfo(drugId);
        return di.areaId == currentArea;
    }

    /**
     * @notice Retrieves all active game request IDs for a specific player
     * @param player The address of the player to query
     * @return gameIds Array of VRF request IDs for the player's active games
     */
    function getPlayerActiveGames(address player) external view returns (bytes32[] memory) {
        return playerActiveGames[player];
    }

    /**
     * @notice Gets game statistics for a specific dealer NFT
     * @param tokenId The ID of the dealer NFT to query
     * @return gamesPlayed Total number of games played by this dealer
     * @return gamesWon Total number of games won by this dealer
     * @return winRate Win rate as a percentage (0-100)
     */
    function getPlayerStats(uint256 tokenId) external view returns (uint256 gamesPlayed, uint256 gamesWon, uint256 winRate) {
        gamesPlayed = playerGamesPlayed[tokenId];
        gamesWon = playerGamesWon[tokenId];
        winRate = gamesPlayed == 0 ? 0 : (gamesWon * 100) / gamesPlayed;
    }

    /**
     * @notice Gets global game statistics across all dealers
     * @return totalPlayed Total number of games played across all dealers
     * @return totalWon Total number of games won across all dealers
     * @return globalWinRate Global win rate as a percentage (0-100)
     */
    function getGlobalStats() external view returns (uint256 totalPlayed, uint256 totalWon, uint256 globalWinRate) {
        totalPlayed = totalGamesPlayed;
        totalWon = totalGamesWon;
        globalWinRate = totalPlayed == 0 ? 0 : (totalWon * 100) / totalPlayed;
    }

    /**
     * @notice Retrieves the complete game data for a specific request ID
     * @param requestId The VRF request ID to query
     * @return gameData The complete GameData struct containing all game information
     */
    function getGameData(bytes32 requestId) external view returns (GameData memory) {
        return pendingGames[requestId];
    }

    /**
     * @notice Checks if a specific game has timed out
     * @param requestId The VRF request ID to check
     * @return timedOut True if the game exists, is unresolved, and has exceeded the timeout period
     */
    function isGameTimedOut(bytes32 requestId) external view returns (bool) {
        GameData storage g = pendingGames[requestId];
        return g.timestamp > 0 && !_isResolved(g) && _timedOut(g);
    }

    /**
     * @notice Retrieves all timed-out games for a specific player
     * @param player The address of the player to query
     * @return timedOutGames Array of VRF request IDs for games that have timed out
     */
    function getTimedOutGames(address player) external view returns (bytes32[] memory) {
        bytes32[] memory active = playerActiveGames[player];
        uint256 n = active.length;
        uint256 cnt;
        for (uint256 i; i < n; ) {
            GameData storage g = pendingGames[active[i]];
            if (g.timestamp > 0 && !_isResolved(g) && _timedOut(g)) cnt++;
            unchecked { ++i; }
        }
        bytes32[] memory out = new bytes32[](cnt);
        uint256 idx;
        for (uint256 i; i < n; ) {
            GameData storage g = pendingGames[active[i]];
            if (g.timestamp > 0 && !_isResolved(g) && _timedOut(g)) {
                out[idx] = active[i];
                unchecked { ++idx; }
            }
            unchecked { ++i; }
        }
        return out;
    }

    // =============================================================
    //                        ADMIN
    // =============================================================

    /**
     * @notice Updates the random provider contract address
     * @dev Only callable by the contract owner
     * @param _randomProvider The new random provider contract address
     */
    function setRandomProvider(address _randomProvider) external onlyOwner {
        address old = address(randomProvider);
        randomProvider = IRandomProvider(_randomProvider);
        emit RandomProviderUpdated(old, _randomProvider);
    }

    /**
     * @notice Updates the payment handler contract address
     * @dev Only callable by the contract owner
     * @param _paymentHandler The new payment handler contract address
     */
    function setPaymentHandler(address _paymentHandler) external onlyOwner {
        address old = address(paymentHandler);
        paymentHandler = IPaymentHandler(_paymentHandler);
        emit PaymentHandlerUpdated(old, _paymentHandler);
    }

    /**
     * @notice Updates the core dealers contract address
     * @dev Only callable by the contract owner
     * @param _dealersExeCore The new core dealers contract address
     */
    function setDealersExeCore(address _dealersExeCore) external onlyOwner {
        address old = address(dealersExeCore);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        emit CoreContractUpdated(old, _dealersExeCore);
    }

    /**
     * @notice Emergency function to refund staked games that haven't been resolved
     * @dev Only callable by the contract owner in emergency situations
     * @param requestIds Array of VRF request IDs to refund
     */
    function emergencyRefund(bytes32[] calldata requestIds) external onlyOwner {
        uint256 len = requestIds.length;
        for (uint256 i; i < len; ) {
            GameData storage g = pendingGames[requestIds[i]];
            if (!_isResolved(g) && _isStaked(g) && !_paymentProcessed(g) && g.stakeAmount > 0) {
                uint256 amt = uint256(g.stakeAmount);
                _safeTransferETH(g.player, amt);
                _setPaymentProcessed(g);
                _setResolved(g);
                emit GameRefunded(requestIds[i], g.player, amt);
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Gets the current ETH balance of the contract
     * @return balance The contract's ETH balance in wei
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Emergency function to withdraw ETH from the contract
     * @dev Only callable by the contract owner for emergency situations
     * @param to The address to send the withdrawn ETH to
     * @param amount The amount of ETH to withdraw in wei
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount <= address(this).balance, "Insufficient balance");
        _safeTransferETH(to, amount);
    }

    /**
     * @notice Allows the contract to receive ETH payments
     * @dev Required for processing game stakes and refunds
     */
    receive() external payable {}
}
