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
    address public yieldSource1 = address(0x1234);
    address public yieldSource2 = address(0x5678);
    address public keeper = address(0x9ABC);
    address public emergencyAdmin = address(0xDEF0);
    address public tokenizedStrategyAddress = address(0x1111);
    address public owner = address(this);
    address public orgAdmin1 = address(0x1);
    address public orgAdmin2 = address(0x2);
    address public contributor1 = address(0x3);
    address public contributor2 = address(0x4);
    address public donor = address(0x5);

    uint256 public orgId1;
    uint256 public orgId2;

    function setUp() public {
        rewardToken = new MockERC20();
        repoRewards = new RepoRewards(
            address(rewardToken),
            keeper,
            emergencyAdmin,
            false, // enableBurning
            tokenizedStrategyAddress
        );

        // Register organizations with their own yield sources
        orgId1 = repoRewards.registerOrganization(orgAdmin1, "Org 1", yieldSource1);
        orgId2 = repoRewards.registerOrganization(orgAdmin2, "Org 2", yieldSource2);

        // Mint tokens to donor
        rewardToken.mint(donor, 100000e18);
    }

    function test_RegisterOrganization() public {
        address newYieldSource = address(0x9999);
        uint256 newOrgId = repoRewards.registerOrganization(
            address(0x10),
            "New Org",
            newYieldSource
        );

        (uint256 id, address admin, string memory name, bool isActive,,) =
            repoRewards.getOrganization(newOrgId);

        assertEq(id, newOrgId);
        assertEq(admin, address(0x10));
        assertEq(name, "New Org");
        assertTrue(isActive);
        
        // Verify strategy was deployed
        address strategy = repoRewards.getOrgStrategy(newOrgId);
        assertTrue(strategy != address(0));
        
        // Verify yield source is stored
        address yieldSource = repoRewards.getOrgYieldSource(newOrgId);
        assertEq(yieldSource, newYieldSource);
    }

    function test_RevertIf_RegisterOrgWithExistingAdmin() public {
        vm.expectRevert("RepoRewards: admin already registered");
        repoRewards.registerOrganization(orgAdmin1, "Duplicate Org", yieldSource1);
    }

    function test_ReceiveFunding() public {
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 10000e18);

        vm.prank(donor);
        repoRewards.receiveFunding(orgId1, 10000e18);

        (,,,, uint256 totalReceived,) = repoRewards.getOrganization(orgId1);
        assertEq(totalReceived, 10000e18);
        assertEq(repoRewards.getOrgBalance(orgId1), 10000e18);
    }

    function test_CreateMonthlyDistribution() public {
        // Fund organization
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 10000e18);
        vm.prank(donor);
        repoRewards.receiveFunding(orgId1, 10000e18);

        // Create distribution
        RepoRewards.RewardRecipient[] memory recipients =
            new RepoRewards.RewardRecipient[](2);
        recipients[0] = RepoRewards.RewardRecipient({
            wallet: contributor1,
            ratio: 6000 // 60%
        });
        recipients[1] = RepoRewards.RewardRecipient({
            wallet: contributor2,
            ratio: 4000 // 40%
        });

        vm.prank(orgAdmin1);
        uint256 distributionId = repoRewards.createMonthlyDistribution(
            orgId1, 1, 2024, recipients, 10000e18
        );

        (
            uint256 id,
            uint256 orgId,
            uint256 month,
            uint256 year,
            uint256 totalAmount,
            uint256 distributedAmount,
            bool isDistributed,
        ) = repoRewards.getDistribution(distributionId);

        assertEq(id, distributionId);
        assertEq(orgId, orgId1);
        assertEq(month, 1);
        assertEq(year, 2024);
        assertEq(totalAmount, 10000e18);
        assertEq(distributedAmount, 0);
        assertFalse(isDistributed);
    }

    function test_RevertIf_DistributionRatiosNot100Percent() public {
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 10000e18);
        vm.prank(donor);
        repoRewards.receiveFunding(orgId1, 10000e18);

        RepoRewards.RewardRecipient[] memory recipients =
            new RepoRewards.RewardRecipient[](2);
        recipients[0] = RepoRewards.RewardRecipient({
            wallet: contributor1,
            ratio: 5000 // 50%
        });
        recipients[1] = RepoRewards.RewardRecipient({
            wallet: contributor2,
            ratio: 4000 // 40% - totals 90%, should fail
        });

        vm.prank(orgAdmin1);
        vm.expectRevert("RepoRewards: ratios must sum to 100%");
        repoRewards.createMonthlyDistribution(orgId1, 1, 2024, recipients, 10000e18);
    }

    function test_DistributeRewards() public {
        // Fund organization
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 10000e18);
        vm.prank(donor);
        repoRewards.receiveFunding(orgId1, 10000e18);

        // Create distribution
        RepoRewards.RewardRecipient[] memory recipients =
            new RepoRewards.RewardRecipient[](2);
        recipients[0] = RepoRewards.RewardRecipient({
            wallet: contributor1,
            ratio: 6000 // 60%
        });
        recipients[1] = RepoRewards.RewardRecipient({
            wallet: contributor2,
            ratio: 4000 // 40%
        });

        vm.prank(orgAdmin1);
        uint256 distributionId = repoRewards.createMonthlyDistribution(
            orgId1, 1, 2024, recipients, 10000e18
        );

        // Distribute rewards
        repoRewards.distributeRewards(distributionId);

        // Check balances
        assertEq(rewardToken.balanceOf(contributor1), 6000e18); // 60%
        assertEq(rewardToken.balanceOf(contributor2), 4000e18); // 40%

        // Check distribution status
        (,,,,, uint256 distributedAmount, bool isDistributed,) =
            repoRewards.getDistribution(distributionId);
        assertEq(distributedAmount, 10000e18);
        assertTrue(isDistributed);

        // Check org stats
        (,,,,, uint256 totalDistributed) = repoRewards.getOrganization(orgId1);
        assertEq(totalDistributed, 10000e18);
    }

    function test_RevertIf_DistributeTwice() public {
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 10000e18);
        vm.prank(donor);
        repoRewards.receiveFunding(orgId1, 10000e18);

        RepoRewards.RewardRecipient[] memory recipients =
            new RepoRewards.RewardRecipient[](1);
        recipients[0] = RepoRewards.RewardRecipient({
            wallet: contributor1,
            ratio: 10000 // 100%
        });

        vm.prank(orgAdmin1);
        uint256 distributionId = repoRewards.createMonthlyDistribution(
            orgId1, 1, 2024, recipients, 10000e18
        );

        repoRewards.distributeRewards(distributionId);

        vm.expectRevert("RepoRewards: already distributed");
        repoRewards.distributeRewards(distributionId);
    }

    function test_MultipleOrganizations() public {
        // Fund both organizations
        vm.prank(donor);
        rewardToken.approve(address(repoRewards), 20000e18);
        vm.prank(donor);
        repoRewards.receiveFunding(orgId1, 10000e18);
        vm.prank(donor);
        repoRewards.receiveFunding(orgId2, 10000e18);

        // Create distributions for both
        RepoRewards.RewardRecipient[] memory recipients1 =
            new RepoRewards.RewardRecipient[](1);
        recipients1[0] = RepoRewards.RewardRecipient({
            wallet: contributor1,
            ratio: 10000
        });

        RepoRewards.RewardRecipient[] memory recipients2 =
            new RepoRewards.RewardRecipient[](1);
        recipients2[0] = RepoRewards.RewardRecipient({
            wallet: contributor2,
            ratio: 10000
        });

        vm.prank(orgAdmin1);
        uint256 dist1 = repoRewards.createMonthlyDistribution(
            orgId1, 1, 2024, recipients1, 10000e18
        );

        vm.prank(orgAdmin2);
        uint256 dist2 = repoRewards.createMonthlyDistribution(
            orgId2, 1, 2024, recipients2, 10000e18
        );

        // Distribute both
        repoRewards.distributeRewards(dist1);
        repoRewards.distributeRewards(dist2);

        assertEq(rewardToken.balanceOf(contributor1), 10000e18);
        assertEq(rewardToken.balanceOf(contributor2), 10000e18);
    }
}
