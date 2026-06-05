// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/DeployBase.s.sol";

interface INFTMinted {
    function currentTokenId() external view returns (uint256);
}

interface ICoreInitView {
    function isInitialized(uint256 tokenId) external view returns (bool);
}

/**
 * @title ReinitializeDealers - Replay initializeDealer for already-minted tokens after a Core redeploy
 * @dev Pre-launch / testnet recovery only. Re-initializing wipes any in-flight progress for the
 *      affected tokens on the new Core (resets to starter rep/cash/drugs at STARTING_AREA).
 *
 *      Flow:
 *        1. Authorize the broadcasting EOA on Core (if not already authorized).
 *        2. Loop tokenIds in [1, NFT.currentTokenId()), skip already-initialized ones,
 *           call Core.initializeDealer for the rest.
 *        3. Revoke the EOA authorization (only if it was added in step 1).
 *
 * Usage:
 *  source .env && forge script script/setup/ReinitializeDealers.s.sol:ReinitializeDealers \
 *       --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *       --skip "RendererSVG"
 */
contract ReinitializeDealers is DeployBase {
    function run() external {
        _loadAddresses();
        _requireAddress(core, "DEALERS_CORE");
        _requireAddress(nft, "DEALERS_NFT");

        uint256 next = INFTMinted(nft).currentTokenId();
        if (next <= 1) {
            console.log("No minted tokens (currentTokenId =", next, ") - nothing to do");
            return;
        }

        address broadcaster = msg.sender;
        IDealersCore c = IDealersCore(core);
        ICoreInitView coreView = ICoreInitView(core);

        console.log("Core:        ", core);
        console.log("NFT:         ", nft);
        console.log("Broadcaster: ", broadcaster);
        console.log("Token range: [1,", next - 1, "]");
        console.log("");

        vm.startBroadcast();

        bool preAuthorized = c.authorizedContracts(broadcaster);
        if (!preAuthorized) {
            c.authorizeContract(broadcaster, true);
            console.log("Authorized broadcaster on Core");
        }

        uint256 initialized;
        uint256 skipped;
        for (uint256 id = 1; id < next; ++id) {
            if (coreView.isInitialized(id)) {
                ++skipped;
                continue;
            }
            c.initializeDealer(id);
            ++initialized;
        }

        if (!preAuthorized) {
            c.authorizeContract(broadcaster, false);
            console.log("Revoked broadcaster authorization on Core");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("Initialized:           ", initialized);
        console.log("Skipped (already init):", skipped);
    }
}
