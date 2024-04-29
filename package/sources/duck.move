module goose_bumps::duck {
    use std::string;
    use std::ascii;

    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::url;
    use sui::clock::Clock;

    public struct DUCK has drop {}

    public struct DuckManager has key {
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
    } 

    #[allow(lint(share_owned))]
    fun init(
        otw: DUCK, 
        ctx: &mut TxContext
    ) {
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
        
        transfer::share_object(DuckManager {
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
        });
    }

    // TODO: admin only + guard
    // called only once
    entry fun init_duck_manager(
        manager: &mut DuckManager,
        clock: &Clock, 
        target_average_age: u64,
        adjustment_period_ms: u64,
        adjustment_mul: u64,
        min_accrual_param: u64,
    ) {
        manager.publish_timestamp = clock.timestamp_ms();
        manager.target_average_age = target_average_age;
        manager.adjustment_period_ms = adjustment_period_ms;
        manager.adjustment_mul = adjustment_mul;
        manager.min_accrual_param = min_accrual_param;
    }

    // === Friend functions ===

    public(package) fun supply(
        manager: &DuckManager
    ): u64 {
        manager.cap.total_supply()
    }

    public(package) fun cap(
        manager: &mut DuckManager
    ): &mut TreasuryCap<DUCK> {
        &mut manager.cap
    }

    public(package) fun mint(
        treasury_cap: &mut TreasuryCap<DUCK>, 
        amount: u64, ctx: &mut TxContext
    ): Coin<DUCK> {
        treasury_cap.mint(amount, ctx)
    }

    public(package) fun burn(
        treasury_cap: &mut TreasuryCap<DUCK>, 
        coin: Coin<DUCK>
    ) {
        treasury_cap.burn(coin);
    }

    public(package) fun current_period(manager: &DuckManager, clock: &Clock): u64 {
        let duration = clock.timestamp_ms() - manager.publish_timestamp;
        duration / manager.adjustment_period_ms
    }

    // === Admin only ===

    // TODO: add admin cap
    entry fun update_name(
        manager: &DuckManager, 
        metadata: &mut CoinMetadata<DUCK>, 
        name: string::String
    ) {
        manager.cap.update_name(metadata, name);
    }
    entry fun update_symbol(
        manager: &DuckManager, 
        metadata: &mut CoinMetadata<DUCK>, 
        name: ascii::String
    ) {
        manager.cap.update_symbol(metadata, name);
    }
    entry fun update_description(
        manager: &DuckManager, 
        metadata: &mut CoinMetadata<DUCK>, 
        name: string::String
    ) {
        manager.cap.update_description(metadata, name);
    }
    entry fun update_icon_url(
        manager: &DuckManager, 
        metadata: &mut CoinMetadata<DUCK>, 
        name: ascii::String
    ) {
        manager.cap.update_icon_url(metadata, name);
    }

    // === Test functions ===

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
    ) {
        init_duck_manager(
            manager,
            clock,
            target_average_age,
            adjustment_period_ms,
            adjustment_mul,
            min_accrual_param,
        );
    }
}
