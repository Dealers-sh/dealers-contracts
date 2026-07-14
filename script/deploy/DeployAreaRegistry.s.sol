// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployAreaRegistry - Redeploy the area registry and re-wire every edge that touches it
 * @dev Constructor deps: DRUG_REGISTRY.
 *      Wires (idempotent): AreaRegistry -> Core/DrugRegistry, plus the areaRegistry refs on
 *      Core, PVE, PVP, Actions, Multicall.
 *
 *      STATE ABANDONED on redeploy: all areas + drug pricing (re-create via SetupAreas) and the
 *      dealer-in-area reverse index (getDealersInArea) — dealers keep their currentArea in Core
 *      and the index re-populates as they move. On mainnet prefer admin functions on the live
 *      registry (createArea, configureAreaDrug, updateMinReputation) over a redeploy.
 *
 *      Mainnet requires CONFIRM=DealersAreaRegistry in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployAreaRegistry.s.sol:DeployAreaRegistry \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployAreaRegistry is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(drugRegistry, "DRUG_REGISTRY");
        _guardMainnet("DealersAreaRegistry");

        console.log("WARNING: fresh registry has ZERO areas until SetupAreas runs; reverse index resets.");
        console.log("");

        vm.startBroadcast();
        areaRegistry = _zkCreate(
            abi.encodePacked(vm.getCode("DealersAreaRegistry.sol:DealersAreaRegistry"), abi.encode(drugRegistry))
        );
        console.log("DealersAreaRegistry deployed:", areaRegistry);
        _wireAreaRegistry();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupAreas.s.sol (REQUIRED - re-create the area ladder + pricing)");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
