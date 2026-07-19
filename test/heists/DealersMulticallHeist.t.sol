// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./HeistsBaseTest.sol";
import {DealersMulticall} from "../../src/core/DealersMulticall.sol";
import {IDealersHeists} from "../../src/core/IDealersHeists.sol";
import {IDealersBankHeist} from "../../src/core/IDealersBankHeist.sol";

/**
 * @dev Frontend aggregation views over DealersBankHeist: paginated live standings
 *      (rank/cut source data) and the single-dealer season card.
 */
contract DealersMulticallHeistTest is HeistsBaseTest {
    uint96 internal constant ENTRY_FEE = 5000;
    uint256 internal constant VAULT = 10 ether;

    address internal player3;
    uint256 internal tA;
    uint256 internal tB;
    uint256 internal tC;

    function setUp() public override {
        super.setUp();
        vm.deal(address(bankHeist), VAULT);
        multicall.setBankHeist(address(bankHeist));
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
        cfg.refundTimeout = 7 days;
        cfg.freezeWindow = 1 days;
        cfg.weights = [uint64(1), 1, 1, 0]; // score = games played, any metric
    }

    function _enter(address player, uint256 tid) internal {
        vm.prank(player);
        bankHeist.enter(tid);
    }

    /// @dev Grind one unit of activity cleanly (start + abandon → heistRuns++, slot freed, cash refunded).
    function _grind(address player, uint256 tid) internal {
        vm.startPrank(player);
        uint256 hid = heists.startHeist(tid, IDealersHeists.HeistFamily.CASH, DIFF_SMALL, false);
        heists.abandonHeist(hid);
        vm.stopPrank();
    }

    /// @dev Open, enter A+B, grind 1:3, close, freeze, settle. Pot = 7.5 ETH, scores 1:3.
    function _settleOneVsThree() internal {
        bankHeist.openSeason(_defaultConfig());
        _enter(player1, tA);
        _enter(player2, tB);
        _grind(player1, tA);
        _grind(player2, tB);
        _grind(player2, tB);
        _grind(player2, tB);
        vm.warp(bankHeist.getSeason(0).closesAt);
        bankHeist.freezeScores(0, type(uint256).max);
        bankHeist.settle(0);
    }

    // ---------------------------------------------------------------- getHeistStandings

    function test_standings_liveScoresInEntryOrder() public {
        bankHeist.openSeason(_defaultConfig());
        _enter(player1, tA);
        _enter(player2, tB);
        _grind(player1, tA);
        _grind(player2, tB);
        _grind(player2, tB);
        _grind(player2, tB);

        (DealersMulticall.HeistEntry[] memory entries, uint256 entryCount, uint256 sumPending, uint256 estPot) =
            multicall.getHeistStandings(0, 0, 10);

        assertEq(entryCount, 2);
        assertEq(entries.length, 2);
        assertEq(entries[0].tokenId, tA);
        assertEq(entries[0].pendingScore, 1);
        assertEq(entries[0].focus, 1); // entry grants the first focus point
        assertEq(entries[1].tokenId, tB);
        assertEq(entries[1].pendingScore, 3);
        assertEq(sumPending, 4);
        assertEq(estPot, VAULT * 7500 / 10000);
    }

    function test_standings_estPotAccountsForSettleFee() public {
        bankHeist.setSettleFee(0.05 ether); // under the 1% (0.1 ETH) cap
        bankHeist.openSeason(_defaultConfig());

        (,,, uint256 estPot) = multicall.getHeistStandings(0, 0, 0);
        assertEq(estPot, (VAULT - 0.05 ether) * 7500 / 10000);

        bankHeist.setSettleFee(1 ether); // over the cap → clamped to 0.1 ETH
        (,,, estPot) = multicall.getHeistStandings(0, 0, 0);
        assertEq(estPot, (VAULT - 0.1 ether) * 7500 / 10000);
    }

    function test_standings_pagination() public {
        bankHeist.openSeason(_defaultConfig());
        _enter(player1, tA);
        _enter(player2, tB);
        _enter(player3, tC);

        (DealersMulticall.HeistEntry[] memory page1, uint256 entryCount,,) = multicall.getHeistStandings(0, 0, 2);
        assertEq(entryCount, 3);
        assertEq(page1.length, 2);
        assertEq(page1[0].tokenId, tA);
        assertEq(page1[1].tokenId, tB);

        (DealersMulticall.HeistEntry[] memory page2,,,) = multicall.getHeistStandings(0, 2, 2);
        assertEq(page2.length, 1);
        assertEq(page2[0].tokenId, tC);

        (DealersMulticall.HeistEntry[] memory beyond,, uint256 sumBeyond,) = multicall.getHeistStandings(0, 3, 2);
        assertEq(beyond.length, 0);
        assertEq(sumBeyond, 0);

        (DealersMulticall.HeistEntry[] memory all,,,) = multicall.getHeistStandings(0, 0, type(uint256).max);
        assertEq(all.length, 3);
    }

    function test_standings_settledSeasonReturnsReservedPot() public {
        _settleOneVsThree();
        (,,, uint256 estPot) = multicall.getHeistStandings(0, 0, 0);
        assertEq(estPot, bankHeist.getSeason(0).pot);
    }

    function test_standings_skippedSeasonHasZeroPot() public {
        bankHeist.openSeason(_defaultConfig());
        _enter(player1, tA); // 1 < minEntrants
        vm.warp(bankHeist.getSeason(0).closesAt);
        bankHeist.freezeScores(0, type(uint256).max);
        assertTrue(bankHeist.getSeason(0).skipped);

        (,,, uint256 estPot) = multicall.getHeistStandings(0, 0, 0);
        assertEq(estPot, 0);
    }

    // ---------------------------------------------------------------- getHeistDealerStatus

    function test_dealerStatus_notEntered() public {
        bankHeist.openSeason(_defaultConfig());
        DealersMulticall.HeistDealerStatus memory st = multicall.getHeistDealerStatus(0, tA);
        assertFalse(st.entered);
        assertEq(st.pendingScore, 0);
        assertEq(st.focus, 0);
        assertFalse(st.checkedInToday);
        assertEq(st.claimableETH, 0);
        assertEq(st.refundableCash, 0);
    }

    function test_dealerStatus_liveSeasonCheckInFlow() public {
        bankHeist.openSeason(_defaultConfig());
        _enter(player1, tA);
        _grind(player1, tA);

        DealersMulticall.HeistDealerStatus memory st = multicall.getHeistDealerStatus(0, tA);
        assertTrue(st.entered);
        assertEq(st.pendingScore, 1);
        assertEq(st.frozenScore, 0); // nothing frozen while the season runs
        assertEq(st.focus, 1);
        assertTrue(st.checkedInToday); // entry counts as day-0 check-in

        vm.warp(1 days + 1);
        st = multicall.getHeistDealerStatus(0, tA);
        assertFalse(st.checkedInToday);

        vm.prank(player1);
        bankHeist.checkIn(tA);
        st = multicall.getHeistDealerStatus(0, tA);
        assertTrue(st.checkedInToday);
        assertEq(st.focus, 2);
    }

    function test_dealerStatus_claimableAfterSettle() public {
        _settleOneVsThree();
        uint256 pot = bankHeist.getSeason(0).pot;

        DealersMulticall.HeistDealerStatus memory st = multicall.getHeistDealerStatus(0, tA);
        assertEq(st.frozenScore, 1);
        assertFalse(st.claimed);
        assertEq(st.claimableETH, pot * 1 / 4);

        st = multicall.getHeistDealerStatus(0, tB);
        assertEq(st.claimableETH, pot * 3 / 4);

        bankHeist.claim(0, tA);
        st = multicall.getHeistDealerStatus(0, tA);
        assertTrue(st.claimed);
        assertEq(st.claimableETH, 0);
    }

    function test_dealerStatus_claimableZeroAfterWindowExpiry() public {
        _settleOneVsThree();
        IDealersBankHeist.Season memory s = bankHeist.getSeason(0);
        vm.warp(uint256(s.settledAt) + s.config.claimWindow + 1);

        DealersMulticall.HeistDealerStatus memory st = multicall.getHeistDealerStatus(0, tA);
        assertEq(st.claimableETH, 0);
    }

    function test_dealerStatus_refundableOnCancelledSeason() public {
        bankHeist.openSeason(_defaultConfig());
        _enter(player1, tA);
        bankHeist.cancelSeason(0);

        DealersMulticall.HeistDealerStatus memory st = multicall.getHeistDealerStatus(0, tA);
        assertFalse(st.refunded);
        assertEq(st.refundableCash, ENTRY_FEE);
        assertEq(st.claimableETH, 0);

        vm.prank(player1);
        bankHeist.claimRefund(0, tA);
        st = multicall.getHeistDealerStatus(0, tA);
        assertTrue(st.refunded);
        assertEq(st.refundableCash, 0);
    }

    function test_dealerStatus_refundableOnAbandonedSeason() public {
        bankHeist.openSeason(_defaultConfig());
        _enter(player1, tA);
        _enter(player2, tB);
        IDealersBankHeist.Season memory s = bankHeist.getSeason(0);
        vm.warp(uint256(s.closesAt) + s.config.refundTimeout + 1); // never frozen nor settled

        DealersMulticall.HeistDealerStatus memory st = multicall.getHeistDealerStatus(0, tA);
        assertEq(st.refundableCash, ENTRY_FEE);
    }
}
