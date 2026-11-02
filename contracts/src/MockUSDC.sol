// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    mapping(address => uint256) public lastFaucet;
    constructor() ERC20("Wheel test dollars (no value)", "tUSDC") {
        require(block.chainid == 31337 || block.chainid == 11155111, "Testnet only");
    }
    function decimals() public pure override returns (uint8) { return 6; }
    function faucet() external {
        require(block.timestamp >= lastFaucet[msg.sender] + 1 hours, "Try again in one hour");
        lastFaucet[msg.sender] = block.timestamp;
        _mint(msg.sender, 1000e6);
    }
}
