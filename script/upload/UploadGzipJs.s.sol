// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SSTORE2} from "solady/src/utils/SSTORE2.sol";
import "../../src/nft/IFileStore.sol";
import "../base/DeployBase.s.sol";

/**
 * @title UploadGzipJs - Upload gzipped JS to FileStore, then set on HTML renderer
 * @notice Two-step process due to Abstract Chain's dual VM:
 *
 * Step 1: Upload to FileStore (EVM mode — no --zksync):
 *   forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs \
 *       --sig "upload()" \
 *       --rpc-url https://api.testnet.abs.xyz \
 *       --account dealersKeystore --broadcast
 *
 * Step 2: Set filename on renderer (zkSync mode):
 *   forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs \
 *       --sig "setFilename(string)" "dealers-testnet-1779291187.js.gz" \
 *       --zksync --skip "RendererSVG" --skip "UploadTraits" \
 *       --rpc-url https://api.testnet.abs.xyz \
 *       --account dealersKeystore --broadcast
 *
 * Prerequisites:
 *   cd ../dealers-app && ./build-single-file.sh
 *   (copies output to script/data/dealers.js.gz.b64)
 */
contract UploadGzipJs is DeployBase {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
    uint256 constant CHUNK_SIZE = 24000;

    function upload() external {
        string memory content = vm.readFile("script/data/dealers.js.gz.b64");
        require(bytes(content).length > 0, "dealers.js.gz.b64 is empty - run build-single-file.sh first");

        string memory filename = _buildFilename();
        string[] memory chunks = _splitIntoChunks(content);

        console.log("==============================================");
        console.log("   Step 1: Upload JS to FileStore (EVM)");
        console.log("==============================================");
        console.log("Filename:", filename);
        console.log("Content size:", bytes(content).length, "bytes (base64)");
        console.log("Chunks:", chunks.length);

        vm.startBroadcast();

        address[] memory pointers = new address[](chunks.length);
        for (uint256 i = 0; i < chunks.length; i++) {
            pointers[i] = SSTORE2.write(bytes(chunks[i]));
            console.log(string.concat("  Chunk ", vm.toString(i), " -> ", vm.toString(pointers[i])));
        }

        FILE_STORE.createFileFromPointers(filename, pointers);

        vm.stopBroadcast();

        gzipFilename = filename;
        _saveAddresses();

        console.log("Uploaded to FileStore");
        console.log("Filename saved to deployments JSON");
        console.log("");
        console.log("Next step: run setFilename with --zksync using this filename:");
        console.log(filename);
    }

    function setFilename(string calldata filename) external {
        _loadAddresses();
        _requireAddress(rendererHtml, "RENDERER_HTML");

        console.log("==============================================");
        console.log("   Step 2: Set filename on renderer (zkSync)");
        console.log("==============================================");
        console.log("Renderer HTML:", rendererHtml);
        console.log("Filename:", filename);

        vm.startBroadcast();
        (bool ok,) = rendererHtml.call(abi.encodeWithSignature("setDealerGzipFilename(string)", filename));
        require(ok, "setDealerGzipFilename failed");
        vm.stopBroadcast();

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
