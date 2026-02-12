// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDealerRendererHTML} from "./IDealerRendererHTML.sol";
import {IFileStore} from "./IFileStore.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

/**
 * @title DealerRendererHTML - On-Chain HTML Generator
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev Generates interactive HTML wrapper for dealer NFT SVGs using on-chain FileStore
 * @author Dealers.Exe Team
 */
contract DealerRendererHTML is IDealerRendererHTML, Ownable {
    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidAddress();
    error EmptyFilename();

    // =============================================================
    //                            EVENTS
    // =============================================================

    event FileStoreUpdated(address indexed oldStore, address indexed newStore);
    event GunzipFilenameUpdated(string oldFilename, string newFilename);
    event GzipFilenameUpdated(string oldFilename, string newFilename);

    // =============================================================
    //                            STORAGE
    // =============================================================

    string public gunzipFilename = "gunzipScripts-0.0.2.js";
    string public dealerGzipFilename = "src1.min.js.gz";
    IFileStore public fileStore;

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    constructor(address _fileStore) {
        if (_fileStore == address(0)) revert InvalidAddress();
        fileStore = IFileStore(_fileStore);
        _initializeOwner(msg.sender);
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Set the FileStore contract address
     * @param fileStoreAddress The new FileStore address
     */
    function setFileStore(address fileStoreAddress) external onlyOwner {
        if (fileStoreAddress == address(0)) revert InvalidAddress();
        address oldStore = address(fileStore);
        fileStore = IFileStore(fileStoreAddress);
        emit FileStoreUpdated(oldStore, fileStoreAddress);
    }

    /**
     * @notice Set the gunzip decompression library filename in FileStore
     * @param _gunzipFilename The filename of the gunzip JS library
     */
    function setGunzipFilename(string memory _gunzipFilename) external onlyOwner {
        if (bytes(_gunzipFilename).length == 0) revert EmptyFilename();
        string memory oldFilename = gunzipFilename;
        gunzipFilename = _gunzipFilename;
        emit GunzipFilenameUpdated(oldFilename, _gunzipFilename);
    }

    /**
     * @notice Set the gzipped dealer UI script filename in FileStore
     * @param _dealerGzipFilename The filename of the gzipped JS in FileStore
     */
    function setDealerGzipFilename(string memory _dealerGzipFilename) external onlyOwner {
        if (bytes(_dealerGzipFilename).length == 0) revert EmptyFilename();
        string memory oldFilename = dealerGzipFilename;
        dealerGzipFilename = _dealerGzipFilename;
        emit GzipFilenameUpdated(oldFilename, _dealerGzipFilename);
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
            fileStore.getFile(gunzipFilename).read(),
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
