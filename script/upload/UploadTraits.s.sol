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
 *   # Upload one-of-ones (chunked, no token assignment — see AssignTraits for that)
 *   forge script script/upload/UploadTraits.s.sol:UploadTraits \
 *     --sig "uploadOneOfOnesRange(uint256,uint256)" 0 5 \
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

    function uploadNormalIndices(uint256[] calldata indices) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading Normal Traits (indices)");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("indices:", indices.length);
        console.log("");

        _uploadTraitsFromJsonIndices(rendererSvg, 0, indices);

        vm.stopBroadcast();
    }

    function uploadSpecialIndices(uint256[] calldata indices) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading Special Traits (indices)");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("indices:", indices.length);
        console.log("");

        _uploadTraitsFromJsonIndices(rendererSvg, 1, indices);

        vm.stopBroadcast();
    }

    function uploadOneOfOnesIndices(uint256[] calldata indices) external {
        _uploadOneOfOnesContentIndices(indices);
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

    function uploadOneOfOnes() external {
        _uploadOneOfOnesContentRange(0, type(uint256).max);
    }

    function uploadOneOfOnesRange(uint256 start, uint256 count) external {
        _uploadOneOfOnesContentRange(start, count);
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
        address[] pointers;
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
        string memory traitsPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory traitsJson = vm.readFile(traitsPath);

        string memory typeKey = charType == 0 ? "normal" : "special";
        TraitJson[] memory traits = abi.decode(
            vm.parseJson(traitsJson, string.concat(".", typeKey)),
            (TraitJson[])
        );

        console.log(string.concat(
            "Found ", vm.toString(traits.length), " ", typeKey,
            " traits; capping to first ", vm.toString(perCat), " per category"
        ));

        TraitsCtx memory ctx;
        ctx.renderer = renderer;
        ctx.charType = charType;
        ctx.traits = traits;
        ctx.pointers = _loadPointerArray(_readPointersJson(), typeKey, traits.length);
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

        _commitPointerUpdates(typeKey, _traitNames(ctx.traits), ctx.pointers, ctx.writePointerIndices, ctx.writePointerValues, ctx.writePointerCount);

        console.log("");
        console.log(string.concat(
            "Summary: uploaded ", vm.toString(ctx.uploadCount),
            " (", vm.toString(ctx.updateCount), " re-uploads), added ",
            vm.toString(ctx.addCount), ", skipped ", vm.toString(ctx.skipCount)
        ));
    }

    function _uploadTraitsFromJsonRange(address renderer, uint8 charType, uint256 start, uint256 count) internal {
        string memory traitsPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory traitsJson = vm.readFile(traitsPath);

        string memory typeKey = charType == 0 ? "normal" : "special";
        TraitJson[] memory traits = abi.decode(
            vm.parseJson(traitsJson, string.concat(".", typeKey)),
            (TraitJson[])
        );

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
        ctx.pointers = _loadPointerArray(_readPointersJson(), typeKey, traits.length);
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

        _commitPointerUpdates(typeKey, _traitNames(ctx.traits), ctx.pointers, ctx.writePointerIndices, ctx.writePointerValues, ctx.writePointerCount);

        console.log("");
        console.log(string.concat(
            "Summary: uploaded ", vm.toString(ctx.uploadCount),
            " (",  vm.toString(ctx.updateCount), " re-uploads via updateTraitPointer), added ",
            vm.toString(ctx.addCount), ", skipped ", vm.toString(ctx.skipCount)
        ));
    }

    function _uploadTraitsFromJsonIndices(
        address renderer,
        uint8 charType,
        uint256[] calldata indices
    ) internal {
        string memory traitsPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory traitsJson = vm.readFile(traitsPath);

        string memory typeKey = charType == 0 ? "normal" : "special";
        TraitJson[] memory traits = abi.decode(
            vm.parseJson(traitsJson, string.concat(".", typeKey)),
            (TraitJson[])
        );

        bool[] memory selected = new bool[](traits.length);
        uint256 maxIdx = 0;
        bool hasAny = false;
        for (uint256 k = 0; k < indices.length; k++) {
            uint256 idx = indices[k];
            require(idx < traits.length, "index out of range");
            if (!selected[idx]) {
                selected[idx] = true;
                if (!hasAny || idx > maxIdx) {
                    maxIdx = idx;
                    hasAny = true;
                }
            }
        }

        console.log(string.concat(
            "Found ", vm.toString(traits.length), " ", typeKey,
            " traits; processing ", vm.toString(indices.length), " indices"
        ));

        if (!hasAny) {
            console.log("No indices to process; nothing to do.");
            return;
        }

        TraitsCtx memory ctx;
        ctx.renderer = renderer;
        ctx.charType = charType;
        ctx.traits = traits;
        ctx.pointers = _loadPointerArray(_readPointersJson(), typeKey, traits.length);
        ctx.addCharacterTypes = new uint8[](indices.length);
        ctx.addCategories = new uint8[](indices.length);
        ctx.addNames = new string[](indices.length);
        ctx.addPointers = new address[](indices.length);
        ctx.writePointerIndices = new uint256[](indices.length);
        ctx.writePointerValues = new address[](indices.length);
        ctx.perCatCap = type(uint256).max;

        for (uint8 c = 0; c < 12; c++) {
            ctx.onchainCount[c] = IDealerRendererSVG(renderer).traitCount(charType, c);
        }

        for (uint256 i = 0; i <= maxIdx; i++) {
            if (selected[i]) {
                _processTraitEntry(ctx, i);
            } else {
                ctx.positionInCat[traits[i].category]++;
            }
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

        _commitPointerUpdates(typeKey, _traitNames(ctx.traits), ctx.pointers, ctx.writePointerIndices, ctx.writePointerValues, ctx.writePointerCount);

        console.log("");
        console.log(string.concat(
            "Summary: uploaded ", vm.toString(ctx.uploadCount),
            " (",  vm.toString(ctx.updateCount), " re-uploads via updateTraitPointer), added ",
            vm.toString(ctx.addCount), ", skipped ", vm.toString(ctx.skipCount)
        ));
    }

    function _processTraitEntry(TraitsCtx memory ctx, uint256 i) internal {
        TraitJson memory t = ctx.traits[i];
        address cached = ctx.pointers[i];
        ctx.positionInCat[t.category]++;
        uint256 pos = ctx.positionInCat[t.category];

        if (pos > ctx.perCatCap) return;

        if (pos <= ctx.onchainCount[t.category]) {
            if (cached != address(0)) {
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
        if (cached != address(0)) {
            pointer = cached;
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


    function _uploadOneOfOnesContentRange(uint256 start, uint256 count) internal {
        string memory traitsPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory traitsJson = vm.readFile(traitsPath);
        OneOfOneJson[] memory traits = abi.decode(
            vm.parseJson(traitsJson, ".oneofone"),
            (OneOfOneJson[])
        );
        address[] memory pointers = _loadPointerArray(_readPointersJson(), "oneofone", traits.length);

        if (start > traits.length) start = traits.length;
        uint256 end = start + count;
        if (end < start || end > traits.length) end = traits.length;

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading One-of-Ones from traits.json");
        console.log("==============================================");
        console.log(string.concat("Found ", vm.toString(traits.length), " one-of-ones"));
        console.log(string.concat("Processing [", vm.toString(start), ", ", vm.toString(end), ")"));
        console.log("");

        uint256 sliceLen = end - start;
        uint256[] memory uploadedIndices = new uint256[](sliceLen);
        address[] memory uploadedPointers = new address[](sliceLen);
        uint256 uploadCount = 0;
        uint256 skipCount = 0;

        for (uint256 i = start; i < end; i++) {
            OneOfOneJson memory t = traits[i];
            address cached = pointers[i];

            if (cached != address(0)) {
                console.log(string.concat("  Skip (cached): ", t.name, " -> ", vm.toString(cached)));
                skipCount++;
                continue;
            }

            string memory uniqueName = string.concat(
                "dealers-oneofone-", t.name, "-",
                vm.toString(block.timestamp), "-", vm.toString(i)
            );
            address[] memory chunkPointers = _writeChunkPointers(t.content);
            (address pointer,) = FILE_STORE.createFileFromPointers(uniqueName, chunkPointers);

            uploadedIndices[uploadCount] = i;
            uploadedPointers[uploadCount] = pointer;
            uploadCount++;

            console.log(string.concat(
                "  Uploaded: ", t.name, " (", vm.toString(chunkPointers.length),
                " chunks) -> ", vm.toString(pointer)
            ));
        }

        vm.stopBroadcast();

        _commitPointerUpdates("oneofone", _oneOfOneNames(traits), pointers, uploadedIndices, uploadedPointers, uploadCount);

        console.log("");
        console.log(string.concat("Summary: uploaded ", vm.toString(uploadCount), ", skipped ", vm.toString(skipCount)));
    }

    function _uploadOneOfOnesContentIndices(uint256[] calldata indices) internal {
        string memory traitsPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory traitsJson = vm.readFile(traitsPath);
        OneOfOneJson[] memory traits = abi.decode(
            vm.parseJson(traitsJson, ".oneofone"),
            (OneOfOneJson[])
        );
        address[] memory pointers = _loadPointerArray(_readPointersJson(), "oneofone", traits.length);

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading One-of-Ones (indices)");
        console.log("==============================================");
        console.log(string.concat("Found ", vm.toString(traits.length), " one-of-ones"));
        console.log(string.concat("Processing ", vm.toString(indices.length), " indices"));
        console.log("");

        uint256[] memory uploadedIndices = new uint256[](indices.length);
        address[] memory uploadedPointers = new address[](indices.length);
        uint256 uploadCount = 0;
        uint256 skipCount = 0;

        for (uint256 k = 0; k < indices.length; k++) {
            uint256 i = indices[k];
            require(i < traits.length, "index out of range");
            OneOfOneJson memory t = traits[i];
            address cached = pointers[i];

            if (cached != address(0)) {
                console.log(string.concat("  Skip (cached): ", t.name, " -> ", vm.toString(cached)));
                skipCount++;
                continue;
            }

            string memory uniqueName = string.concat(
                "dealers-oneofone-", t.name, "-",
                vm.toString(block.timestamp), "-", vm.toString(i)
            );
            address[] memory chunkPointers = _writeChunkPointers(t.content);
            (address pointer,) = FILE_STORE.createFileFromPointers(uniqueName, chunkPointers);

            uploadedIndices[uploadCount] = i;
            uploadedPointers[uploadCount] = pointer;
            uploadCount++;

            console.log(string.concat(
                "  Uploaded: ", t.name, " (", vm.toString(chunkPointers.length),
                " chunks) -> ", vm.toString(pointer)
            ));
        }

        vm.stopBroadcast();

        _commitPointerUpdates("oneofone", _oneOfOneNames(traits), pointers, uploadedIndices, uploadedPointers, uploadCount);

        console.log("");
        console.log(string.concat("Summary: uploaded ", vm.toString(uploadCount), ", skipped ", vm.toString(skipCount)));
    }

    function _uploadPlaceholderFromJson(address renderer) internal {
        string memory traitsPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory traitsJson = vm.readFile(traitsPath);

        bytes memory placeholderData = vm.parseJson(traitsJson, ".placeholder");
        if (placeholderData.length == 0) {
            console.log("No placeholder found in traits.json");
            return;
        }

        PlaceholderJson memory p = abi.decode(placeholderData, (PlaceholderJson));
        address cached = _loadPlaceholderPointer(_readPointersJson());

        address pointer;
        if (cached != address(0)) {
            pointer = cached;
            console.log("Placeholder already uploaded:", pointer);
        } else {
            string memory uniqueName = string.concat("dealers-placeholder-", vm.toString(block.timestamp));
            address[] memory chunkPointers = _writeChunkPointers(p.content);
            (pointer,) = FILE_STORE.createFileFromPointers(uniqueName, chunkPointers);
            console.log("Uploaded placeholder:", pointer);

            _writePointersFilePlaceholder(pointer);
        }

        IDealerRendererSVG(renderer).setPlaceholderSvg(pointer);
        console.log("Set placeholder on renderer");
    }

    function _commitPointerUpdates(
        string memory typeKey,
        string[] memory names,
        address[] memory pointers,
        uint256[] memory indices,
        address[] memory values,
        uint256 count
    ) internal {
        if (count == 0) return;
        for (uint256 i = 0; i < count; i++) {
            pointers[indices[i]] = values[i];
        }
        _persistPointerArray(typeKey, names, pointers);
    }

    function _persistPointerArray(
        string memory typeKey,
        string[] memory names,
        address[] memory pointers
    ) internal {
        string memory pointersJson = _readPointersJson();
        PointerEntry[] memory normal   = _loadPointerEntries(pointersJson, "normal");
        PointerEntry[] memory special  = _loadPointerEntries(pointersJson, "special");
        PointerEntry[] memory oneofone = _loadPointerEntries(pointersJson, "oneofone");
        address placeholder = _loadPlaceholderPointer(pointersJson);

        PointerEntry[] memory updated = _zipEntries(names, pointers);
        if (_eq(typeKey, "normal")) normal = updated;
        else if (_eq(typeKey, "special")) special = updated;
        else if (_eq(typeKey, "oneofone")) oneofone = updated;

        _writePointersFile(normal, special, oneofone, placeholder);
    }

    function _writePointersFilePlaceholder(address placeholder) internal {
        string memory pointersJson = _readPointersJson();
        PointerEntry[] memory normal   = _loadPointerEntries(pointersJson, "normal");
        PointerEntry[] memory special  = _loadPointerEntries(pointersJson, "special");
        PointerEntry[] memory oneofone = _loadPointerEntries(pointersJson, "oneofone");
        _writePointersFile(normal, special, oneofone, placeholder);
    }

    function _writePointersFile(
        PointerEntry[] memory normal,
        PointerEntry[] memory special,
        PointerEntry[] memory oneofone,
        address placeholder
    ) internal {
        string memory body = string.concat(
            '{\n  "normal": ',   _serializePointerEntries(_entryNames(normal),   _entryPointers(normal)),
            ',\n  "special": ',  _serializePointerEntries(_entryNames(special),  _entryPointers(special)),
            ',\n  "oneofone": ', _serializePointerEntries(_entryNames(oneofone), _entryPointers(oneofone)),
            ',\n  "placeholder": ', _serializeAddrOrNull(placeholder),
            '\n}\n'
        );
        string memory path = string.concat(vm.projectRoot(), "/", _getPointersPath());
        vm.writeFile(path, body);
    }

    function _zipEntries(string[] memory names, address[] memory pointers) internal pure returns (PointerEntry[] memory) {
        require(names.length == pointers.length, "Length mismatch");
        PointerEntry[] memory entries = new PointerEntry[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            entries[i] = PointerEntry({ name: names[i], pointer: pointers[i] });
        }
        return entries;
    }

    function _entryNames(PointerEntry[] memory entries) internal pure returns (string[] memory out) {
        out = new string[](entries.length);
        for (uint256 i = 0; i < entries.length; i++) out[i] = entries[i].name;
    }

    function _entryPointers(PointerEntry[] memory entries) internal pure returns (address[] memory out) {
        out = new address[](entries.length);
        for (uint256 i = 0; i < entries.length; i++) out[i] = entries[i].pointer;
    }

    function _traitNames(TraitJson[] memory traits) internal pure returns (string[] memory out) {
        out = new string[](traits.length);
        for (uint256 i = 0; i < traits.length; i++) out[i] = traits[i].name;
    }

    function _oneOfOneNames(OneOfOneJson[] memory traits) internal pure returns (string[] memory out) {
        out = new string[](traits.length);
        for (uint256 i = 0; i < traits.length; i++) out[i] = traits[i].name;
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
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
    uint16 probability;
}

struct OneOfOneJson {
    string content;
    string name;
}

struct PlaceholderJson {
    string content;
}

