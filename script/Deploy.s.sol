// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RepoRewards} from "../src/RepoRewards.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        address keeper = vm.envAddress("KEEPER");
        address emergencyAdmin = vm.envAddress("EMERGENCY_ADMIN");
        bool enableBurning = vm.envBool("ENABLE_BURNING");
        address tokenizedStrategyAddress = vm.envAddress("TOKENIZED_STRATEGY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        RepoRewards repoRewards = new RepoRewards(
            rewardToken,
            keeper,
            emergencyAdmin,
            enableBurning,
            tokenizedStrategyAddress
        );

        console.log("RepoRewards deployed at:", address(repoRewards));
        console.log("Reward Token:", rewardToken);
        console.log("Keeper:", keeper);
        console.log("Emergency Admin:", emergencyAdmin);
        console.log("Enable Burning:", enableBurning);
        console.log("Tokenized Strategy Address:", tokenizedStrategyAddress);
        console.log("Owner:", msg.sender);
        console.log("Note: Each organization will specify its own yield source during registration");

        vm.stopBroadcast();
    }
}
