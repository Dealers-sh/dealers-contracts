// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../base/Wiring.s.sol";

/**
 * @title DeployNFT - Redeploy the dealer collection and re-wire every edge that touches it
 * @dev Constructor deps: ROYALTY_RECEIVER (network-prefixed env).
 *      Wires (idempotent): Core.setNFTContract + auth, NFT -> Core + renderers, and the nft ref on
 *      Boosts/PVE/PVP/Claims/Actions/ChatFactory, plus Heists/BankHeist ref syncs.
 *
 *      STATE ABANDONED on redeploy: THE ENTIRE COLLECTION — ownership, token seeds, tokenToPool
 *      reveal assignments, mint progress. Dealer game state in Core is keyed by tokenId and would
 *      attach to whoever re-mints those ids. On mainnet this is unrecoverable; last resort only.
 *
 *      Mainnet requires CONFIRM=DealersNFT in the environment.
 *
 * Usage:
 *   source .env && forge script script/deploy/DeployNFT.s.sol:DeployNFT \
 *     --rpc-url abstract-testnet --account dealersKeystore --broadcast --zksync \
 *     --skip "RendererSVG" --skip "UploadTraits"
 */
contract DeployNFT is WiringBase {
    function run() external {
        _loadAddresses();
        _requireAddress(royaltyReceiver, "ROYALTY_RECEIVER");
        _guardMainnet("DealersNFT");

        console.log("WARNING: a new NFT contract abandons the whole collection (owners, reveals, mint state).");
        console.log("");

        vm.startBroadcast();
        nft = _zkCreate(abi.encodePacked(vm.getCode("DealersNFT.sol:DealersNFT"), abi.encode(royaltyReceiver)));
        console.log("DealersNFT deployed:", nft);
        console.log("  Royalty Receiver:", royaltyReceiver);
        _wireNFT();
        vm.stopBroadcast();

        _saveAddresses();

        console.log("Follow-ups:");
        console.log("  1. RendererSVG.setDealersNFT(nft) via cast (EVM mode - printed above)");
        console.log("  2. Mint/reserve + reveal flow per DEPLOY.md (pool must be assigned before setMintOpen)");
        console.log("  3. Rebuild + re-upload app gzip (addresses are embedded)");
    }
}
