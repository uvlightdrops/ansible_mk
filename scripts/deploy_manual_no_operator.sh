#!/usr/bin/env bash
set -euo pipefail

# Deploy WebLogic resources without Operator/Domain CR.
# Applies manifests in a fixed order.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NAMESPACE="weblogic"
KC_CMD="${KC_CMD:-kubectl}"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage: scripts/deploy_manual_no_operator.sh [options]

Options:
  -n, --namespace <ns>      Namespace (default: weblogic)
      --kc-cmd <cmd>        kubectl command (default: $KC_CMD or kubectl)
      --dry-run             Use kubectl apply --dry-run=client
  -h, --help                Show help

Examples:
  scripts/deploy_manual_no_operator.sh
  scripts/deploy_manual_no_operator.sh -n weblogic --kc-cmd "kubectl --context mycluster"
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
  "k8s/namespace.yaml"
  "k8s/pv.yaml"
  "k8s/pvc-weblogic-home.yaml"
  "k8s/gen-ssh-keys-config.yaml"
  "k8s/weblogic-authorized-keys.yaml"
  "k8s/services-clusterip.yaml"
  "k8s/services-nodeports.yaml"
  "k8s/deploy-test-db.yaml"
  "k8s/deploy-wls-admin.yaml"
  "k8s/deploy-wls-managed-1.yaml"
  "k8s/deploy-wls-managed-2.yaml"
  "k8s/deploy-wls-managed-3.yaml"
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

echo
for manifest in "${MANIFESTS[@]}"; do
  echo "==> Applying $manifest"
  if [ "$DRY_RUN" = "true" ]; then
    "${KC[@]}" apply --dry-run=client -f "$REPO_ROOT/$manifest" -n "$NAMESPACE"
  else
    "${KC[@]}" apply -f "$REPO_ROOT/$manifest" -n "$NAMESPACE"
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

