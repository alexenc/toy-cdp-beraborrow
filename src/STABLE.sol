// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * This contract its meant to be controlled by toycdp engine
 * Erc20 burnable token that is meant to be the Stable coin of the system
 */
contract STABLE is ERC20Burnable, Ownable {
    error STABLE_NonZeroAmount();
    error STABLE_BurnAmountExceedsBalance();
    error STABLE_NoZeroAddress();
    constructor() ERC20("STABLE", "STBL") Ownable(msg.sender) {}

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) revert STABLE_NoZeroAddress();
        if (_amount <= 0) {
            revert STABLE_NonZeroAmount();
        }
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert STABLE_NonZeroAmount();
        }
        if (balance < _amount) {
            revert STABLE_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
