#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/ssh-compose.yml"
PROJECT_NAME="glassdeck-test-ssh"

GLASSDECK_TEST_SSH_USER="${GLASSDECK_TEST_SSH_USER:-glassdeck}"
GLASSDECK_TEST_SSH_PASSWORD="${GLASSDECK_TEST_SSH_PASSWORD:-glassdeck}"
GLASSDECK_TEST_SSH_PORT="${GLASSDECK_TEST_SSH_PORT:-22222}"
GLASSDECK_TEST_SSH_RUNTIME_DIR="${GLASSDECK_TEST_SSH_RUNTIME_DIR:-$ROOT/.build/docker-ssh}"
GLASSDECK_TEST_SSH_KEY="$ROOT/Scripts/docker/fixtures/keys/glassdeck_ed25519"
GLASSDECK_TEST_SSH_HOSTKEY_PUB="$GLASSDECK_TEST_SSH_RUNTIME_DIR/hostkeys/ssh_host_ed25519_key.pub"

export GLASSDECK_TEST_SSH_USER
export GLASSDECK_TEST_SSH_PASSWORD
export GLASSDECK_TEST_SSH_PORT
export GLASSDECK_TEST_SSH_RUNTIME_DIR

run_quiet() {
  local label="$1"
  local log_file="$2"
  shift 2

  mkdir -p "$(dirname "$log_file")"

  if [[ "${GLASSDECK_VERBOSE:-0}" == "1" ]]; then
    "$@"
    return
  fi

  if ! "$@" >"$log_file" 2>&1; then
    echo "$label failed. Full log:" >&2
    cat "$log_file" >&2
    return 1
  fi
}

die() {
  echo "$*" >&2
  exit 1
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is required. Install Docker Desktop first."
  docker compose version >/dev/null 2>&1 || die "docker compose is required."
}

compose() {
  docker compose \
    --project-name "$PROJECT_NAME" \
    -f "$COMPOSE_FILE" \
    "$@"
}

container_id() {
  compose ps -q ssh
}

wait_for_healthy() {
  local cid
  local status
  local attempt

  cid="$(container_id)"
  [[ -n "$cid" ]] || die "Unable to resolve the SSH container ID."

  for attempt in $(seq 1 60); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "$cid" 2>/dev/null || true)"
    if [[ "$status" == "healthy" ]]; then
      return 0
    fi
    sleep 1
  done

  die "Timed out waiting for the Docker SSH server to become healthy."
}

detect_lan_ip() {
  local iface
  local ip

  iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  if [[ -n "$iface" ]]; then
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
  fi

  ip="$(ifconfig | awk '/inet / && $2 != "127.0.0.1" { print $2; exit }')"
  [[ -n "$ip" ]] || die "Unable to detect a LAN IP address for the Docker SSH target."
  printf '%s\n' "$ip"
}

start_stack() {
  ensure_docker
  mkdir -p "$GLASSDECK_TEST_SSH_RUNTIME_DIR/hostkeys"
  run_quiet \
    "Docker SSH build/start" \
    "$GLASSDECK_TEST_SSH_RUNTIME_DIR/compose-up.log" \
    compose up -d --build --remove-orphans
  wait_for_healthy
}

print_connection_info() {
  local host_ip
  local host_fingerprint=""

  host_ip="$(detect_lan_ip)"

  if [[ -f "$GLASSDECK_TEST_SSH_HOSTKEY_PUB" ]]; then
    host_fingerprint="$(ssh-keygen -lf "$GLASSDECK_TEST_SSH_HOSTKEY_PUB" | awk '{print $2}')"
  fi

  cat <<EOF
Glassdeck Docker SSH target is ready.

Host: $host_ip
Port: $GLASSDECK_TEST_SSH_PORT
Username: $GLASSDECK_TEST_SSH_USER
Password: $GLASSDECK_TEST_SSH_PASSWORD
SSH private key: $GLASSDECK_TEST_SSH_KEY
SSH public key: ${GLASSDECK_TEST_SSH_KEY}.pub
EOF

  if [[ -n "$host_fingerprint" ]]; then
    cat <<EOF
Host key fingerprint: $host_fingerprint
EOF
  fi

  cat <<EOF
Suggested terminal checks:
  ssh -p $GLASSDECK_TEST_SSH_PORT $GLASSDECK_TEST_SSH_USER@$host_ip
  ssh -i $GLASSDECK_TEST_SSH_KEY -o IdentitiesOnly=yes -p $GLASSDECK_TEST_SSH_PORT $GLASSDECK_TEST_SSH_USER@$host_ip
  ~/bin/health-check.sh
  nano --mouse ~/testdata/nano-target.txt
EOF
}
