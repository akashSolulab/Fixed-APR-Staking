//SPDX-License-Identifier: Undefined;

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakedStableCoin is ERC20 {
    constructor() ERC20("StableERC20Token", "SERC") {
        _mint(msg.sender, 999999999999999999000000000000000000 ether);
    }
}