#!/usr/bin/env bash
set -euo pipefail

# mk_stop.sh
# Gracefully stop the minikube cluster (preserves all state; pods restart on mk_start.sh).
# Usage: ./mk_stop.sh [--pause] [--profile PROFILE]
#   (no flag)   minikube stop  — suspends cluster, full state preserved
#   --pause     minikube pause — freezes VMs without stopping (faster resume, less RAM freed)

MK_PRF="${MK_PRF:-wlcluster}"
MODE="stop"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pause)          MODE="pause";   shift ;;
    --profile|-p)     MK_PRF="$2";   shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--pause] [--profile PROFILE]
  (default)  minikube stop -p PROFILE  — full stop, state preserved, RAM freed
  --pause    minikube pause -p PROFILE — freeze VMs (faster resume, RAM stays allocated)

Bring back:
  ./prepare_docker/mk_start.sh        (after stop)
  minikube unpause -p PROFILE         (after pause)
EOF
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

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

