// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockEthOracle {
    uint256 private ethPrice;

    event PriceUpdated(uint256 newPrice);

    constructor() {
        ethPrice = 2000e18; // Initial ETH price of $2000 with 18 decimals
    }

    // Returns the latest ETH/USD price with 18 decimal places
    function getPrice() external view returns (uint256) {
        return ethPrice;
    }

    // Allows owner to update the ETH price
    function updatePrice(uint256 _newPrice) external {
        ethPrice = _newPrice;
        emit PriceUpdated(_newPrice);
    }
}
