// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

interface INFT {
    function tokenJson(uint256 tokenId) external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function contractRendererSVG() external view returns (address);
    function contractRendererHTML() external view returns (address);
    function dealersCore() external view returns (address);
}

interface ISVGRenderer {
    function getSVG(uint256 tokenId) external view returns (string memory);
    function getTraitsMetadataForToken(uint256 tokenId) external view returns (string memory);
}

interface IHTMLRenderer {
    function getHTML(uint256 tokenId, string memory svg) external view returns (string memory);
}

contract DebugTokenUri is Script {
    address constant NFT = 0xaDC4d4277390C54DB3847662895535aa013BC15a;

    function run() external {
        INFT nft = INFT(NFT);

        address svgAddr = nft.contractRendererSVG();
        address htmlAddr = nft.contractRendererHTML();
        address coreAddr = nft.dealersCore();
        console.log("SVG renderer:", svgAddr);
        console.log("HTML renderer:", htmlAddr);
        console.log("Core:", coreAddr);

        ISVGRenderer svgRenderer = ISVGRenderer(svgAddr);
        IHTMLRenderer htmlRenderer = IHTMLRenderer(htmlAddr);

        console.log("\n--- Step 1: getSVG ---");
        string memory svg = svgRenderer.getSVG(1);
        console.log("SVG length:", bytes(svg).length);

        console.log("\n--- Step 2: getTraitsMetadataForToken ---");
        string memory traits = svgRenderer.getTraitsMetadataForToken(1);
        console.log("Traits:", traits);

        console.log("\n--- Step 3: getHTML ---");
        try htmlRenderer.getHTML(1, svg) returns (string memory htmlContent) {
            console.log("HTML length:", bytes(htmlContent).length);
        } catch Error(string memory reason) {
            console.log("getHTML reverted:", reason);
        } catch (bytes memory data) {
            console.log("getHTML reverted (raw), bytes:");
            console.logBytes(data);
        }

        console.log("\n--- Step 5: tokenJson ---");
        try nft.tokenJson(1) returns (string memory json) {
            console.log("tokenJson length:", bytes(json).length);
            vm.writeFile("script/data/debug/token1.json", json);
            console.log("Written to token1.json");
        } catch Error(string memory reason) {
            console.log("tokenJson reverted:", reason);
        } catch (bytes memory data) {
            console.log("tokenJson reverted (raw), bytes:");
            console.logBytes(data);
        }

        console.log("\n--- Step 6: tokenURI ---");
        try nft.tokenURI(1) returns (string memory uri) {
            console.log("tokenURI length:", bytes(uri).length);
            vm.writeFile("script/data/debug/token1_uri.txt", uri);
            console.log("Written to token1_uri.txt");
        } catch Error(string memory reason) {
            console.log("tokenURI reverted:", reason);
        } catch (bytes memory data) {
            console.log("tokenURI reverted (raw), bytes:");
            console.logBytes(data);
        }
    }
}
