// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FakeUSD is ERC20 {

    uint256 public faucetAmount = 1000 * 10 ** 18; 

    constructor() ERC20("Fake USD", "FUSD") {}

    function mint() external returns (bool) {
        _mint(msg.sender, faucetAmount);
        return true;
    }
}