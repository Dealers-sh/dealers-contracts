// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import "../IDealersExeCore.sol";
import "../IERC721Minimal.sol";
import "../IDERandomness.sol";

/**
 * @title DealersExeHeist - Heist Lottery Module
 * @dev Implements a lottery-style heist system where players enter with dealers
 *      to compete for a share of the prize pool
 * @author Dealers.Exe Team
 *
 * Key Features:
 * - Entry fees go 100% to prize pool (no dev/vault split on entries)
 * - Prize tiers based on pool size (50-80% to winner)
 * - Jail arrest check on entry (entry fee lost if arrested)
 * - Kingpin boost gives 2 entries for price of 1
 * - Requires minimum reputation tier (canHeist = true)
 */
contract DealersExeHeist is ReentrancyGuard, Ownable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant DEFAULT_ENTRY_FEE = 0.01 ether;
    uint256 public constant MIN_ENTRY_FEE = 0.005 ether;
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant MAX_DURATION = 7 days;
    uint256 public constant DRAW_DELAY = 5 minutes; // Time between close and draw

    // =============================================================
    //                            ENUMS
    // =============================================================

    enum HeistStatus {
        INACTIVE,   // No heist running
        OPEN,       // Accepting entries
        CLOSED,     // No more entries, waiting for draw
        DRAWING,    // Draw in progress
        COMPLETED   // Winner selected and paid
    }

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /**
     * @dev Heist round data structure
     * @param roundId Unique identifier for this heist round
     * @param entryFee Entry fee for this round
     * @param startTime When the heist opened for entries
     * @param endTime When entries close
     * @param drawTime When draw can happen (endTime + DRAW_DELAY)
     * @param prizePool Total entries * entry fee
     * @param entryCount Number of entries (including double entries from boosts)
     * @param winnerId Winning dealer ID (set after draw)
     * @param winnerAddress Winner's wallet address
     * @param prizeAmount Amount won
     * @param status Current heist status
     */
    struct HeistRound {
        uint256 roundId;
        uint256 entryFee;
        uint256 startTime;
        uint256 endTime;
        uint256 drawTime;
        uint256 prizePool;
        uint256 entryCount;
        uint256 winnerId;
        address winnerAddress;
        uint256 prizeAmount;
        HeistStatus status;
    }

    /**
     * @dev Entry data structure for tracking individual entries
     * @param dealerId The dealer NFT ID that entered
     * @param player The wallet address that owns the dealer
     * @param enteredAt Timestamp when entry was registered
     */
    struct EntryData {
        uint256 dealerId;
        address player;
        uint256 enteredAt;
    }

    // =============================================================
    //                            STORAGE
    // =============================================================

    // External contract references
    IDealersExeCore public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    IDERandomness public randomness;

    // Heist rounds
    mapping(uint256 => HeistRound) public heists;              // roundId => HeistRound
    mapping(uint256 => EntryData[]) public roundEntries;       // roundId => entries array
    mapping(uint256 => mapping(uint256 => bool)) public hasEntered; // roundId => dealerId => entered

    // Current state
    uint256 public currentRoundId;

    // Statistics
    uint256 public totalHeistsCompleted;
    uint256 public totalPrizesPaid;
    uint256 public totalEntriesAllTime;

    // Tracking player history (dealerId => list of rounds entered)
    mapping(uint256 => uint256[]) private _playerHeistHistory;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event HeistStarted(
        uint256 indexed roundId,
        uint256 entryFee,
        uint256 endTime
    );

    event HeistEntered(
        uint256 indexed roundId,
        uint256 indexed dealerId,
        address indexed player,
        uint8 entriesGranted
    );

    event HeistClosed(
        uint256 indexed roundId,
        uint256 entryCount,
        uint256 prizePool
    );

    event HeistDrawn(
        uint256 indexed roundId,
        uint256 indexed winnerId,
        address indexed winner,
        uint256 prizeAmount
    );

    event DealerArrested(
        uint256 indexed roundId,
        uint256 indexed dealerId,
        uint8 heatLevel
    );

    event HeistCancelled(
        uint256 indexed roundId,
        string reason
    );

    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event RandomnessUpdated(address indexed oldRandomness, address indexed newRandomness);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ContractNotSet();
    error HeistNotOpen();
    error HeistNotClosed();
    error HeistNotActive();
    error DrawDelayNotPassed();
    error NoEntries();
    error InsufficientEntryFee();
    error NotDealerOwner();
    error AlreadyEntered();
    error DealerInJail();
    error DealerInSafeHouse();
    error DealerNotInitialized();
    error InsufficientReputation();
    error InvalidDuration();
    error InvalidEntryFee();
    error HeistAlreadyActive();
    error InvalidAddress();
    error TransferFailed();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the Heist contract
     * @param _dealersExeCore Address of the core dealers contract
     * @param _dealersExeNFT Address of the NFT contract for ownership checks
     */
    constructor(address _dealersExeCore, address _dealersExeNFT) {
        _initializeOwner(msg.sender);
        dealersExeCore = IDealersExeCore(_dealersExeCore);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(dealersExeCore) == address(0) ||
            address(dealersExeNFT) == address(0) ||
            address(randomness) == address(0)
        ) {
            revert ContractNotSet();
        }
        _;
    }

    modifier dealerExists(uint256 tokenId) {
        (, , , , , bool isInitialized) = dealersExeCore.getDealerData(tokenId);
        if (!isInitialized) revert DealerNotInitialized();
        _;
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Start a new heist round
     * @param entryFee Entry fee for this round
     * @param duration How long the heist is open (in seconds)
     */
    function startHeist(uint256 entryFee, uint256 duration) external onlyOwner contractsSet {
        // Validate current heist state
        HeistRound storage current = heists[currentRoundId];
        if (currentRoundId > 0 && current.status != HeistStatus.COMPLETED && current.status != HeistStatus.INACTIVE) {
            revert HeistAlreadyActive();
        }

        // Validate parameters
        if (entryFee < MIN_ENTRY_FEE) revert InvalidEntryFee();
        if (duration < MIN_DURATION || duration > MAX_DURATION) revert InvalidDuration();

        // Increment round ID
        unchecked { ++currentRoundId; }

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        uint256 drawTime = endTime + DRAW_DELAY;

        heists[currentRoundId] = HeistRound({
            roundId: currentRoundId,
            entryFee: entryFee,
            startTime: startTime,
            endTime: endTime,
            drawTime: drawTime,
            prizePool: 0,
            entryCount: 0,
            winnerId: 0,
            winnerAddress: address(0),
            prizeAmount: 0,
            status: HeistStatus.OPEN
        });

        emit HeistStarted(currentRoundId, entryFee, endTime);
    }

    /**
     * @notice Close the current heist (no more entries)
     * @dev Can be called after endTime or manually by owner
     */
    function closeHeist() external onlyOwner {
        HeistRound storage heist = heists[currentRoundId];

        if (heist.status != HeistStatus.OPEN) revert HeistNotOpen();

        heist.status = HeistStatus.CLOSED;

        emit HeistClosed(currentRoundId, heist.entryCount, heist.prizePool);
    }

    /**
     * @notice Draw the winner (after draw delay)
     * @dev Uses centralized randomness provider
     */
    function drawWinner() external onlyOwner nonReentrant contractsSet {
        HeistRound storage heist = heists[currentRoundId];

        if (heist.status != HeistStatus.CLOSED) revert HeistNotClosed();
        if (block.timestamp < heist.drawTime) revert DrawDelayNotPassed();
        if (heist.entryCount == 0) revert NoEntries();

        heist.status = HeistStatus.DRAWING;

        // Generate random winner index using centralized randomness
        bytes32 seed = keccak256(abi.encodePacked(heist.prizePool, heist.entryCount, currentRoundId));
        uint256 winnerIndex = randomness.getRandomness(seed) % roundEntries[currentRoundId].length;

        EntryData memory winner = roundEntries[currentRoundId][winnerIndex];

        // Calculate prize based on pool size tiers
        uint256 prizePercent = _getPrizePercent(heist.prizePool);
        uint256 prizeAmount = (heist.prizePool * prizePercent) / 100;

        heist.winnerId = winner.dealerId;
        heist.winnerAddress = winner.player;
        heist.prizeAmount = prizeAmount;
        heist.status = HeistStatus.COMPLETED;

        unchecked {
            ++totalHeistsCompleted;
            totalPrizesPaid += prizeAmount;
        }

        // Transfer prize to winner
        _safeTransferETH(winner.player, prizeAmount);

        // Remaining funds stay in contract for next heist (carries over)

        emit HeistDrawn(currentRoundId, winner.dealerId, winner.player, prizeAmount);
    }

    /**
     * @notice Cancel current heist and refund all entries
     * @dev Emergency function - only use if necessary
     * @param reason Reason for cancellation
     */
    function cancelHeist(string calldata reason) external onlyOwner nonReentrant {
        HeistRound storage heist = heists[currentRoundId];

        if (heist.status == HeistStatus.INACTIVE || heist.status == HeistStatus.COMPLETED) {
            revert HeistNotActive();
        }

        // Refund all entries
        EntryData[] storage entries = roundEntries[currentRoundId];
        uint256 refundAmount = heist.entryFee;

        // Track refunded dealers to avoid double refunds (for double entries)
        mapping(uint256 => bool) storage refunded = hasEntered[currentRoundId];

        for (uint256 i = 0; i < entries.length; ) {
            // Only refund once per dealer (not per entry)
            if (refunded[entries[i].dealerId]) {
                // Already processed this dealer, just reset the flag
                refunded[entries[i].dealerId] = false;
            } else {
                // First entry for this dealer - refund and mark as processed
                _safeTransferETH(entries[i].player, refundAmount);
                refunded[entries[i].dealerId] = true; // Temporarily mark to skip next entry
            }
            unchecked { ++i; }
        }

        // Reset all hasEntered flags
        for (uint256 i = 0; i < entries.length; ) {
            hasEntered[currentRoundId][entries[i].dealerId] = false;
            unchecked { ++i; }
        }

        heist.status = HeistStatus.COMPLETED;

        emit HeistCancelled(currentRoundId, reason);
    }

    // =============================================================
    //                        PLAYER FUNCTIONS
    // =============================================================

    /**
     * @notice Enter heist with a single dealer
     * @param dealerId The dealer NFT ID to enter with
     */
    function enterHeist(uint256 dealerId)
        external
        payable
        nonReentrant
        contractsSet
        dealerExists(dealerId)
    {
        HeistRound storage heist = heists[currentRoundId];

        // Validate heist is open
        if (heist.status != HeistStatus.OPEN) revert HeistNotOpen();
        if (block.timestamp > heist.endTime) revert HeistNotOpen();

        // Validate payment
        uint256 fee = heist.entryFee;
        if (msg.value < fee) revert InsufficientEntryFee();

        // Validate dealer ownership
        if (dealersExeNFT.ownerOf(dealerId) != msg.sender) revert NotDealerOwner();

        // Validate not already entered
        if (hasEntered[currentRoundId][dealerId]) revert AlreadyEntered();

        // Validate dealer location
        if (dealersExeCore.isInJail(dealerId)) revert DealerInJail();
        if (dealersExeCore.isInSafeHouse(dealerId)) revert DealerInSafeHouse();

        // Check reputation requirement (must be Pusher tier or higher - canHeist = true)
        IDealersExeCore.ReputationTier memory tier = dealersExeCore.getPlayerTier(dealerId);
        if (!tier.canHeist) revert InsufficientReputation();

        // Use attempt and increment heat
        dealersExeCore.useAttempt(dealerId);
        dealersExeCore.incrementHeatLevel(dealerId);

        // Check if arrested (heat level % chance)
        uint8 jailChance = dealersExeCore.getJailChance(dealerId);
        bytes32 jailSeed = keccak256(abi.encodePacked(dealerId, currentRoundId, "HEIST_JAIL"));
        uint256 jailRoll = randomness.getRandomness(jailSeed) % 100;

        if (jailRoll < jailChance) {
            dealersExeCore.sendToJail(dealerId);
            emit DealerArrested(currentRoundId, dealerId, jailChance);
            // Fee is lost - no refund for arrested dealers
            // Add to prize pool anyway
            heist.prizePool += fee;
            return;
        }

        // Handle double entries for Kingpin boost
        uint8 entries = dealersExeCore.hasDoubleHeistEntries(dealerId) ? 2 : 1;

        for (uint8 i = 0; i < entries; ) {
            roundEntries[currentRoundId].push(EntryData({
                dealerId: dealerId,
                player: msg.sender,
                enteredAt: block.timestamp
            }));
            unchecked { ++i; }
        }

        hasEntered[currentRoundId][dealerId] = true;
        heist.entryCount += entries;
        heist.prizePool += fee;

        unchecked { ++totalEntriesAllTime; }

        // Track player history
        _playerHeistHistory[dealerId].push(currentRoundId);

        emit HeistEntered(currentRoundId, dealerId, msg.sender, entries);

        // Refund excess
        if (msg.value > fee) {
            _safeTransferETH(msg.sender, msg.value - fee);
        }
    }

    /**
     * @notice Enter heist with multiple dealers (batch)
     * @param dealerIds Array of dealer NFT IDs to enter with
     */
    function enterHeistBatch(uint256[] calldata dealerIds)
        external
        payable
        nonReentrant
        contractsSet
    {
        HeistRound storage heist = heists[currentRoundId];

        // Validate heist is open
        if (heist.status != HeistStatus.OPEN) revert HeistNotOpen();
        if (block.timestamp > heist.endTime) revert HeistNotOpen();

        uint256 totalFee = heist.entryFee * dealerIds.length;
        if (msg.value < totalFee) revert InsufficientEntryFee();

        uint256 successfulEntries = 0;

        for (uint256 i = 0; i < dealerIds.length; ) {
            uint256 dealerId = dealerIds[i];

            // Skip invalid entries silently
            // Check initialization
            (, , , , , bool isInitialized) = dealersExeCore.getDealerData(dealerId);
            if (!isInitialized) {
                unchecked { ++i; }
                continue;
            }

            // Check ownership
            if (dealersExeNFT.ownerOf(dealerId) != msg.sender) {
                unchecked { ++i; }
                continue;
            }

            // Check not already entered
            if (hasEntered[currentRoundId][dealerId]) {
                unchecked { ++i; }
                continue;
            }

            // Check location
            if (dealersExeCore.isInJail(dealerId)) {
                unchecked { ++i; }
                continue;
            }
            if (dealersExeCore.isInSafeHouse(dealerId)) {
                unchecked { ++i; }
                continue;
            }

            // Check reputation
            IDealersExeCore.ReputationTier memory tier = dealersExeCore.getPlayerTier(dealerId);
            if (!tier.canHeist) {
                unchecked { ++i; }
                continue;
            }

            // Use attempt and increment heat
            dealersExeCore.useAttempt(dealerId);
            dealersExeCore.incrementHeatLevel(dealerId);

            // Check if arrested
            uint8 jailChance = dealersExeCore.getJailChance(dealerId);
            bytes32 jailSeed = keccak256(abi.encodePacked(dealerId, currentRoundId, i, "HEIST_JAIL_BATCH"));
            uint256 jailRoll = randomness.getRandomness(jailSeed) % 100;

            if (jailRoll < jailChance) {
                dealersExeCore.sendToJail(dealerId);
                emit DealerArrested(currentRoundId, dealerId, jailChance);
                // Fee lost - goes to prize pool, counts as paid entry
                heist.prizePool += heist.entryFee;
                unchecked {
                    ++successfulEntries;
                    ++i;
                }
                continue;
            }

            // Handle double entries for Kingpin boost
            uint8 entries = dealersExeCore.hasDoubleHeistEntries(dealerId) ? 2 : 1;

            for (uint8 j = 0; j < entries; ) {
                roundEntries[currentRoundId].push(EntryData({
                    dealerId: dealerId,
                    player: msg.sender,
                    enteredAt: block.timestamp
                }));
                unchecked { ++j; }
            }

            hasEntered[currentRoundId][dealerId] = true;
            heist.entryCount += entries;

            // Track player history
            _playerHeistHistory[dealerId].push(currentRoundId);

            // Add fee to prize pool
            heist.prizePool += heist.entryFee;

            emit HeistEntered(currentRoundId, dealerId, msg.sender, entries);

            unchecked {
                ++successfulEntries;
                ++totalEntriesAllTime;
                ++i;
            }
        }

        // Calculate actual fee based on successful entries (including arrested dealers who paid)
        uint256 actualFee = heist.entryFee * successfulEntries;

        // Refund for dealers that didn't enter (skipped due to validation failures)
        if (msg.value > actualFee) {
            _safeTransferETH(msg.sender, msg.value - actualFee);
        }
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get the current heist round data
     * @return The current heist round struct
     */
    function getCurrentHeist() external view returns (HeistRound memory) {
        return heists[currentRoundId];
    }

    /**
     * @notice Get heist round by ID
     * @param roundId The round ID to query
     * @return The heist round struct
     */
    function getHeist(uint256 roundId) external view returns (HeistRound memory) {
        return heists[roundId];
    }

    /**
     * @notice Get entries for a specific round
     * @param roundId The round ID to query
     * @return Array of entry data
     */
    function getHeistEntries(uint256 roundId) external view returns (EntryData[] memory) {
        return roundEntries[roundId];
    }

    /**
     * @notice Get number of entries for a specific round
     * @param roundId The round ID to query
     * @return Number of entries
     */
    function getHeistEntryCount(uint256 roundId) external view returns (uint256) {
        return roundEntries[roundId].length;
    }

    /**
     * @notice Check if a dealer can enter the current heist
     * @param dealerId The dealer NFT ID to check
     * @return canEnter Whether the dealer can enter
     * @return reason Reason code (0=can enter, 1=not initialized, 2=in jail, 3=in safe house, 4=already entered, 5=insufficient rep, 6=no attempts, 7=heist not open)
     */
    function canEnterHeist(uint256 dealerId) external view returns (bool canEnter, uint8 reason) {
        HeistRound storage heist = heists[currentRoundId];

        // Check heist state
        if (heist.status != HeistStatus.OPEN || block.timestamp > heist.endTime) {
            return (false, 7);
        }

        // Check initialization
        (, , uint8 attemptsRemaining, , , bool isInitialized) = dealersExeCore.getDealerData(dealerId);
        if (!isInitialized) return (false, 1);

        // Check jail
        if (dealersExeCore.isInJail(dealerId)) return (false, 2);

        // Check safe house
        if (dealersExeCore.isInSafeHouse(dealerId)) return (false, 3);

        // Check already entered
        if (hasEntered[currentRoundId][dealerId]) return (false, 4);

        // Check reputation
        IDealersExeCore.ReputationTier memory tier = dealersExeCore.getPlayerTier(dealerId);
        if (!tier.canHeist) return (false, 5);

        // Check attempts
        if (attemptsRemaining == 0) return (false, 6);

        return (true, 0);
    }

    /**
     * @notice Get heist statistics
     * @return totalCompleted Total heists completed
     * @return totalPaid Total prizes paid out
     * @return totalEntries Total entries all time
     */
    function getHeistStats() external view returns (
        uint256 totalCompleted,
        uint256 totalPaid,
        uint256 totalEntries
    ) {
        return (totalHeistsCompleted, totalPrizesPaid, totalEntriesAllTime);
    }

    /**
     * @notice Get heist history for a specific dealer
     * @param dealerId The dealer NFT ID to query
     * @return Array of round IDs the dealer has entered
     */
    function getPlayerHeistHistory(uint256 dealerId) external view returns (uint256[] memory) {
        return _playerHeistHistory[dealerId];
    }

    /**
     * @notice Check if a dealer has entered a specific round
     * @param roundId The round ID to check
     * @param dealerId The dealer NFT ID to check
     * @return True if dealer has entered the round
     */
    function hasDealerEntered(uint256 roundId, uint256 dealerId) external view returns (bool) {
        return hasEntered[roundId][dealerId];
    }

    /**
     * @notice Get the current prize pool plus contract balance (potential max prize)
     * @return Current prize pool for active heist
     */
    function getCurrentPrizePool() external view returns (uint256) {
        return heists[currentRoundId].prizePool;
    }

    /**
     * @notice Get the contract's total ETH balance (includes rollover from previous heists)
     * @return Total ETH balance in contract
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Preview prize amount for current pool size
     * @return prizePercent The percentage the winner would receive
     * @return prizeAmount The amount the winner would receive
     */
    function previewPrize() external view returns (uint256 prizePercent, uint256 prizeAmount) {
        uint256 pool = heists[currentRoundId].prizePool;
        prizePercent = _getPrizePercent(pool);
        prizeAmount = (pool * prizePercent) / 100;
    }

    // =============================================================
    //                        ADMIN SETTERS
    // =============================================================

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
     * @notice Updates the Randomness contract address
     * @param _randomness The new Randomness contract address
     */
    function setRandomness(address _randomness) external onlyOwner {
        if (_randomness == address(0)) revert InvalidAddress();
        address old = address(randomness);
        randomness = IDERandomness(_randomness);
        emit RandomnessUpdated(old, _randomness);
    }

    /**
     * @notice Seed the prize pool with ETH
     * @dev Can be used to add bonus funds to the heist
     */
    function seedPrizePool() external payable onlyOwner {
        heists[currentRoundId].prizePool += msg.value;
    }

    /**
     * @notice Emergency withdrawal (owner only)
     * @dev Only use in emergencies when no active heist
     * @param to Address to send funds to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidAddress();

        HeistRound storage heist = heists[currentRoundId];
        if (heist.status == HeistStatus.OPEN || heist.status == HeistStatus.CLOSED) {
            revert HeistAlreadyActive();
        }

        _safeTransferETH(to, amount);
    }

    // =============================================================
    //                        INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Calculate prize percentage based on pool size
     * @param poolSize The total prize pool
     * @return Prize percentage (50-80)
     */
    function _getPrizePercent(uint256 poolSize) internal pure returns (uint256) {
        if (poolSize >= 10 ether) return 80;
        if (poolSize >= 5 ether) return 70;
        if (poolSize >= 1 ether) return 60;
        return 50;
    }

    /**
     * @notice Safe ETH transfer using .call() for Abstract Chain compatibility
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // =============================================================
    //                        RECEIVE FUNCTION
    // =============================================================

    /**
     * @notice Accept ETH for prize pool seeding
     */
    receive() external payable {
        // Add received ETH to current heist prize pool if active
        if (heists[currentRoundId].status == HeistStatus.OPEN) {
            heists[currentRoundId].prizePool += msg.value;
        }
        // Otherwise, ETH is held in contract for next heist
    }
}
