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
VARIANT=${VARIANT:-minikube}   # minikube | manual | base

LOAD_MINIKUBE="false"
RESTART_WORKLOADS="false"
SAVE_TAR="/tmp/${IMAGE_TAG}.tar"  # LEAVE this as is

usage() {
  cat <<EOF
Usage: prepare_docker/build_and_deploy_wls_dev.sh [options]

Options:
  --variant <name>         Image variant to build: base | minikube | manual (default: minikube)
                            base     – heavy base layer (apt, users, Java) – build once
                            minikube – SSH + entrypoint; loads into minikube
                            manual   – slim/strict; no entrypoint; for hosted clusters
  --image-tag <tag>        Image tag (default: wls-dev:1.3)
  --pubkey <path>          SSH pubkey path – only used by minikube variant (default: ~/.ssh/id_ed25519_docker.pub)
  --save-tar <path>        Export built image as docker archive tar
  --load-minikube          Load image into minikube profile
  --restart                Restart WLS workloads after load (or on current KC_CMD)
  --profile <name>         Minikube profile (default: wlcluster)
  -n, --namespace <ns>     Namespace for restart/status (default: wl)
  --kc-cmd <cmd>           kubectl command for restart/status (default: kubectl)
  -h, --help               Show help

Examples:
  prepare_docker/build_and_deploy_wls_dev.sh --variant base
  prepare_docker/build_and_deploy_wls_dev.sh --variant minikube --load-minikube --restart
  prepare_docker/build_and_deploy_wls_dev.sh --variant manual --save-tar /tmp/wls-dev-manual.tar
  prepare_docker/build_and_deploy_wls_dev.sh --variant manual --kc-cmd "kubectl --context mycluster" --restart
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --variant)
      VARIANT="$2"; shift 2 ;;
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

# Validate variant
case "$VARIANT" in
  base|minikube|manual) ;;
  *) echo "Error: unknown --variant '$VARIANT'. Use: base | minikube | manual" >&2; exit 1 ;;
esac

BUILD_CONTEXT="images/wls-dev/$VARIANT"
if [ ! -f "$BUILD_CONTEXT/Dockerfile" ]; then
  echo "Error: Dockerfile not found in $BUILD_CONTEXT/" >&2
  exit 1
fi

# base variant uses a fixed tag; others use IMAGE_TAG
if [ "$VARIANT" = "base" ]; then
  EFFECTIVE_TAG="wls-dev:base"
else
  EFFECTIVE_TAG="$IMAGE_TAG"
fi

# minikube variant needs the pubkey
if [ "$VARIANT" = "minikube" ] && [ ! -f "$PUBKEY" ]; then
  echo "Error: pubkey not found: $PUBKEY (required for minikube variant)" >&2
  exit 1
fi

read -r -a KC <<<"$KC_CMD"

echo "Building variant '$VARIANT' → $EFFECTIVE_TAG (context: $BUILD_CONTEXT)"
if [ "$VARIANT" = "minikube" ]; then
  docker build -t "$EFFECTIVE_TAG" "$BUILD_CONTEXT" \
    --build-arg SSH_PUBKEY="$(sed -n '1p' "$PUBKEY")"
else
  docker build -t "$EFFECTIVE_TAG" "$BUILD_CONTEXT"
fi
echo "Built: $EFFECTIVE_TAG"

if [ -n "$SAVE_TAR" ]; then
  echo "Saving image archive to $SAVE_TAR"
  docker save -o "$SAVE_TAR" "$EFFECTIVE_TAG"
  echo "Archive size:"
  ls -lh "$SAVE_TAR"
fi

if [ "$LOAD_MINIKUBE" = "true" ]; then
  if ! command -v minikube >/dev/null 2>&1; then
    echo "Error: --load-minikube requested, but minikube is not installed." >&2
    exit 1
  fi
  echo "Loading image into minikube profile '$MINIKUBE_PROFILE'"
  minikube -p "$MINIKUBE_PROFILE" image load "$EFFECTIVE_TAG"
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

