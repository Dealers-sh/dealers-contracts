// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

interface INFTReserve {
    function reserve(uint256 nftAmount) external;
}

interface ICoreReputation {
    function updateReputation(uint256 tokenId, int256 change) external;
}

contract SetupTestnetDealers is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(core, "DEALERS_CORE");

        console.log("NFT:", nft);
        console.log("Core:", core);

        vm.startBroadcast();

        INFTReserve(nft).reserve(50);
        console.log("Minted 50 dealers (token IDs 2-51)");

        ICoreReputation coreContract = ICoreReputation(core);

        for (uint256 id = 2; id <= 31; id++) {
            coreContract.updateReputation(id, 150);
        }
        console.log("Set reputation 150 for token IDs 2-31 (30 dealers)");

        for (uint256 id = 42; id <= 46; id++) {
            coreContract.updateReputation(id, 200);
        }
        console.log("Set reputation 200 for token IDs 42-46 (5 dealers)");

        for (uint256 id = 47; id <= 51; id++) {
            coreContract.updateReputation(id, 250);
        }
        console.log("Set reputation 250 for token IDs 47-51 (5 dealers)");

        vm.stopBroadcast();

        console.log("Token IDs 32-41 left at default reputation (10 dealers)");
        console.log("Setup complete: 50 dealers configured");
    }
}
