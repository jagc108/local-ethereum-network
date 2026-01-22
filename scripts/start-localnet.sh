#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

VALUES_FILE="$ROOT_DIR/config/genesis/values.env"
VALUES_EXAMPLE="$ROOT_DIR/config/genesis/values.env.example"
KEYS_DIR="$ROOT_DIR/secrets/validator-keys"
PASSWORDS_DIR="$ROOT_DIR/secrets/validator-passwords"

load_values() {
  if [[ -f "$VALUES_FILE" ]]; then
    set -a
    source "$VALUES_FILE"
    set +a
  fi
}

ensure_values_file() {
  if [[ ! -f "$VALUES_FILE" ]]; then
    cp "$VALUES_EXAMPLE" "$VALUES_FILE"
    echo "Created $VALUES_FILE from example."
  fi
}

ensure_password_files() {
  local missing=0
  if compgen -G "$KEYS_DIR/keystore-*.json" > /dev/null; then
    for f in "$KEYS_DIR"/keystore-*.json; do
      local base
      base="$(basename "$f" .json)"
      if [[ ! -f "$PASSWORDS_DIR/$base.txt" ]]; then
        missing=1
      fi
    done
  fi

  if [[ "$missing" -ne 0 ]]; then
    cat <<MSG
Missing keystore password files in:
  $PASSWORDS_DIR

Create one .txt per keystore using the same password you set in generate-keys.sh.
Example:
  for f in $KEYS_DIR/keystore-*.json; do
    base=\$(basename "\$f" .json)
    printf '%s' '<YOUR_KEYSTORE_PASSWORD>' > "$PASSWORDS_DIR/\${base}.txt"
  done
MSG
    exit 1
  fi
}

ensure_mnemonic() {
  load_values
  local placeholder="<REPLACE_WITH_24_WORD_MNEMONIC>"
  if [[ -z "${EL_AND_CL_MNEMONIC:-}" || "${EL_AND_CL_MNEMONIC}" == "$placeholder" ]]; then
    if compgen -G "$KEYS_DIR/keystore-*.json" > /dev/null; then
      cat <<MSG
EL_AND_CL_MNEMONIC is missing, but validator keys already exist.
Paste the mnemonic used for those keys into:
  $VALUES_FILE
Or wipe and start fresh:
  ./scripts/clean-localnet.sh --force
MSG
    else
      echo "EL_AND_CL_MNEMONIC is missing. Running ./scripts/generate-keys.sh..."
      "$ROOT_DIR/scripts/generate-keys.sh"
      cat <<MSG
Copy the 24-word mnemonic into:
  $VALUES_FILE
Then rerun this script.
MSG
    fi
    exit 1
  fi

  if ! compgen -G "$KEYS_DIR/keystore-*.json" > /dev/null; then
    cat <<MSG
EL_AND_CL_MNEMONIC is set, but no validator keys were found.
Run ./scripts/generate-keys.sh to create keys, then update:
  $VALUES_FILE
with the new mnemonic (overwriting the existing value), and rerun.
MSG
    exit 1
  fi
}

ensure_values_file

ensure_mnemonic
ensure_password_files

echo "Generating genesis artifacts..."
"$ROOT_DIR/scripts/generate-genesis.sh"

echo "Generating JWT secret..."
"$ROOT_DIR/scripts/generate-jwt.sh"

echo "Starting containers..."
docker compose up -d

WIRE_PEERS_START_DELAY="${WIRE_PEERS_START_DELAY:-45}"
echo "Waiting ${WIRE_PEERS_START_DELAY}s for Teku to log peer IDs..."
sleep "$WIRE_PEERS_START_DELAY"

echo "Wiring Teku static peers..."
LOG_FILE="$ROOT_DIR/docker-compose.logs"
docker compose logs teku-validator teku-archive > "$LOG_FILE" 2>/dev/null || true
WIRE_PEERS_LOG_FILE="$LOG_FILE" "$ROOT_DIR/scripts/wire-peers.sh" || {
  cat <<MSG
Wire peers failed. You can retry manually:
  docker compose logs teku-validator teku-archive > $LOG_FILE
  WIRE_PEERS_LOG_FILE=$LOG_FILE $ROOT_DIR/scripts/wire-peers.sh

If peers are set but services didn't restart:
  docker compose restart teku-validator teku-archive
MSG
  exit 1
}

cat <<MSG
Local Ethereum network started.
Check:
  docker compose logs -f teku-validator
  docker compose logs -f nethermind-archive
Run post-start checks after 30-60s:
  ./scripts/post-start-checks.sh
MSG
