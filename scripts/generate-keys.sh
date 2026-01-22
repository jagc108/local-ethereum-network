#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

KEYS_DIR="$ROOT_DIR/secrets/validator-keys"
PASSWORDS_DIR="$ROOT_DIR/secrets/validator-passwords"
OUTPUT_DIR="$ROOT_DIR/secrets/deposit-cli-output"

mkdir -p "$KEYS_DIR" "$PASSWORDS_DIR" "$OUTPUT_DIR"

VALUES_FILE="$ROOT_DIR/config/genesis/values.env"
if [[ -f "$VALUES_FILE" ]]; then
  set -a
  source "$VALUES_FILE"
  set +a
fi

NUM_VALIDATORS="${NUMBER_OF_VALIDATORS:-1}"
MNEMONIC_LANGUAGE="${DEPOSIT_CLI_LANGUAGE:-english}"
CHAIN_NAME="${DEPOSIT_CLI_CHAIN:-mainnet}"
IMAGE="${DEPOSIT_CLI_IMAGE:-ghcr.io/ethstaker/ethstaker-deposit-cli:latest}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to run the ethstaker-deposit-cli image."
  exit 1
fi

cat <<MSG
Running ethstaker-deposit-cli via Docker.
Note: For this local devnet, the deposit data is not used. We only need the keystores and passwords.

Validator count: $NUM_VALIDATORS
Language: $MNEMONIC_LANGUAGE
Chain name: $CHAIN_NAME

Output directory: $OUTPUT_DIR
MSG

docker pull "$IMAGE"

docker run -it --rm \
  -v "$OUTPUT_DIR:/app/validator_keys" \
  "$IMAGE" new-mnemonic \
  --num_validators="$NUM_VALIDATORS" \
  --mnemonic_language="$MNEMONIC_LANGUAGE" \
  --chain="$CHAIN_NAME"

# Move keystores and password files into expected locations
find "$OUTPUT_DIR" -type f -name 'keystore-*.json' -exec mv -n {} "$KEYS_DIR/" \;
find "$OUTPUT_DIR" -type f -name 'keystore-*.txt' -exec mv -n {} "$PASSWORDS_DIR/" \;

if ! find "$PASSWORDS_DIR" -type f -name 'keystore-*.txt' -print -quit | grep -q .; then
  cat <<MSG
No keystore password files were found.
Teku expects a password file per keystore in:
  $PASSWORDS_DIR

Create them using the same password you set in the CLI. Example:
  for f in $KEYS_DIR/keystore-*.json; do
    base=\$(basename "\$f" .json)
    printf '%s' '<YOUR_KEYSTORE_PASSWORD>' > "$PASSWORDS_DIR/\${base}.txt"
  done
MSG
fi

cat <<MSG
Moved keystores to: $KEYS_DIR
Moved passwords to: $PASSWORDS_DIR

Remember to copy the generated 24-word mnemonic into:
  $VALUES_FILE (EL_AND_CL_MNEMONIC)
MSG
