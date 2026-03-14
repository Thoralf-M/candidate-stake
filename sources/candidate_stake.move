module candidate_stake::candidate_stake;

use iota::coin;
use iota_system::staking_pool::StakedIota;
use iota_system::iota_system::{Self, IotaSystemState};

// 2 million IOTA in nanos (1 IOTA = 1_000_000_000 nanos)
const THRESHOLD: u64 = 2_000_000_000_000_000;
const MAX_DEPOSITS: u64 = 1000;

const EThresholdNotReached: u64 = 0;
const ENotDepositor: u64 = 1;
const ENotEmpty: u64 = 2;
const ENotCreator: u64 = 3;
const EDepositTooSmall: u64 = 4;

/// Tracks a single deposited StakedIota and who deposited it.
public struct Deposit has store {
    depositor: address,
    principal_amount: u64,
    staked_iota: StakedIota,
}

/// Shared object that collects StakedIota deposits and coordinates
/// restaking to a target validator once the threshold is reached.
public struct CandidateStake has key {
    id: UID,
    creator: address,
    target_validator: address,
    deposits: vector<Deposit>,
    total_principal: u64,
    max_deposits: u64,
}

/// Create and share a new CandidateStake pool for a target validator.
public fun create(target_validator: address, ctx: &mut TxContext) {
    transfer::share_object(CandidateStake {
        id: object::new(ctx),
        creator: ctx.sender(),
        target_validator,
        deposits: vector::empty(),
        total_principal: 0,
        max_deposits: MAX_DEPOSITS,
    });
}

#[test_only]
public fun create_with_max_deposits(target_validator: address, max_deposits: u64, ctx: &mut TxContext) {
    transfer::share_object(CandidateStake {
        id: object::new(ctx),
        creator: ctx.sender(),
        target_validator,
        deposits: vector::empty(),
        total_principal: 0,
        max_deposits,
    });
}

/// Deposit a StakedIota object into the pool.
/// If the pool is full, evicts the deposit with the smallest principal
/// (sending its StakedIota back to the depositor) provided the new deposit
/// is strictly larger. Aborts with EDepositTooSmall otherwise.
public fun deposit(
    self: &mut CandidateStake,
    staked_iota: StakedIota,
    ctx: &mut TxContext,
) {
    let principal = staked_iota.amount();

    if (self.deposits.length() >= self.max_deposits) {
        let min_idx = find_min_deposit_index(&self.deposits);
        assert!(principal > self.deposits[min_idx].principal_amount, EDepositTooSmall);
        let Deposit { depositor, principal_amount, staked_iota: evicted_stake } = self.deposits.swap_remove(min_idx);
        self.total_principal = self.total_principal - principal_amount;
        transfer::public_transfer(evicted_stake, depositor);
    };

    self.total_principal = self.total_principal + principal;
    self.deposits.push_back(Deposit {
        depositor: ctx.sender(),
        principal_amount: principal,
        staked_iota,
    });
}

/// Withdraw all deposits belonging to the sender, returning each StakedIota.
/// Aborts with ENotDepositor if the sender has no deposits.
public fun withdraw(
    self: &mut CandidateStake,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    let mut i = self.deposits.length();
    let mut found = false;
    while (i > 0) {
        i = i - 1;
        if (self.deposits[i].depositor == sender) {
            let Deposit { depositor, principal_amount, staked_iota } = self.deposits.swap_remove(i);
            self.total_principal = self.total_principal - principal_amount;
            transfer::public_transfer(staked_iota, depositor);
            found = true;
        };
    };
    assert!(found, ENotDepositor);
}

/// Execute the coordinated restaking. Anyone can call this once threshold is met.
/// Unstakes all deposited StakedIota objects, restakes the proceeds to the
/// target validator, sends new StakedIota objects back to each depositor,
/// and destroys the shared object.
public fun execute(
    self: CandidateStake,
    system_state: &mut IotaSystemState,
    ctx: &mut TxContext,
) {
    let CandidateStake { id, creator: _, target_validator, mut deposits, total_principal, max_deposits: _ } = self;
    assert!(total_principal >= THRESHOLD, EThresholdNotReached);
    object::delete(id);

    while (!deposits.is_empty()) {
        let Deposit { depositor, principal_amount: _, staked_iota } = deposits.pop_back();

        // Unstake from the current validator
        let balance = iota_system::request_withdraw_stake_non_entry(
            system_state,
            staked_iota,
            ctx,
        );

        // Restake the full balance to the target validator
        let coin = coin::from_balance(balance, ctx);
        let new_staked = iota_system::request_add_stake_non_entry(
            system_state,
            coin,
            target_validator,
            ctx,
        );

        // Return the new StakedIota to the original depositor
        transfer::public_transfer(new_staked, depositor);
    };

    deposits.destroy_empty();
}

/// Cancel the pool: return all StakedIota objects to their depositors and destroy
/// the shared object. Only the creator can call this.
public fun cancel(self: CandidateStake, ctx: &mut TxContext) {
    let CandidateStake { id, creator, target_validator: _, mut deposits, total_principal: _, max_deposits: _ } = self;
    assert!(creator == ctx.sender(), ENotCreator);
    object::delete(id);

    while (!deposits.is_empty()) {
        let Deposit { depositor, principal_amount: _, staked_iota } = deposits.pop_back();
        transfer::public_transfer(staked_iota, depositor);
    };

    deposits.destroy_empty();
}

/// Destroy an empty CandidateStake object. Use this to clean up after all deposits
/// have been withdrawn.
public fun destroy_empty(self: CandidateStake) {
    let CandidateStake { id, creator: _, target_validator: _, deposits, total_principal: _, max_deposits: _ } = self;
    assert!(deposits.is_empty(), ENotEmpty);
    deposits.destroy_empty();
    object::delete(id);
}

// === Internal ===

fun find_min_deposit_index(deposits: &vector<Deposit>): u64 {
    let mut min_idx = 0;
    let mut min_amount = deposits[0].principal_amount;
    let mut i = 1;
    let len = deposits.length();
    while (i < len) {
        if (deposits[i].principal_amount < min_amount) {
            min_idx = i;
            min_amount = deposits[i].principal_amount;
        };
        i = i + 1;
    };
    min_idx
}

// === View functions ===

public fun creator(self: &CandidateStake): address { self.creator }
public fun total_principal(self: &CandidateStake): u64 { self.total_principal }
public fun deposit_count(self: &CandidateStake): u64 { self.deposits.length() }
public fun threshold_reached(self: &CandidateStake): bool { self.total_principal >= THRESHOLD }
public fun target_validator(self: &CandidateStake): address { self.target_validator }

public fun depositor_of(self: &CandidateStake, index: u64): address {
    self.deposits[index].depositor
}

public fun principal_of(self: &CandidateStake, index: u64): u64 {
    self.deposits[index].principal_amount
}
