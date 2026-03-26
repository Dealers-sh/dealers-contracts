// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/nft/IFileStore.sol";
import "../base/DeployBase.s.sol";

/**
 * @title UploadGzipJs - Upload gzipped JS to FileStore and set on HTML renderer
 * @notice Creates a file in FileStore and updates the HTML renderer's gzip filename
 *
 * Usage:
 *   forge script script/upload/UploadGzipJs.s.sol:UploadGzipJs \
 *     --broadcast \
 *     --account dealersKeystore \
 *     --rpc-url https://api.testnet.abs.xyz
 */
contract UploadGzipJs is DeployBase {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
    string constant FILENAME = "src0.min.js.gz";

    function run() external {
        _loadAddresses();
        _requireAddress(rendererHtml, "RENDERER_HTML");

        vm.startBroadcast();

        string memory content = "H4sIAAAAAAAAA7MGAKkGCWMBAAAA";

        if (!FILE_STORE.fileExists(FILENAME)) {
            FILE_STORE.createFile(FILENAME, content);
            console.log("Uploaded", FILENAME, "to FileStore");
        } else {
            console.log("File already exists:", FILENAME);
        }

        (bool ok,) = rendererHtml.call(abi.encodeWithSignature("setDealerGzipFilename(string)", FILENAME));
        require(ok, "setDealerGzipFilename failed");
        console.log("Set gzip filename on HTML renderer to:", FILENAME);

        vm.stopBroadcast();
    }
}
