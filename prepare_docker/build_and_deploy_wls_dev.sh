#!/usr/bin/env bash
set -euo pipefail

# Build helper for wls-dev image.
# Default behavior: only build locally.
# Optional flags can load into minikube, restart workloads, and export image as tar.

MINIKUBE_PROFILE=${MINIKUBE_PROFILE:-wlcluster}
IMAGE_TAG=${IMAGE_TAG:-wls-dev:1.3}
PUBKEY=${PUBKEY:-${HOME}/.ssh/id_ed25519_docker.pub}
NAMESPACE=${NAMESPACE:-wl}
KC_CMD=${KC_CMD:-kubectl}

LOAD_MINIKUBE="false"
RESTART_WORKLOADS="false"
SAVE_TAR=""

usage() {
  cat <<EOF
Usage: prepare_docker/build_and_deploy_wls_dev.sh [options]

Options:
  --image-tag <tag>        Image tag (default: wls-dev:1.3)
  --pubkey <path>          SSH pubkey path (default: ~/.ssh/id_ed25519_docker.pub)
  --save-tar <path>        Export built image as docker archive tar
  --load-minikube          Load image into minikube profile
  --restart                Restart WLS workloads after load (or on current KC_CMD)
  --profile <name>         Minikube profile (default: wlcluster)
  -n, --namespace <ns>     Namespace for restart/status (default: wl)
  --kc-cmd <cmd>           kubectl command for restart/status (default: kubectl)
  -h, --help               Show help

Examples:
  prepare_docker/build_and_deploy_wls_dev.sh
  prepare_docker/build_and_deploy_wls_dev.sh --save-tar /tmp/wls-dev_1.3.tar
  prepare_docker/build_and_deploy_wls_dev.sh --load-minikube --restart
  prepare_docker/build_and_deploy_wls_dev.sh --kc-cmd "kubectl --context mycluster" --restart
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image-tag)
      IMAGE_TAG="$2"; shift 2 ;;
    --pubkey)
      PUBKEY="$2"; shift 2 ;;
    --save-tar)
      SAVE_TAR="$2"; shift 2 ;;
    --load-minikube)
      LOAD_MINIKUBE="true"; shift ;;
    --restart)
      RESTART_WORKLOADS="true"; shift ;;
    --profile)
      MINIKUBE_PROFILE="$2"; shift 2 ;;
    -n|--namespace)
      NAMESPACE="$2"; shift 2 ;;
    --kc-cmd)
      KC_CMD="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found in PATH (build host required)." >&2
  exit 1
fi

if [ ! -f "$PUBKEY" ]; then
  echo "Error: pubkey not found: $PUBKEY" >&2
  exit 1
fi

read -r -a KC <<<"$KC_CMD"

echo "Building image $IMAGE_TAG locally"
docker build -t "$IMAGE_TAG" images/wls-dev \
  --build-arg SSH_PUBKEY="$(sed -n '1p' "$PUBKEY")"

if [ -n "$SAVE_TAR" ]; then
  echo "Saving image archive to $SAVE_TAR"
  docker save -o "$SAVE_TAR" "$IMAGE_TAG"
  echo "Archive size:"
  ls -lh "$SAVE_TAR"
fi

if [ "$LOAD_MINIKUBE" = "true" ]; then
  if ! command -v minikube >/dev/null 2>&1; then
    echo "Error: --load-minikube requested, but minikube is not installed." >&2
    exit 1
  fi
  echo "Loading image into minikube profile '$MINIKUBE_PROFILE'"
  minikube -p "$MINIKUBE_PROFILE" image load "$IMAGE_TAG"
fi

if [ "$RESTART_WORKLOADS" = "true" ]; then
  echo "Restarting WLS workloads in namespace $NAMESPACE"
  "${KC[@]}" rollout restart deployment/wls-admin -n "$NAMESPACE" || true
  "${KC[@]}" rollout restart statefulset/wls-managed-1 -n "$NAMESPACE" || true
  "${KC[@]}" rollout restart statefulset/wls-managed-2 -n "$NAMESPACE" || true
  "${KC[@]}" rollout restart statefulset/wls-managed-3 -n "$NAMESPACE" || true

  echo "Current pod status:"
  "${KC[@]}" get pods -n "$NAMESPACE" -o wide || true
fi

echo "Done."

