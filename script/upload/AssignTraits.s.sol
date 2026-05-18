// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../../src/nft/IDealerRendererSVG.sol";
import "../base/DeployBase.s.sol";

/**
 * @title AssignTraits - Reveal-time assignments on the renderer
 * @notice Two operations:
 *           - `assignTokenTraits` packs trait-combo bytes32 per token via batchSetTraits
 *           - `assignOneOfOnes` maps cached one-of-one pointers (from traits.json)
 *             to specific token IDs via batchSetOneOfOnes
 *
 *         Both are owner-only and intended to be run once, at reveal.
 *         Upload-side prep (FileStore + batchAddTraits) lives in UploadTraits.s.sol.
 * @dev Run as EVM mode (no --zksync flag).
 *
 * Usage:
 *   forge script script/upload/AssignTraits.s.sol:AssignTraits \
 *     --sig "assignTokenTraits(uint256[],bytes32[])" "[1,2,3]" "[0x..,0x..,0x..]" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 *   forge script script/upload/AssignTraits.s.sol:AssignTraits \
 *     --sig "assignOneOfOnes(uint256[])" "[1,42,99,...]" \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast
 *
 * @author Berny0x
 */
contract AssignTraits is DeployBase {
    string constant TRAITS_JSON_PATH = "script/data/traits.json";

    function assignTokenTraits(
        uint256[] calldata tokenIds,
        bytes32[] calldata packedTraits
    ) external {
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
        OneOfOneJson[] memory traits = abi.decode(
            vm.parseJson(traitsJson, ".oneofone"),
            (OneOfOneJson[])
        );

        address[] memory pointers = _loadPointerArray(_readPointersJson(), "oneofone", traits.length);

        require(
            tokenIds.length == traits.length,
            "Token IDs count must match one-of-ones count"
        );

        string[] memory names = new string[](traits.length);
        for (uint256 i = 0; i < traits.length; i++) {
            require(
                pointers[i] != address(0),
                string.concat("Pointer not uploaded for ", traits[i].name)
            );
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
            console.log(string.concat(
                "  ", traits[i].name, " -> token ", vm.toString(tokenIds[i])
            ));
        }

        vm.stopBroadcast();

        console.log("");
        console.log("Done.");
    }
}

struct OneOfOneJson {
    string content;
    string name;
}
