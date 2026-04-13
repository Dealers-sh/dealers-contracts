// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title DeployNFT
 * @dev Constructor deps: ROYALTY_RECEIVER (EOA)
 *      Post-deploy:
 *        - NFT.setDealersExeCore(core)
 *        - Core.authorizeContract(nft, true)
 *        - Core.setNFTContract(nft)
 *        - Set renderers via setContractRendererSVG/HTML (separate EVM deploy)
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployNFT.s.sol:DeployNFT \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG"
 */
contract DeployNFT is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(royaltyReceiver, "ROYALTY_RECEIVER");

        vm.startBroadcast();
        nft = _zkCreate(abi.encodePacked(
            vm.getCode("DealersExeNFT.sol:DealersExeNFT"),
            abi.encode(royaltyReceiver)
        ));
        vm.stopBroadcast();

        _saveAddresses();

        console.log("DealersExeNFT deployed:", nft);
        console.log("  Royalty Receiver:", royaltyReceiver);
        console.log("");
        console.log("Next:");
        console.log("  1. Run SetupWiring.s.sol");
        console.log("  2. Deploy renderers (EVM mode, no --zksync)");
        console.log("  3. Set renderers on NFT");
    }
}
