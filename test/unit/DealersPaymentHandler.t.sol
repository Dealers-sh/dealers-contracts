// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/BaseTest.sol";

contract DealersPaymentHandlerTest is BaseTest {
    uint256 public constant BANK_FEE_PERCENT = 8000; // 80%

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

    function test_calculateFees_80PercentBank() public view {
        uint256 amount = 1 ether;
        (uint256 bankFee,) = paymentHandler.calculateFees(amount);

        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;
        assertEq(bankFee, expectedBankFee);
        assertEq(bankFee, 0.8 ether);
    }

    function test_calculateFees_20PercentDev() public view {
        uint256 amount = 1 ether;
        (, uint256 devFee) = paymentHandler.calculateFees(amount);

        uint256 expectedDevFee = amount - (amount * BANK_FEE_PERCENT) / 10000;
        assertEq(devFee, expectedDevFee);
        assertEq(devFee, 0.2 ether);
    }

    function test_calculateFees_sumsToTotal() public view {
        uint256 amount = 1 ether;
        (uint256 bankFee, uint256 devFee) = paymentHandler.calculateFees(amount);

        assertEq(bankFee + devFee, amount);
    }

    // =============================================================
    //                     FEE PROCESSING TESTS
    // =============================================================

    function test_processMovementFee_splitsFees() public {
        uint256 amount = 0.001 ether;
        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;
        uint256 expectedDevFee = amount - expectedBankFee;

        uint256 bankBalanceBefore = bankVault.balance;

        vm.prank(authorizedCaller);
        paymentHandler.processMovementFee{value: amount}(player1, amount);

        assertEq(paymentHandler.totalDevFees(), expectedDevFee);
        assertEq(paymentHandler.totalBankFees(), expectedBankFee);
        assertEq(bankVault.balance, bankBalanceBefore + expectedBankFee);
    }

    function test_processMovementFee_sendsBankFeeImmediate() public {
        uint256 amount = 0.001 ether;
        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;

        uint256 bankBalanceBefore = bankVault.balance;

        vm.prank(authorizedCaller);
        paymentHandler.processMovementFee{value: amount}(player1, amount);

        assertEq(bankVault.balance, bankBalanceBefore + expectedBankFee);
    }

    function test_processMovementFee_retainsDevFee() public {
        uint256 amount = 0.001 ether;
        uint256 expectedDevFee = amount - (amount * BANK_FEE_PERCENT) / 10000;

        vm.prank(authorizedCaller);
        paymentHandler.processMovementFee{value: amount}(player1, amount);

        assertEq(address(paymentHandler).balance, expectedDevFee);
        assertEq(paymentHandler.getContractBalance(), expectedDevFee);
    }

    function test_processMovementFee_revertNotAuthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.deal(unauthorized, 10 ether);
        uint256 amount = 0.001 ether;

        vm.prank(unauthorized);
        vm.expectRevert(DealersPaymentHandler.NotAuthorized.selector);
        paymentHandler.processMovementFee{value: amount}(player1, amount);
    }

    function test_processMovementFee_revertWrongAmount() public {
        uint256 declaredAmount = 0.002 ether;
        uint256 sentAmount = 0.001 ether;

        vm.prank(authorizedCaller);
        vm.expectRevert(DealersPaymentHandler.InvalidAmount.selector);
        paymentHandler.processMovementFee{value: sentAmount}(player1, declaredAmount);
    }

    function test_processMovementFee_revertAmountTooSmall() public {
        uint256 amount = 0.00009 ether;

        vm.prank(authorizedCaller);
        vm.expectRevert(DealersPaymentHandler.AmountTooSmall.selector);
        paymentHandler.processMovementFee{value: amount}(player1, amount);
    }

    function test_processMarketplaceFee_sameAsMovementFee() public {
        uint256 amount = 1 ether;
        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;
        uint256 expectedDevFee = amount - expectedBankFee;

        uint256 bankBalanceBefore = bankVault.balance;

        vm.prank(authorizedCaller);
        paymentHandler.processMarketplaceFee{value: amount}(player1, amount);

        assertEq(paymentHandler.totalDevFees(), expectedDevFee);
        assertEq(paymentHandler.totalBankFees(), expectedBankFee);
        assertEq(bankVault.balance, bankBalanceBefore + expectedBankFee);
        assertEq(address(paymentHandler).balance, expectedDevFee);
    }

    // =============================================================
    //                     WITHDRAWAL TESTS
    // =============================================================

    function test_withdrawDevFees_sendsToDevWallet() public {
        uint256 amount = 0.001 ether;
        uint256 expectedDevFee = amount - (amount * BANK_FEE_PERCENT) / 10000;

        vm.prank(authorizedCaller);
        paymentHandler.processMovementFee{value: amount}(player1, amount);

        uint256 devBalanceBefore = devWallet.balance;

        vm.prank(devWallet);
        paymentHandler.withdrawDevFees();

        assertEq(devWallet.balance, devBalanceBefore + expectedDevFee);
    }

    function test_withdrawDevFees_drainsBalance() public {
        uint256 amount = 0.001 ether;

        vm.prank(authorizedCaller);
        paymentHandler.processMovementFee{value: amount}(player1, amount);

        assertTrue(address(paymentHandler).balance > 0);

        vm.prank(devWallet);
        paymentHandler.withdrawDevFees();

        assertEq(address(paymentHandler).balance, 0);
    }

    function test_withdrawDevFees_revertNoFees() public {
        vm.prank(devWallet);
        vm.expectRevert(DealersPaymentHandler.NoFeesToWithdraw.selector);
        paymentHandler.withdrawDevFees();
    }

    function test_withdrawDevFees_onlyDevOrOwner() public {
        uint256 amount = 0.001 ether;

        vm.prank(authorizedCaller);
        paymentHandler.processMovementFee{value: amount}(player1, amount);

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(DealersPaymentHandler.NotAuthorized.selector);
        paymentHandler.withdrawDevFees();

        uint256 devBalanceBefore = devWallet.balance;
        uint256 expectedDevFee = amount - (amount * BANK_FEE_PERCENT) / 10000;

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
        paymentHandler.processMovementFee{value: 0.001 ether}(player1, 0.001 ether);
    }

    function test_authorizeContract_revokesAccess() public {
        assertTrue(paymentHandler.authorizedContracts(authorizedCaller));

        vm.prank(owner);
        paymentHandler.authorizeContract(authorizedCaller, false);

        assertFalse(paymentHandler.authorizedContracts(authorizedCaller));

        vm.prank(authorizedCaller);
        vm.expectRevert(DealersPaymentHandler.NotAuthorized.selector);
        paymentHandler.processMovementFee{value: 0.001 ether}(player1, 0.001 ether);
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

    // =============================================================
    //                        EVENT TESTS
    // =============================================================

    function test_processFee_emitsEvent() public {
        uint256 amount = 1 ether;
        uint256 expectedBankFee = (amount * BANK_FEE_PERCENT) / 10000;
        uint256 expectedDevFee = amount - expectedBankFee;

        vm.prank(authorizedCaller);
        vm.expectEmit(true, false, false, true);
        emit DealersPaymentHandler.FeeProcessed(player1, amount, expectedDevFee, expectedBankFee);
        paymentHandler.processMarketplaceFee{value: amount}(player1, amount);
    }
}
