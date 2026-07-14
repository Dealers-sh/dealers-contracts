// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployRandomness - Redeploy the randomness provider and re-wire every edge that touches it
 * @dev Constructor deps: none.
 *      Wires (idempotent): authorizes PVE/PVP/Actions/Heists as resolvers on the new instance,
 *      repoints the randomness ref on PVE/PVP/Actions, and syncs the Heists ref.
 *
 *      STATE ABANDONED on redeploy: pending commits. Any in-flight PVE/PVP/Actions round that
 *      committed against the old instance can no longer resolve — let pending rounds drain
 *      (resolve or expire) before switching.
 *
 *      Mainnet requires CONFIRM=DealersRandomness in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployRandomness.s.sol:DeployRandomness \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployRandomness is WiringBase {
    function run() external {
        _loadAddresses();
        _guardMainnet("DealersRandomness");

        console.log("WARNING: in-flight commit-reveal rounds on the old instance become unresolvable.");
        console.log("");

        vm.startBroadcast();
        randomness = _zkCreate(vm.getCode("DealersRandomness.sol:DealersRandomness"));
        console.log("DealersRandomness deployed:", randomness);
        _wireRandomness();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
