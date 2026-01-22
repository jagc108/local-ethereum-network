#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

RPC_URL="${EL_RPC_URL:-http://localhost:8545}"
SLEEP_SECS="${POST_CHECK_SLEEP:-15}"

warn_count=0
err_count=0

log() { echo "$@"; }
warn() { echo "WARN: $*" >&2; warn_count=$((warn_count+1)); }
fail() { echo "ERROR: $*" >&2; err_count=$((err_count+1)); }

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required for RPC checks."
  exit 1
fi

rpc_result() {
  local method="$1"
  local params="${2:-[]}"
  local retries="${RPC_RETRIES:-3}"
  local retry_sleep="${RPC_RETRY_SLEEP:-2}"
  local timeout="${RPC_TIMEOUT:-3}"
  local attempt=1
  local resp=""

  while true; do
    resp="$(curl -s --max-time "$timeout" -H "Content-Type: application/json" \
      --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${method}\",\"params\":${params}}" \
      "$RPC_URL" || true)"

    if [[ -n "$resp" ]]; then
      if [[ "${RPC_DEBUG:-}" == "1" ]]; then
        echo "rpc_result raw: $resp" >&2
      fi
      python3 -c 'import json,sys
data=sys.stdin.read()
try:
    obj=json.loads(data)
except Exception:
    print("")
    sys.exit(0)
if isinstance(obj, dict):
    print(obj.get("result",""))
else:
    print(obj)' <<<"$resp"
      return 0
    fi

    if [[ "$attempt" -ge "$retries" ]]; then
      echo ""
      return 0
    fi

    sleep "$retry_sleep"
    attempt=$((attempt+1))
  done
}

hex_to_int() {
  python3 -c 'import sys
h=sys.stdin.read().strip()
try:
    print(int(h, 16))
except Exception:
    print("")'
}

log "Post-start checks (RPC: $RPC_URL)"

bn1_hex="$(rpc_result eth_blockNumber "[]")"
if [[ -z "$bn1_hex" ]]; then
  fail "eth_blockNumber failed (RPC not reachable?)"
else
  bn1_dec="$(printf '%s' "$bn1_hex" | hex_to_int)"
  log "eth_blockNumber (t0): $bn1_hex ($bn1_dec)"
fi

sleep "$SLEEP_SECS"

bn2_hex="$(rpc_result eth_blockNumber "[]")"
if [[ -z "$bn2_hex" ]]; then
  fail "eth_blockNumber failed on second read."
else
  bn2_dec="$(printf '%s' "$bn2_hex" | hex_to_int)"
  log "eth_blockNumber (t1): $bn2_hex ($bn2_dec)"
  if [[ -n "$bn1_dec" && -n "$bn2_dec" ]]; then
    if [[ "$bn2_dec" -gt "$bn1_dec" ]]; then
      log "OK: block number is increasing."
    else
      warn "Block number did not increase (check validator/EL connection)."
    fi
  fi
fi

peer_hex="$(rpc_result net_peerCount "[]")"
if [[ -n "$peer_hex" ]]; then
  peer_dec="$(printf '%s' "$peer_hex" | hex_to_int)"
  log "net_peerCount: $peer_hex ($peer_dec)"
else
  warn "net_peerCount failed."
fi

syncing="$(rpc_result eth_syncing "[]")"
if [[ -n "$syncing" ]]; then
  if [[ "$syncing" == "false" || "$syncing" == "False" ]]; then
    log "eth_syncing: $syncing (OK)"
  else
    warn "eth_syncing: $syncing (still syncing)"
  fi
fi

if [[ -n "${TX_PRIVATE_KEY:-}" || -n "${TX_TO:-}" ]]; then
  if ! command -v cast >/dev/null 2>&1; then
    warn "cast not found; skipping TX balance change check."
  elif [[ -z "${TX_PRIVATE_KEY:-}" || -z "${TX_TO:-}" ]]; then
    warn "TX_PRIVATE_KEY and TX_TO must both be set to run TX balance change check."
  else
    tx_value="${TX_VALUE:-1wei}"
    log "Sending test tx with cast (value: $tx_value)."
    bal_before="$(rpc_result eth_getBalance "[\"$TX_TO\",\"latest\"]")"
    cast send "$TX_TO" --value "$tx_value" --private-key "$TX_PRIVATE_KEY" --rpc-url "$RPC_URL" --confirmations 1 >/dev/null 2>&1 || true
    sleep 2
    bal_after="$(rpc_result eth_getBalance "[\"$TX_TO\",\"latest\"]")"
    if [[ -n "$bal_before" && -n "$bal_after" ]]; then
      bal_before_dec="$(printf '%s' "$bal_before" | hex_to_int)"
      bal_after_dec="$(printf '%s' "$bal_after" | hex_to_int)"
      if [[ -n "$bal_before_dec" && -n "$bal_after_dec" && "$bal_after_dec" -gt "$bal_before_dec" ]]; then
        log "OK: balance increased after test tx."
      else
        warn "Balance did not increase after test tx."
      fi
    else
      warn "Unable to read balances for TX_TO."
    fi
  fi
fi

alloc_addr="$(python3 - <<PY
import json, pathlib
path = pathlib.Path("$ROOT_DIR/config/nethermind/genesis.json")
if not path.exists():
    print("")
    raise SystemExit(0)
data = json.loads(path.read_text())
alloc = data.get("alloc", {})
for k in alloc.keys():
    print(k)
    break
PY
)"

if [[ -n "$alloc_addr" ]]; then
  bal0="$(rpc_result eth_getBalance "[\"$alloc_addr\",\"0x0\"]")"
  ballatest="$(rpc_result eth_getBalance "[\"$alloc_addr\",\"latest\"]")"
  if [[ -n "$bal0" ]]; then
    log "eth_getBalance (block 0) for $alloc_addr: $bal0"
  else
    warn "Historical balance query at block 0 failed."
  fi
  if [[ -n "$ballatest" ]]; then
    log "eth_getBalance (latest) for $alloc_addr: $ballatest"
  fi
else
  warn "No alloc address found in config/nethermind/genesis.json (skipping historical check)."
fi

if command -v rg >/dev/null 2>&1; then
  if rg -q "^p2p-static-peers:" "$ROOT_DIR/config/teku/validator.yaml" "$ROOT_DIR/config/teku/archive.yaml"; then
    log "OK: p2p-static-peers set in Teku configs."
  else
    warn "p2p-static-peers not found in Teku configs."
  fi
else
  if grep -q "^p2p-static-peers:" "$ROOT_DIR/config/teku/validator.yaml" "$ROOT_DIR/config/teku/archive.yaml"; then
    log "OK: p2p-static-peers set in Teku configs."
  else
    warn "p2p-static-peers not found in Teku configs."
  fi
fi

if [[ "$err_count" -gt 0 ]]; then
  exit 1
fi

if [[ "$warn_count" -gt 0 ]]; then
  exit 0
fi
