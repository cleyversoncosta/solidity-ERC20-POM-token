# 🗺️ PinOnMap (POM) – ERC-20 Token & Rewards Distributor

## Overview

**PinOnMap (POM)** is the native token for the **PinOnMap Game Ecosystem**, designed to support player rewards, treasury management, and community governance.  
It consists of **two core smart contracts**:

1. **POMToken.sol** — ERC-20 compliant token with fixed total supply, transparent distribution, and anti-bot safeguards.  
2. **RewardsDistributor.sol** — an independent rewards management contract that securely distributes tokens to players based on gameplay metrics (e.g., guess accuracy in kilometers).

---

## 📦 POMToken.sol

### Description

`POMToken` is a **non-mintable**, **non-taxed**, **fixed-supply** ERC-20 token implementing:
- Initial hardcoded distribution across ecosystem wallets.
- Basic **anti-bot** / **fair-launch** limits (`maxTx`, `maxWallet`).
- **Trading enable switch** and **pause control**.
- Integration support for a future **RewardsDistributor** contract.

### Key Features

| Feature | Description |
|----------|--------------|
| **Total Supply** | `10,000,000,000 POM` (10 B with 18 decimals) |
| **Mint Policy** | One-time mint during deployment only |
| **Fees** | None (no tax or burn fees) |
| **Ownership** | Uses OpenZeppelin `Ownable` |
| **Security** | Inherits `Pausable` for emergency stops |
| **Anti-Bot Rules** | Limits max TX and max wallet per address |
| **Trading Control** | Owner can toggle `enableTrading()` |
| **Distribution** | Treasury, Rewards, Dev, Marketing, Liquidity, Advisors, DAO |
| **Decimals** | 18 |

### Initial Distribution

| Wallet | Percentage | Description |
|--------|-------------|-------------|
| Treasury | 25 % | Ecosystem & operations |
| Rewards Pool | 30 % | Game / player rewards |
| Dev Team | 15 % | Development fund |
| Marketing | 10 % | Growth & promotion |
| Liquidity | 10 % | DEX/LP provisioning |
| Advisors | 5 % | Partner allocations |
| DAO Reserve | 5 % | Future governance use |

---

## 🎮 RewardsDistributor.sol

### Description

`RewardsDistributor` is a **modular contract** that manages POM reward logic independently.  
It allows authorized game servers (“signers”) to issue token rewards directly to players.

The contract is **compatible with any ERC-20 token**, though it is primarily designed for use with `POMToken`.

### Reward Logic

| Distance Accuracy (km) | Reward |
|------------------------|--------|
| ≤ 10 km | **5 POM** |
| ≤ 50 km | **3 POM** |
| ≤ 100 km | **1 POM** |
| > 100 km | **0 POM** |

### Security and Control

| Mechanism | Description |
|------------|-------------|
| **Authorized Signers** | Only approved game backends can trigger rewards |
| **Reentrancy Protection** | `nonReentrant` on reward calls |
| **Daily Player Cap** | Limits how much a player can earn per 24 h |
| **Max Per Call** | Prevents excessive single-transaction rewards |
| **Refill System** | Owner can top-up token balance via `transferFrom` |
| **Emergency Rescue** | Owner can withdraw unused tokens if needed |
| **Renounce Blocked** | Ownership renounce disabled for admin safety |

---

## 🧩 Integration Flow

1. **Deploy `POMToken.sol`**
   - Automatically mints the entire fixed supply (10B POM).
   - Distributes tokens across the predefined ecosystem wallets.
   - Keeps trading disabled until `enableTrading()` is explicitly called.

2. **Deploy `RewardsDistributor.sol`**
   - Pass the deployed POM token address as the `tokenAddress` parameter.
   - Pass the admin or multisig wallet as the `owner_` parameter.
   - Example:
     ```solidity
     new RewardsDistributor(0xYourTokenAddress, 0xYourOwnerWallet);
     ```

3. **Link the two contracts**
   - In `POMToken`, call:
     ```solidity
     setRewardsDistributor(<distributor_address>);
     ```
   - This step allows the token contract to recognize the external distributor that will manage player rewards.

4. **Fund the Rewards Distributor**
   - Transfer tokens from the **Rewards Pool wallet** to the **RewardsDistributor** contract:
     ```solidity
     token.transfer(<distributor_address>, amount);
     ```
   - The distributor must hold enough tokens to send out rewards to players.

5. **Authorize Game Signers**
   - Allow backend game servers or relayers to call reward functions:
     ```solidity
     setSigner(<backend_wallet>, true);
     ```
   - Only addresses marked as `isGameSigner` can issue rewards through `rewardPlayer()`.

6. **Send Rewards**
   - Authorized signers trigger rewards:
     ```solidity
     rewardPlayer(playerAddress, distanceKm);
     ```
   - The contract automatically calculates the correct POM amount based on the distance tiers.

7. **Optional Admin Functions**
   - **Pause/Unpause Token Transfers**
     ```solidity
     pause(); // or unpause()
     ```
   - **Adjust Anti-Bot Limits**
     ```solidity
     setLimits(maxTx, maxWallet, active);
     ```
   - **Rescue or Top-Up Distributor**
     ```solidity
     rescue(to, amount);
     topUp(amount);
     ```

---

## 🔒 Safety Highlights

| Mechanism | Purpose |
|------------|----------|
| **Immutable total supply** | No further minting or inflation possible |
| **Ownership retained** | `renounceOwnership()` disabled for admin security |
| **Emergency stop** | `pause()` halts all token transfers if needed |
| **Anti-bot guardrails** | Max TX and wallet caps to ensure fair launch |
| **No self-transfer** | Contract cannot receive stranded tokens |
| **Non-reentrant rewards** | Prevents double claim or recursive exploit |
| **Daily claim limits** | Stops abuse by capping per-player rewards |

---

## 🧠 Tech Stack

- **Language:** Solidity `^0.8.30`
- **Framework:** OpenZeppelin Contracts v5
  - `ERC20`, `ERC20Burnable`
  - `Ownable`, `Pausable`, `ReentrancyGuard`
- **Networks:** Polygon / Ethereum / EVM compatible chains
- **License:** MIT

---

## 🧪 Example Deployment Parameters

```solidity
// 1️⃣ Deploy Token
POMToken pom = new POMToken();

// 2️⃣ Deploy Distributor
RewardsDistributor distributor = new RewardsDistributor(address(pom), msg.sender);

// 3️⃣ Link Distributor
pom.setRewardsDistributor(address(distributor));

// 4️⃣ Transfer Tokens to Distributor (from Rewards Pool wallet)
pom.transfer(address(distributor), 100_000_000 * 1e18);
 ```


## 🧾 Audit & Verification Checklist

| Status | Checkpoint |
|:------:|-------------|
| ✅ | ERC-20 total supply and distribution verified |
| ✅ | Ownership and admin controls validated |
| ✅ | `enableTrading()` gating tested |
| ✅ | `pause()` / `unpause()` functions verified |
| ✅ | Anti-bot (`maxTx`, `maxWallet`) limits functioning |
| ✅ | `RewardsDistributor` link and transfer flow confirmed |
| ✅ | Reentrancy protection active (`nonReentrant`) |
| ✅ | `renounceOwnership` properly disabled |
| ✅ | Polygon / Ethereum deployment ready |
| ⚙️ | Optional multi-sig owner suggested for production |

---

## 🌍 Author & Credits

**Developed by:** [Cleyverson Costa](https://github.com/cleyversoncosta)  
**Contracts:** `POMToken.sol`, `RewardsDistributor.sol`  
**Ecosystem:** *PinOnMap Game*  

> “Reward curiosity. Map the world. Play to earn with purpose.”

---

## 🧭 Useful Links

- 🧱 **OpenZeppelin Docs:** [https://docs.openzeppelin.com/contracts](https://docs.openzeppelin.com/contracts)  
- 🔗 **Etherscan Verification Guide:** [https://docs.etherscan.io](https://docs.etherscan.io)  
- 🧰 **Remix IDE:** [https://remix.ethereum.org](https://remix.ethereum.org)  
- 🧪 **Polygon Testnet Faucet:** [https://faucet.polygon.technology](https://faucet.polygon.technology)  

---

## 💡 Deployment Tips

- Always test deployments first on **Sepolia** or **Polygon Mumbai**.  
- Verify contract source on **Etherscan / Polygonscan** immediately after deployment.  
- Keep a separate **treasury cold wallet** for ecosystem funds.  
- Use **multi-sig** control for ownership of both contracts (recommended: Gnosis Safe).  
- Never transfer tokens directly to the token contract (`address(this)`); they will be locked forever.  

---

## 🧠 Future Improvements

- 🔄 Upgradeable reward logic with dynamic difficulty tiers  
- 📊 On-chain leaderboard tracking via event indexing  
- 🌐 Integration with decentralized identity (DID)  
- 🪙 DAO governance proposal system for POM holders  
- 🧩 Off-chain signature verification for game servers  

---

## 🏁 Final Notes

This repository demonstrates a **complete ERC-20 ecosystem** designed for gaming and on-chain engagement.  
Both contracts prioritize **security**, **clarity**, and **future extensibility** — forming a reliable foundation for any blockchain-based reward system.

> Built with Solidity. Secured with OpenZeppelin. Designed for exploration.
