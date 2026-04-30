# CandidateStake

An IOTA Move smart contract that lets users pool their staked IOTA to help a candidate validator reach the 2 million IOTA minimum stake required to join the validator set.

## How it works

```mermaid
flowchart LR
    create["<b>create(target_validator)</b><br/>Anyone creates a shared pool"]
    -->deposit["<b>deposit(staked_iota)</b><br/>Users deposit StakedIota objects<br/><i>If pool is full, evicts smallest deposit<br/>when new deposit is strictly larger</i>"]
    -->threshold{"total_principal<br/>≥ 2M IOTA?"}

    threshold-->|No| deposit
    threshold-->|Yes| execute["<b>execute()</b> <i>(creator only)</i><br/>Unstake all from original validators<br/>Restake to target validator<br/>Return new StakedIota to each depositor"]
    -->done(["Pool destroyed"])

    deposit-.->|Depositor, anytime| withdraw["<b>withdraw()</b><br/>Reclaim own deposits"]
    create-.->|Creator only| cancel["<b>cancel()</b><br/>Return all deposits to owners"]
    cancel-.->done
```

1. **Create a pool** — Anyone calls `create` with a target validator address. This creates a shared `CandidateStake` object that anyone can interact with.

2. **Deposit** — Users deposit their existing `StakedIota` objects into the pool. Each deposit tracks the original depositor so they can withdraw or receive their restaked tokens back later.

3. **Execute** — Once the pool's total principal reaches 2,000,000 IOTA, the pool creator can call `execute`. This unstakes every deposit from its current validator and restakes the full balance to the target validator, returning new `StakedIota` objects (including any accrued rewards) to each original depositor. The pool is destroyed after execution. Only the creator can execute, so they can sync it with the target validator calling `0x3::iota_system::request_add_validator` in the same epoch. Since deposits stay staked to their original validator until execution, no rewards are missed before that point. After restaking, the target validator becomes active only in the second following epoch and can only start earning rewards from then on, so depositors miss at least two epochs of staking rewards during the transition — assuming the target validator successfully joins the committee (the committee size is limited, so a slot must be available).

   **Important:** The target validator must call `0x3::iota_system::request_add_validator` in the same epoch as the restaking to join the committee. If this is not called in the same epoch, an additional epoch of rewards is lost. Depositors should not unstake before the validator has joined, as this could cause the join to fail.

4. **Withdraw** — Before execution, depositors can withdraw their `StakedIota` at any time.

5. **Cancel** — The pool creator can cancel at any time, returning all deposits to their owners and destroying the pool.

## Dust protection

The pool holds up to 1,000 deposits. Deposits are stored in a plain vector — more scalable structures like `LinkedTable` were deliberately avoided to keep the contract simple. If someone tries to deposit when the pool is full, the contract compares the new deposit against the smallest existing one. If the new deposit is strictly larger, the smallest deposit is evicted and sent back to its owner. If not, the transaction aborts. This prevents an attacker from filling the pool with tiny stakes to block legitimate depositors.

## Functions

| Function | Access | Description |
|---|---|---|
| `create` | Anyone | Create a new pool for a target validator |
| `deposit` | Anyone | Deposit a `StakedIota` into the pool |
| `withdraw` | Depositor only | Withdraw all deposits for the caller |
| `execute` | Creator only (when threshold met) | Unstake all, restake to target validator, destroy pool |
| `cancel` | Creator only | Return all deposits, destroy pool |
| `destroy_empty` | Anyone | Clean up a pool after all deposits have been withdrawn |

### View functions

`creator`, `total_principal`, `deposit_count`, `threshold_reached`, `target_validator`, `depositor_of`, `principal_of`

## Publish as immutable

After publishing, the package owner holds an `UpgradeCap` that allows upgrading the contract. This means the publisher could add a function that drains funds from the shared pool. To guarantee depositors that this can never happen, destroy the `UpgradeCap` to make the package permanently immutable.

Publish and destroy the `UpgradeCap` in a single atomic transaction to make the package permanently immutable:

```sh
iota client ptb \
  --publish "." \
  --assign upgrade_cap \
  --move-call iota::package::make_immutable upgrade_cap
```

## Build and test

Requires the [IOTA CLI](https://docs.iota.org/developer/getting-started/install-iota).

```sh
iota move build
iota move test
```
