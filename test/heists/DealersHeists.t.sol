// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./HeistsBaseTest.sol";
import {IDealersHeists} from "../../src/core/IDealersHeists.sol";

contract DealersHeistsTest is HeistsBaseTest {
    uint256 internal tokenId;

    function setUp() public override {
        super.setUp();
        tokenId = _readyDealer(player1, 100000);
    }

    function _start(IDealersHeists.HeistFamily family, uint8 diff, bool eth) internal returns (uint256 id) {
        uint256 value = eth ? heists.ethAddOn() : 0;
        vm.prank(player1);
        id = heists.startHeist{value: value}(tokenId, family, diff, eth);
    }

    // ---------------------------------------------------------------- entry

    function test_startHeist_debitsStakeAndAttempt() public {
        uint256 cashBefore = core.getCashBalance(tokenId);
        uint8 attemptsBefore = core.getGameState(tokenId).dailyAttemptsRemaining;

        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);

        assertEq(core.getCashBalance(tokenId), cashBefore - SMALL_CASH, "stake debited");
        assertEq(core.getGameState(tokenId).dailyAttemptsRemaining, attemptsBefore - 1, "one attempt");
        assertEq(heists.activeHeist(tokenId), id, "active set");
        assertEq(heists.heistRuns(tokenId), 1, "run counted");
        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.PRE_STAGE));
    }

    function test_startHeist_revertsWhenAlreadyActive() public {
        _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        vm.prank(player1);
        vm.expectRevert(DealersHeists.HeistActive.selector);
        heists.startHeist(tokenId, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
    }

    function test_startHeist_revertsBelowRepGate() public {
        // BIG requires 300 rep; fresh dealer is below it.
        vm.prank(player1);
        vm.expectRevert(DealersHeists.RepTooLow.selector);
        heists.startHeist(tokenId, IDealersHeists.HeistFamily.CASH, DIFF_BIG, false);
    }

    function test_startHeist_revertsInSafeHouse() public {
        uint256 t2 = _readyDealer(player2, 10000);
        // Force the dealer into the safe house (area 0); players can't enter it voluntarily.
        core.authorizeContract(address(this), true);
        core.forceMove(t2, core.SAFE_HOUSE_AREA());
        core.authorizeContract(address(this), false);

        vm.prank(player2);
        vm.expectRevert(DealersHeists.DealerInSafeHouse.selector);
        heists.startHeist(t2, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
    }

    function test_abandon_refundsCash() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        uint256 cashBefore = core.getCashBalance(tokenId);
        vm.prank(player1);
        heists.abandonHeist(id);
        assertEq(core.getCashBalance(tokenId), cashBefore + SMALL_CASH, "stake refunded");
        assertEq(heists.activeHeist(tokenId), 0, "slot freed");
        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.ABANDONED));
    }

    // ---------------------------------------------------------------- push-your-luck

    function test_cashOut_atStage2_paysMultiplier() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 1 clean
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 2 clean

        uint256 pot = heists.getHeist(id).currentPot;
        // controlled reveal (bits>>32 = 0) rolls the minimum stage-2 multiplier: 500 * 18000/10000 = 900
        assertEq(pot, uint256(SMALL_CASH) * 18000 / 10000, "stage 2 pot (min roll)");

        uint256 cashBefore = core.getCashBalance(tokenId);
        vm.prank(player1);
        heists.cashOut(id);
        assertEq(core.getCashBalance(tokenId), cashBefore + pot, "pot paid");
        assertEq(heists.activeHeist(tokenId), 0, "slot freed");
        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.CASHED_OUT));
    }

    function test_randomizedMultiplier_higherRollHigherPot() public {
        // Same stage, higher RNG slice (bits>>32) → multiplier nearer the max of the range.
        uint256 lowId = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, lowId, RAND_WIN_NO_JP);
        _playStage(player1, lowId, RAND_WIN_NO_JP); // min roll
        uint256 lowPot = heists.getHeist(lowId).currentPot;

        uint256 t2 = _readyDealer(player2, 100000);
        uint256 hiId;
        vm.prank(player2);
        hiId = heists.startHeist(t2, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player2, hiId, RAND_WIN_NO_JP);
        // bits>>32 == (max-min) for stage 2 (10000) → rolls exactly the stage-2 max multiplier.
        _playStage(player2, hiId, (uint256(50) << 16) | (uint256(10000) << 32));
        uint256 hiPot = heists.getHeist(hiId).currentPot;

        assertGt(hiPot, lowPot, "higher RNG yields a bigger pot");
        assertEq(hiPot, uint256(SMALL_CASH) * 28000 / 10000, "stage-2 max roll");
    }

    function test_fullPush_autoCashesOutAtStage5() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        uint256 cashBefore = core.getCashBalance(tokenId);
        for (uint256 i = 0; i < 5; i++) {
            _playStage(player1, id, RAND_WIN_NO_JP);
        }
        // stage-5 min multiplier roll: 500 * 100000/10000 = 5000, auto-paid
        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.CASHED_OUT));
        assertEq(core.getCashBalance(tokenId), cashBefore + (uint256(SMALL_CASH) * 100000 / 10000), "stage5 pot");
        assertEq(heists.activeHeist(tokenId), 0);
    }

    function test_cashOut_revertsAtPrepStage() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // clean stage 1 → REVEALED_WIN but it's prep
        vm.prank(player1);
        vm.expectRevert(DealersHeists.CannotCashYet.selector);
        heists.cashOut(id);
    }

    function test_cashOut_grantsSmallRep() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP);
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 2
        uint256 repBefore = core.getGameState(tokenId).reputation;
        vm.prank(player1);
        heists.cashOut(id);
        // stage-2 rep reward = 2 (PVP-scale, far below PVE)
        assertEq(core.getGameState(tokenId).reputation, repBefore + 6, "small rep on cash-out");
    }

    function test_bust_forfeitsStakeAddsHeatAndDocksRep() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 1 clean
        uint256 cashBefore = core.getCashBalance(tokenId);
        uint8 heatBefore = core.getGameState(tokenId).heatLevel;
        uint256 repBefore = core.getGameState(tokenId).reputation;
        _playStage(player1, id, RAND_LOSS); // stage 2 → bust

        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.BUSTED));
        assertEq(heists.getHeist(id).currentPot, 0, "pot zeroed");
        assertEq(core.getCashBalance(tokenId), cashBefore, "no payout");
        assertEq(heists.activeHeist(tokenId), 0, "slot freed");
        assertEq(core.getGameState(tokenId).heatLevel, heatBefore + 1, "bust raises heat");
        assertEq(core.getGameState(tokenId).reputation, repBefore - heists.bustRepPenalty(), "bust docks rep");
        assertFalse(core.getGameState(tokenId).isJailed, "cold dealer not jailed on bust");
    }

    function test_bust_rollsArrestWhenHot() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // clean stage 1
        _setHeat(tokenId, 3); // hot enough that the heat-scaled jail check can hit
        assertFalse(core.getGameState(tokenId).isJailed);

        _playStage(player1, id, RAND_LOSS); // bust; arrestRng (rand>>64) = 0 → jail check passes

        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.BUSTED));
        assertTrue(core.getGameState(tokenId).isJailed, "busted while hot -> arrested");
        assertEq(heists.activeHeist(tokenId), 0, "slot freed");
    }

    function test_setback_paysPartialPotAddsHeatNoRep() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 1 clean
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 2 clean
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 3 clean
        uint256 cashBefore = core.getCashBalance(tokenId);
        uint8 heatBefore = core.getGameState(tokenId).heatLevel;
        uint256 repBefore = core.getGameState(tokenId).reputation;
        _playStage(player1, id, RAND_SETBACK); // stage 4 → setback (deep enough that old code would have paid rep)

        // partial = stage-4 pot (min roll: 500 * 52000/10000 = 2600) * keep 3500/10000 = 910
        uint256 expectedPartial = (uint256(SMALL_CASH) * 52000 / 10000) * 3500 / 10000;
        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.SETBACK));
        assertEq(core.getCashBalance(tokenId), cashBefore + expectedPartial, "partial pot paid");
        assertEq(heists.activeHeist(tokenId), 0, "slot freed");
        assertEq(core.getGameState(tokenId).heatLevel, heatBefore + 1, "setback raises heat");
        assertEq(core.getGameState(tokenId).reputation, repBefore, "setback grants no rep");
    }

    function test_oneAttemptPerRun_notPerStage() public {
        uint8 attemptsBefore = core.getGameState(tokenId).dailyAttemptsRemaining;
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        for (uint256 i = 0; i < 5; i++) {
            _playStage(player1, id, RAND_WIN_NO_JP);
        }
        // Whole 5-stage push consumed exactly one attempt.
        assertEq(core.getGameState(tokenId).dailyAttemptsRemaining, attemptsBefore - 1, "one attempt for the run");
    }

    function test_supplyRun_paysDrugs() public {
        uint256 id = _start(IDealersHeists.HeistFamily.SUPPLY, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 1 (prep)
        _playStage(player1, id, RAND_WIN_NO_JP); // stage 2: 70% common / 30% uncommon
        vm.prank(player1);
        heists.cashOut(id);

        // Stage-2 pot allocated mostly to common drugs (+ residual cash).
        uint256 common =
            core.getDrugBalance(tokenId, 4) + core.getDrugBalance(tokenId, 1) + core.getDrugBalance(tokenId, 9);
        assertGt(common, 0, "received common drugs");
    }

    function test_supplyRun_paysOnlyCurrentAreaDrugs() public {
        // Dealer is in Manhattan (area 1) which deals Weed(4,common) / XTC(5,uncommon) / Cocaine(6,rare).
        uint256 id = _start(IDealersHeists.HeistFamily.SUPPLY, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // 1
        _playStage(player1, id, RAND_WIN_NO_JP); // 2
        _playStage(player1, id, RAND_WIN_NO_JP); // 3
        _playStage(player1, id, RAND_WIN_NO_JP); // 4 — mix includes rare
        uint256 cocaineBefore = core.getDrugBalance(tokenId, 6);
        vm.prank(player1);
        heists.cashOut(id);

        // The rare bucket can only be Manhattan's rare (Cocaine) — never other areas' rares.
        assertGt(core.getDrugBalance(tokenId, 6), cocaineBefore, "received Manhattan Cocaine");
        assertEq(core.getDrugBalance(tokenId, 11), 0, "no Fentanyl (Tokyo-only)");
        assertEq(core.getDrugBalance(tokenId, 8), 0, "no Heroin (not in Manhattan)");
        assertEq(core.getDrugBalance(tokenId, 3), 0, "no Jewels (not in Manhattan)");
    }

    function test_resolveStage_isPermissionless() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        vm.prank(player1);
        heists.commitStage(id);
        uint64 seq = heists.getHeist(id).commitSeq;
        _mockReveal(seq, RAND_WIN_NO_JP);
        _advanceToRevealable(seq);
        vm.prank(player2); // someone else resolves
        heists.resolveStage(seq);
        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.REVEALED_WIN));
    }

    // ---------------------------------------------------------------- ETH add-on + jackpot

    function test_ethAddOn_routesToReserveAndPaymentHandler() public {
        uint256 addOn = heists.ethAddOn();
        uint256 bankBefore = bankVault.balance;

        _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, true);

        uint256 expectedReserve = addOn * heists.jackpotReserveBps() / 10000; // 40%
        assertEq(heists.jackpotReserve(), expectedReserve, "reserve seeded");
        assertEq(address(heists).balance, expectedReserve, "contract holds reserve only");
        // 60% routed through PaymentHandler → 80% of that to bankVault EOA.
        uint256 feePortion = addOn - expectedReserve;
        assertEq(bankVault.balance, bankBefore + (feePortion * 8000 / 10000), "bank fee forwarded");
    }

    function test_jackpot_triggersPaysCompensationAndClaims() public {
        heists.fundReserve{value: 1 ether}();
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, true);

        _playStage(player1, id, RAND_WIN_JP); // stage 1 win + compensation trigger

        uint64 pseq = mockEntropy.nextSeq() - 1;
        mockEntropy.fire(pseq, bytes32(uint256(123456789)));

        uint256 owed = heists.jackpotOwed(tokenId);
        uint256 addOn = heists.ethAddOn();
        assertLt(owed, addOn, "compensation pays back under the add-on");
        assertGe(owed, addOn * 7000 / 10000, "at least the 0.7x floor");
        assertLe(owed, addOn * 9000 / 10000, "at most the 0.9x ceiling");

        uint256 balBefore = player1.balance;
        vm.prank(player1);
        heists.claimJackpot(tokenId);
        assertEq(player1.balance, balBefore + owed, "jackpot claimed");
        assertEq(heists.jackpotOwed(tokenId), 0);
    }

    function test_jackpot_skippedWhenReserveTooLow() public {
        // No fundReserve: one add-on only seeds ~0.0004 ETH, below the 0.0009 ETH max payout.
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, true);
        uint64 seqBefore = mockEntropy.nextSeq();
        _playStage(player1, id, RAND_WIN_JP);
        assertEq(mockEntropy.nextSeq(), seqBefore, "no Pyth request fired");
        assertEq(heists.jackpotOwed(tokenId), 0);
    }

    function test_jackpot_firesAtMostOncePerRun() public {
        heists.fundReserve{value: 1 ether}(); // ample reserve — only the one-shot flag can stop a second fire
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, true);

        uint64 seqBefore = mockEntropy.nextSeq();
        _playStage(player1, id, RAND_WIN_JP); // stage 1: trigger hits → fires
        assertTrue(heists.getHeist(id).jackpotFired, "flag set on first fire");

        _playStage(player1, id, RAND_WIN_JP); // stage 2: trigger would hit, but is suppressed
        _playStage(player1, id, RAND_WIN_JP); // stage 3: same

        assertEq(mockEntropy.nextSeq(), seqBefore + 1, "exactly one Pyth request for the whole run");
    }

    function test_jackpot_reserveSkipStaysEligible() public {
        // Add-on alone seeds ~0.0004 ETH — below the stage-1 max payout, so the first trigger skips.
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, true);

        uint64 seqBefore = mockEntropy.nextSeq();
        _playStage(player1, id, RAND_WIN_JP); // stage 1: trigger hits but reserve too low → skipped
        assertEq(mockEntropy.nextSeq(), seqBefore, "skip makes no Pyth request");
        assertFalse(heists.getHeist(id).jackpotFired, "a reserve-skip does not burn the one-shot");

        heists.fundReserve{value: 1 ether}();
        _playStage(player1, id, RAND_WIN_JP); // stage 2: now funded → fires
        assertEq(mockEntropy.nextSeq(), seqBefore + 1, "still eligible after the skip");
        assertTrue(heists.getHeist(id).jackpotFired, "flag set once it finally fires");
    }

    function test_cashLane_rejectsEthValue() public {
        vm.prank(player1);
        vm.expectRevert(DealersHeists.InvalidEthAmount.selector);
        heists.startHeist{value: 1}(tokenId, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
    }

    // ---------------------------------------------------------------- timeouts

    function test_expiry_bustsRun_noRerollEscape() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        vm.prank(player1);
        heists.commitStage(id);
        uint64 seq = heists.getHeist(id).commitSeq;
        _advanceToExpired();
        heists.resolveStage(seq); // expired → bust, terminal (no rewind, no re-roll)

        IDealersHeists.DailyHeist memory h = heists.getHeist(id);
        assertEq(uint8(h.status), uint8(IDealersHeists.HeistStatus.BUSTED), "expired run busted");
        assertEq(h.currentPot, 0, "pot zeroed");
        assertEq(heists.activeHeist(tokenId), 0, "slot freed");

        // a busted run cannot be re-committed — the only way to retry is a fresh stake + attempt
        vm.prank(player1);
        vm.expectRevert(DealersHeists.InvalidHeistState.selector);
        heists.commitStage(id);
    }

    function test_forceFinalize_afterIdleTimeout() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP); // REVEALED_WIN, idle
        uint256 cashBefore = core.getCashBalance(tokenId);

        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(player2); // anyone
        heists.forceFinalize(id);

        assertEq(uint8(heists.getHeist(id).status), uint8(IDealersHeists.HeistStatus.CASHED_OUT));
        assertGt(core.getCashBalance(tokenId), cashBefore, "idle pot released");
    }

    function test_pause_blocksStart() public {
        heists.pause();
        vm.prank(player1);
        vm.expectRevert(DealersHeists.ContractPaused.selector);
        heists.startHeist(tokenId, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
    }

    // ---------------------------------------------------------------- lifetime stats

    function test_stats_countCleanStagesAndCashOut() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP);
        _playStage(player1, id, RAND_WIN_NO_JP);
        vm.prank(player1);
        heists.cashOut(id);

        IDealersHeists.HeistStats memory s = heists.getDealerHeistStats(tokenId);
        assertEq(s.stagesCleared, 2, "two clean stages");
        assertEq(s.cashOuts, 1, "one cashout");
        assertEq(s.setbacks, 0);
        assertEq(s.busts, 0);
        assertEq(s.jackpotsWon, 0);
    }

    function test_stats_fullPushCountsFinalStageAndAutoCashOut() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        for (uint256 i = 0; i < 5; i++) {
            _playStage(player1, id, RAND_WIN_NO_JP);
        }

        IDealersHeists.HeistStats memory s = heists.getDealerHeistStats(tokenId);
        assertEq(s.stagesCleared, 5, "final stage counts as cleared");
        assertEq(s.cashOuts, 1, "stage-5 auto-pay counts as cashout");
    }

    function test_stats_countSetback() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP);
        _playStage(player1, id, RAND_SETBACK);

        IDealersHeists.HeistStats memory s = heists.getDealerHeistStats(tokenId);
        assertEq(s.stagesCleared, 1, "only the clean stage counts");
        assertEq(s.setbacks, 1, "setback counted");
        assertEq(s.cashOuts, 0, "a partial-pot ending is not a cashout");
    }

    function test_stats_countBust_includingExpiry() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_LOSS);
        assertEq(heists.getDealerHeistStats(tokenId).busts, 1, "roll bust counted");

        uint256 id2 = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        vm.prank(player1);
        heists.commitStage(id2);
        uint64 seq = heists.getHeist(id2).commitSeq;
        _advanceToExpired();
        heists.resolveStage(seq);
        assertEq(heists.getDealerHeistStats(tokenId).busts, 2, "expiry bust counted");
    }

    function test_stats_countForceFinalizeAsCashOut() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_WIN_NO_JP);
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(player2);
        heists.forceFinalize(id);

        assertEq(heists.getDealerHeistStats(tokenId).cashOuts, 1, "force-finalize pays the pot");
    }

    function test_stats_countJackpotWon() public {
        heists.fundReserve{value: 1 ether}();
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, true);
        _playStage(player1, id, RAND_WIN_JP);
        assertEq(heists.getDealerHeistStats(tokenId).jackpotsWon, 0, "not counted until the Pyth callback");

        uint64 pseq = mockEntropy.nextSeq() - 1;
        mockEntropy.fire(pseq, bytes32(uint256(123456789)));
        assertEq(heists.getDealerHeistStats(tokenId).jackpotsWon, 1, "counted when the callback credits");
    }

    function test_stats_accumulateAcrossRuns() public {
        uint256 id = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id, RAND_LOSS); // run 1: bust at stage 1

        uint256 id2 = _start(IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        _playStage(player1, id2, RAND_WIN_NO_JP);
        _playStage(player1, id2, RAND_WIN_NO_JP);
        vm.prank(player1);
        heists.cashOut(id2); // run 2: two stages + cashout

        IDealersHeists.HeistStats memory s = heists.getDealerHeistStats(tokenId);
        assertEq(s.busts, 1);
        assertEq(s.stagesCleared, 2);
        assertEq(s.cashOuts, 1);
        assertEq(s.runs, 2, "both runs counted");
        assertEq(heists.heistRuns(tokenId), 2, "compat view mirrors stats");
    }
}
