const Web3 = require('web3');
const fs = require('fs');
const dotenv = require('dotenv');
const mongoose = require('mongoose');
const Event = require('./models/Event');

dotenv.config();

const contractABI = JSON.parse(fs.readFileSync('ParimutuelABI.json'));
const contractAddress = process.env.CONTRACT_ADDRESS;
const privateKey = process.env.PRIVATE_KEY;

const web3 = new Web3(new Web3.providers.HttpProvider(`https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`));
const account = web3.eth.accounts.privateKeyToAccount(privateKey);
web3.eth.accounts.wallet.add(account);
web3.eth.defaultAccount = account.address;

const contract = new web3.eth.Contract(contractABI, contractAddress);

// MongoDB connection
mongoose.connect(process.env.MONGO_URI, {
    useNewUrlParser: true,
    useUnifiedTopology: true
}).then(() => console.log('MongoDB connected'))
  .catch(err => console.log(err));

//liquidate short position
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

        // Record the event in the database
        const event = new Event({
            user: user,
            transactionHash: receipt.transactionHash,
        });
        await event.save();

    } catch (error) {
        console.error(`Error liquidating short position for user ${user}: ${error.message}`);
    }
}

async function checkAndLiquidate() {
    // Array of user addresses to check
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

const eventSchema = new mongoose.Schema({
    user: String,
    transactionHash: String,
    eventType: String,
    timestamp: { type: Date, default: Date.now },
});

module.exports = mongoose.model('Event', eventSchema);





// Starts  bot
startBot().catch(err => console.error(err));




//create a bot or loop that itterates through DB 

//liquidate short
//liquidate long
//funding rate long and funding rate short  

//have the database log the events for line 41-51
//anyone should be able to call a function 



// Example usage
(async () => {
    const userAddress = '0xYourUserAddressHere'; // Replace with the actual user address
    await liquidateShort(userAddress);
    await liquidateLong(userAddress);
    await fundingRateShort(userAddress);
    await fundingRateLong(userAddress);
})();