#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VALUES_FILE="$ROOT_DIR/config/genesis/values.env"

RPC_URL="${EL_RPC_URL:-http://localhost:8545}"
TX_RPC_URL="${TX_RPC_URL:-$RPC_URL}"
TX_VALUE="${TX_VALUE:-1wei}"
FROM_INDEX="${MNEMONIC_INDEX_FROM:-0}"
TO_INDEX="${MNEMONIC_INDEX_TO:-1}"
TX_CONFIRMATIONS="${TX_CONFIRMATIONS:-1}"
TX_TIMEOUT="${TX_TIMEOUT:-60}"
TX_RETRIES="${TX_RETRIES:-3}"
TX_RETRY_SLEEP="${TX_RETRY_SLEEP:-3}"
TX_LEGACY="${TX_LEGACY:-0}"
TX_NONCE="${TX_NONCE:-}"
RECEIPT_TIMEOUT="${TX_RECEIPT_TIMEOUT:-60}"
RECEIPT_POLL="${TX_RECEIPT_POLL:-2}"

if ! command -v cast >/dev/null 2>&1; then
  echo "ERROR: cast (Foundry) is required for this script."
  exit 1
fi

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "ERROR: $VALUES_FILE not found."
  exit 1
fi

set -a
source "$VALUES_FILE"
set +a

if [[ -z "${EL_AND_CL_MNEMONIC:-}" || "${EL_AND_CL_MNEMONIC}" == "<REPLACE_WITH_24_WORD_MNEMONIC>" ]]; then
  echo "ERROR: EL_AND_CL_MNEMONIC is missing or placeholder in $VALUES_FILE."
  exit 1
fi

from_pk="$(cast wallet private-key "$EL_AND_CL_MNEMONIC" "$FROM_INDEX" | tr -d '\n')"
to_pk="$(cast wallet private-key "$EL_AND_CL_MNEMONIC" "$TO_INDEX" | tr -d '\n')"

from_addr="$(cast wallet address --private-key "$from_pk" | tr -d '\n')"
to_addr="$(cast wallet address --private-key "$to_pk" | tr -d '\n')"

echo "Sending test tx:"
echo "- From index: $FROM_INDEX ($from_addr)"
echo "- To index:   $TO_INDEX ($to_addr)"
echo "- Value:      $TX_VALUE"
echo "- RPC:        $RPC_URL"
if [[ "$TX_RPC_URL" != "$RPC_URL" ]]; then
  echo "- TX RPC:     $TX_RPC_URL"
fi
echo "- Confirmations: $TX_CONFIRMATIONS"
echo "- Timeout:       ${TX_TIMEOUT}s"

from_before="$(cast balance "$from_addr" --rpc-url "$RPC_URL" 2>/dev/null || true)"
to_before="$(cast balance "$to_addr" --rpc-url "$RPC_URL" 2>/dev/null || true)"

hex_to_int() {
  python3 -c 'import sys
h=sys.stdin.read().strip()
try:
    print(int(h, 16))
except Exception:
    print("")'
}

get_nonce() {
  if [[ -n "$TX_NONCE" ]]; then
    echo "$TX_NONCE"
    return 0
  fi
  local nonce_hex=""
  local cast_out=""
  if [[ "${TX_FORCE_CURL:-0}" != "1" ]]; then
    cast_out="$(cast rpc eth_getTransactionCount "$from_addr" "pending" --rpc-url "$TX_RPC_URL" 2>/dev/null | tr -d '\r' | head -n 1 || true)"
    if [[ "${TX_DEBUG:-}" == "1" ]]; then
      echo "DEBUG: nonce cast rpc: $cast_out" >&2
    fi
    if [[ "$cast_out" =~ ^0x[0-9a-fA-F]+$ ]]; then
      nonce_hex="$cast_out"
    else
      nonce_hex=""
    fi
  fi
  if [[ -z "$nonce_hex" ]]; then
    resp="$(curl -s -H "Content-Type: application/json" \
      --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionCount\",\"params\":[\"$from_addr\",\"pending\"]}" \
      "$TX_RPC_URL" || true)"
    if [[ "${TX_DEBUG:-}" == "1" ]]; then
      echo "DEBUG: nonce RPC raw: $resp" >&2
    fi
    nonce_hex="$(python3 -c 'import json,sys,re
data=sys.stdin.read()
try:
  obj=json.loads(data)
  print(obj.get("result",""))
except Exception:
  m=re.search(r"0x[0-9a-fA-F]+", data)
  print(m.group(0) if m else "")' <<<"$resp" || true)"
    if [[ ! "$nonce_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then
      nonce_hex=""
    fi
  fi
  if [[ -z "$nonce_hex" ]]; then
    if [[ "${TX_DEBUG:-}" == "1" ]]; then
      echo "DEBUG: failed to fetch nonce from RPC at $TX_RPC_URL" >&2
    fi
    echo ""
    return 0
  fi
  printf '%s' "$nonce_hex" | hex_to_int
}

send_tx() {
  local nonce="$1"
  local tx_hash=""
  if [[ "$TX_LEGACY" == "1" ]]; then
    tx_hash="$(cast send "$to_addr" \
      --value "$TX_VALUE" \
      --private-key "$from_pk" \
      --rpc-url "$TX_RPC_URL" \
      --async \
      --timeout "$TX_TIMEOUT" \
      --nonce "$nonce" \
      --legacy | tr -d '\r' | tail -n 1)"
  else
    tx_hash="$(cast send "$to_addr" \
      --value "$TX_VALUE" \
      --private-key "$from_pk" \
      --rpc-url "$TX_RPC_URL" \
      --async \
      --timeout "$TX_TIMEOUT" \
      --nonce "$nonce" | tr -d '\r' | tail -n 1)"
  fi

  tx_hash="$(printf '%s' "$tx_hash" | tr -d ' ')"
  if [[ ! "$tx_hash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "ERROR: failed to get tx hash from cast."
    return 1
  fi

  if [[ "${TX_DEBUG:-}" == "1" ]]; then
    echo "DEBUG: tx hash: $tx_hash" >&2
  fi

  # Poll receipt until mined or timeout
  local elapsed=0
  while [[ "$elapsed" -lt "$RECEIPT_TIMEOUT" ]]; do
    receipt="$(curl -s -H "Content-Type: application/json" \
      --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$tx_hash\"]}" \
      "$TX_RPC_URL" || true)"
    block_hex="$(python3 -c 'import json,sys
data=sys.stdin.read()
try:
  obj=json.loads(data)
  res=obj.get("result")
  print(res.get("blockNumber","") if isinstance(res,dict) else "")
except Exception:
  print("")' <<<"$receipt")"
    if [[ -n "$block_hex" && "$block_hex" != "null" ]]; then
      return 0
    fi
    sleep "$RECEIPT_POLL"
    elapsed=$((elapsed + RECEIPT_POLL))
  done

  echo "Error: transaction was not confirmed within the timeout"
  return 1
}

attempt=1
base_nonce="$(get_nonce)"
if [[ -z "$base_nonce" ]]; then
  echo "ERROR: unable to fetch nonce for $from_addr"
  exit 1
fi

while true; do
  nonce="$((base_nonce + attempt - 1))"
  if send_tx "$nonce"; then
    break
  fi
  if [[ "$attempt" -ge "$TX_RETRIES" ]]; then
    echo "ERROR: transaction was not confirmed after ${TX_RETRIES} attempts."
    exit 1
  fi
  echo "WARN: transaction not confirmed, retrying in ${TX_RETRY_SLEEP}s..."
  sleep "$TX_RETRY_SLEEP"
  attempt=$((attempt+1))
done

from_after="$(cast balance "$from_addr" --rpc-url "$RPC_URL" 2>/dev/null || true)"
to_after="$(cast balance "$to_addr" --rpc-url "$RPC_URL" 2>/dev/null || true)"

echo "From balance before: ${from_before:-unknown}"
echo "From balance after:  ${from_after:-unknown}"
echo "To balance before:   ${to_before:-unknown}"
echo "To balance after:    ${to_after:-unknown}"

echo "Historical balance at block 0:"
hist_hex="$(cast rpc eth_getBalance "$to_addr" "0x0" --rpc-url "$RPC_URL" 2>/dev/null | tr -d '\r' | head -n 1 | tr -d '"' || true)"
if [[ -n "$hist_hex" ]]; then
  hist_dec="$(printf '%s' "$hist_hex" | hex_to_int)"
  echo "$hist_hex ($hist_dec)"
else
  echo "unknown"
fi
