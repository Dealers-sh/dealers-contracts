// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployDrugRegistry
 * @dev Constructor deps: none
 *      Post-deploy: authorize Core in DrugRegistry
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployDrugRegistry.s.sol:DeployDrugRegistry \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployDrugRegistry is DeployBase {
    function run() external {
        _loadAddresses();

        vm.startBroadcast();
        drugRegistry = _zkCreate(vm.getCode("DealersDrugRegistry.sol:DealersDrugRegistry"));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersDrugRegistry deployed:", drugRegistry);
        console.log("");
        console.log("Next: run SetupWiring.s.sol");
    }
}
