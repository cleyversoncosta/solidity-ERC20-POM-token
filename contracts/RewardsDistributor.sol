// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/* ------------------------------------------------------------------
   Minimal ERC20 Interface
   ------------------------------------------------------------------
   • Defines only the core functions used by this contract.
   • Keeps the distributor fully independent from any specific token.
   • Works with any ERC-20 compliant token (e.g. POMToken, USDC, etc.).
------------------------------------------------------------------- */
interface IERC20 {
    // Transfers `amount` tokens to `to`.
    // Returns true on success.
    function transfer(address to, uint256 amount) external returns (bool);

    // Transfers tokens from `from` to `to`, assuming prior allowance.
    // Used when another wallet pre-approves this contract to pull funds.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    // Returns the token balance of an account.
    function balanceOf(address account) external view returns (uint256);
}

/* ------------------------------------------------------------------
   RewardsDistributor
   ------------------------------------------------------------------
   • Independent contract that manages and distributes ERC20 rewards.
   • Token address is passed at deployment (any ERC20-compatible token).
   • Ownable: only the owner can adjust configuration or refill tokens.
   • ReentrancyGuard: protects against reentrancy attack vectors.
------------------------------------------------------------------- */

contract RewardsDistributor is Ownable, ReentrancyGuard {
    // Immutable reference to the main POM token contract
    IERC20 public immutable token;

    // Authorized backend / relayer addresses allowed to call rewardPlayer()
    mapping(address => bool) public isGameSigner;

    // Anti-abuse limits (optional safety caps)
    uint256 public maxRewardPerCall = 10 * 1e18; // Max 10 POM per call (matches tier 1)
    uint256 public maxDailyForAddr = 200 * 1e18; // Max 200 POM per player per day
    // Tracks how much each player has claimed per day
    mapping(address => mapping(uint256 => uint256)) public dailyClaimed; // player => dayIndex => amount

    // ---- Events ----
    event SignerSet(address indexed signer, bool allowed);
    event RewardSent(
        address indexed player,
        uint256 distanceKm,
        uint256 amount
    );

    /* ------------------------------------------------------------------
       Constructor
       @param tokenAddress  Address of the ERC20 token to distribute.
       @param owner_        Address that will become the contract owner.

       • Initializes the Ownable base contract with `owner_`.
       • Stores the token address in an immutable variable for efficiency.
       • The token can be any ERC-20 implementation that supports transfer(), transferFrom(), and balanceOf().
    ------------------------------------------------------------------ */
    constructor(address tokenAddress, address owner_) Ownable(owner_) {
        token = IERC20(tokenAddress);
    }
    /* ------------------------------------------------------------------
       • Prevents the owner from accidentally or intentionally renouncing ownership.
       • The default OpenZeppelin implementation would transfer ownership
         to the zero address (0x000...0), permanently locking all `onlyOwner` functions.
       • By overriding and reverting, we protect administrative control
         and ensure that configuration and emergency functions remain accessible.
    ------------------------------------------------------------------ */
    function renounceOwnership() public view override onlyOwner {
        revert("renounceOwnership disabled");
    }

    /* ------------------------------------------------------------------
       • Restricts specific functions to authorized “game signers”.
       • Ensures that only verified backend systems can trigger rewards.
    ------------------------------------------------------------------ */
    modifier onlyGame() {
        require(isGameSigner[msg.sender], "not game");
        _;
    }

    /* ------------------------------------------------------------------
       • Adds or removes an address from the authorized signer list.
       • Only the contract owner (multisig or admin) can change this list.
       • Used to register backend servers or relayer wallets.
    ------------------------------------------------------------------ */
    function setSigner(address signer, bool allowed) external onlyOwner {
        isGameSigner[signer] = allowed;
        emit SignerSet(signer, allowed);
    }

    /* ------------------------------------------------------------------
       • Updates maximum reward limits to control abuse.
       • _maxPerCall: limit per transaction.
       • _maxDailyForAddr: limit per player per day.
       • Helps prevent farming or accidental over-rewarding.
    ------------------------------------------------------------------ */
    function setCaps(
        uint256 _maxPerCall,
        uint256 _maxDailyForAddr
    ) external onlyOwner {
        maxRewardPerCall = _maxPerCall;
        maxDailyForAddr = _maxDailyForAddr;
    }

    /* ------------------------------------------------------------------
       • Internal pure function that determines how many tokens
         a player earns based on distance accuracy (in km).
       • Reward tiers:
           ≤ 10 km   → 5 POM
           ≤ 50 km   → 3 POM
           ≤ 100 km  → 1 POM
           > 100 km  → 0 POM
    ------------------------------------------------------------------ */
    function _calcReward(uint256 distanceKm) internal pure returns (uint256) {
        if (distanceKm <= 10) return 5 * 1e18;
        if (distanceKm <= 50) return 3 * 1e18;
        if (distanceKm <= 100) return 1 * 1e18;
        return 0;
    }

    /* ------------------------------------------------------------------
       • Main function that sends token rewards to players.
       • Can only be called by authorized “game signers”.
       • Protected by nonReentrant to block reentrancy exploits.
       • Performs multiple validations:
           - Player address must not be zero
           - Reward must be > 0
           - Must not exceed per-call cap
           - Must not exceed daily cap for that player
           - Distributor must hold enough tokens
       • Transfers tokens directly from this contract’s balance.
    ------------------------------------------------------------------ */
    function rewardPlayer(
        address player,
        uint256 distanceKm
    ) external onlyGame nonReentrant {
        require(player != address(0), "zero player");

        // Calculate reward amount based on distance
        uint256 amount = _calcReward(distanceKm);
        require(amount > 0, "no reward");

        // Enforce per-call maximum
        require(amount <= maxRewardPerCall, "per-call cap");

        // Enforce daily cap per player
        uint256 day = block.timestamp / 1 days;
        uint256 newDaily = dailyClaimed[player][day] + amount;
        require(newDaily <= maxDailyForAddr, "daily cap");
        dailyClaimed[player][day] = newDaily;

        // Check token balance and send reward
        require(token.balanceOf(address(this)) >= amount, "insufficient pool");
        token.transfer(player, amount);

        emit RewardSent(player, distanceKm, amount);
    }

    /* ------------------------------------------------------------------
       • Allows the owner to refill the reward pool with more tokens.
       • Transfers tokens from the owner to this contract using transferFrom.
       • Owner must approve the transfer beforehand.
    ------------------------------------------------------------------ */
    function topUp(uint256 amount) external onlyOwner {
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "transferFrom fail"
        );
    }

    /* ------------------------------------------------------------------
       • Emergency function to withdraw leftover tokens.
       • Only callable by the owner (usually a multisig wallet).
       • Useful for upgrades, migrations, or operational recovery.
    ------------------------------------------------------------------ */
    function rescue(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero to");
        token.transfer(to, amount);
    }
}
