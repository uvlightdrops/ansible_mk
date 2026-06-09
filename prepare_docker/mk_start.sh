#!/usr/bin/env bash
set -euo pipefail

# mk_start.sh
# Start (or resume) the minikube wlcluster.
# Usage: ./mk_start.sh [--profile PROFILE] [--nodes N]

MK_PRF="${MK_PRF:-wlcluster}"
MK_NODES="${MK_NODES:-3}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile|-p) MK_PRF="$2"; shift 2 ;;
    --nodes)      MK_NODES="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

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
