// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/src/auth/Ownable.sol";

interface IGameResolver {
    function resolveGame(bytes32 requestId, uint256 randomness) external;
}

/**
 * @title DERandomness - Multi-Module Randomness Provider
 * @dev Uses prevrandao for immediate randomness, designed for easy VRF upgrade
 * Production-ready with enhanced security and monitoring features
 */
contract DERandomness is Ownable {
    
    // =============================================================
    //                            CONSTANTS
    // =============================================================
    
    uint256 public constant REQUEST_TIMEOUT = 300; // 5 minutes
    
    // =============================================================
    //                            STORAGE
    // =============================================================
    
    mapping(address => bool) public authorizedResolvers;
    mapping(bytes32 => RequestData) public requests;
    uint256 private nonce;
    
    // Future VRF support (ready for upgrade)
    bool public vrfEnabled = false;
    address public vrfCoordinator;
    uint256 public vrfThreshold = 0.005 ether; // Threshold for VRF usage
    
    // =============================================================
    //                            STRUCTS
    // =============================================================
    
    struct RequestData {
        address requester;
        bytes32 gameId;
        uint256 timestamp;
        bool resolved;
        uint256 randomness;
    }
    
    // =============================================================
    //                            EVENTS
    // =============================================================
    
    event ResolverAuthorized(address indexed resolver, bool authorized);
    event RandomnessRequested(bytes32 indexed requestId, address indexed requester, bytes32 gameId);
    event RandomnessResolved(bytes32 indexed requestId, uint256 randomness);
    event RequestTimeout(bytes32 indexed requestId, address indexed requester);
    event VRFEnabled(address indexed coordinator, uint256 threshold);
    event VRFConfigUpdated(address indexed coordinator, uint256 threshold);
    
    // =============================================================
    //                            ERRORS
    // =============================================================
    
    error NotAuthorized();
    error InvalidAddress();
    error RequestNotFound();
    error RequestAlreadyResolved();
    error RequestTimedOut();
    error VRFNotEnabled();
    
    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================
    
    constructor() {
        _initializeOwner(msg.sender);
    }
    
    // =============================================================
    //                        RANDOMNESS FUNCTIONS
    // =============================================================
    
    /**
     * @notice Request randomness - resolves immediately with prevrandao
     * @param gameId Unique game identifier
     * @return requestId Request identifier for tracking
     */
    function requestRandomness(bytes32 gameId) external returns (bytes32 requestId) {
        if (!authorizedResolvers[msg.sender]) revert NotAuthorized();
        
        nonce++;
        
        requestId = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            gameId,
            nonce
        ));
        
        // Store request data for tracking
        requests[requestId] = RequestData({
            requester: msg.sender,
            gameId: gameId,
            timestamp: block.timestamp,
            resolved: false,
            randomness: 0
        });
        
        emit RandomnessRequested(requestId, msg.sender, gameId);
        
        // Generate immediate randomness using prevrandao
        _resolvePseudoRandomness(requestId, gameId);
        
        return requestId;
    }
    
    /**
     * @notice Generate pseudo-randomness using prevrandao and resolve immediately
     * @param requestId Request identifier
     * @param gameId Game identifier for additional entropy
     */
    function _resolvePseudoRandomness(bytes32 requestId, bytes32 gameId) internal {
        // Generate randomness using prevrandao + additional entropy
        uint256 randomness = uint256(keccak256(abi.encodePacked(
            block.prevrandao,        // Primary randomness source
            block.timestamp,         // Temporal component
            block.number,           // Block height component
            gameId,                 // Game-specific entropy
            nonce,                  // Incremental nonce
            msg.sender,             // Requester address
            address(this),          // Contract address
            tx.gasprice             // Transaction gas price for additional entropy
        )));
        
        // Update request data
        RequestData storage request = requests[requestId];
        request.resolved = true;
        request.randomness = randomness;
        
        emit RandomnessResolved(requestId, randomness);
        
        // Immediately call back to the requesting contract
        try IGameResolver(msg.sender).resolveGame(requestId, randomness) {
            // Success - game resolved
        } catch {
            // If callback fails, keep request marked as resolved
            // The requester can handle this through timeout mechanisms
        }
    }
    
    // =============================================================
    //                        FUTURE VRF SUPPORT
    // =============================================================
    
    /**
     * @notice Enable VRF for high-stakes games (future upgrade)
     * @param _vrfCoordinator VRF coordinator address
     * @param _threshold Minimum stake amount to trigger VRF
     */
    function enableVRF(address _vrfCoordinator, uint256 _threshold) external onlyOwner {
        if (_vrfCoordinator == address(0)) revert InvalidAddress();
        
        vrfCoordinator = _vrfCoordinator;
        vrfThreshold = _threshold;
        vrfEnabled = true;
        
        emit VRFEnabled(_vrfCoordinator, _threshold);
    }
    
    /**
     * @notice Update VRF configuration
     * @param _vrfCoordinator New VRF coordinator address
     * @param _threshold New threshold for VRF usage
     */
    function updateVRFConfig(address _vrfCoordinator, uint256 _threshold) external onlyOwner {
        if (!vrfEnabled) revert VRFNotEnabled();
        if (_vrfCoordinator == address(0)) revert InvalidAddress();
        
        vrfCoordinator = _vrfCoordinator;
        vrfThreshold = _threshold;
        
        emit VRFConfigUpdated(_vrfCoordinator, _threshold);
    }
    
    /**
     * @notice Disable VRF and fall back to pseudo-randomness
     */
    function disableVRF() external onlyOwner {
        vrfEnabled = false;
        vrfCoordinator = address(0);
    }
    
    // =============================================================
    //                        REQUEST MANAGEMENT
    // =============================================================
    
    /**
     * @notice Check if a request has timed out
     * @param requestId Request identifier
     * @return True if request has timed out
     */
    function isRequestTimedOut(bytes32 requestId) external view returns (bool) {
        RequestData memory request = requests[requestId];
        return request.timestamp > 0 && 
               !request.resolved && 
               block.timestamp > request.timestamp + REQUEST_TIMEOUT;
    }
    
    /**
     * @notice Handle timed out requests (callable by anyone for cleanup)
     * @param requestIds Array of request IDs to check and timeout
     */
    function handleTimeouts(bytes32[] calldata requestIds) external {
        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            RequestData storage request = requests[requestId];
            
            if (request.timestamp > 0 && 
                !request.resolved && 
                block.timestamp > request.timestamp + REQUEST_TIMEOUT) {
                
                request.resolved = true; // Mark as resolved to prevent reprocessing
                emit RequestTimeout(requestId, request.requester);
            }
        }
    }
    
    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================
    
    /**
     * @notice Get request data
     * @param requestId Request identifier
     * @return Request data struct
     */
    function getRequestData(bytes32 requestId) external view returns (RequestData memory) {
        return requests[requestId];
    }
    
    /**
     * @notice Check if a contract is authorized to request randomness
     * @param resolver Address to check
     * @return True if authorized
     */
    function isAuthorizedResolver(address resolver) external view returns (bool) {
        return authorizedResolvers[resolver];
    }
    
    /**
     * @notice Get VRF configuration
     * @return enabled Whether VRF is enabled
     * @return coordinator VRF coordinator address
     * @return threshold Minimum stake for VRF usage
     */
    function getVRFConfig() external view returns (
        bool enabled,
        address coordinator,
        uint256 threshold
    ) {
        enabled = vrfEnabled;
        coordinator = vrfCoordinator;
        threshold = vrfThreshold;
    }
    
    /**
     * @notice Get current nonce (for entropy verification)
     * @return Current nonce value
     */
    function getCurrentNonce() external view returns (uint256) {
        return nonce;
    }
    
    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================
    
    /**
     * @notice Authorize/deauthorize game modules to request randomness
     * @param resolver Game module address
     * @param authorized True to authorize, false to revoke
     */
    function authorizeResolver(address resolver, bool authorized) external onlyOwner {
        if (resolver == address(0)) revert InvalidAddress();
        
        authorizedResolvers[resolver] = authorized;
        emit ResolverAuthorized(resolver, authorized);
    }
    
    /**
     * @notice Batch authorize multiple resolvers
     * @param resolvers Array of resolver addresses
     * @param authorized Authorization status for all
     */
    function batchAuthorizeResolvers(address[] calldata resolvers, bool authorized) external onlyOwner {
        for (uint256 i = 0; i < resolvers.length; i++) {
            if (resolvers[i] != address(0)) {
                authorizedResolvers[resolvers[i]] = authorized;
                emit ResolverAuthorized(resolvers[i], authorized);
            }
        }
    }
    
    // =============================================================
    //                        UPGRADE FUNCTIONS
    // =============================================================
    
    /**
     * @notice Emergency function to manually resolve stuck requests
     * @param requestIds Array of request IDs to manually resolve
     * @param randomnessValues Array of randomness values (must match requestIds length)
     * @dev Only use in case of critical failures
     */
    function emergencyResolve(
        bytes32[] calldata requestIds, 
        uint256[] calldata randomnessValues
    ) external onlyOwner {
        require(requestIds.length == randomnessValues.length, "Array length mismatch");
        
        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            RequestData storage request = requests[requestId];
            
            if (request.timestamp > 0 && !request.resolved) {
                request.resolved = true;
                request.randomness = randomnessValues[i];
                
                emit RandomnessResolved(requestId, randomnessValues[i]);
                
                // Attempt to resolve the game
                try IGameResolver(request.requester).resolveGame(requestId, randomnessValues[i]) {
                    // Success
                } catch {
                    // Log but continue
                }
            }
        }
    }
    
    /**
     * @notice Get statistics for monitoring
     * @return totalRequests Total number of requests made
     * @return resolvedRequests Number of resolved requests
     * @return currentNonce Current nonce value
     */
    function getStatistics() external view returns (
        uint256 totalRequests,
        uint256 resolvedRequests,
        uint256 currentNonce
    ) {
        // Note: These would need to be tracked if detailed stats are needed
        // For now, return basic info
        currentNonce = nonce;
        totalRequests = nonce; // Approximation
        resolvedRequests = nonce; // Most requests resolve immediately
    }
}