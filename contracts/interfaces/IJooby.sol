// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IJooby is IERC20Metadata {
    error MaximumSupplyWasNotMinted();
    error EmptySetOfLiquidityPools();
    error EmptySetOfWhitelistedAccounts();
    error TradingWasAlreadyEnabled();
    error ZeroAddressEntry();
    error ForbiddenToMintTokens();
    error MaximumSupplyWasExceeded();
    error ForbiddenToBurnTokens();
    error MaximumBurnPercentageWasExceeded();
    error AlreadyInLiquidityPoolsSet(address account);
    error NotFoundInLiquidityPoolsSet(address account);
    error AlreadyInWhitelistedAccountsSet(address account);
    error NotFoundInWhitelistedAccountsSet(address account);
    error AlreadyInBlocklistedAccountsSet(address account);
    error NotFoundInBlocklistedAccountsSet(address account);
    error AlreadyInCommissionExemptAccountsSet(address account);
    error NotFoundInCommissionExemptAccountsSet(address account);
    error ForbiddenToUpdatePurchaseProtectionPeriod();
    error ForbiddenToUpdateSaleProtectionPeriod();
    error InvalidCommissionRecipient();
    error ForbiddenToUpdateMaximumPurchaseAmountDuringProtectionPeriod();
    error MaximumPercentageOfSalesCommissionWasExceeded();
    error AlreadyInBurnProtectedAccountsSet();
    error NotFoundInBurnProtectedAccountsSet();
    error Blocklisted();
    error ForbiddenToTransferTokens(address from, address to, uint256 amount);
    error ForbiddenToSaleTokens();

    event TradingEnabled(uint256 indexed tradingEnabledTimestamp);
    event AccumulatedCommissionWasWithdrawn(uint256 indexed commissionAmount);
    event BlocklistedAccountWasNullified(address indexed account, uint256 indexed amount);
    event LiquidityPoolsAdded(address[] indexed liquidityPools);
    event LiquidityPoolsRemoved(address[] indexed liquidityPools);
    event WhitelistedAccountsAdded(address[] indexed accounts);
    event WhitelistedAccountsRemoved(address[] indexed accounts);
    event BlocklistedAccountsAdded(address[] indexed accounts);
    event BlocklistedAccountsRemoved(address[] indexed accounts);
    event CommissionExemptAccountsAdded(address[] indexed accounts);
    event CommissionExemptAccountsRemoved(address[] indexed accounts);
    event PurchaseProtectionPeriodWasUpdated(uint256 indexed newPurchaseProtectionPeriod);
    event SaleProtectionPeriodWasUpdated(uint256 indexed newSaleProtectionPeriod);
    event CommissionRecipientWasUpdated(address indexed newCommissionRecipient);
    event MaximumPurchaseAmountDuringProtectionPeriodWasUpdated(uint256 indexed newMaximumPurchaseAmountDuringProtectionPeriod);
    event PercentageOfSalesCommissionWasUpdated(uint256 indexed newPercentageOfSalesCommission);
    event BurnProtectedAccountAdded(address indexed account);
    event BurnProtectedAccountRemoved(address indexed account);

    /// @notice Enables trading.
    function enableTrading() external;

    /// @notice Transfers the accumulated commission on the contract to the commission recipient.
    function withdrawAccumulatedCommission() external;

    /// @notice Nullifies the blocklisted account.
    /// @param account Account address.
    function nullifyBlocklistedAccount(address account) external;

    /// @notice Creates `amount_` tokens and assigns them to `account`, increasing the total supply.
    /// @param account Token receiver.
    /// @param amount Amount ot tokens to mint.
    function mint(address account, uint256 amount) external;

    /// @notice Destroys the certain percentage of the total supply.
    /// @param percentage Percentage of the total supply to destroy.
    function burn(uint256 percentage) external;

    /// @notice Adds `accounts_` to the liquidity pools set.
    /// @param accounts Account addresses.
    function addLiquidityPools(address[] calldata accounts) external;

    /// @notice Removes `accounts_` from the liquidity pools set.
    /// @param accounts Account addresses.
    function removeLiquidityPools(address[] calldata accounts) external;

    /// @notice Adds `accounts_` to the whitelisted accounts set.
    /// @param accounts Account addresses.
    function addWhitelistedAccounts(address[] calldata accounts) external;

    /// @notice Removes `accounts_` from the whitelisted accounts set.
    /// @param accounts Account addresses.
    function removeWhitelistedAccounts(address[] calldata accounts) external;

    /// @notice Adds `accounts_` to the blocklisted accounts set.
    /// @param accounts Account addresses.
    function addBlocklistedAccounts(address[] calldata accounts) external;

    /// @notice Removes `accounts_` from the blocklisted accounts set.
    /// @param accounts Account addresses.
    function removeBlocklistedAccounts(address[] calldata accounts) external;

    /// @notice Adds `accounts_` to the commission exempt accounts set.
    /// @param accounts Account addresses.
    function addCommissionExemptAccounts(address[] calldata accounts) external;

    /// @notice Removes `accounts_` from the commission exempt accounts set.
    /// @param accounts Account addresses.
    function removeCommissionExemptAccounts(address[] calldata accounts) external;

    /// @notice Adds `account` to the burn-protected accounts set.
    /// @param account Account address.
    function addBurnProtectedAccount(address account) external;

    /// @notice Removes `account` from the burn-protected accounts set.
    /// @param account Account address.
    function removeBurnProtectedAccount(address account) external;

    /// @notice Updates the purchase protection period.
    /// @param purchaseProtectionPeriod New purchase protection period value in seconds.
    function updatePurchaseProtectionPeriod(uint256 purchaseProtectionPeriod) external;

    /// @notice Updates the sale protection period.
    /// @param saleProtectionPeriod New sale protection period value in seconds.
    function updateSaleProtectionPeriod(uint256 saleProtectionPeriod) external;

    /// @notice Updates the commission recipient.
    /// @param commissionRecipient New commission recipient address.
    function updateCommissionRecipient(address commissionRecipient) external;

    /// @notice Updates the maximum purchase amount during protection period.
    /// @param maximumPurchaseAmountDuringProtectionPeriod New maximum purchase amount during protection period value.
    function updateMaximumPurchaseAmountDuringProtectionPeriod(uint256 maximumPurchaseAmountDuringProtectionPeriod) external;

    /// @notice Updates the percentage of sales commission.
    /// @param percentageOfSalesCommission New percentage of sales commission value.
    function updatePercentageOfSalesCommission(uint256 percentageOfSalesCommission) external;

    /// @notice Checks if `account` is in the liquidity pools set.
    /// @param account Account address.
    /// @return Boolean value indicating whether the `account` is in the liquidity pools set.
    function isLiquidityPool(address account) external view returns (bool);

    /// @notice Checks if `account` is in the whitelisted accounts set.
    /// @param account Account address.
    /// @return Boolean value indicating whether `account` is in the whitelisted accounts set.
    function isWhitelistedAccount(address account) external view returns (bool);

    /// @notice Checks if `account` is in the blocklisted accounts set.
    /// @param account Account address.
    /// @return Boolean value indicating whether `account` is in the blocklisted accounts set.
    function isBlocklistedAccount(address account) external view returns (bool);

    /// @notice Checks if `account` is in the commission exempt accounts set.
    /// @param account Account address.
    /// @return Boolean value indicating whether `account` is in the commission exempt accounts set.
    function isCommissionExemptAccount(address account) external view returns (bool);

    /// @notice Checks if `account` is in the burn-protected accounts set.
    /// @param account Account address.
    /// @return Boolean value indicating whether `account` is in the burn-protected accounts set.
    function isBurnProtectedAccount(address account) external view returns (bool);
}