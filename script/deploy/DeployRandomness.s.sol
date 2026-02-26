// SPDX-License-Identifier: MIT
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
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract DeployRandomness is DeployBase {
    function run() external {
        _loadAddresses();

        vm.startBroadcast();
        randomness = _zkCreate(vm.getCode("DERandomness.sol:DERandomness"));
        vm.stopBroadcast();

        console.log("DERandomness deployed:", randomness);
        console.log("");
        console.log("Next: update RANDOMNESS in .env, then run SetupWiring.s.sol");
    }
}
