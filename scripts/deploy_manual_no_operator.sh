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
IMAGE_OVERRIDE="${WLS_IMAGE:-}"
DB_IMAGE_OVERRIDE="${DB_IMAGE:-}"

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

render_manifest_for_apply() {
  local manifest="$1"
  local ready2apply_path="k8s/ready2apply/$(basename "$manifest")"

  # If manifest exists in ready2apply/, use that (filled by yaml_config_support)
  if [ -f "$REPO_ROOT/$ready2apply_path" ]; then
    cat "$REPO_ROOT/$ready2apply_path"
    return
  fi

  if [ -n "$IMAGE_OVERRIDE" ] && [[ "$manifest" == k8s/overlays/manual/deploy-wls-* ]]; then
    local escaped_image
    escaped_image="$(escape_sed_replacement "$IMAGE_OVERRIDE")"
    sed "s|image: wls-dev:1.3|image: ${escaped_image}|g" "$REPO_ROOT/$manifest"
    return
  fi

  if [ -n "$DB_IMAGE_OVERRIDE" ] && [ "$manifest" = "k8s/deploy-test-db.yaml" ]; then
    local escaped_db_image
    escaped_db_image="$(escape_sed_replacement "$DB_IMAGE_OVERRIDE")"
    sed "s|image: postgres:15|image: ${escaped_db_image}|g" "$REPO_ROOT/$manifest"
    return
  fi

  cat "$REPO_ROOT/$manifest"
}

ensure_registry_image_set() {
  local found_local_tag="false"
  local manifest

  [ -n "$IMAGE_OVERRIDE" ] && return 0

  # If ready2apply/ manifests exist, check those (they are the actual deploy source)
  local use_ready2apply="true"
  for base in deploy-wls-admin deploy-wls-managed-1 deploy-wls-managed-2 deploy-wls-managed-3; do
    if ! ls "$REPO_ROOT/k8s/ready2apply/${base}"*.yaml >/dev/null 2>&1; then
      use_ready2apply="false"
      break
    fi
  done

  if [ "$use_ready2apply" = "true" ]; then
    for yaml_file in "$REPO_ROOT/k8s/ready2apply/deploy-wls-"*.yaml; do
      if grep -qE '^\s*image:\s*wls-dev:[^ ]+\s*$' "$yaml_file"; then
        found_local_tag="true"
        break
      fi
    done
  else
    for manifest in \
      "k8s/overlays/manual/deploy-wls-admin.yaml" \
      "k8s/overlays/manual/deploy-wls-managed-1.yaml" \
      "k8s/overlays/manual/deploy-wls-managed-2.yaml" \
      "k8s/overlays/manual/deploy-wls-managed-3.yaml"; do
      if grep -qE '^\s*image:\s*wls-dev:[^ ]+\s*$' "$REPO_ROOT/$manifest"; then
        found_local_tag="true"
        break
      fi
    done
  fi

  if [ "$found_local_tag" = "true" ]; then
    echo "ERROR: WLS image is still set to local tag wls-dev:* in manifests." >&2
    echo "       Set an allowed registry image via --image or WLS_IMAGE," >&2
    echo "       or regenerate ready2apply/ with the correct registry URL." >&2
    echo "       Example: --image harbor.example.com/team/wls-dev:1.3" >&2
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Usage: scripts/deploy_manual_no_operator.sh [options]

Options:
  -n, --namespace <ns>      Namespace (default: wl)
      --kc-cmd <cmd>        kubectl command (default: $KC_CMD or kubectl)
      --image <ref>         Override image in manual WLS manifests
                             (or set env var WLS_IMAGE)
      --db-image <ref>      Override image in test-db manifest
                             (or set env var DB_IMAGE)
      --dry-run             Use kubectl apply --dry-run=client
      --create-namespace    Create namespace if missing (uses --namespace value)
      --with-pv             Also apply cluster-scoped PV manifest (k8s/pv.yaml)
      --skip-pvc            Skip namespace-scoped PVC manifest (k8s/pvc-weblogic-home.yaml)
      --pvc-storage-class   Patch pvc-weblogic-home to use this StorageClass
  -h, --help                Show help

Examples:
  scripts/deploy_manual_no_operator.sh
  scripts/deploy_manual_no_operator.sh -n wl --kc-cmd "kubectl --context mycluster"
  scripts/deploy_manual_no_operator.sh --image harbor.example.com/team/wls-dev:1.3
  scripts/deploy_manual_no_operator.sh --image harbor.example.com/team/wls-dev:1.3 --db-image harbor.example.com/team/postgres:15
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
    --image)
      IMAGE_OVERRIDE="$2"
      shift 2
      ;;
    --db-image)
      DB_IMAGE_OVERRIDE="$2"
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

ensure_registry_image_set

MANIFESTS=(
  "k8s/pv.yaml"
  "k8s/pvc-weblogic-home.yaml"
  "k8s/services-clusterip.yaml"
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
echo "Image override: ${IMAGE_OVERRIDE:-<none>}"
echo "DB image override: ${DB_IMAGE_OVERRIDE:-<none>}"

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
    render_manifest_for_apply "$manifest" | "${KC[@]}" apply --dry-run=client -f - -n "$NAMESPACE"
  else
    set +e
    out=$(render_manifest_for_apply "$manifest" | "${KC[@]}" apply -f - -n "$NAMESPACE" 2>&1)
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

