#!/bin/bash
# E2E test: deposit a StakedIota then withdraw it back.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "=== Test: Withdraw ==="

ADMIN=$(get_active_address)
STAKER=$(new_address)
log "Admin:   $ADMIN"
log "Staker:  $STAKER"

# Fund staker with faucet for gas
fund_with_faucet "$STAKER"

# Transfer 100 IOTA to staker for staking
switch_to "$ADMIN"
log "Transferring 100 IOTA to staker..."
STAKER_COIN=$(transfer_iota "$STAKER" 100000000000)

# Staker stakes the coin to validator1
switch_to "$STAKER"
log "Staker staking 100 IOTA to $VALIDATOR1..."
STAKED=$(stake_coin "$VALIDATOR1" "$STAKER_COIN")
log "StakedIota: $STAKED"

wait_for_next_epoch

# Admin creates pool
switch_to "$ADMIN"
log "Creating CandidateStake pool..."
POOL_ID=$(create_pool "$VALIDATOR2")
log "Pool: $POOL_ID"

# Staker deposits
switch_to "$STAKER"
log "Staker depositing..."
deposit_to_pool "$POOL_ID" "$STAKED" >/dev/null

# Verify deposit
FIELDS=$(get_object_fields "$POOL_ID")
assert_eq "$(echo "$FIELDS" | jq -r '.deposits | length')" "1" "deposit count is 1"

# Staker withdraws all their deposits
log "Staker withdrawing..."
withdraw_from_pool "$POOL_ID" >/dev/null

# Verify pool is now empty
FIELDS=$(get_object_fields "$POOL_ID")
assert_eq "$(echo "$FIELDS" | jq -r '.deposits | length')" "0" "deposit count is 0 after withdraw"
assert_eq "$(echo "$FIELDS" | jq -r '.total_principal')" "0" "total principal is 0 after withdraw"

# Verify StakedIota returned to staker
RETURNED=$(count_owned_staked "$STAKER")
assert_ge "$RETURNED" "1" "staker got StakedIota back"

log "=== PASSED ==="
