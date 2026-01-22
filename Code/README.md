# 🍽️ Crypto Restaurant DAO

A decentralized autonomous organization (DAO) for restaurant governance with ICO crowdfunding, enabling transparent financial management, community-driven menu voting, and proportional profit distribution to token holders.

**Tech Stack:** Solidity 0.8.24 | OpenZeppelin v5.0 | Ethereum

**License:** MIT

## 📖 Overview

Crypto Restaurant DAO revolutionizes restaurant operations through blockchain technology, implementing a complete lifecycle from fundraising to operations:

### Phase 1: Token Sale (ICO)
- **Crowdsale Contract**: Investors purchase CHEW tokens with mUSDT
- **Automatic Capital Allocation**: All proceeds flow directly to restaurant reserve fund
- **One-Time Minting**: After ICO concludes, minting capability is permanently revoked

### Phase 2: Restaurant Operations
- **Three-Account Treasury**: Automated fund allocation (Receiving/Operating/Reserve)
- **Token-Based Governance**: CHEW holders vote on parameters, expenses, and menu items
- **Dividend Distribution**: Annual USDT profit-sharing proportional to holdings
- **Progressive Decentralization**: Gradual transition from centralized to community governance

## 🏗️ System Architecture

### Smart Contract Suite

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **MockUSDT** | Test stablecoin (6 decimals) | Simulates USDT for development |
| **CHEWToken_v2** | ERC20Votes governance token | Voting rights, dividends, snapshot protection |
| **Crowdsale** | ICO fundraising | Token distribution, capital collection, auto-shutdown |
| **RestaurantAccounts_v2** | Treasury management | Three accounts, settlements, whitelists |
| **MenuVoting** | Quarterly menu governance | 20-dish selection, snapshot voting |
| **GovernanceProposal** | Parameter proposals | 60% threshold, 7-day voting, automated execution |

### Fund Flow Diagram

```
ICO Phase:
Investors → [mUSDT] → Crowdsale → [mints CHEW] → Investors
                         ↓
                   [ICO ends]
                         ↓
              RestaurantAccounts (Reserve)

Operations Phase:
Customer Payments → Receiving Account
                         ↓
                   Monthly Settlement
                    ↓          ↓
            Operating       Reserve
          (rent/salaries)   (savings)
                                ↓
                      Annual Dividends
                                ↓
                      CHEW Token Holders
```

## 🔑 Key Innovations

### 1. ICO-to-Operations Pipeline
- **Single-Use Crowdsale**: Minting rights automatically revoked after ICO
- **Direct Reserve Funding**: `fundReserveWithICOCapital()` bypasses daily operations
- **Decentralization Enforcement**: Crowdsale contract renounces minter role

### 2. Financial Management
- **70% Profit Margin** allocation formula
- **Automated Payments**: Rent ($6K), utilities ($1K), employee salaries
- **Tiered Approvals**: Small expenses (<$2K) immediate, large require voting
- **Year-End Dividends**: 80% distribution with $80K minimum reserve

### 3. Security Features
- **Snapshot Voting**: Prevents flash loan manipulation
- **ReentrancyGuard**: All state-changing functions protected
- **Role-Based Access**: ADMIN, MANAGER, TREASURER, MINTER, DISTRIBUTOR
- **Decimal Precision**: 1e20 scaling eliminates rounding errors

## 📊 Token Economics

### Supply Allocation
- **Total Supply**: 500,000 CHEW (18 decimals)
- **Public Sale (ICO)**: 425,000 CHEW (85%)
- **Team Allocation**: 75,000 CHEW (15%)

### ICO Parameters
- **Exchange Rate**: Configurable (e.g., 10 CHEW per 1 mUSDT)
- **Payment Token**: MockUSDT (6 decimals)
- **Capital Usage**: 100% to restaurant reserve fund

### Governance Rights
- **Voting Power**: 1 CHEW = 1 vote (after delegation)
- **Proposal Threshold**: Must hold CHEW to create proposals
- **Approval Rate**: 60% for all governance actions

## 🚀 Complete Deployment Guide

### Prerequisites
```bash
- Remix IDE or Hardhat
- MetaMask wallet
- Sepolia ETH (testnet faucet)
- OpenZeppelin Contracts v5.0+
```

### Deployment Sequence

#### Step 1: Deploy MockUSDT
```solidity
// No constructor parameters required
// Automatically mints 1,000,000 mUSDT to deployer
```

#### Step 2: Deploy CHEWToken_v2
```solidity
constructor(address stableToken)
// stableToken: MockUSDT address

// Post-deployment: Save address for Crowdsale
```

#### Step 3: Deploy RestaurantAccounts_v2
```solidity
constructor(address _usdt, address _chewToken)
// _usdt: MockUSDT address
// _chewToken: CHEWToken_v2 address
```

#### Step 4: Deploy Crowdsale
```solidity
constructor(
    address _chewToken,        // CHEWToken_v2 address
    address _usdt,             // MockUSDT address
    address _restaurantAccounts, // RestaurantAccounts_v2 address
    uint256 _rate              // e.g., 10e18 (10 CHEW per 1 mUSDT)
)
```

#### Step 5: Deploy MenuVoting
```solidity
constructor(address _chewToken)
// _chewToken: CHEWToken_v2 address
```

#### Step 6: Deploy GovernanceProposal
```solidity
constructor(
    address _chewToken,
    address _restaurantAccounts
)
```

### Post-Deployment Configuration

```solidity
// 1. Grant Crowdsale minting rights
CHEWToken_v2.grantRole(MINTER_ROLE, Crowdsale.address)

// 2. Grant RestaurantAccounts distributor rights
CHEWToken_v2.grantRole(DISTRIBUTOR_ROLE, RestaurantAccounts_v2.address)

// 3. Grant Governance admin rights on Accounts
RestaurantAccounts_v2.grantRole(DEFAULT_ADMIN_ROLE, GovernanceProposal.address)

// 4. Delegate CHEW for voting (each token holder)
CHEWToken_v2.delegate(yourAddress)
```

## 🎮 Usage Workflows

### ICO Phase

```solidity
// Investor approves mUSDT spending
MockUSDT.approve(Crowdsale.address, 1000e6) // 1000 USDT

// Investor buys CHEW tokens
Crowdsale.buyTokens(1000e6)
// Receives CHEW based on configured rate

// After fundraising goal met, owner ends sale
Crowdsale.endSale()
// → Transfers all mUSDT to RestaurantAccounts reserve
// → Renounces minter role (permanently stops new CHEW creation)
```

### Restaurant Operations

```solidity
// Customer payment
MockUSDT.approve(RestaurantAccounts_v2.address, 50000e6)
RestaurantAccounts_v2.receivePayment(50000e6)

// Monthly settlement (TREASURER role)
RestaurantAccounts_v2.monthlySettlement()
// → Auto-distributes to operating/reserve
// → Pays rent, utilities, salaries

// Menu voting
MenuVoting.submitDish("Kung Pao Chicken", "Spicy Sichuan classic")
MenuVoting.vote(dishId)

// Governance proposal
GovernanceProposal.proposeParameterChange(
    ProposalType.ADJUST_RENT,
    "Increase rent to 6500 USDT",
    6500e6
)
GovernanceProposal.vote(proposalId, VoteChoice.For)

// Execute after voting period
GovernanceProposal.executeProposal(proposalId)
```

### Dividend Claiming

```solidity
// Year-end (December), anyone can trigger
RestaurantAccounts_v2.distributeDividends()
// → 80% of reserve distributed to CHEW holders

// Individual claims
CHEWToken_v2.claimDividend()
// → Transfers proportional USDT to caller
```

## 📍 Deployed Contracts (Sepolia Testnet)

| Contract | Address | Etherscan |
|----------|---------|-----------|
| MockUSDT | `0x...` | [View](https://sepolia.etherscan.io/address/0x...) |
| CHEWToken_v2 | `0x...` | [View](https://sepolia.etherscan.io/address/0x...) |
| Crowdsale | `0x...` | [View](https://sepolia.etherscan.io/address/0x...) |
| RestaurantAccounts_v2 | `0x...` | [View](https://sepolia.etherscan.io/address/0x...) |
| MenuVoting | `0x...` | [View](https://sepolia.etherscan.io/address/0x...) |
| GovernanceProposal | `0x...` | [View](https://sepolia.etherscan.io/address/0x...) |

> **Note**: Update with your actual deployment addresses

## 🛡️ Security Highlights

### ICO Security
- **Single-Use Minting**: Crowdsale permanently renounces MINTER_ROLE after ICO
- **Direct Capital Flow**: Funds go straight to reserve, bypassing operational accounts
- **Rate Verification**: Exchange rate immutably set at deployment

### Voting Security
- **Snapshot Protection**: `getPastVotes()` prevents flash loan attacks
- **Double-Vote Prevention**: Mapping tracks votes per address per proposal
- **Time-Based Execution**: Proposals only executable after voting period ends

### Treasury Security
- **Reentrancy Guards**: All fund-moving functions protected
- **Multi-Signature Ready**: Role-based access enables multisig patterns
- **Emergency Controls**: Admin emergency withdrawal for fund recovery

## 📚 Technical Documentation

### Governance Parameters

```solidity
// RestaurantAccounts_v2
profitMargin = 70%              // Operating cost allocation
monthlyRent = 6,000 mUSDT
monthlyUtilities = 1,000 mUSDT
largeExpenseThreshold = 2,000 mUSDT
dividendRatio = 80%
minReserve = 80,000 mUSDT

// GovernanceProposal
VOTING_PERIOD = 7 days
APPROVAL_THRESHOLD = 60%

// MenuVoting
MAX_MENU_SIZE = 20 dishes
VOTING_PERIOD = 90 days

// Crowdsale
rate = configurable (e.g., 10e18 CHEW per mUSDT)
```

### Proposal Types

1. **ADJUST_PROFIT_MARGIN** - Modify profit margin percentage
2. **ADJUST_RENT** - Update monthly rent
3. **ADJUST_UTILITIES** - Change utility expenses
4. **CHANGE_DIVIDEND_RATIO** - Alter dividend percentage
5. **LARGE_EXPENSE** - Approve expenditures ≥ $2,000
6. **USE_RESERVE** - Transfer reserve to operating account

### Version Differences (v1 → v2)

**CHEWToken_v2**:
- Removed redundant `Ownable` inheritance
- Fixed constructor to grant `MINTER_ROLE` to deployer
- Enables Crowdsale contract to mint tokens

**RestaurantAccounts_v2**:
- Added `fundReserveWithICOCapital()` function
- Allows Crowdsale to deposit ICO proceeds directly to reserve
- Emits `ICOFundsReceived` event for transparency

## 🔄 Progressive Decentralization Roadmap

### Phase 1: ICO & Launch (Weeks 1-4)
- Crowdsale active, token distribution
- Team has ADMIN/MANAGER/TREASURER roles
- Quick parameter adjustments without voting

### Phase 2: Hybrid Governance (Months 1-6)
- Menu voting enabled
- Large expenses require proposals
- Admin retains emergency controls

### Phase 3: Full Decentralization (Month 6+)
- All parameters governed by proposals
- Admin role transferred to Governance contract
- Complete community control

## 🧪 Testing Checklist

### ICO Testing
- [ ] Buy tokens with various mUSDT amounts
- [ ] Verify correct CHEW minting (rate calculation)
- [ ] End sale and confirm capital transfer
- [ ] Verify minter role renunciation

### Treasury Testing
- [ ] Customer payments to receiving account
- [ ] Monthly settlement with automatic distributions
- [ ] Whitelist payments (rent, salaries, utilities)
- [ ] Emergency reserve transfers

### Governance Testing
- [ ] Create proposals (all types)
- [ ] Vote with different CHEW balances
- [ ] Verify 60% threshold enforcement
- [ ] Execute approved proposals

### Menu Testing
- [ ] Submit dishes
- [ ] Vote for multiple dishes
- [ ] Finalize season
- [ ] Verify top 20 selection

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Developer

**[Your Name]**
- GitHub: [@yourusername](https://github.com/yourusername)
- Email: your.email@example.com

## 🙏 Acknowledgments

- **OpenZeppelin** - Secure smart contract libraries
- **Ethereum Community** - ERC20Votes standard
- **NYU Blockchain Course** - Project guidance

---

**⚠️ Disclaimer**: This project is for educational purposes. Conduct thorough audits before any mainnet deployment involving real funds.
