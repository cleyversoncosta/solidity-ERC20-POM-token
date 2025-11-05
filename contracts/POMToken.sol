// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/*
    PinOnMap (POM)
    --------------------------------------------------
    • Total supply: 10,000,000,000 POM
    • Hardcoded distribution:
        - Treasury: 25%
        - Rewards Pool: 30%
        - Dev Team: 15%
        - Marketing: 10%
        - Liquidity: 10%
        - Advisors: 5%
        - DAO Reserve: 5%
    • No fees, no further minting, fixed supply.
    • Based on OpenZeppelin ERC20 + Ownable + Pausable.
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract POMToken is ERC20, ERC20Burnable, Ownable, Pausable {
    // ---- Supply and control variables ----
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 * 1e18; // 10 B tokens with 18 decimals

    // Basic anti-bot / fair-launch protection
    bool public tradingEnabled = true;
    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;
    bool public limitsInEffect = true;

    mapping(address => bool) public isLimitExempt; // wallets that ignore tx/wallet limits
    mapping(address => bool) public isDexPair; // recognized DEX pairs

    event TradingEnabled();
    event LimitsUpdated(uint256 maxTx, uint256 maxWallet, bool active);

    // ---- Hardcoded wallets (replace with real ones before deploy) ----
    address public constant OWNER_WALLET =
        0xDfb98530d77eE2d29eA7933c02Eff50310201145;
    address public constant TREASURY_WALLET =
        0x71133f5d2548Cd9B182C2DaF68D9D00a56d4343f;
    address public constant REWARDS_WALLET =
        0xAB247964F4b9A1C50e6c01e4a2A808Ce07feaf41;
    address public constant DEV_WALLET =
        0x1bEc551c40d7F6B3B7b0366765Fa769A8DDb4f25;
    address public constant MARKETING_WALLET =
        0x9A982f4EFa6F344E955D28Dba751E17B60E3F217;
    address public constant LIQUIDITY_WALLET =
        0xF03Cb4af13aFDB94688607e100BEE39E4173B446;
    address public constant ADVISORS_WALLET =
        0x8DCdF001b069ef0a027aa8b4DAcA12577423a90b;
    address public constant DAO_WALLET =
        0xFf55e5341142eFdfD37D2E51317bBDA62DB8d8f0;

    event Distributed(
        address indexed treasury,
        address indexed rewards,
        address indexed devTeam,
        address marketing,
        address liquidity,
        address advisors,
        address dao
    );

    event RewardsDistributorUpdated(address indexed newDistributor);

    address public rewardsDistributor;

    event Debug(string message, uint256 value);

    /* ------------------------------------------------------------------
       • Mints total supply once to this contract.
       • Immediately distributes percentages to hardcoded wallets.
       • Initializes basic anti-bot and ownership controls.
    ------------------------------------------------------------------ */
    constructor() ERC20("PinOnMap Token", "POM") Ownable(msg.sender) {
        // disable checks during distribution
        limitsInEffect = false;
        tradingEnabled = true;

        // ---- Initial distribution (fixed split) ----
        _mint(TREASURY_WALLET, percentOf(TOTAL_SUPPLY, 2500)); // 25%
        _mint(REWARDS_WALLET, percentOf(TOTAL_SUPPLY, 3000)); // 30%
        _mint(DEV_WALLET, percentOf(TOTAL_SUPPLY, 1500)); // 15%
        _mint(MARKETING_WALLET, percentOf(TOTAL_SUPPLY, 1000)); // 10%
        _mint(LIQUIDITY_WALLET, percentOf(TOTAL_SUPPLY, 1000)); // 10%
        _mint(ADVISORS_WALLET, percentOf(TOTAL_SUPPLY, 500)); // 5%
        _mint(DAO_WALLET, percentOf(TOTAL_SUPPLY, 500)); // 5%

        // enable checks after distribution
        tradingEnabled = false;
        limitsInEffect = true;

        // ---- Anti-bot default limits ----
        maxTxAmount = percentOf(TOTAL_SUPPLY, 25); // 0.25% por transação
        maxWalletAmount = percentOf(TOTAL_SUPPLY, 50); // 0.5% por carteira

        isLimitExempt[OWNER_WALLET] = true;
        isLimitExempt[address(this)] = true;

        emit Distributed(
            TREASURY_WALLET,
            REWARDS_WALLET,
            DEV_WALLET,
            MARKETING_WALLET,
            LIQUIDITY_WALLET,
            ADVISORS_WALLET,
            DAO_WALLET
        );
    }

    /* ------------------------------------------------------------------
   @param distributor  Address of the RewardsDistributor contract.

   • Allows the owner (admin or multisig) to define or update
     the official RewardsDistributor contract address.
   • This enables the token to recognize which external contract
     manages reward logic or receives redirected tokens.
   • Can be updated in the future in case of contract upgrades.
------------------------------------------------------------------- */
    function setRewardsDistributor(address distributor) external onlyOwner {
        require(distributor != address(0), "Zero address");
        rewardsDistributor = distributor;
        emit RewardsDistributorUpdated(distributor); // Add this event
    }

    /**
     * @dev Calcula uma porcentagem inteira (em basis points) de um valor dado.
     * Solidity não tem números decimais, então usamos basis points (1/100 de 1%)
     * para representar percentuais com alta precisão.
     *
     * Exemplo:
     * - basisPoints = 100  → 1%
     * - basisPoints = 250  → 2.5%
     * - basisPoints = 5000 → 50%
     *
     * @param amount Valor base sobre o qual calcular a porcentagem.
     * @param basisPoints Valor em basis points (onde 100 = 1%).
     * @return Retorna o resultado de (amount * basisPoints / 10_000).
     */
    function percentOf(
        uint256 amount,
        uint256 basisPoints
    ) internal pure returns (uint256) {
        require(basisPoints <= 10_000, "Basis points exceed 100%");
        return (amount * basisPoints) / 10_000;
    }

    /* ------------------------------------------------------------------
       Allows transfers between non-exempt addresses once initial setup
       (e.g., liquidity add) is finished.
    ------------------------------------------------------------------ */
    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /* ------------------------------------------------------------------
       Emergency circuit breakers inherited from Pausable.
       When paused, no mint/transfer/burn can occur.
    ------------------------------------------------------------------ */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ------------------------------------------------------------------
       Updates anti-bot / max transaction and wallet limits.
       _active = false disables all limit checks.
    ------------------------------------------------------------------ */
    function setLimits(
        uint256 _maxTx,
        uint256 _maxWallet,
        bool _active
    ) external onlyOwner {
        maxTxAmount = _maxTx;
        maxWalletAmount = _maxWallet;
        limitsInEffect = _active;
        emit LimitsUpdated(_maxTx, _maxWallet, _active);
    }

    /* ------------------------------------------------------------------
       Marks an address as exempt or not from tx/wallet limit rules.
       Typically used for DEX router, treasury, or owner wallets.
    ------------------------------------------------------------------ */
    function setLimitExempt(address account, bool exempt) external onlyOwner {
        isLimitExempt[account] = exempt;
    }

    /* ------------------------------------------------------------------
       Flags a pair address (e.g., QuickSwap pair) so that wallet-limit
       rules treat it as a DEX liquidity pool.
    ------------------------------------------------------------------ */
    function setDexPair(address pair, bool allowed) external onlyOwner {
        isDexPair[pair] = allowed;
    }

    /* ------------------------------------------------------------------
       Core ERC-20 hook (replaces _beforeTokenTransfer in OZ v5).

       Runs automatically on every mint, burn, or transfer:
       • Blocks all transfers if contract is paused.
       • Enforces "tradingEnabled" gate before public launch.
       • Applies anti-bot maxTx / maxWallet rules.
       After all checks, the real balance update happens inside ERC20’s super._update().
    ------------------------------------------------------------------ */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        // Allow minting/burning, contract-internal actions, and constructor initialization
        if (from == address(0) || to == address(0) || from == address(this)) {
            super._update(from, to, amount);
            return;
        }

        // Prevents tokens from being accidentally sent to the token contract itself,
        // since the contract cannot use or recover those tokens once received.
        require(
            to != address(this),
            "Cannot send tokens to token contract directly"
        );

        // ---- Trading gate: before enabling, only exempt wallets can move tokens ----
        if (!tradingEnabled && from != address(0) && to != address(0)) {
            require(
                isLimitExempt[from] || isLimitExempt[to],
                "Trading not yet enabled"
            );
        }

        // ---- Anti-bot / max limits enforcement ----
        if (limitsInEffect && from != address(0) && to != address(0)) {
            if (!isLimitExempt[from] && !isLimitExempt[to]) {
                require(amount <= maxTxAmount, "Exceeds maxTx");
                if (!isDexPair[to]) {
                    require(
                        balanceOf(to) + amount <= maxWalletAmount,
                        "Exceeds maxWallet"
                    );
                }
            }
        }

        // ---- Proceed with actual balance updates ----
        super._update(from, to, amount);
    }
}
