#!/usr/bin/env bash
set -euo pipefail

group="${1:-video_pis}"

if ! command -v sshpass >/dev/null 2>&1; then
  echo "sshpass is required for password auth but was not found."
  exit 1
fi

echo "Checking password SSH access for inventory group: ${group}"
echo

mapfile -t hosts < <(ansible "$group" --list-hosts | sed '1d; s/^[[:space:]]*//')

if [[ "${#hosts[@]}" -eq 0 ]]; then
  echo "No hosts found for ${group}."
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

for host in "${hosts[@]}"; do
  ansible_user="$(get_host_var "$host" ansible_user)"
  ansible_password="$(get_host_var "$host" ansible_password)"

  if [[ -z "$ansible_user" || -z "$ansible_password" ]]; then
    echo "FAIL ${host}: missing ansible_user or ansible_password"
    failed=1
    continue
  fi

  if SSHPASS="$ansible_password" sshpass -e ssh \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 \
    "${ansible_user}@${host}" \
    'echo "SSH_OK host=$(hostname) user=$(whoami)"'; then
    echo "PASS ${host}"
  else
    echo "FAIL ${host}"
    failed=1
  fi

  echo
done

exit "$failed"
