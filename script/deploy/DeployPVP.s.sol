// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployPVP - Redeploy the PVP module and re-wire every edge that touches it
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, AREA_REGISTRY.
 *      Wires (idempotent): Core auth, Randomness resolver, Actions jailer, PVP refs
 *      (drugRegistry/randomness/actions), Claims.setPVP, Multicall.setPVP, BankHeist ref sync.
 *
 *      STATE ABANDONED on redeploy: pending battle commits, attack cooldowns/daily counters,
 *      and per-dealer lifetime PVP stats — which feed Claims achievement progress and
 *      BankHeist season baselines. Let pending battles drain first.
 *
 *      Mainnet requires CONFIRM=DealersPVP in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployPVP.s.sol:DeployPVP \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployPVP is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _guardMainnet("DealersPVP");

        console.log("WARNING: pending battles + lifetime PVP stats (achievements/seasons) reset.");
        console.log("");

        vm.startBroadcast();
        pvp = _zkCreate(abi.encodePacked(vm.getCode("DealersPVP.sol:DealersPVP"), abi.encode(core, nft, areaRegistry)));
        console.log("DealersPVP deployed:", pvp);
        _wirePVP();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupRebalance.s.sol only if retuning (constructor ships the sim PVP config)");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
