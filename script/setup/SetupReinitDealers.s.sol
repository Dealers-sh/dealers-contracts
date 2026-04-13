// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupReinitDealers - Re-initialize existing dealers on a fresh Core
 * @dev Used after redeploying Core while keeping the same NFT.
 *      Calls initializeDealer for each token, then restores rep from SetupTestnetDealers.
 *
 * Usage:
 *   source .env && forge script script/setup/SetupReinitDealers.s.sol:SetupReinitDealers \
      --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
      --skip "RendererSVG"
 */

interface INFT {
    function currentTokenId() external view returns (uint256);
}

contract SetupReinitDealers is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");

        IDealersExeCore coreContract = IDealersExeCore(core);

        uint256 totalSupply = INFT(nft).currentTokenId();
        console.log("NFT currentTokenId:", totalSupply);
        console.log("Core:", core);

        vm.startBroadcast();

        for (uint256 id = 1; id < totalSupply; id++) {
            coreContract.initializeDealer(id);
        }
        console.log("Initialized dealers 1-%s", vm.toString(totalSupply));

        for (uint256 id = 2; id <= 31; id++) {
            coreContract.updateReputation(id, 150);
        }
        console.log("Set reputation 150 for token IDs 2-31");

        for (uint256 id = 42; id <= 46; id++) {
            coreContract.updateReputation(id, 200);
        }
        console.log("Set reputation 200 for token IDs 42-46");

        for (uint256 id = 47; id <= 51; id++) {
            coreContract.updateReputation(id, 250);
        }
        console.log("Set reputation 250 for token IDs 47-51");

        vm.stopBroadcast();

        console.log("Re-initialization complete");
    }
}
