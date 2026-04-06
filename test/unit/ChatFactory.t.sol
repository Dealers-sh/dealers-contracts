// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ChatFactory} from "../../src/social/ChatFactory.sol";
import {IChatRoom} from "../../src/social/IChatRoom.sol";
import {IChatGate} from "../../src/social/IChatGate.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

contract MockERC721 {
    mapping(uint256 => address) public owners;

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }

    function setOwner(uint256 tokenId, address owner_) external {
        owners[tokenId] = owner_;
    }
}

contract MockGate is IChatGate {
    mapping(uint16 => mapping(uint8 => bool)) public allowed;

    function setAllowed(uint16 tokenId, uint8 roomId, bool _allowed) external {
        allowed[tokenId][roomId] = _allowed;
    }

    function canPost(uint16 tokenId, uint8 roomId) external view override returns (bool) {
        return allowed[tokenId][roomId];
    }
}

contract RejectAllGate is IChatGate {
    function canPost(uint16, uint8) external pure override returns (bool) {
        return false;
    }
}

contract ChatFactoryTest is Test {
    ChatFactory public factory;
    MockERC721 public mockNft;
    MockGate public mockGate;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public gangContract = makeAddr("gangContract");
    uint16 public constant TOKEN_ALICE = 1;
    uint16 public constant TOKEN_BOB = 2;

    bytes32 public worldKey;

    function setUp() public {
        vm.warp(1000);
        mockNft = new MockERC721();
        mockGate = new MockGate();
        factory = new ChatFactory(address(mockNft));

        mockNft.setOwner(TOKEN_ALICE, alice);
        mockNft.setOwner(TOKEN_BOB, bob);

        factory.createRoom(ChatFactory.RoomType.WORLD, 0, address(0));
        worldKey = factory.roomKey(ChatFactory.RoomType.WORLD, 0);
    }

    // =============================================================
    //                     ROOM CREATION
    // =============================================================

    function test_createRoom_deploysAndRegisters() public view {
        address room = factory.getRoomAddress(ChatFactory.RoomType.WORLD, 0);
        assertTrue(room != address(0));
        assertEq(IChatRoom(room).factory(), address(factory));
    }

    function test_createRoom_storesGateAndRoomId() public {
        factory.createRoom(ChatFactory.RoomType.AREA, 3, address(mockGate));
        bytes32 key = factory.roomKey(ChatFactory.RoomType.AREA, 3);

        (address room, address gate, uint8 roomId) = factory.getRoomInfo(key);
        assertTrue(room != address(0));
        assertEq(gate, address(mockGate));
        assertEq(roomId, 3);
    }

    function test_createRoom_noGateStoresZero() public {
        (,address gate,) = factory.getRoomInfo(worldKey);
        assertEq(gate, address(0));
    }

    function test_createRoom_revertsDuplicate() public {
        vm.expectRevert(ChatFactory.RoomAlreadyExists.selector);
        factory.createRoom(ChatFactory.RoomType.WORLD, 0, address(0));
    }

    function test_createRoom_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(ChatFactory.NotAuthorized.selector);
        factory.createRoom(ChatFactory.RoomType.AREA, 1, address(0));
    }

    function test_createRoom_multipleTypes() public {
        factory.createRoom(ChatFactory.RoomType.AREA, 1, address(0));
        factory.createRoom(ChatFactory.RoomType.AREA, 2, address(0));

        address world = factory.getRoomAddress(ChatFactory.RoomType.WORLD, 0);
        address area1 = factory.getRoomAddress(ChatFactory.RoomType.AREA, 1);
        address area2 = factory.getRoomAddress(ChatFactory.RoomType.AREA, 2);

        assertTrue(world != area1);
        assertTrue(world != area2);
        assertTrue(area1 != area2);
    }

    // =============================================================
    //                   AUTHORIZED CREATORS
    // =============================================================

    function test_authorizedCreator_canCreateRoom() public {
        factory.authorizeContract(gangContract, true);

        vm.prank(gangContract);
        address room = factory.createRoom(ChatFactory.RoomType.GANG, 1, address(mockGate));
        assertTrue(room != address(0));
    }

    function test_authorizedCreator_revokedCannotCreate() public {
        factory.authorizeContract(gangContract, true);
        factory.authorizeContract(gangContract, false);

        vm.prank(gangContract);
        vm.expectRevert(ChatFactory.NotAuthorized.selector);
        factory.createRoom(ChatFactory.RoomType.GANG, 1, address(0));
    }

    function test_authorizeContract_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        factory.authorizeContract(gangContract, true);
    }

    function test_authorizeContract_revertsZeroAddress() public {
        vm.expectRevert(ChatFactory.InvalidAddress.selector);
        factory.authorizeContract(address(0), true);
    }

    // =============================================================
    //                     POST MESSAGE
    // =============================================================

    function test_postMessage_success() public {
        vm.prank(alice);
        factory.postMessage(worldKey, TOKEN_ALICE, "gm dealers");

        address room = factory.getRoomAddress(ChatFactory.RoomType.WORLD, 0);
        IChatRoom.Message[] memory msgs = IChatRoom(room).getLatestMessages(1);
        assertEq(msgs[0].tokenId, TOKEN_ALICE);
        assertEq(msgs[0].text, "gm dealers");
    }

    function test_postMessage_revertsRoomDoesNotExist() public {
        bytes32 fakeKey = keccak256("nonexistent");
        vm.prank(alice);
        vm.expectRevert(ChatFactory.RoomDoesNotExist.selector);
        factory.postMessage(fakeKey, TOKEN_ALICE, "hello");
    }

    function test_postMessage_revertsNotTokenOwner() public {
        vm.prank(bob);
        vm.expectRevert(ChatFactory.NotTokenOwner.selector);
        factory.postMessage(worldKey, TOKEN_ALICE, "impersonating");
    }

    function test_postMessage_revertsBlocked() public {
        factory.setBlocked(TOKEN_ALICE, true);

        vm.prank(alice);
        vm.expectRevert(ChatFactory.DealerIsBlocked.selector);
        factory.postMessage(worldKey, TOKEN_ALICE, "blocked msg");
    }

    function test_postMessage_revertsCooldown() public {
        vm.prank(alice);
        factory.postMessage(worldKey, TOKEN_ALICE, "first");

        vm.prank(alice);
        vm.expectRevert(ChatFactory.CooldownActive.selector);
        factory.postMessage(worldKey, TOKEN_ALICE, "too fast");
    }

    function test_postMessage_succeedsAfterCooldown() public {
        vm.prank(alice);
        factory.postMessage(worldKey, TOKEN_ALICE, "first");

        vm.warp(block.timestamp + 31);

        vm.prank(alice);
        factory.postMessage(worldKey, TOKEN_ALICE, "second");

        address room = factory.getRoomAddress(ChatFactory.RoomType.WORLD, 0);
        assertEq(IChatRoom(room).getMessageCount(), 2);
    }

    function test_postMessage_revertsMessageTooLong() public {
        bytes memory longMsg = new bytes(257);
        for (uint256 i = 0; i < 257; ++i) {
            longMsg[i] = "a";
        }

        vm.prank(alice);
        vm.expectRevert(ChatFactory.MessageTooLong.selector);
        factory.postMessage(worldKey, TOKEN_ALICE, string(longMsg));
    }

    function test_postMessage_revertsMessageEmpty() public {
        vm.prank(alice);
        vm.expectRevert(ChatFactory.MessageEmpty.selector);
        factory.postMessage(worldKey, TOKEN_ALICE, "");
    }

    function test_postMessage_256charsSucceeds() public {
        bytes memory maxMsg = new bytes(256);
        for (uint256 i = 0; i < 256; ++i) {
            maxMsg[i] = "z";
        }

        vm.prank(alice);
        factory.postMessage(worldKey, TOKEN_ALICE, string(maxMsg));

        address room = factory.getRoomAddress(ChatFactory.RoomType.WORLD, 0);
        IChatRoom.Message[] memory msgs = IChatRoom(room).getLatestMessages(1);
        assertEq(bytes(msgs[0].text).length, 256);
    }

    function test_postMessage_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit ChatFactory.MessageRouted(worldKey, TOKEN_ALICE);
        factory.postMessage(worldKey, TOKEN_ALICE, "event test");
    }

    // =============================================================
    //                     GATE CHECKS
    // =============================================================

    function test_postMessage_gatedRoom_allowedPasses() public {
        factory.createRoom(ChatFactory.RoomType.AREA, 5, address(mockGate));
        bytes32 areaKey = factory.roomKey(ChatFactory.RoomType.AREA, 5);

        mockGate.setAllowed(TOKEN_ALICE, 5, true);

        vm.prank(alice);
        factory.postMessage(areaKey, TOKEN_ALICE, "area 5 msg");

        address room = factory.getRoomAddress(ChatFactory.RoomType.AREA, 5);
        assertEq(IChatRoom(room).getMessageCount(), 1);
    }

    function test_postMessage_gatedRoom_deniedReverts() public {
        factory.createRoom(ChatFactory.RoomType.AREA, 5, address(mockGate));
        bytes32 areaKey = factory.roomKey(ChatFactory.RoomType.AREA, 5);

        vm.prank(alice);
        vm.expectRevert(ChatFactory.GateCheckFailed.selector);
        factory.postMessage(areaKey, TOKEN_ALICE, "not allowed");
    }

    function test_postMessage_rejectAllGate() public {
        RejectAllGate rejectGate = new RejectAllGate();
        factory.createRoom(ChatFactory.RoomType.GANG, 1, address(rejectGate));
        bytes32 gangKey = factory.roomKey(ChatFactory.RoomType.GANG, 1);

        vm.prank(alice);
        vm.expectRevert(ChatFactory.GateCheckFailed.selector);
        factory.postMessage(gangKey, TOKEN_ALICE, "rejected");
    }

    function test_postMessage_ungatedRoom_noGateCheck() public {
        vm.prank(alice);
        factory.postMessage(worldKey, TOKEN_ALICE, "no gate needed");

        address room = factory.getRoomAddress(ChatFactory.RoomType.WORLD, 0);
        assertEq(IChatRoom(room).getMessageCount(), 1);
    }

    // =============================================================
    //                     ADMIN FUNCTIONS
    // =============================================================

    function test_setBlocked_toggles() public {
        factory.setBlocked(TOKEN_ALICE, true);
        assertTrue(factory.blocked(TOKEN_ALICE));

        factory.setBlocked(TOKEN_ALICE, false);
        assertFalse(factory.blocked(TOKEN_ALICE));
    }

    function test_setBlocked_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        factory.setBlocked(TOKEN_ALICE, true);
    }

    function test_setCooldown_updates() public {
        factory.setCooldown(60);
        assertEq(factory.cooldown(), 60);
    }

    function test_setCooldown_revertsNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        factory.setCooldown(60);
    }

    // =============================================================
    //                     VIEW FUNCTIONS
    // =============================================================

    function test_roomKey_deterministic() public view {
        bytes32 expected = keccak256(abi.encodePacked(uint8(ChatFactory.RoomType.WORLD), uint8(0)));
        assertEq(factory.roomKey(ChatFactory.RoomType.WORLD, 0), expected);
    }

    function test_getRoomAddress_returnsCorrectly() public view {
        address room = factory.getRoomAddress(ChatFactory.RoomType.WORLD, 0);
        (address infoRoom,,) = factory.getRoomInfo(worldKey);
        assertEq(room, infoRoom);
    }

    function test_getRoomAddress_returnsZeroForNonexistent() public view {
        address room = factory.getRoomAddress(ChatFactory.RoomType.GANG, 99);
        assertEq(room, address(0));
    }

    function test_getRoomInfo_returnsAllFields() public {
        factory.createRoom(ChatFactory.RoomType.AREA, 7, address(mockGate));
        bytes32 key = factory.roomKey(ChatFactory.RoomType.AREA, 7);

        (address room, address gate, uint8 roomId) = factory.getRoomInfo(key);
        assertTrue(room != address(0));
        assertEq(gate, address(mockGate));
        assertEq(roomId, 7);
    }

    // =============================================================
    //                     CONSTRUCTOR
    // =============================================================

    function test_constructor_revertsZeroAddress() public {
        vm.expectRevert(ChatFactory.InvalidAddress.selector);
        new ChatFactory(address(0));
    }

    // =============================================================
    //                     COOLDOWN ACROSS ROOMS
    // =============================================================

    function test_cooldown_sharedAcrossRooms() public {
        factory.createRoom(ChatFactory.RoomType.AREA, 1, address(0));
        bytes32 areaKey = factory.roomKey(ChatFactory.RoomType.AREA, 1);

        vm.prank(alice);
        factory.postMessage(worldKey, TOKEN_ALICE, "world msg");

        vm.prank(alice);
        vm.expectRevert(ChatFactory.CooldownActive.selector);
        factory.postMessage(areaKey, TOKEN_ALICE, "area msg too fast");
    }
}
