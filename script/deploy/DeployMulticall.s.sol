// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployMulticall
 * @dev Constructor deps: DEALERS_CORE, DEALERS_PVE, DEALERS_PVP, AREA_REGISTRY, DRUG_REGISTRY
 *      No post-deploy wiring needed (read-only contract).
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployMulticall.s.sol:DeployMulticall \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployMulticall is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _requireAddress(drugRegistry, "DRUG_REGISTRY");

        vm.startBroadcast();
        multicall = _zkCreate(abi.encodePacked(
            vm.getCode("DealersMulticall.sol:DealersMulticall"),
            abi.encode(core, pve, pvp, areaRegistry, drugRegistry)
        ));
        vm.stopBroadcast();

        _saveAddresses();
        console.log("DealersMulticall deployed:", multicall);
    }
}
