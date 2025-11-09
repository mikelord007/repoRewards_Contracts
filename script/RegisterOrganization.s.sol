// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RepoRewards} from "../src/RepoRewards.sol";

contract RegisterOrganizationScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address repoRewardsAddress = vm.envAddress("REPO_REWARDS_ADDRESS");
        address yieldSource = vm.envAddress("YIELD_SOURCE");
        address management = vm.envAddress("MANAGEMENT");
        string memory name = vm.envString("ORG_NAME");

        vm.startBroadcast(deployerPrivateKey);

        RepoRewards repoRewards = RepoRewards(repoRewardsAddress);

        (uint256 orgId, address strategy) = repoRewards.registerOrganization(
            yieldSource,
            management,
            name
        );

        // Get organization details to show token
        RepoRewards.Organization memory org = repoRewards.getOrganization(
            orgId
        );

        console.log("Organization registered!");
        console.log("Organization ID:", orgId);
        console.log("Strategy address:", strategy);
        console.log("Yield Source:", org.yieldSource);
        console.log("Token (from vault):", org.token);
        console.log("Management:", org.management);
        console.log("Name:", name);

        vm.stopBroadcast();
    }
}
