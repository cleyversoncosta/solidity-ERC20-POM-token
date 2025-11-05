POMToken & RewardsDistributor – Manual Test Plan
================================================

Solidity `0.8.30` • OpenZeppelin v5+ • Target: Tenderly Fork / Polygon Amoy / Remix

1) Environment Setup
--------------------

*   Compiler: `0.8.30`
*   Libraries: `@openzeppelin/contracts` v5.0+
*   Network: Tenderly fork or Polygon Amoy testnet
*   Fund a test wallet with small MATIC for gas

2) Deploy Sequence
------------------

### 2.1 Deploy POMToken

*   No constructor params. Compile & deploy.
*   Expect: contract deployed, owner = deployer, totalSupply = `5_000_000_000 * 1e18`.

### 2.2 Verify Initial Distribution

Use `balanceOf()` for each wallet:

Wallet

Expected Tokens

TREASURY\_WALLET

1,250,000,000

REWARDS\_WALLET

1,500,000,000

DEV\_WALLET

750,000,000

MARKETING\_WALLET

500,000,000

LIQUIDITY\_WALLET

500,000,000

ADVISORS\_WALLET

250,000,000

DAO\_WALLET

250,000,000

Pass if totals sum to 5B and each balance matches.

3) Basic Token Functionality
----------------------------

### 3.1 Transfer (happy path)

*   Transfer from `DEV_WALLET` → `MARKETING_WALLET`.
*   Expected: success (trading is enabled by default in your snippet).

### 3.2 Pause / Unpause

1.  Owner calls `pause()`.
2.  Attempt any `transfer()` → expect revert `"Pausable: paused"`.
3.  Owner calls `unpause()` → transfers work again.

### 3.3 Ownership Guards

*   Non-owner calls `pause()` / `setLimits()` → expect revert `"Ownable: caller is not the owner"`.
*   Owner can `transferOwnership(newOwner)` and new owner can call admin funcs.

4) Anti-bot / Limits
--------------------

### 4.1 Tighten Limits

    setLimits(1_000 * 1e18, 2_000 * 1e18, true)

*   Try transfer 5,000 → expect revert "Exceeds maxTx".
*   Try transfer 500 → success.

### 4.2 Wallet Cap

*   Send multiple transfers to a fresh wallet until balance > 2,000 → expect final transfer revert "Exceeds maxWallet".

### 4.3 Disable Limits

    setLimits(0, 0, false)

Repeat transfers → all should succeed.

### 4.4 Exemptions

    setLimitExempt(<addr>, true)

Large transfer from/to exempt wallet → should succeed despite caps.

5) RewardsDistributor Setup
---------------------------

### 5.1 Deploy Distributor

*   Constructor: `(tokenAddress = POMToken, owner_ = your wallet)`
*   Expect: `token()` set correctly; `owner()` is you.

### 5.2 Fund Distributor

1.  From `REWARDS_WALLET`: `approve(distributor, 100000 * 1e18)`
2.  Owner: `topUp(100000 * 1e18)`
3.  Expect distributor balance ↑ by 100,000 POM.

### 5.3 Authorize Signer

    setSigner(<backend_wallet>, true)

Expect: `SignerSet` event.

### 5.4 Unauthorized Reward Attempt

    // from NON-signer
    rewardPlayer(player, 20)

Expect: revert "not game".

### 5.5 Authorized Reward

    // from authorized signer
    rewardPlayer(player, 20) // example distance
    

Expect: transfer based on tier, `RewardSent` event, player balance ↑.

### 5.6 Reward Tiers

Distance (km)

Expected Reward

5

10 POM

25

5 POM

75

2 POM

150

0 POM (should revert with "no reward")

### 5.7 Daily Cap

Call `rewardPlayer(player, 5)` repeatedly until total > 200 POM (same day).

Expect: revert "daily cap".

### 5.8 Insufficient Pool

1.  Owner drains distributor with `rescue()`.
2.  Call `rewardPlayer(player, 10)`.

Expect: revert "insufficient pool".

### 5.9 Admin Rescue / Permissions

*   Owner: `rescue(to, amount)` → success.
*   Non-owner: `rescue()` → revert "Ownable: caller is not the owner".

6) Security & Invariants
------------------------

*   **No external mint:** ABI has no `mint()`; only constructor calls internal `_mint()`.
*   **Burn:** `burn()` reduces `totalSupply()`.
*   **No arbitrary transfers:** No admin function moves others' funds.
*   **Pausable:** When paused, transfers/mint/burn are blocked.
*   **Rewards source:** All rewards come from distributor balance.

7) Final Checklist
------------------

Check

Status

Total supply = 5B

PASS

Sum of initial balances = 5B

PASS

Trading gate & limits behave as configured

PASS

Only owner can admin

PASS

Rewards tiers & caps enforced

PASS

No post-deploy mint possible

PASS

Pausable works

PASS

Helpful Snippets
----------------

    // Tighten limits
    setLimits(1_000 * 1e18, 2_000 * 1e18, true);
    
    // Disable limits
    setLimits(0, 0, false);
    
    // Exempt router/treasury/owner if needed
    setLimitExempt(<address>, true);
    
    // Fund distributor
    approve(<distributor>, 100000 * 1e18)     // from REWARDS_WALLET
    topUp(100000 * 1e18)                       // from distributor owner
    
    // Signer
    setSigner(<backend_wallet>, true);
    
    // Reward a player (from signer)
    rewardPlayer(<player>, <distanceKm>);
    

Tip: In Tenderly, inspect the deploy tx “Logs” to verify all `Transfer` events and balances after constructor distribution.