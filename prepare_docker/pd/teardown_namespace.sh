#!/usr/bin/env bash
set -euo pipefail

# teardown_namespace.sh
# Remove WebLogic k8s resources at the desired level.
#
# Levels (mutually exclusive, default: --resources):
#   --scale-down  scale all workloads to 0 replicas (pods gone, everything else intact)
#   --soft        delete Deployments/StatefulSets (PVC/ConfigMaps/Services stay; re-apply to bring back)
#   --resources   delete all resources in namespace (deployments, svcs, configmaps, pvcs)
#   --namespace   delete the entire namespace (fastest; all resources in one shot)
#   --all         like --namespace + also delete cluster-scoped PV and StorageClass
#
# Extra flags:
#   --purge-data  additionally wipe hostPath data on all minikube node containers
#
# Usage: ./teardown_namespace.sh [-n namespace] [-k kc_cmd] [--scale-down|--soft|--resources|--namespace|--all] [--purge-data] [--yes]

LEVEL="resources"
PURGE_DATA=0

source "$(dirname "$0")/../common.sh"
help_teardown_namespace() {
  teardown_usage_extra() {
    cat <<EOF
Levels (gentlest -> most destructive):
  --scale-down  scale all workloads to 0 replicas (pods stop; everything else stays intact)
                -> bring back: kc scale deployment --all --replicas=1 -n $NAMESPACE
                               kc scale statefulset --all --replicas=1 -n $NAMESPACE
  --soft        delete Deployments/StatefulSets (PVC/ConfigMaps/Services stay; re-apply manifests to restore)
  --resources   (default) delete all resources in namespace (deploy, svcs, cm, pvc)
  --namespace   delete the entire namespace
  --all         like --namespace + delete cluster-scoped PV and StorageClass

Flags:
  --purge-data  wipe $PV_PATH on all minikube node containers (docker required)
  -y / --yes    skip confirmation prompt
EOF
  }
  usage_render_script "$0 [--scale-down|--soft|--resources|--namespace|--all] [--purge-data] [-y]" teardown_usage_extra
  exit 0
}

parse_teardown_namespace_arg() {
  case "$1" in
    --scale-down)  LEVEL="scale-down"; PARSE_ARG_CONSUMED=1; return 0 ;;
    --soft)        LEVEL="soft";       PARSE_ARG_CONSUMED=1; return 0 ;;
    --resources)   LEVEL="resources";  PARSE_ARG_CONSUMED=1; return 0 ;;
    --namespace)   LEVEL="namespace";  PARSE_ARG_CONSUMED=1; return 0 ;;
    --all)         LEVEL="all";        PARSE_ARG_CONSUMED=1; return 0 ;;
    --purge-data)  PURGE_DATA=1;        PARSE_ARG_CONSUMED=1; return 0 ;;
    -y|--yes)      AUTO_YES=1;          PARSE_ARG_CONSUMED=1; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_teardown_namespace parse_teardown_namespace_arg "$@" || exit $?
init_kc_cmd

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

do_scale_down() {
  echo "-> Scaling all Deployments in $NAMESPACE to 0 replicas"
  kc scale deployment --all --replicas=0 -n "$NAMESPACE" || true
  echo "-> Scaling all StatefulSets in $NAMESPACE to 0 replicas"
  kc scale statefulset --all --replicas=0 -n "$NAMESPACE" || true
  echo "-> Waiting for pods to terminate..."
  kc wait pod --all -n "$NAMESPACE" --for=delete --timeout=60s 2>/dev/null || true
  echo "-> All pods stopped. Workloads/Services/ConfigMaps/PVCs intact."
  echo "   To bring pods back: kc scale deployment --all --replicas=1 -n $NAMESPACE"
  echo "                      kc scale statefulset --all --replicas=1 -n $NAMESPACE"
}

do_soft() {
  echo "-> Deleting Deployments in $NAMESPACE"
  kc delete deployment --all -n "$NAMESPACE" --ignore-not-found=true
  echo "-> Deleting StatefulSets in $NAMESPACE"
  kc delete statefulset --all -n "$NAMESPACE" --ignore-not-found=true
}

do_resources() {
  do_soft
  echo "-> Deleting Services in $NAMESPACE"
  kc delete service --all -n "$NAMESPACE" --ignore-not-found=true
  echo "-> Deleting ConfigMaps in $NAMESPACE (skipping kube-root-ca.crt)"
  kc get configmap -n "$NAMESPACE" -o name \
    | grep -v 'kube-root-ca' \
    | xargs -r kc delete -n "$NAMESPACE" --ignore-not-found=true || true
  echo "-> Deleting PVCs in $NAMESPACE"
  kc delete pvc --all -n "$NAMESPACE" --ignore-not-found=true
}

wait_namespace_gone() {
  local retries=30
  echo "-> Waiting for namespace $NAMESPACE to be fully removed..."
  while kc get namespace "$NAMESPACE" >/dev/null 2>&1; do
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
  kc delete namespace "$NAMESPACE" --ignore-not-found=true
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
  scale-down)
    do_scale_down
    ;;
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
    kc delete pv pv-weblogic-home --ignore-not-found=true
    echo "-> Deleting StorageClass manual"
    kc delete storageclass manual --ignore-not-found=true
    ;;
esac

if [ "$PURGE_DATA" -eq 1 ]; then
  do_purge_data
fi

echo ""
echo "=== Teardown complete (level=$LEVEL) ==="
if [ "$LEVEL" = "scale-down" ]; then
  echo "    Bring back:  kc scale deployment --all --replicas=1 -n $NAMESPACE"
  echo "                 kc scale statefulset --all --replicas=1 -n $NAMESPACE"
  echo "    Or full rebuild: ./prepare_docker/bootstrap_cluster.sh --no-start --no-build"
else
  echo "    To rebuild from scratch: ./prepare_docker/bootstrap_cluster.sh"
fi


