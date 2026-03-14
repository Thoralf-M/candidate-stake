#!/bin/bash
# E2E test: two accounts deposit StakedIota, then execute coordinated restaking.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "=== Test: Deposit and Execute ==="

ADMIN=$(get_active_address)
STAKER=$(new_address)
log "Admin:   $ADMIN"
log "Staker:  $STAKER"

# Fund staker with faucet (provides gas coins for transactions)
fund_with_faucet "$STAKER"

# --- Staking phase ---

# Admin stakes 1.2M IOTA to validator1 (split from genesis gas coin)
switch_to "$ADMIN"
log "Admin staking 1,200,000 IOTA to $VALIDATOR1..."
ADMIN_STAKED=$(stake_from_gas "$VALIDATOR1" 1200000000000000)
log "Admin StakedIota: $ADMIN_STAKED"

# Transfer 900K IOTA to staker, then staker stakes the full coin to validator1
log "Transferring 900,000 IOTA to staker..."
STAKER_COIN=$(transfer_iota "$STAKER" 900000000000000)
log "Staker coin: $STAKER_COIN"

switch_to "$STAKER"
log "Staker staking 900,000 IOTA to $VALIDATOR1..."
STAKER_STAKED=$(stake_coin "$VALIDATOR1" "$STAKER_COIN")
log "Staker StakedIota: $STAKER_STAKED"

# Wait for epoch so stakes activate
wait_for_next_epoch

# --- Pool phase ---

# Admin creates pool targeting validator2
switch_to "$ADMIN"
log "Creating CandidateStake pool targeting $VALIDATOR2..."
POOL_ID=$(create_pool "$VALIDATOR2")
log "Pool: $POOL_ID"

# Admin deposits
log "Admin depositing..."
deposit_to_pool "$POOL_ID" "$ADMIN_STAKED" >/dev/null

# Staker deposits
switch_to "$STAKER"
log "Staker depositing..."
deposit_to_pool "$POOL_ID" "$STAKER_STAKED" >/dev/null

# Verify pool state
FIELDS=$(get_object_fields "$POOL_ID")
DEPOSIT_COUNT=$(echo "$FIELDS" | jq -r '.deposits | length')
TOTAL=$(echo "$FIELDS" | jq -r '.total_principal')
assert_eq "$DEPOSIT_COUNT" "2" "deposit count is 2"
assert_ge "$TOTAL" "2000000000000000" "total principal >= 2M IOTA threshold"

# --- Execute phase ---

switch_to "$ADMIN"
log "Executing coordinated restaking..."
EXEC_TX=$(execute_pool "$POOL_ID")

# Verify both depositors received new StakedIota
ADMIN_NEW=$(count_staked_for "$EXEC_TX" "$ADMIN")
STAKER_NEW=$(count_staked_for "$EXEC_TX" "$STAKER")
assert_eq "$ADMIN_NEW" "1" "admin received new StakedIota"
assert_eq "$STAKER_NEW" "1" "staker received new StakedIota"

log "=== PASSED ==="
