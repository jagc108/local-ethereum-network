#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LOCK_DIR="$ROOT_DIR/secrets/validator-keys"

compose_logs() {
  local service="$1"
  local mode="${2:-tail}"
  local since="${WIRE_PEERS_LOG_SINCE:-30m}"
  local tail="${WIRE_PEERS_LOG_TAIL:-2000}"

  if [[ "$mode" == "full" ]]; then
    docker compose logs --no-color "$service" 2>&1 \
      || docker compose logs "$service" 2>&1 \
      || {
        local cid=""
        cid="$(docker compose ps -q "$service" 2>/dev/null || true)"
        if [[ -n "$cid" ]]; then
          docker logs "$cid" 2>&1 || true
        fi
      }
    return 0
  fi

  docker compose logs --no-color --since "$since" --tail "$tail" "$service" 2>&1 \
    || docker compose logs --since "$since" --tail "$tail" "$service" 2>&1 \
    || docker compose logs --no-color "$service" 2>&1 \
    || docker compose logs "$service" 2>&1 \
    || {
      local cid=""
      cid="$(docker compose ps -q "$service" 2>/dev/null || true)"
      if [[ -n "$cid" ]]; then
        docker logs --since "$since" --tail "$tail" "$cid" 2>&1 \
          || docker logs --tail "$tail" "$cid" 2>&1 \
          || true
      fi
    }
}

get_peer_id() {
  local service="$1"
  local id=""
  local log_file=""
  local tmp_file=""
  local from_file=0

  parse_peer_id_file() {
    python3 - "$service" "$log_file" <<'PY'
import os, re, sys
service = sys.argv[1]
path = sys.argv[2]
data = open(path, "rb").read()
log = data.decode("utf-8", errors="ignore")
log = re.sub(r"\x1b\[[0-9;]*m", "", log)
lines = log.splitlines()
if service:
    lines = [ln for ln in lines if service in ln]
log = "\n".join(lines)
# Prefer IDs from the "Listening for connections" line.
peers = re.findall(r"Listening for connections on: .*?/p2p/([A-Za-z0-9]+)", log)
if not peers:
    peers = re.findall(r"/p2p/([A-Za-z0-9]+)", log)
if os.getenv("WIRE_PEERS_DEBUG") == "1":
    sys.stderr.write(f"wire-peers: regex matches={len(peers)}\n")
if not peers:
    sys.exit(1)
print(peers[-1])
PY
  }

  if [[ -n "${WIRE_PEERS_LOG_FILE:-}" && -f "${WIRE_PEERS_LOG_FILE}" ]]; then
    log_file="$WIRE_PEERS_LOG_FILE"
    from_file=1
  else
    tmp_file="$(mktemp)"
    log_file="$tmp_file"
    compose_logs "$service" > "$log_file" || true
  fi

  if [[ "${WIRE_PEERS_DEBUG:-}" == "1" ]]; then
    echo "wire-peers: collected $(wc -c <"$log_file" | tr -d ' ') bytes for $service" >&2
  fi
  if [[ "${WIRE_PEERS_DEBUG:-}" == "1" ]]; then
    id="$(parse_peer_id_file || true)"
  else
    id="$(parse_peer_id_file 2>/dev/null || true)"
  fi

  if [[ -z "$id" && "$from_file" -eq 0 ]]; then
    compose_logs "$service" full > "$log_file" || true
    if [[ "${WIRE_PEERS_DEBUG:-}" == "1" ]]; then
      echo "wire-peers: fallback to full logs for $service ($(wc -c <"$log_file" | tr -d ' ') bytes)" >&2
    fi
    if [[ "${WIRE_PEERS_DEBUG:-}" == "1" ]]; then
      id="$(parse_peer_id_file || true)"
    else
      id="$(parse_peer_id_file 2>/dev/null || true)"
    fi
  fi

  if [[ -n "$tmp_file" ]]; then
    rm -f "$tmp_file"
  fi

  if [[ -z "$id" ]]; then
    return 1
  fi

  echo "$id"
}

wait_for_peer_id() {
  local service="$1"
  local tries="${2:-30}"
  local delay="${3:-2}"
  local id=""

  for i in $(seq 1 "$tries"); do
    id=$(get_peer_id "$service" || true)
    if [[ -n "$id" ]]; then
      echo "$id"
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

set_peer_config() {
  local file="$1"
  local peer_addr="$2"
  python3 - "$file" "$peer_addr" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
peer_addr = sys.argv[2]
lines = path.read_text().splitlines()
key = "p2p-static-peers:"
peer_line = f'  - "{peer_addr}"'

out = []
found = False
skip = False
for line in lines:
    if line.startswith(key):
        out.append(key)
        out.append(peer_line)
        found = True
        skip = True
        continue
    if skip:
        if line.startswith("  -") or line.strip() == "":
            continue
        skip = False
    out.append(line)

if not found:
    out.append("")
    out.append(key)
    out.append(peer_line)

path.write_text("\n".join(out) + "\n")
PY
}

validator_peer="${TEKU_VALIDATOR_PEER_ID:-}"
archive_peer="${TEKU_ARCHIVE_PEER_ID:-}"

if [[ -z "${validator_peer}" ]]; then
  validator_peer=$(wait_for_peer_id teku-validator || true)
fi

if [[ -z "${archive_peer}" ]]; then
  archive_peer=$(wait_for_peer_id teku-archive || true)
fi

if [[ -z "${validator_peer}" || -z "${archive_peer}" ]]; then
  cat <<MSG
Unable to extract peer IDs. Ensure the containers are running and have logged
"Listening for connections on: /ip4/.../tcp/9000/p2p/<PEER_ID>".

Try:
  docker compose up -d
  docker compose logs teku-validator | tail -n 50
  docker compose logs teku-archive   | tail -n 50
MSG
  exit 1
fi

if [[ "${WIRE_PEERS_DRY_RUN:-}" == "1" ]]; then
  echo "validator_peer=$validator_peer"
  echo "archive_peer=$archive_peer"
  exit 0
fi

cleanup_validator_locks() {
  if compgen -G "$LOCK_DIR/*.lock" > /dev/null; then
    echo "Found validator lock files. Stopping teku-validator to clear them..."
    docker compose stop teku-validator >/dev/null 2>&1 || true
    rm -f "$LOCK_DIR"/*.lock || true
  fi
}

set_peer_config "$ROOT_DIR/config/teku/validator.yaml" "/dns4/teku-archive/tcp/9000/p2p/${archive_peer}"
set_peer_config "$ROOT_DIR/config/teku/archive.yaml" "/dns4/teku-validator/tcp/9000/p2p/${validator_peer}"

cat <<MSG
Wired static peers:
- validator -> /dns4/teku-archive/tcp/9000/p2p/${archive_peer}
- archive   -> /dns4/teku-validator/tcp/9000/p2p/${validator_peer}

Restarting Teku services...
MSG

if [[ "${WIRE_PEERS_NO_RESTART:-}" == "1" ]]; then
  echo "Skipping restart (WIRE_PEERS_NO_RESTART=1)."
  exit 0
fi

cleanup_validator_locks

if ! docker compose restart teku-validator teku-archive; then
  cat <<MSG
WARN: Unable to restart Teku services (Docker permissions or daemon not running).
Please run manually:
  docker compose restart teku-validator teku-archive
MSG
  exit 0
fi
