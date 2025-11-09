// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {RepoRewards} from "../src/RepoRewards.sol";
import {YieldDonatingStrategy} from "../src/YieldDonatingStrategy.sol";
import {
    ITokenizedStrategy
} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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

// Mock ERC4626 Vault (Yearn vault) for testing
contract MockERC4626Vault is ERC20, IERC4626 {
    ERC20 public immutable assetToken;
    uint256 public totalAssetsValue;
    uint256 public yieldRate = 1e18; // 1:1 initially, can be adjusted to simulate yield

    constructor(address _asset) ERC20("Mock Yearn Vault", "MYV") {
        assetToken = ERC20(_asset);
        totalAssetsValue = 0;
    }

    // IERC4626 interface functions
    function asset() external view returns (address) {
        return address(assetToken);
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsValue;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalAssetsValue == 0) return assets;
        return (assets * totalSupply()) / totalAssetsValue;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) return shares;
        return (shares * totalAssetsValue) / totalSupply();
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256) {
        assetToken.transferFrom(msg.sender, address(this), assets);
        uint256 shares = convertToShares(assets);
        _mint(receiver, shares);
        totalAssetsValue += assets;
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        uint256 assets = convertToAssets(shares);
        assetToken.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        totalAssetsValue += assets;
        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256) {
        // Convert requested assets to shares based on current conversion rate
        uint256 shares = convertToShares(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        // Withdraw exactly the requested assets amount
        totalAssetsValue -= assets;
        assetToken.transfer(receiver, assets);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        uint256 assets = convertToAssets(shares);
        totalAssetsValue -= assets;
        assetToken.transfer(receiver, assets);
        return assets;
    }

    // Helper to simulate yield accrual
    function simulateYield(uint256 yieldAmount) external {
        // Mint tokens to the vault to simulate yield
        MockERC20(address(assetToken)).mint(address(this), yieldAmount);
        // Increase totalAssetsValue to reflect the yield
        totalAssetsValue += yieldAmount;
    }

    // Helper to set yield rate (for testing different scenarios)
    function setYieldRate(uint256 _rate) external {
        yieldRate = _rate;
    }
}

contract RepoRewardsTest is Test {
    RepoRewards public repoRewards;
    MockERC20 public token1;
    MockERC20 public token2;
    MockERC4626Vault public yieldSource1;
    MockERC4626Vault public yieldSource2;
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

        // Deploy mock ERC4626 vaults (Yearn vaults) as yield sources
        yieldSource1 = new MockERC4626Vault(address(token1));
        yieldSource2 = new MockERC4626Vault(address(token2));

        // Deploy RepoRewards with yieldSource1 as the default
        // Note: RepoRewards will deploy YieldDonatingTokenizedStrategy internally
        repoRewards = new RepoRewards(
            address(yieldSource1),
            keeper,
            emergencyAdmin,
            false // enableBurning
        );

        // Get the deployed tokenized strategy address
        tokenizedStrategyAddress = repoRewards.tokenizedStrategyAddress();
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterOrganization() public {
        (uint256 orgId, address strategy) = repoRewards.registerOrganization(
            address(token1),
            management1,
            "Test Organization 1"
        );

        assertEq(orgId, 0, "First org should have ID 0");
        assertEq(repoRewards.nextOrgId(), 1, "Next org ID should be 1");
        assertTrue(strategy != address(0), "Strategy should be deployed");

        RepoRewards.Organization memory org = repoRewards.getOrganization(
            orgId
        );
        assertEq(org.strategy, strategy, "Strategy should match");
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

        // Note: With real YieldDonatingStrategy, funds are in the vault
        // The strategy will withdraw from vault when reducePrincipal is called

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

        // Simulate yield in the vault (Yearn vault)
        // The strategy deposits into the vault, so yield accrues in the vault
        uint256 yieldAmount = 100e18;
        yieldSource1.simulateYield(yieldAmount);

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
        // Simulate yield in the vault
        yieldSource1.simulateYield(yieldAmount);
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
        // Simulate yield in the vault
        yieldSource1.simulateYield(yieldAmount);
        vm.prank(keeper);
        repoRewards.harvest(orgId);

        address[] memory contributors = new address[](1);
        contributors[0] = contributor1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = rewardShares;

        vm.prank(management1);
        repoRewards.allocateRewards(orgId, contributors, shares);

        // Note: The vault already has assets from the deposit and yield
        // When claiming, the strategy will redeem shares from the vault

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
        uint256 depositAmount = 1000e18;
        uint256 yieldAmount = 100e18;
        uint256 rewardShares = 100e18;

        // Setup: deposit, harvest to create pending rewards
        token1.mint(address(this), depositAmount);
        token1.approve(address(repoRewards), depositAmount);
        repoRewards.addPrincipal(orgId, depositAmount);
        // Simulate yield in the vault
        yieldSource1.simulateYield(yieldAmount);
        vm.prank(keeper);
        repoRewards.harvest(orgId);

        // Allocate rewards
        address[] memory contributors = new address[](1);
        contributors[0] = contributor1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = rewardShares;

        vm.prank(management1);
        repoRewards.allocateRewards(orgId, contributors, shares);

        assertEq(
            repoRewards.getContributorReward(orgId, contributor1),
            rewardShares,
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
