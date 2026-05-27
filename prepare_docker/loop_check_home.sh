#!/usr/bin/env bash
set -euo pipefail

# Check existence and permissions of /home/docker and .ssh on all pods
# Usage: ./loop_check_home.sh [-n namespace] [-k kc_cmd]

NAMESPACE="weblogic"
KC_CMD="${KC_CMD:-kc}"

while getopts ":n:k:" opt; do
  case "$opt" in
    n) NAMESPACE="$OPTARG" ;;
    k) KC_CMD="$OPTARG" ;;
    *) echo "Usage: $0 [-n namespace] [-k kc_cmd]"; exit 1 ;;
  esac
done

echo "Checking pods in namespace: $NAMESPACE"
for p in $($KC_CMD get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
  echo "--- $p ---"
  # Try to list /home and /home/docker
  $KC_CMD exec -n "$NAMESPACE" "$p" -- sh -c 'ls -ld /home /home/docker 2>/dev/null || true'
  $KC_CMD exec -n "$NAMESPACE" "$p" -- sh -c 'ls -la /home/docker/.ssh 2>/dev/null || true'
done

echo "All pods checked."

