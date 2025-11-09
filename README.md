# RepoRewards

A protocol that enables organizations to reward open source contributors using public good funding, integrated with the Octant protocol.

## Overview

RepoRewards allows organizations to register and manage their open source projects, then distribute monthly rewards to contributors based on their contributions. The protocol integrates with Octant to receive public good funding and enables transparent, on-chain reward distribution.

## Features

- **Organization Registration**: Organizations can register with an admin address
- **Project Management**: Each organization can add multiple open source repositories
- **Monthly Distributions**: Admins can create monthly reward distributions with contributor addresses and reward ratios
- **Ratio-Based Rewards**: Distribute rewards based on contribution ratios (basis points)
- **Funding Reception**: Organizations can receive funding from donors or the Octant protocol
- **Transparent Tracking**: All distributions and rewards are recorded on-chain

## Project Structure

```
RepoRewards_contracts/
├── src/
│   ├── RepoRewards.sol          # Main contract
│   └── interfaces/
│       └── IOctant.sol           # Octant protocol interface
├── test/
│   └── RepoRewards.t.sol         # Test suite
├── script/
│   └── Deploy.s.sol              # Deployment script
├── foundry.toml                  # Foundry configuration
└── README.md
```

## Setup

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:
```bash
forge install OpenZeppelin/openzeppelin-contracts
```

3. Build:
```bash
forge build
```

4. Run tests:
```bash
forge test
```

## Usage

### Deploying the Contract

```solidity
// Deploy with Octant protocol address and reward token address
RepoRewards repoRewards = new RepoRewards(octantProtocolAddress, rewardTokenAddress);
```

### Registering an Organization

Only the contract owner can register organizations:

```solidity
uint256 orgId = repoRewards.registerOrganization(adminAddress, "Organization Name");
```

### Adding Projects

Organization admins can add open source repositories:

```solidity
// Must be called by the organization admin
uint256 projectId = repoRewards.addProject(orgId, "https://github.com/org/repo");
```

### Receiving Funding

Anyone can send funding to an organization:

```solidity
// Approve tokens first
rewardToken.approve(address(repoRewards), amount);
// Then send funding
repoRewards.receiveFunding(orgId, amount);
```

### Creating Monthly Distributions

Organization admins create monthly distributions with contributor addresses and reward ratios:

```solidity
// Ratios are in basis points (10000 = 100%)
RepoRewards.RewardRecipient[] memory recipients = new RepoRewards.RewardRecipient[](2);
recipients[0] = RepoRewards.RewardRecipient({
    wallet: contributor1,
    ratio: 6000  // 60%
});
recipients[1] = RepoRewards.RewardRecipient({
    wallet: contributor2,
    ratio: 4000  // 40%
});

// Must be called by the organization admin
uint256 distributionId = repoRewards.createMonthlyDistribution(
    orgId,
    1,      // month (1-12)
    2024,   // year
    recipients,
    10000e18 // total amount to distribute
);
```

### Distributing Rewards

Execute a distribution to send rewards to contributors:

```solidity
// Can be called by org admin or contract owner
repoRewards.distributeRewards(distributionId);
```

## Key Concepts

### Organizations
- Each organization has a unique ID and an admin address
- Admins can add projects and create distributions
- Organizations track total funds received and distributed

### Projects
- Projects represent open source repositories
- Each project belongs to one organization
- Projects are identified by their repository URL

### Monthly Distributions
- Created by organization admins at the end of each month
- Contains contributor addresses and their reward ratios
- Ratios must sum to 100% (10000 basis points)
- Once distributed, cannot be distributed again

### Reward Ratios
- Ratios are specified in basis points (1 basis point = 0.01%)
- 10000 basis points = 100%
- Each recipient's reward = (totalAmount * ratio) / 10000

## Integration with Octant

The contract is designed to integrate with the Octant protocol for public good funding. Organizations can receive funding from Octant, and the `IOctant` interface provides the necessary functions to interact with Octant's contract system.

## Security Considerations

- Only contract owner can register organizations
- Only organization admins can add projects and create distributions
- Distributions can be executed by org admins or contract owner
- Ratios are validated to sum to 100%
- Organizations can be deactivated by the owner

## License

MIT
