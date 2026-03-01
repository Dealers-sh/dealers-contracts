// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployPaymentHandler
 * @dev Deploys a new DEPaymentHandler, saves the address, and re-wires all
 *      contracts that reference it (Core, Boosts) + authorizes Core and Boosts.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployPaymentHandler.s.sol:DeployPaymentHandler \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract DeployPaymentHandler is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(devWallet, "DEV_WALLET");
        _requireAddress(bankVault, "BANK_VAULT");
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(boosts, "DEALERS_BOOSTS");

        address oldHandler = paymentHandler;

        vm.startBroadcast();

        paymentHandler = _zkCreate(abi.encodePacked(
            vm.getCode("DEPaymentHandler.sol:DEPaymentHandler"),
            abi.encode(devWallet, bankVault)
        ));
        console.log("DEPaymentHandler deployed:", paymentHandler);
        console.log("  Old:", oldHandler);

        IPaymentHandler ph = IPaymentHandler(paymentHandler);
        if (!ph.authorizedContracts(core)) ph.authorizeContract(core, true);
        if (!ph.authorizedContracts(boosts)) ph.authorizeContract(boosts, true);
        console.log("  Authorized: Core, Boosts");

        IDealersExeCore(core).setPaymentHandler(paymentHandler);
        console.log("  Core -> PaymentHandler: SET");

        IBoostsContract(boosts).setPaymentHandler(paymentHandler);
        console.log("  Boosts -> PaymentHandler: SET");

        vm.stopBroadcast();

        _saveAddresses();
    }
}
