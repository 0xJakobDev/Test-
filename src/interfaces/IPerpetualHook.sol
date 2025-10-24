// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPerpetualHook {
    struct PoolState {
        uint256 totalLiquidity;
        uint256 totalOpenInterest;
        uint256 maxLeverage;
    }

    event OpenInterestChanged(uint256 newOpenInterest);
    event LeverageLimitUpdated(uint256 newMaxLeverage);

    function getPoolState() external view returns (PoolState memory);
    function updateOpenInterest(uint256 amount, bool increase) external;
    function calculateMaxLeverage() external view returns (uint256);
    function validateTrade(uint256 amount, uint256 leverage) external view returns (bool);
}
