// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RepoRewards} from "../src/RepoRewards.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address yieldSource = vm.envAddress("YIELD_SOURCE");
        address keeper = vm.envAddress("KEEPER");
        address emergencyAdmin = vm.envAddress("EMERGENCY_ADMIN");
        bool enableBurning = vm.envBool("ENABLE_BURNING");

        vm.startBroadcast(deployerPrivateKey);

        RepoRewards repoRewards = new RepoRewards(
            yieldSource,
            keeper,
            emergencyAdmin,
            enableBurning
        );

        console.log("RepoRewards deployed at:", address(repoRewards));
        console.log("Yield Source:", yieldSource);
        console.log("Keeper:", keeper);
        console.log("Emergency Admin:", emergencyAdmin);
        console.log("Enable Burning:", enableBurning);
        console.log("Tokenized Strategy Address:", repoRewards.tokenizedStrategyAddress());
        console.log("Owner:", msg.sender);
        console.log("Note: Each organization will specify its own reward token during registration");

        vm.stopBroadcast();
    }
}
