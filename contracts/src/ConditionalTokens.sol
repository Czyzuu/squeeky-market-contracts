// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// Minimal single-collateral conditional tokens. Amounts use collateral's six decimals.
/// Positions are bitmasks of mutually exclusive outcomes; no nested conditions.
contract ConditionalTokens is ERC1155, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable collateral;
    address public immutable admin;
    address public oracle;
    struct Condition { uint8 outcomes; bool resolved; uint256 denominator; }
    struct Position { bytes32 market; uint256 mask; }
    mapping(bytes32 => Condition) public conditions;
    mapping(bytes32 => mapping(uint256 => uint256)) public payout;
    mapping(uint256 => Position) public positions;
    mapping(bytes32 => uint256) public locked;
    mapping(address => uint256) public claimable;
    event Prepared(bytes32 indexed market, uint8 outcomes);
    event Resolved(bytes32 indexed market, uint256[] numerators);
    event Redeemed(address indexed owner, bytes32 indexed market, uint256 amount);
    constructor(IERC20 token) ERC1155("") { collateral = token; admin = msg.sender; }
    function setOracle(address value) external { require(msg.sender == admin && oracle == address(0) && value != address(0), "One-time setup"); oracle = value; }
    function prepare(bytes32 market, uint8 outcomes) external {
        require(msg.sender == oracle && outcomes >= 2 && outcomes <= 8 && conditions[market].outcomes == 0, "Bad condition");
        conditions[market].outcomes = outcomes;
        // Register singletons and their complements so the exchange can mint them before any split.
        uint256 full = fullMask(market);
        for (uint256 i; i < outcomes; i++) { _id(market, 1 << i); _id(market, full ^ (1 << i)); }
        emit Prepared(market, outcomes);
    }
    function fullMask(bytes32 market) public view returns (uint256) { return (1 << conditions[market].outcomes) - 1; }
    /// Permissionless registration for union positions (e.g. bucket ranges) not covered by prepare.
    function registerPosition(bytes32 market, uint256 mask) external { require(mask > 0 && mask < fullMask(market), "Bad mask"); _id(market, mask); }
    function tokenId(bytes32 market, uint256 mask) public pure returns (uint256) { return uint256(keccak256(abi.encode(market, mask))); }
    function _id(bytes32 market, uint256 mask) internal returns (uint256 id) {
        id = tokenId(market, mask); positions[id] = Position(market, mask);
    }
    function splitPosition(bytes32 market, uint256 mask, uint256 amount) external nonReentrant {
        uint256 full = fullMask(market);
        require(!conditions[market].resolved && mask > 0 && mask < full && amount > 0, "Bad split");
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        locked[market] += amount;
        _mint(msg.sender, _id(market, mask), amount, "");
        _mint(msg.sender, _id(market, full ^ mask), amount, "");
    }
    function mergePositions(bytes32 market, uint256 mask, uint256 amount) external nonReentrant {
        uint256 full = fullMask(market);
        require(mask > 0 && mask < full && amount > 0, "Bad merge");
        _burn(msg.sender, tokenId(market, mask), amount);
        _burn(msg.sender, tokenId(market, full ^ mask), amount);
        locked[market] -= amount;
        collateral.safeTransfer(msg.sender, amount);
    }
    /// Refine a union position into its singleton constituents, preserving total payout.
    function refine(bytes32 market, uint256 mask, uint256 amount) external nonReentrant {
        require(mask > 0 && mask < fullMask(market), "Bad partition");
        _burn(msg.sender, tokenId(market, mask), amount);
        for (uint256 i; i < conditions[market].outcomes; i++) {
            uint256 bit = 1 << i;
            if ((mask & bit) != 0) _mint(msg.sender, _id(market, bit), amount, "");
        }
    }
    function mergeCompleteSet(bytes32 market, uint256 amount) external nonReentrant {
        require(conditions[market].outcomes >= 2 && amount > 0, "Unknown condition");
        for (uint256 i; i < conditions[market].outcomes; i++) _burn(msg.sender, tokenId(market, 1 << i), amount);
        locked[market] -= amount;
        collateral.safeTransfer(msg.sender, amount);
    }
    function reportPayouts(bytes32 market, uint256[] calldata numerators) external {
        Condition storage c = conditions[market];
        require(msg.sender == oracle && !c.resolved && c.outcomes >= 2 && numerators.length == c.outcomes, "Bad resolution");
        uint256 sum;
        for (uint256 i; i < numerators.length; i++) { payout[market][i] = numerators[i]; sum += numerators[i]; }
        require(sum > 0, "Empty payout");
        c.resolved = true; c.denominator = sum;
        emit Resolved(market, numerators);
    }
    function redeemPositions(bytes32 market, uint256[] calldata masks) external nonReentrant {
        Condition memory c = conditions[market]; require(c.resolved, "Unresolved");
        uint256 weighted;
        for (uint256 j; j < masks.length; j++) {
            uint256 mask = masks[j]; require(mask > 0 && mask < fullMask(market), "Bad mask");
            uint256 id = tokenId(market, mask); uint256 amount = balanceOf(msg.sender, id); uint256 num;
            for (uint256 i; i < c.outcomes; i++) if ((mask & (1 << i)) != 0) num += payout[market][i];
            _burn(msg.sender, id, amount); weighted += amount * num;
        }
        uint256 value = weighted / c.denominator;
        locked[market] -= value; claimable[msg.sender] += value;
        emit Redeemed(msg.sender, market, value);
    }
    function withdraw() external nonReentrant {
        uint256 value = claimable[msg.sender]; claimable[msg.sender] = 0;
        collateral.safeTransfer(msg.sender, value);
    }
}
