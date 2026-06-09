#!/usr/bin/env bash
set -euo pipefail

# reap_terminating.sh
# Try to clean up Pods stuck in Terminating state in a namespace.
# Usage: ./reap_terminating.sh [-n namespace] [-k kc_cmd] [-w wait_seconds]
#   -n namespace (default: weblogic)
#   -k kc_cmd  (default: kc)  # wrapper or minikube kubectl
#   -w wait_seconds to wait after delete before force (default: 10)

WAIT_SECONDS=10

source "$(dirname "$0")/common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -w) WAIT_SECONDS="$2"; shift 2; ;;
    -h|--help) echo "Usage: $0 [-n namespace] [-k kc_cmd] [-w wait_seconds]"; exit 0; ;;
    *) echo "Unknown arg: $1" >&2; exit 2; ;;
  esac
done

echo "Namespace: $NAMESPACE, KC_CMD: $KC_CMD, wait: ${WAIT_SECONDS}s"

# Find pods that are terminating (deletionTimestamp set) or status Terminating
pids=$($KC_CMD -n "$NAMESPACE" get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.deletionTimestamp}|{.status.phase}{"\n"}{end}' 2>/dev/null || true)
if [ -z "$pids" ]; then
  echo "No pods found in namespace $NAMESPACE"
  exit 0
fi

found=0
while IFS= read -r line; do
  name=$(printf '%s' "$line" | cut -d'|' -f1)
  delts=$(printf '%s' "$line" | cut -d'|' -f2)
  phase=$(printf '%s' "$line" | cut -d'|' -f3)
  if [ -n "$delts" ] || [ "$phase" = "Terminating" ] || [ "$phase" = "Unknown" ]; then
    found=1
    echo "Handling pod: $name (phase=$phase deletionTimestamp=${delts:-None})"

    # Try normal delete first
    echo "-> attempting normal delete: $KC_CMD delete pod $name -n $NAMESPACE"
    $KC_CMD delete pod "$name" -n "$NAMESPACE" || true

    echo "-> waiting ${WAIT_SECONDS}s"
    sleep "$WAIT_SECONDS"

    # Check if still present
    if $KC_CMD -n "$NAMESPACE" get pod "$name" >/dev/null 2>&1; then
      echo "-> Pod $name still present after wait; attempting to remove finalizers then force-delete"

      # Try to remove finalizers (merge patch). Ignore errors.
      echo "-> patching finalizers (try)"
      $KC_CMD patch pod "$name" -n "$NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true

      # Finally force delete
      echo "-> force delete pod $name"
      $KC_CMD delete pod "$name" -n "$NAMESPACE" --grace-period=0 --force || true
    else
      echo "-> Pod $name removed cleanly"
    fi
  fi
done <<EOF
$pids
EOF

if [ "$found" -eq 0 ]; then
  echo "No terminating pods found in namespace $NAMESPACE"
else
  echo "Done handling terminating pods in $NAMESPACE"
fi

exit 0

