#!/usr/bin/env bash
set -euo pipefail

# bootstrap_cluster.sh
# Full "from-scratch" setup of the WebLogic dev environment on Minikube.
#
# Phases (all enabled by default; skip with --no-<phase>):
#   1. minikube start
#   2. Build wls-dev image + load into minikube
#   3. Regenerate k8s/weblogic-authorized-keys.yaml from current pubkey
#   4. Apply all k8s manifests in dependency order
#   5. Prepare SSH on minikube node containers (deploy-ssh-keys.sh)
#   6. Wait for all pods to become Ready
#   7. Quick SSH connectivity check via NodePorts
#
# Usage: ./bootstrap_cluster.sh [options]
#   -n namespace        (default: weblogic)
#   -k kc_cmd           (default: kc)
#   --profile PROFILE   minikube profile (default: wlcluster)
#   --nodes N           minikube node count for new cluster (default: 3)
#   --pubkey PATH       public key to inject into pods (default: ~/.ssh/id_ed25519_docker.pub)
#   --privkey PATH      private key for SSH test (default: ~/.ssh/id_ed25519_docker)
#   --image-tag TAG     docker image tag (default: wls-dev:1.3)
#   --no-start          skip phase 1 (minikube start)
#   --no-build          skip phase 2 (image build + load)
#   --no-ssh-prep       skip phase 5 (SSH key prep on nodes)
#   --no-wait           skip phase 6 (pod readiness wait)
#   --no-ssh-test       skip phase 7 (SSH test)
#   --wait-timeout T    pod wait timeout (default: 180s)

NAMESPACE="weblogic"
MK_PRF="${MK_PRF:-wlcluster}"
MK_NODES="${MK_NODES:-3}"
PUBKEY="${PUBKEY:-${HOME}/.ssh/id_ed25519_docker.pub}"
PRIVKEY="${PRIVKEY:-${HOME}/.ssh/id_ed25519_docker}"
IMAGE_TAG="${IMAGE_TAG:-wls-dev:1.3}"
WAIT_TIMEOUT="180s"

DO_START=1
DO_BUILD=1
DO_SSH_PREP=1
DO_WAIT=1
DO_SSH_TEST=1

source "$(dirname "$0")/common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)      MK_PRF="$2";        shift 2 ;;
    --nodes)        MK_NODES="$2";      shift 2 ;;
    --pubkey)       PUBKEY="$2";        shift 2 ;;
    --privkey)      PRIVKEY="$2";       shift 2 ;;
    --image-tag)    IMAGE_TAG="$2";     shift 2 ;;
    --wait-timeout) WAIT_TIMEOUT="$2";  shift 2 ;;
    --no-start)     DO_START=0;         shift ;;
    --no-build)     DO_BUILD=0;         shift ;;
    --no-ssh-prep)  DO_SSH_PREP=0;      shift ;;
    --no-wait)      DO_WAIT=0;          shift ;;
    --no-ssh-test)  DO_SSH_TEST=0;      shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^[^#]/{/^[^#]/q; s/^# \{0,1\}//; p}' "$0"
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

step() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

apply() {
  echo "  apply $1"
  $KC_CMD apply -f "$REPO_ROOT/$1"
}

# ── Phase 1: minikube start ────────────────────────────────────────────────────
if [ "$DO_START" -eq 1 ]; then
  step "Phase 1/7 – minikube start (profile=$MK_PRF nodes=$MK_NODES)"
  if minikube status -p "$MK_PRF" --format='{{.Host}}' 2>/dev/null | grep -q "^Running$"; then
    echo "  Cluster already running – skipping start."
  else
    minikube start -p "$MK_PRF" --nodes="$MK_NODES" --driver=docker --cpus=4 --memory=8192
  fi
else
  echo "[skip] Phase 1: minikube start"
fi

# ── Phase 2: build + load image ───────────────────────────────────────────────
if [ "$DO_BUILD" -eq 1 ]; then
  step "Phase 2/7 – Build $IMAGE_TAG and load into minikube"
  if [ ! -f "$PUBKEY" ]; then
    echo "ERROR: pubkey not found: $PUBKEY" >&2; exit 2
  fi
  docker build -t "$IMAGE_TAG" "$REPO_ROOT/images/wls-dev" \
    --build-arg SSH_PUBKEY="$(sed -n '1p' "$PUBKEY")"
  minikube -p "$MK_PRF" image load "$IMAGE_TAG"
  echo "  Image $IMAGE_TAG loaded into $MK_PRF."
else
  echo "[skip] Phase 2: image build"
fi

# ── Phase 3: regenerate authorized-keys ConfigMap ─────────────────────────────
step "Phase 3/7 – Regenerate k8s/weblogic-authorized-keys.yaml"
if [ ! -f "$PUBKEY" ]; then
  echo "ERROR: pubkey not found: $PUBKEY" >&2; exit 2
fi
$KC_CMD create configmap weblogic-authorized-keys \
  --from-file=id_ed25519_docker.pub="$PUBKEY" \
  -n "$NAMESPACE" --dry-run=client -o yaml \
  > "$REPO_ROOT/k8s/weblogic-authorized-keys.yaml"
echo "  Written: k8s/weblogic-authorized-keys.yaml"

# ── Phase 4: apply manifests in dependency order ──────────────────────────────
step "Phase 4/7 – Applying k8s manifests"

# Cluster-scoped first
apply k8s/namespace.yaml
apply k8s/storageclass-manual.yaml
apply k8s/pv.yaml

# Check PV status and warn if Released (stale from previous run)
PV_PHASE=$($KC_CMD get pv pv-weblogic-home -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")
if [ "$PV_PHASE" = "Released" ]; then
  echo "  WARNING: PV is in 'Released' state (leftover from previous PVC)."
  echo "  Patching claimRef to make it Available again..."
  $KC_CMD patch pv pv-weblogic-home \
    --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]' 2>/dev/null || true
fi

# Namespace-scoped resources
apply k8s/pvc-weblogic-home.yaml
apply k8s/gen-ssh-keys-config.yaml
apply k8s/weblogic-authorized-keys.yaml
apply k8s/services-clusterip.yaml
apply k8s/services-nodeports.yaml

# Deployments last (depend on ConfigMaps + PVC)
apply k8s/deploy-wls-admin.yaml
apply k8s/deploy-wls-managed-1.yaml
apply k8s/deploy-wls-managed-2.yaml
apply k8s/deploy-wls-managed-3.yaml
apply k8s/deploy-test-db.yaml

echo "  All manifests applied."

# ── Phase 5: SSH prep on minikube node containers ─────────────────────────────
if [ "$DO_SSH_PREP" -eq 1 ]; then
  step "Phase 5/7 – SSH key prep on minikube nodes"
  cd "$REPO_ROOT"
  MK_PRF="$MK_PRF" CONTAINER_PREFIX="$MK_PRF" PUBKEY_PATH="$PUBKEY" \
    bash prepare_docker/deploy-ssh-keys.sh
else
  echo "[skip] Phase 5: SSH node prep"
fi

# ── Phase 6: wait for pods ────────────────────────────────────────────────────
if [ "$DO_WAIT" -eq 1 ]; then
  step "Phase 6/7 – Waiting for pods (timeout=$WAIT_TIMEOUT)"
  for label in app=wls-admin app=wls-managed-1 app=wls-managed-2 app=wls-managed-3 app=test-db; do
    printf "  waiting: %-25s ... " "-l $label"
    if $KC_CMD wait pod -l "$label" -n "$NAMESPACE" \
         --for=condition=ready --timeout="$WAIT_TIMEOUT" 2>/dev/null; then
      echo "Ready"
    else
      echo "TIMEOUT (check: kc describe pod -l $label -n $NAMESPACE)"
    fi
  done
  echo ""
  $KC_CMD get pods -n "$NAMESPACE" -o wide
else
  echo "[skip] Phase 6: pod wait"
fi

# ── Phase 7: SSH connectivity test ────────────────────────────────────────────
if [ "$DO_SSH_TEST" -eq 1 ]; then
  step "Phase 7/7 – SSH connectivity test via NodePorts"
  NODE_IP=""
  NODE_IP=$($KC_CMD get nodes \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
    2>/dev/null || true)
  if [ -z "$NODE_IP" ]; then
    NODE_IP=$(minikube ip -p "$MK_PRF" 2>/dev/null || true)
  fi

  if [ -z "$NODE_IP" ]; then
    echo "  Warning: could not determine node IP – skipping SSH test." >&2
  else
    SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    all_ok=1
    for port in 30222 30223 30224 30225; do
      printf "  docker@%s:%s  ... " "$NODE_IP" "$port"
      # shellcheck disable=SC2086
      if ssh $SSH_OPTS -i "$PRIVKEY" -p "$port" docker@"$NODE_IP" 'echo SSH_OK' >/dev/null 2>&1; then
        echo "OK ✓"
      else
        echo "FAILED ✗"
        all_ok=0
      fi
    done
    if [ "$all_ok" -eq 0 ]; then
      echo ""
      echo "  Some SSH tests failed. The pod may still be initializing."
      echo "  Retry: PYTHONPATH=. python3 prepare_docker_py/cli.py loop-test-ssh $NODE_IP \\"
      echo "           --ports 30222,30223,30224,30225 -k $PRIVKEY"
    fi
  fi
else
  echo "[skip] Phase 7: SSH test"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  Bootstrap complete."
echo "  Pods:     kc get pods -n $NAMESPACE -o wide"
echo "  SSH:      ssh -i $PRIVKEY -p 30222 docker@<NODE_IP>"
echo "  Ansible:  ansible-playbook -i inventory.yaml ansible/bootstrap_nodes.yml"
echo "  Teardown: ./prepare_docker/teardown_namespace.sh --all --purge-data -y"
echo "═══════════════════════════════════════════════════════════════════"


