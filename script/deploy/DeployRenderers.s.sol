// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/nft/DealerRendererSVG.sol";
import "../../src/nft/DealerRendererHTML.sol";

interface IDealersExeNFT {
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
 *                          ENVIRONMENT VARIABLES
 * ============================================================================
 *
 * Required:
 *   DEALERS_NFT     - NFT contract address to set renderers on
 *
 * Optional (to skip deployment of already-deployed renderers):
 *   RENDERER_SVG    - Skip SVG renderer deployment, use this address
 *   RENDERER_HTML   - Skip HTML renderer deployment, use this address
 *
 * ============================================================================
 *                          USAGE INSTRUCTIONS
 * ============================================================================
 *
 * IMPORTANT: Do NOT use --zksync flag when running this script!
 *
 *   source .env && forge script script/DeployRenderers.s.sol:DeployRenderers \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * @author Dealers.Exe Team
 */
contract DeployRenderers is Script {
    address constant FILE_STORE = 0xFe1411d6864592549AdE050215482e4385dFa0FB;

    function run() external {
        address nft = vm.envAddress("DEALERS_NFT");
        require(nft != address(0), "DEALERS_NFT not set");

        address rendererSVG = vm.envOr("RENDERER_SVG", address(0));
        address rendererHTML = vm.envOr("RENDERER_HTML", address(0));

        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Deploying Renderer Contracts (EVM Mode)");
        console.log("==============================================");
        console.log("");

        if (rendererSVG != address(0)) {
            console.log("Skipping DealerRendererSVG (already deployed):", rendererSVG);
        } else {
            DealerRendererSVG svg = new DealerRendererSVG();
            rendererSVG = address(svg);
            console.log("DealerRendererSVG deployed at:", rendererSVG);
        }

        if (rendererHTML != address(0)) {
            console.log("Skipping DealerRendererHTML (already deployed):", rendererHTML);
        } else {
            DealerRendererHTML html = new DealerRendererHTML(FILE_STORE);
            rendererHTML = address(html);
            console.log("DealerRendererHTML deployed at:", rendererHTML);
        }

        vm.stopBroadcast();

        _saveRendererAddresses(rendererSVG, rendererHTML);

        console.log("");
        console.log("==============================================");
        console.log("   Renderer Deployment Complete!");
        console.log("==============================================");
        console.log("");
        console.log("  RENDERER_SVG=", rendererSVG);
        console.log("  RENDERER_HTML=", rendererHTML);
        console.log("");
        console.log("Set renderers on NFT (requires --zksync since NFT is zkSync bytecode):");
        console.log("  cast send", nft, '"setContractRendererSVG(address)"', rendererSVG);
        console.log("  cast send", nft, '"setContractRendererHTML(address)"', rendererHTML);
    }

    function _saveRendererAddresses(address svg, address html) internal {
        string memory path = _getDeploymentPath();

        try vm.readFile(path) returns (string memory existing) {
            vm.writeJson(vm.toString(svg), path, ".rendererSvg");
            vm.writeJson(vm.toString(html), path, ".rendererHtml");
        } catch {
            string memory obj = "deploy";
            vm.serializeAddress(obj, "rendererSvg", svg);
            string memory json = vm.serializeAddress(obj, "rendererHtml", html);
            vm.writeJson(json, path);
        }

        console.log("Addresses saved to:", path);
    }

    function _getDeploymentPath() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 11124) return "script/data/deployments/testnet.json";
        if (chainId == 2741) return "script/data/deployments/mainnet.json";
        return "script/data/deployments/local.json";
    }
}
