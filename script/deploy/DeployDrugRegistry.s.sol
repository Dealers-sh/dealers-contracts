// SPDX-License-Identifier: MIT
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
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract DeployDrugRegistry is DeployBase {
    function run() external {
        _loadAddresses();

        vm.startBroadcast();
        drugRegistry = _zkCreate(vm.getCode("DEDrugRegistry.sol:DEDrugRegistry"));
        vm.stopBroadcast();

        console.log("DEDrugRegistry deployed:", drugRegistry);
        console.log("");
        console.log("Next: update DRUG_REGISTRY in .env, then run SetupWiring.s.sol");
    }
}
