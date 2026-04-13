// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

contract TestRandomnessDebug is Test {
    function test_keccak_randomness() public {
        uint256 attackerId = 1;
        uint256 defenderId = 2;
        address sender = address(0x123);
        uint256 totalBattles = 0;
        
        // Test different prevrandao values
        for (uint256 i = 0; i < 10; i++) {
            vm.prevrandao(bytes32(i));
            vm.warp(3601); // 1 hour + 1
            
            uint256 randomness = uint256(keccak256(abi.encodePacked(
                block.prevrandao,
                block.timestamp,
                attackerId,
                defenderId,
                sender,
                totalBattles
            )));
            
            uint8 jailRoll = uint8(randomness % 100);
            uint256 winRoll = (randomness >> 8) % 100;
            
            emit log_named_uint("i", i);
            emit log_named_uint("jailRoll", jailRoll);
            emit log_named_uint("winRoll", winRoll);
        }
    }
    
    function test_jail_outcomes() public {
        uint256 attackerId = 1;
        uint256 defenderId = 2;
        address sender = address(0x123);
        uint256 totalBattles = 0;
        uint8 jailChance = 5; // Max heat level
        
        uint256 arrestCount = 0;
        for (uint256 i = 0; i < 500; i++) {
            vm.prevrandao(bytes32(i));
            vm.warp(3601);
            
            uint256 randomness = uint256(keccak256(abi.encodePacked(
                block.prevrandao,
                block.timestamp,
                attackerId,
                defenderId,
                sender,
                totalBattles
            )));
            
            uint8 jailRoll = uint8(randomness % 100);
            if (jailRoll < jailChance) {
                arrestCount++;
                emit log_named_uint("Arrest at i", i);
            }
        }
        emit log_named_uint("Total arrests found", arrestCount);
        assertGt(arrestCount, 0, "Should find at least one arrest outcome");
    }
}
