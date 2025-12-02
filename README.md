# KipuBankV2

KipuBankV2 is a multi-asset vault developed in Solidity, featuring role-based access control, ETH and ERC-20 support, a global USD deposit cap, and Chainlink oracle integration for real-time ETH pricing.  
The project focuses on clean architecture, security, and professional Web3 development practices.

---

## Overview

KipuBankV2 provides:

- Internal account creation for users  
- Deposits and withdrawals in ETH  
- Deposits and withdrawals in approved ERC-20 tokens  
- Secure role hierarchy: ADMIN, MANAGER, CLIENT  
- Global deposit limit defined in USD  
- Real-time ETH/USD price conversion via Chainlink  
- Ability to pause and resume all deposits  
- Internal ETH transfers between clients  
- Security using ReentrancyGuard, validations, and controlled entry points  

---

## Architecture

### 1. Access Control
- **ADMIN_ROLE** – Full administrative privileges  
- **MANAGER_ROLE** – Operational control (token permissions, caps, pause)  
- **CLIENT_ROLE** – Account-level usage permissions  

### 2. Deposit and Withdrawal Logic
- ETH deposits converted to USD at the time of deposit  
- ERC-20 deposits allowed only for whitelisted tokens  
- Deposits can be globally paused  
- All deposits respect the USD bank cap  

### 3. Oracle Integration
- Chainlink AggregatorV3 for ETH/USD price feed  
- Standardized 8-decimal price format  

### 4. Security Measures
- Reentrancy protection  
- No direct ETH transfers (forced use of `deposit()`)  
- State-change validations before execution  

---

## Installation

```bash
npm install

Required dependencies:

npm install @openzeppelin/contracts
npm install @chainlink/contracts
npm install hardhat --save-dev
```

Deployment (Hardhat)

Create scripts/deploy.js:
```bash
const hre = require("hardhat");

async function main() {
  const priceFeed = "CHAINLINK_ETH_USD_ADDRESS"; // Sepolia or chosen network
  const bankCapUSD = 100000n * 10n ** 8n;

  const KipuBank = await hre.ethers.deployContract("KipuBankV2", [
    priceFeed,
    bankCapUSD
  ]);

  await KipuBank.waitForDeployment();
  console.log("KipuBankV2 deployed at:", KipuBank.target);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```
Testing
Hardhat console (Sepolia)
```bash
npx hardhat console --network sepolia
```
Local tests
```bash
npx hardhat test
```
Recommended test cases:

Account creation

ETH and ERC-20 deposits

Withdrawals

Pause/Unpause operations

BankCap enforcement

Access control permissions

Project Structure
```bash
kipu-bankV2/
 ├─ contracts/
 │   └─ KipuBankV2.sol
 ├─ scripts/
 │   └─ deploy.js
 ├─ test/
 ├─ hardhat.config.js
 └─ README.md
```
Author

Developed by Maria Eduarda
A professional-level learning project focused on Solidity, smart contract architecture, and Web3 systems design.
