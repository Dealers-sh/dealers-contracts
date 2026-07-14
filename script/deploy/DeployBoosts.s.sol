// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployBoosts - Redeploy the boosts module and re-wire every edge that touches it
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, PAYMENT_HANDLER.
 *      Wires (idempotent): Core + PaymentHandler auth, Boosts refs, Multicall.setBoosts.
 *
 *      STATE ABANDONED on redeploy: all ACTIVE player boosts (paid time-limited multipliers
 *      vanish) and purchase history. Consider compensating active-boost holders.
 *
 *      Mainnet requires CONFIRM=DealersBoosts in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployBoosts.s.sol:DeployBoosts \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployBoosts is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(paymentHandler, "PAYMENT_HANDLER");
        _guardMainnet("DealersBoosts");

        console.log("WARNING: active player boosts on the old contract are lost.");
        console.log("");

        vm.startBroadcast();
        boosts = _zkCreate(
            abi.encodePacked(vm.getCode("DealersBoosts.sol:DealersBoosts"), abi.encode(core, nft, paymentHandler))
        );
        console.log("DealersBoosts deployed:", boosts);
        _wireBoosts();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupBoosts.s.sol only if retuning (constructor ships the sim-tuned tiers)");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
