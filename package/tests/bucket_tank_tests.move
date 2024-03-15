#[test_only]
module goose_bumps::bucket_tank_tests{
    use std::debug::print;
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils as tu;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::sui::SUI;

    use bucket_protocol::buck::{Self, BucketProtocol, BUCK, AdminCap as BpCap};
    use bucket_protocol::bkt::{Self, BktTreasury, BKT, BktAdminCap as BtCap};
    use bucket_oracle::bucket_oracle::{Self, BucketOracle, AdminCap as BoCap};

    use goose_bumps::pond::{Self, Pond};
    use goose_bumps::duck::{Self, DuckManager, DUCK};
    use goose_bumps::goose::{Self, Goose};
    use goose_bumps::bucket_tank;

    const PUMP_FEE: u64 = 50_000_000; // 5%
    const MUL: u64 = 1_000_000_000; // scaling factor

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xCAFE;
    const BOB: address = @0xFACE;

    struct Storage {
        clock: Clock,
        pond: Pond,
        manager: DuckManager,
        bp: BucketProtocol,
        bt: BktTreasury,
        bo: BucketOracle,
    }

    fun buck(amount: u64, scen: &mut Scenario): Coin<BUCK> {
        coin::mint_for_testing<BUCK>(amount, ts::ctx(scen))
    }

    fun init_scenario(): (Scenario, Storage) {
        let scenario = ts::begin(OWNER);
        let scen = &mut scenario;

        // initialize modules
        pond::init_for_testing(ts::ctx(scen));
        duck::init_for_testing(ts::ctx(scen));
        goose::init_for_testing(ts::ctx(scen));
        
        let clock = clock::create_for_testing(ts::ctx(scen));
        clock::share_for_testing(clock);
        buck::share_for_testing(tu::create_one_time_witness<BUCK>(), OWNER, ts::ctx(scen));
        bkt::share_for_testing(tu::create_one_time_witness<BKT>(), OWNER, ts::ctx(scen));
        bucket_oracle::share_for_testing<SUI>(9, OWNER, ts::ctx(scen));

        ts::next_tx(scen, OWNER);

        // get shared objects for storage
        let clock = ts::take_shared<Clock>(scen);
        let manager = ts::take_shared<DuckManager>(scen);
        let pond = ts::take_shared<Pond>(scen);
        let bp = ts::take_shared<BucketProtocol>(scen);
        let bt = ts::take_shared<BktTreasury>(scen);
        let bo = ts::take_shared<BucketOracle>(scen);

        // init shared objects
        let coin = buck(1, scen);
        bucket_tank::init_strategy_for_testing(&mut pond, &mut bp, coin, ts::ctx(scen));
        duck::init_manager_for_testing(&mut manager, &clock, 0, 0, 0, 0); // TODO see if necessary

        (scenario, Storage {pond, bp, bo, clock, bt, manager})
    }

    fun forward_scenario(scen: &mut Scenario, storage: Storage, user: address): Storage {
        let Storage { pond, bp, bo, clock, bt, manager } = storage;

        ts::return_shared(clock);
        ts::return_shared(pond);
        ts::return_shared(manager);
        ts::return_shared(bp);
        ts::return_shared(bt);
        ts::return_shared(bo);

        ts::next_tx(scen, user);

        let clock = ts::take_shared<Clock>(scen);
        let manager = ts::take_shared<DuckManager>(scen);
        let pond = ts::take_shared<Pond>(scen);
        let bp = ts::take_shared<BucketProtocol>(scen);
        let bt = ts::take_shared<BktTreasury>(scen);
        let bo = ts::take_shared<BucketOracle>(scen);

        Storage {pond, bp, bo, clock, bt, manager}
    }

    fun complete_scenario(scenario: Scenario, storage: Storage) {
        let Storage { pond, bp, bo, clock, bt, manager } = storage;

        clock::destroy_for_testing(clock);
        ts::return_shared(pond);
        ts::return_shared(manager);
        ts::return_shared(bp);
        ts::return_shared(bt);
        ts::return_shared(bo);
        
        ts::end(scenario);
    }

    fun create_egg(scen: &mut Scenario, stor: &mut Storage, amount: u64): Goose {
        // create egg: init request
        let (comp_req, dep_req) = pond::request_bump(buck(amount, scen));
        // deposit in bucket_tank integration
        bucket_tank::deposit(
            &mut stor.pond,
            &mut comp_req,
            &mut dep_req,
            &mut stor.bp,
            &stor.bo,
            &mut stor.bt,
            &stor.clock,
            ts::ctx(scen)
        );
        // create egg: confirm request
        pond::bump(
            &stor.clock, 
            comp_req, 
            dep_req, 
            &mut stor.pond, 
            ts::ctx(scen)
        )
    }

    fun dump_egg(scen: &mut Scenario, stor: &mut Storage, egg: &mut Goose): Coin<BUCK> {
        let (comp_req, wit_req) = pond::request_dump(egg, ts::ctx(scen));
        bucket_tank::withdraw(
            &mut stor.pond, 
            &mut comp_req,
            &mut wit_req,
            &mut stor.bp,
            &stor.bo,
            &mut stor.bt,
            &stor.clock,
            ts::ctx(scen)
        );
        pond::dump(
            comp_req, 
            wit_req, 
            &mut stor.pond, 
            ts::ctx(scen)
        )
    }

    fun pump_egg(scen: &mut Scenario, stor: &mut Storage, egg: &mut Goose): Coin<DUCK> {
        let comp_req = pond::request_compound();
        bucket_tank::compound(
            &mut stor.pond, 
            &mut comp_req,
            &mut stor.bp,
            &stor.bo,
            &mut stor.bt,
            &stor.clock,
            ts::ctx(scen)
        );
        pond::pump(
            egg,
            comp_req, 
            &mut stor.pond,
            &mut stor.manager,
            &stor.clock, 
            ts::ctx(scen)
        )
    }

    fun redeem_duck(scen: &mut Scenario, stor: &mut Storage, duck: Coin<DUCK>): Coin<BUCK> {
        let comp_req = pond::request_compound();
        bucket_tank::compound(
            &mut stor.pond, 
            &mut comp_req,
            &mut stor.bp,
            &stor.bo,
            &mut stor.bt,
            &stor.clock,
            ts::ctx(scen)
        );
        let (comp_req, wit_req) = pond::request_redeem(
            duck,
            comp_req, 
            &mut stor.pond,
            &mut stor.manager,
        );
        bucket_tank::withdraw(
            &mut stor.pond, 
            &mut comp_req,
            &mut wit_req,
            &mut stor.bp,
            &stor.bo,
            &mut stor.bt,
            &stor.clock,
            ts::ctx(scen)
        );
        pond::redeem(
            comp_req,
            wit_req,
            &mut stor.pond,
            ts::ctx(scen),
        )
    }

    fun pump_fee(amount: u64): u64 {
        amount * PUMP_FEE / MUL
    }

    // === test normal operations === 

    #[test]
    fun publish_package() {
        let (scenario, storage) = init_scenario();
        complete_scenario(scenario, storage);
    }

    #[test]
    fun goose_bumps_normal() {
        let (scenario, storage) = init_scenario();
        let egg = create_egg(&mut scenario, &mut storage, 10);

        pond::assert_pond_data(&storage.pond, 10, 0, 1, 0, 1);
        pond::assert_strategy_data(&storage.pond, b"bucket_tank", 1, 11);
        pond::assert_deposit_data(&mut egg, 10, 0);

        transfer::public_transfer(egg, ALICE);
        complete_scenario(scenario, storage);
    }

    #[test]
    fun goose_bumps_dumps_normal() {
        let (scenario, storage) = init_scenario();
        // goose bumps
        let egg = create_egg(&mut scenario, &mut storage, 10);
        // goose dumps
        let buck = dump_egg(&mut scenario, &mut storage, &mut egg);

        tu::assert_eq(coin::value(&buck), 10);
        pond::assert_pond_data(&storage.pond, 0, 0, 1, 0, 1);
        pond::assert_strategy_data(&storage.pond, b"bucket_tank", 1, 1);
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(buck, ALICE);
        complete_scenario(scenario, storage);
    }

    #[test]
    fun goose_bumps_pumps_same_timestamp_no_duck() {
        let (scenario, storage) = init_scenario();
        // goose bumps
        let egg = create_egg(&mut scenario, &mut storage, 1000);
        // goose pumps
        let duck = pump_egg(&mut scenario, &mut storage, &mut egg);

        tu::assert_eq(coin::value(&duck), 0);
        pond::assert_pond_data(&storage.pond, 0, 950, 46, 5, 1);
        pond::assert_strategy_data(&storage.pond, b"bucket_tank", 1, 1001);
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(duck, ALICE);
        complete_scenario(scenario, storage);
    }

    #[test]
    fun goose_bumps_pumps_get_duck() {
        let (scenario, storage) = init_scenario();
        // goose bumps
        let egg = create_egg(&mut scenario, &mut storage, 1000);
        // goose pumps
        clock::increment_for_testing(&mut storage.clock, 10);
        let duck = pump_egg(&mut scenario, &mut storage, &mut egg);
        tu::assert_eq(coin::value(&duck), 949); // with accrual_param = 1000000
        pond::assert_pond_data(&storage.pond, 0, 950, 46, 5, 1);
        pond::assert_strategy_data(&storage.pond, b"bucket_tank", 1, 1001);
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(duck, ALICE);
        complete_scenario(scenario, storage);
    }

    #[test]
    fun goose_bumps_pumps_redeem_one_sec() {
        let (scenario, storage) = init_scenario();
        let amount = 1_000_000_000;
        // goose bumps
        let egg = create_egg(&mut scenario, &mut storage, amount);
        // goose pumps
        clock::increment_for_testing(&mut storage.clock, 1000);
        let duck = pump_egg(&mut scenario, &mut storage, &mut egg);
        // redeem
        clock::increment_for_testing(&mut storage.clock, 1000);
        let buck = redeem_duck(&mut scenario, &mut storage, duck);

        tu::assert_eq(coin::value(&buck), amount - pump_fee(amount));
        pond::assert_pond_data(
            &storage.pond, 
            0, 
            0, 
            pump_fee(amount) - (pump_fee(amount) / 10) + 1, // + init_strat 
            pump_fee(amount) / 10, 
            1
        );
        pond::assert_strategy_data(
            &storage.pond, 
            b"bucket_tank", 
            1, 
            50000001 // + init_strat
        );
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(buck, ALICE);
        complete_scenario(scenario, storage);
    }

}