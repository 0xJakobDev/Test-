// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPerpPositionManager {
    struct Position {
        address trader;
        bool isLong;
        uint256 size;
        uint256 margin;
        uint256 leverage;
        uint256 entryPrice;
        bool isOpen;
    }

    event PositionOpened(
        uint256 indexed positionId,
        address indexed trader,
        bool isLong,
        uint256 size,
        uint256 margin,
        uint256 leverage,
        uint256 entryPrice
    );

    event PositionClosed(uint256 indexed positionId, address indexed trader, uint256 pnl);

    event PositionLiquidated(uint256 indexed positionId, address indexed trader, uint256 pnl);

    function openPosition(bool isLong, uint256 margin, uint256 leverage) external returns (uint256 positionId);

    function closePosition(uint256 positionId) external;

    function liquidatePosition(uint256 positionId) external;

    function getPosition(uint256 positionId) external view returns (Position memory);

    function isLiquidatable(uint256 positionId) external view returns (bool);
}
