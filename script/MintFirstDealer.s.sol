// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

interface IDealersExeNFT {
    enum MintStatus { DISABLED, FAMILY, WHITELIST, PUBLIC }
    function mintPublic(address dest, uint256 count) external payable;
    function setMintStatus(MintStatus newStatus) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function currentTokenId() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function mintStatus() external view returns (MintStatus);
}

interface IDealerRendererSVG {
    function setPlaceholderSvg(address pointer) external;
    function placeholderSvgPointer() external view returns (address);
}

/**
 * @title MintFirstDealer
 * @notice Sets placeholder, mints token 1, initializes it, and transfers to recipient
 *
 * Required env vars:
 *   DEALERS_NFT      - DealersExeNFT address
 *   SVG_RENDERER     - DealerRendererSVG address
 *
 * Usage:
 *   forge script script/MintFirstDealer.s.sol:MintFirstDealer \
 *     --rpc-url https://api.testnet.abs.xyz \
 *     --account dealersKeystore \
 *     --broadcast --zksync
 */
contract MintFirstDealer is Script {
    address constant PLACEHOLDER_POINTER = 0x98199f64a630711f7A2E04aB25e08295FA175aAc;
    address constant RECIPIENT = 0x8a0C4e96a7456032F647780f0DA82f66C9070418;
    uint256 constant MINT_PRICE = 0.01 ether;

    function run() external {
        address nft = vm.envAddress("DEALERS_NFT");
        address svgRenderer = vm.envAddress("RENDERER_SVG");

        IDealersExeNFT nftContract = IDealersExeNFT(nft);
        IDealerRendererSVG renderer = IDealerRendererSVG(svgRenderer);

        vm.startBroadcast();

        if (renderer.placeholderSvgPointer() != PLACEHOLDER_POINTER) {
            renderer.setPlaceholderSvg(PLACEHOLDER_POINTER);
            console.log("Placeholder SVG pointer set:", PLACEHOLDER_POINTER);
        }

        if (nftContract.mintStatus() != IDealersExeNFT.MintStatus.PUBLIC) {
            nftContract.setMintStatus(IDealersExeNFT.MintStatus.PUBLIC);
            console.log("Mint status set to PUBLIC");
        }

        uint256 tokenId = nftContract.currentTokenId();
        nftContract.mintPublic{value: MINT_PRICE}(RECIPIENT, 1);
        console.log("Minted token:", tokenId, "to:", RECIPIENT);

        vm.stopBroadcast();
    }
}
