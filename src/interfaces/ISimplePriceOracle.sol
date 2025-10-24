// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISimplePriceOracle {
    event PriceUpdated(uint256 newPrice);

    function getPrice() external view returns (uint256);
    function updatePrice(uint256 _price) external;
}
