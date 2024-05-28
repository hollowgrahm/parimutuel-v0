const Web3 = require('web3');
const fs = require('fs');
const dotenv = require('dotenv');

dotenv.config();

const contractABI = JSON.parse(fs.readFileSync('ParimutuelABI.json'));
const contractAddress = process.env.CONTRACT_ADDRESS;
const privateKey = process.env.PRIVATE_KEY;

const web3 = new Web3(new Web3.providers.HttpProvider(`https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`));
const account = web3.eth.accounts.privateKeyToAccount(privateKey);
web3.eth.accounts.wallet.add(account);
web3.eth.defaultAccount = account.address;

const contract = new web3.eth.Contract(contractABI, contractAddress);

async function getCurrentPrice() {
    const price = await contract.methods.currentPrice().call();
    console.log(`Current Price: ${price}`);
    return price;
}

async function deposit(amount) {
    const data = contract.methods.deposit(amount).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 200000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Deposit transaction hash: ${receipt.transactionHash}`);
}

async function withdraw(amount) {
    const data = contract.methods.withdraw(amount).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 200000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Withdraw transaction hash: ${receipt.transactionHash}`);
}

async function openShort(margin, leverage) {
    const data = contract.methods.openShort(margin, leverage).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 300000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Open short position transaction hash: ${receipt.transactionHash}`);
}

async function closeShort() {
    const data = contract.methods.closeShort().encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 200000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Close short position transaction hash: ${receipt.transactionHash}`);
}

async function openLong(margin, leverage) {
    const data = contract.methods.openLong(margin, leverage).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 300000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Open long position transaction hash: ${receipt.transactionHash}`);
}

async function closeLong() {
    const data = contract.methods.closeLong().encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 200000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Close long position transaction hash: ${receipt.transactionHash}`);
}

async function addMarginShort(user, amount) {
    const data = contract.methods.addMarginShort(user, amount).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 200000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Add margin to short position transaction hash: ${receipt.transactionHash}`);
}

async function addMarginLong(user, amount) {
    const data = contract.methods.addMarginLong(user, amount).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 200000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Add margin to long position transaction hash: ${receipt.transactionHash}`);
}

// Example usage:
(async () => {
    try {
        await getCurrentPrice();
        await deposit(web3.utils.toWei('1', 'ether')); // Example deposit of 1 ether
        await openShort(web3.utils.toWei('0.1', 'ether'), 2); // Example: Open a short position with 0.1 ether margin and 2x leverage
        await closeShort();
        await openLong(web3.utils.toWei('0.1', 'ether'), 2); // Example: Open a long position with 0.1 ether margin and 2x leverage
        await closeLong();
        await withdraw(web3.utils.toWei('0.1', 'ether')); // Example withdrawal of 0.1 ether
    } catch (error) {
        console.error(error);
    }
})();
