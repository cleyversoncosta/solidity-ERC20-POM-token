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
    address public treasuryWallet;
    address public rewardsWallet;
    address public devWallet;
    address public marketingWallet;
    address public liquidityWallet;
    address public advisorsWallet;
    address public daoWallet;

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
    constructor(
            address _owner,          // Owner (admin / multisig)
            address _treasury,
            address _rewards,
            address _dev,
            address _marketing,
            address _liquidity,
            address _advisors,
            address _dao
        ) ERC20("PinOnMap Token", "POM") Ownable(_owner) {
            require(_owner != address(0), "Invalid owner");
            require(_treasury != address(0), "Invalid treasury");
            require(_rewards != address(0), "Invalid rewards");
            require(_dev != address(0), "Invalid dev");
            require(_marketing != address(0), "Invalid marketing");
            require(_liquidity != address(0), "Invalid liquidity");
            require(_advisors != address(0), "Invalid advisors");
            require(_dao != address(0), "Invalid dao");
    
            treasuryWallet = _treasury;
            rewardsWallet = _rewards;
            devWallet = _dev;
            marketingWallet = _marketing;
            liquidityWallet = _liquidity;
            advisorsWallet = _advisors;
            daoWallet = _dao;
    
            // Disable limits during setup
            limitsInEffect = false;
            tradingEnabled = true;
    
            // ---- Initial Distribution ----
            _mint(treasuryWallet, percentOf(TOTAL_SUPPLY, 2500));  // 25%
            _mint(rewardsWallet, percentOf(TOTAL_SUPPLY, 3000));   // 30%
            _mint(devWallet, percentOf(TOTAL_SUPPLY, 1500));       // 15%
            _mint(marketingWallet, percentOf(TOTAL_SUPPLY, 1000)); // 10%
            _mint(liquidityWallet, percentOf(TOTAL_SUPPLY, 1000)); // 10%
            _mint(advisorsWallet, percentOf(TOTAL_SUPPLY, 500));   // 5%
            _mint(daoWallet, percentOf(TOTAL_SUPPLY, 500));        // 5%
    
            // Reactivate limits
            tradingEnabled = false;
            limitsInEffect = true;
    
            // ---- Anti-bot default limits ----
            maxTxAmount = percentOf(TOTAL_SUPPLY, 25); // 0.25%
            maxWalletAmount = percentOf(TOTAL_SUPPLY, 50); // 0.5%
    
            isLimitExempt[_owner] = true;
            isLimitExempt[address(this)] = true;
    
            emit Distributed(
                treasuryWallet,
                rewardsWallet,
                devWallet,
                marketingWallet,
                liquidityWallet,
                advisorsWallet,
                daoWallet
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
