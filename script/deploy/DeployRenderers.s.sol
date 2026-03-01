// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";
import "../../src/nft/DealerRendererSVG.sol";
import "../../src/nft/DealerRendererHTML.sol";

interface INFTRenderer {
    function setContractRendererSVG(address newAddress) external;
    function setContractRendererHTML(address newAddress) external;
    function contractRendererSVG() external view returns (address);
    function contractRendererHTML() external view returns (address);
}

/**
 * @title DeployRenderers - EVM Bytecode Deployment Script for Renderer Contracts
 * @notice Deploys DealerRendererSVG and DealerRendererHTML via EVM interpreter
 * @dev These contracts use EXTCODECOPY (SSTORE2/FileStore) and MUST be deployed
 *      as standard EVM bytecode, NOT as native zkSync bytecode.
 *
 * ============================================================================
 *                           DEPLOYMENT CONTEXT
 * ============================================================================
 *
 * Abstract Chain supports both native zkSync bytecode and EVM bytecode via
 * its EVM interpreter. The renderer contracts use SSTORE2 which relies on
 * EXTCODECOPY - an opcode not supported natively on zkSync VM.
 *
 * By deploying WITHOUT the --zksync flag, these contracts run as EVM bytecode
 * through Abstract's interpreter layer. This has higher gas costs (150-400%)
 * but provides full EVM compatibility.
 *
 * ============================================================================
 *                          ADDRESS LOADING
 * ============================================================================
 *
 * Addresses are loaded from testnet.json (or mainnet.json) via DeployBase.
 * Falls back to environment variables if the JSON file doesn't exist.
 *
 * If rendererSvg/rendererHtml are already set (from JSON or env), deployment
 * of that renderer is skipped. To force redeployment, remove the keys from
 * the JSON file.
 *
 * ============================================================================
 *                          USAGE INSTRUCTIONS
 * ============================================================================
 *
 * IMPORTANT: Do NOT use --zksync flag when running this script!
 *
 *   source .env && forge script script/deploy/DeployRenderers.s.sol:DeployRenderers \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * @author Dealers.Exe Team
 */
contract DeployRenderers is DeployBase {
    address constant FILE_STORE = 0xFe1411d6864592549AdE050215482e4385dFa0FB;

    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");

        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Deploying Renderer Contracts (EVM Mode)");
        console.log("==============================================");
        console.log("");

        if (rendererSvg != address(0)) {
            console.log("Skipping DealerRendererSVG (already deployed):", rendererSvg);
        } else {
            DealerRendererSVG svg = new DealerRendererSVG();
            rendererSvg = address(svg);
            console.log("DealerRendererSVG deployed at:", rendererSvg);
        }

        if (rendererHtml != address(0)) {
            console.log("Skipping DealerRendererHTML (already deployed):", rendererHtml);
        } else {
            DealerRendererHTML html = new DealerRendererHTML(FILE_STORE);
            rendererHtml = address(html);
            console.log("DealerRendererHTML deployed at:", rendererHtml);
        }

        vm.stopBroadcast();

        _saveAddresses();

        console.log("");
        console.log("==============================================");
        console.log("   Renderer Deployment Complete!");
        console.log("==============================================");
        console.log("");
        console.log("  RENDERER_SVG=", rendererSvg);
        console.log("  RENDERER_HTML=", rendererHtml);
        console.log("");
        console.log("Set renderers on NFT (requires --zksync since NFT is zkSync bytecode):");
        console.log("  cast send", nft, '"setContractRendererSVG(address)"', rendererSvg);
        console.log("  cast send", nft, '"setContractRendererHTML(address)"', rendererHtml);
    }
}
