// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title GrantReward - Owner grant of a Claims reward to a single dealer
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Thin owner-only wrapper over DealersClaims.grantReward for ad-hoc /
 *      demo grants. rewardType: 0=REPUTATION, 1=CASH, 2=DRUG (rewardId = drugId),
 *      3=ATTEMPTS. rewardId is ignored unless rewardType is DRUG. Runs as zkSync
 *      native (game contract).
 *
 * Usage:
 *   forge script script/setup/GrantReward.s.sol:GrantReward \
 *     --sig "grant(uint256,uint8,uint256,uint256)" 3 0 0 673 \
 *     --zksync --skip "RendererSVG" --skip "UploadTraits" \
 *     --rpc-url abstract --account dealersKeystore --broadcast
 *
 * @author Berny0x
 */
contract GrantReward is DeployBase {
    function grant(uint256 tokenId, uint8 rewardType, uint256 rewardId, uint256 amount) external {
        _loadAddresses();
        _requireAddress(claims, "CLAIMS");

        console.log("==============================================");
        console.log("   Grant reward");
        console.log("==============================================");
        console.log("Claims:    ", claims);
        console.log("tokenId:   ", tokenId);
        console.log("rewardType:", rewardType);
        console.log("rewardId:  ", rewardId);
        console.log("amount:    ", amount);

        vm.startBroadcast();
        (bool ok,) = claims.call(
            abi.encodeWithSignature("grantReward(uint256,uint8,uint256,uint256)", tokenId, rewardType, rewardId, amount)
        );
        require(ok, "grantReward failed");
        vm.stopBroadcast();

        console.log("Done.");
    }
}
