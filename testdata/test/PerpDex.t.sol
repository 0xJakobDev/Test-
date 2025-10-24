// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import "../src/PerpetualHook.sol";
import "../src/PerpPositionManager.sol";
import "../src/SimplePriceOracle.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Concrete implementation of PerpetualHook for testing
contract TestPerpetualHook is PerpetualHook {
    constructor(IPoolManager _poolManager) PerpetualHook(_poolManager) {}

    // Override validateHookAddress to allow deployment to any address during testing
    function validateHookAddress(BaseHook) internal pure override {}
}

contract PerpDexTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    TestPerpetualHook public hook;
    PerpPositionManager public positionManager;
    SimplePriceOracle public oracle;
    PoolKey public poolKey;
    MockToken public token0;
    MockToken public token1;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy mock tokens
        token0 = new MockToken("Token0", "TKN0");
        token1 = new MockToken("Token1", "TKN1");

        // Fund users
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        token0.mint(alice, 1000 ether);
        token0.mint(bob, 1000 ether);
        token1.mint(alice, 1000 ether);
        token1.mint(bob, 1000 ether);
        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);

        // Approve tokens for pool manager and router
        vm.startPrank(alice);
        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        // Approve tokens for test contract
        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Deploy our hook with the proper flags
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            )
        );

        // Deploy the hook to the correct address
        deployCodeTo("test/PerpDex.t.sol:TestPerpetualHook", abi.encode(manager), hookAddress);
        hook = TestPerpetualHook(hookAddress);

        // Deploy other contracts
        oracle = new SimplePriceOracle();
        positionManager = new PerpPositionManager(address(hook), address(oracle));

        // Approve tokens for position manager
        vm.startPrank(alice);
        token0.approve(address(positionManager), type(uint256).max);
        token1.approve(address(positionManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(positionManager), type(uint256).max);
        token1.approve(address(positionManager), type(uint256).max);
        vm.stopPrank();

        // Create pool key with tokens in correct order
        address token0Addr = address(token0);
        address token1Addr = address(token1);
        if (token0Addr > token1Addr) {
            (token0Addr, token1Addr) = (token1Addr, token0Addr);
        }

        poolKey = PoolKey({
            currency0: Currency.wrap(token0Addr),
            currency1: Currency.wrap(token1Addr),
            fee: 3000, // 0.3% fee tier
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Initialize pool with a 1:1 price (sqrtPriceX96 = 2^96)
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        manager.initialize(poolKey, sqrtPriceX96);

        // Add initial liquidity
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120, // Price range around 1:1
                tickUpper: 120,
                liquidityDelta: 1000e18,
                salt: bytes32(0)
            }),
            ""
        );
    }

    function test_OpenPosition() public {
        vm.startPrank(alice);

        // Open a position
        uint256 positionId = positionManager.openPosition(true, 1 ether, 5);

        // Verify position is opened
        IPerpPositionManager.Position memory position = positionManager.getPosition(positionId);
        assertTrue(position.isOpen);
        assertEq(position.margin, 1 ether);
        assertEq(position.leverage, 5);
        assertTrue(position.isLong);

        vm.stopPrank();
    }

    function test_ClosePosition() public {
        vm.startPrank(alice);

        // Open and close position
        uint256 positionId = positionManager.openPosition(true, 1 ether, 5);
        positionManager.closePosition(positionId);

        // Verify position is closed
        IPerpPositionManager.Position memory position = positionManager.getPosition(positionId);
        assertFalse(position.isOpen);

        vm.stopPrank();
    }

    function test_Liquidation() public {
        vm.startPrank(alice);

        // Open position
        uint256 positionId = positionManager.openPosition(true, 1 ether, 5);
        vm.stopPrank();

        // Move price down significantly to make position liquidatable
        oracle.updatePrice(500e18); // 50% price drop

        // Liquidate position
        vm.prank(bob);
        positionManager.liquidatePosition(positionId);

        // Verify position is closed
        IPerpPositionManager.Position memory position = positionManager.getPosition(positionId);
        assertFalse(position.isOpen);
    }

    function test_MaxLeverageLimit() public {
        vm.startPrank(alice);

        // Try to open position with too high leverage
        vm.expectRevert("Invalid leverage");

        positionManager.openPosition(true, 1 ether, 11);

        vm.stopPrank();
    }
}
