// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployLens
 * @dev Constructor deps: DEALERS_CORE, DEALERS_PVE, DEALERS_PVP, AREA_REGISTRY, DRUG_REGISTRY
 *      No post-deploy wiring needed (read-only contract).
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployLens.s.sol:DeployLens \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract DeployLens is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(pve, "DEALERS_PVE");
        _requireAddress(pvp, "DEALERS_PVP");
        _requireAddress(areaRegistry, "AREA_REGISTRY");
        _requireAddress(drugRegistry, "DRUG_REGISTRY");

        vm.startBroadcast();
        address lens = _zkCreate(abi.encodePacked(
            vm.getCode("DealersExeLens.sol:DealersExeLens"),
            abi.encode(core, pve, pvp, areaRegistry, drugRegistry)
        ));
        vm.stopBroadcast();

        console.log("DealersExeLens deployed:", lens);
    }
}
