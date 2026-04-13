// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IDealersChatGate} from "./IDealersChatGate.sol";
import {IDealersCore} from "../core/IDealersCore.sol";

/**
 * @title DealersAreaChatGate - Gates chat rooms by dealer's current area
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Reads the dealer's current area from DealersCore and checks
 *      it matches the room's area ID.
 *      chat in the jail room.
 * @author Berny0x
 */
contract DealersAreaChatGate is IDealersChatGate {
    IDealersCore public immutable core;

    error InvalidAddress();

    constructor(address _core) {
        if (_core == address(0)) revert InvalidAddress();
        core = IDealersCore(_core);
    }

    function canPost(uint16 tokenId, uint8 roomId) external view override returns (bool) {
        IDealersCore.GameState memory gs = core.getGameState(tokenId);
        return gs.currentArea == roomId;
    }
}
