import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
	try {
		console.log("calling...")

		const tx = new TransactionBlock();

		const [buck] = tx.splitCoins(
			tx.object("0x4a3f6a03bc26a2f883452029c81174e63858e74924235008074b6bbd196b8bbf"), 
			[1]
		);
		
		tx.moveCall({
			target: `${getId("package")}::bucket_tank::init_strategy`,
			arguments: [
				tx.object(getId("pond::Pond")),
				tx.object("0xc172d7d94db7bbf88662e8cd8b48d2641b98a810b34ff808d84f4e88bd65bdc4"), // protocol
				buck
			],
			typeArguments: [],
		});

		tx.setGasBudget(100000000);

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