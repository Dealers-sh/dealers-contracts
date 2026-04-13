// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./base/DeployBase.s.sol";

interface IInitCore {
    function initializeDealer(uint256 tokenId) external;
}

contract InitDealer is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");

        vm.startBroadcast();
        IInitCore(core).initializeDealer(1);
        vm.stopBroadcast();
    }
}
