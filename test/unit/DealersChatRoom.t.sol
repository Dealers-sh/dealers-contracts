// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DealersChatRoom} from "../../src/social/DealersChatRoom.sol";
import {IDealersChatRoom} from "../../src/social/IDealersChatRoom.sol";

contract DealersChatRoomTest is Test {
    DealersChatRoom public room;

    function setUp() public {
        room = new DealersChatRoom(address(this));
    }

    function test_postMessage_storesCorrectly() public {
        room.postMessage(42, "gm from the streets");

        IDealersChatRoom.Message memory msg_ = room.getMessage(0);
        assertEq(msg_.tokenId, 42);
        assertEq(msg_.timestamp, uint40(block.timestamp));
        assertEq(msg_.text, "gm from the streets");
    }

    function test_postMessage_revertsNotFactory() public {
        vm.prank(address(0xdead));
        vm.expectRevert(IDealersChatRoom.NotFactory.selector);
        room.postMessage(1, "should fail");
    }

    function test_postMessage_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IDealersChatRoom.MessagePosted(7, uint40(block.timestamp), "test event");
        room.postMessage(7, "test event");
    }

    function test_circularBuffer_wrapsAt64() public {
        for (uint16 i = 0; i < 65; ++i) {
            room.postMessage(i, string(abi.encodePacked("msg", vm.toString(i))));
        }

        assertEq(room.getMessageCount(), 64);
        assertEq(room.totalMessages(), 65);

        IDealersChatRoom.Message memory oldest = room.getMessage(0);
        assertEq(oldest.tokenId, 1);

        IDealersChatRoom.Message memory newest = room.getMessage(63);
        assertEq(newest.tokenId, 64);
    }

    function test_circularBuffer_fullDoubleWrap() public {
        for (uint16 i = 0; i < 128; ++i) {
            room.postMessage(i, "x");
        }

        assertEq(room.getMessageCount(), 64);
        assertEq(room.totalMessages(), 128);

        IDealersChatRoom.Message memory oldest = room.getMessage(0);
        assertEq(oldest.tokenId, 64);

        IDealersChatRoom.Message memory newest = room.getMessage(63);
        assertEq(newest.tokenId, 127);
    }

    function test_getLatestMessages_returnsChronological() public {
        for (uint16 i = 1; i <= 10; ++i) {
            room.postMessage(i, string(abi.encodePacked("msg", vm.toString(i))));
        }

        IDealersChatRoom.Message[] memory latest = room.getLatestMessages(5);
        assertEq(latest.length, 5);
        assertEq(latest[0].tokenId, 6);
        assertEq(latest[1].tokenId, 7);
        assertEq(latest[2].tokenId, 8);
        assertEq(latest[3].tokenId, 9);
        assertEq(latest[4].tokenId, 10);
    }

    function test_getLatestMessages_capsToAvailable() public {
        for (uint16 i = 1; i <= 3; ++i) {
            room.postMessage(i, "hi");
        }

        IDealersChatRoom.Message[] memory latest = room.getLatestMessages(10);
        assertEq(latest.length, 3);
        assertEq(latest[0].tokenId, 1);
        assertEq(latest[2].tokenId, 3);
    }

    function test_getLatestMessages_emptyRoom() public view {
        IDealersChatRoom.Message[] memory latest = room.getLatestMessages(5);
        assertEq(latest.length, 0);
    }

    function test_getMessages_offsetAndCount() public {
        for (uint16 i = 1; i <= 10; ++i) {
            room.postMessage(i, "x");
        }

        IDealersChatRoom.Message[] memory page = room.getMessages(2, 3);
        assertEq(page.length, 3);
        assertEq(page[0].tokenId, 3);
        assertEq(page[1].tokenId, 4);
        assertEq(page[2].tokenId, 5);
    }

    function test_getMessages_offsetBeyondAvailable() public {
        room.postMessage(1, "only one");

        IDealersChatRoom.Message[] memory result = room.getMessages(5, 3);
        assertEq(result.length, 0);
    }

    function test_getMessages_countExceedsRemaining() public {
        for (uint16 i = 1; i <= 5; ++i) {
            room.postMessage(i, "x");
        }

        IDealersChatRoom.Message[] memory result = room.getMessages(3, 100);
        assertEq(result.length, 2);
        assertEq(result[0].tokenId, 4);
        assertEq(result[1].tokenId, 5);
    }

    function test_getMessageCount_beforeAndAfterWrap() public {
        for (uint16 i = 0; i < 30; ++i) {
            room.postMessage(i, "x");
        }
        assertEq(room.getMessageCount(), 30);

        for (uint16 i = 30; i < 70; ++i) {
            room.postMessage(i, "x");
        }
        assertEq(room.getMessageCount(), 64);
    }

    function test_getMessage_revertsOutOfBounds() public {
        room.postMessage(1, "x");
        vm.expectRevert(IDealersChatRoom.IndexOutOfBounds.selector);
        room.getMessage(1);
    }

    function test_getLatestMessages_afterWrap() public {
        for (uint16 i = 0; i < 70; ++i) {
            room.postMessage(i, "x");
        }

        IDealersChatRoom.Message[] memory latest = room.getLatestMessages(3);
        assertEq(latest.length, 3);
        assertEq(latest[0].tokenId, 67);
        assertEq(latest[1].tokenId, 68);
        assertEq(latest[2].tokenId, 69);
    }

    function test_getMessages_paginationAfterWrap() public {
        for (uint16 i = 0; i < 70; ++i) {
            room.postMessage(i, "x");
        }

        IDealersChatRoom.Message[] memory page = room.getMessages(0, 3);
        assertEq(page[0].tokenId, 6);
        assertEq(page[1].tokenId, 7);
        assertEq(page[2].tokenId, 8);
    }
}
