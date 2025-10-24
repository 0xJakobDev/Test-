// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockToken} from "../test/PerpDex.t.sol";

contract DeployTokens is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock tokens
        MockToken token0 = new MockToken("Token0", "TKN0");
        MockToken token1 = new MockToken("Token1", "TKN1");

        // Mint some tokens to the deployer
        token0.mint(deployer, 1000000 ether);
        token1.mint(deployer, 1000000 ether);

        vm.stopBroadcast();

        console.log("Deployed tokens:");
        console.log("Token0:", address(token0));
        console.log("Token1:", address(token1));
        console.log("Minted tokens to:", deployer);
    }
}
