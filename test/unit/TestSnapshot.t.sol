// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

contract StateContract {
    uint256 public counter;
    
    function increment() external {
        counter++;
    }
}

contract TestSnapshot is Test {
    StateContract state;
    
    function setUp() public {
        state = new StateContract();
    }
    
    function test_snapshot_revert() public {
        assertEq(state.counter(), 0);
        
        uint256 snapshotId = vm.snapshotState();
        
        state.increment();
        assertEq(state.counter(), 1);
        
        vm.revertToState(snapshotId);
        assertEq(state.counter(), 0, "Should be reverted to 0");
    }
    
    function test_snapshot_in_loop() public {
        uint256 successCount = 0;
        
        for (uint256 i = 0; i < 10; i++) {
            uint256 snapshotId = vm.snapshotState();
            
            state.increment();
            uint256 current = state.counter();
            
            // Check if increment happened
            if (current > 0) {
                successCount++;
            }
            
            vm.revertToState(snapshotId);
        }
        
        emit log_named_uint("successCount", successCount);
        emit log_named_uint("final counter", state.counter());
        
        assertEq(successCount, 10, "All iterations should see increment");
        assertEq(state.counter(), 0, "Counter should be 0 after all reverts");
    }
}
