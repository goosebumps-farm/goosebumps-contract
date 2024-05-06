module goose_bumps::pond {
    // === Imports ===
    use std::ascii::String;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::vec_set::{Self, VecSet};
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;
    use sui::versioned::{Self, Versioned};

    use bucket_protocol::buck::BUCK;

    use goose_bumps::math64;
    use goose_bumps::vec_map::{Self, VecMap};
    use goose_bumps::goose::{Self, Goose};
    use goose_bumps::duck::{DuckManager, DUCK};

    // === Constants ===

    const VERSION: u64 = 1;

    const PUMP_FEE: u64 = 50_000_000; // 5%
    const MUL: u64 = 1_000_000_000; // scaling factor
    const MS_IN_MONTH: u64 = 1000 * 60 * 60 * 24 * 30;

    // === Errors ===

    const EStrategyAlreadyImplemented: u64 = 2;
    const EStrategyDoesntExist: u64 = 3;
    const EPositionAlreadyStored: u64 = 4;
    const EPositionDoesntExist: u64 = 5;
    const ERequestDoesntMatch: u64 = 6;
    const ENotEgg: u64 = 7;
    const EZeroCoin: u64 = 8;

    // === Structs ===

    // helper to get package id
    public struct Package has copy, drop, store {}
    // key to add the pending ContributorToken as a DOF
    public struct PositionKey has drop, copy, store {}
    // key to add the pond struct as a DF to nft
    public struct DepositKey has drop, copy, store {}

    public struct Deposit has store {
        amount: u64,
        timestamp: u64,
    }

    // hot potato
    public struct DepositRequest {
        // deposit amount (immutable)
        amount: u64,
        // user deposit
        balance: Balance<BUCK>,
    }

    // hot potato
    public struct WithdrawalRequest {
        // previous user deposit
        amount: u64,
        // returned balance
        balance: Balance<BUCK>,
    }

    // hot potato
    public struct CompoundRequest {
        // total buck amount managed by the protocol
        total_buck: u64,
        // modules that have been called
        receipts: VecSet<String>,
    }

    public struct Pond has key {
        id: UID,
        // store PondInner to enable a potential PondInnerV2
        inner: Versioned,
    }

    public struct PondInner has store {
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

    public struct Strategy has key, store {
        id: UID,
        // shares of funds that should be directed to this protocol
        shares: u64,
        // current amount of BUCK held by this protocol
        amount: u64,
        // DOF: LP token or Receipt (position)
    }

    // === Events ===

    public struct GooseBumps has copy, drop {
        user: address,
        amount: u64,
    }

    public struct GooseDumps has copy, drop {
        user: address,
        amount: u64,
    }

    public struct GoosePumps has copy, drop {
        user: address,
        buck_amount: u64,
        duck_amount: u64,
    }

    public struct RedeemDuck has copy, drop {
        user: address,
        buck_amount: u64,
        duck_amount: u64,
    }

    fun init(ctx: &mut TxContext) {
        // init pond
        let inner = PondInner {
            pending: 0,
            reserve: 0,
            permanent: 0,
            treasury: 0,
            total_shares: 0,
            strategies: vec_map::empty(),
        };
        transfer::share_object(
            Pond {
                id: object::new(ctx),
                inner: versioned::create(VERSION, inner, ctx),
            }
        );
    }

    // === Public-View Functions ===

    // === Public-Mutative Functions ===

    // create egg: init request
    public fun request_bump(
        coin: Coin<BUCK>
    ): (CompoundRequest, DepositRequest) {
        let amount = coin.value(); 
        assert!(amount > 0, EZeroCoin);
        let balance = coin.into_balance();

        (
            CompoundRequest { total_buck: 0, receipts: vec_set::empty() },
            DepositRequest { amount, balance }
        )
    }

    // create egg: validate request
    public fun bump(
        pond: &mut Pond,
        clock: &Clock, 
        comp_req: CompoundRequest, 
        dep_req: DepositRequest, 
        ctx: &mut TxContext,
    ): Goose {
        let CompoundRequest { total_buck: _, receipts } = comp_req;
        let DepositRequest { amount, balance } = dep_req;
        
        pond.inner_mut().pending = pond.inner().pending + amount;

        let mut nft = goose::create(
            b"Egg",
            b"hi-res",
            b"lo-res",
            1,
            ctx,
        );
        // add egg info
        df::add(
            nft.uid_mut(), 
            DepositKey {}, 
            Deposit { amount, timestamp: clock.timestamp_ms() }
        );

        balance.destroy_zero();
        assert_receipts_match(pond, &receipts);

        event::emit(GooseBumps { user: ctx.sender(), amount });

        nft
    }

    // dump egg: init request
    public fun request_dump(
        nft: &mut Goose, 
        ctx: &mut TxContext
    ): (CompoundRequest, WithdrawalRequest) {
        assert!(nft.status() == 1, ENotEgg);
        
        let Deposit { amount, timestamp: _ } = df::remove(nft.uid_mut(), DepositKey {});
        
        nft.update(
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
        pond: &mut Pond, 
        comp_req: CompoundRequest, 
        wit_req: WithdrawalRequest, 
        ctx: &mut TxContext
    ): Coin<BUCK> {
        let CompoundRequest { total_buck: _, receipts } = comp_req;
        let WithdrawalRequest { amount, balance } = wit_req;
        
        pond.inner_mut().pending = pond.inner().pending - amount;
        assert_receipts_match(pond, &receipts);

        event::emit(GooseDumps { user: ctx.sender(), amount });

        coin::from_balance(balance, ctx)
    }
        
    // pump goose: init request
    public fun request_compound(): CompoundRequest {
        CompoundRequest { total_buck: 0, receipts: vec_set::empty() }
    }

    // pump goose: validate request
    public fun pump(
        pond: &mut Pond, 
        duck_manager: &mut DuckManager, 
        clock: &Clock,
        nft: &mut Goose, 
        comp_req: CompoundRequest,
        ctx: &mut TxContext
    ): Coin<DUCK> {
        assert!(nft.status() == 1, ENotEgg);
        
        let Deposit { amount, timestamp } = df::remove(nft.uid_mut(), DepositKey {});
        
        nft.update(
            b"Pumped Goose",
            b"goose_bumps_hi_res",
            b"goose_bumps_lo_res",
            3,
            ctx,
        );

        let CompoundRequest { total_buck, receipts } = comp_req;     
        compound_buckets(pond, total_buck);

        let fee = amount * PUMP_FEE / MUL; // permanent + treasury
        let treasury_amount = fee * 2 / 5; // 2%
        let permanent_amount = fee - treasury_amount; // 3%
        let user_amount = amount - fee;
        let accrued_duck = calculate_accrued_duck(
            pond, 
            duck_manager, 
            clock, 
            user_amount, 
            timestamp
        );

        assert_receipts_match(pond, &receipts);

        pond.inner_mut().pending = pond.inner().pending - amount;   
        pond.inner_mut().reserve = pond.inner().reserve + user_amount;
        pond.inner_mut().permanent = pond.inner().permanent + permanent_amount;
        pond.inner_mut().treasury = pond.inner().treasury + treasury_amount;

        event::emit(
            GoosePumps { 
                user: ctx.sender(), 
                buck_amount: user_amount,
                duck_amount: accrued_duck,
            }
        );

        duck_manager.cap().mint(accrued_duck, ctx)
    }
    
    // need to call request_compound first
    // redeem duck: compound to get ratio
    public fun request_redeem(
        pond: &mut Pond, 
        duck_manager: &mut DuckManager, 
        coin: Coin<DUCK>, 
        comp_req: CompoundRequest,
        ctx: &mut TxContext,
    ): (CompoundRequest, WithdrawalRequest) {
        assert!(coin.value() > 0, EZeroCoin);
        let CompoundRequest { total_buck, receipts } = comp_req;
        assert_receipts_match(pond, &receipts);

        compound_buckets(pond, total_buck);
        let amount = math64::mul_div_down(
            coin.value(), 
            pond.inner().reserve, 
            duck_manager.supply()
        );

        event::emit(
            RedeemDuck { 
                user: ctx.sender(), 
                buck_amount: coin.value(),
                duck_amount: amount,
            }
        );
        duck_manager.cap().burn(coin);

        (
            CompoundRequest { total_buck: 0, receipts: vec_set::empty() },
            WithdrawalRequest { amount, balance: balance::zero() }
        )
    }

    // redeem duck: withdraw buck
    public fun redeem(
        pond: &mut Pond, 
        comp_req: CompoundRequest,
        wit_req: WithdrawalRequest,
        ctx: &mut TxContext
    ): Coin<BUCK> {
        let CompoundRequest { total_buck: _, receipts } = comp_req;
        let WithdrawalRequest { amount, balance } = wit_req;

        assert_receipts_match(pond, &receipts);
        pond.inner_mut().reserve = pond.inner().reserve - amount;
        
        coin::from_balance(balance, ctx)
    }

    public fun calculate_accrued_duck(
        pond: &Pond,
        duck_manager: &DuckManager,
        clock: &Clock,
        user_amount: u64,
        timestamp: u64,
    ): u64 {
        let egg_age = (clock.timestamp_ms() - timestamp) * MUL;
        // this param increase from 0 to 1 over 30 days increasingly slowly
        let accrual_param = if (egg_age > MS_IN_MONTH) MUL else {
            math64::sqrt_down(
                math64::mul_div_down(MUL, egg_age, MS_IN_MONTH)
            )
        };
        let ratio = reserve_buck_supply_duck_ratio(pond, duck_manager);
        // this amount is capped at user_amount / ratio
        math64::mul_div_down(
            user_amount, 
            accrual_param, // scaled with MUL
            ratio // scaled with MUL
        )
    }

    public fun sort_strategies_by_shares(pond: &mut Pond) {
        let strategies = &mut pond.inner_mut().strategies;
        let len = strategies.size();

        let mut i = 0;
        while (i < len - 1) {
            let mut max_index = i;

            let mut j = i + 1;
            while (j < len) {
                let (_, j_strategy) = strategies.get_entry_by_idx(j);
                let (_, max_index_strategy) = strategies.get_entry_by_idx(max_index);
                
                if (j_strategy.shares > max_index_strategy.shares) { max_index = j };

                j = j + 1;
            };

            strategies.swap(i, max_index);

            i = i + 1;
        };
    }

    // === Public-Package Functions ===

    public(package) fun new_strategy(
        ctx: &mut TxContext,
    ): Strategy {
        Strategy {
            id: object::new(ctx),
            shares: 0,
            amount: 0,
        }
    }

    public(package) fun increase_strategy_amount(
        strategy: &mut Strategy,
        amount: u64,
    ) {
        strategy.amount = strategy.amount + amount;
    }

    public(package) fun decrease_strategy_amount(
        strategy: &mut Strategy,
        amount: u64,
    ) {
        strategy.amount = strategy.amount - amount;
    }

    public(package) fun add_strategy(
        pond: &mut Pond,
        mut strategy: Strategy,
        module_name: String, 
        shares: u64,
        amount: u64,
    ) {
        assert!(
            !pond.inner().strategies.contains(&module_name),
            EStrategyAlreadyImplemented
        );

        pond.inner_mut().total_shares = pond.inner().total_shares + shares;
        pond.inner_mut().permanent = pond.inner().permanent + amount;
        strategy.shares = shares;
        strategy.amount = amount;

        pond.inner_mut().strategies.insert(
            module_name, 
            strategy,
        );
    }

    public(package) fun borrow_strategy_mut(
        pond: &mut Pond,
        module_name: String, 
    ): &mut Strategy {
        assert!(
            vec_map::contains(&pond.inner().strategies, &module_name),
            EStrategyDoesntExist
        );

        pond.inner_mut().strategies.get_mut(&module_name)
    }

    public(package) fun take_position<Position: key + store>(
        strategy: &mut Strategy,
    ): Position {
        assert!(
            dof::exists_(&strategy.id, PositionKey {}),
            EPositionDoesntExist
        );

        dof::remove(&mut strategy.id, PositionKey {})
    }

    public(package) fun store_position<Position: key + store>(
        strategy: &mut Strategy,
        position: Position,
    ) {
        assert!(
            !dof::exists_(&strategy.id, PositionKey {}),
            EPositionAlreadyStored
        );

        dof::add(&mut strategy.id, PositionKey {}, position);
    }

    // returns the balance share of the user to be deposited in the protocol 
    public(package) fun get_user_deposit_for_protocol(
        pond: &Pond,
        dep_req: &mut DepositRequest,
        comp_req: &CompoundRequest,
        module_name: String, 
    ): Balance<BUCK> {
        let balance = dep_req.balance.value();

        if (comp_req.receipts.size() == pond.inner().strategies.size() - 1) {
            // if it is the last module, we take the rest
            return dep_req.balance.split(balance)
        };

        let strategy = pond.inner().strategies.get(&module_name);
        let balance_due = math64::mul_div_up(dep_req.amount, strategy.shares, pond.inner().total_shares);
        dep_req.balance.split(balance_due)
    }

    // returns the amount the user will withdraw from the protocol 
    public(package) fun get_user_withdrawal_for_protocol(
        pond: &Pond,
        request: &WithdrawalRequest,
        module_name: String, 
    ): u64 {

        let strategy_idx = pond.inner().strategies.get_idx(&module_name);
        let mut amount_in_lower_strategies = 0;
        let mut i = pond.inner().strategies.size() - 1;
        // we get all available funds from lower ranked strategies
        while (i > strategy_idx) {
            let (_, strategy) = pond.inner().strategies.get_entry_by_idx(i);
            amount_in_lower_strategies = amount_in_lower_strategies + strategy.amount;

            i = i - 1;
        };
        // if there's not enough in lower strategies, we need to get amount from this one
        if (amount_in_lower_strategies < request.amount) {
            let this_strategy = pond.inner().strategies.get(&module_name);
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

    public(package) fun join_withdrawal_balance(request: &mut WithdrawalRequest, balance: Balance<BUCK>) {
        request.balance.join(balance);
    } 

    public(package) fun add_compound_receipt(request: &mut CompoundRequest, module_name: String) {
        request.receipts.insert(module_name);
    }

    public(package) fun add_compound_amount(request: &mut CompoundRequest, amount: u64) {
        request.total_buck = request.total_buck + amount;
    } 

    // === Admin Functions ===

    // === Private Functions ===

    // fun get_module<Witness: drop>(): String {
    //     let type_name = type_name::get<Witness>();
    //     let mut name = type_name.into_string();
    //     let mut ref = ascii::string(b"Witness");
    //     while (ref.length() > 0) {
    //         // we want to make sure it's the Witness type and not another one
    //         assert!(name.pop_char() == ref.pop_char(), ENotWitness);
    //     };
    //     type_name.get_module()
    // }

    fun inner(pond: &Pond): &PondInner {
        pond.inner.load_value()
    }

    fun inner_mut(pond: &mut Pond): &mut PondInner {
        pond.inner.load_value_mut()
    }

    fun assert_receipts_match(pond: &Pond, receipts: &VecSet<String>) {
        let mut keys = pond.inner().strategies.keys();
        while (keys.length() != 0) {
            assert!(
                receipts.contains(&keys.pop_back()), 
                ERequestDoesntMatch
            )
        };
    }

    // reserve captures yield from all except Treasury 
    // (incentivizes team to not withdraw and lower the fee)
    fun compound_buckets(pond: &mut Pond, total_buck: u64) {
        let inner = pond.inner_mut();
        let prev_buck = inner.pending + inner.reserve + inner.permanent + inner.treasury;
        inner.treasury = math64::mul_div_down(inner.treasury, total_buck, prev_buck);
        inner.reserve = total_buck - inner.pending - inner.permanent - inner.treasury;
    }

    fun reserve_buck_supply_duck_ratio(pond: &Pond, duck_manager: &DuckManager): u64 {
        // TODO: handle supply duck = 0 case
        if (duck_manager.supply() != 0) {
            return math64::mul_div_down(pond.inner().reserve, MUL, duck_manager.supply())
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
        assert!(pending == pond.inner().pending, 100);
        assert!(reserve == pond.inner().reserve, 101);
        assert!(permanent == pond.inner().permanent, 102);
        assert!(treasury == pond.inner().treasury, 103);
        assert!(total_shares == pond.inner().total_shares, 104);
    }

    #[test_only]
    public fun assert_strategy_data(
        pond: &Pond,
        module_name: String,
        shares: u64,
        amount: u64,
    ) {
        let strat = pond.inner().strategies.get(&module_name);
        assert!(shares == strat.shares, 105);
        assert!(amount == strat.amount, 106);
    }

    #[test_only]
    public fun assert_deposit_data(
        nft: &mut Goose,
        amount: u64,
        timestamp: u64,
    ) {
        let deposit = df::borrow<DepositKey, Deposit>(nft.uid_mut(), DepositKey {});
        assert!(amount == deposit.amount, 107);
        assert!(timestamp == deposit.timestamp, 108);
    }

    #[test_only]
    public fun assert_no_deposit(
        nft: &mut Goose,
    ) {
        assert!(!df::exists_(nft.uid_mut(), DepositKey {}), 109);
    }
}

