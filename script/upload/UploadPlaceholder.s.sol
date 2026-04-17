// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../../src/nft/IDealerRendererSVG.sol";
import "../../src/nft/IFileStore.sol";
import "../base/DeployBase.s.sol";

/**
 * @title UploadPlaceholder - Upload and set placeholder SVG
 * @notice Uploads placeholder from traits.json to FileStore and sets it on the renderer
 * @dev FileStore.createFile auto-chunks large content into 24575-byte SSTORE2 pointers.
 *      Loads renderer address from testnet.json via DeployBase.
 *
 * Usage:
 *   forge script script/upload/UploadPlaceholder.s.sol:UploadPlaceholder \
 *     --broadcast \
 *     --account dealersKeystore \
 *     --rpc-url https://api.testnet.abs.xyz
 */
contract UploadPlaceholder is DeployBase {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
    string constant TRAITS_JSON_PATH = "script/data/traits.json";
    uint256 constant CHUNK_SIZE = 24000;

    function run() external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();

        console.log("==============================================");
        console.log("   Uploading Placeholder SVG");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("");

        string memory jsonPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory json = vm.readFile(jsonPath);

        bytes memory placeholderData = vm.parseJson(json, ".placeholder");
        require(placeholderData.length > 0, "No placeholder found in traits.json");

        PlaceholderJson memory p = abi.decode(placeholderData, (PlaceholderJson));

        address pointer;
        bool needsJsonUpdate = false;

        if (p.pointer != address(0)) {
            pointer = p.pointer;
            console.log("Placeholder already uploaded:", pointer);
        } else {
            string memory uniqueName = string.concat("dealers-placeholder-", vm.toString(block.timestamp));

            bytes memory contentBytes = bytes(p.content);
            console.log("Content size:", contentBytes.length, "bytes");

            string[] memory chunks = _splitIntoChunks(p.content);
            console.log("Splitting into", chunks.length, "chunks");

            (pointer,) = FILE_STORE.createFileFromChunks(uniqueName, chunks);

            console.log("Uploaded placeholder:", pointer);
            needsJsonUpdate = true;
        }

        IDealerRendererSVG(rendererSvg).setPlaceholderSvg(pointer);
        console.log("Set placeholder on renderer");

        vm.stopBroadcast();

        if (needsJsonUpdate) {
            _updatePlaceholderPointerInJson(jsonPath, pointer);
            console.log("Updated traits.json with pointer");
        }

        console.log("");
        console.log("Done!");
    }

    function _updatePlaceholderPointerInJson(string memory jsonPath, address pointer) internal {
        vm.writeJson(vm.toString(pointer), jsonPath, ".placeholder.pointer");
    }

    function _splitIntoChunks(string memory content) internal pure returns (string[] memory) {
        bytes memory contentBytes = bytes(content);
        uint256 numChunks = (contentBytes.length + CHUNK_SIZE - 1) / CHUNK_SIZE;

        string[] memory chunks = new string[](numChunks);

        for (uint256 i = 0; i < numChunks; i++) {
            uint256 start = i * CHUNK_SIZE;
            uint256 end = start + CHUNK_SIZE;
            if (end > contentBytes.length) {
                end = contentBytes.length;
            }

            bytes memory chunk = new bytes(end - start);
            for (uint256 j = start; j < end; j++) {
                chunk[j - start] = contentBytes[j];
            }
            chunks[i] = string(chunk);
        }

        return chunks;
    }
}

struct PlaceholderJson {
    string content;
    address pointer;
}
