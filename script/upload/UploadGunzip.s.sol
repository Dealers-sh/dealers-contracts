// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/nft/IFileStore.sol";

interface IDealerRendererHTML {
    function setGunzipFilename(string memory _gunzipFilename) external;
}

/**
 * @title UploadGunzip - Upload gunzip decompression script to FileStore
 * @notice Uploads gunzipScripts JS and sets the filename on DealerRendererHTML
 *
 * Usage:
 *   source .env && forge script script/UploadGunzip.s.sol:UploadGunzip \
 *     --broadcast \
 *     --account dealersKeystore \
 *     --rpc-url https://api.testnet.abs.xyz
 */
contract UploadGunzip is Script {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
    string constant FILENAME = "gunzipScripts-0.0.2.js";

    function run() external {
        address rendererHTML = vm.envAddress("RENDERER_HTML");
        require(rendererHTML != address(0), "RENDERER_HTML not set");

        string memory filePath = string.concat(vm.projectRoot(), "/script/data/", FILENAME);
        string memory contents = vm.readFile(filePath);
        require(bytes(contents).length > 0, "File is empty");

        console.log("Uploading %s (%d bytes)", FILENAME, bytes(contents).length);

        vm.startBroadcast();

        if (FILE_STORE.fileExists(FILENAME)) {
            console.log("File already exists in FileStore, skipping upload");
        } else {
            (address pointer,) = FILE_STORE.createFile(FILENAME, contents);
            console.log("Uploaded to FileStore, pointer:", pointer);
        }

        IDealerRendererHTML(rendererHTML).setGunzipFilename(FILENAME);
        console.log("Set gunzip filename on renderer:", FILENAME);

        vm.stopBroadcast();
    }
}