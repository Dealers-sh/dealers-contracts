// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IChatGate} from "./IChatGate.sol";
import {IDealersExeCore} from "../core/IDealersExeCore.sol";

/**
 * @title AreaChatGate - Gates chat rooms by dealer's current area
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Reads the dealer's current area from DealersExeCore and checks
 *      it matches the room's area ID.
 *      chat in the jail room.
 * @author HeadmasterBerny
 */
contract AreaChatGate is IChatGate {
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
