// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

interface INFTReserve {
    function reserve(uint256 nftAmount) external;
}

interface ICoreAdmin {
    function updateReputation(uint256 tokenId, int256 change) external;
    function forceMove(uint256 tokenId, uint8 newAreaId) external;
}

contract SetupTestnetDealers is DeployBase {
    uint8 constant AMSTERDAM = 2;
    uint8 constant COLOMBIA = 3;

    function run() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");
        _requireAddress(core, "DEALERS_CORE");

        console.log("NFT:", nft);
        console.log("Core:", core);

        vm.startBroadcast();

        INFTReserve(nft).reserve(50);
        console.log("Minted 50 dealers (token IDs 2-51)");

        ICoreAdmin coreContract = ICoreAdmin(core);

        // Distribute dealers across the new convex 2.2x ladder.
        // STARTING_REPUTATION is 25, so reputation deltas land at:
        //   delta +175  -> 200 rep  (Dealer)
        //   delta +475  -> 500 rep  (Soldier)
        //   delta +1175 -> 1,200 rep (Capo)
        // Area gates (Amsterdam 150, Colombia 250) are unchanged.

        for (uint256 id = 2; id <= 31; id++) {
            coreContract.updateReputation(id, 175);
        }
        console.log("Set rep delta +175 -> Dealer (200) for token IDs 2-31 (30 dealers in Manhattan)");

        for (uint256 id = 42; id <= 46; id++) {
            coreContract.updateReputation(id, 475);
            coreContract.forceMove(id, AMSTERDAM);
        }
        console.log("Set rep delta +475 -> Soldier (500) + Amsterdam for token IDs 42-46 (5 dealers)");

        for (uint256 id = 47; id <= 51; id++) {
            coreContract.updateReputation(id, 1175);
            coreContract.forceMove(id, COLOMBIA);
        }
        console.log("Set rep delta +1175 -> Capo (1,200) + Colombia for token IDs 47-51 (5 dealers)");

        vm.stopBroadcast();

        console.log("Token IDs 32-41 left at default rep 25 (Outsider) in Manhattan (10 dealers)");
        console.log("Setup complete: 50 dealers seeded across Outsider/Dealer/Soldier/Capo + 3 areas");
    }
}
