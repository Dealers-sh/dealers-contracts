// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

interface IERC721Minimal {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IDEPaymentHandler {
    function processMarketplaceFee(uint256 amount) external payable;
}

interface IDealersExeCoreMinimal {
    function getDealerData(uint256 tokenId) external view returns (
        uint8 currentArea,
        uint256 reputation,
        uint8 dailyAttemptsRemaining,
        uint8 heatLevel,
        uint32 lastPlayTimestamp,
        bool isInitialized
    );
}

/**
 * @title DealersExeGangs - Gang Management Contract
 * @dev Allows dealers to create and manage gangs with roles and member management
 *      Gangs are social groups with leader, officer, and member roles
 *
 * Future Potential (NOT implemented):
 * - Gang protection (no PVP within gang)
 * - Gang wars
 * - Gang treasury
 * - Territory control
 *
 * @author Dealers.Exe Team
 */
contract DealersExeGangs is ReentrancyGuard, Ownable {
    // =============================================================
    //                            CONSTANTS
    // =============================================================

    /// @notice Fee to create a new gang
    uint256 public constant CREATION_FEE = 0.05 ether;

    /// @notice Maximum number of members per gang
    uint256 public constant MAX_MEMBERS = 50;

    /// @notice Minimum gang name length
    uint256 public constant MIN_NAME_LENGTH = 3;

    /// @notice Maximum gang name length
    uint256 public constant MAX_NAME_LENGTH = 24;

    /// @notice Minimum gang tag length
    uint256 public constant MIN_TAG_LENGTH = 2;

    /// @notice Maximum gang tag length
    uint256 public constant MAX_TAG_LENGTH = 5;

    /// @notice Duration that invitations remain valid
    uint256 public constant INVITATION_DURATION = 7 days;

    // =============================================================
    //                            ENUMS
    // =============================================================

    /// @notice Roles within a gang
    enum GangRole {
        NONE,       // 0 - Not in a gang
        MEMBER,     // 1 - Basic member
        OFFICER,    // 2 - Can invite/kick members
        LEADER      // 3 - Full control
    }

    // =============================================================
    //                            STRUCTS
    // =============================================================

    /**
     * @dev Gang data structure
     * @param name Gang name (3-24 characters)
     * @param tag Short tag (2-5 characters, displayed on NFT)
     * @param leader Owner wallet address
     * @param leaderId Leader's dealer token ID
     * @param memberCount Current number of members
     * @param createdAt Timestamp of gang creation
     * @param isActive Whether the gang is active
     */
    struct Gang {
        string name;
        string tag;
        address leader;
        uint256 leaderId;
        uint256 memberCount;
        uint256 createdAt;
        bool isActive;
    }

    /**
     * @dev Invitation data structure
     * @param gangId ID of the gang sending the invitation
     * @param dealerId Dealer being invited
     * @param invitedBy Address that sent the invitation
     * @param expiresAt Timestamp when invitation expires
     */
    struct Invitation {
        uint256 gangId;
        uint256 dealerId;
        address invitedBy;
        uint256 expiresAt;
    }

    // =============================================================
    //                            STORAGE
    // =============================================================

    // Contract references
    IDealersExeCoreMinimal public dealersExeCore;
    IERC721Minimal public dealersExeNFT;
    IDEPaymentHandler public paymentHandler;

    // Gang storage
    mapping(uint256 => Gang) public gangs;                    // gangId => Gang
    mapping(uint256 => uint256) public dealerToGang;          // dealerId => gangId (0 = no gang)
    mapping(uint256 => GangRole) public memberRole;           // dealerId => role
    mapping(uint256 => Invitation) public invitations;        // dealerId => active invitation
    mapping(string => bool) public gangNameTaken;             // name (lowercase) => taken
    mapping(string => bool) public gangTagTaken;              // tag (lowercase) => taken

    // Member tracking for enumeration
    mapping(uint256 => uint256[]) private gangMembers;        // gangId => array of dealerIds
    mapping(uint256 => uint256) private memberIndex;          // dealerId => index in gangMembers array

    // Statistics
    uint256 public totalGangs;
    uint256 public totalActiveGangs;
    uint256 public totalCreationFees;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event GangCreated(
        uint256 indexed gangId,
        string name,
        string tag,
        uint256 leaderId,
        address leader
    );
    event GangDisbanded(uint256 indexed gangId);
    event MemberJoined(uint256 indexed gangId, uint256 indexed dealerId);
    event MemberLeft(uint256 indexed gangId, uint256 indexed dealerId);
    event MemberKicked(
        uint256 indexed gangId,
        uint256 indexed dealerId,
        address kickedBy
    );
    event MemberPromoted(
        uint256 indexed gangId,
        uint256 indexed dealerId,
        GangRole newRole
    );
    event MemberDemoted(
        uint256 indexed gangId,
        uint256 indexed dealerId,
        GangRole newRole
    );
    event InvitationSent(
        uint256 indexed gangId,
        uint256 indexed dealerId,
        address invitedBy,
        uint256 expiresAt
    );
    event InvitationCancelled(uint256 indexed gangId, uint256 indexed dealerId);
    event LeaderTransferred(
        uint256 indexed gangId,
        uint256 oldLeaderId,
        uint256 newLeaderId
    );

    // Admin events
    event CoreContractUpdated(address indexed oldCore, address indexed newCore);
    event NFTContractUpdated(address indexed oldNFT, address indexed newNFT);
    event PaymentHandlerUpdated(address indexed oldHandler, address indexed newHandler);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error NotDealerOwner();
    error DealerNotInitialized();
    error AlreadyInGang();
    error NotInGang();
    error NotGangMember();
    error NotLeaderOrOfficer();
    error NotLeader();
    error GangFull();
    error InsufficientPayment();
    error InvalidName();
    error InvalidTag();
    error NameTaken();
    error TagTaken();
    error NoInvitation();
    error InvitationExpired();
    error CannotKickLeader();
    error GangNotActive();
    error CannotKickHigherRank();
    error CannotLeaveAsLeader();
    error MemberNotInGang();
    error InvalidAddress();
    error TransferFailed();
    error ContractNotSet();
    error AlreadyHasInvitation();
    error CannotInviteSelf();

    // =============================================================
    //                            CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the Gangs contract
     * @param _dealersExeCore Address of the core dealers contract
     * @param _dealersExeNFT Address of the NFT contract
     * @param _paymentHandler Address of the payment handler
     */
    constructor(
        address _dealersExeCore,
        address _dealersExeNFT,
        address _paymentHandler
    ) {
        _initializeOwner(msg.sender);
        dealersExeCore = IDealersExeCoreMinimal(_dealersExeCore);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        paymentHandler = IDEPaymentHandler(_paymentHandler);
    }

    // =============================================================
    //                            MODIFIERS
    // =============================================================

    modifier contractsSet() {
        if (
            address(dealersExeCore) == address(0) ||
            address(dealersExeNFT) == address(0) ||
            address(paymentHandler) == address(0)
        ) {
            revert ContractNotSet();
        }
        _;
    }

    modifier onlyDealerOwner(uint256 dealerId) {
        if (dealersExeNFT.ownerOf(dealerId) != msg.sender) {
            revert NotDealerOwner();
        }
        _;
    }

    modifier dealerInitialized(uint256 dealerId) {
        (, , , , , bool isInitialized) = dealersExeCore.getDealerData(dealerId);
        if (!isInitialized) revert DealerNotInitialized();
        _;
    }

    modifier gangActive(uint256 gangId) {
        if (!gangs[gangId].isActive) revert GangNotActive();
        _;
    }

    // =============================================================
    //                    ABSTRACT CHAIN COMPATIBLE TRANSFERS
    // =============================================================

    /**
     * @notice Safely transfers ETH to a recipient address
     * @dev Uses low-level call for Abstract Chain compatibility
     */
    function _safeTransferETH(address to, uint256 amount) private {
        if (amount == 0) return;
        if (to == address(0)) revert InvalidAddress();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // =============================================================
    //                        GANG CREATION
    // =============================================================

    /**
     * @notice Create a new gang
     * @param dealerId Dealer to be the leader
     * @param name Gang name (3-24 chars)
     * @param tag Short tag (2-5 chars)
     */
    function createGang(
        uint256 dealerId,
        string calldata name,
        string calldata tag
    )
        external
        payable
        nonReentrant
        contractsSet
        onlyDealerOwner(dealerId)
        dealerInitialized(dealerId)
    {
        // Check payment
        if (msg.value < CREATION_FEE) revert InsufficientPayment();

        // Dealer cannot already be in a gang
        if (dealerToGang[dealerId] != 0) revert AlreadyInGang();

        // Validate and reserve name/tag
        _validateAndReserveNameTag(name, tag);

        // Create the gang and set up leader
        uint256 gangId = _createGangInternal(dealerId, name, tag);

        emit GangCreated(gangId, name, tag, dealerId, msg.sender);

        // Process payment (5% dev, 5% vault)
        totalCreationFees += CREATION_FEE;
        paymentHandler.processMarketplaceFee{value: CREATION_FEE}(CREATION_FEE);

        // Refund excess
        if (msg.value > CREATION_FEE) {
            _safeTransferETH(msg.sender, msg.value - CREATION_FEE);
        }
    }

    /**
     * @notice Validate and reserve name/tag (internal)
     */
    function _validateAndReserveNameTag(
        string calldata name,
        string calldata tag
    ) internal {
        // Validate name
        if (!_validateName(name)) revert InvalidName();

        // Validate tag
        if (!_validateTag(tag)) revert InvalidTag();

        // Check name/tag availability (case-insensitive)
        string memory lowerName = _toLower(name);
        string memory lowerTag = _toLower(tag);

        if (gangNameTaken[lowerName]) revert NameTaken();
        if (gangTagTaken[lowerTag]) revert TagTaken();

        // Reserve name and tag
        gangNameTaken[lowerName] = true;
        gangTagTaken[lowerTag] = true;
    }

    /**
     * @notice Create gang data structure (internal)
     */
    function _createGangInternal(
        uint256 dealerId,
        string calldata name,
        string calldata tag
    ) internal returns (uint256 gangId) {
        // Increment gang counter
        unchecked { ++totalGangs; }
        unchecked { ++totalActiveGangs; }
        gangId = totalGangs;

        // Create gang
        gangs[gangId] = Gang({
            name: name,
            tag: tag,
            leader: msg.sender,
            leaderId: dealerId,
            memberCount: 1,
            createdAt: block.timestamp,
            isActive: true
        });

        // Set leader as member
        dealerToGang[dealerId] = gangId;
        memberRole[dealerId] = GangRole.LEADER;

        // Add to member tracking
        gangMembers[gangId].push(dealerId);
        memberIndex[dealerId] = 0;
    }

    // =============================================================
    //                        INVITATION SYSTEM
    // =============================================================

    /**
     * @notice Invite a dealer to join the gang
     * @param inviterId Your dealer (must be leader or officer)
     * @param inviteeId Dealer to invite
     */
    function inviteMember(uint256 inviterId, uint256 inviteeId)
        external
        nonReentrant
        contractsSet
        onlyDealerOwner(inviterId)
        dealerInitialized(inviterId)
        dealerInitialized(inviteeId)
    {
        // Get inviter's gang
        uint256 gangId = dealerToGang[inviterId];
        if (gangId == 0) revert NotInGang();

        // Check gang is active
        if (!gangs[gangId].isActive) revert GangNotActive();

        // Check inviter has permission (leader or officer)
        GangRole role = memberRole[inviterId];
        if (role != GangRole.LEADER && role != GangRole.OFFICER) {
            revert NotLeaderOrOfficer();
        }

        // Check gang is not full
        if (gangs[gangId].memberCount >= MAX_MEMBERS) revert GangFull();

        // Invitee cannot already be in a gang
        if (dealerToGang[inviteeId] != 0) revert AlreadyInGang();

        // Cannot invite self
        if (inviterId == inviteeId) revert CannotInviteSelf();

        // Check if invitee already has a pending invitation
        if (invitations[inviteeId].expiresAt > block.timestamp) {
            revert AlreadyHasInvitation();
        }

        // Create invitation
        uint256 expiresAt = block.timestamp + INVITATION_DURATION;
        invitations[inviteeId] = Invitation({
            gangId: gangId,
            dealerId: inviteeId,
            invitedBy: msg.sender,
            expiresAt: expiresAt
        });

        emit InvitationSent(gangId, inviteeId, msg.sender, expiresAt);
    }

    /**
     * @notice Accept an invitation to join a gang
     * @param dealerId Your dealer with pending invitation
     */
    function acceptInvitation(uint256 dealerId)
        external
        nonReentrant
        contractsSet
        onlyDealerOwner(dealerId)
    {
        Invitation memory invite = invitations[dealerId];

        // Check invitation exists and is valid
        if (invite.expiresAt == 0) revert NoInvitation();
        if (invite.expiresAt < block.timestamp) revert InvitationExpired();

        uint256 gangId = invite.gangId;

        // Check gang is still active
        if (!gangs[gangId].isActive) revert GangNotActive();

        // Check gang is not full
        if (gangs[gangId].memberCount >= MAX_MEMBERS) revert GangFull();

        // Check dealer is not already in a gang
        if (dealerToGang[dealerId] != 0) revert AlreadyInGang();

        // Join the gang
        dealerToGang[dealerId] = gangId;
        memberRole[dealerId] = GangRole.MEMBER;

        // Add to member tracking
        memberIndex[dealerId] = gangMembers[gangId].length;
        gangMembers[gangId].push(dealerId);

        // Update member count
        unchecked { ++gangs[gangId].memberCount; }

        // Clear invitation
        delete invitations[dealerId];

        emit MemberJoined(gangId, dealerId);
    }

    /**
     * @notice Decline an invitation
     * @param dealerId Your dealer with pending invitation
     */
    function declineInvitation(uint256 dealerId)
        external
        onlyDealerOwner(dealerId)
    {
        Invitation memory invite = invitations[dealerId];

        // Check invitation exists
        if (invite.expiresAt == 0) revert NoInvitation();

        uint256 gangId = invite.gangId;

        // Clear invitation
        delete invitations[dealerId];

        emit InvitationCancelled(gangId, dealerId);
    }

    /**
     * @notice Cancel an invitation you sent (leader/officer only)
     * @param inviterId Your dealer who sent the invitation
     * @param inviteeId The dealer whose invitation to cancel
     */
    function cancelInvitation(uint256 inviterId, uint256 inviteeId)
        external
        onlyDealerOwner(inviterId)
    {
        // Check inviter has permission
        uint256 gangId = dealerToGang[inviterId];
        if (gangId == 0) revert NotInGang();

        GangRole role = memberRole[inviterId];
        if (role != GangRole.LEADER && role != GangRole.OFFICER) {
            revert NotLeaderOrOfficer();
        }

        // Check invitation exists for this gang
        Invitation memory invite = invitations[inviteeId];
        if (invite.gangId != gangId) revert NoInvitation();
        if (invite.expiresAt == 0) revert NoInvitation();

        // Clear invitation
        delete invitations[inviteeId];

        emit InvitationCancelled(gangId, inviteeId);
    }

    // =============================================================
    //                        MEMBER MANAGEMENT
    // =============================================================

    /**
     * @notice Leave the gang voluntarily
     * @param dealerId Your dealer who is leaving
     */
    function leaveGang(uint256 dealerId)
        external
        nonReentrant
        onlyDealerOwner(dealerId)
    {
        uint256 gangId = dealerToGang[dealerId];
        if (gangId == 0) revert NotInGang();

        // Leader cannot leave without transferring leadership or disbanding
        if (memberRole[dealerId] == GangRole.LEADER) {
            revert CannotLeaveAsLeader();
        }

        _removeFromGang(dealerId);

        emit MemberLeft(gangId, dealerId);
    }

    /**
     * @notice Kick a member from the gang (leader or officer only)
     * @param kickerId Your dealer (must be leader/officer)
     * @param kickeeId Dealer to kick
     */
    function kickMember(uint256 kickerId, uint256 kickeeId)
        external
        nonReentrant
        onlyDealerOwner(kickerId)
    {
        uint256 gangId = dealerToGang[kickerId];
        if (gangId == 0) revert NotInGang();

        // Check kicker has permission
        GangRole kickerRole = memberRole[kickerId];
        if (kickerRole != GangRole.LEADER && kickerRole != GangRole.OFFICER) {
            revert NotLeaderOrOfficer();
        }

        // Check kickee is in the same gang
        if (dealerToGang[kickeeId] != gangId) revert MemberNotInGang();

        // Cannot kick the leader
        GangRole kickeeRole = memberRole[kickeeId];
        if (kickeeRole == GangRole.LEADER) revert CannotKickLeader();

        // Officers cannot kick other officers
        if (kickerRole == GangRole.OFFICER && kickeeRole == GangRole.OFFICER) {
            revert CannotKickHigherRank();
        }

        _removeFromGang(kickeeId);

        emit MemberKicked(gangId, kickeeId, msg.sender);
    }

    /**
     * @notice Promote a member to officer (leader only)
     * @param leaderId Leader's dealer
     * @param memberId Member to promote
     */
    function promoteToOfficer(uint256 leaderId, uint256 memberId)
        external
        onlyDealerOwner(leaderId)
    {
        uint256 gangId = dealerToGang[leaderId];
        if (gangId == 0) revert NotInGang();

        // Only leader can promote
        if (memberRole[leaderId] != GangRole.LEADER) revert NotLeader();

        // Check member is in the same gang
        if (dealerToGang[memberId] != gangId) revert MemberNotInGang();

        // Must be a member (not already officer or leader)
        if (memberRole[memberId] != GangRole.MEMBER) revert NotGangMember();

        // Promote to officer
        memberRole[memberId] = GangRole.OFFICER;

        emit MemberPromoted(gangId, memberId, GangRole.OFFICER);
    }

    /**
     * @notice Demote an officer to member (leader only)
     * @param leaderId Leader's dealer
     * @param officerId Officer to demote
     */
    function demoteToMember(uint256 leaderId, uint256 officerId)
        external
        onlyDealerOwner(leaderId)
    {
        uint256 gangId = dealerToGang[leaderId];
        if (gangId == 0) revert NotInGang();

        // Only leader can demote
        if (memberRole[leaderId] != GangRole.LEADER) revert NotLeader();

        // Check officer is in the same gang
        if (dealerToGang[officerId] != gangId) revert MemberNotInGang();

        // Must be an officer
        if (memberRole[officerId] != GangRole.OFFICER) revert NotLeaderOrOfficer();

        // Demote to member
        memberRole[officerId] = GangRole.MEMBER;

        emit MemberDemoted(gangId, officerId, GangRole.MEMBER);
    }

    // =============================================================
    //                        LEADERSHIP FUNCTIONS
    // =============================================================

    /**
     * @notice Transfer leadership to another member (leader only)
     * @param currentLeaderId Current leader's dealer
     * @param newLeaderId New leader's dealer
     */
    function transferLeadership(uint256 currentLeaderId, uint256 newLeaderId)
        external
        onlyDealerOwner(currentLeaderId)
    {
        uint256 gangId = dealerToGang[currentLeaderId];
        if (gangId == 0) revert NotInGang();

        // Only leader can transfer
        if (memberRole[currentLeaderId] != GangRole.LEADER) revert NotLeader();

        // New leader must be in the same gang
        if (dealerToGang[newLeaderId] != gangId) revert MemberNotInGang();

        // Cannot transfer to self
        if (currentLeaderId == newLeaderId) revert NotGangMember();

        // Get new leader's current wallet
        address newLeaderWallet = dealersExeNFT.ownerOf(newLeaderId);

        // Update roles
        memberRole[currentLeaderId] = GangRole.MEMBER;  // Old leader becomes member
        memberRole[newLeaderId] = GangRole.LEADER;       // New leader

        // Update gang data
        gangs[gangId].leader = newLeaderWallet;
        gangs[gangId].leaderId = newLeaderId;

        emit LeaderTransferred(gangId, currentLeaderId, newLeaderId);
    }

    /**
     * @notice Disband the gang (leader only)
     * @param leaderId Leader's dealer
     */
    function disbandGang(uint256 leaderId)
        external
        nonReentrant
        onlyDealerOwner(leaderId)
    {
        uint256 gangId = dealerToGang[leaderId];
        if (gangId == 0) revert NotInGang();

        // Only leader can disband
        if (memberRole[leaderId] != GangRole.LEADER) revert NotLeader();

        Gang storage gang = gangs[gangId];
        if (!gang.isActive) revert GangNotActive();

        // Free name and tag
        gangNameTaken[_toLower(gang.name)] = false;
        gangTagTaken[_toLower(gang.tag)] = false;

        // Remove all members
        uint256[] memory members = gangMembers[gangId];
        for (uint256 i = 0; i < members.length; ) {
            uint256 memberId = members[i];
            dealerToGang[memberId] = 0;
            memberRole[memberId] = GangRole.NONE;
            delete memberIndex[memberId];
            unchecked { ++i; }
        }

        // Clear member array
        delete gangMembers[gangId];

        // Deactivate gang
        gang.isActive = false;
        gang.memberCount = 0;

        unchecked { --totalActiveGangs; }

        emit GangDisbanded(gangId);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get gang data
     * @param gangId The gang ID to query
     * @return The gang data
     */
    function getGang(uint256 gangId) external view returns (Gang memory) {
        return gangs[gangId];
    }

    /**
     * @notice Get a dealer's gang and role
     * @param dealerId The dealer ID to query
     * @return gangId The gang ID (0 if not in a gang)
     * @return role The dealer's role in the gang
     */
    function getDealerGang(uint256 dealerId)
        external
        view
        returns (uint256 gangId, GangRole role)
    {
        gangId = dealerToGang[dealerId];
        role = memberRole[dealerId];
    }

    /**
     * @notice Get all members of a gang
     * @param gangId The gang ID to query
     * @return memberIds Array of dealer IDs in the gang
     */
    function getGangMembers(uint256 gangId)
        external
        view
        returns (uint256[] memory memberIds)
    {
        return gangMembers[gangId];
    }

    /**
     * @notice Check if a dealer has a pending invitation
     * @param dealerId The dealer ID to query
     * @return True if the dealer has a valid invitation
     */
    function hasInvitation(uint256 dealerId) external view returns (bool) {
        return invitations[dealerId].expiresAt > block.timestamp;
    }

    /**
     * @notice Get invitation details for a dealer
     * @param dealerId The dealer ID to query
     * @return The invitation data
     */
    function getInvitation(uint256 dealerId)
        external
        view
        returns (Invitation memory)
    {
        return invitations[dealerId];
    }

    /**
     * @notice Check if a gang name is available
     * @param name The name to check
     * @return True if the name is available
     */
    function isGangNameAvailable(string calldata name)
        external
        view
        returns (bool)
    {
        if (!_validateName(name)) return false;
        return !gangNameTaken[_toLower(name)];
    }

    /**
     * @notice Check if a gang tag is available
     * @param tag The tag to check
     * @return True if the tag is available
     */
    function isGangTagAvailable(string calldata tag)
        external
        view
        returns (bool)
    {
        if (!_validateTag(tag)) return false;
        return !gangTagTaken[_toLower(tag)];
    }

    /**
     * @notice Get gang statistics
     * @return total Total gangs created
     * @return active Currently active gangs
     * @return fees Total creation fees collected
     */
    function getGangStats()
        external
        view
        returns (uint256 total, uint256 active, uint256 fees)
    {
        return (totalGangs, totalActiveGangs, totalCreationFees);
    }

    /**
     * @notice Get gang tag for a dealer (for NFT metadata)
     * @param dealerId The dealer ID to query
     * @return tag The gang tag (empty string if not in a gang)
     */
    function getDealerGangTag(uint256 dealerId)
        external
        view
        returns (string memory tag)
    {
        uint256 gangId = dealerToGang[dealerId];
        if (gangId == 0 || !gangs[gangId].isActive) {
            return "";
        }
        return gangs[gangId].tag;
    }

    // =============================================================
    //                        HELPER FUNCTIONS
    // =============================================================

    /**
     * @notice Validate gang name format
     * @param name The name to validate
     * @return True if valid
     */
    function _validateName(string calldata name) internal pure returns (bool) {
        bytes memory nameBytes = bytes(name);
        uint256 len = nameBytes.length;

        if (len < MIN_NAME_LENGTH || len > MAX_NAME_LENGTH) return false;

        // Check for alphanumeric and spaces only
        for (uint256 i = 0; i < len; ) {
            bytes1 char = nameBytes[i];
            bool isValid = (char >= 0x30 && char <= 0x39) ||  // 0-9
                          (char >= 0x41 && char <= 0x5A) ||  // A-Z
                          (char >= 0x61 && char <= 0x7A) ||  // a-z
                          char == 0x20;                       // space

            if (!isValid) return false;
            unchecked { ++i; }
        }

        return true;
    }

    /**
     * @notice Validate gang tag format
     * @param tag The tag to validate
     * @return True if valid
     */
    function _validateTag(string calldata tag) internal pure returns (bool) {
        bytes memory tagBytes = bytes(tag);
        uint256 len = tagBytes.length;

        if (len < MIN_TAG_LENGTH || len > MAX_TAG_LENGTH) return false;

        // Check for alphanumeric only (no spaces)
        for (uint256 i = 0; i < len; ) {
            bytes1 char = tagBytes[i];
            bool isValid = (char >= 0x30 && char <= 0x39) ||  // 0-9
                          (char >= 0x41 && char <= 0x5A) ||  // A-Z
                          (char >= 0x61 && char <= 0x7A);    // a-z

            if (!isValid) return false;
            unchecked { ++i; }
        }

        return true;
    }

    /**
     * @notice Convert string to lowercase for case-insensitive comparison
     * @param str The string to convert
     * @return The lowercase string
     */
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; ) {
            // Uppercase to lowercase
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
            unchecked { ++i; }
        }

        return string(bLower);
    }

    /**
     * @notice Remove a dealer from their gang
     * @param dealerId The dealer to remove
     */
    function _removeFromGang(uint256 dealerId) internal {
        uint256 gangId = dealerToGang[dealerId];
        if (gangId == 0) return;

        // Remove from member tracking
        uint256 index = memberIndex[dealerId];
        uint256[] storage members = gangMembers[gangId];
        uint256 lastIndex = members.length - 1;

        // Swap with last element if not already last
        if (index != lastIndex) {
            uint256 lastMemberId = members[lastIndex];
            members[index] = lastMemberId;
            memberIndex[lastMemberId] = index;
        }

        // Remove last element
        members.pop();
        delete memberIndex[dealerId];

        // Clear membership
        dealerToGang[dealerId] = 0;
        memberRole[dealerId] = GangRole.NONE;

        // Update count
        unchecked { --gangs[gangId].memberCount; }
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Updates the core dealers contract address
     * @param _dealersExeCore The new core dealers contract address
     */
    function setDealersExeCore(address _dealersExeCore) external onlyOwner {
        if (_dealersExeCore == address(0)) revert InvalidAddress();
        address old = address(dealersExeCore);
        dealersExeCore = IDealersExeCoreMinimal(_dealersExeCore);
        emit CoreContractUpdated(old, _dealersExeCore);
    }

    /**
     * @notice Updates the NFT contract address
     * @param _dealersExeNFT The new NFT contract address
     */
    function setDealersExeNFT(address _dealersExeNFT) external onlyOwner {
        if (_dealersExeNFT == address(0)) revert InvalidAddress();
        address old = address(dealersExeNFT);
        dealersExeNFT = IERC721Minimal(_dealersExeNFT);
        emit NFTContractUpdated(old, _dealersExeNFT);
    }

    /**
     * @notice Updates the payment handler contract address
     * @param _paymentHandler The new payment handler address
     */
    function setPaymentHandler(address _paymentHandler) external onlyOwner {
        if (_paymentHandler == address(0)) revert InvalidAddress();
        address old = address(paymentHandler);
        paymentHandler = IDEPaymentHandler(_paymentHandler);
        emit PaymentHandlerUpdated(old, _paymentHandler);
    }

    /**
     * @notice Emergency function to recover stuck ETH
     * @dev Only callable by owner in case of stuck funds
     * @param to Address to send ETH to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientPayment();
        _safeTransferETH(to, amount);
    }

    /**
     * @notice Get the current contract balance
     * @return The ETH balance of this contract
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Allows the contract to receive ETH
     */
    receive() external payable {}
}
