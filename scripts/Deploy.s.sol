// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PerpetualHook} from "../src/PerpetualHook.sol";
import {PerpPositionManager} from "../src/PerpPositionManager.sol";
import {SimplePriceOracle} from "../src/SimplePriceOracle.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    // Hook flags for our hook implementation
    uint160 constant HOOKS_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG
        | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address token0Address = vm.envAddress("TOKEN0_ADDRESS");
        address token1Address = vm.envAddress("TOKEN1_ADDRESS");

        // Validate addresses
        require(token0Address != address(0), "TOKEN0_ADDRESS cannot be zero address");
        require(token1Address != address(0), "TOKEN1_ADDRESS cannot be zero address");
        require(token0Address < token1Address, "TOKEN0_ADDRESS must be less than TOKEN1_ADDRESS");
        require(poolManagerAddress != address(0), "POOL_MANAGER_ADDRESS cannot be zero address");

        vm.startBroadcast(deployerPrivateKey);

        // Approve tokens for pool manager
        IERC20(token0Address).approve(poolManagerAddress, type(uint256).max);
        IERC20(token1Address).approve(poolManagerAddress, type(uint256).max);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManagerAddress));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, HOOKS_FLAGS, type(PerpetualHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        PerpetualHook hook = new PerpetualHook{salt: salt}(IPoolManager(poolManagerAddress));
        require(address(hook) == hookAddress, "Hook address mismatch");

        // Deploy price oracle
        SimplePriceOracle oracle = new SimplePriceOracle();

        // Deploy position manager
        PerpPositionManager positionManager = new PerpPositionManager(address(hook), address(oracle));

        // Create and initialize pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0Address),
            currency1: Currency.wrap(token1Address),
            fee: 3000, // 0.3% fee tier
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Initialize pool with 1:1 price (sqrtPriceX96 = 2^96)
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        try IPoolManager(poolManagerAddress).initialize(poolKey, sqrtPriceX96) {
            console.log("Pool initialized successfully");
        } catch Error(string memory reason) {
            console.log("Pool initialization failed:", reason);
            revert(reason);
        } catch (bytes memory) /*lowLevelData*/ {
            console.log("Pool initialization failed with low-level error");
            revert("Pool initialization failed with low-level error");
        }

        vm.stopBroadcast();

        console.log("Deployed contracts:");
        console.log("PerpetualHook:", address(hook));
        console.log("SimplePriceOracle:", address(oracle));
        console.log("PerpPositionManager:", address(positionManager));
    }
}
