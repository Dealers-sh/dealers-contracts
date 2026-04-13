// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployAreaRegistry
 * @dev Constructor deps: DRUG_REGISTRY
 *      Post-deploy: set Core in AreaRegistry, then run SetupAreas.s.sol
 *
 * WARNING: Redeploying resets the dealer-in-area reverse index (getDealerCountInArea,
 *          getDealersInArea). Dealer locations in Core are NOT affected — dealers keep
 *          their currentArea. The reverse index re-populates as dealers move.
 *          On mainnet with active players, prefer updating the existing registry via
 *          admin functions (createArea, configureAreaDrug, updateMinReputation) instead.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployAreaRegistry.s.sol:DeployAreaRegistry \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployAreaRegistry is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(drugRegistry, "DRUG_REGISTRY");

        vm.startBroadcast();
        areaRegistry = _zkCreate(abi.encodePacked(
            vm.getCode("DEAreaRegistry.sol:DEAreaRegistry"),
            abi.encode(drugRegistry)
        ));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DEAreaRegistry deployed:", areaRegistry);
        console.log("  DrugRegistry:", drugRegistry);
        console.log("");
        console.log("Next: run SetupWiring.s.sol");
    }
}
