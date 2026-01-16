// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/DealerRendererSVG.sol";
import "../src/DealerRendererHTML.sol";

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
 *                           CONTRACT DETAILS
 * ============================================================================
 *
 * DealerRendererSVG:
 *   - Generates dynamic SVG art for dealers based on token seed
 *   - Uses SSTORE2 for on-chain trait storage
 *   - Constructor sets msg.sender as owner
 *
 * DealerRendererHTML:
 *   - Wraps SVG in interactive HTML for animation_url
 *   - Uses FileStore at 0xFe1411d6864592549AdE050215482e4385dFa0FB
 *   - Constructor sets msg.sender as deployer and hardcodes FileStore address
 *
 * ============================================================================
 *                          USAGE INSTRUCTIONS
 * ============================================================================
 *
 * IMPORTANT: Do NOT use --zksync flag when running this script!
 *
 * Deploy to Abstract Testnet:
 *   forge script script/DeployRenderers.s.sol:DeployRenderers \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --sender <YOUR_ADDRESS> \
 *     --broadcast
 *
 * Deploy to Abstract Mainnet:
 *   forge script script/DeployRenderers.s.sol:DeployRenderers \
 *     --rpc-url https://api.mainnet.abs.xyz \
 *     --account dealersKeystore \
 *     --sender <YOUR_ADDRESS> \
 *     --broadcast
 *
 * After deployment, save the addresses and configure them in DealersExeNFT:
 *   - nft.setRendererSVG(rendererSVGAddress)
 *   - nft.setRendererHTML(rendererHTMLAddress)
 *
 * @author Dealers.Exe Team
 */
contract DeployRenderers is Script {
    function run() external {
        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Deploying Renderer Contracts (EVM Mode)");
        console.log("==============================================");
        console.log("");
        console.log("Deployer:", msg.sender);
        console.log("");

        console.log("Step 1: Deploying DealerRendererSVG...");
        DealerRendererSVG rendererSVG = new DealerRendererSVG();
        console.log("  DealerRendererSVG deployed at:", address(rendererSVG));
        console.log("  Owner:", rendererSVG.owner());
        console.log("");

        console.log("Step 2: Deploying DealerRendererHTML...");
        DealerRendererHTML rendererHTML = new DealerRendererHTML();
        console.log("  DealerRendererHTML deployed at:", address(rendererHTML));
        console.log("  Deployer:", rendererHTML.deployer());
        console.log("  FileStore:", address(rendererHTML.fileStore()));
        console.log("");

        console.log("==============================================");
        console.log("   Renderer Deployment Complete!");
        console.log("==============================================");
        console.log("");
        console.log("Deployed Addresses:");
        console.log("  DealerRendererSVG:", address(rendererSVG));
        console.log("  DealerRendererHTML:", address(rendererHTML));
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Configure renderers in DealersExeNFT:");
        console.log("     nft.setRendererSVG(<SVG_ADDRESS>)");
        console.log("     nft.setRendererHTML(<HTML_ADDRESS>)");
        console.log("  2. Upload traits to DealerRendererSVG");
        console.log("  3. Upload gzipped JS to FileStore");

        vm.stopBroadcast();
    }
}
