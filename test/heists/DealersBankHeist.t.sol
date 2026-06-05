// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./HeistsBaseTest.sol";
import {IDealersHeists} from "../../src/core/IDealersHeists.sol";

/**
 * @dev CONCEPT — OUT OF AUDIT SCOPE. Exercises the bank-heist concept module (DealersBankHeist),
 *      which is not deployed to mainnet and is not part of the audited rollout.
 */
contract DealersBankHeistTest is HeistsBaseTest {
    uint256 internal tA;
    uint256 internal tB;

    function setUp() public override {
        super.setUp();
        vm.deal(address(bankHeist), 10 ether); // vault accrued from game fees
        tA = _readyDealer(player1, 100000);
        tB = _readyDealer(player2, 100000);
    }

    function _close() internal {
        vm.warp(bankHeist.genesisStart() + bankHeist.prepDuration() + 1);
    }

    /// @dev Bump a dealer's activity by one heist run (heistRuns++) after they entered.
    function _bumpActivity(address player, uint256 tid) internal {
        vm.prank(player);
        heists.startHeist(tid, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
    }

    /// @dev Grind one unit of activity cleanly (start + abandon → heistRuns++, slot freed, cash refunded).
    function _grind(address player, uint256 tid) internal {
        vm.startPrank(player);
        uint256 hid = heists.startHeist(tid, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        heists.abandonHeist(hid);
        vm.stopPrank();
    }

    /// @dev Freeze all entrant weights for event 0 in one call.
    function _snapshot() internal {
        bankHeist.snapshotWeights(0, type(uint256).max);
    }

    // ---------------------------------------------------------------- entry

    function test_enter_sinksCashAndSnapshots() public {
        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.enter(tA);

        assertEq(core.getCashBalance(tA), cashBefore - bankHeist.entryFee(), "CASH sunk");
        assertEq(bankHeist.getEvent(0).entryCount, 1);
        assertEq(bankHeist.activityAtEntry(0, tA), bankHeist.activityOf(tA), "snapshot taken");
        // No ETH, no attempt consumed.
        assertEq(core.getGameState(tA).dailyAttemptsRemaining, 5, "no attempt spent");
    }

    function test_enter_revertsBelowVaultFloor() public {
        vm.deal(address(bankHeist), 0); // drain
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.VaultBelowFloor.selector);
        bankHeist.enter(tA);
    }

    function test_enter_revertsOnDoubleEntry() public {
        vm.startPrank(player1);
        bankHeist.enter(tA);
        vm.expectRevert(DealersBankHeist.AlreadyEntered.selector);
        bankHeist.enter(tA);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- skip / refund

    function test_skip_belowMinEntrants_thenRefund() public {
        vm.prank(player1);
        bankHeist.enter(tA); // only 1 entrant, min is 2
        _close();
        bankHeist.requestDraw(0);
        assertTrue(bankHeist.getEvent(0).skipped, "event skipped");

        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + bankHeist.entryFee(), "CASH refunded");
    }

    // ---------------------------------------------------------------- draw + settle

    function test_settle_weightedDrawPaysActiveEntrants() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);

        // Both gain one unit of activity inside the window.
        _bumpActivity(player1, tA);
        _bumpActivity(player2, tB);
        assertEq(bankHeist.eventWeight(0, tA), 1);
        assertEq(bankHeist.eventWeight(0, tB), 1);

        _close();
        bankHeist.requestDraw(0);
        _snapshot();
        uint64 seq = mockEntropy.nextSeq() - 1;
        mockEntropy.fire(seq, bytes32(uint256(0xABCDEF)));
        assertTrue(bankHeist.getEvent(0).seeded);

        uint256 prize = uint256(10 ether) * bankHeist.eventCapBps() / 10000; // 2.5 ETH
        bankHeist.settle(0);

        // 2 entrants → ranks 0 (60%) and 1 (30%) awarded; rank 2 unfilled.
        uint256 distributed = bankHeist.winnings(tA) + bankHeist.winnings(tB);
        assertEq(distributed, prize * 9000 / 10000, "60%+30% distributed");
        assertGt(bankHeist.winnings(tA), 0);
        assertGt(bankHeist.winnings(tB), 0);
        assertEq(bankHeist.totalUnclaimedWinnings(), distributed);
    }

    function test_claimWinnings_transfersEth() public {
        _seedAndSettleTwoWinners();

        uint256 owed = bankHeist.winnings(tA);
        assertGt(owed, 0);
        uint256 balBefore = player1.balance;
        vm.prank(player1);
        bankHeist.claimWinnings(tA);
        assertEq(player1.balance, balBefore + owed, "winnings paid to owner");
        assertEq(bankHeist.winnings(tA), 0);
    }

    function test_zeroActivity_entrantsGetNothing() public {
        // Both enter but neither plays → totalWeight 0 → no winners, prize rolls over.
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _close();
        bankHeist.requestDraw(0);
        _snapshot();
        mockEntropy.fire(mockEntropy.nextSeq() - 1, bytes32(uint256(7)));
        bankHeist.settle(0);

        assertEq(bankHeist.winnings(tA), 0);
        assertEq(bankHeist.winnings(tB), 0);
        assertEq(bankHeist.totalUnclaimedWinnings(), 0, "prize stays in vault");
    }

    function test_refund_onRevealTimeout() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _close();
        bankHeist.requestDraw(0); // Pyth requested but callback never fires

        vm.warp(block.timestamp + bankHeist.refundTimeout() + 1);
        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + bankHeist.entryFee(), "refunded after timeout");
    }

    function _seedAndSettleTwoWinners() internal {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _bumpActivity(player1, tA);
        _bumpActivity(player2, tB);
        _close();
        bankHeist.requestDraw(0);
        _snapshot();
        mockEntropy.fire(mockEntropy.nextSeq() - 1, bytes32(uint256(0xABCDEF)));
        bankHeist.settle(0);
    }

    // ---------------------------------------------------------------- V-001: weight freeze

    function test_v001_postCloseGrindDoesNotInflateWeight() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _grind(player1, tA); // equal in-window activity
        _grind(player2, tB);

        _close();
        bankHeist.requestDraw(0);
        _snapshot(); // freeze: both weight 1
        assertEq(bankHeist.weightAt(0, 0), 1);
        assertEq(bankHeist.weightAt(0, 1), 1);
        assertEq(bankHeist.getEvent(0).totalWeight, 2);

        // Attacker grinds AFTER close + snapshot.
        uint64 liveBefore = bankHeist.activityOf(tA);
        _grind(player1, tA);
        assertGt(bankHeist.activityOf(tA), liveBefore, "live activity rose");

        // Frozen weight is untouched — the post-close grind buys nothing.
        assertEq(bankHeist.weightAt(0, 0), 1, "frozen weight ignores post-snapshot grind");
        assertEq(bankHeist.getEvent(0).totalWeight, 2, "totalWeight frozen");
    }

    function test_settle_revertsWithoutWeightSnapshot() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _grind(player1, tA);
        _close();
        bankHeist.requestDraw(0);
        mockEntropy.fire(mockEntropy.nextSeq() - 1, bytes32(uint256(1)));
        vm.expectRevert(DealersBankHeist.WeightsNotReady.selector);
        bankHeist.settle(0);
    }

    function test_snapshotWeights_paginates() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _grind(player1, tA);
        _grind(player2, tB);
        _close();
        bankHeist.requestDraw(0);

        bankHeist.snapshotWeights(0, 1);
        assertEq(bankHeist.getEvent(0).weightCursor, 1);
        bankHeist.snapshotWeights(0, 1);
        assertEq(bankHeist.getEvent(0).weightCursor, 2);
        assertEq(bankHeist.getEvent(0).totalWeight, 2);
        vm.expectRevert(DealersBankHeist.WeightsAlreadyDone.selector);
        bankHeist.snapshotWeights(0, 1);
    }

    // ---------------------------------------------------------------- V-002: refund lifecycle

    function test_v002_refundedEventCannotSettle() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _grind(player1, tA);
        _close();
        bankHeist.requestDraw(0); // seed never arrives

        vm.warp(block.timestamp + bankHeist.refundTimeout() + 1);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA); // stuck-draw refund flips event to skipped (terminal)
        assertTrue(bankHeist.getEvent(0).skipped);

        // A late Pyth callback is ignored (event skipped) and settle can never run.
        mockEntropy.fire(mockEntropy.nextSeq() - 1, bytes32(uint256(0xABCDEF)));
        assertFalse(bankHeist.getEvent(0).seeded, "late seed ignored");
        vm.expectRevert(DealersBankHeist.NotSeeded.selector);
        bankHeist.settle(0);
    }

    function test_v002_cannotRequestDrawAfterGrace() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _close();
        vm.warp(block.timestamp + bankHeist.refundTimeout() + 1);
        vm.expectRevert(DealersBankHeist.DrawWindowClosed.selector);
        bankHeist.requestDraw(0);
    }

    function test_v002_refundThenDrawBlocked() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _close();
        vm.warp(block.timestamp + bankHeist.refundTimeout() + 1); // abandoned (no draw requested)
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertTrue(bankHeist.getEvent(0).skipped);
        // No refund-then-draw free roll.
        vm.expectRevert(DealersBankHeist.AlreadyResolved.selector);
        bankHeist.requestDraw(0);
    }

    // ---------------------------------------------------------------- V-003: locked entry fee

    function test_v003_refundUsesLockedFeeNotMutatedGlobal() public {
        vm.prank(player1);
        bankHeist.enter(tA); // locks event 0 fee at 5000

        bankHeist.setCycleConfig(9000, 0); // owner raises the global fee after entries exist
        assertEq(bankHeist.entryFee(), 9000);
        assertEq(bankHeist.eventEntryFee(0), 5000, "event fee locked at creation");

        _close();
        vm.warp(block.timestamp + bankHeist.refundTimeout() + 1); // abandoned → refundable
        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + 5000, "refunds the locked 5000, not the new 9000");
    }

    // ---------------------------------------------------------------- V-004: settle fee cap

    function test_v004_settleFeeCappedToAvailableVault() public {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
        _grind(player1, tA);
        _grind(player2, tB);

        uint16[] memory split = new uint16[](3);
        split[0] = 6000;
        split[1] = 3000;
        split[2] = 1000;
        bankHeist.setPrizeConfig(2500, 0.1 ether, 2, 5000, 0, 100 ether, 7 days, split); // settleFee = 100 ETH

        _close();
        bankHeist.requestDraw(0);
        _snapshot();
        mockEntropy.fire(mockEntropy.nextSeq() - 1, bytes32(uint256(0xABCDEF)));

        address keeper = makeAddr("keeper");
        uint256 avail = bankHeist.availableVault();
        uint256 balBefore = address(bankHeist).balance;
        vm.prank(keeper);
        bankHeist.settle(0); // 100 ETH fee capped to availableVault; prize 0

        assertEq(balBefore - address(bankHeist).balance, avail, "fee capped to availableVault");
        assertEq(keeper.balance, avail, "keeper receives only the capped fee");
        assertGe(address(bankHeist).balance, bankHeist.totalUnclaimedWinnings(), "winnings reserve never breached");
    }
}
