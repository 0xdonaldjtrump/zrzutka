// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    Zrzutka — all-or-nothing fundraising in USDC on Base.

    - Anyone can start a campaign with a goal (USDC) and a deadline.
    - Backers contribute USDC (approve + contribute, or one signature with EIP-2612 permit) and can leave a message.
    - Goal reached  -> the creator claims the funds (minus a small platform fee, default 1%).
    - Goal missed / campaign cancelled -> every backer gets a full refund.
    - Backers of successful campaigns can mint a soulbound "Supporter" NFT badge (on-chain SVG).
    - Social layer: upvotes, follows, creator updates, profile names, reports.

    The contract only ever holds USDC of live campaigns; it never takes custody of anything else.
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Zrzutka is ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status { Active, Claimed, Cancelled }

    struct Campaign {
        address creator;
        uint64 createdAt;
        uint64 deadline;
        Status status;
        bool extended;
        bool goalReachedEarly; // creator closed the campaign after reaching the goal
        uint256 goal;          // USDC, 6 decimals
        uint256 raised;
        uint256 refunded;
        uint32 backers;
        uint32 upvotes;
        uint32 followers;
        uint32 reports;
        string title;
        string description;
        string link;
    }

    struct Backing {
        address backer;
        uint64 time;
        uint256 amount;
        string message;
    }

    struct Update {
        uint64 time;
        string text;
    }

    IERC20 public immutable usdc;
    address public owner;
    uint16 public feeBps = 100;            // 1% of successful campaigns
    uint256 public minGoal = 1e6;          // $1
    uint32 public maxDurationDays = 180;
    bool public paused;

    Campaign[] private campaigns;          // id = index + 1
    mapping(uint256 => Backing[]) private backings;
    mapping(uint256 => Update[]) private updates;
    mapping(uint256 => mapping(address => uint256)) public contributionOf;
    mapping(uint256 => mapping(address => bool)) public refundedTo;
    mapping(uint256 => mapping(address => bool)) public upvoted;
    mapping(uint256 => mapping(address => bool)) public following;
    mapping(uint256 => mapping(address => bool)) public reported;
    mapping(uint256 => mapping(address => uint256)) public badgeOf;   // campaign => backer => tokenId
    mapping(uint256 => uint256) public badgeCampaign;                // tokenId => campaign
    mapping(address => uint256[]) private createdBy;
    mapping(address => uint256[]) private backedBy;
    mapping(address => string) public profileName;
    uint256 public badgesMinted;
    uint256 public totalRaised;
    uint256 public totalFees;

    event CampaignCreated(uint256 indexed id, address indexed creator, uint256 goal, uint64 deadline, string title);
    event CampaignEdited(uint256 indexed id);
    event UpdatePosted(uint256 indexed id, uint256 index);
    event Contributed(uint256 indexed id, address indexed backer, uint256 amount, string message);
    event Claimed(uint256 indexed id, uint256 toCreator, uint256 fee);
    event Cancelled(uint256 indexed id, bool byAdmin);
    event Refunded(uint256 indexed id, address indexed backer, uint256 amount);
    event DeadlineExtended(uint256 indexed id, uint64 deadline);
    event Upvoted(uint256 indexed id, address indexed who);
    event Followed(uint256 indexed id, address indexed who, bool following);
    event Reported(uint256 indexed id, address indexed who, string reason);
    event BadgeMinted(uint256 indexed id, address indexed backer, uint256 tokenId);
    event ProfileSet(address indexed who, string name);

    error NotOwner();
    error NotCreator();
    error Paused();
    error BadInput();
    error UnknownCampaign();
    error NotActive();
    error Ended();
    error NotEnded();
    error GoalNotReached();
    error GoalReached();
    error NothingToRefund();
    error AlreadyDone();
    error NotEligible();
    error Soulbound();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _usdc) ERC721("Zrzutka Supporter", "ZRZUT") {
        usdc = IERC20(_usdc);
        owner = msg.sender;
    }

    // =====================================================================
    //                              CREATORS
    // =====================================================================

    function createCampaign(
        string calldata title,
        string calldata description,
        string calldata link,
        uint256 goal,
        uint32 durationDays
    ) external returns (uint256 id) {
        if (paused) revert Paused();
        uint256 tl = bytes(title).length;
        if (tl == 0 || tl > 80 || bytes(description).length > 1000 || bytes(link).length > 200) revert BadInput();
        if (goal < minGoal || durationDays == 0 || durationDays > maxDurationDays) revert BadInput();

        Campaign storage c = campaigns.push();
        c.creator = msg.sender;
        c.createdAt = uint64(block.timestamp);
        c.deadline = uint64(block.timestamp + uint256(durationDays) * 1 days);
        c.goal = goal;
        c.title = title;
        c.description = description;
        c.link = link;
        id = campaigns.length;
        createdBy[msg.sender].push(id);
        emit CampaignCreated(id, msg.sender, goal, c.deadline, title);
    }

    function editCampaign(uint256 id, string calldata description, string calldata link) external {
        Campaign storage c = _creatorActive(id);
        if (bytes(description).length > 1000 || bytes(link).length > 200) revert BadInput();
        c.description = description;
        c.link = link;
        emit CampaignEdited(id);
    }

    function postUpdate(uint256 id, string calldata text) external {
        Campaign storage c = _campaign(id);
        if (msg.sender != c.creator) revert NotCreator();
        uint256 l = bytes(text).length;
        if (l == 0 || l > 500) revert BadInput();
        updates[id].push(Update(uint64(block.timestamp), text));
        emit UpdatePosted(id, updates[id].length - 1);
    }

    /// @notice One-time extension (max +30 days) while the goal is not reached yet.
    function extendDeadline(uint256 id, uint32 extraDays) external {
        Campaign storage c = _creatorActive(id);
        if (c.extended || extraDays == 0 || extraDays > 30) revert BadInput();
        if (block.timestamp >= c.deadline) revert Ended();
        if (c.raised >= c.goal) revert GoalReached();
        c.extended = true;
        c.deadline += uint64(uint256(extraDays) * 1 days);
        emit DeadlineExtended(id, c.deadline);
    }

    /// @notice Goal reached -> creator receives the funds (minus the platform fee). Works before or after the deadline.
    function claim(uint256 id) external nonReentrant {
        Campaign storage c = _creatorActive(id);
        if (c.raised < c.goal) revert GoalNotReached();
        if (block.timestamp < c.deadline) c.goalReachedEarly = true;
        c.status = Status.Claimed;
        uint256 fee = (c.raised * feeBps) / 10_000;
        uint256 toCreator = c.raised - fee;
        totalFees += fee;
        if (fee > 0) usdc.safeTransfer(owner, fee);
        usdc.safeTransfer(c.creator, toCreator);
        emit Claimed(id, toCreator, fee);
    }

    function cancel(uint256 id) external {
        Campaign storage c = _creatorActive(id);
        c.status = Status.Cancelled;
        emit Cancelled(id, false);
    }

    // =====================================================================
    //                              BACKERS
    // =====================================================================

    function contribute(uint256 id, uint256 amount, string calldata message) external nonReentrant {
        _contribute(id, amount, message);
    }

    /// @notice Contribute with a single signature (EIP-2612 permit) instead of approve + contribute.
    function contributeWithPermit(
        uint256 id,
        uint256 amount,
        string calldata message,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        // If the permit was front-run, the allowance is already there and we simply continue.
        try IERC20Permit(address(usdc)).permit(msg.sender, address(this), amount, permitDeadline, v, r, s) {} catch {}
        _contribute(id, amount, message);
    }

    /// @notice Full refund when the campaign failed (deadline passed below goal) or was cancelled.
    function refund(uint256 id) external nonReentrant {
        Campaign storage c = _campaign(id);
        bool failed = c.status == Status.Active && block.timestamp >= c.deadline && c.raised < c.goal;
        if (!(failed || c.status == Status.Cancelled)) revert NotEligible();
        uint256 amount = contributionOf[id][msg.sender];
        if (amount == 0 || refundedTo[id][msg.sender]) revert NothingToRefund();
        refundedTo[id][msg.sender] = true;
        c.refunded += amount;
        usdc.safeTransfer(msg.sender, amount);
        emit Refunded(id, msg.sender, amount);
    }

    /// @notice Backers of a successful (claimed) campaign can mint one soulbound supporter badge.
    function mintBadge(uint256 id) external {
        Campaign storage c = _campaign(id);
        if (c.status != Status.Claimed || contributionOf[id][msg.sender] == 0) revert NotEligible();
        if (badgeOf[id][msg.sender] != 0) revert AlreadyDone();
        uint256 tokenId = ++badgesMinted;
        badgeOf[id][msg.sender] = tokenId;
        badgeCampaign[tokenId] = id;
        _mint(msg.sender, tokenId);
        emit BadgeMinted(id, msg.sender, tokenId);
    }

    // =====================================================================
    //                              SOCIAL
    // =====================================================================

    function upvote(uint256 id) external {
        Campaign storage c = _campaign(id);
        if (upvoted[id][msg.sender]) revert AlreadyDone();
        upvoted[id][msg.sender] = true;
        c.upvotes += 1;
        emit Upvoted(id, msg.sender);
    }

    function setFollow(uint256 id, bool on) external {
        Campaign storage c = _campaign(id);
        if (following[id][msg.sender] == on) revert AlreadyDone();
        following[id][msg.sender] = on;
        if (on) c.followers += 1; else c.followers -= 1;
        emit Followed(id, msg.sender, on);
    }

    function report(uint256 id, string calldata reason) external {
        Campaign storage c = _campaign(id);
        if (reported[id][msg.sender]) revert AlreadyDone();
        if (bytes(reason).length > 200) revert BadInput();
        reported[id][msg.sender] = true;
        c.reports += 1;
        emit Reported(id, msg.sender, reason);
    }

    function setProfileName(string calldata name) external {
        uint256 l = bytes(name).length;
        if (l == 0 || l > 32) revert BadInput();
        profileName[msg.sender] = name;
        emit ProfileSet(msg.sender, name);
    }

    // =====================================================================
    //                              READS
    // =====================================================================

    function campaignsCount() external view returns (uint256) {
        return campaigns.length;
    }

    function getCampaign(uint256 id) external view returns (Campaign memory) {
        return _campaign(id);
    }

    /// @notice Newest first.
    function getCampaigns(uint256 offset, uint256 limit) external view returns (uint256[] memory ids, Campaign[] memory list) {
        uint256 n = campaigns.length;
        if (offset >= n) return (new uint256[](0), new Campaign[](0));
        uint256 count = n - offset < limit ? n - offset : limit;
        ids = new uint256[](count);
        list = new Campaign[](count);
        for (uint256 i; i < count; i++) {
            uint256 id = n - offset - i;
            ids[i] = id;
            list[i] = campaigns[id - 1];
        }
    }

    function getBackings(uint256 id, uint256 offset, uint256 limit) external view returns (Backing[] memory list, uint256 total) {
        Backing[] storage all = backings[id];
        total = all.length;
        if (offset >= total) return (new Backing[](0), total);
        uint256 count = total - offset < limit ? total - offset : limit;
        list = new Backing[](count);
        for (uint256 i; i < count; i++) list[i] = all[total - 1 - offset - i]; // newest first
    }

    function getUpdates(uint256 id) external view returns (Update[] memory) {
        return updates[id];
    }

    function campaignsCreatedBy(address who) external view returns (uint256[] memory) {
        return createdBy[who];
    }

    function campaignsBackedBy(address who) external view returns (uint256[] memory) {
        return backedBy[who];
    }

    function stats() external view returns (uint256 campaigns_, uint256 raised_, uint256 fees_, uint256 badges_) {
        return (campaigns.length, totalRaised, totalFees, badgesMinted);
    }

    /// @notice On-chain SVG badge.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 id = badgeCampaign[tokenId];
        Campaign storage c = campaigns[id - 1];
        string memory idStr = Strings.toString(id);
        string memory title = _escape(c.title);
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0052ff"/><stop offset="1" stop-color="#00c2ff"/></linearGradient></defs>',
            '<rect width="400" height="400" rx="40" fill="url(#g)"/><circle cx="200" cy="150" r="70" fill="none" stroke="#fff" stroke-width="12"/>',
            '<path d="M170 150l22 22 42-46" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>',
            '<text x="200" y="270" font-family="Arial" font-size="28" font-weight="700" fill="#fff" text-anchor="middle">SUPPORTER</text>',
            '<text x="200" y="310" font-family="Arial" font-size="16" fill="#fff" text-anchor="middle">', title, '</text>',
            '<text x="200" y="350" font-family="Arial" font-size="14" fill="#dbe7ff" text-anchor="middle">Zrzutka #', idStr, ' on Base</text></svg>'
        );
        string memory json = string.concat(
            '{"name":"Zrzutka Supporter #', Strings.toString(tokenId),
            '","description":"Backed a successful all-or-nothing campaign on Base: ', title,
            '","attributes":[{"trait_type":"Campaign","value":', idStr, '}],"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)), '"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // =====================================================================
    //                              ADMIN
    // =====================================================================

    /// @notice Stop a scam campaign: it becomes cancelled and every backer can take a refund.
    function adminCancel(uint256 id) external onlyOwner {
        Campaign storage c = _campaign(id);
        if (c.status != Status.Active) revert NotActive();
        c.status = Status.Cancelled;
        emit Cancelled(id, true);
    }

    function setFee(uint16 bps) external onlyOwner {
        if (bps > 500) revert BadInput(); // max 5%
        feeBps = bps;
    }

    function setLimits(uint256 _minGoal, uint32 _maxDurationDays) external onlyOwner {
        if (_minGoal == 0 || _maxDurationDays == 0 || _maxDurationDays > 365) revert BadInput();
        minGoal = _minGoal;
        maxDurationDays = _maxDurationDays;
    }

    function setPaused(bool value) external onlyOwner {
        paused = value; // blocks new campaigns and contributions; refunds and claims always work
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert BadInput();
        owner = newOwner;
    }

    // =====================================================================
    //                              INTERNAL
    // =====================================================================

    function _contribute(uint256 id, uint256 amount, string calldata message) private {
        if (paused) revert Paused();
        Campaign storage c = _campaign(id);
        if (c.status != Status.Active) revert NotActive();
        if (block.timestamp >= c.deadline) revert Ended();
        if (amount == 0 || bytes(message).length > 200) revert BadInput();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        if (contributionOf[id][msg.sender] == 0) {
            c.backers += 1;
            backedBy[msg.sender].push(id);
        }
        contributionOf[id][msg.sender] += amount;
        c.raised += amount;
        totalRaised += amount;
        backings[id].push(Backing(msg.sender, uint64(block.timestamp), amount, message));
        emit Contributed(id, msg.sender, amount, message);
    }

    function _campaign(uint256 id) private view returns (Campaign storage) {
        if (id == 0 || id > campaigns.length) revert UnknownCampaign();
        return campaigns[id - 1];
    }

    function _creatorActive(uint256 id) private view returns (Campaign storage c) {
        c = _campaign(id);
        if (msg.sender != c.creator) revert NotCreator();
        if (c.status != Status.Active) revert NotActive();
    }

    /// @dev Soulbound: badges can be minted but never transferred.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function _escape(string memory s) private pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length);
        for (uint256 i; i < b.length; i++) {
            bytes1 ch = b[i];
            out[i] = (ch == '"' || ch == "<" || ch == ">" || ch == "&" || ch == "\\") ? bytes1("'") : ch;
        }
        return string(out);
    }
}
