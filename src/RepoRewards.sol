// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldDonatingStrategy} from "./YieldDonatingStrategy.sol";

/**
 * @title RepoRewards
 * @notice A protocol that enables organizations to reward open source contributors
 * @dev Integrates with Octant protocol for public good funding distribution
 */
contract RepoRewards {
    // Events
    event OrganizationRegistered(
        uint256 indexed orgId,
        address indexed admin,
        string name,
        address indexed strategy
    );
    event StrategyDeployed(uint256 indexed orgId, address indexed strategy);
    event MonthlyDistributionCreated(
        uint256 indexed orgId,
        uint256 indexed distributionId,
        uint256 month,
        uint256 year
    );
    event RewardsDistributed(
        uint256 indexed orgId,
        uint256 indexed distributionId,
        address indexed recipient,
        uint256 amount
    );
    event FundingReceived(
        uint256 indexed orgId,
        address indexed donor,
        uint256 amount
    );

    // Structs
    struct Organization {
        uint256 orgId;
        address admin;
        string name;
        bool isActive;
        uint256 totalFundsReceived;
        uint256 totalFundsDistributed;
    }

    struct RewardRecipient {
        address wallet;
        uint256 ratio; // Basis points (10000 = 100%)
    }

    struct MonthlyDistribution {
        uint256 distributionId;
        uint256 orgId;
        uint256 month;
        uint256 year;
        uint256 totalAmount;
        uint256 distributedAmount;
        bool isDistributed;
        RewardRecipient[] recipients;
    }

    // State variables
    uint256 public nextOrgId = 1;
    uint256 public nextDistributionId = 1;

    mapping(uint256 => Organization) public organizations;
    mapping(uint256 => MonthlyDistribution) public distributions;
    mapping(uint256 => uint256[]) public orgDistributions; // orgId => distributionIds[]
    mapping(address => uint256) public addressToOrgId; // admin address => orgId
    mapping(uint256 => address) public orgStrategies; // orgId => strategy address
    mapping(uint256 => address) public orgYieldSources; // orgId => yield source address

    IERC20 public immutable rewardToken;
    address public owner;

    // Strategy configuration (shared across all strategies)
    address public immutable keeper;
    address public immutable emergencyAdmin;
    bool public immutable enableBurning;
    address public immutable tokenizedStrategyAddress;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "RepoRewards: not owner");
        _;
    }

    modifier onlyOrgAdmin(uint256 _orgId) {
        require(
            organizations[_orgId].admin == msg.sender,
            "RepoRewards: not org admin"
        );
        require(organizations[_orgId].isActive, "RepoRewards: org not active");
        _;
    }

    modifier validOrg(uint256 _orgId) {
        require(_orgId > 0 && _orgId < nextOrgId, "RepoRewards: invalid org");
        require(organizations[_orgId].isActive, "RepoRewards: org not active");
        _;
    }

    /**
     * @notice Constructor
     * @param _rewardToken Address of the ERC20 token used for rewards
     * @param _keeper Address with keeper role for strategies
     * @param _emergencyAdmin Address with emergency admin role for strategies
     * @param _enableBurning Whether loss-protection burning is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _rewardToken,
        address _keeper,
        address _emergencyAdmin,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    ) {
        require(_rewardToken != address(0), "RepoRewards: invalid token");
        require(_keeper != address(0), "RepoRewards: invalid keeper");
        require(
            _emergencyAdmin != address(0),
            "RepoRewards: invalid emergency admin"
        );
        require(
            _tokenizedStrategyAddress != address(0),
            "RepoRewards: invalid tokenized strategy"
        );

        rewardToken = IERC20(_rewardToken);
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        enableBurning = _enableBurning;
        tokenizedStrategyAddress = _tokenizedStrategyAddress;
        owner = msg.sender;
    }

    /**
     * @notice Register a new organization
     * @param _admin Address of the organization admin
     * @param _name Name of the organization
     * @param _yieldSource Address of the yield source for this organization (e.g., Aave pool, Compound, Yearn vault)
     * @return orgId The ID of the newly registered organization
     */
    function registerOrganization(
        address _admin,
        string memory _name,
        address _yieldSource
    ) external onlyOwner returns (uint256) {
        require(_admin != address(0), "RepoRewards: invalid admin");
        require(bytes(_name).length > 0, "RepoRewards: invalid name");
        require(
            _yieldSource != address(0),
            "RepoRewards: invalid yield source"
        );
        require(
            addressToOrgId[_admin] == 0,
            "RepoRewards: admin already registered"
        );

        uint256 orgId = nextOrgId++;
        organizations[orgId] = Organization({
            orgId: orgId,
            admin: _admin,
            name: _name,
            isActive: true,
            totalFundsReceived: 0,
            totalFundsDistributed: 0
        });

        addressToOrgId[_admin] = orgId;
        orgYieldSources[orgId] = _yieldSource;

        // Deploy YieldDonatingStrategy for this organization
        string memory strategyName = string(
            abi.encodePacked("RepoRewards-", _name)
        );
        YieldDonatingStrategy strategy = new YieldDonatingStrategy(
            _yieldSource,
            address(rewardToken),
            strategyName,
            _admin, // management role goes to org admin
            keeper,
            emergencyAdmin,
            address(this), // donation address is this contract
            enableBurning,
            tokenizedStrategyAddress
        );

        orgStrategies[orgId] = address(strategy);

        emit StrategyDeployed(orgId, address(strategy));
        emit OrganizationRegistered(orgId, _admin, _name, address(strategy));
        return orgId;
    }

    /**
     * @notice Create a monthly distribution with reward recipients and ratios
     * @param _orgId ID of the organization
     * @param _month Month of the distribution (1-12)
     * @param _year Year of the distribution
     * @param _recipients Array of reward recipients with their ratios
     * @param _totalAmount Total amount to be distributed
     * @return distributionId The ID of the newly created distribution
     */
    function createMonthlyDistribution(
        uint256 _orgId,
        uint256 _month,
        uint256 _year,
        RewardRecipient[] memory _recipients,
        uint256 _totalAmount
    ) external onlyOrgAdmin(_orgId) returns (uint256) {
        require(_month >= 1 && _month <= 12, "RepoRewards: invalid month");
        require(_year > 0, "RepoRewards: invalid year");
        require(_totalAmount > 0, "RepoRewards: invalid amount");
        require(_recipients.length > 0, "RepoRewards: no recipients");

        // Validate ratios sum to 100%
        uint256 totalRatio = 0;
        for (uint256 i = 0; i < _recipients.length; i++) {
            require(
                _recipients[i].wallet != address(0),
                "RepoRewards: invalid wallet"
            );
            require(
                _recipients[i].ratio > 0 &&
                    _recipients[i].ratio <= BASIS_POINTS,
                "RepoRewards: invalid ratio"
            );
            totalRatio += _recipients[i].ratio;
        }
        require(
            totalRatio == BASIS_POINTS,
            "RepoRewards: ratios must sum to 100%"
        );

        // Check if organization has sufficient balance
        require(
            getOrgBalance(_orgId) >= _totalAmount,
            "RepoRewards: insufficient org balance"
        );

        uint256 distributionId = nextDistributionId++;
        MonthlyDistribution storage distribution = distributions[
            distributionId
        ];

        distribution.distributionId = distributionId;
        distribution.orgId = _orgId;
        distribution.month = _month;
        distribution.year = _year;
        distribution.totalAmount = _totalAmount;
        distribution.distributedAmount = 0;
        distribution.isDistributed = false;

        // Copy recipients array
        for (uint256 i = 0; i < _recipients.length; i++) {
            distribution.recipients.push(_recipients[i]);
        }

        orgDistributions[_orgId].push(distributionId);

        emit MonthlyDistributionCreated(_orgId, distributionId, _month, _year);
        return distributionId;
    }

    /**
     * @notice Distribute rewards for a monthly distribution
     * @param _distributionId ID of the distribution to execute
     */
    function distributeRewards(uint256 _distributionId) external {
        MonthlyDistribution storage distribution = distributions[
            _distributionId
        ];
        require(
            distribution.distributionId > 0,
            "RepoRewards: invalid distribution"
        );
        require(
            !distribution.isDistributed,
            "RepoRewards: already distributed"
        );
        require(
            distribution.orgId > 0 &&
                organizations[distribution.orgId].isActive,
            "RepoRewards: org not active"
        );

        // Verify caller is org admin or owner
        require(
            msg.sender == organizations[distribution.orgId].admin ||
                msg.sender == owner,
            "RepoRewards: not authorized"
        );

        // Check contract has sufficient balance
        require(
            rewardToken.balanceOf(address(this)) >= distribution.totalAmount,
            "RepoRewards: insufficient contract balance"
        );

        // Distribute to each recipient based on their ratio
        for (uint256 i = 0; i < distribution.recipients.length; i++) {
            uint256 amount = (distribution.totalAmount *
                distribution.recipients[i].ratio) / BASIS_POINTS;

            require(
                rewardToken.transfer(distribution.recipients[i].wallet, amount),
                "RepoRewards: transfer failed"
            );

            distribution.distributedAmount += amount;

            emit RewardsDistributed(
                distribution.orgId,
                _distributionId,
                distribution.recipients[i].wallet,
                amount
            );
        }

        distribution.isDistributed = true;
        organizations[distribution.orgId].totalFundsDistributed += distribution
            .totalAmount;
    }

    /**
     * @notice Receive funding for an organization
     * @param _orgId ID of the organization receiving funding
     * @param _amount Amount of tokens to receive
     */
    function receiveFunding(
        uint256 _orgId,
        uint256 _amount
    ) external validOrg(_orgId) {
        require(_amount > 0, "RepoRewards: invalid amount");

        require(
            rewardToken.transferFrom(msg.sender, address(this), _amount),
            "RepoRewards: transfer failed"
        );

        organizations[_orgId].totalFundsReceived += _amount;

        emit FundingReceived(_orgId, msg.sender, _amount);
    }

    /**
     * @notice Get organization information
     * @param _orgId ID of the organization
     * @return Organization struct
     */
    function getOrganization(
        uint256 _orgId
    ) external view returns (Organization memory) {
        return organizations[_orgId];
    }

    /**
     * @notice Get monthly distribution information
     * @param _distributionId ID of the distribution
     * @return MonthlyDistribution struct
     */
    function getDistribution(
        uint256 _distributionId
    ) external view returns (MonthlyDistribution memory) {
        return distributions[_distributionId];
    }

    /**
     * @notice Get all distribution IDs for an organization
     * @param _orgId ID of the organization
     * @return Array of distribution IDs
     */
    function getOrgDistributions(
        uint256 _orgId
    ) external view returns (uint256[] memory) {
        return orgDistributions[_orgId];
    }

    /**
     * @notice Get recipients for a distribution
     * @param _distributionId ID of the distribution
     * @return Array of RewardRecipient structs
     */
    function getDistributionRecipients(
        uint256 _distributionId
    ) external view returns (RewardRecipient[] memory) {
        return distributions[_distributionId].recipients;
    }

    /**
     * @notice Get strategy address for an organization
     * @param _orgId ID of the organization
     * @return Strategy address
     */
    function getOrgStrategy(uint256 _orgId) external view returns (address) {
        return orgStrategies[_orgId];
    }

    /**
     * @notice Get yield source address for an organization
     * @param _orgId ID of the organization
     * @return Yield source address
     */
    function getOrgYieldSource(uint256 _orgId) external view returns (address) {
        return orgYieldSources[_orgId];
    }

    /**
     * @notice Get organization's available balance (total received - total distributed)
     * @param _orgId ID of the organization
     * @return Available balance for the organization
     */
    function getOrgBalance(uint256 _orgId) public view returns (uint256) {
        Organization memory org = organizations[_orgId];
        if (!org.isActive) return 0;

        // For simplicity, we track funds per org but store them in the contract
        // In a production system, you might want separate accounting per org
        uint256 available = org.totalFundsReceived - org.totalFundsDistributed;

        // Ensure we don't exceed contract balance
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        return available > contractBalance ? contractBalance : available;
    }

    /**
     * @notice Get contract's total balance
     * @return Total balance of reward tokens
     */
    function getContractBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    /**
     * @notice Deactivate an organization (only owner)
     * @param _orgId ID of the organization to deactivate
     */
    function deactivateOrganization(uint256 _orgId) external onlyOwner {
        require(
            organizations[_orgId].isActive,
            "RepoRewards: already inactive"
        );
        organizations[_orgId].isActive = false;
    }

    /**
     * @notice Reactivate an organization (only owner)
     * @param _orgId ID of the organization to reactivate
     */
    function reactivateOrganization(uint256 _orgId) external onlyOwner {
        require(!organizations[_orgId].isActive, "RepoRewards: already active");
        organizations[_orgId].isActive = true;
    }
}
