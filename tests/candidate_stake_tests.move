#[test_only]
module candidate_stake::candidate_stake_tests;

use iota::coin;
use iota::iota::IOTA;
use iota::test_scenario::{Self, Scenario};
use iota_system::iota_system::IotaSystemState;
use iota_system::staking_pool::StakedIota;
use iota_system::governance_test_utils::{
    create_validators_with_stakes_and_commission_rates,
    create_iota_system_state_for_testing,
    advance_epoch,
    advance_epoch_with_balanced_reward_amounts,
};
use candidate_stake::candidate_stake::{Self, CandidateStake};

const VALIDATOR_1: address = @0x1; // existing validator users are staked with
const VALIDATOR_2: address = @0x2; // target validator for restaking

const STAKER_1: address = @0x42;
const STAKER_2: address = @0x43;
const STAKER_3: address = @0x44;
const ANYONE: address = @0x99;

const NANOS_PER_IOTA: u64 = 1_000_000_000;

// ============================
// Helpers
// ============================

fun set_up_system() {
    let mut scenario = test_scenario::begin(@0x0);
    let ctx = scenario.ctx();
    let (_, validators) = create_validators_with_stakes_and_commission_rates(
        vector[100, 100],
        vector[0, 0],
        ctx,
    );
    create_iota_system_state_for_testing(validators, 0, 0, ctx);
    scenario.end();
}

fun stake_with(staker: address, validator: address, amount: u64, scenario: &mut Scenario) {
    scenario.next_tx(staker);
    let mut system_state = scenario.take_shared<IotaSystemState>();
    let ctx = scenario.ctx();
    system_state.request_add_stake(
        coin::mint_for_testing<IOTA>(amount * NANOS_PER_IOTA, ctx),
        validator,
        ctx,
    );
    test_scenario::return_shared(system_state);
}

fun create_candidate_stake(creator: address, scenario: &mut Scenario) {
    scenario.next_tx(creator);
    candidate_stake::create(VALIDATOR_2, scenario.ctx());
}

fun deposit_stake(staker: address, scenario: &mut Scenario) {
    scenario.next_tx(staker);
    let staked_iota = scenario.take_from_sender<StakedIota>();
    let mut pool = scenario.take_shared<CandidateStake>();
    candidate_stake::deposit(&mut pool, staked_iota, scenario.ctx());
    test_scenario::return_shared(pool);
}

// ============================
// Creation tests
// ============================

#[test]
fun test_create() {
    set_up_system();
    let mut scenario = test_scenario::begin(ANYONE);
    create_candidate_stake(ANYONE, &mut scenario);

    scenario.next_tx(ANYONE);
    let pool = scenario.take_shared<CandidateStake>();
    assert!(pool.creator() == ANYONE);
    assert!(pool.total_principal() == 0);
    assert!(pool.deposit_count() == 0);
    assert!(!pool.threshold_reached());
    assert!(pool.target_validator() == VALIDATOR_2);
    test_scenario::return_shared(pool);
    scenario.end();
}

// ============================
// Deposit tests
// ============================

#[test]
fun test_deposit_single() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    scenario.next_tx(STAKER_1);
    let pool = scenario.take_shared<CandidateStake>();
    assert!(pool.deposit_count() == 1);
    assert!(pool.total_principal() == 100 * NANOS_PER_IOTA);
    assert!(pool.depositor_of(0) == STAKER_1);
    assert!(pool.principal_of(0) == 100 * NANOS_PER_IOTA);
    test_scenario::return_shared(pool);
    scenario.end();
}

#[test]
fun test_deposit_multiple_from_same_address() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 50, &mut scenario);
    stake_with(STAKER_1, VALIDATOR_1, 75, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    scenario.next_tx(STAKER_1);
    let pool = scenario.take_shared<CandidateStake>();
    assert!(pool.deposit_count() == 2);
    assert!(pool.total_principal() == 125 * NANOS_PER_IOTA);
    assert!(pool.depositor_of(0) == STAKER_1);
    assert!(pool.depositor_of(1) == STAKER_1);
    test_scenario::return_shared(pool);
    scenario.end();
}

#[test]
fun test_deposit_multiple_users() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 200, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);

    scenario.next_tx(ANYONE);
    let pool = scenario.take_shared<CandidateStake>();
    assert!(pool.deposit_count() == 2);
    assert!(pool.total_principal() == 300 * NANOS_PER_IOTA);
    test_scenario::return_shared(pool);
    scenario.end();
}

// ============================
// Withdraw tests
// ============================

#[test]
fun test_withdraw() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Withdraw all deposits for STAKER_1
    scenario.next_tx(STAKER_1);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        assert!(pool.deposit_count() == 0);
        assert!(pool.total_principal() == 0);
        test_scenario::return_shared(pool);
    };

    // Verify StakedIota returned
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

#[test]
fun test_withdraw_multiple_deposits_same_user() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 50, &mut scenario);
    stake_with(STAKER_1, VALIDATOR_1, 75, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Withdraw returns both StakedIota objects
    scenario.next_tx(STAKER_1);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        assert!(pool.deposit_count() == 0);
        assert!(pool.total_principal() == 0);
        test_scenario::return_shared(pool);
    };

    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 2);
    scenario.end();
}

#[test]
fun test_withdraw_only_own_deposits() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 50, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 100, &mut scenario);
    stake_with(STAKER_3, VALIDATOR_1, 150, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);
    deposit_stake(STAKER_3, &mut scenario);

    // Staker 2 withdraws — only their deposit is removed
    scenario.next_tx(STAKER_2);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        assert!(pool.deposit_count() == 2);
        assert!(pool.total_principal() == 200 * NANOS_PER_IOTA);
        test_scenario::return_shared(pool);
    };

    scenario.next_tx(STAKER_2);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::ENotDepositor)]
fun test_withdraw_no_deposits() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Staker 2 has no deposits — should abort
    scenario.next_tx(STAKER_2);
    let mut pool = scenario.take_shared<CandidateStake>();
    candidate_stake::withdraw(&mut pool, scenario.ctx());
    test_scenario::return_shared(pool);
    scenario.end();
}

#[test]
fun test_withdraw_drops_below_threshold() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 1_000_000, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 1_500_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);

    // Threshold reached (2.5M > 2M)
    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        assert!(pool.threshold_reached());
        test_scenario::return_shared(pool);
    };

    // Staker 1 withdraws, dropping below threshold
    scenario.next_tx(STAKER_1);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        assert!(!pool.threshold_reached());
        assert!(pool.total_principal() == 1_500_000 * NANOS_PER_IOTA);
        test_scenario::return_shared(pool);
    };

    scenario.end();
}

// ============================
// Execute tests
// ============================

#[test]
fun test_execute_at_threshold() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    // Exactly 2M IOTA
    stake_with(STAKER_1, VALIDATOR_1, 2_000_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Execute — consumes the shared object
    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        let mut system_state = scenario.take_shared<IotaSystemState>();
        candidate_stake::execute(pool, &mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);
    };

    // Staker 1 should have received a new StakedIota
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

#[test]
fun test_execute_above_threshold() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 1_500_000, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 1_000_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);

    // Execute by the creator
    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        let mut system_state = scenario.take_shared<IotaSystemState>();
        candidate_stake::execute(pool, &mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);
    };

    // Both stakers should have received new StakedIota objects
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.next_tx(STAKER_2);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

#[test]
fun test_execute_many_depositors() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 800_000, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 700_000, &mut scenario);
    stake_with(STAKER_3, VALIDATOR_1, 600_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);
    deposit_stake(STAKER_3, &mut scenario);

    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        let mut system_state = scenario.take_shared<IotaSystemState>();
        candidate_stake::execute(pool, &mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);
    };

    // All three stakers get new StakedIota
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.next_tx(STAKER_2);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.next_tx(STAKER_3);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

#[test]
fun test_execute_preserves_amounts() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 1_200_000, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 900_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);

    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        let mut system_state = scenario.take_shared<IotaSystemState>();
        candidate_stake::execute(pool, &mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);
    };

    // Verify amounts preserved (no rewards with 0 reward epoch)
    scenario.next_tx(STAKER_1);
    {
        let staked = scenario.take_from_sender<StakedIota>();
        assert!(staked.amount() == 1_200_000 * NANOS_PER_IOTA);
        scenario.return_to_sender(staked);
    };
    scenario.next_tx(STAKER_2);
    {
        let staked = scenario.take_from_sender<StakedIota>();
        assert!(staked.amount() == 900_000 * NANOS_PER_IOTA);
        scenario.return_to_sender(staked);
    };
    scenario.end();
}

#[test]
fun test_execute_multiple_deposits_same_user() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 1_000_000, &mut scenario);
    stake_with(STAKER_1, VALIDATOR_1, 1_000_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        let mut system_state = scenario.take_shared<IotaSystemState>();
        candidate_stake::execute(pool, &mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);
    };

    // Staker 1 gets 2 new StakedIota objects
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 2);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::EThresholdNotReached)]
fun test_execute_below_threshold() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 1_000_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Only 1M deposited, threshold is 2M
    scenario.next_tx(ANYONE);
    let pool = scenario.take_shared<CandidateStake>();
    let mut system_state = scenario.take_shared<IotaSystemState>();
    candidate_stake::execute(pool, &mut system_state, scenario.ctx());
    test_scenario::return_shared(system_state);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::EThresholdNotReached)]
fun test_execute_after_all_withdrawn() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 2_000_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Withdraw everything
    scenario.next_tx(STAKER_1);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        test_scenario::return_shared(pool);
    };

    // Try execute on empty pool
    scenario.next_tx(ANYONE);
    let pool = scenario.take_shared<CandidateStake>();
    let mut system_state = scenario.take_shared<IotaSystemState>();
    candidate_stake::execute(pool, &mut system_state, scenario.ctx());
    test_scenario::return_shared(system_state);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::ENotCreator)]
fun test_execute_not_creator() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 2_000_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Non-creator tries to execute — should abort
    scenario.next_tx(STAKER_1);
    let pool = scenario.take_shared<CandidateStake>();
    let mut system_state = scenario.take_shared<IotaSystemState>();
    candidate_stake::execute(pool, &mut system_state, scenario.ctx());
    test_scenario::return_shared(system_state);
    scenario.end();
}

// ============================
// Execute with rewards
// ============================

#[test]
fun test_execute_with_rewards() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 2_000_000, &mut scenario);

    // Advance epoch so stake activates, then another epoch with rewards
    advance_epoch(&mut scenario);
    advance_epoch_with_balanced_reward_amounts(0, 100, &mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        let mut system_state = scenario.take_shared<IotaSystemState>();
        candidate_stake::execute(pool, &mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);
    };

    // Staker gets back principal + rewards restaked to new validator
    scenario.next_tx(STAKER_1);
    {
        let staked = scenario.take_from_sender<StakedIota>();
        assert!(staked.amount() >= 2_000_000 * NANOS_PER_IOTA);
        scenario.return_to_sender(staked);
    };
    scenario.end();
}

// ============================
// destroy_empty tests
// ============================

#[test]
fun test_destroy_empty_after_all_withdrawn() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Withdraw
    scenario.next_tx(STAKER_1);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        test_scenario::return_shared(pool);
    };

    // Destroy empty pool
    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        candidate_stake::destroy_empty(pool);
    };

    scenario.end();
}

#[test]
fun test_destroy_empty_fresh_pool() {
    set_up_system();
    let mut scenario = test_scenario::begin(ANYONE);
    create_candidate_stake(ANYONE, &mut scenario);

    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        candidate_stake::destroy_empty(pool);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::ENotEmpty)]
fun test_destroy_non_empty() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Try to destroy non-empty pool
    scenario.next_tx(ANYONE);
    let pool = scenario.take_shared<CandidateStake>();
    candidate_stake::destroy_empty(pool);
    scenario.end();
}

// ============================
// Cancel tests
// ============================

#[test]
fun test_cancel_returns_all_deposits() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 200, &mut scenario);
    stake_with(STAKER_3, VALIDATOR_1, 300, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);
    deposit_stake(STAKER_3, &mut scenario);

    // Creator cancels
    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        candidate_stake::cancel(pool, scenario.ctx());
    };

    // All stakers get their StakedIota back
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.next_tx(STAKER_2);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.next_tx(STAKER_3);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

#[test]
fun test_cancel_empty_pool() {
    set_up_system();
    let mut scenario = test_scenario::begin(ANYONE);
    create_candidate_stake(ANYONE, &mut scenario);

    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        candidate_stake::cancel(pool, scenario.ctx());
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::ENotCreator)]
fun test_cancel_not_creator() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Non-creator tries to cancel
    scenario.next_tx(STAKER_1);
    let pool = scenario.take_shared<CandidateStake>();
    candidate_stake::cancel(pool, scenario.ctx());
    scenario.end();
}

#[test]
fun test_cancel_after_partial_withdraw() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 100, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 200, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);

    // Staker 2 withdraws first
    scenario.next_tx(STAKER_2);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        test_scenario::return_shared(pool);
    };

    // Creator cancels, returning staker 1's deposit
    scenario.next_tx(ANYONE);
    {
        let pool = scenario.take_shared<CandidateStake>();
        candidate_stake::cancel(pool, scenario.ctx());
    };

    // Staker 1 gets StakedIota back
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

// ============================
// Deposit-withdraw-redeposit cycle
// ============================

#[test]
fun test_deposit_withdraw_redeposit() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 2_000_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    // Withdraw
    scenario.next_tx(STAKER_1);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        test_scenario::return_shared(pool);
    };

    // Re-deposit
    deposit_stake(STAKER_1, &mut scenario);

    scenario.next_tx(STAKER_1);
    let pool = scenario.take_shared<CandidateStake>();
    assert!(pool.deposit_count() == 1);
    assert!(pool.total_principal() == 2_000_000 * NANOS_PER_IOTA);
    assert!(pool.threshold_reached());
    test_scenario::return_shared(pool);
    scenario.end();
}

// ============================
// Withdraw with non-contiguous sender deposits
// ============================

#[test]
fun test_withdraw_interleaved_deposits() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 50, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 100, &mut scenario);
    stake_with(STAKER_1, VALIDATOR_1, 75, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);  // index 0
    deposit_stake(STAKER_2, &mut scenario);  // index 1
    deposit_stake(STAKER_1, &mut scenario);  // index 2

    // S1 withdraws — both non-contiguous deposits removed via swap_remove
    scenario.next_tx(STAKER_1);
    {
        let mut pool = scenario.take_shared<CandidateStake>();
        candidate_stake::withdraw(&mut pool, scenario.ctx());
        assert!(pool.deposit_count() == 1);
        assert!(pool.total_principal() == 100 * NANOS_PER_IOTA);
        assert!(pool.depositor_of(0) == STAKER_2);
        test_scenario::return_shared(pool);
    };

    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 2);
    scenario.end();
}

// ============================
// Self-eviction tests
// ============================

#[test]
fun test_deposit_self_eviction() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 10, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 20, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake_with_max(ANYONE, 2, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);  // S1(10) at index 0
    deposit_stake(STAKER_2, &mut scenario);  // S2(20) at index 1, pool full

    // S1 creates a larger stake and deposits, evicting own smaller deposit
    stake_with(STAKER_1, VALIDATOR_1, 25, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);

    scenario.next_tx(STAKER_1);
    {
        let pool = scenario.take_shared<CandidateStake>();
        assert!(pool.deposit_count() == 2);
        assert!(pool.total_principal() == 45 * NANOS_PER_IOTA);
        test_scenario::return_shared(pool);
    };

    scenario.end();
}

// ============================
// Dust protection tests
// ============================

fun create_candidate_stake_with_max(creator: address, max: u64, scenario: &mut Scenario) {
    scenario.next_tx(creator);
    candidate_stake::create_with_max_deposits(VALIDATOR_2, max, scenario.ctx());
}

#[test]
fun test_deposit_evicts_smallest_when_full() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 10, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 20, &mut scenario);
    stake_with(STAKER_3, VALIDATOR_1, 30, &mut scenario);
    stake_with(ANYONE, VALIDATOR_1, 15, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake_with_max(ANYONE, 3, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario); // 10 IOTA at index 0
    deposit_stake(STAKER_2, &mut scenario); // 20 IOTA at index 1
    deposit_stake(STAKER_3, &mut scenario); // 30 IOTA at index 2

    // Pool is full (3/3). ANYONE deposits 15 IOTA, evicts STAKER_1 (10 IOTA)
    deposit_stake(ANYONE, &mut scenario);

    scenario.next_tx(ANYONE);
    let pool = scenario.take_shared<CandidateStake>();
    assert!(pool.deposit_count() == 3);
    assert!(pool.total_principal() == 65 * NANOS_PER_IOTA);
    test_scenario::return_shared(pool);

    // STAKER_1 should have gotten their StakedIota back
    scenario.next_tx(STAKER_1);
    assert!(scenario.ids_for_sender<StakedIota>().length() == 1);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::EDepositTooSmall)]
fun test_deposit_too_small_when_full() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 10, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 20, &mut scenario);
    stake_with(STAKER_3, VALIDATOR_1, 30, &mut scenario);
    stake_with(ANYONE, VALIDATOR_1, 5, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake_with_max(ANYONE, 3, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);
    deposit_stake(STAKER_3, &mut scenario);

    // Pool is full (3/3). ANYONE deposits 5 IOTA which is smaller than
    // the minimum (10 IOTA), so it should abort.
    deposit_stake(ANYONE, &mut scenario);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ::candidate_stake::candidate_stake::EDepositTooSmall)]
fun test_deposit_equal_to_min_when_full() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 10, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 20, &mut scenario);
    stake_with(STAKER_3, VALIDATOR_1, 30, &mut scenario);
    stake_with(ANYONE, VALIDATOR_1, 10, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake_with_max(ANYONE, 3, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);
    deposit_stake(STAKER_3, &mut scenario);

    // Pool is full (3/3). ANYONE deposits 10 IOTA which equals the minimum,
    // so it should abort (must be strictly greater to evict).
    deposit_stake(ANYONE, &mut scenario);
    scenario.end();
}

// ============================
// View function tests
// ============================

#[test]
fun test_view_functions() {
    set_up_system();
    let mut scenario = test_scenario::begin(STAKER_1);

    stake_with(STAKER_1, VALIDATOR_1, 500_000, &mut scenario);
    stake_with(STAKER_2, VALIDATOR_1, 300_000, &mut scenario);
    advance_epoch(&mut scenario);

    create_candidate_stake(ANYONE, &mut scenario);
    deposit_stake(STAKER_1, &mut scenario);
    deposit_stake(STAKER_2, &mut scenario);

    scenario.next_tx(ANYONE);
    let pool = scenario.take_shared<CandidateStake>();
    assert!(pool.total_principal() == 800_000 * NANOS_PER_IOTA);
    assert!(pool.deposit_count() == 2);
    assert!(!pool.threshold_reached());
    assert!(pool.target_validator() == VALIDATOR_2);
    assert!(pool.depositor_of(0) == STAKER_1);
    assert!(pool.depositor_of(1) == STAKER_2);
    assert!(pool.principal_of(0) == 500_000 * NANOS_PER_IOTA);
    assert!(pool.principal_of(1) == 300_000 * NANOS_PER_IOTA);
    test_scenario::return_shared(pool);
    scenario.end();
}
