#[test_only]
module goose_bumps::goose_tests {
    use std::string;

    use sui::test_scenario as ts;
    use sui::transfer;

    use goose_bumps::goose::{init_for_testing, create, update, destroy, name, status, Goose};

    #[test]
    fun test_nft_module(){


        // Create test addresses representing users that transfer the Goose NFT
        let admin = @0xBABE;
        let initial_owner = @0xCAFE;
        let final_owner = @0xFACE;

        // Module initialization for emulating transactions
        let scenario_val = ts::begin(admin);
        let scenario = &mut scenario_val;
        {
            init_for_testing(ts::ctx(scenario));
        };

        // Test create() function called by admin
        ts::next_tx(scenario, admin);
        {
            // Perform create of goose with defined values
            let goose_nft = create(
                b"Bonding",
                b"hi-res",
                b"lo-res",
                1,
                ts::ctx(scenario)
            );

            // Check if the name and status match with initial ones
            assert!(name(&goose_nft) == string::utf8(b"Bonding") && status(&goose_nft) == 1, 0);

            // Transfer goose_nft to further owner ( initial_owner )
            transfer::public_transfer(goose_nft, initial_owner);
        };

        // Test update() function called by initial owner
        ts::next_tx(scenario, initial_owner);
        {
            // Get the goose owned by initial owner
            let goose_nft = ts::take_from_sender<Goose>(scenario);

            // Perform the update of the goose with new values
            update(
                &mut goose_nft,
                b"Updated Goose",
                b"updated_image",
                b"updated_thumbnail",
                3,
                ts::ctx(scenario)
            );

            // Check if updated name and status match with updated ones
            assert!(name(&goose_nft) == string::utf8(b"Updated Goose") && status(&goose_nft) == 3, 1);

            // Transfer goose_nft to further owner ( final_owner )
            transfer::public_transfer(goose_nft, final_owner);
        };

        // Test destroy() function called by final owner
        ts::next_tx(scenario, final_owner);
        {
            // Get the goose owned by final owner
            let goose_nft = ts::take_from_sender<Goose>(scenario);

            // Perform the destroy of goose nft object
            destroy(goose_nft);
            
            // Check if the goose_nft is not anymore in final owner custody

        };
        // End test session
        ts::end(scenario_val);
    }
}