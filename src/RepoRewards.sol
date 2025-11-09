// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RepoRewards
 * @notice A protocol that rewards open source contributors using public good funding
 * @dev Integrates with Octant protocol for public good funding distribution
 */
contract RepoRewards {
    // Events
    event ContributorRegistered(
        address indexed contributor,
        string githubUsername
    );
    event ContributionRewarded(
        address indexed contributor,
        uint256 amount,
        string repository,
        uint256 timestamp
    );
    event FundingReceived(address indexed donor, uint256 amount);
    event FundsDistributed(uint256 totalAmount, uint256 contributorCount);

    // Structs
    struct Contributor {
        address wallet;
        string githubUsername;
        uint256 totalRewards;
        bool isRegistered;
    }

    struct Contribution {
        address contributor;
        string repository;
        uint256 amount;
        uint256 timestamp;
    }

    // State variables
    mapping(address => Contributor) public contributors;
    mapping(string => address) public githubToAddress;
    Contribution[] public contributions;

    address public immutable octantProtocol;
    IERC20 public immutable rewardToken;
    address public owner;

    uint256 public totalFundsReceived;
    uint256 public totalFundsDistributed;

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "RepoRewards: not owner");
        _;
    }

    modifier onlyRegistered(address contributor) {
        require(
            contributors[contributor].isRegistered,
            "RepoRewards: not registered"
        );
        _;
    }

    /**
     * @notice Constructor
     * @param _octantProtocol Address of the Octant protocol contract
     * @param _rewardToken Address of the ERC20 token used for rewards
     */
    constructor(address _octantProtocol, address _rewardToken) {
        require(
            _octantProtocol != address(0),
            "RepoRewards: invalid octant address"
        );
        require(
            _rewardToken != address(0),
            "RepoRewards: invalid token address"
        );

        octantProtocol = _octantProtocol;
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender;
    }

    /**
     * @notice Register a contributor with their GitHub username
     * @param _githubUsername GitHub username of the contributor
     */
    function registerContributor(string memory _githubUsername) external {
        require(
            bytes(_githubUsername).length > 0,
            "RepoRewards: invalid username"
        );
        require(
            !contributors[msg.sender].isRegistered,
            "RepoRewards: already registered"
        );
        require(
            githubToAddress[_githubUsername] == address(0),
            "RepoRewards: username taken"
        );

        contributors[msg.sender] = Contributor({
            wallet: msg.sender,
            githubUsername: _githubUsername,
            totalRewards: 0,
            isRegistered: true
        });

        githubToAddress[_githubUsername] = msg.sender;

        emit ContributorRegistered(msg.sender, _githubUsername);
    }

    /**
     * @notice Distribute rewards to contributors based on their contributions
     * @param _recipients Array of contributor addresses
     * @param _amounts Array of reward amounts corresponding to each contributor
     * @param _repositories Array of repository names for each contribution
     */
    function distributeRewards(
        address[] memory _recipients,
        uint256[] memory _amounts,
        string[] memory _repositories
    ) external onlyOwner {
        require(
            _recipients.length == _amounts.length &&
                _amounts.length == _repositories.length,
            "RepoRewards: array length mismatch"
        );

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalAmount += _amounts[i];
        }

        require(
            rewardToken.balanceOf(address(this)) >= totalAmount,
            "RepoRewards: insufficient balance"
        );

        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            uint256 amount = _amounts[i];

            require(
                contributors[recipient].isRegistered,
                "RepoRewards: recipient not registered"
            );

            contributors[recipient].totalRewards += amount;
            totalFundsDistributed += amount;

            contributions.push(
                Contribution({
                    contributor: recipient,
                    repository: _repositories[i],
                    amount: amount,
                    timestamp: block.timestamp
                })
            );

            require(
                rewardToken.transfer(recipient, amount),
                "RepoRewards: transfer failed"
            );

            emit ContributionRewarded(
                recipient,
                amount,
                _repositories[i],
                block.timestamp
            );
        }

        emit FundsDistributed(totalAmount, _recipients.length);
    }

    /**
     * @notice Receive funding from donors or Octant protocol
     * @param _amount Amount of tokens received
     */
    function receiveFunding(uint256 _amount) external {
        require(_amount > 0, "RepoRewards: invalid amount");

        require(
            rewardToken.transferFrom(msg.sender, address(this), _amount),
            "RepoRewards: transfer failed"
        );

        totalFundsReceived += _amount;
        emit FundingReceived(msg.sender, _amount);
    }

    /**
     * @notice Get contributor information
     * @param _contributor Address of the contributor
     * @return Contributor struct with contributor details
     */
    function getContributor(
        address _contributor
    ) external view returns (Contributor memory) {
        return contributors[_contributor];
    }

    /**
     * @notice Get total number of contributions
     * @return Total number of contributions recorded
     */
    function getContributionCount() external view returns (uint256) {
        return contributions.length;
    }

    /**
     * @notice Get contribution by index
     * @param _index Index of the contribution
     * @return Contribution struct
     */
    function getContribution(
        uint256 _index
    ) external view returns (Contribution memory) {
        require(_index < contributions.length, "RepoRewards: invalid index");
        return contributions[_index];
    }

    /**
     * @notice Get contract balance
     * @return Current balance of reward tokens in the contract
     */
    function getBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
}
