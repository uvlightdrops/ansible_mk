#!/usr/bin/env bash
set -euo pipefail

# Remove WebLogic resources deployed by scripts/deploy_manual_no_operator.sh.
# Deletes manifests in reverse order.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NAMESPACE="wl"
KC_CMD="${KC_CMD:-kubectl}"
DRY_RUN="false"
SKIP_PV="true"
DELETE_NAMESPACE="false"

usage() {
  cat <<'EOF'
Usage: scripts/undeploy_manual_no_operator.sh [options]

Options:
  -n, --namespace <ns>      Namespace (default: wl)
      --kc-cmd <cmd>        kubectl command (default: $KC_CMD or kubectl)
      --dry-run             Print delete commands, do not execute
      --delete-pv           Also delete cluster-scoped PV manifest (k8s/pv.yaml)
                            (skipped by default – needs cluster-admin permissions)
      --delete-namespace    Also delete namespace object (uses --namespace value)
  -h, --help                Show help

Examples:
  scripts/undeploy_manual_no_operator.sh
  scripts/undeploy_manual_no_operator.sh --kc-cmd "kubectl --context mycluster" -n wl
  scripts/undeploy_manual_no_operator.sh --delete-pv
  scripts/undeploy_manual_no_operator.sh --delete-namespace
  scripts/undeploy_manual_no_operator.sh --dry-run
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --kc-cmd)
      KC_CMD="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift 1
      ;;
    --delete-pv)
      SKIP_PV="false"
      shift 1
      ;;
    --delete-namespace)
      DELETE_NAMESPACE="true"
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

read -r -a KC <<<"$KC_CMD"

MANIFESTS=(
  "k8s/overlays/manual/deploy-wls-managed-3.yaml"
  "k8s/overlays/manual/deploy-wls-managed-2.yaml"
  "k8s/overlays/manual/deploy-wls-managed-1.yaml"
  "k8s/overlays/manual/deploy-wls-admin.yaml"
  "k8s/deploy-test-db.yaml"
  "k8s/services-clusterip.yaml"
  "k8s/pvc-weblogic-home.yaml"
  "k8s/pv.yaml"
)

for manifest in "${MANIFESTS[@]}"; do
  if [ ! -f "$REPO_ROOT/$manifest" ]; then
    echo "Missing manifest: $manifest" >&2
    exit 1
  fi
done

echo "Repo root: $REPO_ROOT"
echo "Namespace: $NAMESPACE"
echo "kubectl cmd: $KC_CMD"
echo "Dry run: $DRY_RUN"
echo "Skip PV delete: $SKIP_PV (use --delete-pv to force deletion)"
echo "Delete namespace: $DELETE_NAMESPACE"

echo
for manifest in "${MANIFESTS[@]}"; do
  if [ "$manifest" = "k8s/pv.yaml" ] && [ "$SKIP_PV" = "true" ]; then
    echo "==> Skipping $manifest (PV wird nicht gelöscht – bei Bedarf --delete-pv angeben)"
    continue
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] ${KC_CMD} delete -f $REPO_ROOT/$manifest -n $NAMESPACE --ignore-not-found=true"
    continue
  fi

  echo "==> Deleting $manifest"
  set +e
  out=$("${KC[@]}" delete -f "$REPO_ROOT/$manifest" -n "$NAMESPACE" --ignore-not-found=true 2>&1)
  rc=$?
  set -e

  if [ $rc -ne 0 ]; then
    if [ "$manifest" = "k8s/pv.yaml" ] && echo "$out" | grep -qiE 'forbidden|cannot delete resource|persistentvolumes'; then
      echo "$out" >&2
      echo "WARN: No permission to delete PV. Continuing." >&2
      continue
    fi
    echo "$out" >&2
    exit $rc
  fi

  echo "$out"
done

if [ "$DELETE_NAMESPACE" = "true" ]; then
  echo "==> Deleting namespace $NAMESPACE"
  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] ${KC_CMD} delete namespace $NAMESPACE --ignore-not-found=true"
  else
    set +e
    out=$("${KC[@]}" delete namespace "$NAMESPACE" --ignore-not-found=true 2>&1)
    rc=$?
    set -e
    if [ $rc -ne 0 ]; then
      if echo "$out" | grep -qiE 'forbidden|cannot delete resource|namespaces'; then
        echo "$out" >&2
        echo "WARN: No permission to delete namespace. Continuing." >&2
      else
        echo "$out" >&2
        exit $rc
      fi
    else
      echo "$out"
    fi
  fi
fi

echo
echo "Undeploy complete. Current status:"
"${KC[@]}" get pods -n "$NAMESPACE" -o wide 2>/dev/null || true
"${KC[@]}" get svc -n "$NAMESPACE" 2>/dev/null || true
"${KC[@]}" get pvc -n "$NAMESPACE" 2>/dev/null || true

