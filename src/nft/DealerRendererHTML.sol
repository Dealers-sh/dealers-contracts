// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDealerRendererHTML} from "./IDealerRendererHTML.sol";
import {IFileStore} from "./IFileStore.sol";

/**
 * @title DealerRendererHTML - On-Chain HTML Generator
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Generates interactive HTML wrapper for dealer NFT SVGs using on-chain FileStore
 * @author Dealers.Exe Team
 */
contract DealerRendererHTML is IDealerRendererHTML {
    // =============================================================
    //                            STORAGE
    // =============================================================

    string public dealerGzipFilename = "src6.min.js.gz";
    IFileStore public fileStore;
    address public deployer;

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor() {
        deployer = msg.sender;
        fileStore = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Set the FileStore contract address
     * @param fileStoreAddress The new FileStore address
     */
    function setFileStore(address fileStoreAddress) external {
        require(msg.sender == deployer, "Only deployer can set file store");
        fileStore = IFileStore(fileStoreAddress);
    }

    /**
     * @notice Set the gzipped JavaScript filename for the dealer UI
     * @param _dealerGzipFilename The filename of the gzipped JS in FileStore
     */
    function setDealerGzipFilename(string memory _dealerGzipFilename) external {
        require(msg.sender == deployer, "Only the deployer can set the gzip filename");
        dealerGzipFilename = _dealerGzipFilename;
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get the gunzip decompression script tag
     * @return Script tag with base64-encoded gunzip library
     */
    function getGzip() public view returns (string memory) {
        return string.concat(
            "<script src=\"data:text/javascript;base64,",
            fileStore.getFile("gunzipScripts-0.0.1.js").read(),
            "\"></script>"
        );
    }

    /**
     * @notice Get the gzipped dealer UI script tag
     * @return Script tag with base64-encoded gzipped JavaScript
     */
    function getScriptJs() public view returns (string memory) {
        return string.concat(
            "<script type=\"text/javascript+gzip\" src=\"data:text/javascript;base64,",
            fileStore.getFile(dealerGzipFilename).read(),
            "\"></script>"
        );
    }

    /**
     * @notice Generate complete HTML document wrapping the dealer SVG
     * @param svg The SVG content to embed in the HTML
     * @return Complete HTML document as a string
     */
    function getHTML(string memory svg) external view override returns (string memory) {
        string memory image = string(abi.encodePacked(
            unicode'<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Dealer # 0000</title><style></style>',
            getScriptJs(),
            getGzip(),
            unicode'</head><body>',
            svg,
            unicode'</body></html>'
        ));

        return image;
    }
}
