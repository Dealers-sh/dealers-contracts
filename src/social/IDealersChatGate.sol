// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDealersChatGate - Chat Room Access Gate Interface
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Implementations check whether a dealer is allowed to post in a room.
 *      The factory calls canPost before routing each message.
 * @author Berny0x
 */
interface IDealersChatGate {
    /**
     * @param tokenId The dealer's NFT token ID
     * @param roomId The room-type-specific identifier (area ID, gang ID, etc.)
     * @return allowed Whether the dealer can post in this room
     */
    function canPost(uint16 tokenId, uint8 roomId) external view returns (bool allowed);
}
