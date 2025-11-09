# RepoRewards

A protocol that rewards open source contributors using public good funding, integrated with the Octant protocol.

## Overview

RepoRewards enables the distribution of rewards to open source contributors based on their contributions. The protocol integrates with Octant to receive public good funding and distributes it fairly to registered contributors.

## Features

- **Contributor Registration**: Contributors can register with their GitHub username
- **Reward Distribution**: Owner can distribute rewards to multiple contributors based on their contributions
- **Funding Reception**: Accepts funding from donors or the Octant protocol
- **Transparent Tracking**: All contributions and rewards are recorded on-chain

## Project Structure

```
RepoRewards_contracts/
├── src/
│   ├── RepoRewards.sol          # Main contract
│   └── interfaces/
│       └── IOctant.sol          # Octant protocol interface
├── test/
│   └── RepoRewards.t.sol        # Test suite
├── foundry.toml                 # Foundry configuration
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

### Registering as a Contributor

```solidity
repoRewards.registerContributor("your-github-username");
```

### Receiving Funding

```solidity
// Approve tokens first
rewardToken.approve(address(repoRewards), amount);
// Then receive funding
repoRewards.receiveFunding(amount);
```

### Distributing Rewards

```solidity
address[] memory recipients = [contributor1, contributor2];
uint256[] memory amounts = [100e18, 200e18];
string[] memory repositories = ["repo1", "repo2"];

repoRewards.distributeRewards(recipients, amounts, repositories);
```

## Integration with Octant

The contract is designed to integrate with the Octant protocol for public good funding. The `IOctant` interface provides the necessary functions to interact with Octant, though the actual implementation should be updated based on Octant's contract interface.

## License

MIT

