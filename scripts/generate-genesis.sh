#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VALUES_FILE="$ROOT_DIR/config/genesis/values.env"
OUTPUT_DIR="$ROOT_DIR/genesis-output"

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Missing $VALUES_FILE"
  echo "Copy the example and fill in required values:"
  echo "  cp $ROOT_DIR/config/genesis/values.env.example $VALUES_FILE"
  exit 1
fi

GENESIS_TIMESTAMP=${GENESIS_TIMESTAMP:-$(date +%s)}

mkdir -p "$OUTPUT_DIR"

# Generate EL + CL genesis artifacts
# Ref: https://github.com/ethpandaops/ethereum-genesis-generator

docker run --rm -u "$(id -u)" \
  -v "$OUTPUT_DIR:/data" \
  -v "$ROOT_DIR/config/genesis:/config" \
  -e GENESIS_TIMESTAMP="$GENESIS_TIMESTAMP" \
  ethpandaops/ethereum-genesis-generator:master all

# Sync outputs into client config directories
cp "$OUTPUT_DIR/metadata/chainspec.json" "$ROOT_DIR/config/nethermind/chainspec.json"
cp "$OUTPUT_DIR/metadata/genesis.json" "$ROOT_DIR/config/nethermind/genesis.json"
cp "$OUTPUT_DIR/metadata/genesis.ssz" "$ROOT_DIR/config/teku/genesis.ssz"
cp "$OUTPUT_DIR/metadata/config.yaml" "$ROOT_DIR/config/teku/config.yaml"

# Configure Bellatrix transition using terminal block hash (Teku no longer supports TTD).
PARSED_GENESIS="$OUTPUT_DIR/parsed/parsedConsensusGenesis.json"
if [[ -f "$PARSED_GENESIS" ]]; then
  TERMINAL_BLOCK_HASH=$(python3 - <<'PY'
import json
with open("genesis-output/parsed/parsedConsensusGenesis.json", "r") as f:
    data = json.load(f)
print(data["latest_execution_payload_header"]["block_hash"])
PY
  )

  python3 - <<PY
from pathlib import Path
cfg_path = Path("config/teku/config.yaml")
lines = cfg_path.read_text().splitlines()

def set_value(key, value):
    for i, line in enumerate(lines):
        if line.startswith(f"{key}:"):
            lines[i] = f"{key}: {value}"
            return True
    lines.append(f"{key}: {value}")
    return False

set_value("TERMINAL_BLOCK_HASH", "$TERMINAL_BLOCK_HASH")
set_value("TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH", "0")
cfg_path.write_text("\\n".join(lines) + "\\n")
PY
fi

cat <<MSG
Genesis artifacts synced:
- config/nethermind/chainspec.json
- config/nethermind/genesis.json
- config/teku/genesis.ssz
- config/teku/config.yaml
MSG
