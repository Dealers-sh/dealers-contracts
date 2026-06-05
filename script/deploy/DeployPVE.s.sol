// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployPVE
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, AREA_REGISTRY
 *      Post-deploy:
 *        - Core.authorizeContract(pve, true)
 *        - PVE.setRandomness(randomness)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployPVE.s.sol:DeployPVE \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployPVE is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        vm.startBroadcast();
        pve = _zkCreate(abi.encodePacked(vm.getCode("DealersPVE.sol:DealersPVE"), abi.encode(core, nft, areaRegistry)));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersPVE deployed:", pve);
        console.log("");
        console.log("Next: run SetupWiring.s.sol");
    }
}
