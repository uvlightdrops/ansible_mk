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
reap_terminating_usage_extra() {
  cat <<EOF
  -w wait_seconds to wait after delete before force (default: 10)
EOF
}

help_reap_terminating() {
  usage_render_script "$0 [-w wait_seconds]" reap_terminating_usage_extra
  exit 0
}

parse_reap_terminating_arg() {
  case "$1" in
    -w) WAIT_SECONDS="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_reap_terminating parse_reap_terminating_arg "$@" || exit $?
init_kc_cmd

echo "Namespace: $NAMESPACE, KC_CMD: $KC_CMD, wait: ${WAIT_SECONDS}s"

# Find pods that are terminating (deletionTimestamp set) or status Terminating
pids=$(kc -n "$NAMESPACE" get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.deletionTimestamp}|{.status.phase}{"\n"}{end}' 2>/dev/null || true)
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
    echo "-> attempting normal delete: kc delete pod $name -n $NAMESPACE"
    kc delete pod "$name" -n "$NAMESPACE" || true

    echo "-> waiting ${WAIT_SECONDS}s"
    sleep "$WAIT_SECONDS"

    # Check if still present
    if kc -n "$NAMESPACE" get pod "$name" >/dev/null 2>&1; then
      echo "-> Pod $name still present after wait; attempting to remove finalizers then force-delete"

      # Try to remove finalizers (merge patch). Ignore errors.
      echo "-> patching finalizers (try)"
      kc patch pod "$name" -n "$NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true

      # Finally force delete
      echo "-> force delete pod $name"
      kc delete pod "$name" -n "$NAMESPACE" --grace-period=0 --force || true
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

