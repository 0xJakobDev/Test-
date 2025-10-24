// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";

contract DeployPoolManager is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the pool manager
        PoolManager poolManager = new PoolManager(vm.addr(deployerPrivateKey));

        vm.stopBroadcast();

        console.log("Deployed PoolManager:", address(poolManager));
    }
}
