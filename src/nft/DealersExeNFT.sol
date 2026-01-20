// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";
import "../core/IDealersExeCore.sol";
import "../utils/IDERandomness.sol";

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

/**
 * @title DealersExeNFT
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀▀ ▀▄▀ █▀▀
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ██▄ █░█ ██▄
 *
 * @dev ERC721 with dynamic on-chain metadata and embedded HTML gameplay UI
 * @author Dealers.Exe Team
 */
contract DealersExeNFT is ERC721Enumerable, ReentrancyGuard, Ownable, IERC2981 {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using LibString for uint256;
    using LibString for uint8;

    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant MAX_SUPPLY = 8888;
    uint256 public constant RESERVE_SUPPLY = 200;
    uint256 public constant ROYALTY_PERCENTAGE = 500; // 5%
    uint256 public constant MINT_PRICE = 0.01 ether;
    uint256 public constant MAX_PER_WALLET = 10;

    // =============================================================
    //                            STORAGE
    // =============================================================

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
    IDERandomness public randomness;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event MintStatusChanged(MintStatus newStatus);
    event DealerInitialized(uint256 indexed tokenId, address indexed owner);
    event RendererSVGChanged(address indexed newAddress);
    event RendererHTMLChanged(address indexed newAddress);
    event DealersExeCoreUpdated(address indexed newCore);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event DistributionInitialized(uint256 seed);
    event RandomnessUpdated(address indexed newAddress);
    event SignerAddressChanged(address indexed oldSigner, address indexed newSigner);
    event RoyaltyReceiverChanged(address indexed oldReceiver, address indexed newReceiver);

    // =============================================================
    //                            ERRORS
    // =============================================================

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
    error ETHTransferFailed();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(address _signerAddress, address _royaltyReceiver)
        ERC721("Drug Wars Dealers", "DEALERS")
    {
        _initializeOwner(msg.sender);
        signerAddress = _signerAddress;
        royaltyReceiver = _royaltyReceiver;
        reserve(RESERVE_SUPPLY);
    }

    // =============================================================
    //                           MODIFIERS
    // =============================================================

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

    /**
     * @notice Reserve NFTs to the owner address
     * @param nftAmount Number of NFTs to reserve
     */
    function reserve(uint256 nftAmount)
        public
        onlyOwner
        checkAndUpdateTotalMinted(nftAmount)
    {
        _mintDealer(msg.sender, nftAmount);
    }

    /**
     * @notice Reserve NFTs to a specific recipient address
     * @param nftAmount Number of NFTs to reserve
     * @param recipient Address to receive the reserved NFTs
     */
    function reserveTo(uint256 nftAmount, address recipient)
        public
        onlyOwner
        checkAndUpdateTotalMinted(nftAmount)
    {
        _mintDealer(recipient, nftAmount);
    }

    /**
     * @notice Reserve NFTs to multiple recipient addresses
     * @param nftAmount Number of NFTs per recipient
     * @param recipients Array of addresses to receive NFTs
     */
    function reserveToMany(uint256 nftAmount, address[] memory recipients)
        public
        onlyOwner
        checkAndUpdateTotalMinted(nftAmount * recipients.length)
    {
        uint256 len = recipients.length;
        for (uint256 i; i < len; ) {
            _mintDealer(recipients[i], nftAmount);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Mint NFTs during family phase with signature verification
     * @param dest Destination address for minted NFTs
     * @param count Number of NFTs to mint
     * @param signature Authorization signature from signer
     */
    function mintFamily(address dest, uint256 count, bytes calldata signature)
        external
        payable
        nonReentrant
        onlyFamilyMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        uint256 requiredPayment = MINT_PRICE * count;
        if (msg.value < requiredPayment) revert InsufficientETH();
        bytes32 sigH = keccak256(signature);
        if (usedSignaturesHash[sigH]) revert SignatureAlreadyUsed();

        bytes32 msgHash = keccak256(abi.encodePacked("FAMILY", block.chainid, address(this), msg.sender, dest, count)).toEthSignedMessageHash();
        if (msgHash.recover(signature) != signerAddress) revert InvalidSignature();

        usedSignaturesHash[sigH] = true;
        _mintDealer(dest, count);

        if (msg.value > requiredPayment) {
            (bool success, ) = msg.sender.call{value: msg.value - requiredPayment}("");
            if (!success) revert ETHTransferFailed();
        }
    }

    /**
     * @notice Mint NFTs during whitelist phase with signature verification
     * @param dest Destination address for minted NFTs
     * @param count Number of NFTs to mint
     * @param signature Authorization signature from signer
     */
    function mintWhitelist(address dest, uint256 count, bytes calldata signature)
        external
        payable
        nonReentrant
        onlyWhitelistMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        uint256 requiredPayment = MINT_PRICE * count;
        if (msg.value < requiredPayment) revert InsufficientETH();
        bytes32 sigH = keccak256(signature);
        if (usedSignaturesHash[sigH]) revert SignatureAlreadyUsed();

        bytes32 msgHash = keccak256(abi.encodePacked("WHITELIST", block.chainid, address(this), msg.sender, dest, count)).toEthSignedMessageHash();
        if (msgHash.recover(signature) != signerAddress) revert InvalidSignature();

        usedSignaturesHash[sigH] = true;
        _mintDealer(dest, count);

        if (msg.value > requiredPayment) {
            (bool success, ) = msg.sender.call{value: msg.value - requiredPayment}("");
            if (!success) revert ETHTransferFailed();
        }
    }

    /**
     * @notice Mint NFTs during public phase
     * @param dest Destination address for minted NFTs
     * @param count Number of NFTs to mint
     */
    function mintPublic(address dest, uint256 count)
        external
        payable
        nonReentrant
        onlyPublicMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        uint256 requiredPayment = MINT_PRICE * count;
        if (msg.value < requiredPayment) revert InsufficientETH();
        _mintDealer(dest, count);

        if (msg.value > requiredPayment) {
            (bool success, ) = msg.sender.call{value: msg.value - requiredPayment}("");
            if (!success) revert ETHTransferFailed();
        }
    }

    function _mintDealer(address to, uint256 nftAmount) private {
        address core = dealersExeCore; // cache
        IDERandomness rng = randomness; // cache
        uint256 id = currentTokenId;

        for (uint256 i; i < nftAmount; ) {
            uint256 tokenId = id;

            // per-token seed using centralized randomness if available
            if (address(rng) != address(0)) {
                bytes32 seed = keccak256(abi.encodePacked(tokenId, address(this)));
                tokenSeeds[tokenId] = rng.getRandomness(seed);
            } else {
                // Fallback for initial deploy before randomness is set
                tokenSeeds[tokenId] = uint256(
                    keccak256(
                        abi.encodePacked(tokenId, address(this), block.timestamp, block.prevrandao)
                    )
                );
            }

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
    //                           METADATA
    // =============================================================

    /**
     * @notice Get the raw JSON metadata for a token
     * @param tokenId The token ID to get metadata for
     * @return JSON string containing token metadata
     */
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

    /**
     * @notice Get the base64-encoded data URI for a token
     * @param tokenId The token ID to get URI for
     * @return Base64-encoded data URI containing token metadata
     */
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
            uint8 /* dailyAttemptsRemaining */,
            uint8 heatLevel,
            uint32 /* lastPlayTimestamp */,
            bool isInitialized
        ) {
            if (!isInitialized) return "";
            return abi.encodePacked(
                '{"trait_type":"Area","value":"', currentArea.toString(), '"},',
                '{"trait_type":"Reputation","value":"', reputation.toString(), '"},',
                '{"trait_type":"Heat Level","value":"', heatLevel.toString(), '"}'
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

    /**
     * @notice Initialize the character type distribution in the renderer
     * @param seed Random seed for distribution initialization
     */
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

    /**
     * @notice Get the character type for a specific token
     * @param tokenId The token ID to query
     * @return Character type identifier (0 if renderer not set)
     */
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

    /**
     * @notice Check if the renderer distribution has been initialized
     * @return True if distribution is initialized, false otherwise
     */
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

    /**
     * @notice Set the DealersExeCore contract address
     * @param _core Address of the core game contract
     */
    function setDealersExeCore(address _core) external onlyOwner {
        if (_core == address(0)) revert InvalidAddress();
        dealersExeCore = _core;
        emit DealersExeCoreUpdated(_core);
    }

    /**
     * @notice Set the SVG renderer contract address
     * @param newAddress Address of the SVG renderer contract
     */
    function setContractRendererSVG(address newAddress) external onlyOwner {
        if (newAddress == address(0)) revert InvalidAddress();
        contractRendererSVG = IDealersExeRendererSVG(newAddress);
        emit RendererSVGChanged(newAddress);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    /**
     * @notice Set the HTML renderer contract address
     * @param newAddress Address of the HTML renderer contract
     */
    function setContractRendererHTML(address newAddress) external onlyOwner {
        if (newAddress == address(0)) revert InvalidAddress();
        contractRendererHTML = IDealersExeRendererHTML(newAddress);
        emit RendererHTMLChanged(newAddress);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    /**
     * @notice Set the randomness provider contract address
     * @param newAddress Address of the randomness contract
     */
    function setRandomness(address newAddress) external onlyOwner {
        if (newAddress == address(0)) revert InvalidAddress();
        randomness = IDERandomness(newAddress);
        emit RandomnessUpdated(newAddress);
    }

    /**
     * @notice Set the current minting phase status
     * @param newStatus New mint status (DISABLED, FAMILY, WHITELIST, PUBLIC)
     */
    function setMintStatus(MintStatus newStatus) external onlyOwner {
        mintStatus = newStatus;
        emit MintStatusChanged(newStatus);
    }

    /**
     * @notice Set the signer address for signature verification
     * @param _signer Address authorized to sign mint allowances
     */
    function setSignerAddress(address _signer) external onlyOwner {
        if (_signer == address(0)) revert InvalidAddress();
        address oldSigner = signerAddress;
        signerAddress = _signer;
        emit SignerAddressChanged(oldSigner, _signer);
    }

    /**
     * @notice Set the royalty receiver address for EIP-2981
     * @param _receiver Address to receive royalty payments
     */
    function setRoyaltyReceiver(address _receiver) external onlyOwner {
        if (_receiver == address(0)) revert InvalidAddress();
        address oldReceiver = royaltyReceiver;
        royaltyReceiver = _receiver;
        emit RoyaltyReceiverChanged(oldReceiver, _receiver);
    }

    /**
     * @notice Emit metadata update event for all tokens
     */
    function refreshMetadata() external onlyOwner {
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    /**
     * @notice Withdraw a specific amount of ETH to a recipient
     * @param to Recipient address
     * @param amount Amount of ETH to withdraw in wei
     */
    function withdrawAmount(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientBalance();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /**
     * @notice Withdraw all ETH to the contract owner
     */
    function withdrawAll() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) revert InsufficientBalance();
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert TransferFailed();
    }

    // =============================================================
    //                            VIEWS
    // =============================================================

    /**
     * @notice Get the public mint price in ETH
     * @return Mint price in wei
     */
    function getPricePublicETH() external pure returns (uint256) { return MINT_PRICE; }

    /**
     * @notice Get the number of NFTs minted by an account
     * @param account Address to check
     * @return Number of NFTs minted
     */
    function getNumMinted(address account) external view returns (uint256) {
        return mintCount[account];
    }

    /**
     * @notice Get the random seed for a token
     * @param tokenId Token ID to query
     * @return Seed value used for trait generation
     */
    function getTokenSeed(uint256 tokenId) external view returns (uint256) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return tokenSeeds[tokenId];
    }

    /**
     * @notice Get the current mint configuration
     * @return status Current mint phase status
     * @return price Mint price in wei
     * @return maxPerWallet Maximum NFTs per wallet
     * @return currentSupply Current total supply
     * @return maxSupply Maximum total supply
     * @return reserveSupply Reserved supply for team
     */
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

    /**
     * @notice Get all external contract addresses
     * @return SVG renderer, HTML renderer, and core contract addresses
     */
    function getContractAddresses() external view returns (address, address, address) {
        return (address(contractRendererSVG), address(contractRendererHTML), dealersExeCore);
    }

    /**
     * @notice Check if a signature has already been used for minting
     * @param signature Signature bytes to check
     * @return True if signature has been used
     */
    function isSignatureUsed(bytes calldata signature) external view returns (bool) {
        return usedSignaturesHash[keccak256(signature)];
    }

    /**
     * @notice Get all token IDs owned by an address
     * @param owner_ Address to query
     * @return Array of token IDs owned by the address
     */
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
    //                          ROYALTIES
    // =============================================================

    /**
     * @notice Get royalty information for a token sale (EIP-2981)
     * @param salePrice Sale price to calculate royalty from
     * @return receiver Address to receive royalty payment
     * @return royaltyAmount Royalty amount in wei
     */
    function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = royaltyReceiver;
        royaltyAmount = (salePrice * ROYALTY_PERCENTAGE) / 10000;
    }

    /**
     * @notice Check if contract supports an interface (ERC165)
     * @param interfaceId Interface identifier to check
     * @return True if interface is supported
     */
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
