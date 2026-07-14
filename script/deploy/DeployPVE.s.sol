// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployPVE - Redeploy the PVE module and re-wire every edge that touches it
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, AREA_REGISTRY.
 *      Wires (idempotent): Core auth, Randomness resolver, Actions jailer, PVE refs
 *      (randomness/actions), Claims.setPVE, Multicall.setPVE, BankHeist ref sync.
 *
 *      STATE ABANDONED on redeploy: pending commit-reveal rounds (stakes debited but
 *      unresolvable) and per-dealer lifetime PVE stats — which feed Claims achievement
 *      progress and BankHeist season baselines. Let pending rounds drain first.
 *
 *      Mainnet requires CONFIRM=DealersPVE in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployPVE.s.sol:DeployPVE \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployPVE is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _guardMainnet("DealersPVE");

        console.log("WARNING: pending PVE rounds + lifetime PVE stats (achievements/seasons) reset.");
        console.log("");

        vm.startBroadcast();
        pve = _zkCreate(abi.encodePacked(vm.getCode("DealersPVE.sol:DealersPVE"), abi.encode(core, nft, areaRegistry)));
        console.log("DealersPVE deployed:", pve);
        _wirePVE();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupRebalance.s.sol only if retuning (constructor ships sim odds + stake scaling)");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
