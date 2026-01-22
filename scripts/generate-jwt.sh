#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JWT_FILE="$ROOT_DIR/secrets/jwt.hex"

mkdir -p "$ROOT_DIR/secrets"

if [[ -f "$JWT_FILE" ]]; then
  echo "JWT secret already exists: $JWT_FILE"
  exit 0
fi

openssl rand -hex 32 > "$JWT_FILE"
chmod 600 "$JWT_FILE"

echo "Wrote JWT secret to $JWT_FILE"
