const Web3 = require('web3');
const fs = require('fs');
const dotenv = require('dotenv');
const Moralis = require('moralis').default;

dotenv.config();

const contractABI = JSON.parse(fs.readFileSync('ParimutuelABI.json'));
const contractAddress = process.env.CONTRACT_ADDRESS;
const privateKey = process.env.PRIVATE_KEY;

const web3 = new Web3(new Web3.providers.HttpProvider(`https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`));
const account = web3.eth.accounts.privateKeyToAccount(privateKey);
web3.eth.accounts.wallet.add(account);
web3.eth.defaultAccount = account.address;

const contract = new web3.eth.Contract(contractABI, contractAddress);

// Initialize Moralis
const serverUrl = process.env.MORALIS_SERVER_URL;
const appId = process.env.MORALIS_APP_ID;
Moralis.start({ serverUrl, appId });

// Function to record event
async function recordEvent(user, transactionHash, eventType) {
    const Event = Moralis.Object.extend("Event");
    const event = new Event();
    event.set("user", user);
    event.set("transactionHash", transactionHash);
    event.set("eventType", eventType);
    await event.save();
}

// Liquidate short position
async function liquidateShort(user) {
    try {
        const data = contract.methods.liquidateShort(user).encodeABI();

        const tx = {
            to: contractAddress,
            data,
            gas: 200000,
        };

        const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
        const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

        console.log(`Liquidate short position transaction hash: ${receipt.transactionHash}`);
        await recordEvent(user, receipt.transactionHash, 'ShortLiquidation');
    } catch (error) {
        console.error(`Error liquidating short position for user ${user}: ${error.message}`);
    }
}

// Check and liquidate function
async function checkAndLiquidate() {
    const users = ['0xUserAddress1', '0xUserAddress2']; // Replace with actual user addresses
    for (const user of users) {
        await liquidateShort(user);
    }
}

// Function to liquidate long position
async function liquidateLong(user) {
    try {
        const data = contract.methods.liquidateLong(user).encodeABI();

        const tx = {
            to: contractAddress,
            data,
            gas: 200000,
        };

        const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
        const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

        console.log(`Liquidate long position transaction hash: ${receipt.transactionHash}`);
        await recordEvent(user, receipt.transactionHash, 'LongLiquidation');
    } catch (error) {
        console.error(`Error liquidating long position for user ${user}: ${error.message}`);
    }
}

// Function to update funding rate for short position
async function fundingRateShort(user) {
    try {
        const data = contract.methods.fundingRateShort(user).encodeABI();

        const tx = {
            to: contractAddress,
            data,
            gas: 200000,
        };

        const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
        const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

        console.log(`Funding rate short position transaction hash: ${receipt.transactionHash}`);
        await recordEvent(user, receipt.transactionHash, 'ShortFundingRate');
    } catch (error) {
        console.error(`Error updating funding rate for short position for user ${user}: ${error.message}`);
    }
}

// Function to update funding rate for long position
async function fundingRateLong(user) {
    try {
        const data = contract.methods.fundingRateLong(user).encodeABI();

        const tx = {
            to: contractAddress,
            data,
            gas: 200000,
        };

        const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
        const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

        console.log(`Funding rate long position transaction hash: ${receipt.transactionHash}`);
        await recordEvent(user, receipt.transactionHash, 'LongFundingRate');
    } catch (error) {
        console.error(`Error updating funding rate for long position for user ${user}: ${error.message}`);
    }
}

// Loop function
async function startBot() {
    while (true) {
        await checkAndLiquidate();
        await new Promise(resolve => setTimeout(resolve, 60000)); // Wait for 1 minute before next loop
    }
}

// Starts bot
startBot().catch(err => console.error(err));

// Example usage
(async () => {
    const userAddress = '0xYourUserAddressHere'; // Replace with the actual user address
    await liquidateShort(userAddress);
    await liquidateLong(userAddress);
    await fundingRateShort(userAddress);
    await fundingRateLong(userAddress);
})();
