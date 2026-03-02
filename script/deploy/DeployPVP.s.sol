// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployPVP
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, AREA_REGISTRY
 *      Post-deploy:
 *        - Core.authorizeContract(pvp, true)
 *        - PVP.setDrugRegistry(drugRegistry)
 *        - PVP.setRandomness(randomness)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployPVP.s.sol:DeployPVP \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract DeployPVP is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        vm.startBroadcast();
        pvp = _zkCreate(abi.encodePacked(
            vm.getCode("DealersExePVP.sol:DealersExePVP"),
            abi.encode(core, nft, areaRegistry)
        ));
        vm.stopBroadcast();

        _saveAddresses();
        console.log("DealersExePVP deployed:", pvp);
        console.log("");
        console.log("Next: run SetupWiring.s.sol to wire up references and authorizations");
    }
}
