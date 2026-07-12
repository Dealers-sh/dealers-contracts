// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./HeistsBaseTest.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IDealersHeists} from "../../src/core/IDealersHeists.sol";
import {IDealersBankHeist} from "../../src/core/IDealersBankHeist.sol";
import {IDealersPVE} from "../../src/core/IDealersPVE.sol";

contract DealersBankHeistTest is HeistsBaseTest {
    uint256 internal constant DRUG_WEED = 4;
    uint96 internal constant ENTRY_FEE = 5000;
    uint64 internal constant REFUND_TIMEOUT = 7 days;
    uint32 internal constant FREEZE_WINDOW = 1 days;

    address internal player3;
    uint256 internal tA;
    uint256 internal tB;
    uint256 internal tC;

    function setUp() public override {
        super.setUp();
        vm.deal(address(bankHeist), 10 ether); // vault accrued from game fees
        player3 = makeAddr("player3");
        tA = _readyDealer(player1, 100000);
        tB = _readyDealer(player2, 100000);
        tC = _readyDealer(player3, 100000);
    }

    // ---------------------------------------------------------------- helpers

    function _defaultConfig() internal pure returns (IDealersBankHeist.SeasonConfig memory cfg) {
        cfg.duration = 7 days;
        cfg.entryFee = ENTRY_FEE;
        cfg.minEntrants = 2;
        cfg.maxEntrants = 10000;
        cfg.potBps = 7500;
        cfg.claimWindow = 60 days;
        cfg.refundTimeout = REFUND_TIMEOUT;
        cfg.freezeWindow = FREEZE_WINDOW;
        cfg.weights = [uint64(1), 1, 1, 0]; // score = games played, any metric
    }

    function _openDefaultSeason() internal {
        bankHeist.openSeason(_defaultConfig());
    }

    function _close(uint256 sid) internal {
        vm.warp(bankHeist.getSeason(sid).closesAt);
    }

    function _freeze(uint256 sid) internal {
        bankHeist.freezeScores(sid, type(uint256).max);
    }

    /// @dev Warp to just past 00:00 UTC of epoch day `n` (tests start at ts 1 = day 0). Absolute
    ///      targets sidestep a foundry-zksync quirk where the test frame's block.timestamp read
    ///      goes stale after intervening zkEVM calls.
    function _warpToDay(uint256 n) internal {
        vm.warp(n * 1 days + 1);
    }

    /// @dev Grind one unit of activity cleanly (start + abandon → heistRuns++, slot freed, cash refunded).
    function _grind(address player, uint256 tid) internal {
        vm.startPrank(player);
        uint256 hid = heists.startHeist(tid, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        heists.abandonHeist(hid);
        vm.stopPrank();
    }

    function _enterBoth() internal {
        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        bankHeist.enter(tB);
    }

    /// @dev Full happy path: both enter, grind 1:3, close, freeze, settle. Pot = 7.5 ETH.
    function _settleOneVsThree() internal {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _grind(player2, tB);
        _grind(player2, tB);
        _close(0);
        _freeze(0);
        bankHeist.settle(0);
    }

    // ---------------------------------------------------------------- openSeason

    function test_openSeason_storesLockedConfig() public {
        _openDefaultSeason();
        IDealersBankHeist.Season memory s = bankHeist.getSeason(0);
        assertEq(bankHeist.seasonCount(), 1);
        assertEq(s.opensAt, block.timestamp);
        assertEq(s.closesAt, block.timestamp + 7 days);
        assertEq(s.config.entryFee, ENTRY_FEE);
        assertEq(s.config.potBps, 7500);
    }

    function test_openSeason_onlyOwner() public {
        vm.prank(player1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        bankHeist.openSeason(_defaultConfig());
    }

    function test_openSeason_rejectsInvalidConfig() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.duration = 0;
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.potBps = 10001;
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.claimWindow = 0;
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.refundTimeout = 0;
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.freezeWindow = 0;
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.freezeWindow = uint32(REFUND_TIMEOUT); // must be strictly under the refund grace
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.maxEntrants = 0;
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.maxEntrants = 1; // below minEntrants (2)
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.weights = [uint64(0), 0, 0, 0];
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);

        cfg = _defaultConfig();
        cfg.entryFee = type(uint96).max;
        cfg.maxEntrants = 2; // fee x entrants would overflow cashSunk (uint96)
        vm.expectRevert(DealersBankHeist.InvalidConfig.selector);
        bankHeist.openSeason(cfg);
    }

    function test_openSeason_requiresPreviousResolved() public {
        _openDefaultSeason();
        vm.expectRevert(DealersBankHeist.PreviousSeasonUnresolved.selector);
        bankHeist.openSeason(_defaultConfig());

        // Resolve season 0 (zero entrants < minEntrants → skip), then a new season opens.
        _close(0);
        _freeze(0);
        assertTrue(bankHeist.getSeason(0).skipped);
        _openDefaultSeason();
        assertEq(bankHeist.seasonCount(), 2);
    }

    // ---------------------------------------------------------------- enter

    function test_enter_sinksCashAndSnapshotsBaseline() public {
        _grind(player1, tA); // pre-season activity must land in the baseline
        _openDefaultSeason();

        uint256 cashBefore = core.getCashBalance(tA);
        uint256 attemptsBefore = core.getGameState(tA).dailyAttemptsRemaining;
        vm.prank(player1);
        bankHeist.enter(tA);

        assertEq(core.getCashBalance(tA), cashBefore - ENTRY_FEE, "CASH sunk");
        IDealersBankHeist.Season memory s = bankHeist.getSeason(0);
        assertEq(s.entryCount, 1);
        assertEq(s.cashSunk, ENTRY_FEE);

        (,, uint64 heistRuns) = bankHeist.metricsOf(tA);
        (,, uint64 baseHeists) = bankHeist.baselines(0, tA);
        assertEq(baseHeists, heistRuns, "baseline = live counters at entry");
        assertEq(bankHeist.pendingScore(0, tA), 0, "no in-season activity yet");
        assertEq(core.getGameState(tA).dailyAttemptsRemaining, attemptsBefore, "no attempt spent");
    }

    function test_enter_revertsWithoutSeason() public {
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.NoOpenSeason.selector);
        bankHeist.enter(tA);
    }

    function test_enter_revertsAfterClose() public {
        _openDefaultSeason();
        _close(0);
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.SeasonClosed.selector);
        bankHeist.enter(tA);
    }

    function test_enter_revertsOnDoubleEntry() public {
        _openDefaultSeason();
        vm.startPrank(player1);
        bankHeist.enter(tA);
        vm.expectRevert(DealersBankHeist.AlreadyEntered.selector);
        bankHeist.enter(tA);
        vm.stopPrank();
    }

    function test_enter_enforcesRepGate() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.entryRepGate = 100;
        bankHeist.openSeason(cfg);

        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.RepTooLow.selector);
        bankHeist.enter(tA);

        _giveRep(tA, 100);
        vm.prank(player1);
        bankHeist.enter(tA);
        assertEq(bankHeist.getSeason(0).entryCount, 1);
    }

    function test_enter_enforcesMaxEntrants() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.minEntrants = 1;
        cfg.maxEntrants = 1;
        bankHeist.openSeason(cfg);

        vm.prank(player1);
        bankHeist.enter(tA);
        vm.prank(player2);
        vm.expectRevert(DealersBankHeist.EntrantsFull.selector);
        bankHeist.enter(tB);
    }

    function test_enter_revertsWhenPaused() public {
        _openDefaultSeason();
        bankHeist.pause();
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.ContractPaused.selector);
        bankHeist.enter(tA);
    }

    function test_enter_revertsWhenCancelled() public {
        _openDefaultSeason();
        bankHeist.cancelSeason(0);
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.SeasonClosed.selector);
        bankHeist.enter(tA);
    }

    function test_enter_revertsForNonOwner() public {
        _openDefaultSeason();
        vm.prank(player2);
        vm.expectRevert(DealersBankHeist.NotDealerOwner.selector);
        bankHeist.enter(tA);
    }

    /// @dev Jail via an authorized jailer (the fixture registers heists as one).
    function _jail(uint256 tid) internal {
        vm.prank(address(heists));
        actions.arrest(tid, 0);
    }

    function test_enter_revertsWhenJailed() public {
        _openDefaultSeason();
        _jail(tA);
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.DealerInJail.selector);
        bankHeist.enter(tA);
    }

    function test_checkIn_revertsWhenJailed() public {
        _openDefaultSeason();
        _enterBoth();
        _jail(tA);
        _warpToDay(1);
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.DealerInJail.selector);
        bankHeist.checkIn(tA);

        vm.prank(player2); // free dealers keep checking in
        bankHeist.checkIn(tB);
    }

    // ---------------------------------------------------------------- scoring

    function test_scoring_weightsPerMetric() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.minEntrants = 1;
        cfg.weights = [uint64(0), 0, 5, 2]; // heists x5 + total x2
        bankHeist.openSeason(cfg);

        vm.prank(player1);
        bankHeist.enter(tA);
        _grind(player1, tA);
        _grind(player1, tA);
        _grind(player1, tA);

        assertEq(bankHeist.pendingScore(0, tA), 3 * 5 + 3 * 2, "weighted sum across metrics");
        _close(0);
        _freeze(0);
        assertEq(bankHeist.scoreOf(0, tA), 21);
    }

    function test_scoring_pveGamesCount() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.minEntrants = 1;
        cfg.weights = [uint64(1), 0, 0, 0]; // PVE only
        bankHeist.openSeason(cfg);

        vm.prank(player1);
        bankHeist.enter(tA);
        _grind(player1, tA); // heist run must NOT score
        _pveWin(player1, tA, 0, IDealersPVE.HustleType.BUY, DRUG_WEED, 10);

        assertEq(bankHeist.pendingScore(0, tA), 1, "one PVE game, heist run ignored");
    }

    function test_scoring_pvpCountsAttackerOnly() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.weights = [uint64(0), 1, 0, 0]; // PVP only
        bankHeist.openSeason(cfg);

        _giveRep(tA, 500);
        _giveRep(tB, 500);
        _enterBoth();

        _pvpAttackerWins(player1, tA, tB);

        assertEq(bankHeist.pendingScore(0, tA), 1, "attacker scores the game");
        assertEq(bankHeist.pendingScore(0, tB), 0, "defender scores nothing");
    }

    function test_scoring_thresholdDisqualifies() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.weights = [uint64(0), 0, 1, 0];
        cfg.minThresholds = [uint32(0), 0, 2, 0]; // need >= 2 heist runs to qualify
        bankHeist.openSeason(cfg);

        _enterBoth();
        _grind(player1, tA); // 1 run — below threshold
        _grind(player2, tB);
        _grind(player2, tB);

        _close(0);
        _freeze(0);
        assertEq(bankHeist.scoreOf(0, tA), 0, "below threshold scores zero");
        assertEq(bankHeist.scoreOf(0, tB), 2);
        assertEq(bankHeist.getSeason(0).totalScore, 2);
    }

    function test_scoring_preSeasonActivityExcluded() public {
        _grind(player1, tA);
        _grind(player1, tA);
        _openDefaultSeason();
        vm.prank(player1);
        bankHeist.enter(tA);
        assertEq(bankHeist.pendingScore(0, tA), 0, "baseline excludes pre-entry play");
        _grind(player1, tA);
        assertEq(bankHeist.pendingScore(0, tA), 1);
    }

    // ---------------------------------------------------------------- genesis (zeroBaseline)

    function _openZeroBaselineSeason() internal {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.zeroBaseline = true;
        bankHeist.openSeason(cfg);
    }

    function test_zeroBaseline_countsLifetimeActivity() public {
        _grind(player1, tA);
        _grind(player1, tA); // pre-season play
        _openZeroBaselineSeason();

        vm.prank(player1);
        bankHeist.enter(tA);
        assertEq(bankHeist.pendingScore(0, tA), 2, "lifetime play credited at entry");

        _grind(player1, tA);
        assertEq(bankHeist.pendingScore(0, tA), 3, "in-season play stacks on top");
    }

    function test_zeroBaseline_settlesLifetimeProRata() public {
        _grind(player1, tA);
        _grind(player2, tB);
        _grind(player2, tB);
        _grind(player2, tB); // 1:3 lifetime, all pre-season

        _openZeroBaselineSeason();
        _enterBoth();
        _close(0);
        _freeze(0);
        bankHeist.settle(0);

        uint256 p1Before = player1.balance;
        uint256 p2Before = player2.balance;
        bankHeist.claim(0, tA);
        bankHeist.claim(0, tB);
        assertEq(player1.balance - p1Before, 1.875 ether, "1/4 of the pot from lifetime score");
        assertEq(player2.balance - p2Before, 5.625 ether, "3/4 of the pot from lifetime score");
    }

    function test_zeroBaseline_nextSeasonSnapshotsFresh() public {
        _grind(player1, tA);
        _openZeroBaselineSeason();
        _enterBoth();
        _close(0);
        _freeze(0);
        bankHeist.settle(0);

        _openDefaultSeason(); // season 1 back to delta-vs-entry scoring
        vm.prank(player1);
        bankHeist.enter(tA);
        assertEq(bankHeist.pendingScore(1, tA), 0, "lifetime credit does not leak past genesis");
    }

    // ---------------------------------------------------------------- focus

    function test_focus_entryGrantsFirstPoint() public {
        _openDefaultSeason();
        vm.prank(player1);
        bankHeist.enter(tA);
        assertEq(bankHeist.focusOf(0, tA), 1, "entry is the first check-in");

        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.AlreadyCheckedInToday.selector);
        bankHeist.checkIn(tA);
    }

    function test_focus_checkInWithoutPlay() public {
        _openDefaultSeason();
        vm.prank(player1);
        bankHeist.enter(tA);

        // Checking in can be the first thing a player does in a day — no play required.
        _warpToDay(1);
        vm.prank(player1);
        bankHeist.checkIn(tA);
        assertEq(bankHeist.focusOf(0, tA), 2);
    }

    function test_focus_skippedDayIsForfeit() public {
        _openDefaultSeason();
        vm.prank(player1);
        bankHeist.enter(tA);
        (,, uint32 entryDay) = bankHeist.focusState(0, tA);
        assertEq(entryDay, uint32(block.timestamp / 1 days), "entry stamps the entry day");

        _warpToDay(2); // skipped day 1
        vm.prank(player1);
        bankHeist.checkIn(tA);
        assertEq(bankHeist.focusOf(0, tA), 2, "elapsed days buy only one point");
        (, uint32 lastDay, uint32 entryDayAfter) = bankHeist.focusState(0, tA);
        assertEq(entryDayAfter, entryDay, "check-ins never move the entry day");
        assertEq(lastDay, entryDay + 2);

        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.AlreadyCheckedInToday.selector);
        bankHeist.checkIn(tA);
    }

    function test_focus_checkInGates() public {
        _openDefaultSeason();

        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.NotEntered.selector);
        bankHeist.checkIn(tA);

        vm.prank(player1);
        bankHeist.enter(tA);
        _warpToDay(1);

        vm.prank(player2);
        vm.expectRevert(DealersBankHeist.NotDealerOwner.selector);
        bankHeist.checkIn(tA);

        bankHeist.pause();
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.ContractPaused.selector);
        bankHeist.checkIn(tA);
        bankHeist.unpause();

        _close(0);
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.SeasonClosed.selector);
        bankHeist.checkIn(tA);
    }

    function test_focus_multiplierAmplifiesScore() public {
        IDealersBankHeist.SeasonConfig memory cfg = _defaultConfig();
        cfg.weights = [uint64(0), 0, 100, 0]; // heists x100
        cfg.focusBonusBps = 1000; // +10% per focus point
        bankHeist.openSeason(cfg);
        _enterBoth(); // both start at focus 1

        _grind(player1, tA);
        _grind(player1, tA);
        _grind(player2, tB);
        _grind(player2, tB);

        // tB shows up two more days and grinds once more; tA never returns.
        _warpToDay(1);
        vm.prank(player2);
        bankHeist.checkIn(tB);
        _grind(player2, tB);
        _warpToDay(2);
        vm.prank(player2);
        bankHeist.checkIn(tB);

        // tA: base 200, focus 1 -> x1.1 = 220. tB: base 300, focus 3 -> x1.3 = 390.
        assertEq(bankHeist.pendingScore(0, tA), 220);
        assertEq(bankHeist.pendingScore(0, tB), 390);

        _close(0);
        _freeze(0);
        assertEq(bankHeist.scoreOf(0, tA), 220, "frozen score includes the multiplier");
        assertEq(bankHeist.scoreOf(0, tB), 390);
        assertEq(bankHeist.getSeason(0).totalScore, 610);
    }

    function test_focus_zeroBpsDisablesMultiplier() public {
        _openDefaultSeason(); // focusBonusBps 0
        vm.prank(player1);
        bankHeist.enter(tA);
        _grind(player1, tA);
        assertEq(bankHeist.pendingScore(0, tA), 1, "raw score when focus is disabled");
    }

    // ---------------------------------------------------------------- freeze

    function test_freeze_skipsBelowMinEntrants() public {
        _openDefaultSeason();
        vm.prank(player1);
        bankHeist.enter(tA); // only 1 entrant, min is 2
        _close(0);
        _freeze(0);
        assertTrue(bankHeist.getSeason(0).skipped, "season skipped");

        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + ENTRY_FEE, "CASH refunded");
    }

    function test_freeze_revertsBeforeClose() public {
        _openDefaultSeason();
        _enterBoth();
        vm.expectRevert(DealersBankHeist.SeasonNotClosed.selector);
        bankHeist.freezeScores(0, 10);
    }

    function test_freeze_paginates() public {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);

        bankHeist.freezeScores(0, 1);
        assertEq(bankHeist.getSeason(0).scoreCursor, 1);
        bankHeist.freezeScores(0, 1);
        assertEq(bankHeist.getSeason(0).scoreCursor, 2);
        assertEq(bankHeist.getSeason(0).totalScore, 2);
        vm.expectRevert(DealersBankHeist.ScoresAlreadyFrozen.selector);
        bankHeist.freezeScores(0, 1);
    }

    function test_freeze_revertsAfterWindow() public {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);

        vm.warp(block.timestamp + FREEZE_WINDOW + 1); // past the freeze window
        vm.expectRevert(DealersBankHeist.FreezeWindowClosed.selector);
        bankHeist.freezeScores(0, type(uint256).max);
    }

    /// @dev A last-indexed entrant can no longer freeze rivals early then grind before freezing
    ///      itself: once the window lapses no score can be frozen, and the season refunds instead.
    function test_freeze_windowBoundsPostCloseGrind() public {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);

        bankHeist.freezeScores(0, 1); // attacker freezes the rival (index 0) at its close score
        assertEq(bankHeist.getSeason(0).scoreCursor, 1);

        _grind(player2, tB); // ... then keeps grinding its own dealer
        _grind(player2, tB);

        vm.warp(block.timestamp + FREEZE_WINDOW + 1); // but the window lapses before it can freeze itself
        vm.expectRevert(DealersBankHeist.FreezeWindowClosed.selector);
        bankHeist.freezeScores(0, type(uint256).max);

        vm.expectRevert(DealersBankHeist.ScoresNotReady.selector); // half-frozen season cannot settle
        bankHeist.settle(0);

        vm.warp(uint256(bankHeist.getSeason(0).closesAt) + REFUND_TIMEOUT + 1);
        uint256 cashBefore = core.getCashBalance(tB);
        vm.prank(player2);
        bankHeist.claimRefund(0, tB); // entrants recover their $CASH
        assertEq(core.getCashBalance(tB), cashBefore + ENTRY_FEE);
    }

    function test_freeze_frozenScoreIgnoresLaterGrind() public {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);
        _freeze(0);
        assertEq(bankHeist.scoreOf(0, tA), 1);

        _grind(player1, tA); // post-freeze grind buys nothing
        assertEq(bankHeist.scoreOf(0, tA), 1, "frozen score untouched");
        assertEq(bankHeist.getSeason(0).totalScore, 2, "totalScore frozen");
    }

    // ---------------------------------------------------------------- settle

    function test_settle_reservesPotBps() public {
        _settleOneVsThree();

        IDealersBankHeist.Season memory s = bankHeist.getSeason(0);
        assertTrue(s.settled);
        assertEq(s.pot, 7.5 ether, "75% of the 10 ETH vault");
        assertEq(s.totalScore, 4);
        assertEq(bankHeist.reservedETH(), 7.5 ether);
        assertEq(bankHeist.availableVault(), 2.5 ether, "rest rolls forward");
    }

    function test_settle_revertsWithoutFullFreeze() public {
        _openDefaultSeason();
        _enterBoth();
        _close(0);
        bankHeist.freezeScores(0, 1); // partial
        vm.expectRevert(DealersBankHeist.ScoresNotReady.selector);
        bankHeist.settle(0);
    }

    function test_settle_zeroScoreSkipsAndRefunds() public {
        _openDefaultSeason();
        _enterBoth(); // nobody plays → totalScore 0
        _close(0);
        _freeze(0);
        bankHeist.settle(0);

        IDealersBankHeist.Season memory s = bankHeist.getSeason(0);
        assertFalse(s.settled, "zero-score routes to skip, not settle");
        assertTrue(s.skipped, "skipped so entries can refund");
        assertEq(s.pot, 0);
        assertEq(bankHeist.reservedETH(), 0, "pot stays in vault");

        // Entrants recover their $CASH rather than having it trapped in a settled season.
        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + ENTRY_FEE, "CASH refunded");
    }

    function test_settle_belowMinEntrantsReverts() public {
        _openDefaultSeason();
        vm.prank(player1);
        bankHeist.enter(tA);
        _close(0);
        vm.expectRevert(DealersBankHeist.BelowMinEntrants.selector);
        bankHeist.settle(0);
    }

    function test_settle_feeBoundedToMaxBps() public {
        bankHeist.setSettleFee(100 ether); // fat-fingered fee far above the vault

        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);
        _freeze(0);

        address keeper = makeAddr("keeper");
        uint256 avail = bankHeist.availableVault(); // 10 ETH
        vm.prank(keeper);
        bankHeist.settle(0);

        uint256 expectedFee = avail / 100; // MAX_SETTLE_FEE_BPS = 1%
        assertEq(keeper.balance, expectedFee, "fee capped to 1% of the vault, not the whole vault");
        assertEq(bankHeist.getSeason(0).pot, (avail - expectedFee) * 7500 / 10000, "pot funded after the capped fee");
        assertGt(bankHeist.getSeason(0).pot, 0);
        assertGe(address(bankHeist).balance, bankHeist.reservedETH(), "solvency invariant holds");
    }

    function test_settle_revertsAfterGraceWindow() public {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);
        _freeze(0);

        vm.warp(block.timestamp + REFUND_TIMEOUT + 1); // past the settle deadline
        vm.expectRevert(DealersBankHeist.SettleWindowClosed.selector);
        bankHeist.settle(0);
    }

    function test_settle_revertsOnEmptyVault() public {
        vm.deal(address(bankHeist), 0); // hollow vault: no ETH to pay a pot

        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);
        _freeze(0);

        vm.expectRevert(DealersBankHeist.EmptyVault.selector);
        bankHeist.settle(0);

        // Leaving it unsettled is the fail-safe: after the grace window entries refund.
        vm.warp(block.timestamp + REFUND_TIMEOUT + 1);
        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + ENTRY_FEE, "hollow-vault entries refundable");
    }

    function test_settle_refundMutualExclusionAcrossGrace() public {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA);
        _grind(player2, tB);
        _close(0);
        _freeze(0);

        // Within the grace window a refund is not yet available — settle still owns the outcome.
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.NotRefundable.selector);
        bankHeist.claimRefund(0, tA);

        // Past the window settle is dead and refunds take over — the two never overlap.
        vm.warp(block.timestamp + REFUND_TIMEOUT + 1);
        vm.expectRevert(DealersBankHeist.SettleWindowClosed.selector);
        bankHeist.settle(0);

        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertTrue(bankHeist.getSeason(0).skipped);
    }

    // ---------------------------------------------------------------- claim

    function test_claim_paysProRataShares() public {
        _settleOneVsThree(); // scores 1 : 3, pot 7.5 ETH

        uint256 p1Before = player1.balance;
        uint256 p2Before = player2.balance;
        bankHeist.claim(0, tA);
        bankHeist.claim(0, tB);

        assertEq(player1.balance - p1Before, 1.875 ether, "1/4 of the pot");
        assertEq(player2.balance - p2Before, 5.625 ether, "3/4 of the pot");
        assertEq(bankHeist.reservedETH(), 0);
        assertEq(bankHeist.getSeason(0).claimedTotal, 7.5 ether);
        assertGe(address(bankHeist).balance, bankHeist.reservedETH(), "solvency invariant holds");
    }

    function test_claim_paysCurrentNftOwner() public {
        _settleOneVsThree();

        vm.prank(player1);
        nft.transferFrom(player1, player2, tA);

        // Anyone can trigger the claim; ETH goes to the CURRENT owner.
        uint256 p2Before = player2.balance;
        vm.prank(makeAddr("keeper"));
        bankHeist.claim(0, tA);
        assertEq(player2.balance - p2Before, 1.875 ether, "paid to new owner");
    }

    function test_claim_revertsOnDoubleClaim() public {
        _settleOneVsThree();
        bankHeist.claim(0, tA);
        vm.expectRevert(DealersBankHeist.AlreadyClaimed.selector);
        bankHeist.claim(0, tA);
    }

    function test_claim_revertsOnZeroScore() public {
        _openDefaultSeason();
        _enterBoth();
        _grind(player1, tA); // tB never plays
        _close(0);
        _freeze(0);
        bankHeist.settle(0);

        vm.expectRevert(DealersBankHeist.NothingToClaim.selector);
        bankHeist.claim(0, tB);
    }

    function test_claim_revertsBeforeSettle() public {
        _openDefaultSeason();
        _enterBoth();
        vm.expectRevert(DealersBankHeist.NotSettled.selector);
        bankHeist.claim(0, tA);
    }

    function test_claim_revertsAfterWindow() public {
        _settleOneVsThree();
        vm.warp(block.timestamp + 60 days + 1);
        vm.expectRevert(DealersBankHeist.ClaimWindowClosed.selector);
        bankHeist.claim(0, tA);
    }

    // ---------------------------------------------------------------- sweep

    function test_sweep_returnsUnclaimedToVault() public {
        _settleOneVsThree();
        bankHeist.claim(0, tA); // tB never claims (5.625 ETH abandoned)

        vm.expectRevert(DealersBankHeist.ClaimWindowOpen.selector);
        bankHeist.sweepExpired(0);

        vm.warp(block.timestamp + 60 days + 1);
        bankHeist.sweepExpired(0);

        assertEq(bankHeist.reservedETH(), 0);
        assertEq(bankHeist.availableVault(), address(bankHeist).balance, "remainder back in the vault");
        assertTrue(bankHeist.getSeason(0).swept);

        vm.expectRevert(DealersBankHeist.AlreadySwept.selector);
        bankHeist.sweepExpired(0);
    }

    // ---------------------------------------------------------------- refunds

    function test_refund_abandonedSeasonAfterTimeout() public {
        _openDefaultSeason();
        _enterBoth();
        _close(0); // closed but never frozen/settled

        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.NotRefundable.selector);
        bankHeist.claimRefund(0, tA);

        vm.warp(block.timestamp + REFUND_TIMEOUT + 1);
        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + ENTRY_FEE, "refunded after timeout");

        // First refund is terminal: freeze and settle are permanently blocked.
        assertTrue(bankHeist.getSeason(0).skipped);
        vm.expectRevert(DealersBankHeist.AlreadyResolved.selector);
        bankHeist.freezeScores(0, 10);
        vm.expectRevert(DealersBankHeist.AlreadyResolved.selector);
        bankHeist.settle(0);
    }

    function test_refund_settledSeasonNeverRefundable() public {
        _settleOneVsThree();
        vm.warp(block.timestamp + REFUND_TIMEOUT + 1);
        vm.prank(player1);
        vm.expectRevert(DealersBankHeist.NotRefundable.selector);
        bankHeist.claimRefund(0, tA);
    }

    function test_refund_cancelledSeasonRefundsImmediately() public {
        _openDefaultSeason();
        _enterBoth();
        bankHeist.cancelSeason(0); // mid-window owner cancel

        uint256 cashBefore = core.getCashBalance(tA);
        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        assertEq(core.getCashBalance(tA), cashBefore + ENTRY_FEE);
    }

    function test_refund_revertsOnDoubleRefundAndNonEntrant() public {
        _openDefaultSeason();
        vm.prank(player1);
        bankHeist.enter(tA);
        bankHeist.cancelSeason(0);

        vm.prank(player2);
        vm.expectRevert(DealersBankHeist.NotEntered.selector);
        bankHeist.claimRefund(0, tB);

        vm.startPrank(player1);
        bankHeist.claimRefund(0, tA);
        vm.expectRevert(DealersBankHeist.AlreadyRefunded.selector);
        bankHeist.claimRefund(0, tA);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- multi-season

    function test_secondSeason_freshBaselinesAndEntries() public {
        _settleOneVsThree(); // season 0 done: tA ground 1, tB ground 3

        _openDefaultSeason(); // season 1
        _enterBoth();
        assertEq(bankHeist.pendingScore(1, tA), 0, "season-1 baseline starts at current counters");

        _grind(player1, tA);
        _close(1);
        _freeze(1);
        assertEq(bankHeist.scoreOf(1, tA), 1);
        assertEq(bankHeist.scoreOf(1, tB), 0, "season-0 grinding does not leak into season 1");

        bankHeist.settle(1);
        // Season-1 pot = 75% of what season 0 left available (10 - 7.5 = 2.5 ETH).
        assertEq(bankHeist.getSeason(1).pot, 1.875 ether);
    }

    // ---------------------------------------------------------------- admin

    function test_cancelSeason_onlyOwnerAndNotAfterSettle() public {
        _openDefaultSeason();
        vm.prank(player1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        bankHeist.cancelSeason(0);

        _enterBoth();
        _grind(player1, tA);
        _close(0);
        _freeze(0);
        bankHeist.settle(0);
        vm.expectRevert(DealersBankHeist.AlreadyResolved.selector);
        bankHeist.cancelSeason(0);
    }

    function test_emergencyWithdraw_boundedByAvailableVault() public {
        _settleOneVsThree(); // 7.5 ETH reserved, 2.5 available

        vm.expectRevert(DealersBankHeist.InsufficientVault.selector);
        bankHeist.emergencyWithdraw(owner, 2.5 ether + 1);

        address to = makeAddr("treasury");
        bankHeist.emergencyWithdraw(to, 2.5 ether);
        assertEq(to.balance, 2.5 ether);
        assertEq(address(bankHeist).balance, bankHeist.reservedETH(), "reserve untouched");
    }

    function test_emergencyWithdraw_blockedWhileSeasonInFlight() public {
        _openDefaultSeason();
        _enterBoth();
        _close(0); // closed but not yet settled/skipped — pot not reserved yet

        // Draining now would settle entrants' earned pot down to near zero.
        vm.expectRevert(DealersBankHeist.SeasonInFlight.selector);
        bankHeist.emergencyWithdraw(owner, 1 ether);

        // Cancelling opens refunds and frees the escape hatch.
        bankHeist.cancelSeason(0);
        address to = makeAddr("treasury");
        bankHeist.emergencyWithdraw(to, 1 ether);
        assertEq(to.balance, 1 ether);
    }

    function test_setContracts_blockedWhileSeasonInFlight() public {
        _openDefaultSeason();
        vm.expectRevert(DealersBankHeist.SeasonInFlight.selector);
        bankHeist.setContracts(address(0), address(0), address(0), address(0), address(heists));

        bankHeist.cancelSeason(0);
        bankHeist.setContracts(address(0), address(0), address(0), address(0), address(heists));
    }

    function test_constructor_rejectsZeroAddress() public {
        vm.expectRevert(DealersBankHeist.InvalidAddress.selector);
        new DealersBankHeist(address(0), address(nft), address(pve), address(pvp), address(heists));

        vm.expectRevert(DealersBankHeist.InvalidAddress.selector);
        new DealersBankHeist(address(core), address(nft), address(pve), address(pvp), address(0));
    }
}
