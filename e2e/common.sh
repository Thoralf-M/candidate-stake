#!/bin/bash
set -euo pipefail

PACKAGE_ID="${PACKAGE_ID:?PACKAGE_ID must be set}"
VALIDATOR1="${VALIDATOR1:?VALIDATOR1 must be set}"
VALIDATOR2="${VALIDATOR2:?VALIDATOR2 must be set}"
RPC_URL="${RPC_URL:-http://localhost:9000}"

# ---------------------------------------------------------------------------
# Logging & assertions
# ---------------------------------------------------------------------------

log()  { echo "==> $*" >&2; }
pass() { echo "  ✓ $*" >&2; }
fail() { echo "  ✗ $*" >&2; exit 1; }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "${3:-}"; else fail "${3:-} (expected '$2', got '$1')"; fi
}

assert_ge() {
  if [ "$1" -ge "$2" ] 2>/dev/null; then pass "${3:-}"; else fail "${3:-} (expected >= $2, got '$1')"; fi
}

# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------

get_current_epoch() {
  curl -s "$RPC_URL" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"iotax_getLatestIotaSystemState"}' \
    | jq -r '.result.epoch'
}

wait_for_next_epoch() {
  local current target
  current=$(get_current_epoch)
  target=$((current + 1))
  log "Waiting for epoch $target (current: $current)..."
  while [ "$(get_current_epoch)" -lt "$target" ]; do sleep 2; done
  log "Epoch $target reached"
}

get_object_fields() {
  curl -s "$RPC_URL" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"iota_getObject","params":["'"$1"'",{"showContent":true}]}' \
    | jq '.result.data.content.fields'
}

# ---------------------------------------------------------------------------
# Account helpers
# ---------------------------------------------------------------------------

switch_to() {
  iota client switch --address "$1" >/dev/null 2>&1
}

get_active_address() {
  iota client active-address
}

new_address() {
  iota client new-address --json | jq -r '.address'
}

fund_with_faucet() {
  local addr="$1"
  switch_to "$addr"
  iota client faucet >/dev/null 2>&1 || true
  sleep 3
}

# Transfer IOTA from the current address. Prints the created coin's object ID.
transfer_iota() {
  local to="$1" amount="$2"
  local output
  output=$(iota client ptb \
    --split-coins gas "[$amount]" \
    --assign coin \
    --transfer-objects "[coin.0]" "@$to" \
    --json)
  echo "$output" | jq -r \
    '[.objectChanges[] | select(.type == "created") | select(.owner.AddressOwner == "'"$to"'")][0].objectId'
}

# ---------------------------------------------------------------------------
# Staking helpers
# ---------------------------------------------------------------------------

# Stake IOTA (split from gas) to a validator. Prints the StakedIota object ID.
stake_from_gas() {
  local validator="$1" amount="$2"
  local output
  output=$(iota client ptb \
    --split-coins gas "[$amount]" \
    --assign coin \
    --move-call 0x3::iota_system::request_add_stake @0x5 coin.0 "@$validator" \
    --json)
  echo "$output" | jq -r \
    '[.objectChanges[] | select(.objectType // "" | contains("StakedIota")) | select(.type == "created")][0].objectId'
}

# Stake a specific coin object to a validator. Prints the StakedIota object ID.
stake_coin() {
  local validator="$1" coin_id="$2"
  local output
  output=$(iota client ptb \
    --move-call 0x3::iota_system::request_add_stake @0x5 "@$coin_id" "@$validator" \
    --json)
  echo "$output" | jq -r \
    '[.objectChanges[] | select(.objectType // "" | contains("StakedIota")) | select(.type == "created")][0].objectId'
}

# ---------------------------------------------------------------------------
# Contract helpers
# ---------------------------------------------------------------------------

create_pool() {
  local target_validator="$1"
  local output
  output=$(iota client ptb \
    --move-call "${PACKAGE_ID}::candidate_stake::create" "@$target_validator" \
    --json)
  echo "$output" | jq -r \
    '[.objectChanges[] | select(.objectType // "" | contains("CandidateStake")) | select(.type == "created")][0].objectId'
}

deposit_to_pool() {
  local pool_id="$1" staked_iota_id="$2"
  iota client ptb \
    --move-call "${PACKAGE_ID}::candidate_stake::deposit" "@$pool_id" "@$staked_iota_id" \
    --json
}

withdraw_from_pool() {
  local pool_id="$1"
  iota client ptb \
    --move-call "${PACKAGE_ID}::candidate_stake::withdraw" "@$pool_id" \
    --json
}

execute_pool() {
  local pool_id="$1"
  iota client ptb \
    --move-call "${PACKAGE_ID}::candidate_stake::execute" "@$pool_id" @0x5 \
    --json
}

cancel_pool() {
  local pool_id="$1"
  iota client ptb \
    --move-call "${PACKAGE_ID}::candidate_stake::cancel" "@$pool_id" \
    --json
}

# Count StakedIota objectChanges owned by an address in a transaction output.
count_staked_for() {
  local tx_json="$1" addr="$2"
  echo "$tx_json" | jq \
    '[.objectChanges[] | select(.objectType // "" | contains("StakedIota")) | select(.owner.AddressOwner == "'"$addr"'")] | length'
}

# Count StakedIota objects owned by an address (via RPC query).
# Use this for withdraw/cancel where unwrapped objects don't appear in objectChanges.
count_owned_staked() {
  local addr="$1"
  iota client switch --address "$addr" >/dev/null 2>&1
  iota client objects --json 2>/dev/null \
    | jq '[.[] | select(.data.type // "" | contains("StakedIota"))] | length'
}
