module goose_bumps::afsui_tank {
    use std::ascii::{Self, String};
    use sui::coin::Coin;
    use sui::clock::{Clock};

    use goose_bumps::pond::{DepositRequest, WithdrawalRequest, CompoundRequest, Pond};
    use goose_bumps::bucket_tank;
    use goose_bumps::admin::AdminCap;

    use bucket_protocol::buck::{BUCK, BucketProtocol};
    use bucket_protocol::bkt::BktTreasury;
    use bucket_oracle::bucket_oracle::BucketOracle;
    use afsui::afsui::AFSUI;

    // called once
    public fun init_strategy(
        pond: &mut Pond,
        bp: &mut BucketProtocol,
        _cap: &AdminCap,
        coin: Coin<BUCK>,
        ctx: &mut TxContext,
    ) {
        bucket_tank::init_strategy<AFSUI>(module_name(), pond, bp, coin, ctx);
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
        bucket_tank::deposit<AFSUI>(module_name(), pond, comp_req, dep_req, bp, oracle, bt, clock, ctx);
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
        bucket_tank::withdraw<AFSUI>(module_name(), pond, comp_req, wit_req, bp, oracle, bt, clock, ctx);
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
        bucket_tank::compound<AFSUI>(module_name(), pond, comp_req, bp, oracle, bt, clock, ctx);
    }

    fun module_name(): String {
        ascii::string(b"afsui_tank")
    }

    #[test_only]
    public fun init_strategy_for_testing(
        pond: &mut Pond, 
        bp: &mut BucketProtocol, 
        cap: &AdminCap,
        coin: Coin<BUCK>, 
        ctx: &mut TxContext
    ) {
        init_strategy(pond, bp, cap, coin, ctx);
    }
}

