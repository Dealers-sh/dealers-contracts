// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";
import "../../src/core/DealersPVE.sol";
import "../../src/core/DealersPVP.sol";
import "../../src/core/DealersActions.sol";

contract CommitRevealEdgeCasesTest is BaseTest {
    uint256 internal tokenA;
    uint256 internal tokenB;

    function setUp() public override {
        super.setUp();
        tokenA = _mintAndInitialize(player1);
        tokenB = _mintAndInitialize(player2);

        // Move both out of safe house so they can play
        vm.startPrank(owner);
        core.authorizeContract(address(this), true);
        vm.stopPrank();
        core.moveToArea(tokenA, 1);
        core.moveToArea(tokenB, 1);

        // Ensure both have funds for gameplay
        core.addCash(tokenA, 10_000);
        core.addCash(tokenB, 10_000);
        core.updateDrugBalance(tokenA, 4, 1_000);
        core.updateDrugBalance(tokenB, 4, 1_000);
    }

    // =========================================================================
    //                  PVE EXPIRY — TREATED AS LOSS (audit C-1)
    // =========================================================================

    function test_pveExpiry_buyStakeForfeitedAsLoss() public {
        uint256 amount = 5;
        uint256 buyPrice = 1;
        uint256 stake = amount * buyPrice;

        uint256 cashBefore = core.getCashBalance(tokenA);
        uint8 heatBefore = core.getGameState(tokenA).heatLevel;
        IDealersPVE.PveStats memory statsBefore = pve.getDealerPveStats(tokenA);

        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, amount);

        assertEq(core.getCashBalance(tokenA), cashBefore - stake, "stake debited at commit");

        _advanceToExpired();
        pve.resolveGame(seq);

        assertEq(core.getCashBalance(tokenA), cashBefore - stake, "stake forfeited on expiry");
        assertEq(core.getGameState(tokenA).heatLevel, heatBefore + 1, "heat incremented");
        assertEq(pve.getDealerPveStats(tokenA).losses, statsBefore.losses + 1, "loss counted");
        assertEq(pve.activePveRoundOf(tokenA), 0, "round cleared");
    }

    function test_pveExpiry_sellStakeForfeitedAsLoss() public {
        uint256 amount = 10;
        uint256 drugsBefore = core.getDrugBalance(tokenA, 4);
        uint8 heatBefore = core.getGameState(tokenA).heatLevel;
        IDealersPVE.PveStats memory statsBefore = pve.getDealerPveStats(tokenA);

        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.SELL, 4, amount);

        assertEq(core.getDrugBalance(tokenA, 4), drugsBefore - amount, "drugs debited at commit");

        _advanceToExpired();
        pve.resolveGame(seq);

        assertEq(core.getDrugBalance(tokenA, 4), drugsBefore - amount, "drugs forfeited on expiry");
        assertEq(core.getGameState(tokenA).heatLevel, heatBefore + 1, "heat incremented");
        assertEq(pve.getDealerPveStats(tokenA).losses, statsBefore.losses + 1, "loss counted");
        assertEq(pve.activePveRoundOf(tokenA), 0, "round cleared");
    }

    function test_pveExpiry_attemptIsForfeit() public {
        IDealersCore.GameState memory before = core.getGameState(tokenA);

        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);

        _advanceToExpired();
        pve.resolveGame(seq);

        IDealersCore.GameState memory afterState = core.getGameState(tokenA);
        assertEq(
            afterState.dailyAttemptsRemaining,
            before.dailyAttemptsRemaining - 1,
            "attempt forfeit on expiry"
        );
    }

    function test_pveExpiry_appliesScaledRepLoss() public {
        // Use a large stake so the loss penalty does not round to zero after stake scaling.
        // weed sellPrice in Manhattan is configured via BaseTest; we only need a stake
        // big enough that (lossPenalty * stake) / repStakeDivisor != 0.
        core.updateDrugBalance(tokenA, 4, 10_000);
        uint256 amount = 1_000;

        uint256 repBefore = core.getGameState(tokenA).reputation;

        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.SELL, 4, amount);

        _advanceToExpired();
        pve.resolveGame(seq);

        assertLt(core.getGameState(tokenA).reputation, repBefore, "rep dropped on expired loss");
    }

    // =========================================================================
    //                            ROUND-PENDING GUARD
    // =========================================================================

    function test_pve_doubleCommit_revertsRoundPending() public {
        vm.prank(player1);
        pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);

        vm.prank(player1);
        vm.expectRevert(DealersPVE.RoundPending.selector);
        pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);
    }

    function test_pve_canCommitAgainAfterResolve() public {
        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);

        // Force a lossy outcome (no arrest, no win) by crafting rand
        uint16 noArrest = 999;   // jailRng % 1000 high = no arrest
        uint16 lossOutcome = 99; // outcomeRng % 100 = LOSS branch
        uint256 rand = _packRand(noArrest, lossOutcome, 0, 0, 0);
        _mockReveal(seq, rand);

        _advanceToRevealable(seq);
        pve.resolveGame(seq);

        // After resolve, dealer should be able to commit again
        vm.prank(player1);
        pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);
    }

    // =========================================================================
    //                       ANYONE-CAN-RESOLVE
    // =========================================================================

    function test_pve_thirdPartyCanResolve() public {
        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);

        uint16 noArrest = 999;
        uint16 lossOutcome = 99;
        _mockReveal(seq, _packRand(noArrest, lossOutcome, 0, 0, 0));
        _advanceToRevealable(seq);

        // Player2 (a third party) resolves player1's round
        vm.prank(player2);
        pve.resolveGame(seq);
        // No revert => success
    }

    // =========================================================================
    //                       BREAKOUT EXPIRY
    // =========================================================================

    function test_breakout_expiry_preservesDailyLockout() public {
        vm.warp(block.timestamp + 2 days);

        core.forceMove(tokenA, core.JAIL_AREA());

        vm.prank(player1);
        uint64 seq = actions.commitBreakout(tokenA);

        uint32 lastAttemptAfterCommit = core.getGameState(tokenA).lastBreakoutAttempt;
        assertGt(lastAttemptAfterCommit, 0, "lockout applied at commit");

        _advanceToExpired();
        actions.resolveBreakout(seq);

        // Lockout still in place after expired round
        assertEq(
            core.getGameState(tokenA).lastBreakoutAttempt,
            lastAttemptAfterCommit,
            "lockout preserved after expiry"
        );

        // Same-day re-commit should still revert
        vm.prank(player1);
        vm.expectRevert(DealersActions.BreakoutAlreadyAttemptedToday.selector);
        actions.commitBreakout(tokenA);
    }

    // =========================================================================
    //                       UNKNOWN-ROUND GUARD
    // =========================================================================

    function test_pve_resolveUnknownSeq_reverts() public {
        vm.expectRevert(DealersPVE.UnknownRound.selector);
        pve.resolveGame(99999);
    }

    function test_pvp_resolveUnknownSeq_reverts() public {
        vm.expectRevert(DealersPVP.UnknownRound.selector);
        pvp.resolveAttack(99999);
    }

    function test_breakout_resolveUnknownSeq_reverts() public {
        vm.expectRevert(DealersActions.UnknownRound.selector);
        actions.resolveBreakout(99999);
    }

    // =========================================================================
    //                       REVEAL TIMING ROLLBACK
    // =========================================================================

    function test_pve_revealTooEarly_revertsAndIsRetryable() public {
        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);

        // Land exactly on revealBlock so block.number == rb. DealersRandomness.reveal
        // reverts on `block.number <= rb`, so this triggers TooEarly.
        vm.roll(block.number + uint256(randomness.REVEAL_OFFSET()));

        vm.expectRevert(DealersRandomness.TooEarly.selector);
        pve.resolveGame(seq);

        // Round must still be pending — the revert rolled back the early `delete`s.
        assertEq(pve.activePveRoundOf(tokenA), seq, "round still pending after TooEarly revert");

        // One more block puts us past rb; mock reveal and resolve cleanly.
        vm.roll(block.number + 1);
        _mockReveal(seq, _packRand(ARREST_RNG_NO, OUTCOME_RNG_LOSS, 0, 0, 0));
        pve.resolveGame(seq);

        assertEq(pve.activePveRoundOf(tokenA), 0, "round cleared after successful resolve");

        // Dealer can commit a new round.
        vm.prank(player1);
        pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, 5);
    }

    // =========================================================================
    //                ARREST REVERT DURING RESOLVE — RECOVERY VIA EXPIRY
    // =========================================================================

    function test_pve_arrestRevertDuringResolve_recoverableViaExpiry() public {
        // Heat must be > 0 for rollJailCheck to ever return true.
        // jailChance = heat * jailChancePerHeat (default 5); arrestRng=0 < jailChance forces arrest.
        core.setHeatLevel(tokenA, 1);

        uint256 amount = 5;
        uint256 buyPrice = 1; // weed in Manhattan
        uint256 stake = amount * buyPrice;
        uint256 cashBefore = core.getCashBalance(tokenA);

        vm.prank(player1);
        uint64 seq = pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, amount);

        assertEq(core.getCashBalance(tokenA), cashBefore - stake, "stake debited at commit");

        // Force jail roll true via arrestRng=0, then revoke jailer auth so arrest() reverts.
        _mockReveal(seq, _packRand(ARREST_RNG_YES, OUTCOME_RNG_LOSS, 0, 0, 0));
        vm.prank(owner);
        actions.authorizeJailer(address(pve), false);

        _advanceToRevealable(seq);

        vm.expectRevert(DealersActions.NotAuthorizedJailer.selector);
        pve.resolveGame(seq);

        // Round still pending — the deletes were rolled back along with the revert.
        assertEq(pve.activePveRoundOf(tokenA), seq, "round still pending after arrest revert");

        // Recovery path: wait for expiry, resolve clears the round as a loss
        // (stake stays forfeited per C-1 fix; the slot frees so the dealer can play again).
        _advanceToExpired();
        pve.resolveGame(seq);

        assertEq(pve.activePveRoundOf(tokenA), 0, "round cleared after expiry resolve");
        assertEq(core.getCashBalance(tokenA), cashBefore - stake, "stake forfeited via expiry-as-loss");

        vm.prank(player1);
        pve.commitGame(tokenA, 0, IDealersPVE.HustleType.BUY, 4, amount);
    }

    // =========================================================================
    //                  PVP EXPIRY — TREATED AS ATTACKER LOSS (audit H-2)
    // =========================================================================

    function _permissivePvpConfig() internal {
        vm.prank(owner);
        pvp.setPVPConfig(IDealersPVP.PVPConfig({
            minReputation: 0,
            baseWinChance: 50,
            minWinChance: 25,
            maxWinChance: 75,
            maxAttacksPerDay: 3,
            drugStealPercent: 2,
            cashStealPercent: 1,
            rarityWeightCommon: 50,
            rarityWeightUncommon: 30,
            rarityWeightRare: 20,
            repRangePercent: 100,
            defenderRepBonus: 2,
            repRangeThreshold: 0
        }));
    }

    function test_pvpExpiry_appliesAttackerLossOutcome() public {
        _permissivePvpConfig();

        uint256 atkRepBefore = core.getGameState(tokenA).reputation;
        uint256 defRepBefore = core.getGameState(tokenB).reputation;
        uint8 atkHeatBefore = core.getGameState(tokenA).heatLevel;
        IDealersPVP.PvpStats memory atkStatsBefore = pvp.getDealerPvpStats(tokenA);
        IDealersPVP.PvpStats memory defStatsBefore = pvp.getDealerPvpStats(tokenB);

        vm.prank(player1);
        uint64 seq = pvp.commitAttack(tokenA, tokenB);

        _advanceToExpired();
        pvp.resolveAttack(seq);

        assertEq(pvp.activePvpRoundOf(tokenA), 0, "round cleared on expiry");
        assertEq(core.getGameState(tokenA).heatLevel, atkHeatBefore + 1, "attacker heat incremented");
        assertLt(core.getGameState(tokenA).reputation, atkRepBefore, "attacker rep dropped");
        assertEq(core.getGameState(tokenB).reputation, defRepBefore + 2, "defender got rep bonus");
        assertEq(
            pvp.getDealerPvpStats(tokenA).attackLosses,
            atkStatsBefore.attackLosses + 1,
            "attacker loss counted"
        );
        assertEq(
            pvp.getDealerPvpStats(tokenB).defendWins,
            defStatsBefore.defendWins + 1,
            "defender win counted"
        );
    }

    function test_pvpExpiry_refundsDefenderSlot() public {
        _permissivePvpConfig();

        uint256 slotsBefore = pvp.attacksReceivedToday(tokenB);
        assertEq(slotsBefore, 0);

        vm.prank(player1);
        uint64 seq = pvp.commitAttack(tokenA, tokenB);
        assertEq(pvp.attacksReceivedToday(tokenB), 1, "slot consumed at commit");

        _advanceToExpired();
        pvp.resolveAttack(seq);

        assertEq(pvp.attacksReceivedToday(tokenB), 0, "slot refunded on expiry");
    }

    function test_pvpExpiry_attackerJailedExternally_noExtraPunishment() public {
        _permissivePvpConfig();

        vm.prank(player1);
        uint64 seq = pvp.commitAttack(tokenA, tokenB);

        core.forceMove(tokenA, core.JAIL_AREA());

        uint256 atkRepBeforeExpiry = core.getGameState(tokenA).reputation;
        uint8 atkHeatBeforeExpiry = core.getGameState(tokenA).heatLevel;
        IDealersPVP.PvpStats memory atkStatsBeforeExpiry = pvp.getDealerPvpStats(tokenA);

        _advanceToExpired();
        pvp.resolveAttack(seq);

        assertEq(pvp.activePvpRoundOf(tokenA), 0, "round cleared");
        assertEq(core.getGameState(tokenA).reputation, atkRepBeforeExpiry, "no extra rep loss on jailed attacker");
        assertEq(core.getGameState(tokenA).heatLevel, atkHeatBeforeExpiry, "no extra heat on jailed attacker");
        assertEq(
            pvp.getDealerPvpStats(tokenA).attackLosses,
            atkStatsBeforeExpiry.attackLosses,
            "no extra loss recorded on jailed attacker"
        );
    }

    // =========================================================================
    //              PVP DEFENDER STATE DRIFT — STALE-OK BEHAVIOR
    // =========================================================================

    function test_pvp_resolveAfterDefenderJailedExternally_succeeds() public {
        // Allow attacks with zero reputation and wide rep range so fresh dealers can fight.
        vm.prank(owner);
        pvp.setPVPConfig(IDealersPVP.PVPConfig({
            minReputation: 0,
            baseWinChance: 50,
            minWinChance: 25,
            maxWinChance: 75,
            maxAttacksPerDay: 3,
            drugStealPercent: 2,
            cashStealPercent: 1,
            rarityWeightCommon: 50,
            rarityWeightUncommon: 30,
            rarityWeightRare: 20,
            repRangePercent: 100,
            defenderRepBonus: 2,
            repRangeThreshold: 0
        }));

        // Both dealers in Manhattan from setUp. Commit attack while defender is healthy.
        vm.prank(player1);
        uint64 seq = pvp.commitAttack(tokenA, tokenB);

        assertEq(pvp.activePvpRoundOf(tokenA), seq, "round pending after commit");

        // Defender jailed externally between commit and resolve.
        core.forceMove(tokenB, core.JAIL_AREA());
        assertTrue(_isInJail(tokenB), "defender jailed externally");

        // Attacker-loss outcome: jailRng=999 (no arrest), winRng=99 (loses).
        // Battle resolves using commit-time defender armor; live defender state is not re-validated.
        _mockReveal(seq, _packRand(999, 99, 0, 0, 0));
        _advanceToRevealable(seq);

        pvp.resolveAttack(seq);

        assertEq(pvp.activePvpRoundOf(tokenA), 0, "round cleared after resolve");
        assertEq(core.getGameState(tokenB).currentArea, core.JAIL_AREA(), "defender still in jail");
    }

    // =========================================================================
    //         L-01 — RESOLVE BREAKOUT MUST NOT TELEPORT AN UN-JAILED DEALER
    // =========================================================================

    function test_breakout_skipsTeleportIfDealerLeftJail() public {
        vm.warp(block.timestamp + 2 days);

        // Jail dealer A, commit a breakout, then move them out of jail (e.g. via
        // payBail in practice; modelled here with a direct forceMove since the test
        // is authorized on core). Resolve should not teleport them back.
        core.forceMove(tokenA, core.JAIL_AREA());

        vm.prank(player1);
        uint64 seq = actions.commitBreakout(tokenA);

        uint8 freeArea = 3;
        core.forceMove(tokenA, freeArea);
        assertEq(core.getGameState(tokenA).currentArea, freeArea, "dealer left jail before resolve");

        // rand=0 ensures success branch (rand % 100 < breakoutSuccessChance=50)
        _mockReveal(seq, 0);
        _advanceToRevealable(seq);

        actions.resolveBreakout(seq);

        assertEq(
            core.getGameState(tokenA).currentArea,
            freeArea,
            "L-01: no teleport after dealer left jail"
        );
    }

    // =========================================================================
    //         L-02 — commitWantedPoster MUST REJECT A JAILED DEALER
    // =========================================================================

    function test_wantedPoster_rejectsJailedDealer() public {
        vm.warp(block.timestamp + 2 days);

        core.setHeatLevel(tokenA, 3);
        core.forceMove(tokenA, core.JAIL_AREA());

        vm.prank(player1);
        vm.expectRevert(DealersActions.DealerInJail.selector);
        actions.commitWantedPoster(tokenA);
    }

}
