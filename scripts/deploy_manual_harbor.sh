#!/usr/bin/env bash
set -euo pipefail

# Wrapper around deploy_manual_no_operator.sh for clusters enforcing foreign-registry policies.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_SCRIPT="$REPO_ROOT/scripts/deploy_manual_no_operator.sh"
ENV_FILE="$REPO_ROOT/scripts/manual_harbor.env"

# Optional host-local defaults (not tracked unless user creates the file).
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

NAMESPACE="${NAMESPACE:-wl}"
KC_CMD="${KC_CMD:-kubectl}"
IMAGE="${WLS_IMAGE:-}"
DB_IMAGE="${DB_IMAGE:-}"

EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: scripts/deploy_manual_harbor.sh [options]

Options:
  -n, --namespace <ns>      Namespace (default: wl)
      --kc-cmd <cmd>        kubectl command (default: $KC_CMD or kubectl)
      --image <ref>         Full image reference in allowed registry
                             (fallback: env var WLS_IMAGE)
      --db-image <ref>      Optional DB image reference in allowed registry
                             (fallback: env var DB_IMAGE)
      --dry-run             Forward to base deploy script
      --create-namespace    Forward to base deploy script
      --with-pv             Forward to base deploy script
      --skip-pvc            Forward to base deploy script
      --pvc-storage-class   Forward to base deploy script
  -h, --help                Show help

Examples:
  scripts/deploy_manual_harbor.sh --image harbor.example.com/team/wls-dev:1.3
  scripts/deploy_manual_harbor.sh --image harbor.example.com/team/wls-dev:1.3 --db-image harbor.example.com/team/postgres:15
  WLS_IMAGE=harbor.example.com/team/wls-dev:1.3 scripts/deploy_manual_harbor.sh
  scripts/deploy_manual_harbor.sh --kc-cmd "kubectl --context mycluster" --image harbor.example.com/team/wls-dev:1.3
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
      IMAGE="$2"
      shift 2
      ;;
    --db-image)
      DB_IMAGE="$2"
      shift 2
      ;;
    --dry-run|--create-namespace|--with-pv|--skip-pvc)
      EXTRA_ARGS+=("$1")
      shift 1
      ;;
    --pvc-storage-class)
      EXTRA_ARGS+=("$1" "$2")
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

if [ ! -x "$BASE_SCRIPT" ]; then
  echo "Error: Base deploy script is missing or not executable: $BASE_SCRIPT" >&2
  exit 1
fi

BASE_ARGS=(
  --namespace "$NAMESPACE"
  --kc-cmd "$KC_CMD"
  --image "$IMAGE"
)

if [ -z "$IMAGE" ]; then
  echo "Error: No image configured. Use --image or set WLS_IMAGE." >&2
  echo "Example: scripts/deploy_manual_harbor.sh --image harbor.example.com/team/wls-dev:1.3" >&2
  exit 1
fi

if [ -n "$DB_IMAGE" ]; then
  BASE_ARGS+=(--db-image "$DB_IMAGE")
fi

exec "$BASE_SCRIPT" \
  "${BASE_ARGS[@]}" \
  "${EXTRA_ARGS[@]}"


