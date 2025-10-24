// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import "./interfaces/IPerpetualHook.sol";

contract PerpetualHook is BaseHook, IPerpetualHook {
    using PoolIdLibrary for PoolKey;

    // Constants
    uint256 private constant MAX_BPS = 10000;
    uint256 private constant MIN_LEVERAGE = 2;
    uint256 private constant MAX_LEVERAGE = 10;

    // State variables
    mapping(PoolId => PoolState) public poolStates;
    PoolKey public poolKey;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getPoolState() public view returns (PoolState memory) {
        // Assuming a single pool, return the state for the poolKey
        return poolStates[poolKey.toId()];
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata, uint160) internal pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        poolKey = key;
        poolStates[key.toId()] = PoolState({totalLiquidity: 0, totalOpenInterest: 0, maxLeverage: MAX_LEVERAGE});
        return IHooks.afterInitialize.selector;
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal override returns (bytes4) {
        PoolState storage state = poolStates[key.toId()];

        // Update liquidity tracking for adding liquidity
        if (params.liquidityDelta > 0) {
            state.totalLiquidity += uint256(params.liquidityDelta);
        }

        return IHooks.beforeAddLiquidity.selector;
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal pure override returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal override returns (bytes4) {
        PoolState storage state = poolStates[key.toId()];

        // Update liquidity tracking for removing liquidity
        if (params.liquidityDelta < 0) {
            state.totalLiquidity -= uint256(-params.liquidityDelta);
        }

        return IHooks.beforeRemoveLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal pure override returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function updateOpenInterest(uint256 amount, bool increase) external {
        PoolState storage state = poolStates[poolKey.toId()];

        if (increase) {
            state.totalOpenInterest += amount;
        } else {
            state.totalOpenInterest = state.totalOpenInterest > amount ? state.totalOpenInterest - amount : 0;
        }

        state.maxLeverage = calculateMaxLeverage();

        emit OpenInterestChanged(state.totalOpenInterest);
        emit LeverageLimitUpdated(state.maxLeverage);
    }

    function calculateMaxLeverage() public view returns (uint256) {
        PoolState memory state = getPoolState();

        if (state.totalLiquidity == 0) return MIN_LEVERAGE;

        uint256 utilization = (state.totalOpenInterest * MAX_BPS) / state.totalLiquidity;

        if (utilization >= MAX_BPS) return MIN_LEVERAGE;

        // Linear interpolation between max and min leverage based on utilization
        uint256 leverageRange = MAX_LEVERAGE - MIN_LEVERAGE;
        uint256 adjustedLeverage = MAX_LEVERAGE - (leverageRange * utilization) / MAX_BPS;

        return adjustedLeverage;
    }

    function validateTrade(uint256 amount, uint256 leverage) external view returns (bool) {
        PoolState memory state = getPoolState();

        // Check if leverage is within limits
        if (leverage < MIN_LEVERAGE || leverage > state.maxLeverage) {
            return false;
        }

        // Check if there's enough liquidity
        uint256 totalRequired = amount * leverage;
        if (totalRequired > state.totalLiquidity) {
            return false;
        }

        return true;
    }
}
