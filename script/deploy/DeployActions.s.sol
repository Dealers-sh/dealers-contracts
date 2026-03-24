// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployActions
 * @dev Constructor deps: DEALERS_CORE, DEALERS_NFT, AREA_REGISTRY
 *      Post-deploy:
 *        - Core.authorizeContract(actions, true)
 *        - PaymentHandler.authorizeContract(actions, true)
 *        - Randomness.authorizeResolver(actions, true)
 *        - Actions.setPaymentHandler(paymentHandler)
 *        - Actions.setRandomness(randomness)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployActions.s.sol:DeployActions \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 */
contract DeployActions is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(areaRegistry, "AREA_REGISTRY");

        vm.startBroadcast();
        actions = _zkCreate(abi.encodePacked(
            vm.getCode("DealersExeActions.sol:DealersExeActions"),
            abi.encode(core, nft, areaRegistry)
        ));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersExeActions deployed:", actions);
        console.log("");
        console.log("Next: run SetupWiring.s.sol to wire references + authorizations");
    }
}
