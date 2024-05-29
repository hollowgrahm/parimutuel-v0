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
    // Example: Array of user addresses to check
    const users = ['0xUserAddress1', '0xUserAddress2']; // Replace with actual user addresses

    for (const user of users) {
        await liquidateShort(user);
    }
}

// Looping function
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





// Start the bot
startBot().catch(err => console.error(err));




//create a bot or loop that itterates through DB 

//liquidate short
//liquidate long
//funcding rate long and funding rate short  

//have the database log the events for line 41-51


