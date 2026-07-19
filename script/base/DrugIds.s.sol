// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./DeployBase.s.sol";

/**
 * @title DrugIds - Canonical drug-id constants shared by config bases
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev The drug ids (registration order in SetupDrugs) are referenced by both the achievement
 *      ladder (ClaimsAchievements) and the area ladder (AreasConfig). Declaring them once here
 *      lets a script inherit both bases without a duplicate-identifier clash, and keeps the
 *      ids from drifting between the two.
 * @author Berny0x
 */
abstract contract DrugIds is DeployBase {
    uint256 constant GOODS = 1;
    uint256 constant CONTRABAND = 2;
    uint256 constant JEWELS = 3;
    uint256 constant WEED = 4;
    uint256 constant XTC = 5;
    uint256 constant COCAINE = 6;
    uint256 constant SHROOMS = 7;
    uint256 constant HEROIN = 8;
    uint256 constant OPIOIDS = 9;
    uint256 constant METH = 10;
    uint256 constant FENTANYL = 11;
    uint256 constant SLIVO = 12;
    uint256 constant KROKODIL = 13;
    uint256 constant SPEED = 14;
}
