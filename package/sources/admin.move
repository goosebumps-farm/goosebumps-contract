module goose_bumps::admin {
    // cap should be transferred to the Multisig

    public struct AdminCap has key, store { id: UID }

    fun init(ctx: &mut TxContext) {
        transfer::public_transfer(
            AdminCap { id: object::new(ctx) },
            ctx.sender(),
        )
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}

