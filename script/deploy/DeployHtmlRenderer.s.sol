// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";
import "../../src/nft/DealerRendererHTML.sol";

interface INFTSetRenderer {
    function setContractRendererHTML(address newAddress) external;
    function contractRendererHTML() external view returns (address);
}

/**
 * @title DeployHtmlRenderer - Deploy and configure HTML renderer
 * @notice Deploys DealerRendererHTML as native zkSync bytecode, configures it,
 *         and points the NFT contract to it.
 *
 * Usage:
 *   forge script script/deploy/DeployHtmlRenderer.s.sol:DeployHtmlRenderer \
 *       --zksync --skip "RendererSVG" --skip "UploadTraits" \
 *       --rpc-url https://api.testnet.abs.xyz \
 *       --account dealersKeystore \
 *       --broadcast
 *
 * @author Berny0x
 */
contract DeployHtmlRenderer is DeployBase {
    address constant FILE_STORE = 0xFe1411d6864592549AdE050215482e4385dFa0FB;

    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(rendererSvg, "RENDERER_SVG");

        string memory targetRpcUrl = _getRpcUrl();
        string memory gzip = bytes(gzipFilename).length > 0 ? gzipFilename : "placeholder.js.gz";

        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Deploying HTML Renderer (zkSync Native)");
        console.log("==============================================");

        DealerRendererHTML html;
        if (rendererHtml != address(0)) {
            console.log("Skipping deploy (already deployed):", rendererHtml);
            html = DealerRendererHTML(rendererHtml);
        } else {
            html = new DealerRendererHTML(FILE_STORE);
            rendererHtml = address(html);
            console.log("DealerRendererHTML deployed at:", rendererHtml);
        }

        console.log("");
        console.log("Configuring...");

        html.setRpcUrl(targetRpcUrl);
        console.log("  RPC URL:", targetRpcUrl);

        html.setSvgRendererAddress(rendererSvg);
        console.log("  SVG renderer:", rendererSvg);

        html.setDealerGzipFilename(gzip);
        console.log("  Gzip filename:", gzip);

        INFTSetRenderer nftContract = INFTSetRenderer(nft);
        if (nftContract.contractRendererHTML() != rendererHtml) {
            nftContract.setContractRendererHTML(rendererHtml);
            console.log("  Set HTML renderer on NFT:", rendererHtml);
        } else {
            console.log("  NFT already points to this renderer");
        }

        vm.stopBroadcast();

        _saveAddresses();

        console.log("");
        console.log("Done!");
    }

    function _getRpcUrl() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 2741) return "https://api.mainnet.abs.xyz";
        if (chainId == 11124) return "https://api.testnet.abs.xyz";
        revert("Unsupported chain");
    }
}
