// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SSTORE2} from "solady/src/utils/SSTORE2.sol";
import "../../src/nft/IDealerRendererSVG.sol";
import "../../src/nft/IFileStore.sol";
import "../base/DeployBase.s.sol";

/**
 * @title UploadTraits - Upload SVG traits from traits.json to FileStore
 * @notice Reads traits.json, uploads traits where pointer is null, updates JSON with new pointers
 * @dev Designed for EVM mode deployment (no --zksync flag) since it uses SSTORE2/EXTCODECOPY.
 *      Loads renderer address from testnet.json via DeployBase.
 *
 * JSON format (script/data/traits.json):
 * {
 *   "normal": [{ "category": 0, "name": "Black", "probability": 100, "content": "...", "pointer": null }],
 *   "special": [...],
 *   "oneofone": [{ "name": "Satoshi", "content": "...", "pointer": null }]
 * }
 *
 * Usage:
 *   # Upload normal traits
 *   forge script script/upload/UploadTraits.s.sol:UploadTraits \
 *     --sig "uploadNormal()" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 *   # Upload special traits
 *   forge script script/upload/UploadTraits.s.sol:UploadTraits \
 *     --sig "uploadSpecial()" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 *   # Upload one-of-ones (requires token IDs)
 *   forge script script/upload/UploadTraits.s.sol:UploadTraits \
 *     --sig "uploadOneOfOnes(uint256[])" "[1,42,99]" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * @author Berny0x
 */
contract UploadTraits is DeployBase {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);

    string constant TRAITS_JSON_PATH = "script/data/traits.json";
    uint256 constant CHUNK_SIZE = 24000;

    string[12] categoryNames = [
        "backdrop", "head", "expression", "eyes", "nose", "eartip",
        "earaccessory", "facialhair", "mouth", "chin", "neck", "accessory"
    ];

    function uploadNormal() external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading Normal Traits from traits.json");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("");

        _uploadTraitsFromJsonRange(rendererSvg, 0, 0, type(uint256).max);

        vm.stopBroadcast();
    }

    function uploadSpecial() external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading Special Traits from traits.json");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("");

        _uploadTraitsFromJsonRange(rendererSvg, 1, 0, type(uint256).max);

        vm.stopBroadcast();
    }

    function uploadNormalRange(uint256 start, uint256 count) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading Normal Traits (range)");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("start:", start);
        console.log("count:", count);
        console.log("");

        _uploadTraitsFromJsonRange(rendererSvg, 0, start, count);

        vm.stopBroadcast();
    }

    function uploadSpecialRange(uint256 start, uint256 count) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading Special Traits (range)");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("start:", start);
        console.log("count:", count);
        console.log("");

        _uploadTraitsFromJsonRange(rendererSvg, 1, start, count);

        vm.stopBroadcast();
    }

    function uploadFirstNormalPerCategory(uint256 perCat) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading first N Normal traits per category");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("perCat:", perCat);
        console.log("");

        _uploadTraitsCapped(rendererSvg, 0, perCat);

        vm.stopBroadcast();
    }

    function uploadFirstSpecialPerCategory(uint256 perCat) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading first N Special traits per category");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("perCat:", perCat);
        console.log("");

        _uploadTraitsCapped(rendererSvg, 1, perCat);

        vm.stopBroadcast();
    }

    function uploadOneOfOnes(uint256[] calldata tokenIds) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading One-of-Ones from traits.json");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("Token IDs count:", tokenIds.length);
        console.log("");

        _uploadOneOfOnesFromJson(rendererSvg, tokenIds);

        vm.stopBroadcast();
    }

    function uploadPlaceholder() external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading Placeholder from traits.json");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("");

        _uploadPlaceholderFromJson(rendererSvg);

        vm.stopBroadcast();
    }


    struct TraitsCtx {
        address renderer;
        uint8 charType;
        TraitJson[] traits;
        uint8[] addCharacterTypes;
        uint8[] addCategories;
        string[] addNames;
        address[] addPointers;
        uint256[] writePointerIndices;
        address[] writePointerValues;
        uint256[12] onchainCount;
        uint256[12] positionInCat;
        uint256 addCount;
        uint256 writePointerCount;
        uint256 uploadCount;
        uint256 skipCount;
        uint256 updateCount;
        uint256 perCatCap;
    }

    function _uploadTraitsCapped(address renderer, uint8 charType, uint256 perCat) internal {
        string memory jsonPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory json = vm.readFile(jsonPath);

        string memory typeKey = charType == 0 ? "normal" : "special";
        bytes memory traitsArray = vm.parseJson(json, string.concat(".", typeKey));
        TraitJson[] memory traits = abi.decode(traitsArray, (TraitJson[]));

        console.log(string.concat(
            "Found ", vm.toString(traits.length), " ", typeKey,
            " traits; capping to first ", vm.toString(perCat), " per category"
        ));

        TraitsCtx memory ctx;
        ctx.renderer = renderer;
        ctx.charType = charType;
        ctx.traits = traits;
        ctx.addCharacterTypes = new uint8[](traits.length);
        ctx.addCategories = new uint8[](traits.length);
        ctx.addNames = new string[](traits.length);
        ctx.addPointers = new address[](traits.length);
        ctx.writePointerIndices = new uint256[](traits.length);
        ctx.writePointerValues = new address[](traits.length);
        ctx.perCatCap = perCat;

        for (uint8 c = 0; c < 12; c++) {
            ctx.onchainCount[c] = IDealerRendererSVG(renderer).traitCount(charType, c);
        }

        for (uint256 i = 0; i < traits.length; i++) {
            _processTraitEntry(ctx, i);
        }

        if (ctx.addCount > 0) {
            uint256 finalAddCount = ctx.addCount;
            uint8[] memory addCT = ctx.addCharacterTypes;
            uint8[] memory addCat = ctx.addCategories;
            string[] memory addNm = ctx.addNames;
            address[] memory addPt = ctx.addPointers;
            assembly ("memory-safe") {
                mstore(addCT, finalAddCount)
                mstore(addCat, finalAddCount)
                mstore(addNm, finalAddCount)
                mstore(addPt, finalAddCount)
            }
            IDealerRendererSVG(renderer).batchAddTraits(addCT, addCat, addNm, addPt);
            console.log(string.concat("Registered ", vm.toString(finalAddCount), " new traits with renderer"));
        }

        for (uint256 i = 0; i < ctx.writePointerCount; i++) {
            string memory key = string.concat(".", typeKey, "[", vm.toString(ctx.writePointerIndices[i]), "].pointer");
            vm.writeJson(vm.toString(ctx.writePointerValues[i]), jsonPath, key);
        }

        console.log("");
        console.log(string.concat(
            "Summary: uploaded ", vm.toString(ctx.uploadCount),
            " (", vm.toString(ctx.updateCount), " re-uploads), added ",
            vm.toString(ctx.addCount), ", skipped ", vm.toString(ctx.skipCount)
        ));
    }

    function _uploadTraitsFromJsonRange(address renderer, uint8 charType, uint256 start, uint256 count) internal {
        string memory jsonPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory json = vm.readFile(jsonPath);

        string memory typeKey = charType == 0 ? "normal" : "special";
        bytes memory traitsArray = vm.parseJson(json, string.concat(".", typeKey));

        TraitJson[] memory traits = abi.decode(traitsArray, (TraitJson[]));

        if (start > traits.length) start = traits.length;
        uint256 end = start + count;
        if (end < start || end > traits.length) end = traits.length;
        uint256 sliceLen = end - start;

        console.log(string.concat(
            "Found ", vm.toString(traits.length), " ", typeKey,
            " traits; processing [", vm.toString(start), ", ", vm.toString(end), ")"
        ));

        TraitsCtx memory ctx;
        ctx.renderer = renderer;
        ctx.charType = charType;
        ctx.traits = traits;
        ctx.addCharacterTypes = new uint8[](sliceLen);
        ctx.addCategories = new uint8[](sliceLen);
        ctx.addNames = new string[](sliceLen);
        ctx.addPointers = new address[](sliceLen);
        ctx.writePointerIndices = new uint256[](sliceLen);
        ctx.writePointerValues = new address[](sliceLen);
        ctx.perCatCap = type(uint256).max;

        for (uint8 c = 0; c < 12; c++) {
            ctx.onchainCount[c] = IDealerRendererSVG(renderer).traitCount(charType, c);
        }

        for (uint256 j = 0; j < start; j++) {
            ctx.positionInCat[traits[j].category]++;
        }

        for (uint256 i = start; i < end; i++) {
            _processTraitEntry(ctx, i);
        }

        if (ctx.addCount > 0) {
            uint256 finalAddCount = ctx.addCount;
            uint8[] memory addCT = ctx.addCharacterTypes;
            uint8[] memory addCat = ctx.addCategories;
            string[] memory addNm = ctx.addNames;
            address[] memory addPt = ctx.addPointers;
            assembly ("memory-safe") {
                mstore(addCT, finalAddCount)
                mstore(addCat, finalAddCount)
                mstore(addNm, finalAddCount)
                mstore(addPt, finalAddCount)
            }
            IDealerRendererSVG(renderer).batchAddTraits(addCT, addCat, addNm, addPt);
            console.log(string.concat("Registered ", vm.toString(finalAddCount), " new traits with renderer"));
        }

        for (uint256 i = 0; i < ctx.writePointerCount; i++) {
            string memory key = string.concat(".", typeKey, "[", vm.toString(ctx.writePointerIndices[i]), "].pointer");
            vm.writeJson(vm.toString(ctx.writePointerValues[i]), jsonPath, key);
        }

        console.log("");
        console.log(string.concat(
            "Summary: uploaded ", vm.toString(ctx.uploadCount),
            " (",  vm.toString(ctx.updateCount), " re-uploads via updateTraitPointer), added ",
            vm.toString(ctx.addCount), ", skipped ", vm.toString(ctx.skipCount)
        ));
    }

    function _processTraitEntry(TraitsCtx memory ctx, uint256 i) internal {
        TraitJson memory t = ctx.traits[i];
        ctx.positionInCat[t.category]++;
        uint256 pos = ctx.positionInCat[t.category];

        if (pos > ctx.perCatCap) return;

        if (pos <= ctx.onchainCount[t.category]) {
            if (t.pointer != address(0)) {
                ctx.skipCount++;
                console.log(string.concat("  Skip (registered): ", t.name));
                return;
            }

            address newPointer = _uploadTraitContent(ctx.charType, t.category, t.name, t.content, i);
            console.log(string.concat("  Re-uploaded: ", t.name, " -> ", vm.toString(newPointer)));

            IDealerRendererSVG(ctx.renderer).updateTraitPointer(ctx.charType, t.category, pos, newPointer);
            console.log(string.concat("  updateTraitPointer cat=", vm.toString(t.category), " pos=", vm.toString(pos)));

            ctx.writePointerIndices[ctx.writePointerCount] = i;
            ctx.writePointerValues[ctx.writePointerCount] = newPointer;
            ctx.writePointerCount++;
            ctx.uploadCount++;
            ctx.updateCount++;
            return;
        }

        address pointer;
        if (t.pointer != address(0)) {
            pointer = t.pointer;
            console.log(string.concat("  Use cached pointer: ", t.name));
        } else {
            pointer = _uploadTraitContent(ctx.charType, t.category, t.name, t.content, i);
            console.log(string.concat("  Uploaded: ", t.name, " -> ", vm.toString(pointer)));

            ctx.writePointerIndices[ctx.writePointerCount] = i;
            ctx.writePointerValues[ctx.writePointerCount] = pointer;
            ctx.writePointerCount++;
            ctx.uploadCount++;
        }

        ctx.addCharacterTypes[ctx.addCount] = ctx.charType;
        ctx.addCategories[ctx.addCount] = t.category;
        ctx.addNames[ctx.addCount] = t.name;
        ctx.addPointers[ctx.addCount] = pointer;
        ctx.addCount++;
    }

    function _uploadTraitContent(
        uint8 charType,
        uint8 category,
        string memory name,
        string memory content,
        uint256 index
    ) internal returns (address pointer) {
        string memory uniqueName = _generateUniqueName(charType, category, name, index);
        address[] memory chunkPointers = _writeChunkPointers(content);
        (pointer,) = FILE_STORE.createFileFromPointers(uniqueName, chunkPointers);
    }

    function _writeChunkPointers(string memory content) internal returns (address[] memory) {
        bytes memory contentBytes = bytes(content);
        uint256 numChunks = (contentBytes.length + CHUNK_SIZE - 1) / CHUNK_SIZE;
        if (numChunks == 0) numChunks = 1;

        address[] memory pointers = new address[](numChunks);
        for (uint256 i = 0; i < numChunks; i++) {
            uint256 start = i * CHUNK_SIZE;
            uint256 end = start + CHUNK_SIZE;
            if (end > contentBytes.length) end = contentBytes.length;

            bytes memory chunk = new bytes(end - start);
            for (uint256 j = start; j < end; j++) {
                chunk[j - start] = contentBytes[j];
            }
            pointers[i] = SSTORE2.write(chunk);
        }
        return pointers;
    }


    struct OneOfOneCtx {
        OneOfOneJson[] traits;
        uint256[] tids;
        string[] names;
        address[] pointers;
        uint256[] uploadedIndices;
        address[] uploadedPointers;
        uint256 uploadCount;
        uint256 skipCount;
    }

    function _uploadOneOfOnesFromJson(address renderer, uint256[] calldata tokenIds) internal {
        string memory jsonPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory json = vm.readFile(jsonPath);

        bytes memory traitsArray = vm.parseJson(json, ".oneofone");
        OneOfOneJson[] memory traits = abi.decode(traitsArray, (OneOfOneJson[]));

        console.log(string.concat("Found ", vm.toString(traits.length), " one-of-ones"));

        require(tokenIds.length == traits.length, "Token IDs count must match one-of-ones count");

        OneOfOneCtx memory ctx = OneOfOneCtx({
            traits: traits,
            tids: new uint256[](traits.length),
            names: new string[](traits.length),
            pointers: new address[](traits.length),
            uploadedIndices: new uint256[](traits.length),
            uploadedPointers: new address[](traits.length),
            uploadCount: 0,
            skipCount: 0
        });

        for (uint256 i = 0; i < traits.length; i++) {
            _processOneOfOneEntry(ctx, i, tokenIds[i]);
        }

        if (traits.length > 0) {
            IDealerRendererSVG(renderer).batchSetOneOfOnes(ctx.tids, ctx.names, ctx.pointers);
            console.log(string.concat("Registered ", vm.toString(traits.length), " one-of-ones with renderer"));
        }

        for (uint256 i = 0; i < ctx.uploadCount; i++) {
            string memory key = string.concat(".oneofone[", vm.toString(ctx.uploadedIndices[i]), "].pointer");
            vm.writeJson(vm.toString(ctx.uploadedPointers[i]), jsonPath, key);
        }

        console.log("");
        console.log(string.concat("Summary: uploaded ", vm.toString(ctx.uploadCount), ", skipped ", vm.toString(ctx.skipCount)));
    }

    function _processOneOfOneEntry(OneOfOneCtx memory ctx, uint256 i, uint256 tokenId) internal {
        OneOfOneJson memory t = ctx.traits[i];
        address pointer;
        if (t.pointer != address(0)) {
            pointer = t.pointer;
            ctx.skipCount++;
            console.log(string.concat("  Skip (cached): ", t.name));
        } else {
            string memory uniqueName = string.concat(
                "dealers-oneofone-", t.name, "-",
                vm.toString(block.timestamp), "-", vm.toString(i)
            );
            address[] memory chunkPointers = _writeChunkPointers(t.content);
            (pointer,) = FILE_STORE.createFileFromPointers(uniqueName, chunkPointers);
            console.log(string.concat("  Uploaded: ", t.name, " -> ", vm.toString(pointer)));

            ctx.uploadedIndices[ctx.uploadCount] = i;
            ctx.uploadedPointers[ctx.uploadCount] = pointer;
            ctx.uploadCount++;
        }

        ctx.tids[i] = tokenId;
        ctx.names[i] = t.name;
        ctx.pointers[i] = pointer;
    }

    function _uploadPlaceholderFromJson(address renderer) internal {
        string memory jsonPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory json = vm.readFile(jsonPath);

        bytes memory placeholderData = vm.parseJson(json, ".placeholder");
        if (placeholderData.length == 0) {
            console.log("No placeholder found in traits.json");
            return;
        }

        PlaceholderJson memory p = abi.decode(placeholderData, (PlaceholderJson));

        address pointer;
        if (p.pointer != address(0)) {
            pointer = p.pointer;
            console.log("Placeholder already uploaded:", pointer);
        } else {
            string memory uniqueName = string.concat("dealers-placeholder-", vm.toString(block.timestamp));
            address[] memory chunkPointers = _writeChunkPointers(p.content);
            (pointer,) = FILE_STORE.createFileFromPointers(uniqueName, chunkPointers);
            console.log("Uploaded placeholder:", pointer);

            _updatePlaceholderPointerInJson(jsonPath, pointer);
        }

        IDealerRendererSVG(renderer).setPlaceholderSvg(pointer);
        console.log("Set placeholder on renderer");
    }

    function _updatePlaceholderPointerInJson(string memory jsonPath, address pointer) internal {
        vm.writeJson(vm.toString(pointer), jsonPath, ".placeholder.pointer");
    }

    function _generateUniqueName(
        uint8 charType,
        uint8 category,
        string memory traitName,
        uint256 index
    ) internal view returns (string memory) {
        string memory prefix = charType == 0 ? "dealers-normal" : "dealers-special";
        string memory categoryName = categoryNames[category];
        return string.concat(
            prefix, "-", categoryName, "-", traitName, "-",
            vm.toString(block.timestamp), "-", vm.toString(index)
        );
    }

}

struct TraitJson {
    uint8 category;
    string content;
    string name;
    address pointer;
}

struct OneOfOneJson {
    string content;
    string name;
    address pointer;
}

struct PlaceholderJson {
    string content;
    address pointer;
}

