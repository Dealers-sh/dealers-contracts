// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import "../core/IDealersCore.sol";
import "../utils/IAreaRegistry.sol";

interface IDealerRendererSVG {
    function getSVG(uint256 tokenId) external view returns (string memory);
    function getTraitsMetadataForToken(uint256 tokenId) external view returns (string memory);
    function getCharacterType(uint256 tokenId) external view returns (uint8);
}

interface IDealerRendererHTML {
    function getHTML(uint256 tokenId, string memory svg) external view returns (string memory);
}

/**
 * @title DealersNFT
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev ERC721 with dynamic on-chain metadata and embedded HTML gameplay UI
 * @author Berny0x
 */
contract DealersNFT is ERC721Enumerable, ReentrancyGuard, Ownable, IERC2981 {
    using LibString for uint256;
    using LibString for uint8;

    // =============================================================
    //                            CONSTANTS
    // =============================================================

    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant ROYALTY_PERCENTAGE = 500; // 5%
    uint256 public constant MAX_PER_WALLET = 10;

    // =============================================================
    //                            STORAGE
    // =============================================================

    enum MintStatus {
        DISABLED,
        FAMILY,
        WHITELIST,
        PUBLIC
    }

    MintStatus public mintStatus = MintStatus.DISABLED;
    bool public paused;

    uint32 public totalMinted; // fits in 32 bits
    uint256 public currentTokenId = 1;

    address public dealersCore;
    address public royaltyReceiver;

    bytes32 public familyMerkleRoot;
    bytes32 public whitelistMerkleRoot;

    mapping(address => uint256) private mintCount;
    mapping(address => uint256) private familyClaimed;
    mapping(address => uint256) private whitelistClaimed;

    IDealerRendererSVG public contractRendererSVG;
    IDealerRendererHTML public contractRendererHTML;

    uint256 public mintPrice = 0.01 ether;

    string public contractDescription;
    string public contractImage;
    string public contractBannerImage;
    string public contractFeaturedImage;
    string public contractExternalLink;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event MintStatusChanged(MintStatus newStatus);
    event MintPriceChanged(uint256 oldPrice, uint256 newPrice);
    event DealerInitialized(uint256 indexed tokenId, address indexed owner);
    event RendererSVGChanged(address indexed newAddress);
    event RendererHTMLChanged(address indexed newAddress);
    event DealersCoreUpdated(address indexed newCore);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event FamilyMerkleRootSet(bytes32 indexed root);
    event WhitelistMerkleRootSet(bytes32 indexed root);
    event RoyaltyReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    event Paused(address account);
    event Unpaused(address account);
    event ContractURIUpdated();

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidMint();
    error TotalSupplyReached();
    error NotFamilyMint();
    error NotWhitelistMint();
    error NotPublicMint();
    error InsufficientETH();
    error InvalidMerkleProof();
    error MerkleRootNotSet();
    error ExceedsAllocation();
    error TokenDoesNotExist();
    error InvalidAddress();
    error TransferFailed();
    error InsufficientBalance();
    error ETHTransferFailed();
    error ContractPaused();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(address _royaltyReceiver) ERC721("dealers.sh", "DEALER") {
        _initializeOwner(msg.sender);
        royaltyReceiver = _royaltyReceiver;
    }

    // =============================================================
    //                           MODIFIERS
    // =============================================================

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyFamilyMint() {
        if (mintStatus != MintStatus.FAMILY) revert NotFamilyMint();
        _;
    }

    modifier onlyWhitelistMint() {
        if (mintStatus != MintStatus.WHITELIST) revert NotWhitelistMint();
        _;
    }

    modifier onlyPublicMint() {
        if (mintStatus != MintStatus.PUBLIC) revert NotPublicMint();
        _;
    }

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
    function reserve(uint256 nftAmount) public onlyOwner nonReentrant checkAndUpdateTotalMinted(nftAmount) {
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
        nonReentrant
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
        nonReentrant
        checkAndUpdateTotalMinted(nftAmount * recipients.length)
    {
        uint256 len = recipients.length;
        for (uint256 i; i < len;) {
            _mintDealer(recipients[i], nftAmount);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Mint NFTs during family phase with merkle proof verification
     * @dev Family mint is FREE - no payment required
     * @param count Number of NFTs to mint
     * @param maxAllocation Maximum allocation for this address in merkle tree
     * @param proof Merkle proof for family list inclusion
     */
    function mintFamily(uint256 count, uint256 maxAllocation, bytes32[] calldata proof)
        external
        nonReentrant
        whenNotPaused
        onlyFamilyMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        if (familyMerkleRoot == bytes32(0)) revert MerkleRootNotSet();

        uint256 alreadyClaimed = familyClaimed[msg.sender];
        if (alreadyClaimed + count > maxAllocation) revert ExceedsAllocation();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, maxAllocation))));
        if (!MerkleProofLib.verifyCalldata(proof, familyMerkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        familyClaimed[msg.sender] = alreadyClaimed + count;
        _mintDealer(msg.sender, count);
    }

    /**
     * @notice Mint NFTs during whitelist phase with merkle proof verification
     * @dev Whitelist mint requires payment at mintPrice per NFT
     * @param count Number of NFTs to mint
     * @param maxAllocation Maximum allocation for this address in merkle tree
     * @param proof Merkle proof for whitelist inclusion
     */
    function mintWhitelist(uint256 count, uint256 maxAllocation, bytes32[] calldata proof)
        external
        payable
        nonReentrant
        whenNotPaused
        onlyWhitelistMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        uint256 requiredPayment = mintPrice * count;
        if (msg.value < requiredPayment) revert InsufficientETH();

        if (whitelistMerkleRoot == bytes32(0)) revert MerkleRootNotSet();

        uint256 alreadyClaimed = whitelistClaimed[msg.sender];
        if (alreadyClaimed + count > maxAllocation) revert ExceedsAllocation();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, maxAllocation))));
        if (!MerkleProofLib.verifyCalldata(proof, whitelistMerkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        whitelistClaimed[msg.sender] = alreadyClaimed + count;
        _mintDealer(msg.sender, count);

        if (msg.value > requiredPayment) {
            (bool success,) = msg.sender.call{value: msg.value - requiredPayment}("");
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
        whenNotPaused
        onlyPublicMint
        checkAndUpdateBuyerMintCount(count)
        checkAndUpdateTotalMinted(count)
    {
        uint256 requiredPayment = mintPrice * count;
        if (msg.value < requiredPayment) revert InsufficientETH();
        _mintDealer(dest, count);

        if (msg.value > requiredPayment) {
            (bool success,) = msg.sender.call{value: msg.value - requiredPayment}("");
            if (!success) revert ETHTransferFailed();
        }
    }

    function _mintDealer(address to, uint256 nftAmount) private {
        address core = dealersCore;
        uint256 id = currentTokenId;

        for (uint256 i; i < nftAmount;) {
            uint256 tokenId = id;
            _safeMint(to, tokenId);
            unchecked {
                ++id;
                ++i;
            }

            if (core != address(0)) {
                IDealersCore(core).initializeDealer(tokenId);
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

        string memory svg;
        IDealerRendererSVG svgRenderer = contractRendererSVG;

        if (address(svgRenderer) != address(0)) {
            svg = svgRenderer.getSVG(tokenId);
        } else {
            svg = "";
        }

        bytes memory staticTraits = _getStaticTraits(tokenId);
        bytes memory dynamicTraits = _getDynamicTraits(tokenId);
        bytes memory attrs = staticTraits.length > 0 && dynamicTraits.length > 0
            ? abi.encodePacked(staticTraits, ",", dynamicTraits)
            : abi.encodePacked(staticTraits, dynamicTraits);

        string memory description = _buildDescription(tokenId);

        bytes memory json = abi.encodePacked(
            '{"name":"Dealer #',
            tokenId.toString(),
            '","description":"',
            description,
            '",',
            '"attributes":[',
            attrs,
            "],",
            _getAnimationUrl(tokenId, svg),
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        );

        return string(json);
    }

    /**
     * @notice Get the base64-encoded data URI for a token
     * @param tokenId The token ID to get URI for
     * @return Base64-encoded data URI containing token metadata
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(tokenJson(tokenId)))));
    }

    /**
     * @notice Get collection-level metadata per EIP-7572
     * @return Base64-encoded data URI containing collection metadata
     */
    function contractURI() external view returns (string memory) {
        bytes memory json = abi.encodePacked(
            '{"name":"',
            name(),
            '","description":"',
            contractDescription,
            '","image":"',
            contractImage,
            '","banner_image":"',
            contractBannerImage,
            '","featured_image":"',
            contractFeaturedImage,
            '","external_link":"',
            contractExternalLink,
            '"}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function _getStaticTraits(uint256 tokenId) private view returns (bytes memory) {
        IDealerRendererSVG svgRenderer = contractRendererSVG;
        if (address(svgRenderer) == address(0)) return "";

        string memory out;
        try svgRenderer.getTraitsMetadataForToken(tokenId) returns (string memory tokenMeta) {
            out = tokenMeta;
        } catch {
            out = "";
        }
        if (bytes(out).length == 0) return "";
        return abi.encodePacked(out);
    }

    function _getDynamicTraits(uint256 tokenId) private view returns (bytes memory) {
        address core = dealersCore;
        if (core == address(0)) return "";

        try IDealersCore(core).getDealerData(tokenId) returns (
            uint8 currentArea,
            uint256, /* reputation */
            uint8, /* dailyAttemptsRemaining */
            uint8 heatLevel,
            uint32, /* lastPlayTimestamp */
            bool isInitialized
        ) {
            if (!isInitialized) return "";

            uint256 totalRep = IDealersCore(core).getTotalReputation(tokenId);
            string memory rank = IDealersCore(core).getReputationTitle(totalRep);
            string memory areaName = _getAreaName(core, currentArea);
            string memory heat = _heatStars(heatLevel);
            uint256 infamy = IDealersCore(core).getInfamy(tokenId);

            return abi.encodePacked(
                '{"trait_type":"Rank","value":"',
                rank,
                '"},',
                '{"trait_type":"Infamy","display_type":"number","value":',
                infamy.toString(),
                "},",
                '{"trait_type":"Area","value":"',
                areaName,
                '"},',
                '{"trait_type":"Heat","value":"',
                heat,
                '"}'
            );
        } catch {
            return "";
        }
    }

    function _buildDescription(uint256 tokenId) private view returns (string memory) {
        address core = dealersCore;
        if (core == address(0)) {
            return string(
                abi.encodePacked(
                    "Dealer #",
                    tokenId.toString(),
                    " is part of the Dealers.sh collection - 8,888 on-chain dealers hustling, fighting, and climbing the ranks on Abstract Chain."
                )
            );
        }

        try IDealersCore(core).getDealerData(tokenId) returns (
            uint8, /* currentArea */
            uint256, /* reputation */
            uint8, /* dailyAttemptsRemaining */
            uint8, /* heatLevel */
            uint32, /* lastPlayTimestamp */
            bool isInitialized
        ) {
            if (!isInitialized) {
                return string(
                    abi.encodePacked(
                        "Dealer #",
                        tokenId.toString(),
                        " is part of the Dealers.sh collection - 8,888 on-chain dealers hustling, fighting, and climbing the ranks on Abstract Chain."
                    )
                );
            }

            uint256 totalRep = IDealersCore(core).getTotalReputation(tokenId);
            string memory rank = IDealersCore(core).getReputationTitle(totalRep);
            uint256 infamy = IDealersCore(core).getInfamy(tokenId);

            return string(
                abi.encodePacked(
                    "Dealer #",
                    tokenId.toString(),
                    " is a ",
                    rank,
                    " (",
                    totalRep.toString(),
                    " rep)",
                    " with an infamy score of ",
                    infamy.toString(),
                    ". Part of the Dealers.sh collection - 8,888 on-chain dealers hustling, fighting, and climbing the ranks on Abstract Chain."
                )
            );
        } catch {
            return string(
                abi.encodePacked(
                    "Dealer #",
                    tokenId.toString(),
                    " is part of the Dealers.sh collection - 8,888 on-chain dealers hustling, fighting, and climbing the ranks on Abstract Chain."
                )
            );
        }
    }

    function _getAreaName(address core, uint8 areaId) private view returns (string memory) {
        try IAreaRegistry(address(IDealersCore(core).areaRegistry())).getAreaInfo(areaId) returns (
            IAreaRegistry.AreaInfo memory info
        ) {
            return info.name;
        } catch {
            return areaId.toString();
        }
    }

    function _heatStars(uint8 level) private pure returns (string memory) {
        if (level == 0) return "None";
        if (level == 1) return "\\u2605";
        if (level == 2) return "\\u2605\\u2605";
        if (level == 3) return "\\u2605\\u2605\\u2605";
        if (level == 4) return "\\u2605\\u2605\\u2605\\u2605";
        return "\\u2605\\u2605\\u2605\\u2605\\u2605";
    }

    function _getAnimationUrl(uint256 tokenId, string memory svg) private view returns (bytes memory) {
        IDealerRendererHTML htmlRenderer = contractRendererHTML;
        if (address(htmlRenderer) == address(0)) return "";
        return abi.encodePacked(
            '"animation_url":"data:text/html;base64,', Base64.encode(bytes(htmlRenderer.getHTML(tokenId, svg))), '",'
        );
    }

    // =============================================================
    //                    RENDERER INTEGRATION
    // =============================================================

    /**
     * @notice Get the character type for a specific token
     * @param tokenId The token ID to query
     * @return Character type identifier (0 if renderer not set)
     */
    function getCharacterType(uint256 tokenId) external view returns (uint8) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        IDealerRendererSVG svgRenderer = contractRendererSVG;
        if (address(svgRenderer) == address(0)) return 0;
        try svgRenderer.getCharacterType(tokenId) returns (uint8 t) {
            return t;
        } catch {
            return 0;
        }
    }

    // =============================================================
    //                           ADMIN
    // =============================================================

    /**
     * @notice Set the DealersCore contract address
     * @param _core Address of the core game contract
     */
    function setDealersCore(address _core) external onlyOwner {
        if (_core == address(0)) revert InvalidAddress();
        dealersCore = _core;
        emit DealersCoreUpdated(_core);
    }

    /**
     * @notice Set the SVG renderer contract address
     * @param newAddress Address of the SVG renderer contract
     */
    function setContractRendererSVG(address newAddress) external onlyOwner {
        if (newAddress == address(0)) revert InvalidAddress();
        contractRendererSVG = IDealerRendererSVG(newAddress);
        emit RendererSVGChanged(newAddress);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    /**
     * @notice Set the HTML renderer contract address
     * @param newAddress Address of the HTML renderer contract
     */
    function setContractRendererHTML(address newAddress) external onlyOwner {
        if (newAddress == address(0)) revert InvalidAddress();
        contractRendererHTML = IDealerRendererHTML(newAddress);
        emit RendererHTMLChanged(newAddress);
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
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
     * @notice Set the mint price for whitelist and public minting
     * @param newPrice New mint price in wei (per NFT)
     */
    function setMintPrice(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = mintPrice;
        mintPrice = newPrice;
        emit MintPriceChanged(oldPrice, newPrice);
    }

    /**
     * @notice Pause minting operations
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Resume minting operations
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Set the merkle root for family list
     * @param _root Merkle root hash
     */
    function setFamilyMerkleRoot(bytes32 _root) external onlyOwner {
        familyMerkleRoot = _root;
        emit FamilyMerkleRootSet(_root);
    }

    /**
     * @notice Set the merkle root for whitelist
     * @param _root Merkle root hash
     */
    function setWhitelistMerkleRoot(bytes32 _root) external onlyOwner {
        whitelistMerkleRoot = _root;
        emit WhitelistMerkleRootSet(_root);
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
     * @notice Set collection-level metadata fields exposed via contractURI()
     * @dev Values must not contain unescaped double quotes or backslashes
     * @param description Collection description
     * @param image Collection image URL (HTTPS recommended)
     * @param bannerImage Banner image URL
     * @param featuredImage Featured image URL
     * @param externalLink External project URL
     */
    function setContractURI(
        string calldata description,
        string calldata image,
        string calldata bannerImage,
        string calldata featuredImage,
        string calldata externalLink
    ) external onlyOwner {
        contractDescription = description;
        contractImage = image;
        contractBannerImage = bannerImage;
        contractFeaturedImage = featuredImage;
        contractExternalLink = externalLink;
        emit ContractURIUpdated();
    }

    /**
     * @notice Emit metadata update event for all tokens
     */
    function refreshMetadata() external onlyOwner {
        emit BatchMetadataUpdate(1, MAX_SUPPLY);
    }

    /**
     * @notice Withdraw ETH from the contract
     * @param to Recipient address (address(0) defaults to owner)
     * @param amount Amount of ETH to withdraw in wei (0 withdraws all)
     */
    function withdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        address recipient = to == address(0) ? owner() : to;
        uint256 withdrawAmount = amount == 0 ? address(this).balance : amount;

        if (withdrawAmount == 0) revert InsufficientBalance();
        if (withdrawAmount > address(this).balance) revert InsufficientBalance();

        (bool ok,) = recipient.call{value: withdrawAmount}("");
        if (!ok) revert TransferFailed();
    }

    // =============================================================
    //                            VIEWS
    // =============================================================

    /**
     * @notice Get the number of NFTs minted by an account
     * @param account Address to check
     * @return Number of NFTs minted
     */
    function getNumMinted(address account) external view returns (uint256) {
        return mintCount[account];
    }

    /**
     * @notice Get the current mint configuration
     * @return status Current mint phase status
     * @return price Mint price in wei
     * @return maxPerWallet Maximum NFTs per wallet
     * @return currentSupply Current total supply
     * @return maxSupply Maximum total supply
     */
    function getMintConfig()
        external
        view
        returns (MintStatus status, uint256 price, uint256 maxPerWallet, uint256 currentSupply, uint256 maxSupply)
    {
        status = mintStatus;
        price = mintPrice;
        maxPerWallet = MAX_PER_WALLET;
        currentSupply = totalSupply();
        maxSupply = MAX_SUPPLY;
    }

    /**
     * @notice Get the number of NFTs claimed by an address in family phase
     * @param account Address to check
     * @return Number of NFTs claimed
     */
    function getFamilyClaimed(address account) external view returns (uint256) {
        return familyClaimed[account];
    }

    /**
     * @notice Get the number of NFTs claimed by an address in whitelist phase
     * @param account Address to check
     * @return Number of NFTs claimed
     */
    function getWhitelistClaimed(address account) external view returns (uint256) {
        return whitelistClaimed[account];
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
        for (uint256 i; i < n;) {
            ids[i] = tokenOfOwnerByIndex(owner_, i);
            unchecked {
                ++i;
            }
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
    function royaltyInfo(uint256, /*tokenId*/ uint256 salePrice)
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
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, IERC165) returns (bool) {
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
