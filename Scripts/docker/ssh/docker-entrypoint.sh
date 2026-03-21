#!/usr/bin/env bash
set -euo pipefail

TEST_USER="${GLASSDECK_TEST_SSH_USER:-glassdeck}"
TEST_PASSWORD="${GLASSDECK_TEST_SSH_PASSWORD:-glassdeck}"
USER_HOME="/home/$TEST_USER"
SEED_HOME="/opt/glassdeck-seed/home"
HOSTKEY_DIR="/var/lib/glassdeck-runtime/hostkeys"

if ! getent group "$TEST_USER" >/dev/null 2>&1; then
  groupadd --gid 1000 "$TEST_USER"
fi

if ! id -u "$TEST_USER" >/dev/null 2>&1; then
  useradd --uid 1000 --gid "$TEST_USER" --home-dir "$USER_HOME" --shell /bin/bash "$TEST_USER"
fi

mkdir -p /run/sshd "$USER_HOME"
mkdir -p "$HOSTKEY_DIR"
find "$USER_HOME" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "$SEED_HOME"/. "$USER_HOME"/

echo "$TEST_USER:$TEST_PASSWORD" | chpasswd
if [[ ! -f "$HOSTKEY_DIR/ssh_host_ed25519_key" ]]; then
  ssh-keygen \
    -q \
    -t ed25519 \
    -f "$HOSTKEY_DIR/ssh_host_ed25519_key" \
    -N "" \
    -C "glassdeck-docker-host"
fi

chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
find "$USER_HOME/bin" -type f -name '*.sh' -exec chmod 755 {} +
chown -R "$TEST_USER:$TEST_USER" "$USER_HOME"

exec "$@"
