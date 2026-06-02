#!/usr/bin/env bash
set -euo pipefail

# Minimal helper: build wls-dev into Minikube's docker daemon and restart deployments
# No heavy checks; adjust env vars if needed

MINIKUBE_PROFILE=${MINIKUBE_PROFILE:-wlcluster}
IMAGE_TAG=${IMAGE_TAG:-wls-dev:1.3}
PUBKEY=${PUBKEY:-${HOME}/.ssh/id_ed25519_docker.pub}
NAMESPACE=${NAMESPACE:-weblogic}

echo "Building image $IMAGE_TAG locally and loading into minikube ($MINIKUBE_PROFILE)"
docker build -t "$IMAGE_TAG" images/wls-dev \
  --build-arg SSH_PUBKEY="$(sed -n '1p' "$PUBKEY")"

echo "Loading image into minikube"
minikube -p "$MINIKUBE_PROFILE" image load "$IMAGE_TAG"

echo "Restarting WLS deployments in namespace $NAMESPACE"
# adjust deployments list if you changed names
kc rollout restart deployment/wls-admin -n "$NAMESPACE" || true
kc rollout restart deployment/wls-managed-1 -n "$NAMESPACE" || true
kc rollout restart deployment/wls-managed-2 -n "$NAMESPACE" || true
kc rollout restart deployment/wls-dev -n "$NAMESPACE" || true

echo "Done. Check pods:"
kc get pods -n "$NAMESPACE" -o wide

