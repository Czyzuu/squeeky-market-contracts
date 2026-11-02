// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";

contract NegRiskAdapter is ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;
    ConditionalTokens public immutable ctf;
    constructor(ConditionalTokens tokens) { ctf = tokens; }
    /// NO on every bucket except target = YES(target) + (N-2) complete sets.
    /// Returning that collateral is necessary to preserve value for N > 2.
    function convert(bytes32 market, uint8 target, uint256 amount) external nonReentrant {
        (uint8 n,,) = ctf.conditions(market);
        require(n > 2 && target < n && amount > 0, "Bad bucket set");
        uint256 full = ctf.fullMask(market);
        for (uint256 i; i < n; i++) if (i != target) {
            uint256 mask = full ^ (1 << i);
            ctf.safeTransferFrom(msg.sender, address(this), ctf.tokenId(market, mask), amount, "");
            ctf.refine(market, mask, amount);
        }
        ctf.mergeCompleteSet(market, amount * (n - 2));
        ctf.safeTransferFrom(address(this), msg.sender, ctf.tokenId(market, 1 << target), amount, "");
        ctf.collateral().safeTransfer(msg.sender, amount * (n - 2));
    }
}
