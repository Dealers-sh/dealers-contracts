// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  (banner omitted for brevity)
*/

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";

interface IDealersExeCore {
    function initializeDealer(uint256 tokenId) external;
    function getDealerData(uint256 tokenId) external view returns (
        uint8 currentArea,
        uint256 reputation,           // ← match your Core (uint256), prevents decode bugs
        bool pvpEnabled,
        uint8 dailyPlaysRemaining,
        uint32 lastPlayTimestamp,
        bool isInitialized
    );
    function getReputationTitle(uint256 reputation) external view returns (string memory);
}

interface IDealersExeRendererSVG {
    function getSVG(uint256 tokenId, uint256 seed) external view returns (string memory);
    function getTraitsMetadata(uint256 seed) external view returns (string memory);
    function getTraitsMetadataForToken(uint256 tokenId, uint256 seed) external view returns (string memory);
    function getCharacterType(uint256 tokenId) external view returns (uint8);
    function initializeDistribution(uint256 seed) external;
    function distributionInitialized() external view returns (bool);
}

interface IDealersExeRendererHTML {
    function getHTML(string memory svg) external view returns (string memory);
}

contract DealersExeNFT is ERC721Enumerable, ReentrancyGuard, Ownable, IERC2981 {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using LibString for uint256;
    using LibString for uint8;

    // -------- Constants
    uint256 public constant MAX_SUPPLY = 8888;
    uint256 public constant RESERVE_SUPPLY = 200;
    uint256 public constant ROYALTY_PERCENTAGE = 500; // 5%
    uint256 public constant MINT_PRICE = 0.01 ether;
    uint256 public constant MAX_PER_WALLET = 10;

    // -------- Storage
    enum MintStatus { DISABLED, FAMILY, WHITELIST, PUBLIC }
    MintStatus public mintStatus = MintStatus.DISABLED;

    uint32  public totalMinted;          // fits in 32 bits
    uint256 public currentTokenId = 1;

    address public dealersExeCore;
    address public signerAddress;
    address public royaltyReceiver;

    mapping(address => uint256) private mintCount;

    // cheaper than mapping(bytes => bool); we hash once and track 32 bytes
    mapping(bytes32 => bool) private usedSignaturesHash;

    mapping(uint256 => uint256) public tokenSeeds;

    IDealersExeRendererSVG  public contractRendererSVG;
    IDealersExeRendererHTML public contractRendererHTML;

    // -------- Events
    event MintStatusChanged(MintStatus newStatus);
    event DealerInitialized(uint256 indexed tokenId, address indexed owner);
    event RendererSVGChanged(address indexed newAddress);
    event RendererHTMLChanged(address indexed newAddress);
    event DealersExeCoreUpdated(address indexed newCore);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event DistributionInitialized(uint256 seed);

    // -------- Errors
    error InvalidMint();
    error TotalSupplyReached();
    error NotFamilyMint();
    error NotWhitelistMint();
    error NotPublicMint();
    error InsufficientETH();
    error InvalidSignature();
    error SignatureAlreadyUsed();
    error TokenDoesNotExist();
    error InvalidAddress();
    error TransferFailed();
    error InsufficientBalance();
    error DistributionAlreadyInitialized();
    error RendererNotSet();

    constructor(address _signerAddress, address _royaltyReceiver)
        ERC721("Drug Wars Dealers", "DEALERS")
    {
        _initializeOwner(msg.sender);
        signerAddress = _signerAddress;
        royaltyReceiver = _royaltyReceiver;
        reserve(RESERVE_SUPPLY);
    }

    // -------- Modifiers
    modifier onlyFamilyMint() { if (mintStatus != MintStatus.FAMILY) revert NotFamilyMint(); _; }
    modifier onlyWhitelistMint() { if (mintStatus != MintStatus.WHITELIST) revert NotWhitelistMint(); _; }
    modifier onlyPublicMint() { if (mintStatus != MintStatus.PUBLIC) revert NotPublicMint(); _; }

    modifier checkAndUpdateTotalMinted(uint256 nftAmount) {
        uint256 newTotal = uint256(totalMinted) + nftAmount;
        if (newTotal > MAX_SUPPLY) revert TotalSupplyReached();
        totalMinted = uint32(newTotal);
        _;
    }

    modifier checkAndUpdateBuyerMintCount(uint256 nftAmount) {
        uint256 newMint = mintCount[msg.sender] + nftAmount;
        if (newMint > MAX_PER_WALLET) revert InvalidMint();
        mintCount[msg.sender] = newMint;
        _;
    }

    // =============================================================
    //                           MINTING
    // =============================================================

    function reserve(uint256 nftAmount)
        public
        onlyOwner
        checkAndUpdateTotalMinted(nftAmount)
    {
        _mintDealer(msg.sender, nftAmount);
    }

    function reserveTo(uint256 nftAmount, address recipient)
        public
        onlyOwner
        checkAndUpdateTotalMinted(nftAmount)
    {
        _mintDealer(recipient, nftAmount);
    }

    function reserveToMany(uint256 nftAmount, address[] memory recipients) public onlyOwner {
        uint256 len = recipients.length;
        for (uint256 i; i < len; ) {
            _mintDealer(recipients[i], nftAmount);
            unchecked { ++i; }
        }
    }

    function mintFamily(address dest, uint256 count, bytes calldata signature)
        external
        payable
        nonReentrant
        onlyFamilyMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        if (msg.value < MINT_PRICE * count) revert InsufficientETH();
        bytes32 sigH = keccak256(signature);
        if (usedSignaturesHash[sigH]) revert SignatureAlreadyUsed();

        // EOA allowance encoded; include sender, dest, count, and domain tag
        bytes32 msgHash = keccak256(abi.encodePacked("FAMILY", msg.sender, dest, count)).toEthSignedMessageHash();
        if (msgHash.recover(signature) != signerAddress) revert InvalidSignature();

        usedSignaturesHash[sigH] = true;
        _mintDealer(dest, count);
    }

    function mintWhitelist(address dest, uint256 count, bytes calldata signature)
        external
        payable
        nonReentrant
        onlyWhitelistMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        if (msg.value < MINT_PRICE * count) revert InsufficientETH();
        bytes32 sigH = keccak256(signature);
        if (usedSignaturesHash[sigH]) revert SignatureAlreadyUsed();

        bytes32 msgHash = keccak256(abi.encodePacked("WHITELIST", msg.sender, dest, count)).toEthSignedMessageHash();
        if (msgHash.recover(signature) != signerAddress) revert InvalidSignature();

        usedSignaturesHash[sigH] = true;
        _mintDealer(dest, count);
    }

    function mintPublic(address dest, uint256 count)
        external
        payable
        nonReentrant
        onlyPublicMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        if (msg.value < MINT_PRICE * count) revert InsufficientETH();
        _mintDealer(dest, count);
    }

    function _mintDealer(address to, uint256 nftAmount) private {
        address core = dealersExeCore; // cache
        uint256 id = currentTokenId;

        for (uint256 i; i < nftAmount; ) {
            uint256 tokenId = id;

            // per-token seed (varied by tokenId)
            tokenSeeds[tokenId] = uint256(
                keccak256(
                    abi.encodePacked(tokenId, address(this), block.timestamp, block.prevrandao)
                )
            );

            _safeMint(to, tokenId);
            unchecked { ++id; ++i; }

            if (core != address(0)) {
                IDealersExeCore(core).initializeDealer(tokenId);
                emit DealerInitialized(tokenId, to);
            }
        }
        currentTokenId = id;
    }

    // =============================================================
    //                         METADATA / URI
    // =============================================================

    function tokenJson(uint256 tokenId) public view returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();

        uint256 seed = tokenSeeds[tokenId];
        string memory svg;
        IDealersExeRendererSVG svgRenderer = contractRendererSVG;

        if (address(svgRenderer) != address(0)) {
            svg = svgRenderer.getSVG(tokenId, seed);
        } else {
            svg = "";
        }

        bytes memory attrs = abi.encodePacked(
            _getStaticTraits(tokenId, seed),
            _getDynamicTraits(tokenId)
        );

        // Build JSON via bytes => one final copy
        bytes memory json = abi.encodePacked(
            '{"name":"Dealer #', tokenId.toString(),
            '","description":"Drug Wars - On-Chain Mafia Strategy Game. An on-chain PvE/PvP mafia strategy game built around dynamic NFT dealers with embedded gameplay interfaces and player-to-player drug trading.",',
            '"attributes":[', attrs, '],',
            _getAnimationUrl(svg),
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '"}'
        );

        return string(json);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(bytes(tokenJson(tokenId)))
            )
        );
    }

    function _getStaticTraits(uint256 tokenId, uint256 seed) private view returns (bytes memory) {
        IDealersExeRendererSVG svgRenderer = contractRendererSVG;
        if (address(svgRenderer) == address(0)) return "";

        string memory out;
        // Prefer token-aware traits (1/1, Special)
        try svgRenderer.getTraitsMetadataForToken(tokenId, seed) returns (string memory tokenMeta) {
            out = tokenMeta;
        } catch {
            // Fallback to generic
            try svgRenderer.getTraitsMetadata(seed) returns (string memory genericMeta) {
                out = genericMeta;
            } catch {
                out = "";
            }
        }
        if (bytes(out).length == 0) return "";
        return abi.encodePacked(out, ",");
    }

    function _getDynamicTraits(uint256 tokenId) private view returns (bytes memory) {
        address core = dealersExeCore;
        if (core == address(0)) return "";

        try IDealersExeCore(core).getDealerData(tokenId) returns (
            uint8 currentArea,
            uint256 reputation,
            bool pvpEnabled,
            uint8 /* dailyPlaysRemaining */,
            uint32 /* lastPlayTimestamp */,
            bool isInitialized
        ) {
            if (!isInitialized) return "";
            return abi.encodePacked(
                '{"trait_type":"Area","value":"', currentArea.toString(), '"},',
                '{"trait_type":"Reputation","value":"', reputation.toString(), '"},',
                '{"trait_type":"PvP Status","value":"', (pvpEnabled ? "Enabled" : "Disabled"), '"}'
            );
        } catch {
            return "";
        }
    }

    function _getAnimationUrl(string memory svg) private view returns (bytes memory) {
        IDealersExeRendererHTML htmlRenderer = contractRendererHTML;
        if (address(htmlRenderer) == address(0)) return "";
        return abi.encodePacked(
            '"animation_url":"data:text/html;base64,',
            Base64.encode(bytes(htmlRenderer.getHTML(svg))),
            '",'
        );
    }

    // =============================================================
    //                    RENDERER INTEGRATION
    // =============================================================

    function initializeRendererDistribution(uint256 seed) external onlyOwner {
        IDealersExeRendererSVG svgRenderer = contractRendererSVG;
        if (address(svgRenderer) == address(0)) revert RendererNotSet();

        try svgRenderer.distributionInitialized() returns (bool initialized) {
            if (initialized) revert DistributionAlreadyInitialized();
            svgRenderer.initializeDistribution(seed);
            emit DistributionInitialized(seed);
        } catch {
            // keep explicit revert so the caller knows renderer lacks this API
            revert("Renderer does not support distribution");
        }
    }

    function getCharacterType(uint256 tokenId) external view returns (uint8) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        IDealersExeRendererSVG svgRenderer = contractRendererSVG;
        if (address(svgRenderer) == address(0)) return 0;
        try svgRenderer.getCharacterType(tokenId) returns (uint8 t) {
            return t;
        } catch {
            return 0;
        }
    }

    function isDistributionInitialized() external view returns (bool) {
        IDealersExeRendererSVG svgRenderer = contractRendererSVG;
        if (address(svgRenderer) == address(0)) return false;
        try svgRenderer.distributionInitialized() returns (bool b) {
            return b;
        } catch {
            return false;
        }
    }

    // =============================================================
    //                           ADMIN
    // =============================================================

    function setDealersExeCore(address _core) external onlyOwner {
        if (_core == address(0)) revert InvalidAddress();
        dealersExeCore = _core;
        emit DealersExeCoreUpdated(_core);
    }

    function setContractRendererSVG(address newAddress) external onlyOwner {
        contractRendererSVG = IDealersExeRendererSVG(newAddress);
        emit RendererSVGChanged(newAddress);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    function setContractRendererHTML(address newAddress) external onlyOwner {
        contractRendererHTML = IDealersExeRendererHTML(newAddress);
        emit RendererHTMLChanged(newAddress);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    function setMintStatus(MintStatus newStatus) external onlyOwner {
        mintStatus = newStatus;
        emit MintStatusChanged(newStatus);
    }

    function setSignerAddress(address _signer) external onlyOwner {
        if (_signer == address(0)) revert InvalidAddress();
        signerAddress = _signer;
    }

    function setRoyaltyReceiver(address _receiver) external onlyOwner {
        if (_receiver == address(0)) revert InvalidAddress();
        royaltyReceiver = _receiver;
    }

    function refreshMetadata() external onlyOwner {
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    function withdrawAmount(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientBalance();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function withdrawAll() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) revert InsufficientBalance();
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert TransferFailed();
    }

    // =============================================================
    //                            VIEWS
    // =============================================================

    function getPricePublicETH() external pure returns (uint256) { return MINT_PRICE; }

    function getNumMinted(address account) external view returns (uint256) {
        return mintCount[account];
    }

    function getTokenSeed(uint256 tokenId) external view returns (uint256) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return tokenSeeds[tokenId];
    }

    function getMintConfig() external view returns (
        MintStatus status,
        uint256 price,
        uint256 maxPerWallet,
        uint256 currentSupply,
        uint256 maxSupply,
        uint256 reserveSupply
    ) {
        status = mintStatus;
        price = MINT_PRICE;
        maxPerWallet = MAX_PER_WALLET;
        currentSupply = totalSupply();
        maxSupply = MAX_SUPPLY;
        reserveSupply = RESERVE_SUPPLY;
    }

    function getContractAddresses() external view returns (address, address, address) {
        return (address(contractRendererSVG), address(contractRendererHTML), dealersExeCore);
    }

    function isSignatureUsed(bytes calldata signature) external view returns (bool) {
        return usedSignaturesHash[keccak256(signature)];
    }

    function tokensOfOwner(address owner_) external view returns (uint256[] memory) {
        uint256 n = balanceOf(owner_);
        if (n == 0) return new uint256[](0);
        uint256[] memory ids = new uint256[](n);
        for (uint256 i; i < n; ) {
            ids[i] = tokenOfOwnerByIndex(owner_, i);
            unchecked { ++i; }
        }
        return ids;
    }

    // =============================================================
    //                        ROYALTIES / INTERFACES
    // =============================================================

    function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = royaltyReceiver;
        royaltyAmount = (salePrice * ROYALTY_PERCENTAGE) / 10000;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    // =============================================================
    //                          INTERNAL
    // =============================================================

    function _exists(uint256 tokenId) internal view returns (bool) {
        // O(1) existence check without storage scan
        return tokenId > 0 && tokenId < currentTokenId;
    }
}
