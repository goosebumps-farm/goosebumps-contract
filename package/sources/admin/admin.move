// TBD if useful for emergency 
module goose_bumps::admin {

    // TODO: group all cap objects under shared Manager object

    public struct AdminCap has key, store {
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