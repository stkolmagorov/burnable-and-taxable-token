// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

import "./interfaces/IJooby.sol";

contract Jooby is IJooby, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PRBMathUD60x18 for uint256;

    uint256 public constant MAXIMUM_SUPPLY = 100_000_000_000 ether;
    uint256 public constant BASE_PERCENTAGE = 10_000;
    uint256 public constant MAXIMUM_BURN_PERCENTAGE = 400;
    uint256 public constant MAXIMUM_PERCENTAGE_OF_SALES_COMMISSION = 400;
    bytes32 public constant LIQUIDITY_PROVIDER_ROLE = keccak256("LIQUIDITY_PROVIDER_ROLE");

    address public commissionRecipient;
    uint256 public purchaseProtectionPeriod = 30 minutes;
    uint256 public saleProtectionPeriod = 60 minutes;
    uint256 public maximumPurchaseAmountDuringProtectionPeriod = 15_000_000 ether;
    uint256 public percentageOfSalesCommission = 200;
    uint256 public cumulativeAdjustmentFactor = PRBMathUD60x18.fromUint(1);
    uint256 public tradingEnabledTimestamp;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    bool public isTradingEnabled;

    mapping(address => bool) public isPurchaseWasMadeDuringProtectionPeriodByAccount;
    mapping(address => uint256) public availableAmountToPurchaseDuringProtectionPeriodByAccount;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    EnumerableSet.AddressSet private _liquidityPools;
    EnumerableSet.AddressSet private _whitelistedAccounts;
    EnumerableSet.AddressSet private _blocklistedAccounts;
    EnumerableSet.AddressSet private _commissionExemptAccounts;
    EnumerableSet.AddressSet private _burnProtectedAccounts;

    /// @param commissionRecipient_ Commission recipient address.
    /// @param liquidityProvider_ Liquidity provider address.
    constructor(address commissionRecipient_, address liquidityProvider_) {
        commissionRecipient = commissionRecipient_;
        _name = "Jooby";
        _symbol = "JOOBY";
        _commissionExemptAccounts.add(liquidityProvider_);
        _burnProtectedAccounts.add(commissionRecipient_);
        _burnProtectedAccounts.add(address(this));
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LIQUIDITY_PROVIDER_ROLE, liquidityProvider_);
    }

    /// @notice Enables trading.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    function enableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_totalSupply != MAXIMUM_SUPPLY) {
            revert MaximumSupplyWasNotMinted();
        }
        if (_liquidityPools.length() == 0) {
            revert EmptySetOfLiquidityPools();
        }
        if (_whitelistedAccounts.length() == 0) {
            revert EmptySetOfWhitelistedAccounts();
        }
        if (isTradingEnabled) {
            revert TradingWasAlreadyEnabled();
        }
        isTradingEnabled = true;
        tradingEnabledTimestamp = block.timestamp;
        emit TradingEnabled(block.timestamp);
    }

    /// @notice Transfers the accumulated commission on the contract to the commission recipient.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    function withdrawAccumulatedCommission() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 commissionAmount = _balances[address(this)];
        if (commissionAmount > 0) {
            _transfer(address(this), commissionRecipient, commissionAmount);
            emit AccumulatedCommissionWasWithdrawn(commissionAmount);
        }
    }

    /// @notice Nullifies the blocklisted account.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function nullifyBlocklistedAccount(address account_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (!_blocklistedAccounts.contains(account_)) {
            revert NotFoundInBlocklistedAccountsSet({account: account_});
        }
        uint256 amount = balanceOf(account_);
        _balances[account_] = 0;
        _balances[commissionRecipient] += amount;
        emit BlocklistedAccountWasNullified(account_, amount);
    }

    /// @notice Creates `amount_` tokens and assigns them to `account_`, increasing the total supply.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Token receiver.
    /// @param amount_ Amount ot tokens to mint.
    function mint(address account_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (isTradingEnabled) {
            revert ForbiddenToMintTokens();
        }
        if (_totalSupply + amount_ > MAXIMUM_SUPPLY) {
            revert MaximumSupplyWasExceeded();
        }
        _totalSupply += amount_;
        unchecked {
            _balances[account_] += amount_;
        }
        emit Transfer(address(0), account_, amount_);
    }

    /// @notice Destroys `percentage_` of total supply.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param percentage_ Percentage of total supply to destroy.
    function burn(uint256 percentage_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isTradingEnabled) {
            revert ForbiddenToBurnTokens();
        }
        if (percentage_ > MAXIMUM_BURN_PERCENTAGE) {
            revert MaximumBurnPercentageWasExceeded();
        }
        uint256 currentTotalSupply = _totalSupply;
        uint256 nonBurnableSupply = _totalSupplyOfBurnProtectedAccounts();
        uint256 burnableSupply = currentTotalSupply - nonBurnableSupply;
        uint256 burnAmount = currentTotalSupply * percentage_ / BASE_PERCENTAGE;
        uint256 adjustmentFactor = burnableSupply.div(burnableSupply - burnAmount);
        cumulativeAdjustmentFactor = cumulativeAdjustmentFactor.mul(adjustmentFactor);
        _totalSupply = nonBurnableSupply + burnableSupply.div(adjustmentFactor);
        emit Transfer(address(0), address(0), currentTotalSupply - _totalSupply);
    }

    /// @notice Adds `accounts_` to the liquidity pools set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_liquidityPools.add(accounts_[i])) {
                revert AlreadyInLiquidityPoolsSet({account: accounts_[i]});
            }
        }
        emit LiquidityPoolsAdded(accounts_);
    }

    /// @notice Removes `accounts_` from the liquidity pools set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeLiquidityPools(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_liquidityPools.remove(accounts_[i])) {
                revert NotFoundInLiquidityPoolsSet({account: accounts_[i]});
            }
        }
        emit LiquidityPoolsRemoved(accounts_);
    }

    /// @notice Adds `accounts_` to the whitelisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addWhitelistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_whitelistedAccounts.add(accounts_[i])) {
                revert AlreadyInWhitelistedAccountsSet({account: accounts_[i]});
            }
        }
        emit WhitelistedAccountsAdded(accounts_);
    }

    /// @notice Removes `accounts_` from the whitelisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeWhitelistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_whitelistedAccounts.remove(accounts_[i])) {
                revert NotFoundInWhitelistedAccountsSet({account: accounts_[i]});
            }
        }
        emit WhitelistedAccountsRemoved(accounts_);
    }

    /// @notice Adds `accounts_` to the blocklisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addBlocklistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_blocklistedAccounts.add(accounts_[i])) {
                revert AlreadyInBlocklistedAccountsSet({account: accounts_[i]});
            }
        }
        emit BlocklistedAccountsAdded(accounts_);
    }

    /// @notice Removes `accounts_` from the blocklisted accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeBlocklistedAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_blocklistedAccounts.remove(accounts_[i])) {
                revert NotFoundInBlocklistedAccountsSet({account: accounts_[i]});
            }
        }
        emit BlocklistedAccountsRemoved(accounts_);
    }

    /// @notice Adds `accounts_` to the commission exempt accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function addCommissionExemptAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_commissionExemptAccounts.add(accounts_[i])) {
                revert AlreadyInCommissionExemptAccountsSet({account: accounts_[i]});
            }
        }
        emit CommissionExemptAccountsAdded(accounts_);
    }

    /// @notice Removes `accounts_` from the commission exempt accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param accounts_ Account addresses.
    function removeCommissionExemptAccounts(address[] calldata accounts_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts_.length; i++) {
            if (!_commissionExemptAccounts.remove(accounts_[i])) {
                revert NotFoundInCommissionExemptAccountsSet({account: accounts_[i]});
            }
        }
        emit CommissionExemptAccountsRemoved(accounts_);
    }

    /// @notice Updates the purchase protection period.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param purchaseProtectionPeriod_ New purchase protection period value in seconds.
    function updatePurchaseProtectionPeriod(uint256 purchaseProtectionPeriod_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isTradingEnabled) {
            revert ForbiddenToUpdatePurchaseProtectionPeriod();
        }
        purchaseProtectionPeriod = purchaseProtectionPeriod_;
        emit PurchaseProtectionPeriodWasUpdated(purchaseProtectionPeriod_);
    }

    /// @notice Updates the sale protection period.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param saleProtectionPeriod_ New sale protection period value in seconds.
    function updateSaleProtectionPeriod(uint256 saleProtectionPeriod_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isTradingEnabled) {
            revert ForbiddenToUpdateSaleProtectionPeriod();
        }
        saleProtectionPeriod = saleProtectionPeriod_;
        emit SaleProtectionPeriodWasUpdated(saleProtectionPeriod_);
    }

    /// @notice Updates the commission recipient.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param commissionRecipient_ New commission recipient address.
    function updateCommissionRecipient(address commissionRecipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address currentCommissionRecipient = commissionRecipient;
        if (currentCommissionRecipient == commissionRecipient_ || commissionRecipient_ == address(0)) {
            revert InvalidCommissionRecipient();
        }
        removeBurnProtectedAccount(currentCommissionRecipient);
        commissionRecipient = commissionRecipient_;
        addBurnProtectedAccount(commissionRecipient_);
        emit CommissionRecipientWasUpdated(commissionRecipient_);
    }

    /// @notice Updates the maximum purchase amount during protection period.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param maximumPurchaseAmountDuringProtectionPeriod_ New maximum purchase amount during protection period value.
    function updateMaximumPurchaseAmountDuringProtectionPeriod(
        uint256 maximumPurchaseAmountDuringProtectionPeriod_
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (isTradingEnabled) {
            revert ForbiddenToUpdateMaximumPurchaseAmountDuringProtectionPeriod();
        }
        maximumPurchaseAmountDuringProtectionPeriod = maximumPurchaseAmountDuringProtectionPeriod_;
        emit MaximumPurchaseAmountDuringProtectionPeriodWasUpdated(maximumPurchaseAmountDuringProtectionPeriod_);
    }

    /// @notice Updates the percentage of sales commission.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param percentageOfSalesCommission_ New percentage of sales commission value.
    function updatePercentageOfSalesCommission(uint256 percentageOfSalesCommission_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (percentageOfSalesCommission_ > MAXIMUM_PERCENTAGE_OF_SALES_COMMISSION) {
            revert MaximumPercentageOfSalesCommissionWasExceeded();
        }
        percentageOfSalesCommission = percentageOfSalesCommission_;
        emit PercentageOfSalesCommissionWasUpdated(percentageOfSalesCommission_);
    }

    /// @notice Sets `amount_` as the allowance of `spender_` over the caller's tokens.
    /// @param spender_ Token spender address.
    /// @param amount_ Amount of tokens to approve.
    /// @return Boolean value indicating whether the operation succeeded.
    function approve(address spender_, uint256 amount_) external override returns (bool) {
        if (msg.sender == address(0) || spender_ == address(0)) {
            revert ZeroAddressEntry();
        }
        _allowances[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    /// @notice Moves `amount_` tokens from the caller's account to `to_`.
    /// @param to_ Token receiver.
    /// @param amount_ Amount of tokens to transfer.
    /// @return Boolean value indicating whether the operation succeeded.
    function transfer(address to_, uint256 amount_) external override returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }
    
    /// @notice Moves `amount_` tokens from `from_` to `to_` using the
    /// allowance mechanism, `amount_` is then deducted from the caller's allowance.
    /// @param from_ Token sender.
    /// @param to_ Token receiver.
    /// @param amount_ Amount of tokens to transfer.
    /// @return Boolean value indicating whether the operation succeeded.
    function transferFrom(address from_, address to_, uint256 amount_) external override returns (bool) {
        _allowances[from_][msg.sender] -= amount_;
        _transfer(from_, to_, amount_);
        return true;
    }

    /// @notice Retrieves the name of the token.
    /// @return Name of the token.
    function name() external view override returns (string memory) {
        return _name;
    }
    
    /// @notice Retrieves the symbol of the token, usually a shorter version of the name.
    /// @return Symbol of the token.
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    /// @notice Retrieves the number of decimals utilized to get its human-readable representation.
    /// @return Number of decimals used to get its user representation.
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    /// @notice Retrieves the amount of tokens in existence.
    /// @return Amount of tokens in existence.
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /// @notice Retrieves the remaining number of tokens that `spender_` will be
    /// allowed to spend on behalf of `owner_` through `transferFrom()` function. This is zero by default.
    /// @param owner_ Token owner address.
    /// @param spender_ Token spender address.
    /// @return Remaining number of tokens that `spender_` will be
    /// allowed to spend on behalf of `owner_` through `transferFrom()` function.
    function allowance(address owner_, address spender_) external view override returns (uint256) {
        return _allowances[owner_][spender_];
    }

    /// @notice Checks if `account_` is in the liquidity pools set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether the `account_` is in the liquidity pools set.
    function isLiquidityPool(address account_) external view returns (bool) {
        return _liquidityPools.contains(account_);
    }

    /// @notice Checks if `account_` is in the whitelisted accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the whitelisted accounts set.
    function isWhitelistedAccount(address account_) external view returns (bool) {
        return _whitelistedAccounts.contains(account_);
    }

    /// @notice Checks if `account_` is in the blocklisted accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the blocklisted accounts set.
    function isBlocklistedAccount(address account_) external view returns (bool) {
        return _blocklistedAccounts.contains(account_);
    }

    /// @notice Checks if `account_` is in the commission exempt accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the commission exempt accounts set.
    function isCommissionExemptAccount(address account_) external view returns (bool) {
        return _commissionExemptAccounts.contains(account_);
    }

    /// @notice Checks if `account_` is in the burn-protected accounts set.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether `account_` is in the burn-protected accounts set.
    function isBurnProtectedAccount(address account_) external view returns (bool) {
        return _burnProtectedAccounts.contains(account_);
    }

    /// @notice Adds `account_` to the burn-protected accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function addBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.add(account_)) {
            revert AlreadyInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].div(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountAdded(account_);
    }

    /// @notice Removes `account_` from the burn-protected accounts set.
    /// @dev Could be called only by the DEFAULT_ADMIN_ROLE.
    /// @param account_ Account address.
    function removeBurnProtectedAccount(address account_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_burnProtectedAccounts.remove(account_)) {
            revert NotFoundInBurnProtectedAccountsSet();
        }
        _balances[account_] = _balances[account_].mul(cumulativeAdjustmentFactor);
        emit BurnProtectedAccountRemoved(account_);
    }

    /// @notice Retrieves the amount of tokens owned by `account_`.
    /// @param account_ Account address.
    /// @return Amount of tokens owned by `account_`.
    function balanceOf(address account_) public view override returns (uint256) {
        if (_burnProtectedAccounts.contains(account_)) {
            return _balances[account_];
        } else {
            return _balances[account_].div(cumulativeAdjustmentFactor);
        }
    }

    /// @notice Moves `amount_` of tokens from `from_` to `to_`. 
    /// @param from_ Token sender.
    /// @param to_ Token receiver.
    /// @param amount_ Amount of tokens to transfer.
    function _transfer(address from_, address to_, uint256 amount_) private {
        if (from_ == address(0) || to_ == address(0)) {
            revert ZeroAddressEntry();
        }
        if (_blocklistedAccounts.contains(from_) || _blocklistedAccounts.contains(to_)) {
            revert Blocklisted();
        }
        if (!isTradingEnabled) {
            if (_hasLimits(from_, to_)) {
                revert ForbiddenToTransferTokens({
                    from: from_,
                    to: to_,
                    amount: amount_
                });
            }
        } else {
            uint256 timeElapsed = block.timestamp - tradingEnabledTimestamp;
            if (timeElapsed < purchaseProtectionPeriod && _liquidityPools.contains(from_)) {
                if (_whitelistedAccounts.contains(tx.origin)) {
                    if (!isPurchaseWasMadeDuringProtectionPeriodByAccount[tx.origin]) {
                        availableAmountToPurchaseDuringProtectionPeriodByAccount[tx.origin] 
                            = maximumPurchaseAmountDuringProtectionPeriod - amount_;
                        isPurchaseWasMadeDuringProtectionPeriodByAccount[tx.origin] = true;
                    } else {
                        availableAmountToPurchaseDuringProtectionPeriodByAccount[tx.origin] -= amount_;
                    }
                } else {
                    revert ForbiddenToTransferTokens({
                        from: from_,
                        to: to_,
                        amount: amount_
                    });
                }
            }
            if (timeElapsed < saleProtectionPeriod && _liquidityPools.contains(to_)) {
                revert ForbiddenToSaleTokens();
            }
        }
        bool shouldTakeSalesCommission;
        if (!_commissionExemptAccounts.contains(from_) && _liquidityPools.contains(to_)) {
            shouldTakeSalesCommission = true;
        }
        uint256 adjustmentFactor = cumulativeAdjustmentFactor;
        uint256 adjustedAmount = amount_.mul(adjustmentFactor);
        uint256 amountToReceive = shouldTakeSalesCommission ? _takeSalesCommission(from_, amount_) : amount_;
        uint256 adjustedAmountToReceive = amountToReceive.mul(adjustmentFactor);
        if (!_burnProtectedAccounts.contains(from_) && _burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= adjustedAmount;
            _balances[to_] += amountToReceive;
        } else if (_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= amount_;
            _balances[to_] += adjustedAmountToReceive;
        } else if (!_burnProtectedAccounts.contains(from_) && !_burnProtectedAccounts.contains(to_)) {
            _balances[from_] -= adjustedAmount;
            _balances[to_] += adjustedAmountToReceive;
        } else {
            _balances[from_] -= amount_;
            _balances[to_] += amountToReceive;
        }
        emit Transfer(from_, to_, amountToReceive);
    }

    /// @notice Takes the sales commission and transfers it to the balance of the contract.
    /// @param from_ Token sender.
    /// @param amount_ Amount of tokens to transfer.
    /// @return Amount of tokens to transfer including the sales commission.
    function _takeSalesCommission(address from_, uint256 amount_) private returns (uint256) {
        uint256 commissionAmount = amount_ * percentageOfSalesCommission / BASE_PERCENTAGE;
        if (commissionAmount > 0) {
            _balances[address(this)] += commissionAmount;
            emit Transfer(from_, address(this), commissionAmount);
        }
        return amount_ - commissionAmount;
    }

    /// @notice Determines whether tokens can be sent between sender 
    /// and receiver when trading is not enabled.
    /// @param from_ Token sender.
    /// @param to_ Token receiver.
    /// @return Boolean value indicating whether tokens can be sent.
    function _hasLimits(address from_, address to_) private view returns (bool) {
        return
            !hasRole(LIQUIDITY_PROVIDER_ROLE, from_) &&
            !hasRole(LIQUIDITY_PROVIDER_ROLE, to_);
    }

    /// @notice Retrieves the total supply of burn-protected accounts.
    /// @return supply_ Total supply of burn-protected accounts.
    function _totalSupplyOfBurnProtectedAccounts() private view returns (uint256 supply_) {
        uint256 length = _burnProtectedAccounts.length();
        for (uint256 i = 0; i < length; i++) {
            supply_ += _balances[_burnProtectedAccounts.at(i)];
        }
    }
}