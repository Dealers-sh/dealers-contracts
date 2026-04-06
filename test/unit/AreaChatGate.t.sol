// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AreaChatGate} from "../../src/social/AreaChatGate.sol";
import {IDealersExeCore} from "../../src/core/IDealersExeCore.sol";

contract MockCore {
    mapping(uint256 => IDealersExeCore.GameState) private _states;

    function setGameState(uint256 tokenId, uint8 currentArea, bool isJailed) external {
        IDealersExeCore.GameState memory gs;
        gs.currentArea = currentArea;
        gs.isJailed = isJailed;
        gs.isInitialized = true;
        _states[tokenId] = gs;
    }

    function getGameState(uint256 tokenId) external view returns (IDealersExeCore.GameState memory) {
        return _states[tokenId];
    }
}

contract AreaChatGateTest is Test {
    AreaChatGate public gate;
    MockCore public mockCore;

    uint16 public constant TOKEN_A = 1;
    uint16 public constant TOKEN_B = 2;

    function setUp() public {
        mockCore = new MockCore();
        gate = new AreaChatGate(address(mockCore));
    }

    function test_canPost_correctAreaReturnsTrue() public {
        mockCore.setGameState(TOKEN_A, 3, false);
        assertTrue(gate.canPost(TOKEN_A, 3));
    }

    function test_canPost_wrongAreaReturnsFalse() public {
        mockCore.setGameState(TOKEN_A, 3, false);
        assertFalse(gate.canPost(TOKEN_A, 5));
    }

    function test_canPost_jailedCanChatInJailRoom() public {
        mockCore.setGameState(TOKEN_A, 255, true);
        assertTrue(gate.canPost(TOKEN_A, 255));
    }

    function test_canPost_jailedCannotChatInOtherArea() public {
        mockCore.setGameState(TOKEN_A, 255, true);
        assertFalse(gate.canPost(TOKEN_A, 3));
    }

    function test_canPost_multipleTokens() public {
        mockCore.setGameState(TOKEN_A, 3, false);
        mockCore.setGameState(TOKEN_B, 5, false);

        assertTrue(gate.canPost(TOKEN_A, 3));
        assertFalse(gate.canPost(TOKEN_A, 5));
        assertTrue(gate.canPost(TOKEN_B, 5));
        assertFalse(gate.canPost(TOKEN_B, 3));
    }

    function test_constructor_revertsZeroAddress() public {
        vm.expectRevert(AreaChatGate.InvalidAddress.selector);
        new AreaChatGate(address(0));
    }

    function test_constructor_storesCore() public view {
        assertEq(address(gate.core()), address(mockCore));
    }
}
