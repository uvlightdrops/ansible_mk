#!/usr/bin/env bash
set -euo pipefail

# mk_stop.sh
# Gracefully stop the minikube cluster (preserves all state; pods restart on mk_start.sh).
# Usage: ./mk_stop.sh [--pause] [--profile PROFILE]
#   (no flag)   minikube stop  — suspends cluster, full state preserved
#   --pause     minikube pause — freezes VMs without stopping (faster resume, less RAM freed)

MODE="stop"

source "$(dirname "$0")/common.sh"

mk_stop_usage_extra() {
  cat <<EOF
  (default)  minikube stop -p PROFILE  — full stop, state preserved, RAM freed
  --pause    minikube pause -p PROFILE — freeze VMs (faster resume, RAM stays allocated)

Bring back:
  ./prepare_docker/mk_start.sh        (after stop)
  minikube unpause -p PROFILE         (after pause)
EOF
}

help_mk_stop() {
  usage_render_script "$0 [--pause] [--profile PROFILE]" mk_stop_usage_extra
  exit 0
}

parse_mk_stop_arg() {
  case "$1" in
    --pause)          MODE="pause";   PARSE_ARG_CONSUMED=1; return 0 ;;
    --profile|-p)     MK_PRF="$2";   PARSE_ARG_CONSUMED=2; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_mk_stop parse_mk_stop_arg "$@" || exit $?

case "$MODE" in
  stop)
    echo "Stopping minikube cluster '$MK_PRF' (state preserved)..."
    minikube stop -p "$MK_PRF"
    echo "Done. Restart with: ./prepare_docker/mk_start.sh"
    ;;
  pause)
    echo "Pausing minikube cluster '$MK_PRF'..."
    minikube pause -p "$MK_PRF"
    echo "Done. Resume with: minikube unpause -p $MK_PRF"
    ;;
esac

