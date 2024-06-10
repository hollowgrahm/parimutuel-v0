const Web3 = require('web3');
const { toWei } = Web3.utils;

// Replace with your Infura endpoint or another Ethereum node provider
const web3 = new Web3(new Web3.providers.HttpProvider('https://holesky.infura.io/v3/23c1944e453c48bca5112adab0cfc908'));

// Replace with your Ethereum wallet private key
const privateKey = 'bd30facbb8b2c18ae580572c97c223bbb2c356cda7a7724051f86d52953f2571';

// Replace with your Ethereum wallet address
const senderAddress = '0x8DF8654Fcd1CfC82d24bBa8e2C60d53AbF6Ac1C3';

// List of recipient smart contract addresses
const contractAddresses = [
    '0xB9cc6EE2240178Cf08837a310e3735B7A289A87C',
    // Add more addresses as needed


];

const transferETH = async (recipient, amountInEth) => {
    const amountInWei = toWei(amountInEth, 'ether');

    const tx = {
        from: senderAddress,
        to: recipient,
        value: amountInWei,
        gas: 21000,
        gasPrice: await web3.eth.getGasPrice()
    };

    const signedTx = await web3.eth.accounts.signTransaction(tx, privateKey);
    const receipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

    console.log(`Transaction to ${recipient} completed: `, receipt.transactionHash);
};

const main = async () => {
    for (const address of contractAddresses) {
        await transferETH(address, '0.01'); // Replace '0.1' with the desired amount of ETH to transfer
    }
    console.log('All transactions completed.');
};

main().catch(console.error);
