// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

interface INFTReserve {
    function reserve(uint256 nftAmount) external;
    function resolveMany(uint256[] calldata tokenIds) external;
    function currentTokenId() external view returns (uint256);
}

interface ICoreAdmin {
    function updateReputation(uint256 tokenId, int256 change) external;
    function forceMove(uint256 tokenId, uint8 newAreaId) external;
    function authorizeContract(address contractAddress, bool authorized) external;
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

        // updateReputation / forceMove are onlyAuthorized — temporarily authorize the broadcasting
        // owner EOA so this seed script can write dealer state directly, then revoke it below.
        coreContract.authorizeContract(tx.origin, true);

        // Distribute dealers across the new convex 2.2x ladder.
        // STARTING_REPUTATION is 25, so reputation deltas land at:
        //   delta +225  -> 250 rep   (Dealer)
        //   delta +575  -> 600 rep   (Soldier)
        //   delta +1475 -> 1,500 rep (Capo)
        // Area gates (Amsterdam 150, Colombia 500) are unchanged.

        for (uint256 id = 2; id <= 31; id++) {
            coreContract.updateReputation(id, 225);
        }
        console.log("Set rep delta +225 -> Dealer (250) for token IDs 2-31 (30 dealers in Manhattan)");

        for (uint256 id = 42; id <= 46; id++) {
            coreContract.updateReputation(id, 575);
            coreContract.forceMove(id, AMSTERDAM);
        }
        console.log("Set rep delta +575 -> Soldier (600) + Amsterdam for token IDs 42-46 (5 dealers)");

        for (uint256 id = 47; id <= 51; id++) {
            coreContract.updateReputation(id, 1475);
            coreContract.forceMove(id, COLOMBIA);
        }
        console.log("Set rep delta +1475 -> Capo (1,500) + Colombia for token IDs 47-51 (5 dealers)");

        coreContract.authorizeContract(tx.origin, false);

        vm.stopBroadcast();

        console.log("Token IDs 32-41 left at default rep 25 (Outsider) in Manhattan (10 dealers)");
        console.log("Setup complete: 50 dealers seeded across Outsider/Dealer/Soldier/Capo + 3 areas");
        console.log("");
        console.log("Next: wait a few blocks, then reveal their art with --sig \"reveal()\"");
    }

    /**
     * @notice Reveal the artwork of every minted dealer via resolveMany.
     * @dev Run a few blocks AFTER run() — resolve requires block.number > revealBlock
     *      (REVEAL_DELAY = 2), so a token cannot be revealed in the same block it was minted.
     *      resolveMany skips any token that is already revealed or not yet revealable, so this is
     *      idempotent: re-run it if some were still too early when called.
     */
    function reveal() external {
        _loadAddresses();
        _requireAddress(nft, "DEALERS_NFT");

        uint256 next = INFTReserve(nft).currentTokenId();
        if (next <= 1) {
            console.log("No dealers minted yet - nothing to reveal");
            return;
        }

        uint256 count = next - 1; // token IDs 1 .. next-1
        uint256[] memory ids = new uint256[](count);
        for (uint256 i; i < count; i++) {
            ids[i] = i + 1;
        }

        vm.startBroadcast();
        INFTReserve(nft).resolveMany(ids);
        vm.stopBroadcast();

        console.log("resolveMany attempted on token IDs 1 ..", count);
        console.log("Re-run reveal() if any were skipped (still within REVEAL_DELAY when called).");
    }
}
