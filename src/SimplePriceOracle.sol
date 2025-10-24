// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/ISimplePriceOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SimplePriceOracle is ISimplePriceOracle, Ownable {
    uint256 private price;

    constructor() Ownable(msg.sender) {
        price = 1000e18; // Initial price of 1000 USD
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

    function updatePrice(uint256 _price) external onlyOwner {
        require(_price > 0, "Invalid price");
        price = _price;
        emit PriceUpdated(_price);
    }
}
