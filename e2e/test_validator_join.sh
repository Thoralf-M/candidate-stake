#!/bin/bash
# E2E test: full flow from staking via CandidateStake through to validator joining the committee.
# Based on https://docs.iota.org/operator/validator-node/cli-validator-command#test-becoming-a-validator-in-a-local-network
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "=== Test: Validator Join via CandidateStake ==="

ADMIN=$(get_active_address)
STAKER=$(new_address)
log "Admin:   $ADMIN"
log "Staker:  $STAKER"

# Fund staker
fund_with_faucet "$STAKER"

# --- Validator becomes a candidate ---

switch_to "$VALIDATOR2"
log "Validator2 requesting to become a candidate validator..."
iota validator become-candidate

wait_for_next_epoch

# Verify validator2 is now a candidate (not yet active)
CANDIDATE_STATUS=$(curl -s "$RPC_URL" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"iotax_getLatestIotaSystemState"}' \
  | jq -r --arg v "$VALIDATOR2" \
    '[.result.pendingActiveValidators[]? | select(.iotaAddress == $v)] | length')
log "Validator2 candidate status entries: $CANDIDATE_STATUS"

# --- Staking phase ---

# Admin stakes 1.2M IOTA to validator1
switch_to "$ADMIN"
log "Admin staking 1,200,000 IOTA to $VALIDATOR1..."
ADMIN_STAKED=$(stake_from_gas "$VALIDATOR1" 1200000000000000)
log "Admin StakedIota: $ADMIN_STAKED"

# Transfer 900K to staker, staker stakes to validator1
log "Transferring 900,000 IOTA to staker..."
STAKER_COIN=$(transfer_iota "$STAKER" 900000000000000)

switch_to "$STAKER"
log "Staker staking 900,000 IOTA to $VALIDATOR1..."
STAKER_STAKED=$(stake_coin "$VALIDATOR1" "$STAKER_COIN")
log "Staker StakedIota: $STAKER_STAKED"

# Wait for stakes to activate
wait_for_next_epoch

# --- Pool phase ---

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

# Verify threshold reached
FIELDS=$(get_object_fields "$POOL_ID")
TOTAL=$(echo "$FIELDS" | jq -r '.total_principal')
assert_ge "$TOTAL" "2000000000000000" "total principal >= 2M IOTA threshold"

# --- Execute restaking ---

switch_to "$ADMIN"
log "Executing coordinated restaking to $VALIDATOR2..."
EXEC_TX=$(execute_pool "$POOL_ID")

# Verify depositors received new StakedIota targeted at validator2
ADMIN_NEW=$(count_staked_for "$EXEC_TX" "$ADMIN")
STAKER_NEW=$(count_staked_for "$EXEC_TX" "$STAKER")
assert_eq "$ADMIN_NEW" "1" "admin received new StakedIota"
assert_eq "$STAKER_NEW" "1" "staker received new StakedIota"

# --- Validator joins the committee (must be same epoch as restaking) ---

switch_to "$VALIDATOR2"
log "Validator2 calling join-validators..."
iota validator join-validators

log "Waiting for epoch change so validator2 joins the committee..."
wait_for_next_epoch

# Verify validator2 is now in the active validator set
ACTIVE=$(curl -s "$RPC_URL" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"iotax_getLatestIotaSystemState"}' \
  | jq -r --arg v "$VALIDATOR2" \
    '[.result.activeValidators[] | select(.iotaAddress == $v)] | length')
assert_eq "$ACTIVE" "1" "validator2 is now an active validator"

log "=== PASSED ==="
