// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/utils/DealersRandomness.sol";

contract MockResolver {
    DealersRandomness public r;

    constructor(DealersRandomness _r) {
        r = _r;
    }

    function commit() external returns (uint64) {
        return r.commit();
    }

    function reveal(uint64 seq) external view returns (uint256) {
        return r.reveal(seq);
    }

    function isExpired(uint64 seq) external view returns (bool) {
        return r.isExpired(seq);
    }
}

contract DealersRandomnessTest is Test {
    DealersRandomness public randomness;
    MockResolver public resolverA;
    MockResolver public resolverB;
    address public owner;
    address public outsider;

    function setUp() public {
        owner = address(this);
        outsider = makeAddr("outsider");

        randomness = new DealersRandomness();
        resolverA = new MockResolver(randomness);
        resolverB = new MockResolver(randomness);

        randomness.authorizeResolver(address(resolverA), true);
        randomness.authorizeResolver(address(resolverB), true);
    }

    function test_commit_revertsWhenNotAuthorized() public {
        vm.prank(outsider);
        vm.expectRevert(DealersRandomness.NotAuthorized.selector);
        randomness.commit();
    }

    function test_commit_monotonicSeq() public {
        uint64 s1 = resolverA.commit();
        uint64 s2 = resolverA.commit();
        uint64 s3 = resolverB.commit();
        assertEq(s2, s1 + 1);
        assertEq(s3, s2 + 1);
    }

    function test_commit_storesRevealBlock() public {
        uint64 startBlock = uint64(block.number);
        uint64 seq = resolverA.commit();
        assertEq(randomness.revealBlockOf(seq), startBlock + randomness.REVEAL_OFFSET());
    }

    function test_reveal_revertsUnknownSeq() public {
        vm.expectRevert(DealersRandomness.UnknownSeq.selector);
        randomness.reveal(99999);
    }

    function test_reveal_revertsTooEarlySameBlock() public {
        uint64 seq = resolverA.commit();
        vm.expectRevert(DealersRandomness.TooEarly.selector);
        resolverA.reveal(seq);
    }

    function test_reveal_revertsTooEarlyAtRevealBlock() public {
        uint64 seq = resolverA.commit();
        // Move to exactly the reveal block — still TooEarly (need block.number > rb)
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()));
        vm.expectRevert(DealersRandomness.TooEarly.selector);
        resolverA.reveal(seq);
    }

    function test_reveal_succeedsJustAfterRevealBlock() public {
        uint64 seq = resolverA.commit();
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()) + 1);
        uint256 rand = resolverA.reveal(seq);
        // Foundry's blockhash for vm.roll'd blocks may be 0; we assert it's a deterministic
        // function of (blockhash, seq, msg.sender). Same call again returns same value.
        uint256 randAgain = resolverA.reveal(seq);
        assertEq(rand, randAgain);
    }

    function test_reveal_revertsExpired() public {
        uint64 seq = resolverA.commit();
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()) + uint256(randomness.EXPIRY_WINDOW()) + 1);
        vm.expectRevert(DealersRandomness.Expired.selector);
        resolverA.reveal(seq);
    }

    function test_reveal_atExpiryEdgeStillValid() public {
        uint64 seq = resolverA.commit();
        uint256 rb = randomness.revealBlockOf(seq);
        // Last valid block: rb + EXPIRY_WINDOW
        vm.roll(rb + uint256(randomness.EXPIRY_WINDOW()));
        // Should not revert
        resolverA.reveal(seq);
    }

    function test_reveal_differentMsgSenderProducesDifferentRand() public {
        uint64 seq = resolverA.commit();
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()) + 1);
        uint256 randA = resolverA.reveal(seq);
        uint256 randB = resolverB.reveal(seq);
        // Different consumers calling reveal on the same seq should get different rands
        // because msg.sender is mixed into the digest.
        assertTrue(randA != randB, "consumers must see different rand");
    }

    function test_isExpired_falseBeforeWindow() public {
        uint64 seq = resolverA.commit();
        assertFalse(randomness.isExpired(seq));
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()) + 1);
        assertFalse(randomness.isExpired(seq));
    }

    function test_isExpired_trueAfterWindow() public {
        uint64 seq = resolverA.commit();
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()) + uint256(randomness.EXPIRY_WINDOW()) + 1);
        assertTrue(randomness.isExpired(seq));
    }

    function test_isExpired_falseForUnknownSeq() public view {
        assertFalse(randomness.isExpired(99999));
    }

    function test_authorizeResolver_onlyOwner() public {
        address newResolver = makeAddr("newResolver");
        vm.prank(outsider);
        vm.expectRevert();
        randomness.authorizeResolver(newResolver, true);
    }

    function test_authorizeResolver_revertsZero() public {
        vm.expectRevert(DealersRandomness.InvalidAddress.selector);
        randomness.authorizeResolver(address(0), true);
    }

    function test_authorizeResolver_revoke() public {
        randomness.authorizeResolver(address(resolverA), false);
        vm.expectRevert(DealersRandomness.NotAuthorized.selector);
        resolverA.commit();
    }

    function test_isAuthorizedResolver() public view {
        assertTrue(randomness.isAuthorizedResolver(address(resolverA)));
        assertTrue(randomness.isAuthorizedResolver(address(resolverB)));
        assertFalse(randomness.isAuthorizedResolver(outsider));
    }
}
