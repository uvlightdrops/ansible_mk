#!/usr/bin/env bash
set -euo pipefail

# Restart common WLS-related workloads and wait for rollout
# See -h/--help for usage.

DEPLOYMENTS="wls-admin wls-dev"
STATEFULSETS="wls-managed-1 wls-managed-2 wls-managed-3"
TIMEOUT="120s"

source "$(dirname "$0")/../common.sh"

help_restart_wls_rollouts() {
  restart_wls_rollouts_usage_extra() {
    cat <<EOF
  --timeout T    rollout status timeout (default: 120s)
EOF
  }
  usage_render_script "$0 [--timeout 120s]" restart_wls_rollouts_usage_extra
  exit 0
}

parse_restart_wls_rollouts_arg() {
  case "$1" in
    --timeout) TIMEOUT="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_restart_wls_rollouts parse_restart_wls_rollouts_arg "$@" || exit $?

init_kc_cmd

for d in $DEPLOYMENTS; do
  echo "Restarting deployment/$d in namespace $NAMESPACE"
  kc rollout restart deployment/$d -n "$NAMESPACE" || true
  echo "Waiting for rollout status for $d (timeout: $TIMEOUT)"
  kc rollout status deployment/$d -n "$NAMESPACE" --timeout=$TIMEOUT || true
done

for s in $STATEFULSETS; do
  echo "Restarting statefulset/$s in namespace $NAMESPACE"
  kc rollout restart statefulset/$s -n "$NAMESPACE" || true
  echo "Waiting for rollout status for $s (timeout: $TIMEOUT)"
  kc rollout status statefulset/$s -n "$NAMESPACE" --timeout=$TIMEOUT || true
done

echo "Done."


