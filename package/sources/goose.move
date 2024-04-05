module goose_bumps::goose {
    use std::string::{utf8, String};
    
    use sui::object::{Self, ID, UID};
    use sui::event;
    use sui::transfer;
    use sui::display;
    use sui::package;
    use sui::tx_context::{Self, TxContext};

    friend goose_bumps::pond;
    
    // === Structs ===

    struct Goose has key, store {
        id: UID,
        // standard fields minus display
        name: String,
        image_url: String,
        thumbnail_url: String,
        // bonding status : 1 (bonding), 2 (goose dumps), 3 (goose bumps)
        status: u8,
    }

    // ==== Events ====

    struct GooseMinted has copy, drop {
        // The Object ID of the NFT
        id: ID,
        // The owner of the NFT
        owner: address,
    }

    struct GooseUpdated has copy, drop {
        // The Object ID of the NFT
        id: ID,
        // The owner of the NFT
        owner: address,
        // The status of the bonded NFT
        status: u8,
    }

    struct GOOSE has drop {}

    // ===== Init =====

    fun init(otw: GOOSE, ctx: &mut TxContext) {
        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url"),
            utf8(b"thumbnail_url"),
            utf8(b"project_url"),
        ];

        let values = vector[
            utf8(b"{name}"),
            utf8(b"a cool goose out of the pond"),
            utf8(b"ipfs://{image_url}"),
            utf8(b"ipfs://{thumbnail_url}"),
            utf8(b"https://goosebumps.farm"),
        ];

        let publisher = package::claim(otw, ctx);

        let display = display::new_with_fields<Goose>(
            &publisher, keys, values, ctx
        );

        display::update_version(&mut display);

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));
    }

    // ===== Public view functions =====

    public fun status(self: &Goose): u8 {
        self.status
    }

    // === Public-Friend Functions ===

    public(friend) fun create(
        name: vector<u8>,
        image_url: vector<u8>,
        thumbnail_url: vector<u8>,
        status: u8,
        ctx: &mut TxContext
    ): Goose {
        let nft = Goose {
            id: object::new(ctx),
            name: utf8(name),
            image_url: utf8(image_url),
            thumbnail_url: utf8(thumbnail_url),
            status,
        };

        event::emit(GooseMinted {
            id: object::id(&nft),
            owner: tx_context::sender(ctx),
        });

        nft
    }

    public(friend) fun update(
        self: &mut Goose,
        name: vector<u8>,
        image_url: vector<u8>,
        thumbnail_url: vector<u8>,
        status: u8,
        ctx: &mut TxContext
    ) {
        self.name = utf8(name);
        self.image_url = utf8(image_url);
        self.thumbnail_url = utf8(thumbnail_url);
        self.status = status;

        event::emit(GooseUpdated {
            id: object::id(self),
            owner: tx_context::sender(ctx),
            status,
        });
    }

    public(friend) fun destroy(nft: Goose) {
        object::delete(nft.id); // Simplified destructuring
    }

    public(friend) fun uid_mut(self: &mut Goose): &mut UID {
        &mut self.id
    }
    
    // === Test Functions ===

    #[test_only]
    friend goose_bumps::goose_tests;

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(GOOSE {}, ctx);
    }    
    
    #[test_only]
    public fun name(goose: &Goose): String {
        goose.name
    }

    // Additional functionality:
    // - Added a destroy function to delete a Goose object.
    // - Simplified destructuring in the destroy function.
    // - Added a uid_mut function to get a mutable reference to the UID of a Goose object.
    // - Improved consistency and readability of variable names.
    // - Removed redundant comments and redundant variables in the init function.
}
