// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/nft/IDealerRendererSVG.sol";
import "../../src/nft/IFileStore.sol";
import "../base/DeployBase.s.sol";

/**
 * @title UploadOneOfOnes - Upload Complete SVG Art for One-of-One Characters
 * @notice Uploads one-of-one SVG files to FileStore and optionally assigns them to tokens
 * @dev This script is designed for EVM mode deployment (no --zksync flag).
 *      Loads renderer address from testnet.json via DeployBase.
 *
 * ============================================================================
 *                           ONE-OF-ONE WORKFLOW
 * ============================================================================
 *
 * 1. Upload SVGs to FileStore (can be done anytime):
 *    - Reads from traits/oneofone/ folder
 *    - Filename = character name (e.g., "Satoshi.svg" → name="Satoshi")
 *    - Saves pointers to script/data/{network}/pointers-oneofone.json
 *
 * 2. Assign to tokens:
 *    - Token IDs are determined off-chain (no on-chain distribution)
 *    - Use assignOneOfOne() to link a character to a specific token ID
 *
 * ============================================================================
 *                           IMPORTANT NOTES
 * ============================================================================
 *
 * - Token IDs for one-of-ones are determined off-chain
 * - You can upload fewer SVGs than total one-of-one slots
 * - Tokens without assigned SVG will show placeholder or revert
 * - Upload step is separate from assignment to allow flexibility
 *
 * ============================================================================
 *                              USAGE
 * ============================================================================
 *
 * Upload all one-of-one SVGs to FileStore:
 *   forge script script/upload/UploadOneOfOnes.s.sol:UploadOneOfOnes \
 *     --sig "uploadOneOfOnes()" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * Assign a specific one-of-one to a token:
 *   forge script script/upload/UploadOneOfOnes.s.sol:UploadOneOfOnes \
 *     --sig "assignOneOfOne(uint256,string)" <TOKEN_ID> "Satoshi" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * Assign all uploaded one-of-ones to explicit token IDs:
 *   forge script script/upload/UploadOneOfOnes.s.sol:UploadOneOfOnes \
 *     --sig "assignAllOneOfOnes(uint256[])" "[1,42,100,...]" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * @author Berny0x
 */
contract UploadOneOfOnes is DeployBase {
    IFileStore constant FILE_STORE = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);

    string constant ONEOFONE_PATH = "../traits/oneofone/";

    function uploadOneOfOnes() external {
        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Uploading One-of-One SVGs to FileStore");
        console.log("==============================================");
        console.log("");

        string memory folderPath = string.concat(vm.projectRoot(), "/", ONEOFONE_PATH);
        string memory pointerJsonPath = _getPointerJsonPath();

        string memory existingJson = _loadExistingPointers(pointerJsonPath);

        string[] memory files = _getTraitFiles(folderPath);
        console.log(string.concat("Found ", vm.toString(files.length), " one-of-one files"));
        console.log("");

        uint256 uploadCount = 0;
        uint256 skipCount = 0;

        for (uint256 i = 0; i < files.length; i++) {
            string memory filename = files[i];
            string memory characterName = _extractCharacterName(filename);

            address existingPointer = _getPointerFromJson(existingJson, characterName);

            if (existingPointer != address(0)) {
                console.log(string.concat("  Skipping (cached): ", characterName, " -> ", vm.toString(existingPointer)));
                skipCount++;
            } else {
                string memory filePath = string.concat(folderPath, "/", filename);
                string memory svgContent = vm.readFile(filePath);

                string memory uniqueName = _generateUniqueName(characterName);
                (address pointer,) = FILE_STORE.createFile(uniqueName, svgContent);

                _savePointerToJson(pointerJsonPath, characterName, pointer);
                console.log(string.concat("  Uploaded: ", characterName, " -> ", vm.toString(pointer)));
                uploadCount++;
            }
        }

        console.log("");
        console.log("==============================================");
        console.log("   Upload Complete");
        console.log("==============================================");
        console.log("Uploaded:", uploadCount);
        console.log("Skipped:", skipCount);
        console.log("Pointers saved to:", pointerJsonPath);

        vm.stopBroadcast();
    }

    function assignOneOfOne(
        uint256 tokenId,
        string calldata characterName
    ) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Assigning One-of-One to Token");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log("Token ID:", tokenId);
        console.log("Character:", characterName);
        console.log("");

        string memory pointerJsonPath = _getPointerJsonPath();
        string memory existingJson = _loadExistingPointers(pointerJsonPath);

        address pointer = _getPointerFromJson(existingJson, characterName);
        require(pointer != address(0), "Character not found in pointers JSON. Upload first.");

        console.log("Found pointer:", pointer);

        IDealerRendererSVG(rendererSvg).setOneOfOne(tokenId, characterName, pointer);

        console.log(string.concat("Successfully assigned ", characterName, " to token ", vm.toString(tokenId)));

        vm.stopBroadcast();
    }

    function assignAllOneOfOnes(uint256[] calldata oneOfOneTokenIds) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        vm.startBroadcast();
        console.log("==============================================");
        console.log("   Assigning All One-of-Ones to Tokens");
        console.log("==============================================");
        console.log("Renderer:", rendererSvg);
        console.log(string.concat("Token IDs provided: ", vm.toString(oneOfOneTokenIds.length)));
        console.log("");

        IDealerRendererSVG rendererContract = IDealerRendererSVG(rendererSvg);

        string memory pointerJsonPath = _getPointerJsonPath();
        string memory existingJson = _loadExistingPointers(pointerJsonPath);

        string memory folderPath = string.concat(vm.projectRoot(), "/", ONEOFONE_PATH);
        string[] memory files = _getTraitFiles(folderPath);

        console.log(string.concat("Found ", vm.toString(files.length), " one-of-one SVG files"));
        console.log("");

        uint256 assignedCount = 0;
        uint256 maxAssignments = files.length < oneOfOneTokenIds.length ? files.length : oneOfOneTokenIds.length;

        uint256[] memory tokenIds = new uint256[](maxAssignments);
        string[] memory names = new string[](maxAssignments);
        address[] memory pointers = new address[](maxAssignments);

        for (uint256 i = 0; i < maxAssignments; i++) {
            string memory characterName = _extractCharacterName(files[i]);
            address pointer = _getPointerFromJson(existingJson, characterName);

            if (pointer == address(0)) {
                console.log(string.concat("  Warning: No pointer for ", characterName, " - skipping"));
                continue;
            }

            (, , bool exists) = rendererContract.getOneOfOneInfo(oneOfOneTokenIds[i]);
            if (exists) {
                console.log(string.concat("  Token ", vm.toString(oneOfOneTokenIds[i]), " already assigned - skipping"));
                continue;
            }

            tokenIds[assignedCount] = oneOfOneTokenIds[i];
            names[assignedCount] = characterName;
            pointers[assignedCount] = pointer;

            console.log(string.concat("  Preparing: ", characterName, " -> token ", vm.toString(oneOfOneTokenIds[i])));
            assignedCount++;
        }

        if (assignedCount > 0) {
            uint256[] memory finalTokenIds = new uint256[](assignedCount);
            string[] memory finalNames = new string[](assignedCount);
            address[] memory finalPointers = new address[](assignedCount);

            for (uint256 i = 0; i < assignedCount; i++) {
                finalTokenIds[i] = tokenIds[i];
                finalNames[i] = names[i];
                finalPointers[i] = pointers[i];
            }

            rendererContract.batchSetOneOfOnes(finalTokenIds, finalNames, finalPointers);
            console.log("");
            console.log(string.concat("Batch assigned ", vm.toString(assignedCount), " one-of-ones"));
        }

        console.log("");
        console.log("==============================================");
        console.log("   Assignment Complete");
        console.log("==============================================");
        console.log("Total assigned:", assignedCount);

        vm.stopBroadcast();
    }

    function listOneOfOneTokens(uint256[] calldata tokenIds) external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        console.log("==============================================");
        console.log("   One-of-One Token IDs");
        console.log("==============================================");

        IDealerRendererSVG rendererContract = IDealerRendererSVG(rendererSvg);

        console.log(string.concat("Checking ", vm.toString(tokenIds.length), " token IDs:"));
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (string memory name, address pointer, bool exists) = rendererContract.getOneOfOneInfo(tokenIds[i]);
            if (exists) {
                console.log(string.concat("  Token ", vm.toString(tokenIds[i]), ": ", name, " -> ", vm.toString(pointer)));
            } else {
                console.log(string.concat("  Token ", vm.toString(tokenIds[i]), ": (unassigned)"));
            }
        }
    }

    function _getPointerJsonPath() internal view returns (string memory) {
        string memory networkFolder = _getNetworkFolder();
        return string.concat(vm.projectRoot(), "/script/data/", networkFolder, "/pointers-oneofone.json");
    }

    function _getNetworkFolder() internal view returns (string memory) {
        if (block.chainid == 11124) return "testnet";
        if (block.chainid == 2741) return "mainnet";
        return "local";
    }

    function _loadExistingPointers(string memory jsonPath) internal view returns (string memory) {
        try vm.readFile(jsonPath) returns (string memory content) {
            return content;
        } catch {
            return "{}";
        }
    }

    function _getPointerFromJson(string memory json, string memory characterName) internal pure returns (address) {
        if (bytes(json).length <= 2) return address(0);

        bytes memory jsonBytes = bytes(json);
        bytes memory nameBytes = bytes(characterName);

        uint256 nameStart = _findInBytes(jsonBytes, nameBytes, 0);
        if (nameStart == type(uint256).max) return address(0);

        uint256 colonPos = _findInBytes(jsonBytes, bytes(":"), nameStart);
        if (colonPos == type(uint256).max) return address(0);

        uint256 quoteStart = _findInBytes(jsonBytes, bytes("\"0x"), colonPos);
        if (quoteStart == type(uint256).max) return address(0);

        uint256 addrStart = quoteStart + 1;
        bytes memory addrBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addrBytes[i] = jsonBytes[addrStart + i];
        }

        return _parseAddress(string(addrBytes));
    }

    function _findInBytes(bytes memory haystack, bytes memory needle, uint256 start) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) return type(uint256).max;

        for (uint256 i = start; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }

    function _parseAddress(string memory addrStr) internal pure returns (address) {
        bytes memory b = bytes(addrStr);
        if (b.length != 42) return address(0);

        uint160 result = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint8 digit = _hexCharToUint(uint8(b[i]));
            if (digit == 255) return address(0);
            result = result * 16 + digit;
        }
        return address(result);
    }

    function _hexCharToUint(uint8 c) internal pure returns (uint8) {
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 65 && c <= 70) return c - 55;
        if (c >= 97 && c <= 102) return c - 87;
        return 255;
    }

    function _savePointerToJson(
        string memory jsonPath,
        string memory characterName,
        address pointer
    ) internal {
        string memory existingJson = _loadExistingPointers(jsonPath);
        string memory newJson = _updateJson(existingJson, characterName, pointer);
        vm.writeFile(jsonPath, newJson);
    }

    function _updateJson(
        string memory existingJson,
        string memory characterName,
        address pointer
    ) internal pure returns (string memory) {
        string memory pointerStr = vm.toString(pointer);

        if (bytes(existingJson).length <= 2 || _isEmptyJson(existingJson)) {
            return string.concat('{\n  "', characterName, '": "', pointerStr, '"\n}');
        }

        bytes memory jsonBytes = bytes(existingJson);
        uint256 lastBrace = jsonBytes.length - 1;
        while (lastBrace > 0 && jsonBytes[lastBrace] != "}") lastBrace--;

        bytes memory prefix = new bytes(lastBrace);
        for (uint256 i = 0; i < lastBrace; i++) {
            prefix[i] = jsonBytes[i];
        }

        return string.concat(string(prefix), ',\n  "', characterName, '": "', pointerStr, '"\n}');
    }

    function _isEmptyJson(string memory json) internal pure returns (bool) {
        bytes memory b = bytes(json);
        uint256 nonWhitespace = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] != " " && b[i] != "\n" && b[i] != "\t" && b[i] != "\r") {
                nonWhitespace++;
            }
        }
        return nonWhitespace <= 2;
    }

    function _getTraitFiles(string memory folderPath) internal returns (string[] memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "ls";
        inputs[1] = "-1";
        inputs[2] = folderPath;

        try vm.ffi(inputs) returns (bytes memory result) {
            return _splitLines(string(result));
        } catch {
            return new string[](0);
        }
    }

    function _splitLines(string memory str) internal pure returns (string[] memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) return new string[](0);

        uint256 lineCount = 1;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == "\n" && i < strBytes.length - 1) lineCount++;
        }

        string[] memory lines = new string[](lineCount);
        uint256 lineIndex = 0;
        uint256 lineStart = 0;

        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == "\n") {
                uint256 lineLen = i - lineStart;
                if (lineLen > 0) {
                    bytes memory lineBytes = new bytes(lineLen);
                    for (uint256 j = 0; j < lineLen; j++) {
                        lineBytes[j] = strBytes[lineStart + j];
                    }
                    string memory line = string(lineBytes);
                    if (_endsWith(line, ".svg")) {
                        lines[lineIndex] = line;
                        lineIndex++;
                    }
                }
                lineStart = i + 1;
            }
        }

        string[] memory result = new string[](lineIndex);
        for (uint256 i = 0; i < lineIndex; i++) {
            result[i] = lines[i];
        }
        return result;
    }

    function _endsWith(string memory str, string memory suffix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);
        if (strBytes.length < suffixBytes.length) return false;

        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[strBytes.length - suffixBytes.length + i] != suffixBytes[i]) {
                return false;
            }
        }
        return true;
    }

    function _extractCharacterName(string memory filename) internal pure returns (string memory) {
        bytes memory fnBytes = bytes(filename);
        uint256 dotPos = fnBytes.length - 4;

        bytes memory nameBytes = new bytes(dotPos);
        for (uint256 i = 0; i < dotPos; i++) {
            nameBytes[i] = fnBytes[i];
        }
        return string(nameBytes);
    }

    function _generateUniqueName(string memory characterName) internal view returns (string memory) {
        return string.concat("dealers-oneofone-", characterName, "-", vm.toString(block.timestamp));
    }
}
