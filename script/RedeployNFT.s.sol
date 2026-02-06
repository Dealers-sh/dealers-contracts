// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

/**
 * @title RedeployNFT - Redeploy NFT and reconfigure all references
 *
 * Usage:
 *   source .env && forge script script/RedeployNFT.s.sol:RedeployNFT \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast \
 *     --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 *
 * Required env vars:
 *   ROYALTY_RECEIVER - Address for NFT royalty payments
 *   DEALERS_CORE     - Existing Core contract address
 *   RANDOMNESS       - Existing Randomness contract address
 *
 * Optional env vars:
 *   RENDERER_SVG     - Set SVG renderer after deployment
 *   RENDERER_HTML    - Set HTML renderer after deployment
 */

interface IDealersExeCore {
    function setNFTContract(address _nftContract) external;
    function authorizeContract(address contractAddress, bool authorized) external;
    function nftContract() external view returns (address);
    function authorizedContracts(address) external view returns (bool);
}

interface IDealersExeNFT {
    function setDealersExeCore(address _core) external;
    function setRandomness(address _randomness) external;
    function setContractRendererSVG(address _renderer) external;
    function setContractRendererHTML(address _renderer) external;
}

contract RedeployNFT is Script {
    function run() external {
        address royaltyReceiver = vm.envAddress("ROYALTY_RECEIVER");
        address core = vm.envAddress("DEALERS_CORE");
        address randomness = vm.envAddress("RANDOMNESS");
        address svgRenderer = vm.envOr("RENDERER_SVG", address(0));
        address htmlRenderer = vm.envOr("RENDERER_HTML", address(0));

        require(royaltyReceiver != address(0), "ROYALTY_RECEIVER not set");
        require(core != address(0), "DEALERS_CORE not set");
        require(randomness != address(0), "RANDOMNESS not set");

        console.log("=== RedeployNFT ===");
        console.log("ROYALTY_RECEIVER:", royaltyReceiver);
        console.log("DEALERS_CORE:", core);
        console.log("RANDOMNESS:", randomness);
        if (svgRenderer != address(0)) console.log("RENDERER_SVG:", svgRenderer);
        if (htmlRenderer != address(0)) console.log("RENDERER_HTML:", htmlRenderer);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy new NFT
        console.log("1. Deploying DealersExeNFT...");
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("DealersExeNFT.sol:DealersExeNFT"),
            abi.encode(royaltyReceiver)
        );
        address nft;
        assembly {
            nft := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(nft != address(0), "DealersExeNFT deployment failed");
        console.log("   Deployed at:", nft);

        // 2. Configure NFT references
        console.log("2. Configuring NFT references...");
        IDealersExeNFT nftContract = IDealersExeNFT(nft);
        nftContract.setDealersExeCore(core);
        console.log("   NFT -> Core: SET");
        nftContract.setRandomness(randomness);
        console.log("   NFT -> Randomness: SET");

        // 3. Set renderers if provided
        if (svgRenderer != address(0)) {
            nftContract.setContractRendererSVG(svgRenderer);
            console.log("   NFT -> SVG Renderer: SET");
        }
        if (htmlRenderer != address(0)) {
            nftContract.setContractRendererHTML(htmlRenderer);
            console.log("   NFT -> HTML Renderer: SET");
        }

        // 4. Update Core to point to new NFT
        console.log("3. Updating Core references...");
        IDealersExeCore coreContract = IDealersExeCore(core);
        coreContract.setNFTContract(nft);
        console.log("   Core -> NFT: SET");

        // 5. Authorize NFT in Core
        coreContract.authorizeContract(nft, true);
        console.log("   NFT authorized in Core: YES");

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("DealersExeNFT:", nft);
        console.log("");
        console.log("Update .env:");
        console.log("  DEALERS_NFT=%s", vm.toString(nft));
        if (svgRenderer == address(0) || htmlRenderer == address(0)) {
            console.log("");
            console.log("Don't forget to set renderers:");
            if (svgRenderer == address(0)) {
                console.log("  cast send %s \"setContractRendererSVG(address)\" <SVG_ADDR> --account dealersKeystore", vm.toString(nft));
            }
            if (htmlRenderer == address(0)) {
                console.log("  cast send %s \"setContractRendererHTML(address)\" <HTML_ADDR> --account dealersKeystore", vm.toString(nft));
            }
        }
    }
}
