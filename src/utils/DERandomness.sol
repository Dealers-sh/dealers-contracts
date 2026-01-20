// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DERandomness
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Provides synchronous randomness using prevrandao for gaming applications
 * @author Dealers.Exe Team
 */
contract DERandomness is Ownable {

    // =============================================================
    //                            STORAGE
    // =============================================================

    mapping(address => bool) public authorizedResolvers;
    uint256 private nonce;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event ResolverAuthorized(address indexed resolver, bool authorized);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotAuthorized();
    error InvalidAddress();

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
     * @dev WARNING: This randomness is NOT suitable for high-stakes financial applications.
     * Limitations:
     * - Block proposers can know prevrandao one block ahead
     * - On L2, sequencer has timing control
     * - Use only for gaming with in-game assets
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
        for (uint256 i = 0; i < resolvers.length;) {
            if (resolvers[i] == address(0)) revert InvalidAddress();
            authorizedResolvers[resolvers[i]] = authorized;
            emit ResolverAuthorized(resolvers[i], authorized);
            unchecked { ++i; }
        }
    }
}
