// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../../src/nft/IDealerRendererSVG.sol";
import "../base/DeployBase.s.sol";

/**
 * @title AssignTraits - Reveal-time assignments on the renderer
 * @notice Two scopes of operations:
 *
 *   Manifest-driven (reads script/data/assignments.json, produced by
 *   ../generateAssignments.py):
 *     - `assignTokenTraitsRange(start, count)` -- slice of normal+special
 *       entries, calls batchSetTraits.
 *     - `assignOneOfOnesFromManifest()` -- all one-of-one entries, looks up
 *       each name in script/data/{network}/pointers.json, calls
 *       batchSetOneOfOnes.
 *     - `assignOneOfOnesFromManifestRange(start, count)` -- chunked slice of
 *       one-of-one entries, same lookup, calls batchSetOneOfOnes.
 *
 *   Low-level escape hatches (still useful for ad-hoc fixes):
 *     - `assignTokenTraits(uint256[], bytes32[])` -- raw passthrough.
 *     - `assignOneOfOnes(uint256[])` -- index-aligned with traits.json oneofone[].
 *
 *   All entry points are owner-only and intended for reveal-time. Upload-side
 *   prep (FileStore + batchAddTraits) lives in UploadTraits.s.sol.
 *
 * @dev Run as EVM mode (no --zksync flag).
 *
 * Usage:
 *   forge script script/upload/AssignTraits.s.sol:AssignTraits \
 *     --sig "assignTokenTraitsRange(uint256,uint256)" 0 500 \
 *     --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
 *
 *   forge script script/upload/AssignTraits.s.sol:AssignTraits \
 *     --sig "assignOneOfOnesFromManifest()" \
 *     --rpc-url https://api.testnet.abs.xyz --account dealersKeystore --broadcast
 *
 * @author Berny0x
 */
contract AssignTraits is DeployBase {
    string constant TRAITS_JSON_PATH = "script/data/traits.json";
    string constant ASSIGNMENTS_JSON_PATH = "script/data/assignments.json";

    // -------------------------------------------------------------------
    // Manifest-driven entry points
    // -------------------------------------------------------------------

    function assignTokenTraitsRange(uint256 start, uint256 count) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        AssignmentEntry[] memory manifest = _readManifest();

        (uint256[] memory tokenIds, bytes32[] memory packedTraits) = _sliceNormalAndSpecial(manifest, start, count);

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Assigning Token Traits (range)");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("Range start:", start);
        console.log("Range count:", count);
        console.log("Tokens in slice:", tokenIds.length);
        console.log("");

        if (tokenIds.length > 0) {
            IDealerRendererSVG(rendererSvg).batchSetTraits(tokenIds, packedTraits);
        }

        vm.stopBroadcast();
        console.log("Done.");
    }

    function assignOneOfOnesFromManifest() external {
        _assignOneOfOnesRange(0, type(uint256).max);
    }

    function assignOneOfOnesFromManifestRange(uint256 start, uint256 count) external {
        _assignOneOfOnesRange(start, count);
    }

    function _assignOneOfOnesRange(uint256 start, uint256 count) internal {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        (uint256[] memory allIds, string[] memory allNames, address[] memory allPtrs) = _collectOneOfOnes();
        uint256 total = allIds.length;

        if (start > total) start = total;
        uint256 end = start + count;
        if (end < start || end > total) end = total;
        uint256 len = end - start;

        uint256[] memory tokenIds = new uint256[](len);
        string[] memory names = new string[](len);
        address[] memory pointers = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            tokenIds[i] = allIds[start + i];
            names[i] = allNames[start + i];
            pointers[i] = allPtrs[start + i];
        }

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Assigning One-of-Ones (from manifest)");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("Range start:", start);
        console.log("Range count:", count);
        console.log("In slice:", len);
        console.log("");

        if (len > 0) {
            IDealerRendererSVG(rendererSvg).batchSetOneOfOnes(tokenIds, names, pointers);
            for (uint256 i = 0; i < len; i++) {
                console.log(string.concat("  ", names[i], " -> token ", vm.toString(tokenIds[i])));
            }
        }

        vm.stopBroadcast();
        console.log("Done.");
    }

    function _collectOneOfOnes()
        internal
        returns (uint256[] memory tokenIds, string[] memory names, address[] memory pointers)
    {
        AssignmentEntry[] memory manifest = _readManifest();
        PointerEntry[] memory oneOfOnePointers = _loadPointerEntries(_readPointersJson(), "oneofone");

        uint256 ooCount = 0;
        for (uint256 i = 0; i < manifest.length; i++) {
            if (_isOneOfOne(manifest[i].kind)) ooCount++;
        }

        tokenIds = new uint256[](ooCount);
        names = new string[](ooCount);
        pointers = new address[](ooCount);
        uint256 w = 0;
        for (uint256 i = 0; i < manifest.length; i++) {
            if (!_isOneOfOne(manifest[i].kind)) continue;
            address ptr = _findPointerByName(oneOfOnePointers, manifest[i].name);
            require(ptr != address(0), string.concat("Pointer not found for one-of-one '", manifest[i].name, "'"));
            tokenIds[w] = manifest[i].tokenId;
            names[w] = manifest[i].name;
            pointers[w] = ptr;
            w++;
        }
    }

    function manifestNormalSpecialCount() external returns (uint256) {
        AssignmentEntry[] memory manifest = _readManifest();
        uint256 n = 0;
        for (uint256 i = 0; i < manifest.length; i++) {
            if (!_isOneOfOne(manifest[i].kind)) n++;
        }
        console.log("Normal+special in manifest:", n);
        return n;
    }

    // -------------------------------------------------------------------
    // Low-level entry points
    // -------------------------------------------------------------------

    function assignTokenTraits(uint256[] calldata tokenIds, bytes32[] calldata packedTraits) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");
        require(tokenIds.length == packedTraits.length, "Length mismatch");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Assigning Token Traits");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("Tokens:", tokenIds.length);
        console.log("");

        IDealerRendererSVG(rendererSvg).batchSetTraits(tokenIds, packedTraits);

        vm.stopBroadcast();
        console.log("Done.");
    }

    function assignOneOfOnes(uint256[] calldata tokenIds) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        string memory traitsPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory traitsJson = vm.readFile(traitsPath);
        OneOfOneJson[] memory traits = abi.decode(vm.parseJson(traitsJson, ".oneofone"), (OneOfOneJson[]));

        address[] memory pointers = _loadPointerArray(_readPointersJson(), "oneofone", traits.length);

        require(tokenIds.length == traits.length, "Token IDs count must match one-of-ones count");

        string[] memory names = new string[](traits.length);
        for (uint256 i = 0; i < traits.length; i++) {
            require(pointers[i] != address(0), string.concat("Pointer not uploaded for ", traits[i].name));
            names[i] = traits[i].name;
        }

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Assigning One-of-Ones to Token IDs");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("Count:", traits.length);
        console.log("");

        IDealerRendererSVG(rendererSvg).batchSetOneOfOnes(tokenIds, names, pointers);

        for (uint256 i = 0; i < traits.length; i++) {
            console.log(string.concat("  ", traits[i].name, " -> token ", vm.toString(tokenIds[i])));
        }

        vm.stopBroadcast();
        console.log("Done.");
    }

    // -------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------

    function _readManifest() internal view returns (AssignmentEntry[] memory) {
        string memory path = string.concat(vm.projectRoot(), "/", ASSIGNMENTS_JSON_PATH);
        string memory json = vm.readFile(path);
        bytes memory raw = vm.parseJson(json, ".tokens");
        return abi.decode(raw, (AssignmentEntry[]));
    }

    function _sliceNormalAndSpecial(AssignmentEntry[] memory manifest, uint256 start, uint256 count)
        internal
        pure
        returns (uint256[] memory tokenIds, bytes32[] memory packed)
    {
        uint256 totalNs = 0;
        for (uint256 i = 0; i < manifest.length; i++) {
            if (!_isOneOfOne(manifest[i].kind)) totalNs++;
        }
        if (start > totalNs) start = totalNs;
        uint256 end = start + count;
        if (end < start || end > totalNs) end = totalNs;
        uint256 sliceLen = end - start;

        tokenIds = new uint256[](sliceLen);
        packed = new bytes32[](sliceLen);

        uint256 nsIdx = 0;
        uint256 w = 0;
        for (uint256 i = 0; i < manifest.length && w < sliceLen; i++) {
            if (_isOneOfOne(manifest[i].kind)) continue;
            if (nsIdx >= start) {
                tokenIds[w] = manifest[i].tokenId;
                packed[w] = manifest[i].packed;
                w++;
            }
            nsIdx++;
        }
    }

    function _isOneOfOne(string memory kind) internal pure returns (bool) {
        return keccak256(bytes(kind)) == keccak256(bytes("oneOfOne"));
    }

    function _findPointerByName(PointerEntry[] memory pool, string memory name) internal pure returns (address) {
        bytes32 needle = keccak256(bytes(name));
        for (uint256 i = 0; i < pool.length; i++) {
            if (keccak256(bytes(pool[i].name)) == needle) return pool[i].pointer;
        }
        return address(0);
    }
}

struct OneOfOneJson {
    string content;
    string name;
}

struct AssignmentEntry {
    string kind;
    string name;
    bytes32 packed;
    uint256 tokenId;
}
