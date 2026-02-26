// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployPaymentHandler
 * @dev Constructor deps: DEV_WALLET, BANK_VAULT (EOAs)
 *      Post-deploy: authorize Core and Boosts in PaymentHandler
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

        vm.startBroadcast();
        paymentHandler = _zkCreate(abi.encodePacked(
            vm.getCode("DEPaymentHandler.sol:DEPaymentHandler"),
            abi.encode(devWallet, bankVault)
        ));
        vm.stopBroadcast();

        console.log("DEPaymentHandler deployed:", paymentHandler);
        console.log("  Dev Wallet:", devWallet);
        console.log("  Bank Vault:", bankVault);
        console.log("");
        console.log("Next: update PAYMENT_HANDLER in .env, then run SetupWiring.s.sol");
    }
}
