// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployActions - Redeploy the actions module and re-wire every edge that touches it
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, AREA_REGISTRY. The core reference is
 *      constructor-only — this script is also the mandatory follow-up to a Core redeploy.
 *      Wires (idempotent): Core auth, PaymentHandler auth, Randomness resolver, Actions refs
 *      (paymentHandler/randomness), jailer auths for PVE/PVP/Heists, and the actions ref on
 *      PVE/PVP/Heists.
 *
 *      STATE ABANDONED on redeploy: pending commit-reveal actions (breakouts, wanted posters,
 *      area moves in flight). Jail/area state itself lives in Core and survives.
 *
 *      Mainnet requires CONFIRM=DealersActions in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployActions.s.sol:DeployActions \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployActions is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _guardMainnet("DealersActions");

        console.log("WARNING: in-flight action commits (breakouts/posters/moves) become unresolvable.");
        console.log("");

        vm.startBroadcast();
        actions = _zkCreate(
            abi.encodePacked(vm.getCode("DealersActions.sol:DealersActions"), abi.encode(core, nft, areaRegistry))
        );
        console.log("DealersActions deployed:", actions);
        _wireActions();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
