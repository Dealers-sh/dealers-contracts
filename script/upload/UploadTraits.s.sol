// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
 * @author HeadmasterBerny
 */
contract UploadTraits is DeployBase {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);

    string constant TRAITS_JSON_PATH = "script/data/traits.json";

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

        _uploadTraitsFromJson(rendererSvg, 0);

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

        _uploadTraitsFromJson(rendererSvg, 1);

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


    function _uploadTraitsFromJson(address renderer, uint8 charType) internal {
        string memory jsonPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory json = vm.readFile(jsonPath);

        string memory typeKey = charType == 0 ? "normal" : "special";
        bytes memory traitsArray = vm.parseJson(json, string.concat(".", typeKey));

        TraitJson[] memory traits = abi.decode(traitsArray, (TraitJson[]));

        console.log(string.concat("Found ", vm.toString(traits.length), " ", typeKey, " traits"));

        uint256 uploadCount = 0;
        uint256 skipCount = 0;
        uint256 registerCount = 0;

        uint8[] memory characterTypes = new uint8[](traits.length);
        uint8[] memory categories = new uint8[](traits.length);
        string[] memory names = new string[](traits.length);
        uint16[] memory probabilities = new uint16[](traits.length);
        address[] memory pointers = new address[](traits.length);

        for (uint256 i = 0; i < traits.length; i++) {
            TraitJson memory t = traits[i];

            address pointer;
            if (t.pointer != address(0)) {
                pointer = t.pointer;
                skipCount++;
                console.log(string.concat("  Skip (cached): ", t.name));
            } else {
                string memory uniqueName = _generateUniqueName(charType, t.category, t.name);
                (pointer,) = FILE_STORE.createFile(uniqueName, t.content);
                uploadCount++;
                console.log(string.concat("  Uploaded: ", t.name, " -> ", vm.toString(pointer)));

                _updatePointerInJson(jsonPath, typeKey, i, pointer);
            }

            characterTypes[i] = charType;
            categories[i] = t.category;
            names[i] = t.name;
            probabilities[i] = t.probability;
            pointers[i] = pointer;
            registerCount++;
        }

        if (registerCount > 0) {
            IDealerRendererSVG(renderer).batchAddTraits(
                characterTypes,
                categories,
                names,
                probabilities,
                pointers
            );
            console.log(string.concat("Registered ", vm.toString(registerCount), " traits with renderer"));
        }

        console.log("");
        console.log(string.concat("Summary: uploaded ", vm.toString(uploadCount), ", skipped ", vm.toString(skipCount)));
    }

    function _uploadOneOfOnesFromJson(address renderer, uint256[] calldata tokenIds) internal {
        string memory jsonPath = string.concat(vm.projectRoot(), "/", TRAITS_JSON_PATH);
        string memory json = vm.readFile(jsonPath);

        bytes memory traitsArray = vm.parseJson(json, ".oneofone");
        OneOfOneJson[] memory traits = abi.decode(traitsArray, (OneOfOneJson[]));

        console.log(string.concat("Found ", vm.toString(traits.length), " one-of-ones"));

        require(tokenIds.length == traits.length, "Token IDs count must match one-of-ones count");

        uint256 uploadCount = 0;
        uint256 skipCount = 0;

        uint256[] memory tids = new uint256[](traits.length);
        string[] memory names = new string[](traits.length);
        address[] memory pointers = new address[](traits.length);

        for (uint256 i = 0; i < traits.length; i++) {
            OneOfOneJson memory t = traits[i];

            address pointer;
            if (t.pointer != address(0)) {
                pointer = t.pointer;
                skipCount++;
                console.log(string.concat("  Skip (cached): ", t.name));
            } else {
                string memory uniqueName = string.concat("dealers-oneofone-", t.name, "-", vm.toString(block.timestamp));
                (pointer,) = FILE_STORE.createFile(uniqueName, t.content);
                uploadCount++;
                console.log(string.concat("  Uploaded: ", t.name, " -> ", vm.toString(pointer)));

                _updateOneOfOnePointerInJson(jsonPath, i, pointer);
            }

            tids[i] = tokenIds[i];
            names[i] = t.name;
            pointers[i] = pointer;
        }

        if (traits.length > 0) {
            IDealerRendererSVG(renderer).batchSetOneOfOnes(tids, names, pointers);
            console.log(string.concat("Registered ", vm.toString(traits.length), " one-of-ones with renderer"));
        }

        console.log("");
        console.log(string.concat("Summary: uploaded ", vm.toString(uploadCount), ", skipped ", vm.toString(skipCount)));
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
            (pointer,) = FILE_STORE.createFile(uniqueName, p.content);
            console.log("Uploaded placeholder:", pointer);

            _updatePlaceholderPointerInJson(jsonPath, pointer);
        }

        IDealerRendererSVG(renderer).setPlaceholderSvg(pointer);
        console.log("Set placeholder on renderer");
    }

    function _updatePlaceholderPointerInJson(string memory jsonPath, address pointer) internal {
        string memory json = vm.readFile(jsonPath);

        string memory searchPattern = '"placeholder"';
        uint256 typeStart = _findInString(json, searchPattern, 0);
        if (typeStart == type(uint256).max) return;

        uint256 objStart = _findInString(json, "{", typeStart);
        if (objStart == type(uint256).max) return;

        uint256 pointerKeyStart = _findInString(json, '"pointer"', objStart);
        if (pointerKeyStart == type(uint256).max) return;

        uint256 colonPos = _findInString(json, ":", pointerKeyStart);
        if (colonPos == type(uint256).max) return;

        uint256 valueStart = colonPos + 1;
        while (valueStart < bytes(json).length && (bytes(json)[valueStart] == " " || bytes(json)[valueStart] == "\n")) {
            valueStart++;
        }

        uint256 valueEnd = valueStart;
        if (bytes(json)[valueStart] == "n") {
            valueEnd = valueStart + 4;
        } else if (bytes(json)[valueStart] == '"') {
            valueEnd = _findInString(json, '"', valueStart + 1) + 1;
        }

        string memory newValue = string.concat('"', vm.toString(pointer), '"');
        string memory newJson = string.concat(
            _substring(json, 0, valueStart),
            newValue,
            _substring(json, valueEnd, bytes(json).length)
        );

        vm.writeFile(jsonPath, newJson);
    }


    function _updatePointerInJson(
        string memory jsonPath,
        string memory typeKey,
        uint256 index,
        address pointer
    ) internal {
        string memory json = vm.readFile(jsonPath);

        string memory searchPattern = string.concat('"', typeKey, '"');
        uint256 typeStart = _findInString(json, searchPattern, 0);
        if (typeStart == type(uint256).max) return;

        uint256 arrayStart = _findInString(json, "[", typeStart);
        if (arrayStart == type(uint256).max) return;

        uint256 currentIndex = 0;
        uint256 pos = arrayStart + 1;

        while (currentIndex < index) {
            pos = _findInString(json, "{", pos);
            if (pos == type(uint256).max) return;
            pos = _findMatchingBrace(json, pos);
            if (pos == type(uint256).max) return;
            pos++;
            currentIndex++;
        }

        uint256 objStart = _findInString(json, "{", pos);
        if (objStart == type(uint256).max) return;

        uint256 pointerKeyStart = _findInString(json, '"pointer"', objStart);
        if (pointerKeyStart == type(uint256).max) return;

        uint256 colonPos = _findInString(json, ":", pointerKeyStart);
        if (colonPos == type(uint256).max) return;

        uint256 valueStart = colonPos + 1;
        while (valueStart < bytes(json).length && (bytes(json)[valueStart] == " " || bytes(json)[valueStart] == "\n")) {
            valueStart++;
        }

        uint256 valueEnd = valueStart;
        if (bytes(json)[valueStart] == "n") {
            valueEnd = valueStart + 4;
        } else if (bytes(json)[valueStart] == '"') {
            valueEnd = _findInString(json, '"', valueStart + 1) + 1;
        }

        string memory newValue = string.concat('"', vm.toString(pointer), '"');
        string memory newJson = string.concat(
            _substring(json, 0, valueStart),
            newValue,
            _substring(json, valueEnd, bytes(json).length)
        );

        vm.writeFile(jsonPath, newJson);
    }

    function _updateOneOfOnePointerInJson(
        string memory jsonPath,
        uint256 index,
        address pointer
    ) internal {
        _updatePointerInJson(jsonPath, "oneofone", index, pointer);
    }

    function _generateUniqueName(
        uint8 charType,
        uint8 category,
        string memory traitName
    ) internal view returns (string memory) {
        string memory prefix = charType == 0 ? "dealers-normal" : "dealers-special";
        string memory categoryName = categoryNames[category];
        return string.concat(prefix, "-", categoryName, "-", traitName, "-", vm.toString(block.timestamp));
    }

    function _findInString(string memory haystack, string memory needle, uint256 start) internal pure returns (uint256) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);

        if (n.length == 0 || h.length < n.length + start) return type(uint256).max;

        for (uint256 i = start; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }

    function _findMatchingBrace(string memory json, uint256 openPos) internal pure returns (uint256) {
        bytes memory b = bytes(json);
        uint256 depth = 1;
        for (uint256 i = openPos + 1; i < b.length; i++) {
            if (b[i] == "{") depth++;
            else if (b[i] == "}") {
                depth--;
                if (depth == 0) return i;
            }
        }
        return type(uint256).max;
    }

    function _substring(string memory str, uint256 start, uint256 end) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = b[i];
        }
        return string(result);
    }
}

struct TraitJson {
    uint8 category;
    string content;
    string name;
    address pointer;
    uint16 probability;
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

