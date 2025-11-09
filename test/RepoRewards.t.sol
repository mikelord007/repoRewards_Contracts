// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {RepoRewards} from "../src/RepoRewards.sol";
import {YieldDonatingStrategy} from "../src/YieldDonatingStrategy.sol";
import {
    ITokenizedStrategy
} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

// Mock TokenizedStrategy for testing
contract MockTokenizedStrategy is ERC20 {
    ERC20 public asset;
    uint256 public totalAssetsValue;
    uint256 public pricePerShareValue = 1e18; // 1:1 initially
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;

    constructor(address _asset) ERC20("Mock Strategy", "MSTRAT") {
        asset = ERC20(_asset);
        totalAssetsValue = 0;
    }

    function initialize(
        address _asset,
        string memory,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool
    ) external {
        management = _management;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        donationAddress = _donationAddress;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256) {
        asset.transferFrom(msg.sender, address(this), assets);
        uint256 shares = convertToShares(assets);
        _mint(receiver, shares);
        totalAssetsValue += assets;
        return shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256
    ) external returns (uint256) {
        uint256 shares = convertToShares(assets);
        _burn(owner, shares);
        totalAssetsValue -= assets;
        asset.transfer(receiver, assets);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256
    ) external returns (uint256) {
        _burn(owner, shares);
        uint256 assets = convertToAssets(shares);
        totalAssetsValue -= assets;
        asset.transfer(receiver, assets);
        return assets;
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        _mint(receiver, shares);
        uint256 assets = convertToAssets(shares);
        totalAssetsValue += assets;
        return assets;
    }

    function report() external returns (uint256 profit, uint256 loss) {
        uint256 currentBalance = asset.balanceOf(address(this));
        if (currentBalance > totalAssetsValue) {
            profit = currentBalance - totalAssetsValue;
            // Mint shares to donationAddress based on profit
            uint256 profitShares = convertToShares(profit);
            _mint(donationAddress, profitShares);
            totalAssetsValue = currentBalance;
        } else if (currentBalance < totalAssetsValue) {
            loss = totalAssetsValue - currentBalance;
            totalAssetsValue = currentBalance;
        }
        return (profit, loss);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalAssetsValue == 0) return assets;
        return (assets * totalSupply()) / totalAssetsValue;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) return shares;
        return (shares * totalAssetsValue) / totalSupply();
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsValue;
    }

    function pricePerShare() external view returns (uint256) {
        return pricePerShareValue;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }

    // Helper to simulate yield
    // Note: This function expects the asset to be a MockERC20 with a mint function
    function simulateYield(uint256 yieldAmount) external {
        // Use address(asset) to get the address, then cast to MockERC20
        MockERC20(address(asset)).mint(address(this), yieldAmount);
    }
}

// Mock YieldSource
interface IYieldSource {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

contract MockYieldSource {
    ERC20 public token;
    mapping(address => uint256) public balances;

    constructor(address _token) {
        token = ERC20(_token);
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
    }
}

contract RepoRewardsTest is Test {
    RepoRewards public repoRewards;
    MockERC20 public token1;
    MockERC20 public token2;
    MockTokenizedStrategy public mockStrategy1;
    MockTokenizedStrategy public mockStrategy2;
    MockYieldSource public yieldSource;
    address public owner;
    address public keeper;
    address public emergencyAdmin;
    address public management1;
    address public management2;
    address public contributor1;
    address public contributor2;
    address public tokenizedStrategyAddress;

    event OrganizationRegistered(
        uint256 indexed orgId,
        address indexed strategy,
        address indexed token,
        address management
    );
    event PrincipalAdded(
        uint256 indexed orgId,
        address indexed token,
        uint256 amount
    );
    event PrincipalReduced(
        uint256 indexed orgId,
        address indexed token,
        uint256 amount
    );
    event RewardsHarvested(
        uint256 indexed orgId,
        uint256 profit,
        uint256 totalRewards
    );
    event ContributorRewardAllocated(
        uint256 indexed orgId,
        address indexed contributor,
        uint256 amount
    );
    event RewardsClaimed(
        uint256 indexed orgId,
        address indexed contributor,
        uint256 amount
    );

    function setUp() public {
        owner = address(this);
        keeper = makeAddr("keeper");
        emergencyAdmin = makeAddr("emergencyAdmin");
        management1 = makeAddr("management1");
        management2 = makeAddr("management2");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");

        // Deploy mock tokens
        token1 = new MockERC20("Token 1", "TKN1");
        token2 = new MockERC20("Token 2", "TKN2");

        // Deploy mock yield source
        yieldSource = new MockYieldSource(address(token1));

        // Deploy RepoRewards
        // Note: RepoRewards will deploy YieldDonatingTokenizedStrategy internally
        repoRewards = new RepoRewards(
            address(yieldSource),
            keeper,
            emergencyAdmin,
            false // enableBurning
        );

        // Get the deployed tokenized strategy address
        tokenizedStrategyAddress = repoRewards.tokenizedStrategyAddress();

        // Deploy mock strategies (these would normally be YieldDonatingStrategy instances)
        // For testing purposes, we'll use MockTokenizedStrategy
        mockStrategy1 = new MockTokenizedStrategy(address(token1));
        mockStrategy2 = new MockTokenizedStrategy(address(token2));
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterOrganization() public {
        vm.expectEmit(true, true, true, true);
        emit OrganizationRegistered(
            0,
            address(mockStrategy1),
            address(token1),
            management1
        );

        (uint256 orgId, address strategy) = repoRewards.registerOrganization(
            address(token1),
            management1,
            "Test Organization 1"
        );

        assertEq(orgId, 0, "First org should have ID 0");
        assertEq(repoRewards.nextOrgId(), 1, "Next org ID should be 1");

        RepoRewards.Organization memory org = repoRewards.getOrganization(
            orgId
        );
        assertEq(org.token, address(token1), "Token should match");
        assertEq(org.management, management1, "Management should match");
        assertEq(org.totalPrincipal, 0, "Initial principal should be 0");
    }

    function test_RegisterMultipleOrganizations() public {
        repoRewards.registerOrganization(address(token1), management1, "Org 1");
        repoRewards.registerOrganization(address(token2), management2, "Org 2");

        assertEq(repoRewards.nextOrgId(), 2, "Should have 2 organizations");
        assertEq(repoRewards.getOrganizationCount(), 2, "Count should be 2");

        RepoRewards.Organization memory org1 = repoRewards.getOrganization(0);
        RepoRewards.Organization memory org2 = repoRewards.getOrganization(1);

        assertEq(org1.token, address(token1), "Org 1 token should match");
        assertEq(org2.token, address(token2), "Org 2 token should match");
    }

    function test_RegisterOrganization_RevertIf_InvalidToken() public {
        vm.expectRevert("Invalid token");
        repoRewards.registerOrganization(address(0), management1, "Test");
    }

    function test_RegisterOrganization_RevertIf_InvalidManagement() public {
        vm.expectRevert("Invalid management");
        repoRewards.registerOrganization(address(token1), address(0), "Test");
    }

    function test_RegisterOrganization_OnlyOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        repoRewards.registerOrganization(address(token1), management1, "Test");
    }

    /*//////////////////////////////////////////////////////////////
                        PRINCIPAL MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddPrincipal() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 amount = 1000e18;

        token1.mint(address(this), amount);
        token1.approve(address(repoRewards), amount);

        vm.expectEmit(true, true, false, true);
        emit PrincipalAdded(orgId, address(token1), amount);

        repoRewards.addPrincipal(orgId, amount);

        RepoRewards.Organization memory org = repoRewards.getOrganization(
            orgId
        );
        assertEq(org.totalPrincipal, amount, "Principal should be updated");
    }

    function test_AddPrincipal_MultipleTimes() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 amount1 = 1000e18;
        uint256 amount2 = 500e18;

        token1.mint(address(this), amount1 + amount2);
        token1.approve(address(repoRewards), amount1 + amount2);

        repoRewards.addPrincipal(orgId, amount1);
        repoRewards.addPrincipal(orgId, amount2);

        RepoRewards.Organization memory org = repoRewards.getOrganization(
            orgId
        );
        assertEq(
            org.totalPrincipal,
            amount1 + amount2,
            "Principal should accumulate"
        );
    }

    function test_AddPrincipal_RevertIf_OrgNotFound() public {
        token1.mint(address(this), 1000e18);
        token1.approve(address(repoRewards), 1000e18);

        vm.expectRevert("Organization not found");
        repoRewards.addPrincipal(999, 1000e18);
    }

    function test_AddPrincipal_RevertIf_ZeroAmount() public {
        uint256 orgId = _registerOrganization(address(token1), management1);

        vm.expectRevert("Amount must be greater than 0");
        repoRewards.addPrincipal(orgId, 0);
    }

    function test_ReducePrincipal() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 depositAmount = 1000e18;
        uint256 withdrawAmount = 500e18;

        // Setup: deposit principal
        token1.mint(address(this), depositAmount);
        token1.approve(address(repoRewards), depositAmount);
        repoRewards.addPrincipal(orgId, depositAmount);

        // Mock strategy to hold tokens
        token1.mint(address(mockStrategy1), depositAmount);

        // Reduce principal
        vm.prank(management1);
        vm.expectEmit(true, true, false, true);
        emit PrincipalReduced(orgId, address(token1), withdrawAmount);

        repoRewards.reducePrincipal(orgId, withdrawAmount);

        RepoRewards.Organization memory org = repoRewards.getOrganization(
            orgId
        );
        assertEq(
            org.totalPrincipal,
            depositAmount - withdrawAmount,
            "Principal should be reduced"
        );
    }

    function test_ReducePrincipal_OnlyManagementOrOwner() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 amount = 1000e18;

        token1.mint(address(this), amount);
        token1.approve(address(repoRewards), amount);
        repoRewards.addPrincipal(orgId, amount);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Not authorized");
        repoRewards.reducePrincipal(orgId, 100e18);
    }

    function test_ReducePrincipal_RevertIf_InsufficientPrincipal() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 depositAmount = 1000e18;

        token1.mint(address(this), depositAmount);
        token1.approve(address(repoRewards), depositAmount);
        repoRewards.addPrincipal(orgId, depositAmount);

        vm.prank(management1);
        vm.expectRevert("Insufficient principal");
        repoRewards.reducePrincipal(orgId, depositAmount + 1);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Harvest() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 depositAmount = 1000e18;

        // Setup: deposit principal
        token1.mint(address(this), depositAmount);
        token1.approve(address(repoRewards), depositAmount);
        repoRewards.addPrincipal(orgId, depositAmount);

        // Simulate yield in strategy
        uint256 yieldAmount = 100e18;
        mockStrategy1.simulateYield(yieldAmount);

        // Harvest (must be called by keeper)
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = repoRewards.harvest(orgId);

        assertEq(profit, yieldAmount, "Profit should match yield");
        assertEq(loss, 0, "Loss should be 0");
    }

    function test_Harvest_RevertIf_OrgNotFound() public {
        vm.expectRevert("Organization not found");
        vm.prank(keeper);
        repoRewards.harvest(999);
    }

    function test_AllocateRewards() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 depositAmount = 1000e18;
        uint256 yieldAmount = 100e18;

        // Setup: deposit and harvest
        token1.mint(address(this), depositAmount);
        token1.approve(address(repoRewards), depositAmount);
        repoRewards.addPrincipal(orgId, depositAmount);
        mockStrategy1.simulateYield(yieldAmount);
        vm.prank(keeper);
        repoRewards.harvest(orgId);

        // Allocate rewards
        address[] memory contributors = new address[](2);
        contributors[0] = contributor1;
        contributors[1] = contributor2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 50e18;
        shares[1] = 50e18;

        vm.prank(management1);
        repoRewards.allocateRewards(orgId, contributors, shares);

        assertEq(
            repoRewards.getContributorReward(orgId, contributor1),
            50e18,
            "Contributor 1 should have rewards"
        );
        assertEq(
            repoRewards.getContributorReward(orgId, contributor2),
            50e18,
            "Contributor 2 should have rewards"
        );
    }

    function test_AllocateRewards_OnlyManagementOrOwner() public {
        uint256 orgId = _registerOrganization(address(token1), management1);

        address[] memory contributors = new address[](1);
        contributors[0] = contributor1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10e18;

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Not authorized");
        repoRewards.allocateRewards(orgId, contributors, shares);
    }

    function test_AllocateRewards_RevertIf_InsufficientRewards() public {
        uint256 orgId = _registerOrganization(address(token1), management1);

        address[] memory contributors = new address[](1);
        contributors[0] = contributor1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1000e18; // More than available

        vm.prank(management1);
        vm.expectRevert("Insufficient pending rewards");
        repoRewards.allocateRewards(orgId, contributors, shares);
    }

    function test_Claim() public {
        uint256 orgId = _registerOrganization(address(token1), management1);
        uint256 depositAmount = 1000e18;
        uint256 yieldAmount = 100e18;
        uint256 rewardShares = 50e18;

        // Setup: deposit, harvest, and allocate
        token1.mint(address(this), depositAmount);
        token1.approve(address(repoRewards), depositAmount);
        repoRewards.addPrincipal(orgId, depositAmount);
        mockStrategy1.simulateYield(yieldAmount);
        vm.prank(keeper);
        repoRewards.harvest(orgId);

        address[] memory contributors = new address[](1);
        contributors[0] = contributor1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = rewardShares;

        vm.prank(management1);
        repoRewards.allocateRewards(orgId, contributors, shares);

        // Mock strategy to have tokens for redemption
        uint256 assetsToRedeem = mockStrategy1.convertToAssets(rewardShares);
        token1.mint(address(mockStrategy1), assetsToRedeem);

        // Claim
        uint256 balanceBefore = token1.balanceOf(contributor1);
        vm.prank(contributor1);
        vm.expectEmit(true, true, false, true);
        emit RewardsClaimed(orgId, contributor1, rewardShares);

        repoRewards.claim(orgId);

        assertEq(
            repoRewards.getContributorReward(orgId, contributor1),
            0,
            "Rewards should be cleared"
        );
        assertGt(
            token1.balanceOf(contributor1),
            balanceBefore,
            "Contributor should receive tokens"
        );
    }

    function test_Claim_RevertIf_NoRewards() public {
        uint256 orgId = _registerOrganization(address(token1), management1);

        vm.prank(contributor1);
        vm.expectRevert("No rewards to claim");
        repoRewards.claim(orgId);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetOrganization() public {
        uint256 orgId = _registerOrganization(address(token1), management1);

        RepoRewards.Organization memory org = repoRewards.getOrganization(
            orgId
        );
        assertEq(org.token, address(token1), "Token should match");
        assertEq(org.management, management1, "Management should match");
    }

    function test_GetContributorReward() public {
        uint256 orgId = _registerOrganization(address(token1), management1);

        address[] memory contributors = new address[](1);
        contributors[0] = contributor1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100e18;

        vm.prank(management1);
        repoRewards.allocateRewards(orgId, contributors, shares);

        assertEq(
            repoRewards.getContributorReward(orgId, contributor1),
            100e18,
            "Reward should match"
        );
    }

    function test_GetOrganizationCount() public {
        assertEq(
            repoRewards.getOrganizationCount(),
            0,
            "Initial count should be 0"
        );

        _registerOrganization(address(token1), management1);
        assertEq(repoRewards.getOrganizationCount(), 1, "Count should be 1");

        _registerOrganization(address(token2), management2);
        assertEq(repoRewards.getOrganizationCount(), 2, "Count should be 2");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _registerOrganization(
        address token,
        address management
    ) internal returns (uint256 orgId) {
        (orgId, ) = repoRewards.registerOrganization(
            token,
            management,
            "Test Org"
        );
    }
}
