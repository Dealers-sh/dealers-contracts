// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../../src/nft/IDealerRendererSVG.sol";
import "../base/DeployBase.s.sol";

/**
 * @title CheckAssignments - Read-only on-chain assignment tally
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Walks every pool index 1..MAX_SUPPLY on the live SVG renderer and tallies
 *      how many carry packed traits (normal + special) vs. a one-of-one record.
 *      Pure read — run WITHOUT --broadcast. Mappings keep no size, so the only
 *      way to verify coverage is to enumerate the keyspace.
 *
 * Usage:
 *   forge script script/upload/CheckAssignments.s.sol:CheckAssignments \
 *     --sig "check()" \
 *     --rpc-url https://api.mainnet.abs.xyz
 *
 * @author Berny0x
 */
contract CheckAssignments is DeployBase {
    uint256 constant MAX_SUPPLY = 10000;

    function check() external {
        _loadAddresses();
        _requireAddress(rendererSvg, "RENDERER_SVG");

        IDealerRendererSVG renderer = IDealerRendererSVG(rendererSvg);

        uint256 traitCount = 0;
        uint256 oneOfOneCount = 0;
        uint256 missing = 0;
        uint256 firstMissing = 0;

        for (uint256 poolIndex = 1; poolIndex <= MAX_SUPPLY; poolIndex++) {
            (,, bool isOneOfOne) = renderer.getOneOfOneInfo(poolIndex);
            if (isOneOfOne) {
                oneOfOneCount++;
            } else if (renderer.isTraitStored(poolIndex)) {
                traitCount++;
            } else {
                missing++;
                if (firstMissing == 0) firstMissing = poolIndex;
            }
        }

        console.log("==============================================");
        console.log("   On-chain assignment tally");
        console.log("==============================================");
        console.log("Renderer:        ", rendererSvg);
        console.log("Pool size:       ", MAX_SUPPLY);
        console.log("Normal+special:  ", traitCount);
        console.log("One-of-ones:     ", oneOfOneCount);
        console.log("Unassigned:      ", missing);
        if (missing > 0) console.log("First unassigned:", firstMissing);
    }
}
