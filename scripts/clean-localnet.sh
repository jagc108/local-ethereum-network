#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

confirm() {
  local reply=""
  cat <<MSG
This will stop containers and delete generated artifacts and secrets:
- data/
- genesis-output/
- config/nethermind/genesis.json
- config/nethermind/chainspec.json
- config/teku/genesis.ssz
- config/teku/config.yaml
- secrets/jwt.hex
- secrets/validator-keys/*
- secrets/validator-passwords/*
- secrets/deposit-cli-output/*
- config/genesis/values.env

Continue? [y/N]
MSG
  read -r reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
}

if [[ "${1:-}" != "--force" ]]; then
  confirm
fi

docker compose down --remove-orphans >/dev/null 2>&1 || true

rm -rf "$ROOT_DIR/data" "$ROOT_DIR/genesis-output"

rm -f \
  "$ROOT_DIR/config/nethermind/genesis.json" \
  "$ROOT_DIR/config/nethermind/chainspec.json" \
  "$ROOT_DIR/config/teku/genesis.ssz" \
  "$ROOT_DIR/config/teku/config.yaml" \
  "$ROOT_DIR/secrets/jwt.hex" \
  "$ROOT_DIR/config/genesis/values.env" \
  "$ROOT_DIR/docker-compose.logs"

for dir in \
  "$ROOT_DIR/secrets/validator-keys" \
  "$ROOT_DIR/secrets/validator-passwords" \
  "$ROOT_DIR/secrets/deposit-cli-output"
do
  if [[ -d "$dir" ]]; then
    find "$dir" -type f ! -name 'README.md' ! -name '.gitkeep' -delete
  fi
done

echo "Clean complete."
