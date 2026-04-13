// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDEChatGate} from "./IDEChatGate.sol";
import {IDealersExeCore} from "../core/IDealersExeCore.sol";

/**
 * @title DEAreaChatGate - Gates chat rooms by dealer's current area
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Reads the dealer's current area from DealersExeCore and checks
 *      it matches the room's area ID.
 *      chat in the jail room.
 * @author Berny0x
 */
contract DEAreaChatGate is IDEChatGate {
    IDealersExeCore public immutable core;

    error InvalidAddress();

    constructor(address _core) {
        if (_core == address(0)) revert InvalidAddress();
        core = IDealersExeCore(_core);
    }

    function canPost(uint16 tokenId, uint8 roomId) external view override returns (bool) {
        IDealersExeCore.GameState memory gs = core.getGameState(tokenId);
        return gs.currentArea == roomId;
    }
}
