#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: check_sync.sh [options]

Options:
  --container NAME         Docker container name or ID to run curl/jq within
  --compose-service NAME   Docker Compose service name to resolve to a container
  --local-rpc URL          Local Aptos REST endpoint (default: http://127.0.0.1:${API_PORT:-8080}/v1)
  --public-rpc URL         Public/reference Aptos REST endpoint (default: https://api.mainnet.aptoslabs.com/v1)
  --block-lag N            Acceptable lag in blocks (default: 2)
  --env-file PATH          Path to env file to load (default: .env if present)
  --no-install             Do not install curl/jq inside the container
  -h, --help               Show this help

Examples:
  ./scripts/check_sync.sh
  ./scripts/check_sync.sh --public-rpc https://api.mainnet.aptoslabs.com/v1
  ./scripts/check_sync.sh --compose-service aptos --public-rpc https://api.mainnet.aptoslabs.com/v1
  CONTAINER=aptos-1 ./scripts/check_sync.sh
USAGE
}

DEFAULT_ENV_FILE=".env"
DEFAULT_PUBLIC_RPC="https://api.mainnet.aptoslabs.com/v1"
DEFAULT_BLOCK_LAG_THRESHOLD="2"

ENV_FILE="${ENV_FILE:-}"
CONTAINER="${CONTAINER:-}"
DOCKER_SERVICE="${DOCKER_SERVICE:-}"
LOCAL_RPC="${LOCAL_RPC:-}"
PUBLIC_RPC="${PUBLIC_RPC:-}"
BLOCK_LAG_THRESHOLD="${BLOCK_LAG_THRESHOLD:-$DEFAULT_BLOCK_LAG_THRESHOLD}"
INSTALL_TOOLS="${INSTALL_TOOLS:-1}"

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line#export }"
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      local key="${line%%=*}"
      local val="${line#*=}"
      val="${val#"${val%%[![:space:]]*}"}"
      if [[ "$val" =~ ^\".*\"$ ]]; then
        val="${val:1:-1}"
      elif [[ "$val" =~ ^\'.*\'$ ]]; then
        val="${val:1:-1}"
      fi
      printf -v "$key" '%s' "$val"
      export "${key?}"
    fi
  done < "$file"
}

args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "--env-file" ]]; then
    ENV_FILE="${args[$((i+1))]:-}"
  fi
done

if [[ -n "$ENV_FILE" ]]; then
  load_env_file "$ENV_FILE"
elif [[ -f "$DEFAULT_ENV_FILE" ]]; then
  load_env_file "$DEFAULT_ENV_FILE"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)
      [[ $# -ge 2 ]] || { echo "Missing value for --container"; usage; exit 2; }
      CONTAINER="$2"
      shift 2
      ;;
    --compose-service)
      [[ $# -ge 2 ]] || { echo "Missing value for --compose-service"; usage; exit 2; }
      DOCKER_SERVICE="$2"
      shift 2
      ;;
    --local-rpc)
      [[ $# -ge 2 ]] || { echo "Missing value for --local-rpc"; usage; exit 2; }
      LOCAL_RPC="$2"
      shift 2
      ;;
    --public-rpc)
      [[ $# -ge 2 ]] || { echo "Missing value for --public-rpc"; usage; exit 2; }
      PUBLIC_RPC="$2"
      shift 2
      ;;
    --block-lag)
      [[ $# -ge 2 ]] || { echo "Missing value for --block-lag"; usage; exit 2; }
      BLOCK_LAG_THRESHOLD="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --env-file"; usage; exit 2; }
      ENV_FILE="$2"
      shift 2
      ;;
    --no-install)
      INSTALL_TOOLS="0"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

normalize_rpc_base() {
  local rpc="${1%/}"
  if [[ "$rpc" =~ /v1$ ]]; then
    printf '%s' "$rpc"
  else
    printf '%s/v1' "$rpc"
  fi
}

LOCAL_RPC="${LOCAL_RPC:-http://127.0.0.1:${API_PORT:-8080}/v1}"
PUBLIC_RPC="${PUBLIC_RPC:-$DEFAULT_PUBLIC_RPC}"
LOCAL_RPC="$(normalize_rpc_base "$LOCAL_RPC")"
PUBLIC_RPC="$(normalize_rpc_base "$PUBLIC_RPC")"

jq_eval() {
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" jq -r "$1"
  else
    jq -r "$1"
  fi
}

http_get() {
  local base="$1"
  local path="$2"
  local url="${base%/}${path}"
  if [[ -n "$CONTAINER" ]]; then
    docker exec "$CONTAINER" sh -c "curl -sS --fail --max-time 10 '$url' 2>/dev/null"
  else
    curl -sS --fail --max-time 10 "$url" 2>/dev/null
  fi
}

print_final_status() {
  local status="$1"
  case "$status" in
    in_sync)
      echo "✅ Final status: in sync"
      ;;
    syncing)
      echo "⏳ Final status: syncing"
      ;;
    *)
      echo "❌ Final status: error"
      ;;
  esac
}

fail_sync() {
  local msg="$1"
  echo "❌ error: $msg"
  echo
  print_final_status "error"
  exit 2
}

resolve_container_error=""
resolve_container() {
  if [[ -n "$CONTAINER" || -z "$DOCKER_SERVICE" ]]; then
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    resolve_container_error="docker not found; cannot resolve --compose-service ${DOCKER_SERVICE}"
    return 1
  fi
  if docker compose version >/dev/null 2>&1; then
    CONTAINER="$(docker compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  elif command -v docker-compose >/dev/null 2>&1; then
    CONTAINER="$(docker-compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  else
    resolve_container_error="docker compose not available; cannot resolve --compose-service ${DOCKER_SERVICE}"
    return 1
  fi
  if [[ -z "$CONTAINER" ]]; then
    resolve_container_error="no running container found for compose service ${DOCKER_SERVICE}"
    return 1
  fi
}

echo "⏳ Checking tools inside container"
if ! resolve_container; then
  fail_sync "$resolve_container_error"
fi

if [[ -n "$CONTAINER" ]]; then
  if ! docker exec "$CONTAINER" sh -c "command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1"; then
    if [[ "$INSTALL_TOOLS" == "1" ]]; then
      if ! docker exec -u root "$CONTAINER" sh -c '
        set -e
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update -y
          apt-get install -y curl jq ca-certificates
        elif command -v apk >/dev/null 2>&1; then
          apk add --no-cache curl jq ca-certificates
        else
          exit 1
        fi
      '; then
        fail_sync "failed to install curl/jq inside container"
      fi
    else
      fail_sync "curl/jq not found in container and --no-install set"
    fi
  fi
else
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    fail_sync "curl and jq are required on the host when no --container is set"
  fi
fi

if [[ ! "$BLOCK_LAG_THRESHOLD" =~ ^[0-9]+$ ]]; then
  fail_sync "--block-lag must be a non-negative integer"
fi

echo "✅ Tools available in container"
echo

if ! local_ledger="$(http_get "$LOCAL_RPC" "")"; then
  fail_sync "RPC unreachable (${LOCAL_RPC})"
fi
if ! public_ledger="$(http_get "$PUBLIC_RPC" "")"; then
  fail_sync "RPC unreachable (${PUBLIC_RPC})"
fi

if ! local_height="$(printf '%s' "$local_ledger" | jq_eval '.block_height // .ledger_info.block_height // empty')"; then
  fail_sync "JSON parse failure (local RPC)"
fi
if ! public_height="$(printf '%s' "$public_ledger" | jq_eval '.block_height // .ledger_info.block_height // empty')"; then
  fail_sync "JSON parse failure (public RPC)"
fi

if [[ -z "$local_height" || -z "$public_height" ]]; then
  fail_sync "missing block_height in RPC response"
fi

if [[ ! "$local_height" =~ ^[0-9]+$ || ! "$public_height" =~ ^[0-9]+$ ]]; then
  fail_sync "non-numeric block_height in RPC response"
fi

get_block_hash() {
  local rpc="$1"
  local height="$2"
  local block_json=""
  local hash_val=""

  if ! block_json="$(http_get "$rpc" "/blocks/by_height/${height}?with_transactions=false")"; then
    printf '%s' ""
    return 0
  fi

  if ! hash_val="$(printf '%s' "$block_json" | jq_eval '.block_hash // .hash // empty')"; then
    printf '%s' ""
    return 0
  fi

  printf '%s' "$hash_val"
}

local_hash="$(get_block_hash "$LOCAL_RPC" "$local_height")"
public_hash="$(get_block_hash "$PUBLIC_RPC" "$public_height")"

local_height_dec="$local_height"
public_height_dec="$public_height"
lag_raw=$((public_height_dec - local_height_dec))
lag_display="$lag_raw"
lag_state="in sync"

if (( lag_raw > 0 )); then
  lag_state="local behind"
elif (( lag_raw < 0 )); then
  lag_display=0
  lag_state="local ahead"
else
  lag_display=0
fi

local_hash_display="$local_hash"
public_hash_display="$public_hash"
[[ -z "$local_hash_display" ]] && local_hash_display="n/a"
[[ -z "$public_hash_display" ]] && public_hash_display="n/a"

echo "⏳ Latest block comparison"
echo "Local latest:  ${local_height_dec} ${local_hash_display}"
echo "Public latest: ${public_height_dec} ${public_hash_display}"
echo "Lag:         ${lag_display} blocks (threshold: ${BLOCK_LAG_THRESHOLD}) (${lag_state})"
echo

if (( lag_raw == 0 )) && [[ "$local_hash_display" != "n/a" && "$public_hash_display" != "n/a" && "$local_hash_display" != "$public_hash_display" ]]; then
  print_final_status "error"
  exit 2
fi

if (( lag_raw > BLOCK_LAG_THRESHOLD )); then
  print_final_status "syncing"
  exit 1
fi

print_final_status "in_sync"
exit 0
