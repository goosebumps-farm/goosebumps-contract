#[test_only]
module goose_bumps::bucket_tank_tests{
    use std::debug::print;
    use std::ascii::{Self, String};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils as tu;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use bucket_protocol::buck::{Self, BucketProtocol, BUCK};
    use bucket_protocol::bkt::{Self, BktTreasury, BKT};
    use bucket_oracle::bucket_oracle::{Self, BucketOracle};

    use goose_bumps::pond::{Self, Pond};
    use goose_bumps::duck::{Self, DuckManager, DUCK};
    use goose_bumps::goose::{Self, Goose};
    use goose_bumps::bucket_tank;

    const PUMP_FEE: u64 = 50_000_000; // 5%
    const MUL: u64 = 1_000_000_000; // scaling factor

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    public struct World {
        scenario: Scenario,
        clock: Clock,
        pond: Pond,
        dm: DuckManager,
        bp: BucketProtocol,
        bt: BktTreasury,
        bo: BucketOracle,
    }

    // === helpers ===

    fun buck(amount: u64, scen: &mut Scenario): Coin<BUCK> {
        coin::mint_for_testing<BUCK>(amount, scen.ctx())
    }

    fun module_name(): String {
        ascii::string(b"sui_tank")
    }

    fun pump_fee(amount: u64): u64 {
        amount * PUMP_FEE / MUL
    }

    fun permanent_fee(amount: u64): u64 {
        pump_fee(amount) * 3 / 5
    }

    fun treasury_fee(amount: u64): u64 {
        pump_fee(amount) * 2 / 5
    }

    fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        let scen = &mut scenario;

        // initialize modules
        pond::init_for_testing(scen.ctx());
        duck::init_for_testing(scen.ctx());
        goose::init_for_testing(scen.ctx());
        
        // initialize shared objects
        let clock = clock::create_for_testing(scen.ctx());
        clock.share_for_testing();
        buck::share_for_testing(tu::create_one_time_witness<BUCK>(), OWNER, scen.ctx());
        bkt::share_for_testing(tu::create_one_time_witness<BKT>(), OWNER, scen.ctx());
        bucket_oracle::share_for_testing<SUI>(9, OWNER, scen.ctx());

        // finalize tx to move objects into the account and global inventories
        scen.next_tx(OWNER);

        // get shared objects to compose World
        let clock = scen.take_shared<Clock>();
        let dm = scen.take_shared<DuckManager>();
        let mut pond = scen.take_shared<Pond>();
        let mut bp = scen.take_shared<BucketProtocol>();
        let bt = scen.take_shared<BktTreasury>();
        let bo = scen.take_shared<BucketOracle>();

        // admin function to be executed once at the beginning
        bucket_tank::init_strategy<SUI>(
            module_name(), 
            &mut pond, 
            &mut bp, 
            buck(1, scen), // we deposit 1 buck
            scen.ctx()
        );

        World {scenario, pond, bp, bo, clock, bt, dm}
    }

    fun end_world(world: World) {
        let World { scenario, pond, bp, bo, clock, bt, dm } = world;

        clock.destroy_for_testing();
        ts::return_shared(pond);
        ts::return_shared(dm);
        ts::return_shared(bp);
        ts::return_shared(bt);
        ts::return_shared(bo);
        
        scenario.end();
    }

    // === PTBs ===

    fun create_egg(world: &mut World, amount: u64): Goose {
        // create egg: init request
        let (mut comp_req, mut dep_req) = pond::request_bump(buck(amount, &mut world.scenario));
        // deposit in bucket_tank integration
        bucket_tank::deposit<SUI>(
            module_name(), 
            &mut world.pond,
            &mut comp_req,
            &mut dep_req,
            &mut world.bp,
            &world.bo,
            &mut world.bt,
            &world.clock,
            world.scenario.ctx()
        );
        // create egg: confirm request
        world.pond.bump(
            &world.clock, 
            comp_req, 
            dep_req, 
            world.scenario.ctx()
        )
    }

    fun dump_egg(world: &mut World, egg: &mut Goose): Coin<BUCK> {
        let (mut comp_req, mut wit_req) = pond::request_dump(egg, world.scenario.ctx());
        bucket_tank::withdraw<SUI>(
            module_name(), 
            &mut world.pond, 
            &mut comp_req,
            &mut wit_req,
            &mut world.bp,
            &world.bo,
            &mut world.bt,
            &world.clock,
            world.scenario.ctx()
        );
        world.pond.dump(
            comp_req, 
            wit_req, 
            world.scenario.ctx()
        )
    }

    fun pump_egg(world: &mut World, egg: &mut Goose): Coin<DUCK> {
        let mut comp_req = pond::request_compound();
        bucket_tank::compound<SUI>(
            module_name(), 
            &mut world.pond, 
            &mut comp_req,
            &mut world.bp,
            &world.bo,
            &mut world.bt,
            &world.clock,
            world.scenario.ctx()
        );
        world.pond.pump(
            &mut world.dm,
            &world.clock, 
            egg,
            comp_req, 
            world.scenario.ctx()
        )
    }

    fun redeem_duck(world: &mut World, duck: Coin<DUCK>): Coin<BUCK> {
        let mut comp_req = pond::request_compound();
        bucket_tank::compound<SUI>(
            module_name(), 
            &mut world.pond, 
            &mut comp_req,
            &mut world.bp,
            &world.bo,
            &mut world.bt,
            &world.clock,
            world.scenario.ctx()
        );
        let (mut comp_req, mut wit_req) = world.pond.request_redeem(
            &mut world.dm,
            duck,
            comp_req, 
            world.scenario.ctx()
        );
        bucket_tank::withdraw<SUI>(
            module_name(), 
            &mut world.pond, 
            &mut comp_req,
            &mut wit_req,
            &mut world.bp,
            &world.bo,
            &mut world.bt,
            &world.clock,
            world.scenario.ctx()
        );
        world.pond.redeem(
            comp_req,
            wit_req,
            world.scenario.ctx(),
        )
    }

    // === tests === 

    #[test]
    fun publish_package() {
        let world = start_world();
        end_world(world);
    }

    #[test]
    fun goose_bumps_normal() {
        let mut world = start_world();
        let mut egg = create_egg(&mut world, 10);

        world.pond.assert_pond_data(10, 0, 1, 0, 1);
        world.pond.assert_strategy_data(module_name(), 1, 11);
        pond::assert_deposit_data(&mut egg, 10, 0);

        transfer::public_transfer(egg, ALICE);
        end_world(world);
    }

    #[test]
    fun goose_bumps_dumps_normal() {
        let mut world = start_world();
        // goose bumps
        let mut egg = create_egg(&mut world, 10);
        // goose dumps
        let buck = dump_egg(&mut world, &mut egg);

        tu::assert_eq(coin::value(&buck), 10);
        world.pond.assert_pond_data(0, 0, 1, 0, 1);
        world.pond.assert_strategy_data(module_name(), 1, 1);
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(buck, ALICE);
        end_world(world);
    }

    #[test]
    fun goose_bumps_pumps_same_timestamp_no_duck() {
        let mut world = start_world();
        // goose bumps
        let mut egg = create_egg(&mut world, 1000);
        // goose pumps
        let duck = pump_egg(&mut world, &mut egg);

        tu::assert_eq(duck.value(), 0);
        world.pond.assert_pond_data(0, 950, 31, 20, 1);
        world.pond.assert_strategy_data(module_name(), 1, 1001);
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(duck, ALICE);
        end_world(world);
    }

    #[test]
    fun goose_bumps_pumps_get_duck() {
        let mut world = start_world();
        // goose bumps
        let mut egg = create_egg(&mut world, 1000);
        // goose pumps
        world.clock.increment_for_testing(10);
        let duck = pump_egg(&mut world, &mut egg);
        tu::assert_eq(duck.value(), 950);
        world.pond.assert_pond_data(0, 950, 31, 20, 1);
        world.pond.assert_strategy_data(module_name(), 1, 1001);
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(duck, ALICE);
        end_world(world);
    }

    #[test]
    fun goose_bumps_pumps_redeem_one_sec() {
        let mut world = start_world();
        let amount = 1_000_000_000;
        // goose bumps
        let mut egg = create_egg(&mut world, amount);
        // goose pumps
        clock::increment_for_testing(&mut world.clock, 1000);
        let duck = pump_egg(&mut world, &mut egg);
        // redeem
        clock::increment_for_testing(&mut world.clock, 1000);
        let buck = redeem_duck(&mut world, duck);

        tu::assert_eq(coin::value(&buck), amount - pump_fee(amount));
        pond::assert_pond_data(
            &world.pond, 
            0, 
            0, 
            permanent_fee(amount) + 1, // + init_strat 
            treasury_fee(amount), 
            1
        );
        pond::assert_strategy_data(
            &world.pond, 
            module_name(), 
            1, 
            50000001 // + init_strat
        );
        pond::assert_no_deposit(&mut egg);

        transfer::public_transfer(egg, ALICE);
        transfer::public_transfer(buck, ALICE);
        end_world(world);
    }

}