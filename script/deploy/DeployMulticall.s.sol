// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployMulticall - Redeploy the read-aggregation helper and point it at the live contracts
 * @dev Constructor deps: DEALERS_CORE, DEALERS_PVE, DEALERS_PVP, AREA_REGISTRY, DRUG_REGISTRY.
 *      Wires (idempotent): Multicall refs incl. setBoosts + setBankHeist. Stateless views —
 *      nothing on-chain references Multicall, so this is the lowest-risk redeploy in the system.
 *
 *      Mainnet requires CONFIRM=DealersMulticall in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployMulticall.s.sol:DeployMulticall \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployMulticall is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _requireAddress(drugRegistry, "DRUG_REGISTRY");
        _guardMainnet("DealersMulticall");

        vm.startBroadcast();
        multicall = _zkCreate(
            abi.encodePacked(
                vm.getCode("DealersMulticall.sol:DealersMulticall"),
                abi.encode(core, pve, pvp, areaRegistry, drugRegistry)
            )
        );
        console.log("DealersMulticall deployed:", multicall);
        _wireMulticall();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. Rebuild + re-upload app gzip (the app reads views through this address)");
    }
}
