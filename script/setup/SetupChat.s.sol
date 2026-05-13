// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";
import {DealersChatFactory} from "../../src/social/DealersChatFactory.sol";
import {DealersAreaChatGate} from "../../src/social/DealersAreaChatGate.sol";

/**
 * @title SetupChat - Create WORLD room and area chat rooms
 * @dev Creates:
 *      - WORLD room (ungated)
 *      - Area rooms for areas 1-6, 254 (Black Market), 255 (Jail) with DealersAreaChatGate
 *      - Skips Safe House (area 0)
 *
 * Usage:
   source .env && forge script script/setup/SetupChat.s.sol:SetupChat \
     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
     --skip "RendererSVG"
 */
contract SetupChat is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(chatFactory, "CHAT_FACTORY");
        _requireAddress(core, "DEALERS_CORE");

        DealersChatFactory factory = DealersChatFactory(chatFactory);

        vm.startBroadcast();

        _createWorldRoom(factory);
        address gate = _deployAreaGate();
        _createAreaRooms(factory, gate);

        vm.stopBroadcast();
    }

    function _createWorldRoom(DealersChatFactory factory) internal {
        bytes32 worldKey = factory.roomKey(DealersChatFactory.RoomType.WORLD, 0);
        (address existing,,) = factory.getRoomInfo(worldKey);

        if (existing != address(0)) {
            console.log("WORLD room: exists, skipping");
        } else {
            address room = factory.createRoom(DealersChatFactory.RoomType.WORLD, 0, address(0));
            console.log("WORLD room created:", room);
        }
    }

    function _deployAreaGate() internal returns (address gate) {
        gate = address(new DealersAreaChatGate(core));
        console.log("DealersAreaChatGate deployed:", gate);
    }

    function _createAreaRooms(DealersChatFactory factory, address gate) internal {
        uint8[9] memory areas = [uint8(1), 2, 3, 4, 5, 6, 7, 254, 255];

        for (uint256 i = 0; i < areas.length; ++i) {
            uint8 areaId = areas[i];
            bytes32 key = factory.roomKey(DealersChatFactory.RoomType.AREA, areaId);
            (address existing,,) = factory.getRoomInfo(key);

            if (existing != address(0)) {
                console.log("  Area", areaId, "room: exists, skipping");
            } else {
                factory.createRoom(DealersChatFactory.RoomType.AREA, areaId, gate);
                console.log("  Area", areaId, "room: created");
            }
        }
    }
}
