#!/usr/bin/env bash
set -euo pipefail

group="${1:-video_pis}"
log_file="${2:-}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  if [[ -n "$log_file" ]]; then
    echo "$msg" >> "$log_file"
  fi
}

if ! command -v sshpass >/dev/null 2>&1; then
  log "ERROR: sshpass is required for password auth but was not found."
  exit 1
fi

log "Checking SSH access for inventory group: ${group}"
if [[ -n "$log_file" ]]; then
  log "Log file: ${log_file}"
fi
echo

mapfile -t hosts < <(ansible "$group" --list-hosts | sed '1d; s/^[[:space:]]*//')

if [[ "${#hosts[@]}" -eq 0 ]]; then
  log "No hosts found for ${group}."
  exit 1
fi

get_host_var() {
  local host="$1"
  local var_name="$2"

  ansible-inventory --host "$host" |
    sed -nE 's/^[[:space:]]*"'"$var_name"'":[[:space:]]*"([^"]*)",?$/\1/p' |
    head -n 1
}

failed=0
passed=0
skipped=0

for host in "${hosts[@]}"; do
  ansible_user="$(get_host_var "$host" ansible_user)"
  ansible_password="$(get_host_var "$host" ansible_password)"

  if [[ -z "$ansible_user" || -z "$ansible_password" ]]; then
    log "${YELLOW}SKIP ${host}: missing ansible_user or ansible_password${NC}"
    ((skipped++)) || true
    continue
  fi

  # Try SSH key auth first, fall back to password
  ssh_result=1
  if ssh \
    -o PubkeyAuthentication=yes \
    -o PreferredAuthentications=publickey,password \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 \
    "${ansible_user}@${host}" \
    'echo "SSH_OK host=$(hostname) user=$(whoami)"' >/dev/null 2>&1; then
    ssh_result=0
  fi

  # Fall back to password auth if key auth failed
  if [[ $ssh_result -ne 0 ]]; then
    if SSHPASS="$ansible_password" sshpass -e ssh \
      -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=8 \
      "${ansible_user}@${host}" \
      'echo "SSH_OK host=$(hostname) user=$(whoami)"' >/dev/null 2>&1; then
      ssh_result=0
    fi
  fi

  if [[ $ssh_result -eq 0 ]]; then
    log "${GREEN}PASS ${host}${NC}"
    ((passed++)) || true
  else
    log "${RED}FAIL ${host}${NC}"
    ((failed++)) || true
  fi
done

echo "----------------------------------------"
log "Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}, ${YELLOW}${skipped} skipped${NC}"
if [[ -n "$log_file" ]]; then
  log "Full log written to: ${log_file}"
fi

exit "$failed"
