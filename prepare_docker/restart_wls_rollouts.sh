#!/usr/bin/env bash
set -euo pipefail

# Restart common WLS-related deployments and wait for rollout
# Usage: ./restart_wls_rollouts.sh [-n namespace] [-k kc_cmd] [-d deployments]

NAMESPACE="weblogic"
KC_CMD="${KC_CMD:-kc}"
DEPLOYMENTS="wls-admin wls-managed-1 wls-managed-2 wls-dev"
TIMEOUT="120s"

source "$(dirname "$0")/common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

for d in $DEPLOYMENTS; do
  echo "Restarting deployment/$d in namespace $NAMESPACE"
  $KC_CMD rollout restart deployment/$d -n "$NAMESPACE" || true
  echo "Waiting for rollout status for $d (timeout: $TIMEOUT)"
  $KC_CMD rollout status deployment/$d -n "$NAMESPACE" --timeout=$TIMEOUT || true
done

echo "Done."

