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
}