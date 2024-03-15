import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
	try {
		console.log("calling...")

		const tx = new TransactionBlock();

		const [coin] = tx.splitCoins(tx.object("coinId"), [10]);

		tx.transferObjects([coin], "0xdc2dbdf749bcf228a97339020607110baf45248ccc3e7671edd3e3c866a75717");

		tx.setGasBudget(10000000);

		const result = await client.signAndExecuteTransactionBlock({
			signer: keypair,
			transactionBlock: tx,
			options: {
				showObjectChanges: true,
				showEffects: true,
			},
			requestType: "WaitForLocalExecution"
		});

		console.log("result: ", JSON.stringify(result.objectChanges, null, 2));
		console.log("status: ", JSON.stringify(result.effects?.status, null, 2));

	} catch (e) {
		console.log(e)
	}
})()