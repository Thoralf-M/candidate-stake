#!/bin/bash
# E2E test: two stakers deposit, then the creator cancels the pool.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "=== Test: Cancel ==="

ADMIN=$(get_active_address)
STAKER1=$(new_address)
STAKER2=$(new_address)
log "Admin:   $ADMIN (creator)"
log "Staker1: $STAKER1"
log "Staker2: $STAKER2"

# Fund stakers with faucet for gas
fund_with_faucet "$STAKER1"
fund_with_faucet "$STAKER2"

# Transfer IOTA from admin for staking
switch_to "$ADMIN"
log "Transferring IOTA to stakers..."
COIN1=$(transfer_iota "$STAKER1" 100000000000)
COIN2=$(transfer_iota "$STAKER2" 200000000000)

# Staker1 stakes 100 IOTA
switch_to "$STAKER1"
log "Staker1 staking 100 IOTA to $VALIDATOR1..."
STAKED1=$(stake_coin "$VALIDATOR1" "$COIN1")
log "Staker1 StakedIota: $STAKED1"

# Staker2 stakes 200 IOTA
switch_to "$STAKER2"
log "Staker2 staking 200 IOTA to $VALIDATOR1..."
STAKED2=$(stake_coin "$VALIDATOR1" "$COIN2")
log "Staker2 StakedIota: $STAKED2"

wait_for_next_epoch

# Admin creates pool
switch_to "$ADMIN"
log "Creating CandidateStake pool..."
POOL_ID=$(create_pool "$VALIDATOR2")
log "Pool: $POOL_ID"

# Both stakers deposit
switch_to "$STAKER1"
log "Staker1 depositing..."
deposit_to_pool "$POOL_ID" "$STAKED1" >/dev/null

switch_to "$STAKER2"
log "Staker2 depositing..."
deposit_to_pool "$POOL_ID" "$STAKED2" >/dev/null

# Verify deposits
FIELDS=$(get_object_fields "$POOL_ID")
assert_eq "$(echo "$FIELDS" | jq -r '.deposits | length')" "2" "deposit count is 2"

# Admin cancels the pool
switch_to "$ADMIN"
log "Admin cancelling pool..."
cancel_pool "$POOL_ID" >/dev/null

# Verify both stakers got their StakedIota back
S1_RETURNED=$(count_owned_staked "$STAKER1")
S2_RETURNED=$(count_owned_staked "$STAKER2")
assert_ge "$S1_RETURNED" "1" "staker1 got StakedIota back"
assert_ge "$S2_RETURNED" "1" "staker2 got StakedIota back"

log "=== PASSED ==="
