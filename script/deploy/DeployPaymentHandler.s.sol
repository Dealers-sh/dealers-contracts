// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployPaymentHandler - Redeploy the fee router and re-wire every edge that touches it
 * @dev Constructor deps: DEV_WALLET, BANK_VAULT (network-prefixed env).
 *      Wires (idempotent): authorizes Core/Boosts/Actions/Heists on the new handler, repoints the
 *      paymentHandler ref on Core/Boosts/Actions, and syncs the Heists ref.
 *
 *      STATE: the handler is a pass-through (no balances held), but the new instance's bankVault
 *      comes from BANK_VAULT env — if the BankHeist event is live as the vault, repoint it after
 *      deploying (setBankVault). The wire step prints a warning when they disagree.
 *
 *      Mainnet requires CONFIRM=DealersPaymentHandler in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployPaymentHandler.s.sol:DeployPaymentHandler \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployPaymentHandler is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(devWallet, "DEV_WALLET");
        _requireAddress(bankVault, "BANK_VAULT");
        _guardMainnet("DealersPaymentHandler");

        address oldHandler = paymentHandler;

        vm.startBroadcast();
        paymentHandler = _zkCreate(
            abi.encodePacked(
                vm.getCode("DealersPaymentHandler.sol:DealersPaymentHandler"), abi.encode(devWallet, bankVault)
            )
        );
        console.log("DealersPaymentHandler deployed:", paymentHandler);
        console.log("  Old:", oldHandler);
        _wirePaymentHandler();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. If the bank-heist event is live: setBankVault(bankHeist) on the new handler");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
