// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DERandomness
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Provides synchronous randomness using prevrandao, designed for easy VRF upgrade
 * @author Dealers.Exe Team
 */
contract DERandomness is Ownable {

    // =============================================================
    //                            STORAGE
    // =============================================================

    mapping(address => bool) public authorizedResolvers;
    uint256 private nonce;

    // Future VRF support (ready for upgrade)
    bool public vrfEnabled = false;
    address public vrfCoordinator;
    uint256 public vrfThreshold = 0.005 ether;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event ResolverAuthorized(address indexed resolver, bool authorized);
    event VRFEnabled(address indexed coordinator, uint256 threshold);
    event VRFConfigUpdated(address indexed coordinator, uint256 threshold);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotAuthorized();
    error InvalidAddress();
    error VRFNotEnabled();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor() {
        _initializeOwner(msg.sender);
    }

    // =============================================================
    //                        RANDOMNESS FUNCTION
    // =============================================================

    /**
     * @notice Get randomness using prevrandao and additional entropy
     * @param seed Context-specific seed for additional entropy
     * @return Deterministic randomness value
     */
    function getRandomness(bytes32 seed) external returns (uint256) {
        if (!authorizedResolvers[msg.sender]) revert NotAuthorized();

        unchecked { ++nonce; }

        return uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            block.number,
            seed,
            nonce,
            address(this)
        )));
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
    //                        VIEW FUNCTIONS
    // =============================================================

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
}
