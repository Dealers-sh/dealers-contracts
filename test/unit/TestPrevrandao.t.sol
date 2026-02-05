// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

contract TestPrevrandao is Test {
    function test_prevrandao_cheatcode() public {
        vm.prevrandao(bytes32(uint256(12345)));
        uint256 actual = block.prevrandao;
        emit log_named_uint("prevrandao", actual);
        assertEq(actual, 12345, "prevrandao should be settable");
    }
    
    function test_prevrandao_values() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prevrandao(bytes32(i));
            uint256 actual = block.prevrandao;
            emit log_named_uint("i", i);
            emit log_named_uint("prevrandao", actual);
        }
    }
}
