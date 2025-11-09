// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {YieldDonatingStrategy} from "./YieldDonatingStrategy.sol";
import {
    ITokenizedStrategy
} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RepoRewards
 * @notice Manages multiple organizations, each with their own yield strategy
 * @dev Each organization has a YieldDonatingStrategy instance that generates yield
 *      from a shared yield source (Yearn). Yield is distributed to contributors.
 */
contract RepoRewards is Ownable {
    using SafeERC20 for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Organization data structure
     * @param strategy Address of the organization's YieldDonatingStrategy
     * @param token Address of the organization's reward token
     * @param management Address with management permissions for the strategy
     * @param totalPrincipal Total principal amount deposited by the organization
     */
    struct Organization {
        address strategy;
        address token;
        address management;
        uint256 totalPrincipal;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Shared yield source address (Yearn vault)
    address public immutable yieldSource;

    /// @notice Keeper address for strategies
    address public immutable keeper;

    /// @notice Emergency admin address for strategies
    address public immutable emergencyAdmin;

    /// @notice Whether burning is enabled for strategies
    bool public immutable enableBurning;

    /// @notice TokenizedStrategy implementation address
    address public immutable tokenizedStrategyAddress;

    /// @notice Counter for the next organization ID
    uint256 public nextOrgId;

    /// @notice Mapping from organization ID to Organization struct
    mapping(uint256 => Organization) public organizations;

    /// @notice Mapping from organization ID => contributor address => reward shares
    /// @dev Rewards are tracked in strategy shares, not base assets
    mapping(uint256 => mapping(address => uint256)) public contributorRewards;

    /// @notice Mapping from organization ID => total pending reward shares
    /// @dev Total shares available for distribution to contributors
    mapping(uint256 => uint256) public totalPendingRewards;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _yieldSource Address of the shared yield source (Yearn vault)
     * @param _keeper Keeper address for strategies
     * @param _emergencyAdmin Emergency admin address for strategies
     * @param _enableBurning Whether burning is enabled for strategies
     * @param _tokenizedStrategyAddress TokenizedStrategy implementation address
     */
    constructor(
        address _yieldSource,
        address _keeper,
        address _emergencyAdmin,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    ) Ownable(msg.sender) {
        require(_yieldSource != address(0), "Invalid yield source");
        require(_keeper != address(0), "Invalid keeper");
        require(_emergencyAdmin != address(0), "Invalid emergency admin");
        require(
            _tokenizedStrategyAddress != address(0),
            "Invalid tokenized strategy"
        );

        yieldSource = _yieldSource;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        enableBurning = _enableBurning;
        tokenizedStrategyAddress = _tokenizedStrategyAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            ORGANIZATION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new organization
     * @param _token Address of the organization's reward token
     * @param _management Address with management permissions for the strategy
     * @param _name Name for the strategy
     * @return orgId The assigned organization ID
     * @return strategy Address of the deployed YieldDonatingStrategy
     */
    function registerOrganization(
        address _token,
        address _management,
        string memory _name
    ) external onlyOwner returns (uint256 orgId, address strategy) {
        require(_token != address(0), "Invalid token");
        require(_management != address(0), "Invalid management");

        // Assign the next available organization ID
        orgId = nextOrgId;
        nextOrgId++;

        // Deploy new YieldDonatingStrategy for this organization
        strategy = address(
            new YieldDonatingStrategy(
                yieldSource,
                _token,
                _name,
                _management,
                keeper,
                emergencyAdmin,
                address(this), // donationAddress = this contract
                enableBurning,
                tokenizedStrategyAddress
            )
        );

        organizations[orgId] = Organization({
            strategy: strategy,
            token: _token,
            management: _management,
            totalPrincipal: 0
        });

        emit OrganizationRegistered(orgId, strategy, _token, _management);
    }

    /*//////////////////////////////////////////////////////////////
                            PRINCIPAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add principal to an organization's strategy
     * @param _orgId Organization ID
     * @param _amount Amount of tokens to deposit
     */
    function addPrincipal(uint256 _orgId, uint256 _amount) external {
        Organization memory org = organizations[_orgId];
        require(org.strategy != address(0), "Organization not found");

        ERC20 token = ERC20(org.token);
        require(_amount > 0, "Amount must be greater than 0");

        // Transfer tokens from caller to this contract
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // Approve strategy to spend tokens
        token.safeApprove(org.strategy, _amount);

        // Deposit into strategy
        ITokenizedStrategy(org.strategy).deposit(_amount, address(this));

        // Update total principal
        organizations[_orgId].totalPrincipal += _amount;

        emit PrincipalAdded(_orgId, org.token, _amount);
    }

    /**
     * @notice Reduce principal from an organization's strategy
     * @param _orgId Organization ID
     * @param _amount Amount of tokens to withdraw
     */
    function reducePrincipal(uint256 _orgId, uint256 _amount) external {
        Organization memory org = organizations[_orgId];
        require(org.strategy != address(0), "Organization not found");
        require(
            msg.sender == org.management || msg.sender == owner(),
            "Not authorized"
        );
        require(_amount > 0, "Amount must be greater than 0");
        require(
            organizations[_orgId].totalPrincipal >= _amount,
            "Insufficient principal"
        );

        // Withdraw from strategy (maxLoss = 0 for now, can be made configurable)
        ITokenizedStrategy(org.strategy).withdraw(
            _amount,
            address(this),
            address(this),
            0
        );

        // Transfer tokens back to caller
        ERC20 token = ERC20(org.token);
        token.safeTransfer(msg.sender, _amount);

        // Update total principal
        organizations[_orgId].totalPrincipal -= _amount;

        emit PrincipalReduced(_orgId, org.token, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARD MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Harvest rewards from an organization's strategy
     * @dev Calls report() on the strategy which mints profit shares to this contract
     * @param _orgId Organization ID
     * @return profit Profit generated since last harvest (in asset units)
     * @return loss Loss incurred since last harvest (in asset units)
     */
    function harvest(
        uint256 _orgId
    ) external returns (uint256 profit, uint256 loss) {
        Organization memory org = organizations[_orgId];
        require(org.strategy != address(0), "Organization not found");

        // Get current share balance before report
        ITokenizedStrategy strategy = ITokenizedStrategy(org.strategy);
        uint256 sharesBefore = strategy.balanceOf(address(this));

        // Call report() on the strategy to harvest and account for profits/losses
        // This will mint profit shares to this contract (as donationAddress)
        (profit, loss) = strategy.report();

        // If there's profit, calculate the shares minted to this contract
        if (profit > 0) {
            uint256 sharesAfter = strategy.balanceOf(address(this));
            uint256 sharesMinted = sharesAfter - sharesBefore;

            // Track the minted shares as pending rewards
            totalPendingRewards[_orgId] += sharesMinted;

            emit RewardsHarvested(_orgId, profit, totalPendingRewards[_orgId]);
        }
    }

    /**
     * @notice Allocate harvested rewards to contributors
     * @dev Allocates strategy shares to contributors based on their contribution
     * @param _orgId Organization ID
     * @param _contributors Array of contributor addresses
     * @param _shares Array of reward shares (must match contributors length)
     */
    function allocateRewards(
        uint256 _orgId,
        address[] calldata _contributors,
        uint256[] calldata _shares
    ) external {
        Organization memory org = organizations[_orgId];
        require(org.strategy != address(0), "Organization not found");
        require(
            msg.sender == org.management || msg.sender == owner(),
            "Not authorized"
        );
        require(
            _contributors.length == _shares.length,
            "Arrays length mismatch"
        );

        uint256 totalAllocated = 0;
        for (uint256 i = 0; i < _contributors.length; i++) {
            require(_contributors[i] != address(0), "Invalid contributor");
            require(_shares[i] > 0, "Shares must be greater than 0");

            contributorRewards[_orgId][_contributors[i]] += _shares[i];
            totalAllocated += _shares[i];

            emit ContributorRewardAllocated(
                _orgId,
                _contributors[i],
                _shares[i]
            );
        }

        require(
            totalAllocated <= totalPendingRewards[_orgId],
            "Insufficient pending rewards"
        );

        totalPendingRewards[_orgId] -= totalAllocated;
    }

    /**
     * @notice Claim rewards for a contributor
     * @dev Redeems strategy shares for base assets and transfers to contributor
     * @param _orgId Organization ID
     */
    function claim(uint256 _orgId) external {
        Organization memory org = organizations[_orgId];
        require(org.strategy != address(0), "Organization not found");

        uint256 rewardShares = contributorRewards[_orgId][msg.sender];
        require(rewardShares > 0, "No rewards to claim");

        // Reset reward balance
        contributorRewards[_orgId][msg.sender] = 0;

        // Redeem strategy shares for base assets and transfer to contributor
        // The shares are owned by this contract, so we redeem on behalf of this contract
        ITokenizedStrategy(org.strategy).redeem(
            rewardShares,
            msg.sender, // receiver gets the assets
            address(this), // owner is this contract
            0 // maxLoss = 0
        );

        emit RewardsClaimed(_orgId, msg.sender, rewardShares);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get organization data
     * @param _orgId Organization ID
     * @return Organization struct
     */
    function getOrganization(
        uint256 _orgId
    ) external view returns (Organization memory) {
        return organizations[_orgId];
    }

    /**
     * @notice Get contributor reward balance in shares
     * @param _orgId Organization ID
     * @param _contributor Contributor address
     * @return Reward shares
     */
    function getContributorReward(
        uint256 _orgId,
        address _contributor
    ) external view returns (uint256) {
        return contributorRewards[_orgId][_contributor];
    }

    /**
     * @notice Get contributor reward balance in asset units
     * @param _orgId Organization ID
     * @param _contributor Contributor address
     * @return Reward amount in asset units
     */
    function getContributorRewardInAssets(
        uint256 _orgId,
        address _contributor
    ) external view returns (uint256) {
        Organization memory org = organizations[_orgId];
        require(org.strategy != address(0), "Organization not found");

        uint256 shares = contributorRewards[_orgId][_contributor];
        if (shares == 0) {
            return 0;
        }

        // Convert shares to assets using the strategy's conversion rate
        ITokenizedStrategy strategy = ITokenizedStrategy(org.strategy);
        return strategy.convertToAssets(shares);
    }

    /**
     * @notice Get total number of organizations
     * @return Number of organizations
     */
    function getOrganizationCount() external view returns (uint256) {
        return nextOrgId;
    }
}
