// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

/**
 * @title SetupClaims - Configure default reputation milestone achievements
 * @dev Usage:
 *   source .env && forge script script/setup/SetupClaims.s.sol:SetupClaims \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "DealerRenderer" --skip "DeployRenderers"
 *
 *   Requires DEALERS_CLAIMS env var.
 */
contract SetupClaims is DeployBase {
    uint8 constant CONDITION_REPUTATION = 8;
    uint8 constant REWARD_CASH = 1;
    uint8 constant REWARD_DRUG = 2;
    uint256 constant DRUG_COCAINE = 3;

    function run() external {
        _loadAddresses();
        _requireAddress(claims, "DEALERS_CLAIMS");

        IClaimsContract claimsContract = IClaimsContract(claims);

        console.log("Claims address:", claims);
        console.log("Current achievement count:", claimsContract.achievementCount());

        vm.startBroadcast();

        // Achievement 0: Reach 50 rep -> 50 $CASH
        claimsContract.setAchievement(0, IClaimsContract.Achievement({
            conditionType: CONDITION_REPUTATION,
            conditionValue: 0,
            threshold: 50,
            rewardType: REWARD_CASH,
            rewardId: 0,
            rewardAmount: 50,
            active: true
        }));

        // Achievement 1: Reach 100 rep -> 100 $CASH
        claimsContract.setAchievement(1, IClaimsContract.Achievement({
            conditionType: CONDITION_REPUTATION,
            conditionValue: 0,
            threshold: 100,
            rewardType: REWARD_CASH,
            rewardId: 0,
            rewardAmount: 100,
            active: true
        }));

        // Achievement 2: Reach 150 rep -> 150 $CASH
        claimsContract.setAchievement(2, IClaimsContract.Achievement({
            conditionType: CONDITION_REPUTATION,
            conditionValue: 0,
            threshold: 150,
            rewardType: REWARD_CASH,
            rewardId: 0,
            rewardAmount: 150,
            active: true
        }));

        // Achievement 3: Reach 150 rep -> 1 COKE
        claimsContract.setAchievement(3, IClaimsContract.Achievement({
            conditionType: CONDITION_REPUTATION,
            conditionValue: 0,
            threshold: 150,
            rewardType: REWARD_DRUG,
            rewardId: DRUG_COCAINE,
            rewardAmount: 1,
            active: true
        }));

        vm.stopBroadcast();

        console.log("4 achievements configured:");
        console.log("  #0: Rep >= 50  -> 50 $CASH");
        console.log("  #1: Rep >= 100 -> 100 $CASH");
        console.log("  #2: Rep >= 150 -> 150 $CASH");
        console.log("  #3: Rep >= 150 -> 1 COKE");
    }
}
