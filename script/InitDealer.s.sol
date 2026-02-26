// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

interface ICore {
    function initializeDealer(uint256 tokenId) external;
}

contract InitDealer is Script {
    function run() external {
        address core = vm.envAddress("DEALERS_CORE");

        vm.startBroadcast();
        ICore(core).initializeDealer(1);
        vm.stopBroadcast();
    }

}
