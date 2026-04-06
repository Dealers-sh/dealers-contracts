// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployChatFactory
 * @dev Constructor deps: DEALERS_NFT
 *      Post-deploy: run SetupChat.s.sol to create the WORLD chat room
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployChatFactory.s.sol:DeployChatFactory \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployChatFactory is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");

        vm.startBroadcast();
        chatFactory = _zkCreate(abi.encodePacked(
            vm.getCode("ChatFactory.sol:ChatFactory"),
            abi.encode(nft)
        ));
        vm.stopBroadcast();

        _saveAddresses();
        console.log("ChatFactory deployed:", chatFactory);
        console.log("");
        console.log("Next: run SetupChat.s.sol to create the WORLD room");
    }
}
