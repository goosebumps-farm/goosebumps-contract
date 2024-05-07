// core interface for Bucket Tanks
module goose_bumps::bucket_tank {
    use std::ascii::String;
    use sui::coin::{Self, Coin};
    use sui::balance::{Balance};
    use sui::clock::{Clock};

    use goose_bumps::pond::{Self, DepositRequest, WithdrawalRequest, CompoundRequest, Pond, Strategy};

    use bucket_protocol::tank::{ContributorToken};
    use bucket_protocol::buck::{BUCK, BucketProtocol};
    use bucket_protocol::bkt::BktTreasury;
    use bucket_oracle::bucket_oracle::BucketOracle;

    // called once
    public(package) fun init_strategy<CoinType: drop>(
        module_name: String,
        pond: &mut Pond,
        bp: &mut BucketProtocol,
        coin: Coin<BUCK>,
        ctx: &mut TxContext,
    ) {
        let amount = coin.value();
        let mut strategy = pond::new_strategy(ctx);
        let tank = bp.borrow_tank_mut<CoinType>();
        let token = tank.deposit(coin.into_balance(), ctx);
        
        strategy.store_position(token);
        pond.add_strategy(strategy, module_name, 1, amount); // abort if already exists
    }

    public(package) fun deposit<CoinType: drop>(
        module_name: String,
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
        let user_balance = pond.get_user_deposit_for_protocol(
            dep_req, 
            comp_req,
            module_name, 
        );
        let strategy = pond.borrow_strategy_mut(module_name);
        // update strategy data
        strategy.increase_strategy_amount(user_balance.value());
        // merge user_balance with all buck
        let mut buck = get_all_buck<CoinType>(strategy, bp, oracle, bt, clock, ctx);
        buck.join(user_balance);
        // deposit into bucket tank, store the token and validate rule
        let token = bp.borrow_tank_mut<CoinType>().deposit(buck, ctx);
        strategy.store_position(token);
        comp_req.add_compound_receipt(module_name);
    }

    public(package) fun withdraw<CoinType: drop>(
        module_name: String,
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
        let user_amount = pond.get_user_withdrawal_for_protocol(wit_req, module_name);
        let strategy = pond.borrow_strategy_mut(module_name);
        // update strategy data
        strategy.decrease_strategy_amount(user_amount);
        // merge it with the rest of the balance to withdraw
        let mut buck = get_all_buck<CoinType>(strategy, bp, oracle, bt, clock, ctx);
        let balance = buck.split(user_amount);
        wit_req.join_withdrawal_balance(balance);
        // deposit into bucket tank, store the token and validate rule
        let token = bp.borrow_tank_mut<CoinType>().deposit(buck, ctx);
        strategy.store_position(token);
        comp_req.add_compound_receipt(module_name);
    }

    public(package) fun compound<CoinType: drop>(
        module_name: String,
        pond: &mut Pond, 
        comp_req: &mut CompoundRequest,
        bp: &mut BucketProtocol,
        oracle: &BucketOracle,
        bt: &mut BktTreasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let strategy = pond.borrow_strategy_mut(module_name);
        // get total buck in this protocol and add it to total
        let buck = get_all_buck<CoinType>(strategy, bp, oracle, bt, clock, ctx);
        comp_req.add_compound_amount(buck.value());
        // deposit into bucket tank, store the token and validate rule
        let token = bp.borrow_tank_mut<CoinType>().deposit(buck, ctx);
        strategy.store_position(token);
        comp_req.add_compound_receipt(module_name);
    }

    fun get_all_buck<CoinType: drop>(
        strategy: &mut Strategy,
        bp: &mut BucketProtocol,
        oracle: &BucketOracle,
        bt: &mut BktTreasury,
        clock: &Clock,
        ctx: &mut TxContext
    ): Balance<BUCK> {
        let token: ContributorToken<BUCK, CoinType> = strategy.take_position();
        let (buck, coin, bkt) = bp.tank_withdraw<CoinType>(oracle, clock, bt, token, ctx);
        // TODO: to remove and add HPP for swapping 
        transfer::public_transfer(coin::from_balance(coin, ctx), @0xfcd5f2eee4ca6d81d49c85a1669503b7fc8e641b406fe7cdb696a67ef861492c);
        // TODO: to remove and replace 
        bkt.destroy_zero();

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
}

