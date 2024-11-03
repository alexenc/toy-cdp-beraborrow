// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockEthOracle {
    uint256 private ethPrice;
    address private owner;

    error NotOwner();

    event PriceUpdated(uint256 newPrice);

    constructor() {
        ethPrice = 2000e18; // Initial ETH price of $2000 with 18 decimals
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // Returns the latest ETH/USD price with 18 decimal places
    function getPrice() external view returns (uint256) {
        return ethPrice;
    }

    // Allows owner to update the ETH price
    function updatePrice(uint256 _newPrice) external onlyOwner {
        ethPrice = _newPrice;
        emit PriceUpdated(_newPrice);
    }
}
