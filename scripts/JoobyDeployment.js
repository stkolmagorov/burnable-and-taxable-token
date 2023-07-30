const { ethers } = require("hardhat");

async function main() {
    const commissionRecipient = undefined;
    const liquidityProvider = undefined;
    const Jooby = await ethers.getContractFactory("Jooby");
    const jooby = await Jooby.deploy(commissionRecipient, liquidityProvider);
    console.log("Address: ", jooby.address);
}
  
main().catch((error) => {
    console.error(error);
    process.exit(1);
});