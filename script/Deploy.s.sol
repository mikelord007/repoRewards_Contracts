// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RepoRewards} from "../src/RepoRewards.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address octantProtocol = vm.envAddress("OCTANT_PROTOCOL");
        address rewardToken = vm.envAddress("REWARD_TOKEN");

        vm.startBroadcast(deployerPrivateKey);

        RepoRewards repoRewards = new RepoRewards(octantProtocol, rewardToken);

        console.log("RepoRewards deployed at:", address(repoRewards));
        console.log("Octant Protocol:", octantProtocol);
        console.log("Reward Token:", rewardToken);

        vm.stopBroadcast();
    }
}

