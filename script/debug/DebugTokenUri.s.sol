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
        console.log("SVG renderer:", svgAddr);
        console.log("HTML renderer:", htmlAddr);

        try nft.dealersCore() returns (address coreAddr) {
            console.log("Core:", coreAddr);
        } catch {
            console.log("Core: not set or call failed");
        }

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

        console.log("\n--- Step 7: Generate viewer.html ---");
        try nft.tokenJson(1) returns (string memory viewerJson) {
            string memory viewer = _buildViewer(viewerJson);
            vm.writeFile("script/data/debug/viewer.html", viewer);
            console.log("Written to viewer.html");
        } catch {
            console.log("Skipped viewer (tokenJson failed)");
        }
    }

    function _buildViewer(string memory tokenJson) internal pure returns (string memory) {
        return string.concat(
            "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Token Viewer</title>" "<style>"
            "*{margin:0;padding:0;box-sizing:border-box}"
            "body{background:#111;color:#eee;font-family:system-ui,sans-serif;padding:24px}"
            "h1{font-size:18px;margin-bottom:16px;color:#999}"
            ".grid{display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:20px;align-items:start}"
            ".col{background:#1a1a1a;border-radius:8px;padding:16px;min-height:200px}"
            ".col h2{font-size:13px;color:#666;text-transform:uppercase;letter-spacing:1px;margin-bottom:12px}"
            ".col img{width:100%;border-radius:4px}"
            ".col iframe{width:100%;height:500px;border:none;border-radius:4px;background:#000}"
            ".traits{display:grid;grid-template-columns:1fr 1fr;gap:8px}"
            ".trait{background:#222;border-radius:6px;padding:10px}"
            ".trait-type{font-size:10px;color:#666;text-transform:uppercase;letter-spacing:.5px}"
            ".trait-value{font-size:14px;margin-top:4px}" "</style></head><body>",
            "<h1 id='title'></h1>" "<div class='grid'>" "<div class='col'><h2>Image</h2><img id='img'></div>"
            "<div class='col'><h2>Animation</h2><iframe id='anim'></iframe></div>"
            "<div class='col' style='grid-column:span 2'><h2>Metadata</h2><div class='traits' id='traits'></div></div>"
            "</div>" "<script>const d=",
            tokenJson,
            ";" "document.getElementById('title').textContent=d.name;" "document.getElementById('img').src=d.image||'';"
            "if(d.animation_url){" "var h=atob(d.animation_url.split(',')[1]);"
            "var b=new Blob([h],{type:'text/html'});" "document.getElementById('anim').src=URL.createObjectURL(b)}"
            "(d.attributes||[]).forEach(a=>{" "const e=document.createElement('div');e.className='trait';"
            "e.innerHTML='<div class=\"trait-type\">'+a.trait_type+'</div><div class=\"trait-value\">'+a.value+'</div>';"
            "document.getElementById('traits').appendChild(e)" "});</script></body></html>"
        );
    }
}
