const solanaJSON = require('./solana-consensus.js');

(async() => {
		console.log('deploying...');
		const connection = solanaJSON.setupConnection('https://testnet.solana.com');
		const payerAccount = await solanaJSON.createUser();
		await solanaJSON.fundUser(connection,payerAccount);
		const smartContract = {
			pathToProgram: './solana-consensus.so',
			dataLayout: solanaJSON.setDataStructure(1000),
		}
		const app = await solanaJSON.loadProgram(connection,smartContract,payerAccount);
		console.log('app',app);
		const confirmationTicket = await solanaJSON.pushJSON(connection,app,'{"validators":["0x04Fec2d572497397007FD96E431156698F3abb14","0x2F41ad391A5BC0E994CcB6ccbfCfF67b9D9515AC"]}');
		const testJSON = solanaJSON.pullJSON(connection,app.appAccount.publicKey);
		console.log(`Test: ${JSON.parse(testJSON).abc}`);
})();