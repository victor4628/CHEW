# CHEW Restaurant DAO

A decentralized autonomous organization (DAO) for restaurant governance with ICO crowdfunding, enabling transparent financial management, community-driven menu voting, and proportional profit distribution to token holders.

**Tech Stack:** Solidity 0.8.24 | OpenZeppelin v5.0 | Hardhat 3 | Ethers.js v6 | Sepolia Testnet

## Overview

CHEW turns a restaurant's profit rights and governance rights into on-chain smart contracts. Investors hold CHEW tokens like shares, all money flows and dividend rules are written into code — public, transparent, and immutable.

## Smart Contracts

| Contract | Purpose |
|----------|---------|
| `musdt.sol` | Mock USDT (6 decimals) for testing |
| `CHEWToken.sol` | ERC20Votes governance token — voting rights and dividends |
| `CHEWRestaurantAccounts.sol` | Three-account treasury (Receiving / Operating / Reserve) |
| `CHEWGovernanceProposal.sol` | On-chain proposals with 60% threshold and 7-day voting |
| `CHEWMenuVoting.sol` | Quarterly menu voting, selects top 20 dishes per season |
| `CHEWCrowdsale.sol` | ICO — sells CHEW for mUSDT, funds the Reserve on close |

## Fund Flow

```
ICO Phase:
  Investor → [mUSDT] → Crowdsale → [mints CHEW] → Investor
                           ↓ endSale()
                   RestaurantAccounts (Reserve)

Operations Phase:
  Customer Payments → Receiving Account
                           ↓ monthlySettlement()
                    ↙              ↘
              Operating           Reserve
          (rent/salaries)      (savings)
                                    ↓ distributeDividends()
                           CHEW Token Holders
```

## Token Economics

- Supply is dynamic — minted exclusively through Crowdsale
- Crowdsale permanently renounces `MINTER_ROLE` after `endSale()`
- Voting power requires delegation: `CHEWToken.delegate(yourAddress)`

## Deployment Guide

### Prerequisites

- MetaMask with Sepolia ETH
- Node.js installed
- OpenZeppelin Contracts v5.0

### Step 1: Install dependencies

```bash
npm install
```

### Step 2: Set environment variables

```bash
cp .env.example .env
# Fill in SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY
```

### Step 3: Deploy all 6 contracts (in this exact order)

```bash
npx hardhat ignition deploy ignition/modules/CHEW.ts --network sepolia
```

Or deploy manually in Remix in this order:

1. `musdt.sol`
2. `CHEWToken.sol` — constructor: `(musdt address)`
3. `CHEWRestaurantAccounts.sol` — constructor: `(musdt address, CHEWToken address)`
4. `CHEWGovernanceProposal.sol` — constructor: `(CHEWToken address, RestaurantAccounts address)`
5. `CHEWMenuVoting.sol` — constructor: `(CHEWToken address)`
6. `CHEWCrowdsale.sol` — constructor: `(CHEWToken address, musdt address, RestaurantAccounts address, rate)`
   - Example rate: `10000000000000000000` = 10 CHEW per 1 mUSDT

### Step 4: Post-deployment configuration (CRITICAL)

Call these from the deployer wallet using Remix or Etherscan:

```solidity
// 1. Grant Crowdsale minting rights
CHEWToken.grantRole(MINTER_ROLE, Crowdsale.address)

// 2. Grant RestaurantAccounts dividend distribution rights
CHEWToken.grantRole(DISTRIBUTOR_ROLE, RestaurantAccounts.address)

// 3. Grant GovernanceProposal admin control over RestaurantAccounts
RestaurantAccounts.grantRole(DEFAULT_ADMIN_ROLE, GovernanceProposal.address)

// 4. Grant Crowdsale treasurer rights so endSale() can fund the Reserve
RestaurantAccounts.grantRole(TREASURER_ROLE, Crowdsale.address)

// 5. Delegate CHEW for voting (each token holder must do this)
CHEWToken.delegate(yourAddress)
```

## Deployed Contracts (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| MockUSDT | `0x...` |
| CHEWToken | `0x...` |
| RestaurantAccounts | `0x...` |
| GovernanceProposal | `0x...` |
| MenuVoting | `0x...` |
| Crowdsale | `0x...` |

> Update with actual deployment addresses after deploying.

## Key Parameters

```
RestaurantAccounts:
  profitMargin          = 70%
  monthlyRent           = 6,000 mUSDT
  monthlyUtilities      = 1,000 mUSDT
  largeExpenseThreshold = 2,000 mUSDT
  dividendRatio         = 80%
  minReserve            = 80,000 mUSDT

GovernanceProposal:
  VOTING_PERIOD         = 7 days
  APPROVAL_THRESHOLD    = 60%

MenuVoting:
  MAX_MENU_SIZE         = 20 dishes
  VOTING_PERIOD         = 90 days
```

## Running Tests

```bash
npx hardhat test
```

## License

MIT
