// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployRandomness
 * @dev Constructor deps: none
 *      Post-deploy: PVE.setRandomness + PVP.setRandomness
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployRandomness.s.sol:DeployRandomness \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployRandomness is DeployBase {
    function run() external {
        _loadAddresses();

        vm.startBroadcast();
        randomness = _zkCreate(vm.getCode("DealersRandomness.sol:DealersRandomness"));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersRandomness deployed:", randomness);
        console.log("");
        console.log("Next: run SetupWiring.s.sol");
    }
}
