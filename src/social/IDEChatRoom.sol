// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDEChatRoom - Chat Room Interface
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @author Berny0x
 */
interface IDEChatRoom {
    // =============================================================
    //                          STRUCTS
    // =============================================================

    struct Message {
        uint16 tokenId;
        uint40 timestamp;
        string text;
    }

    // =============================================================
    //                          EVENTS
    // =============================================================

    event MessagePosted(uint16 indexed tokenId, uint40 timestamp, string text);

    // =============================================================
    //                          ERRORS
    // =============================================================

    error NotFactory();
    error IndexOutOfBounds();

    // =============================================================
    //                    STATE-MODIFYING FUNCTIONS
    // =============================================================

    /**
     * @param tokenId The dealer's token ID
     * @param text The message text
     */
    function postMessage(uint16 tokenId, string calldata text) external;

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @param index Absolute position in the circular buffer (0 = oldest available)
     */
    function getMessage(uint256 index) external view returns (Message memory);

    /**
     * @param offset Offset from the oldest available message
     * @param count Number of messages to return
     */
    function getMessages(uint256 offset, uint256 count) external view returns (Message[] memory);

    /**
     * @param count Number of latest messages to return (capped to available)
     */
    function getLatestMessages(uint256 count) external view returns (Message[] memory);

    /** @dev Returns min(_messageCount, BUFFER_SIZE) */
    function getMessageCount() external view returns (uint256);

    /** @dev Returns raw total messages ever posted */
    function totalMessages() external view returns (uint256);

    function factory() external view returns (address);
}
