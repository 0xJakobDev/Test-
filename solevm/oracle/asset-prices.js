const fetch = require('node-fetch');
const Web3 = require('web3');
const experimentalABI = require('./abis/experimentalABI.json');
const credentials = require('./credentials.json');

const web3 = new Web3(`https://kovan.infura.io/v3/${credentials.infuraKey}`);

const privateKey = credentials.privateKey;
const activeAccount = web3.eth.accounts.privateKeyToAccount(privateKey);

const contractAddress = '0xc8a6b771485BE49BF6898472168ae8f26377d0bA3'; 

const contract = new web3.eth.Contract(experimentalABI, contractAddress);

const marketData = {};

const round = (num,decimals=8,down=false) => {
	if (typeof num !== 'number') num = parseFloat(num);
	const multiplier = 10 ** decimals;
	let roundedNumber = Math.round(num * multiplier) / multiplier;
	if (down) roundedNumber = Math.floor(num * multiplier) / multiplier;
	return Number(roundedNumber);
}

const updatePrices = async () => {
	const res1Promise = fetch(`https://api.binance.com/api/v3/ticker/24hr`).catch(err => utils.errorLog(err));
	const res1 = await res1Promise;
	const json = await res1.json().catch(err => utils.errorLog(err));
	if (!json) return false;
	const marketData = [];
	json.forEach((coinData) => {
		if (!coinData.symbol || coinData.symbol.substr(coinData.symbol.length - 4) !== 'USDT') return false;
		if (!coinData.symbol.substr(0,3) === 'BTC' && !coinData.symbol.substr(0,3) === 'ETH' && !coinData.symbol.substr(0,3) === 'SOL') return false;
		const sym = coinData.symbol.split('USDT').join('');
		const price = round(coinData.lastPrice);
		marketData.push([sym,price]);
	});
	oracleService(marketData);
	return false;
}

const signAndSend = async (tx_builder,sendToAddress) => {
	let encoded_tx = tx_builder.encodeABI();
	let transactionObject = {
		gas: 6000000,
		data: encoded_tx,
		from: activeAccount.address,
		to: sendToAddress,
	};
	web3.eth.accounts.signTransaction(transactionObject, activeAccount.privateKey, (error, signedTx) => {
		if (error) {
			console.log(error);
		} else {
			web3.eth.sendSignedTransaction(signedTx.rawTransaction).on('receipt', (receipt) => {
				console.log(receipt);
			});
		}
	});
}

const oracleService = async (marketData) => {
	let txRaw = contract.methods.updatePrices(marketData);
	signAndSend(txRaw,contractAddress);
}

updatePrices();