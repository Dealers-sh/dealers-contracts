// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDealerRendererHTML} from "./IDealerRendererHTML.sol";
import {IFileStore} from "./IFileStore.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Base64} from "solady/src/utils/Base64.sol";
import {LibString} from "solady/src/utils/LibString.sol";

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
    using LibString for uint256;

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
     * @param tokenId The token ID for dynamic title/meta tags
     * @param svg The SVG content to embed in the HTML
     * @return Complete HTML document as a string
     */
    function getHTML(uint256 tokenId, string memory svg) external view override returns (string memory) {
        string memory svgBase64 = Base64.encode(bytes(svg));
        return string(abi.encodePacked(
            '<!DOCTYPE html><html lang="en"><head>',
            _buildHead(tokenId, svgBase64),
            getScriptJs(),
            getGzip(),
            '</head><body>',
            svg,
            '</body></html>'
        ));
    }

    // =============================================================
    //                      INTERNAL HELPERS
    // =============================================================

    function _buildHead(uint256 tokenId, string memory svgBase64) private pure returns (string memory) {
        string memory id = tokenId.toString();
        string memory svgDataUri = string(abi.encodePacked("data:image/svg+xml;base64,", svgBase64));

        bytes memory metaTags = abi.encodePacked(
            '<meta charset="UTF-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
            '<title>Dealer #', id,
            '</title><meta name="description" content="Dealer #', id,
            unicode' \u2014 Dealers.exe: Fully on-chain. Permanently stored. Deal your way to the top and become a legend. Play now.">'
        );

        bytes memory ogTags = abi.encodePacked(
            '<meta property="og:title" content="Dealer #', id,
            unicode' \u2014 Dealers.exe">',
            '<meta property="og:description" content="Fully on-chain. Permanently stored. Deal your way to the top and become a legend. Play now.">'
            '<meta property="og:type" content="website">'
            '<meta name="theme-color" content="#000000">'
        );

        bytes memory links = abi.encodePacked(
            '<link rel="icon" type="image/svg+xml" href="', svgDataUri,
            '"><link rel="apple-touch-icon" href="', svgDataUri,
            '"><link rel="manifest" href="', _buildManifestDataUri(id, svgDataUri), '">'
        );

        return string(abi.encodePacked(metaTags, ogTags, links));
    }

    function _buildManifestDataUri(string memory id, string memory svgDataUri) private pure returns (string memory) {
        bytes memory manifestJson = abi.encodePacked(
            '{"name":"Dealer #', id,
            unicode' \u2014 Dealers.exe","short_name":"Dealer #', id,
            '","icons":[{"src":"', svgDataUri,
            '","sizes":"any","type":"image/svg+xml","purpose":"maskable"}],'
            '"theme_color":"#000000","background_color":"#000000","display":"standalone"}'
        );
        return string(abi.encodePacked("data:application/manifest+json;base64,", Base64.encode(manifestJson)));
    }
}
