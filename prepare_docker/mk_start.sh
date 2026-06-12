#!/usr/bin/env bash
set -euo pipefail

# mk_start.sh
# Start (or resume) the minikube wlcluster.
# Usage: ./mk_start.sh [--profile PROFILE] [--nodes N]


source "$(dirname "$0")/common.sh"

mk_start_usage_extra() {
  cat <<EOF
  --profile PROFILE   minikube profile (default: wlcluster)
  --nodes N           minikube node count (default: 3)
EOF
}

help_mk_start() {
  usage_render_script "$0 [--profile PROFILE] [--nodes N]" mk_start_usage_extra
  exit 0
}

parse_mk_start_arg() {
  case "$1" in
    --profile|-p) MK_PRF="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
    --nodes)      MK_NODES="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_mk_start parse_mk_start_arg "$@" || exit $?

if minikube status -p "$MK_PRF" --format='{{.Host}}' 2>/dev/null | grep -q "^Running$"; then
  echo "Cluster '$MK_PRF' is already running."
else
  echo "Starting minikube cluster '$MK_PRF' (nodes=$MK_NODES)..."
  minikube start -p "$MK_PRF" --nodes="$MK_NODES" --driver=docker --cpus=4 --memory=8192
fi

echo ""
echo "Cluster ready. Pod status:"
minikube -p "$MK_PRF" kubectl -- get pods -n weblogic -o wide 2>/dev/null || true
echo ""
echo "If pods are scaled to 0:"
echo "  kc scale deployment --all --replicas=1 -n weblogic"
echo "  kc scale statefulset --all --replicas=1 -n weblogic"
