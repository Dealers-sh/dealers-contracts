// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../../src/nft/IFileStore.sol";
import "../base/DeployBase.s.sol";

/**
 * @title UploadGzipJs - Build app, upload gzipped JS to FileStore, set on HTML renderer
 * @notice Reads base64(gzip(dealers.js)) from script/data/dealers.js.gz.b64,
 *         uploads to FileStore with a versioned filename, and updates the renderer.
 *
 * Prerequisites:
 *   cd ../dealers-app && ./build-single-file.sh
 *   (this copies the output to script/data/dealers.js.gz.b64)
 *
 * Usage:
 *   forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs \
 *     --broadcast \
 *     --account dealersKeystore \
 *     --rpc-url https://api.testnet.abs.xyz
 */
contract UploadGzipJs is DeployBase {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
    uint256 constant CHUNK_SIZE = 24000;

    function run() external {
        _loadAddresses();
        _requireAddress(rendererHtml, "RENDERER_HTML");

        string memory content = vm.readFile("script/data/dealers.js.gz.b64");
        require(bytes(content).length > 0, "dealers.js.gz.b64 is empty - run build-single-file.sh first");

        string memory filename = _buildFilename();

        console.log("==============================================");
        console.log("   Upload Dealers App JS to FileStore");
        console.log("==============================================");
        console.log("Renderer HTML:", rendererHtml);
        console.log("Filename:", filename);
        console.log("Content size:", bytes(content).length, "bytes (base64)");

        vm.startBroadcast();

        string[] memory chunks = _splitIntoChunks(content);
        console.log("Chunks:", chunks.length);

        FILE_STORE.createFileFromChunks(filename, chunks);
        console.log("Uploaded to FileStore");

        (bool ok,) = rendererHtml.call(abi.encodeWithSignature("setDealerGzipFilename(string)", filename));
        require(ok, "setDealerGzipFilename failed");
        console.log("Set gzip filename on renderer to:", filename);

        vm.stopBroadcast();

        console.log("");
        console.log("Done!");
    }

    function _buildFilename() internal view returns (string memory) {
        string memory chain = "unknown";
        if (block.chainid == 11124) chain = "testnet";
        if (block.chainid == 2741) chain = "mainnet";
        return string.concat("dealers-", chain, "-", vm.toString(block.timestamp), ".js.gz");
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
