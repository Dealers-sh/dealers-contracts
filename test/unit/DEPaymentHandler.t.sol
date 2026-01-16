// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../base/BaseTest.sol";

contract DEPaymentHandlerTest is BaseTest {
    uint256 public constant DEV_FEE_PERCENT = 500;
    uint256 public constant BANK_FEE_PERCENT = 500;
    uint256 public constant GAME_FEE_PERCENT = 1000;

    uint8 public constant WIN = 0;
    uint8 public constant TIE = 1;
    uint8 public constant LOSS = 2;

    address public authorizedCaller;

    function setUp() public override {
        super.setUp();
        authorizedCaller = makeAddr("authorizedCaller");
        vm.deal(authorizedCaller, 100 ether);
        vm.prank(owner);
        paymentHandler.authorizeContract(authorizedCaller, true);
    }

    // =============================================================
    //                     FEE CALCULATION TESTS
    // =============================================================

    function test_calculateFees_5PercentDev() public view {
        uint256 amount = 1 ether;
        (uint256 devFee,,,) = paymentHandler.calculateFees(amount);

        uint256 expectedDevFee = (amount * DEV_FEE_PERCENT) / 10000;
        assertEq(devFee, expectedDevFee);
        assertEq(devFee, 0.05 ether);
    }

    function test_calculateFees_5PercentBank() public view {
        uint256 amount = 1 ether;
        (, uint256 bankFee,,) = paymentHandler.calculateFees(amount);

        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;
        assertEq(bankFee, expectedBankFee);
        assertEq(bankFee, 0.05 ether);
    }

    function test_calculateFees_netAmount() public view {
        uint256 amount = 1 ether;
        (,,, uint256 netAmount) = paymentHandler.calculateFees(amount);

        uint256 expectedNet = amount - (amount * GAME_FEE_PERCENT) / 10000;
        assertEq(netAmount, expectedNet);
        assertEq(netAmount, 0.9 ether);
    }

    function test_calculateFees_totalIs10Percent() public view {
        uint256 amount = 1 ether;
        (uint256 devFee, uint256 bankFee, uint256 totalFee,) = paymentHandler.calculateFees(amount);

        assertEq(totalFee, devFee + bankFee);
        assertEq(totalFee, 0.1 ether);
    }

    // =============================================================
    //                    PAYOUT CALCULATION TESTS
    // =============================================================

    function test_calculatePayout_win2xMinusFee() public view {
        uint256 stakeAmount = 1 ether;
        uint256 payout = paymentHandler.calculatePayout(stakeAmount, WIN);

        uint256 totalFee = (stakeAmount * GAME_FEE_PERCENT) / 10000;
        uint256 expectedPayout = (stakeAmount * 2) - totalFee;
        assertEq(payout, expectedPayout);
        assertEq(payout, 1.9 ether);
    }

    function test_calculatePayout_tie1xMinusFee() public view {
        uint256 stakeAmount = 1 ether;
        uint256 payout = paymentHandler.calculatePayout(stakeAmount, TIE);

        uint256 totalFee = (stakeAmount * GAME_FEE_PERCENT) / 10000;
        uint256 expectedPayout = stakeAmount - totalFee;
        assertEq(payout, expectedPayout);
        assertEq(payout, 0.9 ether);
    }

    function test_calculatePayout_lossZero() public view {
        uint256 stakeAmount = 1 ether;
        uint256 payout = paymentHandler.calculatePayout(stakeAmount, LOSS);

        assertEq(payout, 0);
    }

    function test_calculatePayout_handlesLargeAmounts() public view {
        uint256 stakeAmount = 1000 ether;

        uint256 winPayout = paymentHandler.calculatePayout(stakeAmount, WIN);
        uint256 tiePayout = paymentHandler.calculatePayout(stakeAmount, TIE);
        uint256 lossPayout = paymentHandler.calculatePayout(stakeAmount, LOSS);

        assertEq(winPayout, 1900 ether);
        assertEq(tiePayout, 900 ether);
        assertEq(lossPayout, 0);
    }

    // =============================================================
    //                     STAKED BET TESTS
    // =============================================================

    function test_processStakedBet_splitsFees() public {
        uint256 amount = 1 ether;
        uint256 expectedDevFee = (amount * DEV_FEE_PERCENT) / 10000;
        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;

        uint256 bankBalanceBefore = bankVault.balance;

        vm.prank(authorizedCaller);
        paymentHandler.processStakedBet{value: amount}(amount);

        assertEq(paymentHandler.totalDevFees(), expectedDevFee);
        assertEq(paymentHandler.totalBankFees(), expectedBankFee);
        assertEq(bankVault.balance, bankBalanceBefore + expectedBankFee);
    }

    function test_processStakedBet_sendsBankFeeImmediate() public {
        uint256 amount = 1 ether;
        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;

        uint256 bankBalanceBefore = bankVault.balance;

        vm.prank(authorizedCaller);
        paymentHandler.processStakedBet{value: amount}(amount);

        assertEq(bankVault.balance, bankBalanceBefore + expectedBankFee);
    }

    function test_processStakedBet_accruesDevFee() public {
        uint256 amount = 1 ether;
        uint256 expectedDevFee = (amount * DEV_FEE_PERCENT) / 10000;

        vm.prank(authorizedCaller);
        paymentHandler.processStakedBet{value: amount}(amount);

        assertEq(paymentHandler.pendingDevWithdrawal(), expectedDevFee);
        assertEq(paymentHandler.getPendingDevFees(), expectedDevFee);
    }

    function test_processStakedBet_revertNotAuthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.deal(unauthorized, 10 ether);
        uint256 amount = 1 ether;

        vm.prank(unauthorized);
        vm.expectRevert(DEPaymentHandler.NotAuthorized.selector);
        paymentHandler.processStakedBet{value: amount}(amount);
    }

    function test_processStakedBet_revertWrongAmount() public {
        uint256 declaredAmount = 1 ether;
        uint256 sentAmount = 0.5 ether;

        vm.prank(authorizedCaller);
        vm.expectRevert(DEPaymentHandler.InvalidAmount.selector);
        paymentHandler.processStakedBet{value: sentAmount}(declaredAmount);
    }

    // =============================================================
    //                     GAME PAYOUT TESTS
    // =============================================================

    function test_processGamePayout_winPaysOut() public {
        uint256 stakeAmount = 1 ether;
        uint256 expectedPayout = paymentHandler.calculatePayout(stakeAmount, WIN);

        vm.deal(address(paymentHandler), 10 ether);

        uint256 playerBalanceBefore = player1.balance;

        vm.prank(authorizedCaller);
        paymentHandler.processGamePayout(player1, WIN, stakeAmount);

        assertEq(player1.balance, playerBalanceBefore + expectedPayout);
        assertEq(paymentHandler.totalPayouts(), expectedPayout);
    }

    function test_processGamePayout_tiePaysOut() public {
        uint256 stakeAmount = 1 ether;
        uint256 expectedPayout = paymentHandler.calculatePayout(stakeAmount, TIE);

        vm.deal(address(paymentHandler), 10 ether);

        uint256 playerBalanceBefore = player1.balance;

        vm.prank(authorizedCaller);
        paymentHandler.processGamePayout(player1, TIE, stakeAmount);

        assertEq(player1.balance, playerBalanceBefore + expectedPayout);
        assertEq(paymentHandler.totalPayouts(), expectedPayout);
    }

    function test_processGamePayout_lossPaysNothing() public {
        uint256 stakeAmount = 1 ether;

        vm.deal(address(paymentHandler), 10 ether);

        uint256 playerBalanceBefore = player1.balance;
        uint256 contractBalanceBefore = address(paymentHandler).balance;

        vm.prank(authorizedCaller);
        paymentHandler.processGamePayout(player1, LOSS, stakeAmount);

        assertEq(player1.balance, playerBalanceBefore);
        assertEq(address(paymentHandler).balance, contractBalanceBefore);
        assertEq(paymentHandler.totalPayouts(), 0);
    }

    function test_processGamePayout_revertInsufficientBalance() public {
        uint256 stakeAmount = 1 ether;

        vm.prank(authorizedCaller);
        vm.expectRevert(DEPaymentHandler.InsufficientBalance.selector);
        paymentHandler.processGamePayout(player1, WIN, stakeAmount);
    }

    // =============================================================
    //                     WITHDRAWAL TESTS
    // =============================================================

    function test_withdrawDevFees_sendsToDevWallet() public {
        uint256 amount = 1 ether;
        uint256 expectedDevFee = (amount * DEV_FEE_PERCENT) / 10000;

        vm.prank(authorizedCaller);
        paymentHandler.processStakedBet{value: amount}(amount);

        uint256 devBalanceBefore = devWallet.balance;

        vm.prank(devWallet);
        paymentHandler.withdrawDevFees();

        assertEq(devWallet.balance, devBalanceBefore + expectedDevFee);
    }

    function test_withdrawDevFees_resetsPending() public {
        uint256 amount = 1 ether;

        vm.prank(authorizedCaller);
        paymentHandler.processStakedBet{value: amount}(amount);

        assertTrue(paymentHandler.pendingDevWithdrawal() > 0);

        vm.prank(devWallet);
        paymentHandler.withdrawDevFees();

        assertEq(paymentHandler.pendingDevWithdrawal(), 0);
    }

    function test_withdrawDevFees_revertNoFees() public {
        vm.prank(devWallet);
        vm.expectRevert(DEPaymentHandler.NoFeesToWithdraw.selector);
        paymentHandler.withdrawDevFees();
    }

    function test_withdrawDevFees_onlyDevOrOwner() public {
        uint256 amount = 1 ether;

        vm.prank(authorizedCaller);
        paymentHandler.processStakedBet{value: amount}(amount);

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(DEPaymentHandler.NotAuthorized.selector);
        paymentHandler.withdrawDevFees();

        uint256 devBalanceBefore = devWallet.balance;
        uint256 expectedDevFee = (amount * DEV_FEE_PERCENT) / 10000;

        vm.prank(owner);
        paymentHandler.withdrawDevFees();

        assertEq(devWallet.balance, devBalanceBefore + expectedDevFee);
    }

    // =============================================================
    //                        ADMIN TESTS
    // =============================================================

    function test_authorizeContract_grantsAccess() public {
        address newContract = makeAddr("newContract");
        vm.deal(newContract, 10 ether);

        assertFalse(paymentHandler.authorizedContracts(newContract));

        vm.prank(owner);
        paymentHandler.authorizeContract(newContract, true);

        assertTrue(paymentHandler.authorizedContracts(newContract));

        vm.prank(newContract);
        paymentHandler.processStakedBet{value: 1 ether}(1 ether);
    }

    function test_authorizeContract_revokesAccess() public {
        assertTrue(paymentHandler.authorizedContracts(authorizedCaller));

        vm.prank(owner);
        paymentHandler.authorizeContract(authorizedCaller, false);

        assertFalse(paymentHandler.authorizedContracts(authorizedCaller));

        vm.prank(authorizedCaller);
        vm.expectRevert(DEPaymentHandler.NotAuthorized.selector);
        paymentHandler.processStakedBet{value: 1 ether}(1 ether);
    }

    function test_setDevWallet_changes() public {
        address newDevWallet = makeAddr("newDevWallet");

        assertEq(paymentHandler.devWallet(), devWallet);

        vm.prank(owner);
        paymentHandler.setDevWallet(newDevWallet);

        assertEq(paymentHandler.devWallet(), newDevWallet);
    }

    function test_setBankVault_changes() public {
        address newBankVault = makeAddr("newBankVault");

        assertEq(paymentHandler.bankVault(), bankVault);

        vm.prank(owner);
        paymentHandler.setBankVault(newBankVault);

        assertEq(paymentHandler.bankVault(), newBankVault);
    }
}
