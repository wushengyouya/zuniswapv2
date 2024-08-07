// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {ERC20} from "solmate/tokens/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_, 18) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
