// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";

contract DealersExeActionsTest is BaseTest {
    uint256 dealerToken;

    uint8 constant AREA_MANHATTAN = 1;
    uint8 constant AREA_BLACK_MARKET = 254;

    uint256 constant DRUG_GENERAL_GOODS = 1;
    uint256 constant DRUG_CONTRABAND = 2;
    uint256 constant DRUG_JEWELS = 3;

    uint256 constant RATE_GENERAL_GOODS = 75;
    uint256 constant RATE_CONTRABAND = 500;
    uint256 constant RATE_JEWELS = 2500;

    function setUp() public override {
        super.setUp();

        dealerToken = _mintAndInitialize(player1);
    }

    function _giveDrops(uint256 tokenId, uint256 drugId, uint256 amount) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.updateDrugBalance(tokenId, drugId, int256(amount));
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    function _moveToBlackMarket(uint256 tokenId, address player) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        (, uint256 rep,,,,) = core.getDealerData(tokenId);
        if (rep < 250) {
            core.updateReputation(tokenId, int256(250) - int256(rep));
        }
        core.authorizeContract(address(this), false);
        vm.stopPrank();

        vm.prank(player);
        actions.travel{value: 0}(tokenId, AREA_BLACK_MARKET);
    }

    function _forceToArea(uint256 tokenId, uint8 areaId) internal {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.forceMove(tokenId, areaId);
        vm.prank(owner);
        core.authorizeContract(address(this), false);
    }

    // =============================================================
    //                     SELL DROP (6 tests)
    // =============================================================

    function test_sellDrop_success_generalGoods() public {
        _moveToBlackMarket(dealerToken, player1);
        _giveDrops(dealerToken, DRUG_GENERAL_GOODS, 5);

        uint256 cashBefore = core.getCashBalance(dealerToken);
        uint256 drugBefore = core.getDrugBalance(dealerToken, DRUG_GENERAL_GOODS);

        vm.prank(player1);
        actions.sellDrop(dealerToken, DRUG_GENERAL_GOODS, 3);

        assertEq(core.getDrugBalance(dealerToken, DRUG_GENERAL_GOODS), drugBefore - 3, "Drug balance reduced");
        assertEq(core.getCashBalance(dealerToken), cashBefore + 3 * RATE_GENERAL_GOODS, "Cash increased correctly");
    }

    function test_sellDrop_success_jewels() public {
        _moveToBlackMarket(dealerToken, player1);
        _giveDrops(dealerToken, DRUG_JEWELS, 2);

        uint256 cashBefore = core.getCashBalance(dealerToken);

        vm.prank(player1);
        actions.sellDrop(dealerToken, DRUG_JEWELS, 2);

        assertEq(core.getCashBalance(dealerToken), cashBefore + 2 * RATE_JEWELS, "Jewels converted at correct rate");
        assertEq(core.getDrugBalance(dealerToken, DRUG_JEWELS), 0, "Jewels balance emptied");
    }

    function test_sellDrop_revertNotInBlackMarket() public {
        _giveDrops(dealerToken, DRUG_GENERAL_GOODS, 5);

        vm.prank(player1);
        vm.expectRevert(DealersExeActions.NotInBlackMarket.selector);
        actions.sellDrop(dealerToken, DRUG_GENERAL_GOODS, 1);
    }

    function test_sellDrop_revertNotSellableDrop() public {
        _moveToBlackMarket(dealerToken, player1);

        uint256 unsellableDrugId = 4; // Weed is not configured in Black Market

        vm.prank(player1);
        vm.expectRevert(DealersExeActions.NotSellableDrop.selector);
        actions.sellDrop(dealerToken, unsellableDrugId, 1);
    }

    function test_sellDrop_revertZeroAmount() public {
        _moveToBlackMarket(dealerToken, player1);
        _giveDrops(dealerToken, DRUG_GENERAL_GOODS, 5);

        vm.prank(player1);
        vm.expectRevert(DealersExeActions.InvalidAmount.selector);
        actions.sellDrop(dealerToken, DRUG_GENERAL_GOODS, 0);
    }

    function test_sellDrop_revertNotOwner() public {
        _moveToBlackMarket(dealerToken, player1);
        _giveDrops(dealerToken, DRUG_GENERAL_GOODS, 5);

        vm.prank(player2);
        vm.expectRevert(DealersExeActions.NotDealerOwner.selector);
        actions.sellDrop(dealerToken, DRUG_GENERAL_GOODS, 1);
    }

    // =============================================================
    //                  BLACK MARKET TRAVEL (4 tests)
    // =============================================================

    function test_travel_toBlackMarket_isFree() public {
        vm.prank(owner);
        core.authorizeContract(address(this), true);
        core.updateReputation(dealerToken, 250);
        vm.prank(owner);
        core.authorizeContract(address(this), false);

        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        actions.travel{value: 0}(dealerToken, AREA_BLACK_MARKET);

        assertEq(player1.balance, balanceBefore, "No ETH charged for BM entry");
        assertEq(core.getGameState(dealerToken).currentArea, AREA_BLACK_MARKET, "Dealer entered BM");
    }

    function test_travel_fromBlackMarket_returnsToCorrectArea() public {
        _moveOutOfSafeHouse(dealerToken);
        _forceToArea(dealerToken, AREA_BLACK_MARKET);

        vm.prank(player1);
        actions.travel{value: 0}(dealerToken, AREA_BLACK_MARKET);

        assertEq(core.getGameState(dealerToken).currentArea, AREA_MANHATTAN, "Dealer returned to previousArea");
    }

    function test_travel_fromBlackMarket_destinationParamIgnored() public {
        uint8 AREA_COLOMBIA = 2;
        _moveOutOfSafeHouse(dealerToken);
        _forceToArea(dealerToken, AREA_BLACK_MARKET);

        vm.prank(player1);
        actions.travel{value: 0}(dealerToken, AREA_COLOMBIA);

        assertEq(core.getGameState(dealerToken).currentArea, AREA_MANHATTAN, "Destination param ignored; returned to previousArea");
    }

    function test_travel_fromBlackMarket_exitIsFree() public {
        _moveOutOfSafeHouse(dealerToken);
        _forceToArea(dealerToken, AREA_BLACK_MARKET);

        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        actions.travel{value: 0}(dealerToken, 0);

        assertEq(player1.balance, balanceBefore, "No ETH charged for BM exit");
    }
}
