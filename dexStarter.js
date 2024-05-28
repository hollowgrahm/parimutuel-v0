const Web3 = require('web3');
const contractABI = require('./ParimutuelPerpetualsABI.json');
const contractAddress = '0xYourContractAddressHere';

const web3 = new Web3(new Web3.providers.HttpProvider('https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID'));// mainnet configuration

const contract = new web3.eth.Contract(contractABI, contractAddress);

const account = '0xYourEthereumAddressHere'; // User Ethereum address
const privateKey = '0xYourPrivateKeyHere'; // User private key

async function getPrice() {
    const price = await contract.methods.getPrice().call();
    console.log(`Current Price: ${price}`);
    return price;
}

async function openPosition(margin, leverage) {
    const data = contract.methods.openPosition(margin, leverage).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 2000000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Position opened: ${receipt.transactionHash}`);
}

async function closePosition() {
    const data = contract.methods.closePosition().encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 2000000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Position closed: ${receipt.transactionHash}`);
}

async function liquidate(userAddress) {
    const data = contract.methods.liquidate(userAddress).encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 2000000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`User liquidated: ${receipt.transactionHash}`);
}

async function applyFundingRate() {
    const data = contract.methods.applyFundingRate().encodeABI();

    const tx = {
        to: contractAddress,
        data,
        gas: 2000000,
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Funding rate applied: ${receipt.transactionHash}`);
}

// Example usage:
(async () => {
    try {
        await getPrice();
        await openPosition(100, 2); // Example: Open a position with 100 margin and 2x leverage
        await closePosition();
        await liquidate('0xAnotherUserAddressHere'); // Example: Liquidate another user's position
        await applyFundingRate();
    } catch (error) {
        console.error(error);
    }
})();
