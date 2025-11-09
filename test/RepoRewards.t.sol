// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {RepoRewards} from "../src/RepoRewards.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract RepoRewardsTest is Test {
    RepoRewards public repoRewards;
    MockERC20 public rewardToken;
    address public octantProtocol = address(0x1234);
    address public owner = address(this);
    address public contributor1 = address(0x1);
    address public contributor2 = address(0x2);
    address public donor = address(0x3);

    function setUp() public {
        rewardToken = new MockERC20();
        repoRewards = new RepoRewards(octantProtocol, address(rewardToken));

        // Mint tokens to donor
        rewardToken.mint(donor, 10000e18);
    }

    function test_RegisterContributor() public {
        vm.prank(contributor1);
        repoRewards.registerContributor("alice-github");

        (address wallet, string memory githubUsername, uint256 totalRewards, bool isRegistered) =
            repoRewards.getContributor(contributor1);

        assertEq(wallet, contributor1);
        assertEq(githubUsername, "alice-github");
        assertEq(totalRewards, 0);
        assertTrue(isRegistered);
    }

    function test_ReceiveFunding() public {
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 1000e18);
        
        vm.prank(donor);
        repoRewards.receiveFunding(1000e18);

        assertEq(repoRewards.getBalance(), 1000e18);
        assertEq(repoRewards.totalFundsReceived(), 1000e18);
    }

    function test_DistributeRewards() public {
        // Register contributors
        vm.prank(contributor1);
        repoRewards.registerContributor("alice-github");
        
        vm.prank(contributor2);
        repoRewards.registerContributor("bob-github");

        // Fund the contract
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 1000e18);
        
        vm.prank(donor);
        repoRewards.receiveFunding(1000e18);

        // Distribute rewards
        address[] memory recipients = new address[](2);
        recipients[0] = contributor1;
        recipients[1] = contributor2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 300e18;
        amounts[1] = 200e18;

        string[] memory repositories = new string[](2);
        repositories[0] = "repo1";
        repositories[1] = "repo2";

        repoRewards.distributeRewards(recipients, amounts, repositories);

        // Check balances
        assertEq(rewardToken.balanceOf(contributor1), 300e18);
        assertEq(rewardToken.balanceOf(contributor2), 200e18);
        assertEq(repoRewards.getBalance(), 500e18);
        assertEq(repoRewards.totalFundsDistributed(), 500e18);

        // Check contributor rewards
        (,, uint256 totalRewards1,) = repoRewards.getContributor(contributor1);
        (,, uint256 totalRewards2,) = repoRewards.getContributor(contributor2);
        
        assertEq(totalRewards1, 300e18);
        assertEq(totalRewards2, 200e18);
    }

    function test_RevertIf_NotRegistered() public {
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 1000e18);
        
        vm.prank(donor);
        repoRewards.receiveFunding(1000e18);

        address[] memory recipients = new address[](1);
        recipients[0] = contributor1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        string[] memory repositories = new string[](1);
        repositories[0] = "repo1";

        vm.expectRevert("RepoRewards: recipient not registered");
        repoRewards.distributeRewards(recipients, amounts, repositories);
    }
}

