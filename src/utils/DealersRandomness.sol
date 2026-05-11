// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DealersRandomness
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @notice Commit-reveal randomness coordinator. Consumers call commit() in tx 1 to
 *         reserve a sequence number, then call reveal(seq) (a view) in tx 2+ to read
 *         entropy derived from blockhash(commitBlock + REVEAL_OFFSET).
 *
 * @dev Player-side simulation defense: at commit time the future blockhash does not
 *      exist, so a wrapper-and-revert simulator cannot read the outcome before
 *      committing. EXPIRY_WINDOW stays well under the EVM 256-block blockhash ceiling.
 *
 *      Sequencer manipulation is NOT addressed here — see Pyth Entropy for that.
 *
 * @author Berny0x
 */
contract DealersRandomness is Ownable {
    uint64 public constant REVEAL_OFFSET = 2;
    uint64 public constant EXPIRY_WINDOW = 200;

    mapping(address => bool) public authorizedResolvers;

    uint64 public nextSeq = 1;
    mapping(uint64 => uint64) public revealBlockOf;

    event ResolverAuthorized(address indexed resolver, bool authorized);
    event Committed(uint64 indexed seq, address indexed resolver, uint64 revealBlock);

    error NotAuthorized();
    error InvalidAddress();
    error UnknownSeq();
    error TooEarly();
    error Expired();

    constructor() {
        _initializeOwner(msg.sender);
    }

    function commit() external returns (uint64 seq) {
        if (!authorizedResolvers[msg.sender]) revert NotAuthorized();
        unchecked { seq = nextSeq++; }
        uint64 rb = uint64(block.number) + REVEAL_OFFSET;
        revealBlockOf[seq] = rb;
        emit Committed(seq, msg.sender, rb);
    }

    function reveal(uint64 seq) external view returns (uint256) {
        uint64 rb = revealBlockOf[seq];
        if (rb == 0) revert UnknownSeq();
        if (block.number <= rb) revert TooEarly();
        if (block.number > rb + EXPIRY_WINDOW) revert Expired();
        return uint256(keccak256(abi.encodePacked(blockhash(rb), seq, msg.sender)));
    }

    function isExpired(uint64 seq) external view returns (bool) {
        uint64 rb = revealBlockOf[seq];
        return rb != 0 && block.number > rb + EXPIRY_WINDOW;
    }

    function isAuthorizedResolver(address resolver) external view returns (bool) {
        return authorizedResolvers[resolver];
    }

    function authorizeResolver(address resolver, bool authorized) external onlyOwner {
        if (resolver == address(0)) revert InvalidAddress();
        authorizedResolvers[resolver] = authorized;
        emit ResolverAuthorized(resolver, authorized);
    }
}
