// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IDealersChatRoom} from "./IDealersChatRoom.sol";

/**
 * @title DealersChatRoom - Circular Buffer Message Storage
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Stores up to 64 messages in a circular buffer. Oldest messages
 *      are overwritten when the buffer is full. Only the factory
 *      contract can post messages.
 * @author Berny0x
 */
contract DealersChatRoom is IDealersChatRoom {
    uint256 private constant BUFFER_SIZE = 64;

    address public immutable factory;

    uint256 private _messageCount;
    Message[64] private _messages;

    constructor(address _factory) {
        factory = _factory;
    }

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    function postMessage(uint16 tokenId, string calldata text) external {
        if (msg.sender != factory) revert NotFactory();

        uint256 index;
        unchecked {
            index = _messageCount & 63;
            ++_messageCount;
        }

        _messages[index] = Message({
            tokenId: tokenId,
            timestamp: uint40(block.timestamp),
            text: text
        });

        emit MessagePosted(tokenId, uint40(block.timestamp), text);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    function getMessage(uint256 index) external view returns (Message memory) {
        uint256 mc = _messageCount;
        uint256 available = mc < BUFFER_SIZE ? mc : BUFFER_SIZE;
        if (index >= available) revert IndexOutOfBounds();

        unchecked {
            uint256 oldest = _oldestSlot(mc);
            return _messages[(oldest + index) & 63];
        }
    }

    function getMessages(uint256 offset, uint256 count) external view returns (Message[] memory) {
        uint256 mc = _messageCount;
        uint256 available = mc < BUFFER_SIZE ? mc : BUFFER_SIZE;
        if (offset >= available) return new Message[](0);

        unchecked {
            uint256 remaining = available - offset;
            if (count > remaining) count = remaining;

            Message[] memory result = new Message[](count);
            uint256 startSlot = (_oldestSlot(mc) + offset) & 63;

            for (uint256 i = 0; i < count; ++i) {
                result[i] = _messages[(startSlot + i) & 63];
            }
            return result;
        }
    }

    function getLatestMessages(uint256 count) external view returns (Message[] memory) {
        uint256 mc = _messageCount;
        uint256 available = mc < BUFFER_SIZE ? mc : BUFFER_SIZE;
        if (count > available) count = available;
        if (count == 0) return new Message[](0);

        Message[] memory result = new Message[](count);
        unchecked {
            uint256 startIndex = (mc - count) & 63;
            for (uint256 i = 0; i < count; ++i) {
                result[i] = _messages[(startIndex + i) & 63];
            }
        }
        return result;
    }

    function getMessageCount() external view returns (uint256) {
        uint256 mc = _messageCount;
        return mc < BUFFER_SIZE ? mc : BUFFER_SIZE;
    }

    function totalMessages() external view returns (uint256) {
        return _messageCount;
    }

    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

    function _oldestSlot(uint256 mc) private pure returns (uint256) {
        return mc <= BUFFER_SIZE ? 0 : mc & 63;
    }
}
