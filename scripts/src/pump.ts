import { TransactionBlock } from '@mysten/sui.js/transactions';
import { client, keypair, getId } from './utils.js';

(async () => {
	try {
		console.log("calling...")

		const tx = new TransactionBlock();

		const packageId = getId("package");
		
		const [comp_req] = tx.moveCall({
			target: `${packageId}::pond::request_compound`,
			arguments: [],
			typeArguments: [],
		});
		
		tx.moveCall({
			target: `0x06dec2d93d91558ef917053673762e44fafac9c999fdeea29b5e6105ad7df246::bucket_oracle::update_price`,
			arguments: [
				tx.object("0xf6db6a423e8a2b7dea38f57c250a85235f286ffd9b242157eff7a4494dffc119"),
				tx.object("0x0000000000000000000000000000000000000000000000000000000000000006"),
				tx.object("0x84d2b7e435d6e6a5b137bf6f78f34b2c5515ae61cd8591d5ff6cd121a21aa6b7"),
				tx.object("0x090d740655461e285affa1654971c4e87064c31f672dda282c61df257c8c1ec0"),
				tx.pure(90),
			],
			typeArguments: [
				"0x2::sui::SUI"
			],
		});
		
		tx.moveCall({
			target: `${packageId}::bucket_tank::compound`,
			arguments: [
				tx.object(getId("pond::Pond")),
				comp_req,
				tx.object("0xc172d7d94db7bbf88662e8cd8b48d2641b98a810b34ff808d84f4e88bd65bdc4"), // protocol
				tx.object("0xf6db6a423e8a2b7dea38f57c250a85235f286ffd9b242157eff7a4494dffc119"), // oracle
				tx.object("0x392ae71b0aa00c3c00a43c4e854b605d4b97de586efbcffb6ccbcbd740ec7964"), // treasury
				tx.object("0x0000000000000000000000000000000000000000000000000000000000000006"),
			],
			typeArguments: [],
		});
		
		const [duck] = tx.moveCall({
			target: `${packageId}::pond::pump`,
			arguments: [
				tx.object("0x8b4ec24712fb1139a6107a4819b7bd7b336664a7273d3895e5149c343648c367"),
				comp_req,
				tx.object(getId("pond::Pond")),
				tx.object(getId("duck::DuckManager")),
				tx.object("0x0000000000000000000000000000000000000000000000000000000000000006"),
			],
			typeArguments: [],
		});

		tx.transferObjects([duck], keypair.getPublicKey().toSuiAddress());

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