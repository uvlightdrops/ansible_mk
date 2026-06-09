#!/usr/bin/env bash
set -euo pipefail

# teardown_namespace.sh
# Remove WebLogic k8s resources at the desired level.
#
# Levels (mutually exclusive, default: --resources):
#   --soft        only delete Deployments; PVC/ConfigMaps/Services stay
#   --resources   delete all resources in namespace (deployments, svcs, configmaps, pvcs)
#   --namespace   delete the entire namespace (fastest; all resources in one shot)
#   --all         like --namespace + also delete cluster-scoped PV and StorageClass
#
# Extra flags:
#   --purge-data  additionally wipe hostPath data on all minikube node containers
#
# Usage: ./teardown_namespace.sh [-n namespace] [-k kc_cmd] [--soft|--resources|--namespace|--all] [--purge-data] [--yes]

LEVEL="resources"
PURGE_DATA=0
MK_PRF="${MK_PRF:-wlcluster}"
PV_PATH="${PV_PATH:-/mnt/weblogic/pv-home}"
AUTO_YES=0

source "$(dirname "$0")/common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --soft)        LEVEL="soft";       shift ;;
    --resources)   LEVEL="resources";  shift ;;
    --namespace)   LEVEL="namespace";  shift ;;
    --all)         LEVEL="all";        shift ;;
    --purge-data)  PURGE_DATA=1;       shift ;;
    -y|--yes)      AUTO_YES=1;         shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [-n namespace] [-k kc_cmd] [--soft|--resources|--namespace|--all] [--purge-data] [-y]

Levels:
  --soft        only delete Deployments (pods die; PVC/ConfigMaps/Services stay)
  --resources   (default) delete all resources in namespace (deploy, svcs, cm, pvc)
  --namespace   delete the entire namespace
  --all         like --namespace + delete cluster-scoped PV and StorageClass

Flags:
  --purge-data  wipe $PV_PATH on all minikube node containers (docker required)
  -y / --yes    skip confirmation prompt
EOF
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

echo "=== Teardown plan: level='$LEVEL'  purge_data=$PURGE_DATA  namespace=$NAMESPACE ==="
if [ "$AUTO_YES" -eq 0 ]; then
  printf "Continue? [y/N] "
  read -r ans
  case "$ans" in
    [yY]*) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ── helpers ────────────────────────────────────────────────────────────────────

do_soft() {
  echo "-> Deleting Deployments in $NAMESPACE"
  $KC_CMD delete deployment --all -n "$NAMESPACE" --ignore-not-found=true
}

do_resources() {
  do_soft
  echo "-> Deleting Services in $NAMESPACE"
  $KC_CMD delete service --all -n "$NAMESPACE" --ignore-not-found=true
  echo "-> Deleting ConfigMaps in $NAMESPACE (skipping kube-root-ca.crt)"
  $KC_CMD get configmap -n "$NAMESPACE" -o name \
    | grep -v 'kube-root-ca' \
    | xargs -r $KC_CMD delete -n "$NAMESPACE" --ignore-not-found=true || true
  echo "-> Deleting PVCs in $NAMESPACE"
  $KC_CMD delete pvc --all -n "$NAMESPACE" --ignore-not-found=true
}

wait_namespace_gone() {
  local retries=30
  echo "-> Waiting for namespace $NAMESPACE to be fully removed..."
  while $KC_CMD get namespace "$NAMESPACE" >/dev/null 2>&1; do
    retries=$((retries-1))
    if [ "$retries" -eq 0 ]; then
      echo "Warning: namespace $NAMESPACE still present after wait – continuing anyway" >&2
      return 0
    fi
    sleep 2
  done
  echo "-> Namespace gone."
}

do_namespace() {
  echo "-> Deleting namespace $NAMESPACE"
  $KC_CMD delete namespace "$NAMESPACE" --ignore-not-found=true
  wait_namespace_gone
}

do_purge_data() {
  echo "-> Purging $PV_PATH on minikube nodes (profile prefix: $MK_PRF)"
  containers=$(docker ps --format '{{.Names}}' | grep "^${MK_PRF}" || true)
  if [ -z "$containers" ]; then
    echo "Warning: no minikube containers found with prefix '$MK_PRF'" >&2
    return 0
  fi
  for c in $containers; do
    echo "   $c: rm -rf $PV_PATH && mkdir + chown"
    docker exec --privileged -u root "$c" rm -rf "$PV_PATH" || true
    docker exec --privileged -u root "$c" mkdir -p "$PV_PATH" || true
    docker exec --privileged -u root "$c" chown -R 1000:1000 "$PV_PATH" || true
    docker exec --privileged -u root "$c" chmod 700 "$PV_PATH" || true
  done
  echo "-> Data purge done."
}

# ── execute level ──────────────────────────────────────────────────────────────

case "$LEVEL" in
  soft)
    do_soft
    ;;
  resources)
    do_resources
    ;;
  namespace)
    do_namespace
    ;;
  all)
    do_namespace
    echo "-> Deleting PV pv-weblogic-home"
    $KC_CMD delete pv pv-weblogic-home --ignore-not-found=true
    echo "-> Deleting StorageClass manual"
    $KC_CMD delete storageclass manual --ignore-not-found=true
    ;;
esac

if [ "$PURGE_DATA" -eq 1 ]; then
  do_purge_data
fi

echo ""
echo "=== Teardown complete (level=$LEVEL) ==="
echo "    To rebuild from scratch: ./prepare_docker/bootstrap_cluster.sh"

