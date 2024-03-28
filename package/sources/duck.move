module goose_bumps::duck {
    use std::option;
    use std::string;
    use std::ascii;

    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url;
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};

    use goose_bumps::math64;

    friend goose_bumps::pond;

    const EDUCK_INIT_ALREADY_CALLED: u64 = 0;
    const EINVALID_ADMIN: u64 = 1;

    struct DUCK has drop {}

    struct DuckManager has key {
        id: UID,
        cap: TreasuryCap<DUCK>,
        reserve: u64,
        publish_timestamp: u64,
        average_start_time: u64,
        target_average_age: u64,
        adjustment_period_ms: u64,
        last_period_adjusted: u64,
        adjustment_mul: u64,
        min_accrual_param: u64,
        accrual_param: u64,
        initialized: bool,
    }

    fun init(otw: DUCK, ctx: &mut TxContext) {
        assert!(!exists<DuckManager>(ctx), EDUCK_INIT_ALREADY_CALLED);

        let (cap, metadata) = coin::create_currency<DUCK>(
            otw,
            9,
            b"DUCK",
            b"Duck",
            b"BUCK with a boosted yield that gives you goose bumps",
            option::some(url::new_unsafe_from_bytes(b"https://twitter.com/goosebumps_farm/photo")),
            ctx
        );

        transfer::public_share_object(metadata);

        transfer::share_object(
            DuckManager {
                id: object::new(ctx),
                cap,
                reserve: 0,
                publish_timestamp: 0,
                average_start_time: 0,
                target_average_age: 0,
                adjustment_period_ms: 0,
                last_period_adjusted: 0,
                adjustment_mul: 0,
                min_accrual_param: 0,
                accrual_param: 0,
                initialized: false,
            }
        );
    }

    entry fun init_duck_manager(
        manager: &mut DuckManager,
        clock: &Clock,
        target_average_age: u64,
        adjustment_period_ms: u64,
        adjustment_mul: u64,
        min_accrual_param: u64,
        admin: &address,
    ) {
        assert!(!manager.initialized, EDUCK_INIT_ALREADY_CALLED);
        assert!(tx_context::sender() == @admin, EINVALID_ADMIN);

        manager.publish_timestamp = clock::timestamp_ms(clock);
        manager.target_average_age = target_average_age;
        manager.adjustment_period_ms = adjustment_period_ms;
        manager.adjustment_mul = adjustment_mul;
        manager.min_accrual_param = min_accrual_param;
        manager.initialized = true;
    }

    public(friend) fun supply(manager: &DuckManager): u64 {
        coin::total_supply(&manager.cap)
    }

    public(friend) fun cap(manager: &mut DuckManager): &mut TreasuryCap<DUCK> {
        &mut manager.cap
    }

    public(friend) fun mint(
        treasury_cap: &mut TreasuryCap<DUCK>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<DUCK> {
        coin::mint(treasury_cap, amount, ctx)
    }

    public(friend) fun burn(treasury_cap: &mut TreasuryCap<DUCK>, coin: Coin<DUCK>) {
        coin::burn(treasury_cap, coin);
    }

    public(friend) fun current_period(manager: &DuckManager, clock: &Clock): u64 {
        let duration = clock::timestamp_ms(clock) - manager.publish_timestamp;
        duration / manager.adjustment_period_ms
    }

    public(friend) fun handle_accrual_param(manager: &mut DuckManager, clock: &Clock): u64 {
        if (manager.accrual_param == manager.min_accrual_param) return manager.accrual_param;

        let current_period = current_period(manager, clock);
        if (current_period > manager.last_period_adjusted) {
            let target_adjustment_period = math64::div_up(
                manager.average_start_time + manager.target_average_age - manager.publish_timestamp,
                manager.adjustment_period_ms
            );
            if (current_period < target_adjustment_period) return manager.accrual_param;
            let adjustments = current_period - target_adjustment_period;
            let adjusted_accrual_param = manager.accrual_param * math64::pow(manager.adjustment_mul, adjustments);
            if (adjusted_accrual_param > manager.min_accrual_param) {
                manager.accrual_param = adjusted_accrual_param;
            };
        };

        manager.last_period_adjusted = current_period;
        manager.accrual_param
    }

    entry fun update_name(
        manager: &mut DuckManager,
        metadata: &mut CoinMetadata<DUCK>,
        name: string::String,
        admin: &address,
    ) {
        assert!(tx_context::sender() == @admin, EINVALID_ADMIN);
        coin::update_name(&mut manager.cap, metadata, name);
    }

    entry fun update_symbol(
        manager: &mut DuckManager,
        metadata: &mut CoinMetadata<DUCK>,
        symbol: ascii::String,
        admin: &address,
    ) {
        assert!(tx_context::sender() == @admin, EINVALID_ADMIN);
        coin::update_symbol(&mut manager.cap, metadata, symbol);
    }

    entry fun update_description(
        manager: &mut DuckManager,
        metadata: &mut CoinMetadata<DUCK>,
        description: string::String,
        admin: &address,
    ) {
        assert!(tx_context::sender() == @admin, EINVALID_ADMIN);
        coin::update_description(&mut manager.cap, metadata, description);
    }

    entry fun update_icon_url(
        manager: &mut DuckManager,
        metadata: &mut CoinMetadata<DUCK>,
        icon_url: ascii::String,
        admin: &address,
    ) {
        assert!(tx_context::sender() == @admin, EINVALID_ADMIN);
        coin::update_icon_url(&mut manager.cap, metadata, icon_url);
    }

    #[test_only]
    friend goose_bumps::bucket_tank_tests;

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(DUCK {}, ctx);
    }

    #[test_only]
    public fun init_manager_for_testing(
        manager: &mut DuckManager,
        clock: &Clock,
        target_average_age: u64,
        adjustment_period_ms: u64,
        adjustment_mul: u64,
        min_accrual_param: u64,
        admin: &address,
    ) {
        init_duck_manager(
            manager,
            clock,
            target_average_age,
            adjustment_period_ms,
            adjustment_mul,
            min_accrual_param,
            admin,
        );
    }
}