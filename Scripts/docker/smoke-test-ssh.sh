#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

command -v expect >/dev/null 2>&1 || die "expect is required for the password-auth smoke check."

run_password_smoke() {
  local host_ip="$1"
  local output

  output="$(
    expect <<EOF
set timeout 20
log_user 0
spawn ssh -o ConnectTimeout=10 -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p $GLASSDECK_TEST_SSH_PORT $GLASSDECK_TEST_SSH_USER@$host_ip "echo GLASSDECK_PASSWORD_OK && pwd && ~/bin/health-check.sh"
expect {
  -re "(?i)password:" {
    send "$GLASSDECK_TEST_SSH_PASSWORD\r"
    exp_continue
  }
  eof
}
catch wait result
set exit_status [lindex \$result 3]
puts \$expect_out(buffer)
exit \$exit_status
EOF
  )"

  printf '%s\n' "$output"
  grep -q "GLASSDECK_PASSWORD_OK" <<<"$output" || die "Password-auth smoke test did not return the expected marker."
  grep -q "GLASSDECK_SSH_OK" <<<"$output" || die "Password-auth smoke test did not execute the seeded helper command."
}

run_key_smoke() {
  local host_ip="$1"
  local output

  chmod 600 "$GLASSDECK_TEST_SSH_KEY"
  output="$(
    ssh \
      -o ConnectTimeout=10 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      -o IdentitiesOnly=yes \
      -i "$GLASSDECK_TEST_SSH_KEY" \
      -p "$GLASSDECK_TEST_SSH_PORT" \
      "$GLASSDECK_TEST_SSH_USER@$host_ip" \
      "echo GLASSDECK_KEY_OK && pwd && ls ~/testdata && ~/bin/health-check.sh"
  )"

  printf '%s\n' "$output"
  grep -q "GLASSDECK_KEY_OK" <<<"$output" || die "SSH-key smoke test did not return the expected marker."
  grep -q "preview.txt" <<<"$output" || die "SSH-key smoke test did not see the seeded testdata."
  grep -q "GLASSDECK_SSH_OK" <<<"$output" || die "SSH-key smoke test did not execute the seeded helper command."
}

start_stack
host_ip="$(detect_lan_ip)"

run_password_smoke "$host_ip"
run_key_smoke "$host_ip"

printf '\nSmoke test passed against %s:%s.\n' "$host_ip" "$GLASSDECK_TEST_SSH_PORT"
