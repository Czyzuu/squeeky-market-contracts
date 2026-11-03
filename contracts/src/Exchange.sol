// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";
import {DistanceOracle} from "./DistanceOracle.sol";

contract Exchange is EIP712, ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct Order { address maker; uint256 tokenId; uint8 side; uint256 price; uint256 size; uint256 expiry; uint256 nonce; uint256 feeRateBps; uint8 timeInForce; }
    struct Match { Order maker; bytes makerSig; Order taker; bytes takerSig; uint256 amount; }
    bytes32 public constant ORDER_TYPEHASH = keccak256("Order(address maker,uint256 tokenId,uint8 side,uint256 price,uint256 size,uint256 expiry,uint256 nonce,uint256 feeRateBps,uint8 timeInForce)");
    ConditionalTokens public immutable ctf;
    DistanceOracle public immutable oracle;
    IERC20 public immutable collateral;
    address public immutable operator;
    address public immutable guardian;
    address public immutable feeRecipient;
    bool public paused;
    mapping(bytes32 => uint256) public filled;
    mapping(bytes32 => bool) public cancelled;
    mapping(address => mapping(uint256 => bool)) public cancelledNonce;
    mapping(address => uint256) public minNonce;
    event Matched(bytes32 indexed makerHash, bytes32 indexed takerHash, uint256 amount, uint8 matchType);
    constructor(ConditionalTokens tokens, DistanceOracle source, address op, address guard, address fees) EIP712("Wheel Markets", "1") {
        require(op != address(0) && guard != address(0) && fees != address(0), "Bad config");
        ctf = tokens; collateral = tokens.collateral(); oracle = source; operator = op; guardian = guard; feeRecipient = fees;
        collateral.forceApprove(address(tokens), type(uint256).max);
        tokens.setApprovalForAll(address(this), true);
    }
    function hashOrder(Order calldata o) public view returns (bytes32) { return _hashTypedDataV4(keccak256(abi.encode(ORDER_TYPEHASH, o))); }
    function cancel(Order calldata o) external { require(o.maker == msg.sender, "Not maker"); cancelled[hashOrder(o)] = true; }
    function cancelNonce(uint256 nonce) external { cancelledNonce[msg.sender][nonce] = true; }
    function invalidateNonces(uint256 next) external { require(next > minNonce[msg.sender], "Nonce must increase"); minNonce[msg.sender] = next; }
    function setPaused(bool value) external { require(msg.sender == guardian, "Not guardian"); paused = value; }
    function _check(Order calldata o, bytes calldata sig, uint256 amount) internal returns (bytes32 h) {
        h = hashOrder(o);
        require(o.side <= 1 && o.timeInForce <= 4 && o.price >= 10_000 && o.price <= 990_000 && o.price % 10_000 == 0 && o.feeRateBps <= 100, "Bad order");
        require(amount > 0 && o.expiry > block.timestamp && o.nonce >= minNonce[o.maker] && !cancelledNonce[o.maker][o.nonce] && !cancelled[h], "Inactive order");
        require(ECDSA.recover(h, sig) == o.maker && filled[h] + amount <= o.size, "Signature or fill");
        filled[h] += amount;
    }
    function matchOrders(Match[] calldata matches) external nonReentrant {
        require(msg.sender == operator && !paused, "Unavailable");
        for (uint256 i; i < matches.length; i++) _match(matches[i]);
        for (uint256 i; i < matches.length; i++) {
            _settleTimeInForce(matches[i].maker); _settleTimeInForce(matches[i].taker);
            require(matches[i].taker.timeInForce != 4, "Post-only cannot take");
        }
    }
    /// FOK and IOC are signed by the order owner, so they bind whichever slot the operator puts the order in.
    function _settleTimeInForce(Order calldata o) internal {
        bytes32 h = hashOrder(o);
        if (o.timeInForce == 2) require(filled[h] == o.size, "FOK incomplete");
        if (o.timeInForce == 3) cancelled[h] = true;
    }
    function _match(Match calldata m) internal {
        Order calldata a = m.maker; Order calldata b = m.taker;
        // Prices are whole cents, so amounts in steps of 100 keep every notional exact.
        require(a.maker != b.maker && m.amount % 100 == 0, "Self trade or amount");
        bytes32 ah = _check(a, m.makerSig, m.amount); bytes32 bh = _check(b, m.takerSig, m.amount);
        (bytes32 market, uint256 mask) = ctf.positions(a.tokenId);
        (bytes32 otherMarket, uint256 otherMask) = ctf.positions(b.tokenId);
        require(market != bytes32(0) && market == otherMarket && oracle.isTradable(market), "Market closed");
        uint256 av = m.amount * a.price / 1e6; uint256 bv; uint8 kind;
        if (a.tokenId == b.tokenId) {
            require(a.side != b.side && (a.side == 0 ? a.price >= b.price : b.price >= a.price), "Not crossing");
            Order calldata buy = a.side == 0 ? a : b; Order calldata sell = a.side == 1 ? a : b;
            ctf.safeTransferFrom(sell.maker, buy.maker, a.tokenId, m.amount, "");
            collateral.safeTransferFrom(buy.maker, sell.maker, av); bv = av;
        } else {
            require((mask ^ otherMask) == ctf.fullMask(market) && a.side == b.side, "Not complements");
            bv = m.amount - av;
            if (a.side == 0) {
                require(a.price + b.price >= 1e6, "Not crossing"); kind = 1;
                collateral.safeTransferFrom(a.maker, address(this), av); collateral.safeTransferFrom(b.maker, address(this), bv);
                ctf.splitPosition(market, mask, m.amount);
                ctf.safeTransferFrom(address(this), a.maker, a.tokenId, m.amount, "");
                ctf.safeTransferFrom(address(this), b.maker, b.tokenId, m.amount, "");
            } else {
                require(a.price + b.price <= 1e6, "Not crossing"); kind = 2;
                ctf.safeTransferFrom(a.maker, address(this), a.tokenId, m.amount, "");
                ctf.safeTransferFrom(b.maker, address(this), b.tokenId, m.amount, "");
                ctf.mergePositions(market, mask, m.amount);
                collateral.safeTransfer(a.maker, av); collateral.safeTransfer(b.maker, bv);
            }
        }
        // Both parties sign their fee cap; this v1 charges exactly that cap on execution notional.
        collateral.safeTransferFrom(a.maker, feeRecipient, av * a.feeRateBps / 10_000);
        collateral.safeTransferFrom(b.maker, feeRecipient, bv * b.feeRateBps / 10_000);
        emit Matched(ah, bh, m.amount, kind);
    }
}
