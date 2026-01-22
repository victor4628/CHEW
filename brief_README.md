# **🍽️ Crypto Restaurant DAO (CHEW)**

This project is a complete, on-chain proof-of-concept for a decentralized autonomous organization (DAO) that manages a real-world restaurant. It includes a full ecosystem of smart contracts for tokenomics, governance, and transparent financial operations.

## **Core Features**

* **On-Chain Accounting:** A three-account system (Receiving, Operating, Reserve) to transparently manage all restaurant funds (RestaurantAccounts\_v2.sol).  
* **Community Governance:** CHEW token holders can vote on major financial decisions, such as changing the profit margin or approving large expenses (GovernanceProposal.sol).  
* **Community Engagement:** A separate voting system allows token holders to vote on the quarterly menu (MenuVoting.sol).  
* **Automated Dividends:** A portion of the restaurant's profits (from the Reserve account) is automatically distributed to all CHEW token holders at the end of the year.  
* **Full ICO Lifecycle:** A Crowdsale.sol contract manages the initial token sale and securely funds the DAO's treasury.

## **📄 File Structure**

### **Smart Contracts (.sol)**

1. **musdt.sol**: A mock ERC20 stablecoin (6 decimals) used to simulate real-world customer payments and ICO investments.  
2. **CHEWToken\_v2.sol**: The DAO's ERC20Votes governance token. Holders can vote and earn dividends.  
3. **RestaurantAccounts\_v2.sol**: The "bank" and "treasurer" of the DAO. It manages all revenue, expenses, and triggers dividends.  
4. **GovernanceProposal.sol**: The "brain" of the DAO. Allows holders to vote on financial proposals that directly control the RestaurantAccounts contract.  
5. **MenuVoting.sol**: A secondary, community-focused contract for voting on menu items.  
6. **Crowdsale.sol**: The ICO contract. Sells CHEWToken for musdt and funds the RestaurantAccounts reserve.

### **Web Application (.html)**

1. **interactive\_demo.html**: A **fully functional, interactive web app** built with React and Ethers.js. It connects to MetaMask and allows you to interact with all 6 deployed contracts.  

## **📊 On-Chain Fund Flow**

This DAO has two distinct revenue streams:

1. Customer Payments:  
   Customer \-\> receivePayment() \-\> Receiving Account \-\> monthlySettlement() splits funds into Operating & Reserve accounts.  
2. ICO (Startup Capital):  
   Investor \-\> buyTokens() \-\> Crowdsale Contract \-\> endSale() transfers all funds \-\> Reserve Account.

## **🚀 How to Run the Interactive Demo (Step-by-Step)**

Follow these steps exactly to deploy, connect, and test the entire DAO ecosystem.

### **Prerequisites**

1. **MetaMask:** You must have the [MetaMask](https://metamask.io/) browser extension installed.  
2. **Testnet ETH:** Your MetaMask wallet must be on the **Sepolia Testnet** and funded with SepoliaETH (for gas fees).  
3. **Node.js:** You must have [Node.js](https://nodejs.org/en) installed to run a simple web server.

### **Step 1: Deploy All 6 Contracts**

Deploy all contracts to the Sepolia Testnet (using Remix, Hardhat, etc.) **in this exact order**.

1. Deploy **musdt.sol**.  
2. Deploy **CHEWToken\_v2.sol**. (Pass the musdt.sol address to its constructor).  
3. Deploy **RestaurantAccounts\_v2.sol**. (Pass the musdt.sol and CHEWToken\_v2.sol addresses).  
4. Deploy **GovernanceProposal.sol**. (Pass the CHEWToken\_v2.sol and RestaurantAccounts\_v2.sol addresses).  
5. Deploy **MenuVoting.sol**. (Pass the CHEWToken\_v2.sol address).  
6. Deploy **Crowdsale.sol**. (Pass all 3 addresses: CHEWToken\_v2, musdt, RestaurantAccounts\_v2, plus a rate. *Example rate*: 1000000000000000000 for 1 CHEW per 1 mUSDT).

### **Step 2: Connect Contracts (The CRITICAL Step)**

Your contracts are deployed but cannot talk to each other. You (as the Deployer) must grant them permissions. Use Etherscan or Remix to call these functions from your **deployer wallet**.

1. **Enable the ICO:**  
   * **Contract:** CHEWToken\_v2  
   * **Function:** grantRole()  
   * **role:** MINTER\_ROLE (get this by calling the MINTER\_ROLE view function)  
   * **account:** The Crowdsale.sol contract address.  
2. **Enable Dividends:**  
   * **Contract:** CHEWToken\_v2  
   * **Function:** grantRole()  
   * **role:** DISTRIBUTOR\_ROLE  
   * **account:** The RestaurantAccounts\_v2.sol contract address.  
3. **Enable Governance Control:**  
   * **Contract:** RestaurantAccounts\_v2  
   * **Function:** grantRole()  
   * **role:** DEFAULT\_ADMIN\_ROLE  
   * **account:** The GovernanceProposal.sol contract address.  
4. **Enable ICO Funding:**  
   * **Contract:** RestaurantAccounts\_v2  
   * **Function:** grantRole()  
   * **role:** TREASURER\_ROLE  
   * **account:** Your **own wallet address** (the deployer). This allows you to call endSale() on the Crowdsale contract, which in turn calls the fundReserveWithICOCapital function.

### **Step 3: Run the Web App**

You **cannot** just double-click the HTML file. It must be served by a web server.

1. Open your **Terminal** or **Command Prompt**.  
2. Navigate to the folder where interactive\_demo.html is saved.  
3. Run the command: npx serve  
4. Open this URL in your browser: http://localhost:3000

### **Step 4: Configure the Web App**

1. Open interactive\_demo.html in a text editor.  
2. At the top of the \<script type="text/babel"\> block, replace all 6 "PASTE\_YOUR\_...\_ADDRESS\_HERE" placeholders with the contract addresses from Step 1\.  
3. Save the file. The npx serve server will automatically pick up the changes.

### **Step 5: Test the Full Lifecycle\!**

You can now test the entire DAO flow from your http://localhost:3000 window.

1. **Connect Wallet:** Click "Connect Wallet". Make sure MetaMask is on the **Sepolia network**.  
2. **Get mUSDT:** Click the "Get 1,000 test mUSDT" button. (This only works if you are the *deployer* of musdt.sol). If you are a test user, have the deployer *send* you mUSDT from their wallet.  
3. **Buy CHEW:** Go to the "ICO / Purchase" tab, enter an amount, and buy tokens.  
4. **Pay for Meal:** Go to the "Customer Payment" tab and simulate a $20 payment.  
5. **Check Treasury:** Go to the "Treasury" tab. You will see $20.00 in the "Receiving Account". The "Reserve Account" will still be $0.  
6. **Run Settlement:** On the "Treasury" tab, click "Run Monthly Settlement". The $20 will move from "Receiving" to the "Operating" and "Reserve" accounts based on your profitMargin rule.  
7. **Vote:** Go to "Menu Voting" to submit and vote on a dish, or "Governance" to vote on proposals.