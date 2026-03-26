// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";
import "../../src/nft/DealerRendererSVG.sol";

/**
 * @title DeployRendererSVG - EVM Bytecode Deployment for SVG Renderer
 * @notice Deploys DealerRendererSVG via EVM interpreter (uses EXTCODECOPY/SSTORE2)
 * @dev MUST be run WITHOUT --zksync flag.
 *
 * Usage:
 *   forge script script/deploy/DeployRendererSVG.s.sol:DeployRendererSVG \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * @author Dealers.Exe Team
 */
contract DeployRendererSVG is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");

        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Deploying SVG Renderer (EVM Mode)");
        console.log("==============================================");

        if (rendererSvg != address(0)) {
            console.log("Skipping DealerRendererSVG (already deployed):", rendererSvg);
        } else {
            DealerRendererSVG svg = new DealerRendererSVG();
            rendererSvg = address(svg);
            console.log("DealerRendererSVG deployed at:", rendererSvg);
        }

        vm.stopBroadcast();

        _saveAddresses();

        console.log("");
        console.log("Set renderer on NFT (requires --zksync):");
        console.log("  cast send", nft, '"setContractRendererSVG(address)"', rendererSvg);
    }
}
