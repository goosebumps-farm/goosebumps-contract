module goose_bumps::bucket_tank {
    use sui::tx_context::TxContext;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::{Clock};
    use sui::transfer;

    use goose_bumps::pond::{Self, DepositRequest, WithdrawalRequest, CompoundRequest, Pond, Strategy};

    use bucket_protocol::tank::{Self, ContributorToken};
    use bucket_protocol::buck::{Self, BUCK, BucketProtocol};
    use bucket_protocol::bkt::BktTreasury;
    use bucket_oracle::bucket_oracle::BucketOracle;

    const EBucketAlreadyImplemented: u64 = 0;
    
    struct Witness has drop {}

    // called once
    public fun init_strategy(
        pond: &mut Pond,
        bp: &mut BucketProtocol,
        coin: Coin<BUCK>,
        ctx: &mut TxContext,
    ) {
        let amount = coin::value(&coin);
        let strategy = pond::new_strategy(ctx);
        let tank = buck::borrow_tank_mut<SUI>(bp);
        let token = tank::deposit(tank, coin::into_balance(coin), ctx);
        
        pond::store_position(&mut strategy, token);
        pond::add_strategy(Witness {}, 1, amount, strategy, pond); // abort if already exists
    }

    public fun deposit(
        pond: &mut Pond, 
        comp_req: &mut CompoundRequest, 
        dep_req: &mut DepositRequest, 
        bp: &mut BucketProtocol,
        oracle: &BucketOracle,
        bt: &mut BktTreasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // get user balance to deposit in bucket 
        let user_balance = pond::get_user_deposit_for_protocol(
            Witness {}, 
            pond, 
            dep_req, 
            comp_req
        );
        let strategy = pond::borrow_strategy_mut(Witness {}, pond);
        // update strategy data
        pond::increase_strategy_amount(balance::value(&user_balance), strategy);
        // merge user_balance with all buck
        let buck = get_all_buck(strategy, bp, oracle, bt, clock, ctx);
        balance::join(&mut buck, user_balance);
        // deposit into bucket tank, store the token and validate rule
        let token = tank::deposit(buck::borrow_tank_mut<SUI>(bp), buck, ctx);
        pond::store_position(strategy, token);
        pond::add_compound_receipt(Witness {}, comp_req);
    }

    public fun withdraw(
        pond: &mut Pond, 
        comp_req: &mut CompoundRequest, 
        wit_req: &mut WithdrawalRequest, 
        bp: &mut BucketProtocol,
        oracle: &BucketOracle,
        bt: &mut BktTreasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // get user amount to withdraw from bucket
        let user_amount = pond::get_user_withdrawal_for_protocol(Witness {}, pond, wit_req);
        let strategy = pond::borrow_strategy_mut(Witness {}, pond);
        // update strategy data
        pond::decrease_strategy_amount(user_amount, strategy);
        // merge it with the rest of the balance to withdraw
        let buck = get_all_buck(strategy, bp, oracle, bt, clock, ctx);
        let balance = balance::split(&mut buck, user_amount);
        pond::join_withdrawal_balance(Witness {}, wit_req, balance);
        // deposit into bucket tank, store the token and validate rule
        let token = tank::deposit(buck::borrow_tank_mut<SUI>(bp), buck, ctx);
        pond::store_position(strategy, token);
        pond::add_compound_receipt(Witness {}, comp_req);
    }

    public fun compound(
        pond: &mut Pond, 
        comp_req: &mut CompoundRequest,
        bp: &mut BucketProtocol,
        oracle: &BucketOracle,
        bt: &mut BktTreasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let strategy = pond::borrow_strategy_mut(Witness {}, pond);
        // get total buck in this protocol and add it to total
        let buck = get_all_buck(strategy, bp, oracle, bt, clock, ctx);
        pond::add_compound_amount(Witness {}, comp_req, balance::value(&buck));
        // deposit into bucket tank, store the token and validate rule
        let token = tank::deposit(buck::borrow_tank_mut<SUI>(bp), buck, ctx);
        pond::store_position(strategy, token);
        pond::add_compound_receipt(Witness {}, comp_req);
    }

    fun get_all_buck(
        strategy: &mut Strategy,
        bp: &mut BucketProtocol,
        oracle: &BucketOracle,
        bt: &mut BktTreasury,
        clock: &Clock,
        ctx: &mut TxContext
    ): Balance<BUCK> {
        let token: ContributorToken<BUCK, SUI> = pond::take_position(strategy);
        let (buck, sui, bkt) = buck::tank_withdraw<SUI>(bp, oracle, clock, bt, token, ctx);
        // TODO: to remove and add HPP for swapping 
        transfer::public_transfer(coin::from_balance(sui, ctx), @0xfcd5f2eee4ca6d81d49c85a1669503b7fc8e641b406fe7cdb696a67ef861492c);
        // TODO: to remove and replace 
        balance::destroy_zero(bkt);

        buck
    }

    // BUCK/SUI Pool is empty!!
    // fun swap_sui_for_buck(
    //     config: &GlobalConfig, 
    //     pool: &mut Pool<BUCK, SUI>,
    //     clock: &Clock, 
    //     sui_to_swap: Balance<SUI>,
    //     ctx: &mut TxContext
    // ): Balance<BUCK> {
    //     let (buck_balance, sui_balance, flash_receipt) = pool::flash_swap<BUCK, SUI>(
    //         config,
    //         pool,
    //         false, // sui to buck
    //         true, // next value is amount in
    //         balance::value(&sui_to_swap),
    //         1, // sqrt(sui_price/buck_price) TODO: dynamic
    //         clock
    //     );
    //     // balance::destroy_zero<SUI>(sui_balance);

    //     // pay for flash swap
    //     let sui_amount_to_pay = pool::swap_pay_amount(&flash_receipt);
    //     let pay_sui = balance::split(&mut sui_to_swap, sui_amount_to_pay);
    //     balance::join(&mut sui_balance, sui_to_swap);

    //     pool::repay_flash_swap<BUCK, SUI>(
    //         config,
    //         pool,
    //         balance::zero<BUCK>(),
    //         pay_sui,
    //         flash_receipt
    //     );
    //     // TODO: see if best solution
    //     transfer::public_transfer(coin::from_balance(sui_balance, ctx), @0xfcd5f2eee4ca6d81d49c85a1669503b7fc8e641b406fe7cdb696a67ef861492c);
    //     buck_balance
    // }

    #[test_only]
    public fun init_strategy_for_testing(
        pond: &mut Pond, 
        bp: &mut BucketProtocol, 
        coin: Coin<BUCK>, 
        ctx: &mut TxContext
    ) {
        init_strategy(pond, bp, coin, ctx);
    }
}