// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IPerpPositionManager.sol";
import "./interfaces/IPerpetualHook.sol";
import "./interfaces/ISimplePriceOracle.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PerpPositionManager is IPerpPositionManager, ReentrancyGuard, Ownable {
    // Constants
    uint256 private constant MAINTENANCE_MARGIN_BPS = 500; // 5%
    uint256 private constant MAX_BPS = 10000;

    // Dependencies
    IPerpetualHook public immutable perpetualHook;
    ISimplePriceOracle public immutable priceOracle;

    // State
    uint256 public nextPositionId;
    mapping(uint256 => Position) public positions;

    constructor(address _perpetualHook, address _priceOracle) Ownable(msg.sender) {
        perpetualHook = IPerpetualHook(_perpetualHook);
        priceOracle = ISimplePriceOracle(_priceOracle);
        nextPositionId = 1;
    }

    function openPosition(bool isLong, uint256 margin, uint256 leverage)
        external
        nonReentrant
        returns (uint256 positionId)
    {
        require(margin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 10, "Invalid leverage");

        // Validate trade with hook
        require(perpetualHook.validateTrade(margin, leverage), "Trade validation failed");

        // Calculate position size
        uint256 size = margin * leverage;
        uint256 entryPrice = priceOracle.getPrice();

        // Create position
        positionId = nextPositionId++;
        positions[positionId] = Position({
            trader: msg.sender,
            isLong: isLong,
            size: size,
            margin: margin,
            leverage: leverage,
            entryPrice: entryPrice,
            isOpen: true
        });

        // Update open interest
        perpetualHook.updateOpenInterest(size, true);

        emit PositionOpened(positionId, msg.sender, isLong, size, margin, leverage, entryPrice);
    }

    function closePosition(uint256 positionId) external nonReentrant {
        Position storage position = positions[positionId];
        require(position.isOpen, "Position already closed");
        require(position.trader == msg.sender, "Not position owner");

        uint256 currentPrice = priceOracle.getPrice();
        uint256 pnl = calculatePnL(position, currentPrice);

        position.isOpen = false;

        // Update open interest
        perpetualHook.updateOpenInterest(position.size, false);

        emit PositionClosed(positionId, msg.sender, pnl);
    }

    function liquidatePosition(uint256 positionId) external nonReentrant {
        Position storage position = positions[positionId];
        require(position.isOpen, "Position already closed");
        require(isLiquidatable(positionId), "Position not liquidatable");

        uint256 currentPrice = priceOracle.getPrice();
        uint256 pnl = calculatePnL(position, currentPrice);

        position.isOpen = false;

        // Update open interest
        perpetualHook.updateOpenInterest(position.size, false);

        emit PositionLiquidated(positionId, position.trader, pnl);
    }

    function getPosition(uint256 positionId) external view returns (Position memory) {
        return positions[positionId];
    }

    function isLiquidatable(uint256 positionId) public view returns (bool) {
        Position memory position = positions[positionId];
        if (!position.isOpen) return false;

        uint256 currentPrice = priceOracle.getPrice();
        uint256 pnl = calculatePnL(position, currentPrice);

        // Calculate remaining margin after PnL
        uint256 remainingMargin;
        if (pnl > position.margin) {
            remainingMargin = 0;
        } else {
            remainingMargin = position.margin - pnl;
        }

        // Calculate required maintenance margin
        uint256 maintenanceMargin = (position.size * MAINTENANCE_MARGIN_BPS) / MAX_BPS;

        return remainingMargin < maintenanceMargin;
    }

    function calculatePnL(Position memory position, uint256 currentPrice) internal pure returns (uint256) {
        uint256 priceDelta;
        if (position.isLong) {
            if (currentPrice > position.entryPrice) {
                priceDelta = currentPrice - position.entryPrice;
                return (position.size * priceDelta) / position.entryPrice;
            } else {
                priceDelta = position.entryPrice - currentPrice;
                return (position.size * priceDelta) / position.entryPrice;
            }
        } else {
            if (currentPrice > position.entryPrice) {
                priceDelta = currentPrice - position.entryPrice;
                return (position.size * priceDelta) / position.entryPrice;
            } else {
                priceDelta = position.entryPrice - currentPrice;
                return (position.size * priceDelta) / position.entryPrice;
            }
        }
    }
}
