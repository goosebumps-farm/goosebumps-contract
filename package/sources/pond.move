module goose_bumps::pond {
    // === Imports ===
    use std::debug::print;
    use std::type_name::{Self, TypeName};
    use std::vector;
    use std::ascii::{Self, String};

    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Supply, Balance};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::tx_context::TxContext;
    use sui::vec_set::{Self, VecSet};
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;

    use bucket_protocol::buck::BUCK;

    use goose_bumps::math64;
    use goose_bumps::vec_map::{Self, VecMap};
    use goose_bumps::goose::{Self, Goose};
    use goose_bumps::duck::{Self, DuckManager, DUCK};
    use goose_bumps::admin::AdminCap;

    // === Constants ===

    const VERSION: u64 = 1;

    const PUMP_FEE: u64 = 50_000_000; // 5%
    const MUL: u64 = 1_000_000_000; // scaling factor

    // === Errors ===

    const ENotBuck: u64 = 0;
    const EDifferentPackage: u64 = 1;
    const EStrategyAlreadyImplemented: u64 = 2;
    const EStrategyDoesntExist: u64 = 3;
    const EPositionAlreadyStored: u64 = 4;
    const EPositionDoesntExist: u64 = 5;
    const ERequestDoesntMatch: u64 = 6;
    const ENotEgg: u64 = 7;
    const EZeroCoin: u64 = 8;

    // === Structs ===

    // helper to get package id
    struct Package has copy, drop, store {}
    // key to add the pending ContributorToken as a DOF
    struct PositionKey has drop, copy, store {}
    // key to add the pond struct as a DF to nft
    struct DepositKey has drop, copy, store {}

    struct Deposit has store {
        amount: u64,
        timestamp: u64,
    }

    // hot potato
    struct DepositRequest {
        // deposit amount (immutable)
        amount: u64,
        // user deposit
        balance: Balance<BUCK>,
    }

    // hot potato
    struct WithdrawalRequest {
        // previous user deposit
        amount: u64,
        // returned balance
        balance: Balance<BUCK>,
    }

    // hot potato
    struct CompoundRequest {
        // total buck amount managed by the protocol
        total_buck: u64,
        // modules that have been called
        receipts: VecSet<String>,
    }

    struct Pond has key {
        id: UID,
        version: u64,
        // pending or bonding amount 
        pending: u64,
        // redeemable supply
        reserve: u64,
        // protocol owned liquidity
        permanent: u64,
        // team owned funds
        treasury: u64,
        // total of all strategies shares
        total_shares: u64,
        // protocols data 
        strategies: VecMap<String, Strategy>,
    }

    struct Strategy has key, store {
        id: UID,
        // shares of funds that should be directed to this protocol
        shares: u64,
        // current amount of BUCK held by this protocol
        amount: u64,
        // DOF: LP token or Receipt (position)
    }


    fun init(ctx: &mut TxContext) {
        // init pond
        transfer::share_object(
            Pond {
                id: object::new(ctx),
                version: 1,
                pending: 0,
                reserve: 0,
                permanent: 0,
                treasury: 0,
                total_shares: 0,
                strategies: vec_map::empty(),
            }
        );
    }

    // === Public-View Functions ===

    // === Public-Mutative Functions ===

    // create egg: init request
    public fun request_bump(
        coin: Coin<BUCK>
    ): (CompoundRequest, DepositRequest) {
        let amount = coin::value(&coin); 
        assert!(amount > 0, EZeroCoin);
        let balance = coin::into_balance(coin);

        (
            CompoundRequest { total_buck: 0, receipts: vec_set::empty() },
            DepositRequest { amount, balance }
        )
    }

    // create egg: validate request
    public fun bump(
        clock: &Clock, 
        comp_req: CompoundRequest, 
        dep_req: DepositRequest, 
        pond: &mut Pond,
        ctx: &mut TxContext,
    ): Goose {
        let CompoundRequest { total_buck: _, receipts } = comp_req;
        let DepositRequest { amount, balance } = dep_req;
        
        pond.pending = pond.pending + amount;

        let nft = goose::create(
            b"Egg",
            b"hi-res",
            b"lo-res",
            1,
            ctx,
        );
        // add egg info
        df::add(
            goose::uid_mut(&mut nft), 
            DepositKey {}, 
            Deposit { amount, timestamp: clock::timestamp_ms(clock) }
        );

        balance::destroy_zero(balance);

        assert_receipts_match(pond, &receipts);

        nft
    }

    // dump egg: init request
    public fun request_dump(
        nft: &mut Goose, 
        ctx: &mut TxContext
    ): (CompoundRequest, WithdrawalRequest) {
        assert!(goose::status(nft) == 1, ENotEgg);
        
        let Deposit { amount, timestamp: _ } = df::remove(goose::uid_mut(nft), DepositKey {});
        
        goose::update(
            nft,
            b"Dumped Goose",
            b"goose_dumps_hi_res",
            b"goose_dumps_lo_res",
            2,
            ctx,
        );

        (
            CompoundRequest { total_buck: 0, receipts: vec_set::empty() },
            WithdrawalRequest { amount, balance: balance::zero() }
        )
    }

    // dump goose: validate request
    public fun dump(
        comp_req: CompoundRequest, 
        wit_req: WithdrawalRequest, 
        pond: &mut Pond, 
        ctx: &mut TxContext
    ): Coin<BUCK> {
        let CompoundRequest { total_buck: _, receipts } = comp_req;
        let WithdrawalRequest { amount, balance } = wit_req;
        
        pond.pending = pond.pending - amount;
        assert_receipts_match(pond, &receipts);

        coin::from_balance(balance, ctx)
    }
        
    // pump goose: init request
    public fun request_compound(): CompoundRequest {
        CompoundRequest { total_buck: 0, receipts: vec_set::empty() }
    }

    // pump goose: validate request
    public fun pump(
        nft: &mut Goose, 
        comp_req: CompoundRequest,
        pond: &mut Pond, 
        manager: &mut DuckManager, 
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<DUCK> {
        assert!(goose::status(nft) == 1, ENotEgg);
        
        let Deposit { amount, timestamp } = df::remove(goose::uid_mut(nft), DepositKey {});
        
        goose::update(
            nft,
            b"Pumped Goose",
            b"goose_bumps_hi_res",
            b"goose_bumps_lo_res",
            3,
            ctx,
        );

        let CompoundRequest { total_buck, receipts } = comp_req;     
        compound_buckets(pond, total_buck);
        // TODO: test accrual_param
        // let accrual_param = duck::handle_accrual_param(manager, clock);
        let accrual_param = 1000000;

        let fee = amount * PUMP_FEE / MUL;
        let treasury_amount = fee / 10;
        let permanent_amount = fee - treasury_amount;
        let user_amount = amount - fee;

        let egg_age = (clock::timestamp_ms(clock) - timestamp) * MUL;
        let ratio = reserve_buck_supply_duck_ratio(pond, manager);
        let accrued_duck = MUL * math64::mul_div_down(
            user_amount, 
            egg_age, 
            (egg_age + accrual_param)
        ) / ratio;

        assert_receipts_match(pond, &receipts);

        pond.pending = pond.pending - amount;   
        pond.reserve = pond.reserve + user_amount;
        pond.permanent = pond.permanent + permanent_amount;
        pond.treasury = pond.treasury + treasury_amount;
        duck::mint(duck::cap(manager), accrued_duck, ctx)
    }
    
    // need to call request_compound first
    // redeem duck: compound to get ratio
    public fun request_redeem(
        coin: Coin<DUCK>, 
        comp_req: CompoundRequest,
        pond: &mut Pond, 
        manager: &mut DuckManager, 
    ): (CompoundRequest, WithdrawalRequest) {
        let CompoundRequest { total_buck, receipts } = comp_req;
        assert_receipts_match(pond, &receipts);

        compound_buckets(pond, total_buck);
        let amount = coin::value(&coin) * pond.reserve / duck::supply(manager);
        duck::burn(duck::cap(manager), coin);

        (
            CompoundRequest { total_buck: 0, receipts: vec_set::empty() },
            WithdrawalRequest { amount, balance: balance::zero() }
        )
    }

    // redeem duck: withdraw buck
    public fun redeem(
        comp_req: CompoundRequest,
        wit_req: WithdrawalRequest,
        pond: &mut Pond, 
        ctx: &mut TxContext
    ): Coin<BUCK> {
        let CompoundRequest { total_buck: _, receipts } = comp_req;
        let WithdrawalRequest { amount, balance } = wit_req;

        assert_receipts_match(pond, &receipts);
        pond.reserve = pond.reserve - amount;
        
        coin::from_balance(balance, ctx)
    }

    // === Public-Friend Functions ===

    // TODO: add public(package)
    public fun new_strategy(
        ctx: &mut TxContext,
    ): Strategy {
        Strategy {
            id: object::new(ctx),
            shares: 0,
            amount: 0,
        }
    }

    public fun increase_strategy_amount(
        amount: u64,
        strategy: &mut Strategy,
    ) {
        strategy.amount = strategy.amount + amount;
    }

    public fun decrease_strategy_amount(
        amount: u64,
        strategy: &mut Strategy,
    ) {
        strategy.amount = strategy.amount - amount;
    }

    // TODO: add public(package)
    public fun add_strategy<Witness: drop>(
        _: Witness, 
        shares: u64,
        amount: u64,
        strategy: Strategy,
        pond: &mut Pond,
    ) {
        assert_is_this_package<Witness>();
        assert!(
            !vec_map::contains(&pond.strategies, &get_module<Witness>()),
            EStrategyAlreadyImplemented
        );

        pond.total_shares = pond.total_shares + shares;
        pond.permanent = pond.permanent + amount;
        strategy.shares = shares;
        strategy.amount = amount;

        vec_map::insert(
            &mut pond.strategies, 
            get_module<Witness>(), 
            strategy,
        );
    }

    // TODO: add public(package)
    public fun borrow_strategy_mut<Witness: drop>(
        _: Witness, 
        pond: &mut Pond
    ): &mut Strategy {
        assert_is_this_package<Witness>();
        assert!(
            vec_map::contains(&pond.strategies, &get_module<Witness>()),
            EStrategyDoesntExist
        );

        vec_map::get_mut(&mut pond.strategies, &get_module<Witness>())
    }

    // TODO: add public(package)
    public fun take_position<Position: key + store>(
        strategy: &mut Strategy,
    ): Position {
        assert!(
            dof::exists_(&strategy.id, PositionKey {}),
            EPositionDoesntExist
        );

        dof::remove(&mut strategy.id, PositionKey {})
    }

    // TODO: add public(package)
    public fun store_position<Position: key + store>(
        strategy: &mut Strategy,
        position: Position,
    ) {
        assert!(
            !dof::exists_(&strategy.id, PositionKey {}),
            EPositionAlreadyStored
        );

        dof::add(&mut strategy.id, PositionKey {}, position);
    }

    // TODO: add public(package)
    // returns the balance share of the user to be deposited in the protocol 
    public fun get_user_deposit_for_protocol<Witness: drop>(
        _: Witness, 
        pond: &Pond,
        dep_req: &mut DepositRequest,
        comp_req: &mut CompoundRequest,
    ): Balance<BUCK> {
        assert_is_this_package<Witness>();
        let balance = balance::value(&dep_req.balance);

        if (vec_set::size(&comp_req.receipts) == vec_map::size(&pond.strategies) - 1) {
            // if it is the last module, we take the rest
            return balance::split(&mut dep_req.balance, balance)
        };

        let strategy = vec_map::get(&pond.strategies, &get_module<Witness>());
        let balance_due = math64::mul_div_up(dep_req.amount, strategy.shares, pond.total_shares);
        balance::split(&mut dep_req.balance, balance_due)
    }

    // TODO: add public(package)
    // returns the amount the user will withdraw from the protocol 
    public fun get_user_withdrawal_for_protocol<Witness: drop>(
        _: Witness, 
        pond: &Pond,
        request: &mut WithdrawalRequest,
    ): u64 {
        assert_is_this_package<Witness>();

        let strategy_idx = vec_map::get_idx(&pond.strategies, &get_module<Witness>());
        let amount_in_lower_strategies = 0;
        let i = vec_map::size(&pond.strategies) - 1;
        // we get all available funds from lower ranked strategies
        while (i > strategy_idx) {
            let (_, strategy) = vec_map::get_entry_by_idx(&pond.strategies, i);
            amount_in_lower_strategies = amount_in_lower_strategies + strategy.amount;

            i = i - 1;
        };
        // if there's not enough in lower strategies, we need to get amount from this one
        if (amount_in_lower_strategies < request.amount) {
            let this_strategy = vec_map::get(&pond.strategies, &get_module<Witness>());
            // if this one doesn't have enough we take everything
            if (this_strategy.amount < request.amount) return this_strategy.amount;
            // if this one has enough, we return the amount requested
            return request.amount
            // otherwise we don't take from this strategy
        } else return 0
    }

    // public fun get_user_balance_for_protocol<Witness: drop>(
    //     _: Witness, 
    //     pond: &mut Pond,
    //     request: &mut DepositRequest,
    // ): Balance<BUCK> {
    //     assert_is_this_package<Witness>();

    //     if (coin::value(&request.coin) == 0) { return balance::zero() };

    //     let total_amount = pond.pending + pond.reserve + pond.permanent + pond.treasury;
    //     let strategy_idx = vec_map::get_idx(&pond.strategies, &get_module<Witness>());

    //     let i = 0;
    //     while (i < strategy_idx) {
    //         let (_, strategy) = vec_map::get_entry_by_idx(&mut pond.strategies, i);
    //         // calculate the amount the checked protocol should have depending on the shares 
    //         let target_amount = total_amount * strategy.shares / pond.total_shares;
    //         if (target_amount > strategy.amount + coin::value(&request.coin)) {
    //             // meaning the protocol with higher votes should take the balance first
    //             return balance::zero()
    //         };

    //         i = i + 1;
    //     };
    //     // calculate how much the protocol called should have
    //     let strategy = vec_map::get_mut(&mut pond.strategies, &get_module<Witness>());
    //     let target_amount = total_amount * strategy.shares / pond.total_shares;
    //     let amount = if (target_amount - strategy.amount > coin::value(&request.coin)) {
    //         coin::value(&request.coin)
    //     } else {
    //         target_amount - strategy.amount
    //     };
    //     balance::split(coin::balance_mut(&mut request.coin), amount)
    // }

    // TODO: add public(package)
    public fun join_withdrawal_balance<Witness: drop>(_: Witness, request: &mut WithdrawalRequest, balance: Balance<BUCK>) {
        assert_is_this_package<Witness>();
        balance::join(&mut request.balance, balance);
    } 

    // TODO: add public(package)
    public fun add_compound_receipt<Witness: drop>(_: Witness, request: &mut CompoundRequest) {
        assert_is_this_package<Witness>();
        vec_set::insert(&mut request.receipts, get_module<Witness>());
    }

    // TODO: add public(package)
    public fun add_compound_amount<Witness: drop>(_: Witness, request: &mut CompoundRequest, amount: u64) {
        assert_is_this_package<Witness>();
        request.total_buck = request.total_buck + amount;
    } 

    // === Admin Functions ===

    // === Private Functions ===

    fun assert_is_this_package<Witness: drop>() {
        let this_type_name = type_name::get<Package>();
        let this_package_id = type_name::get_address<>(&this_type_name);

        let witness_type_name = type_name::get<Witness>();
        let witness_package_id = type_name::get_address<>(&witness_type_name);
        // TODO: add verify type_name include Witness

        assert!(this_package_id == witness_package_id, EDifferentPackage);
    }

    fun get_module<Witness: drop>(): String {
        let type_name = type_name::get<Witness>();
        type_name::get_module(&type_name)
    }

    fun sort_strategies_by_shares<K: copy, V>(strategies: &mut VecMap<String, Strategy>) {
        let len = vec_map::size(strategies);

        let i = 0;
        while (i < len - 1) {
            let max_index = i;

            let j = i + 1;
            while (j < len) {
                let (_, j_strategy) = vec_map::get_entry_by_idx(strategies, j);
                let (_, max_index_strategy) = vec_map::get_entry_by_idx(strategies, max_index);
                
                if (j_strategy.shares > max_index_strategy.shares) { max_index = j };

                j = j + 1;
            };

            vec_map::swap(strategies, i, max_index);

            i = i + 1;
        };
    }

    fun assert_receipts_match(pond: &mut Pond, receipts: &VecSet<String>) {
        let keys = vec_map::keys(&pond.strategies);
        while (vector::length(&keys) != 0) {
            assert!(
                vec_set::contains(receipts, &vector::pop_back(&mut keys)), 
                ERequestDoesntMatch
            )
        };
    }

    // reserve captures yield from all except Treasury 
    // (incentivizes team to not withdraw and lower the fee)
    fun compound_buckets(pond: &mut Pond, total_buck: u64) {
        let prev_buck = pond.pending + pond.reserve + pond.permanent + pond.treasury;
        pond.treasury = pond.treasury * total_buck / prev_buck;
        pond.reserve = total_buck - pond.pending - pond.permanent - pond.treasury;
    }

    fun reserve_buck_supply_duck_ratio(pond: &Pond, manager: &mut DuckManager): u64 {
        // TODO: handle supply duck = 0 case
        if (duck::supply(manager) != 0) {
            return pond.reserve * MUL / duck::supply(manager)
        };

        1 * MUL
    }

    // === Test Functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun assert_pond_data(
        pond: &Pond,
        pending: u64,
        reserve: u64,
        permanent: u64,
        treasury: u64,
        total_shares: u64,
    ) {
        assert!(pending == pond.pending, 100);
        assert!(reserve == pond.reserve, 101);
        assert!(permanent == pond.permanent, 102);
        assert!(treasury == pond.treasury, 103);
        assert!(total_shares == pond.total_shares, 104);
    }

    #[test_only]
    public fun assert_strategy_data(
        pond: &Pond,
        name: vector<u8>,
        shares: u64,
        amount: u64,
    ) {
        let strat = vec_map::get(&pond.strategies, &ascii::string(name));
        assert!(shares == strat.shares, 105);
        assert!(amount == strat.amount, 106);
    }

    #[test_only]
    public fun assert_deposit_data(
        nft: &mut Goose,
        amount: u64,
        timestamp: u64,
    ) {
        let deposit = df::borrow<DepositKey, Deposit>(goose::uid_mut(nft), DepositKey {});
        assert!(amount == deposit.amount, 107);
        assert!(timestamp == deposit.timestamp, 108);
    }

    #[test_only]
    public fun assert_no_deposit(
        nft: &mut Goose,
    ) {
        assert!(!df::exists_(goose::uid_mut(nft), DepositKey {}), 109);
    }
}