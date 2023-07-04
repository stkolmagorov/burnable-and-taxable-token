const { expect } = require("chai");
const { loadFixture, time, impersonateAccount } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require("hardhat");

describe("Jooby", () => {
    const ONE_ETHER = ethers.utils.parseEther("1");
    const HUNDRED = ethers.utils.parseEther("100");
    const MAXIMUM_JOOBY_TOKEN_SUPPLY = ethers.utils.parseEther("100000000000");
    const ADMIN_ROLE = ethers.constants.HashZero;
    const LIQUIDITY_PROVIDER_ROLE = "0x42802a37d17e698ec3d88f7a6917f1f5a6abb4d99a8f4255c389e56d10218a64";

    before(async () => {
        [owner, liquidityProvider, alice, bob, commissionRecipient, liquidityPool] = await ethers.getSigners();
    });

    const fixture = async () => {
        // Jooby token deployment
        const Jooby = await ethers.getContractFactory("Jooby");
        const jooby = await Jooby.deploy(commissionRecipient.address, liquidityProvider.address);
        return jooby;
    }

    beforeEach(async () => {
        jooby = await loadFixture(fixture);
    });

    it("Successful deployment", async () => {
        // Checking if everything is setted up correctly
        expect(await jooby.hasRole(ADMIN_ROLE, owner.address)).to.equal(true);
        expect(await jooby.hasRole(LIQUIDITY_PROVIDER_ROLE, liquidityProvider.address)).to.equal(true);
        expect(await jooby.commissionRecipient()).to.equal(commissionRecipient.address);
        expect(await jooby.isCommissionExemptAccount(liquidityProvider.address)).to.equal(true);
        expect(await jooby.isBurnProtectedAccount(jooby.address)).to.equal(true);
        expect(await jooby.name()).to.equal("Jooby");
        expect(await jooby.symbol()).to.equal("JOOBY");
        expect(await jooby.decimals()).to.equal(18);
        expect(await jooby.totalSupply()).to.equal(0);
    });

    it("Successful addLiquidityPools() execution", async () => {
        // Attempt to set from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).addLiquidityPools([liquidityPool.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful execution
        await jooby.addLiquidityPools([liquidityPool.address]);
        expect(await jooby.isLiquidityPool(liquidityPool.address)).to.equal(true);
        // Attempt to add again the same liquidity pool
        await expect(jooby.addLiquidityPools([liquidityPool.address])).to.be.revertedWith("AlreadyInLiquidityPoolsSet");
    });

    it("Successful removeLiquidityPools() execution", async () => {
        // Attempt to set from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).removeLiquidityPools([liquidityPool.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Addition
        await jooby.addLiquidityPools([liquidityPool.address]);
        expect(await jooby.isLiquidityPool(liquidityPool.address)).to.equal(true);
        // Successful removal
        await jooby.removeLiquidityPools([liquidityPool.address]);
        expect(await jooby.isLiquidityPool(liquidityPool.address)).to.equal(false);
        // Attempt to remove again
        await expect(jooby.removeLiquidityPools([liquidityPool.address])).to.be.revertedWith("NotFoundInLiquidityPoolsSet");
    });

    it("Successful mint() execution", async () => {
        // Attempt to mint from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).mint(owner.address, ONE_ETHER))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Attempt to mint to zero address
        await expect(jooby.mint(ethers.constants.AddressZero, MAXIMUM_JOOBY_TOKEN_SUPPLY)).to.be.revertedWith("ZeroAddressEntry");
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        expect(await jooby.balanceOf(owner.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Attempt to mint more than MAXIMUM_SUPPLY
        await expect(jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY)).to.be.revertedWith("MaximumSupplyWasExceeded");
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        // Attempt to mint
        await expect(jooby.mint(owner.address, ONE_ETHER)).to.be.revertedWith("ForbiddenToMintTokens");
    });

    it("Successful burn() execution", async () => {
        // Attempt to burn from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).burn(100))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Mint half of the MAXIMUM_SUPPLY to owner
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
        // Mint half of the MAXIMUM_SUPPLY to liquidity provider
        await jooby.mint(liquidityProvider.address, MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
        // Add liquidity provider to burn-protected accounts
        await jooby.addBurnProtectedAccount(liquidityProvider.address);
        // Attempt to burn when trading has not enabled
        await expect(jooby.burn(100)).to.be.revertedWith("ForbiddenToBurnTokens");
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        // Attempt to burn more than 4% of TS
        await expect(jooby.burn(500)).to.be.revertedWith("MaximumBurnPercentageWasExceeded");
        // Successful burn 1% of TS
        await jooby.burn(100);
        const onePercentage = MAXIMUM_JOOBY_TOKEN_SUPPLY.mul(1).div(100);
        expect(await jooby.totalSupply()).to.be.closeTo(MAXIMUM_JOOBY_TOKEN_SUPPLY.sub(onePercentage), ONE_ETHER);
        expect(await jooby.balanceOf(owner.address)).to.closeTo(MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2).sub(onePercentage), ONE_ETHER);
        expect(await jooby.balanceOf(liquidityProvider.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
    });

    it("Successful nullifyBlocklistedAccount() execution", async () => {
        // Attempt to nullify from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).nullifyBlocklistedAccount(alice.address))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Attempt to nullify zero address
        await expect(jooby.nullifyBlocklistedAccount(ethers.constants.AddressZero)).to.be.revertedWith("ZeroAddressEntry");
        // Attempt to nullify not blocklisted account
        await expect(jooby.nullifyBlocklistedAccount(alice.address)).to.be.revertedWith("NotFoundInBlocklistedAccountsSet");
        // Successful nullfying
        await jooby.mint(alice.address, ONE_ETHER);
        await jooby.addBlocklistedAccounts([alice.address]);
        await jooby.nullifyBlocklistedAccount(alice.address);
        expect(await jooby.balanceOf(commissionRecipient.address)).to.equal(ONE_ETHER);
        expect(await jooby.balanceOf(alice.address)).to.equal(0);
    });

    it("Successful addBurnProtectedAccount() execution", async () => {
        // Attempt to add from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).addBurnProtectedAccount(owner.address))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addBurnProtectedAccount(owner.address);
        expect(await jooby.isBurnProtectedAccount(owner.address)).to.equal(true); 
        // Attempt to add again
        await expect(jooby.addBurnProtectedAccount(owner.address)).to.be.revertedWith("AlreadyInBurnProtectedAccountsSet");
    });

    it("Successful addBlocklistedAccounts() execution", async () => {
        // Attempt to add from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).addBlocklistedAccounts([owner.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addBlocklistedAccounts([owner.address]);
        expect(await jooby.isBlocklistedAccount(owner.address)).to.equal(true); 
        // Attempt to add again
        await expect(jooby.addBlocklistedAccounts([owner.address])).to.be.revertedWith("AlreadyInBlocklistedAccountsSet");
    });

    it("Successful addWhitelistedAccounts() execution", async () => {
        // Attempt to add from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).addWhitelistedAccounts([owner.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addWhitelistedAccounts([owner.address]);
        expect(await jooby.isWhitelistedAccount(owner.address)).to.equal(true); 
        // Attempt to add again
        await expect(jooby.addWhitelistedAccounts([owner.address])).to.be.revertedWith("AlreadyInWhitelistedAccountsSet");
    });

    it("Successful addCommissionExemptAccounts() execution", async () => {
        // Attempt to add from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).addCommissionExemptAccounts([owner.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addCommissionExemptAccounts([owner.address]);
        expect(await jooby.isCommissionExemptAccount(owner.address)).to.equal(true); 
        // Attempt to add again
        await expect(jooby.addCommissionExemptAccounts([owner.address])).to.be.revertedWith("AlreadyInCommissionExemptAccountsSet");
    });

    it("Successful removeBurnProtectedAccount() execution", async () => {
        // Attempt to remove from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).removeBurnProtectedAccount(owner.address))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addBurnProtectedAccount(owner.address);
        expect(await jooby.isBurnProtectedAccount(owner.address)).to.equal(true); 
        // Successful removal
        await jooby.removeBurnProtectedAccount(owner.address);
        expect(await jooby.isBurnProtectedAccount(owner.address)).to.equal(false); 
        // Attempt to remove again
        await expect(jooby.removeBurnProtectedAccount(owner.address)).to.be.revertedWith("NotFoundInBurnProtectedAccountsSet");
    });

    it("Successful removeBlocklistedAccounts() execution", async () => {
        // Attempt to remove from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).removeBlocklistedAccounts([owner.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addBlocklistedAccounts([owner.address]);
        expect(await jooby.isBlocklistedAccount(owner.address)).to.equal(true); 
        // Successful removal
        await jooby.removeBlocklistedAccounts([owner.address]);
        expect(await jooby.isBlocklistedAccount(owner.address)).to.equal(false); 
        // Attempt to remove again
        await expect(jooby.removeBlocklistedAccounts([owner.address])).to.be.revertedWith("NotFoundInBlocklistedAccountsSet");
    });

    it("Successful removeWhitelistedAccounts() execution", async () => {
        // Attempt to remove from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).removeWhitelistedAccounts([owner.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addWhitelistedAccounts([owner.address]);
        expect(await jooby.isWhitelistedAccount(owner.address)).to.equal(true); 
        // Successful removal
        await jooby.removeWhitelistedAccounts([owner.address]);
        expect(await jooby.isWhitelistedAccount(owner.address)).to.equal(false); 
        // Attempt to remove again
        await expect(jooby.removeWhitelistedAccounts([owner.address])).to.be.revertedWith("NotFoundInWhitelistedAccountsSet");
    });

    it("Successful removeCommissionExemptAccounts() execution", async () => {
        // Attempt to remove from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).removeCommissionExemptAccounts([owner.address]))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful addition
        await jooby.addCommissionExemptAccounts([owner.address]);
        expect(await jooby.isCommissionExemptAccount(owner.address)).to.equal(true); 
        // Successful removal
        await jooby.removeCommissionExemptAccounts([owner.address]);
        expect(await jooby.isCommissionExemptAccount(owner.address)).to.equal(false); 
        // Attempt to remove again
        await expect(jooby.removeCommissionExemptAccounts([owner.address])).to.be.revertedWith("NotFoundInCommissionExemptAccountsSet");
    });

    it("Successful updatePurchaseProtectionPeriod() execution", async () => {
        // Attempt to update from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).updatePurchaseProtectionPeriod(1))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful updating
        await jooby.updatePurchaseProtectionPeriod(100);
        expect(await jooby.purchaseProtectionPeriod()).to.equal(100);
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        await expect(jooby.updatePurchaseProtectionPeriod(1)).to.be.revertedWith("ForbiddenToUpdatePurchaseProtectionPeriod");
    });

    it("Successful updateSaleProtectionPeriod() execution", async () => {
        // Attempt to update from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).updateSaleProtectionPeriod(1))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful updating
        await jooby.updateSaleProtectionPeriod(100);
        expect(await jooby.saleProtectionPeriod()).to.equal(100);
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        await expect(jooby.updateSaleProtectionPeriod(1)).to.be.revertedWith("ForbiddenToUpdateSaleProtectionPeriod");
    });

    it("Successful updateCommissionRecipient() execution", async () => {
        // Attempt to update from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).updateCommissionRecipient(owner.address))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Attempt to update with zero address
        await expect(jooby.updateCommissionRecipient(ethers.constants.AddressZero)).to.be.revertedWith("InvalidCommissionRecipient");
        // Attempt to update with the same address address
        await expect(jooby.updateCommissionRecipient(commissionRecipient.address)).to.be.revertedWith("InvalidCommissionRecipient");
        // Successful updating
        await jooby.updateCommissionRecipient(owner.address);
        expect(await jooby.commissionRecipient()).to.equal(owner.address);
    });

    it("Successful updatePercentageOfSalesCommission() execution", async () => {
        // Attempt to update from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).updatePercentageOfSalesCommission(100))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Attempt to update more than 4%
        await expect(jooby.updatePercentageOfSalesCommission(500)).to.be.revertedWith("MaximumPercentageOfSalesCommissionWasExceeded");
        // Successful updating
        await jooby.updatePercentageOfSalesCommission(100);
        expect(await jooby.percentageOfSalesCommission()).to.equal(100);
    });

    it("Successful enableTrading() execution", async () => {
        // Attempt to enable trading from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).enableTrading())
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Attempt to enable trading when totalSupply != MAXIMUM_SUPPLY
        await expect(jooby.enableTrading()).to.be.revertedWith("MaximumSupplyWasNotMinted");
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Attempt to enable without liquidity pool setting
        await expect(jooby.enableTrading()).to.be.revertedWith("EmptySetOfLiquidityPools");
        // Attempt to enable without whitelisted accounts setting
        await jooby.addLiquidityPools([liquidityPool.address]);
        await expect(jooby.enableTrading()).to.be.revertedWith("EmptySetOfWhitelistedAccounts");
        // Successful trading enabling
        expect(await jooby.isTradingEnabled()).to.equal(false);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        expect(await jooby.isTradingEnabled()).to.equal(true);
        // Attempt to enable trading again
        await expect(jooby.enableTrading()).to.be.revertedWith("TradingWasAlreadyEnabled");
    });

    it("Successful purchase restriction logic", async () => {
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(liquidityPool.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Add liquidity pool
        await jooby.addLiquidityPools([liquidityPool.address]);
        // Attempt to update non-granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).updateMaximumPurchaseAmountDuringProtectionPeriod(100))
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful updating
        await jooby.updateMaximumPurchaseAmountDuringProtectionPeriod(HUNDRED);
        expect(await jooby.maximumPurchaseAmountDuringProtectionPeriod()).to.equal(HUNDRED);
        // Enable trading
        await jooby.addWhitelistedAccounts([owner.address]);
        await jooby.enableTrading();
        // Attempt to update available amount to purchase during protection time period
        await expect(jooby.updateMaximumPurchaseAmountDuringProtectionPeriod(100))
            .to.be.revertedWith("ForbiddenToUpdateMaximumPurchaseAmountDuringProtectionPeriod");
        // Purchase
        await jooby.connect(liquidityPool).approve(owner.address, HUNDRED.mul(2));
        await jooby.transferFrom(liquidityPool.address, owner.address, HUNDRED);
        expect(await jooby.availableAmountToPurchaseDuringProtectionPeriodByAccount(owner.address)).to.equal(0);
        // Attempt to purchase more than limit
        await expect(jooby.transferFrom(liquidityPool.address, owner.address, HUNDRED)).to.be.reverted;
    });

    it("Successful sale restriction logic", async () => {
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        // Attempt to sale
        await expect(jooby.transfer(liquidityPool.address, ONE_ETHER)).to.be.revertedWith("ForbiddenToSaleTokens");
        // + 1 hour
        await time.increase(3600);
        // Successful sale
        await jooby.transfer(liquidityPool.address, ONE_ETHER);
    });

    it("Successful blocklist logic", async () => {
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY.sub(ONE_ETHER));
        await jooby.mint(bob.address, ONE_ETHER);
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        // Add bob to blocklist
        await jooby.addBlocklistedAccounts([bob.address]);
        // Attempt to transfer to bob
        await expect(jooby.transfer(bob.address, ONE_ETHER)).to.be.revertedWith("Blocklisted");
        // Attempt to transfer from bob
        await expect(jooby.connect(bob).transfer(owner.address, ONE_ETHER)).to.be.revertedWith("Blocklisted");
    });

    it("Successful _hasLimits() execution", async () => {
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        expect(await jooby.balanceOf(owner.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Attempt to transfer tokens to alice
        await expect(jooby.transfer(alice.address, ONE_ETHER)).to.be.revertedWith("ForbiddenToTransferTokens");
        // Successful token transfer to liquidity provider
        await jooby.transfer(liquidityProvider.address, ONE_ETHER);
        expect(await jooby.balanceOf(liquidityProvider.address)).to.equal(ONE_ETHER);
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        // Successful token transfer to alice
        await jooby.transfer(alice.address, ONE_ETHER);
        expect(await jooby.balanceOf(alice.address)).to.equal(ONE_ETHER);
    });

    it("Successful _transfer() execution", async () => {
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY);
        // Attempt to transfer tokens to alice
        await expect(jooby.transfer(alice.address, ONE_ETHER)).to.be.revertedWith("ForbiddenToTransferTokens");
        // Successful token transfer to liquidity provider
        await jooby.transfer(liquidityProvider.address, MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
        expect(await jooby.balanceOf(liquidityProvider.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        // Attempt to approve on ZERO_ADDRESS
        await expect(jooby.approve(ethers.constants.AddressZero, ONE_ETHER)).to.be.revertedWith("ZeroAddressEntry")
        // Attempt to approve from ZERO_ADDRESS
        await impersonateAccount(ethers.constants.AddressZero);
        const zeroAddressSigner = await ethers.getSigner(ethers.constants.AddressZero);
        await hre.network.provider.send("hardhat_setBalance", [zeroAddressSigner.address, "0x10000000000000000000"]);
        await expect(jooby.connect(zeroAddressSigner).approve(owner.address, ONE_ETHER)).to.be.revertedWith("ZeroAddressEntry");
        // Check allowance
        await jooby.approve(alice.address, ONE_ETHER);
        expect(await jooby.allowance(owner.address, alice.address)).to.equal(ONE_ETHER);
        // Sniping (it wasn't 30 min after trading was enabled
        await expect(jooby.connect(alice).transferFrom(liquidityPool.address, alice.address, 0)).to.be.revertedWith("ForbiddenToTransferTokens");
        // Add alice to blocklist
        await jooby.addBlocklistedAccounts([alice.address]);
        await expect(jooby.connect(alice).transfer(owner.address, 0)).to.be.revertedWith("Blocklisted");
        expect(await jooby.balanceOf(owner.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
        // Successful token transfer to bob
        await jooby.transfer(bob.address, ONE_ETHER);
        expect(await jooby.balanceOf(bob.address)).to.equal(ONE_ETHER);
        // Successful token transfer to owner
        await jooby.connect(bob).transfer(owner.address, ONE_ETHER);
        // Add liquidity provider to burn-protected accounts
        await jooby.addBurnProtectedAccount(liquidityProvider.address);
        // Burn 1%
        await jooby.burn(100);
        const ownerBalanceAfterBurn = ethers.BigNumber.from("49000000000000000021560000000");
        expect(await jooby.balanceOf(owner.address)).to.equal(ownerBalanceAfterBurn);
        expect(await jooby.balanceOf(liquidityProvider.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
        // Attempt to transfer to zero address
        await expect(jooby.transfer(ethers.constants.AddressZero, ONE_ETHER)).to.be.revertedWith("ZeroAddressEntry");
        // Transfer from burn-protected address to non-protected
        await jooby.connect(liquidityProvider).transfer(owner.address, ONE_ETHER);
        expect(await jooby.balanceOf(owner.address)).to.equal(ownerBalanceAfterBurn.add(ONE_ETHER));
        // Transfer from non-protected to burn-protected
        await jooby.transfer(liquidityProvider.address, ONE_ETHER);
        expect(await jooby.balanceOf(liquidityProvider.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2));
        // Add owner to burn-protected accounts
        await jooby.addBurnProtectedAccount(owner.address);
        expect(await jooby.balanceOf(owner.address)).to.equal(ownerBalanceAfterBurn);
        // Transfer from burn-protected to burn-protected
        await jooby.transfer(liquidityProvider.address, ONE_ETHER);
        expect(await jooby.balanceOf(liquidityProvider.address)).to.equal(MAXIMUM_JOOBY_TOKEN_SUPPLY.div(2).add(ONE_ETHER));
        // Transfer from zero address
        await expect(jooby.connect(zeroAddressSigner).transfer(owner.address, ONE_ETHER)).to.be.revertedWith("ZeroAddressEntry");
    });

    it("Successful _takeFee() execution", async () => {
        // Mint MAXIMUM_SUPPLY
        await jooby.mint(owner.address, MAXIMUM_JOOBY_TOKEN_SUPPLY.sub(ONE_ETHER));
        // Mint 1 to alice
        await jooby.mint(alice.address, ONE_ETHER);
        // Enable trading
        await jooby.addLiquidityPools([liquidityPool.address]);
        await jooby.addWhitelistedAccounts([bob.address]);
        await jooby.enableTrading();
        // +1 hour
        await time.increase(3600);
        // Transfer from alice to liquidity pool (1 ether)
        await jooby.connect(alice).approve(liquidityPool.address, ONE_ETHER);
        await jooby.connect(liquidityPool).transferFrom(alice.address, liquidityPool.address, ONE_ETHER);
        const percentageOfSalesCommission = await jooby.percentageOfSalesCommission();
        const basePercentage = await jooby.BASE_PERCENTAGE();
        expect(await jooby.balanceOf(alice.address)).to.equal(0);
        expect(await jooby.balanceOf(jooby.address)).to.equal(ONE_ETHER.mul(percentageOfSalesCommission).div(basePercentage));
        expect(await jooby.balanceOf(liquidityPool.address))
            .to.equal(ONE_ETHER.mul(basePercentage.sub(percentageOfSalesCommission)).div(await jooby.BASE_PERCENTAGE()));
        // Transfer from alice to liquidity pool (0 ether)
        await jooby.connect(liquidityPool).transferFrom(alice.address, liquidityPool.address, 0);
        // Attempt to claim from non granted to DEFAULT_ADMIN_ROLE address
        await expect(jooby.connect(liquidityProvider).withdrawAccumulatedCommission())
            .to.be.revertedWith(`AccessControl: account ${(liquidityProvider.address).toLowerCase()} is missing role ${ADMIN_ROLE}`);
        // Successful claim
        const balance = await jooby.balanceOf(jooby.address);
        await jooby.withdrawAccumulatedCommission();
        expect(await jooby.balanceOf(commissionRecipient.address)).to.equal(balance);
        // Claim again
        await jooby.withdrawAccumulatedCommission();
        expect(await jooby.balanceOf(commissionRecipient.address)).to.equal(balance);
    });
});