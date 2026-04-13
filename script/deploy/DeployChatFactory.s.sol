// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployDealersChatFactory
 * @dev Constructor deps: DEALERS_NFT
 *      Post-deploy: run SetupChat.s.sol to create the WORLD chat room
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployDealersChatFactory.s.sol:DeployDealersChatFactory \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployDealersChatFactory is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");

        vm.startBroadcast();
        chatFactory = _zkCreate(abi.encodePacked(
            vm.getCode("DealersChatFactory.sol:DealersChatFactory"),
            abi.encode(nft)
        ));
        vm.stopBroadcast();

        _saveAddresses();
        console.log("DealersChatFactory deployed:", chatFactory);
        console.log("");
        console.log("Next: run SetupChat.s.sol to create the WORLD room");
    }
}
