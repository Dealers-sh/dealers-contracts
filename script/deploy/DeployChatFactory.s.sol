// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployChatFactory - Redeploy the chat factory and re-wire every edge that touches it
 * @dev Constructor deps: DEALERS_NFT.
 *      Wires (idempotent): ChatFactory -> NFT.
 *
 *      STATE ABANDONED on redeploy: every room (WORLD + areas) and all message history — rooms
 *      are child contracts of the factory. SetupChat re-creates the room set with a fresh
 *      AreaChatGate.
 *
 *      Mainnet requires CONFIRM=DealersChatFactory in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployChatFactory.s.sol:DeployChatFactory \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployChatFactory is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");
        _guardMainnet("DealersChatFactory");

        console.log("WARNING: all chat rooms + history are abandoned with the old factory.");
        console.log("");

        vm.startBroadcast();
        chatFactory =
            _zkCreate(abi.encodePacked(vm.getCode("DealersChatFactory.sol:DealersChatFactory"), abi.encode(nft)));
        console.log("DealersChatFactory deployed:", chatFactory);
        _wireChatFactory();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. SetupChat.s.sol (REQUIRED - recreate WORLD + area rooms with a fresh gate)");
        console.log("  2. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
