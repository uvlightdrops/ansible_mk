#!/usr/bin/env bash
set -euo pipefail

# Deploy WebLogic resources without Operator/Domain CR.
# Applies manifests in a fixed order.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NAMESPACE="wl"
KC_CMD="${KC_CMD:-kubectl}"
DRY_RUN="false"
CREATE_NAMESPACE="false"
APPLY_PV="false"
SKIP_PVC="false"
PVC_STORAGE_CLASS=""

usage() {
  cat <<'EOF'
Usage: scripts/deploy_manual_no_operator.sh [options]

Options:
  -n, --namespace <ns>      Namespace (default: wl)
      --kc-cmd <cmd>        kubectl command (default: $KC_CMD or kubectl)
      --dry-run             Use kubectl apply --dry-run=client
      --create-namespace    Create namespace if missing (uses --namespace value)
      --with-pv             Also apply cluster-scoped PV manifest (k8s/pv.yaml)
      --skip-pvc            Skip namespace-scoped PVC manifest (k8s/pvc-weblogic-home.yaml)
      --pvc-storage-class   Patch pvc-weblogic-home to use this StorageClass
  -h, --help                Show help

Examples:
  scripts/deploy_manual_no_operator.sh
  scripts/deploy_manual_no_operator.sh -n wl --kc-cmd "kubectl --context mycluster"
  scripts/deploy_manual_no_operator.sh --with-pv
  scripts/deploy_manual_no_operator.sh --skip-pvc
  scripts/deploy_manual_no_operator.sh --create-namespace --with-pv --pvc-storage-class metro-nas
  scripts/deploy_manual_no_operator.sh --dry-run
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
    --create-namespace)
      CREATE_NAMESPACE="true"
      shift 1
      ;;
    --with-pv)
      APPLY_PV="true"
      shift 1
      ;;
    --skip-pvc)
      SKIP_PVC="true"
      shift 1
      ;;
    --pvc-storage-class)
      PVC_STORAGE_CLASS="$2"
      shift 2
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
  "k8s/pv.yaml"
  "k8s/pvc-weblogic-home.yaml"
  "k8s/gen-ssh-keys-config.yaml"
  "k8s/weblogic-authorized-keys.yaml"
  "k8s/services-clusterip.yaml"
  "k8s/services-nodeports.yaml"
  "k8s/deploy-test-db.yaml"
  "k8s/overlays/manual/deploy-wls-admin.yaml"
  "k8s/overlays/manual/deploy-wls-managed-1.yaml"
  "k8s/overlays/manual/deploy-wls-managed-2.yaml"
  "k8s/overlays/manual/deploy-wls-managed-3.yaml"
)

for manifest in "${MANIFESTS[@]}"; do
  if [ ! -f "$REPO_ROOT/$manifest" ]; then
    echo "Missing manifest: $manifest" >&2
    exit 1
  fi
done

if [ "$CREATE_NAMESPACE" = "true" ]; then
  echo "==> Ensuring namespace exists: $NAMESPACE"
  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] ${KC_CMD} get namespace $NAMESPACE || ${KC_CMD} create namespace $NAMESPACE"
  else
    "${KC[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1 || "${KC[@]}" create namespace "$NAMESPACE"
  fi
fi

echo "Repo root: $REPO_ROOT"
echo "Namespace: $NAMESPACE"
echo "kubectl cmd: $KC_CMD"
echo "Dry run: $DRY_RUN"
echo "Create namespace: $CREATE_NAMESPACE"
echo "Apply PV: $APPLY_PV"
echo "Skip PVC: $SKIP_PVC"
echo "PVC storageClass patch: ${PVC_STORAGE_CLASS:-<none>}"

echo
for manifest in "${MANIFESTS[@]}"; do

  if [ "$manifest" = "k8s/pv.yaml" ] && [ "$APPLY_PV" != "true" ]; then
    echo "==> Skipping $manifest (default behavior; use --with-pv to apply it)"
    continue
  fi

  if [ "$manifest" = "k8s/pvc-weblogic-home.yaml" ] && [ "$SKIP_PVC" = "true" ]; then
    echo "==> Skipping $manifest (--skip-pvc)"
    continue
  fi

  echo "==> Applying $manifest"
  if [ "$DRY_RUN" = "true" ]; then
    "${KC[@]}" apply --dry-run=client -f "$REPO_ROOT/$manifest" -n "$NAMESPACE"
  else
    set +e
    out=$("${KC[@]}" apply -f "$REPO_ROOT/$manifest" -n "$NAMESPACE" 2>&1)
    rc=$?
    set -e

    if [ $rc -ne 0 ]; then
      if [ "$manifest" = "k8s/pv.yaml" ] && echo "$out" | grep -qiE 'forbidden|cannot create resource|persistentvolumes'; then
        echo "$out" >&2
        echo "WARN: PV creation forbidden. Continuing without k8s/pv.yaml." >&2
        echo "      If PVC stays Pending, set --pvc-storage-class <class> or ask platform team for storage." >&2
        continue
      fi
      echo "$out" >&2
      exit $rc
    fi

    echo "$out"

    if [ "$manifest" = "k8s/pvc-weblogic-home.yaml" ] && [ -n "$PVC_STORAGE_CLASS" ]; then
      echo "==> Patching pvc-weblogic-home storageClassName=$PVC_STORAGE_CLASS"
      "${KC[@]}" patch pvc pvc-weblogic-home -n "$NAMESPACE" --type merge \
        -p "{\"spec\":{\"storageClassName\":\"$PVC_STORAGE_CLASS\"}}"
    fi
  fi
done

if [ "$DRY_RUN" = "true" ]; then
  echo
  echo "Dry-run complete. No resources were changed."
  exit 0
fi

echo
echo "Deployment complete. Current status:"
"${KC[@]}" get pods -n "$NAMESPACE" -o wide || true
"${KC[@]}" get svc -n "$NAMESPACE" || true
"${KC[@]}" get pvc -n "$NAMESPACE" || true

