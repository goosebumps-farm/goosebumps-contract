// TBD if useful for emergency 
module goose_bumps::admin { 
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};

    // TODO: group all cap objects under shared Manager object

    struct AdminCap has key, store {
        id: UID
    }

    #[allow(unused_function)]
    fun init(ctx: &mut TxContext) {
        transfer::transfer(
            AdminCap { id: object::new(ctx) },
            tx_context::sender(ctx)
        );
    }
}