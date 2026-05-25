// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IERC721Minimal} from "../utils/IERC721Minimal.sol";
import {IDealersChatRoom} from "./IDealersChatRoom.sol";
import {IDealersChatGate} from "./IDealersChatGate.sol";
import {DealersChatRoom} from "./DealersChatRoom.sol";

/**
 * @title DealersChatFactory - Chat Room Deployer and Message Router
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Deploys DealersChatRoom instances via CREATE2 and routes messages
 *      after validating token ownership, blocked status, cooldowns,
 *      and optional per-room access gates.
 * @author Berny0x
 */
contract DealersChatFactory is Ownable {
    // =============================================================
    //                          STRUCTS
    // =============================================================

    struct RoomInfo {
        address room;
        IDealersChatGate gate;
        uint8 roomId;
    }

    // =============================================================
    //                          ENUMS
    // =============================================================

    enum RoomType {
        WORLD,
        AREA,
        GANG
    }

    // =============================================================
    //                          EVENTS
    // =============================================================

    event RoomCreated(RoomType indexed roomType, uint8 indexed id, address room, address gate);
    event MessageRouted(bytes32 indexed roomKey, uint16 indexed tokenId);
    event DealerBlocked(uint16 indexed tokenId, bool blocked);
    event CooldownUpdated(uint32 newCooldown);
    event ContractAuthorized(address indexed contractAddress, bool authorized);
    event NFTContractUpdated(address indexed oldAddress, address indexed newAddress);

    // =============================================================
    //                          ERRORS
    // =============================================================

    error RoomAlreadyExists();
    error RoomDoesNotExist();
    error NotTokenOwner();
    error DealerIsBlocked();
    error CooldownActive();
    error MessageTooLong();
    error MessageEmpty();
    error InvalidAddress();
    error NotAuthorized();
    error GateCheckFailed();

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    uint256 private constant MAX_MESSAGE_LENGTH = 256;

    // =============================================================
    //                         STORAGE
    // =============================================================

    IERC721Minimal public nftContract;

    mapping(bytes32 => RoomInfo) public rooms;
    mapping(uint16 => bool) public blocked;
    mapping(uint16 => uint40) public lastMessageTime;
    mapping(address => bool) public authorizedContracts;
    uint32 public cooldown = 30;

    // =============================================================
    //                       CONSTRUCTOR
    // =============================================================

    constructor(address _nftContract) {
        if (_nftContract == address(0)) revert InvalidAddress();
        _initializeOwner(msg.sender);
        nftContract = IERC721Minimal(_nftContract);
    }

    // =============================================================
    //                      OWNER FUNCTIONS
    // =============================================================

    /**
     * @param roomType The type of chat room (WORLD, AREA, GANG)
     * @param id The identifier within the room type (e.g., area ID)
     * @param gate Access gate contract (address(0) for unrestricted)
     */
    function createRoom(RoomType roomType, uint8 id, address gate) external returns (address room) {
        if (msg.sender != owner() && !authorizedContracts[msg.sender]) revert NotAuthorized();

        bytes32 key = roomKey(roomType, id);
        if (rooms[key].room != address(0)) revert RoomAlreadyExists();

        room = address(new DealersChatRoom{salt: key}(address(this)));
        rooms[key] = RoomInfo({
            room: room,
            gate: IDealersChatGate(gate),
            roomId: id
        });

        emit RoomCreated(roomType, id, room, gate);
    }

    /**
     * @param contractAddress The address to authorize/deauthorize
     * @param authorized Whether the address can create rooms
     */
    function authorizeContract(address contractAddress, bool authorized) external onlyOwner {
        if (contractAddress == address(0)) revert InvalidAddress();
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorized(contractAddress, authorized);
    }

    /**
     * @param tokenId The dealer token ID to block/unblock
     * @param _blocked Whether the dealer should be blocked
     */
    function setBlocked(uint16 tokenId, bool _blocked) external onlyOwner {
        blocked[tokenId] = _blocked;
        emit DealerBlocked(tokenId, _blocked);
    }

    /**
     * @param _cooldown New cooldown duration in seconds
     */
    function setCooldown(uint32 _cooldown) external onlyOwner {
        cooldown = _cooldown;
        emit CooldownUpdated(_cooldown);
    }

    /**
     * @param _nftContract Address of the DealersNFT contract
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert InvalidAddress();
        address old = address(nftContract);
        nftContract = IERC721Minimal(_nftContract);
        emit NFTContractUpdated(old, _nftContract);
    }

    // =============================================================
    //                      PUBLIC FUNCTIONS
    // =============================================================

    /**
     * @param _roomKey The room key (from roomKey())
     * @param tokenId The sender's dealer token ID
     * @param text The message text (1-256 bytes)
     */
    function postMessage(bytes32 _roomKey, uint16 tokenId, string calldata text) external {
        RoomInfo storage info = rooms[_roomKey];
        if (info.room == address(0)) revert RoomDoesNotExist();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (blocked[tokenId]) revert DealerIsBlocked();

        if (address(info.gate) != address(0)) {
            if (!info.gate.canPost(tokenId, info.roomId)) revert GateCheckFailed();
        }

        uint40 now_ = uint40(block.timestamp);
        unchecked {
            if (now_ - lastMessageTime[tokenId] < cooldown) revert CooldownActive();
        }

        uint256 len = bytes(text).length;
        if (len == 0) revert MessageEmpty();
        if (len > MAX_MESSAGE_LENGTH) revert MessageTooLong();

        lastMessageTime[tokenId] = now_;
        IDealersChatRoom(info.room).postMessage(tokenId, text);

        emit MessageRouted(_roomKey, tokenId);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @param roomType The room type
     * @param id The room identifier
     */
    function getRoomAddress(RoomType roomType, uint8 id) external view returns (address) {
        return rooms[roomKey(roomType, id)].room;
    }

    /**
     * @param _roomKey The room key
     */
    function getRoomInfo(bytes32 _roomKey) external view returns (address room, address gate, uint8 roomId) {
        RoomInfo storage info = rooms[_roomKey];
        return (info.room, address(info.gate), info.roomId);
    }

    /**
     * @param roomType The room type
     * @param id The room identifier
     */
    function roomKey(RoomType roomType, uint8 id) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(uint8(roomType), id));
    }
}
