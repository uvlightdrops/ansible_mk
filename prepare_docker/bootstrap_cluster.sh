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
#   5. Prepare SSH on minikube node containers (pd/deploy-ssh-keys.sh)
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
#   --force-build       always rebuild image in phase 2 (ignore smart-build cache)
#   --no-ssh-prep       skip phase 5 (SSH key prep on nodes)
#   --no-wait           skip phase 6 (pod readiness wait)
#   --no-ssh-test       skip phase 7 (SSH test)
#   --wait-timeout T    pod wait timeout (default: 180s)

WAIT_TIMEOUT="180s"

DO_START=1
DO_BUILD=1
DO_SSH_PREP=1
DO_WAIT=1
DO_SSH_TEST=1
FORCE_BUILD=0

source "$(dirname "$0")/common.sh"

bootstrap_usage_extra() {
  cat <<EOF
  --profile PROFILE   minikube profile (default: wlcluster)
  --nodes N           minikube node count for new cluster (default: 3)
  --pubkey PATH       public key to inject into pods (default: ~/.ssh/id_ed25519_docker.pub)
  --privkey PATH      private key for SSH test (default: ~/.ssh/id_ed25519_docker)
  --image-tag TAG     docker image tag (default: wls-dev:1.3)
  --no-start          skip phase 1 (minikube start)
  --no-build          skip phase 2 (image build + load)
  --force-build       always rebuild image in phase 2 (ignore smart-build cache)
  --no-ssh-prep       skip phase 5 (SSH key prep on nodes)
  --no-wait           skip phase 6 (pod readiness wait)
  --no-ssh-test       skip phase 7 (SSH test)
  --wait-timeout T    pod wait timeout (default: 180s)
EOF
}

help_bootstrap_cluster() {
  usage_render_script "$0 [options]" bootstrap_usage_extra
  exit 0
}

parse_bootstrap_cluster_arg() {
  case "$1" in
    --profile)      MK_PRF="$2";       PARSE_ARG_CONSUMED=2; return 0 ;;
    --nodes)        MK_NODES="$2";     PARSE_ARG_CONSUMED=2; return 0 ;;
    --pubkey)       PUBKEY="$2";       PARSE_ARG_CONSUMED=2; return 0 ;;
    --privkey)      PRIVKEY="$2";      PARSE_ARG_CONSUMED=2; return 0 ;;
    --image-tag)    IMAGE_TAG="$2";    PARSE_ARG_CONSUMED=2; return 0 ;;
    --wait-timeout) WAIT_TIMEOUT="$2"; PARSE_ARG_CONSUMED=2; return 0 ;;
    --no-start)     DO_START=0;         PARSE_ARG_CONSUMED=1; return 0 ;;
    --no-build)     DO_BUILD=0;         PARSE_ARG_CONSUMED=1; return 0 ;;
    --force-build)  FORCE_BUILD=1;      PARSE_ARG_CONSUMED=1; return 0 ;;
    --no-ssh-prep)  DO_SSH_PREP=0;      PARSE_ARG_CONSUMED=1; return 0 ;;
    --no-wait)      DO_WAIT=0;          PARSE_ARG_CONSUMED=1; return 0 ;;
    --no-ssh-test)  DO_SSH_TEST=0;      PARSE_ARG_CONSUMED=1; return 0 ;;
    *) return 1 ;;
  esac
}

parse_script_args help_bootstrap_cluster parse_bootstrap_cluster_arg "$@" || exit $?
init_kc_cmd

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

build_fingerprint() {
  {
    printf 'image_tag=%s\n' "$IMAGE_TAG"
    printf 'pubkey_sha=%s\n' "$(sha256sum "$PUBKEY" | awk '{print $1}')"
    find "$REPO_ROOT/images/wls-dev" -type f -print0 \
      | sort -z \
      | xargs -0 sha256sum
  } | sha256sum | awk '{print $1}'
}

step() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

apply() {
  echo "  apply $1"
  kc apply -f "$REPO_ROOT/$1"
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

  local_stamp_dir="$REPO_ROOT/prepare_docker/out.mk"
  local_stamp_file="$local_stamp_dir/wls-dev.build.stamp"
  mkdir -p "$local_stamp_dir"

  fp_current="$(build_fingerprint)"
  fp_cached=""
  if [ -f "$local_stamp_file" ]; then
    fp_cached="$(sed -n '1p' "$local_stamp_file" 2>/dev/null || true)"
  fi

  if [ "$FORCE_BUILD" -eq 0 ] \
    && [ -n "$fp_cached" ] \
    && [ "$fp_cached" = "$fp_current" ] \
    && docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    echo "  Build inputs unchanged – skipping docker build."
  else
    docker build -t "$IMAGE_TAG" "$REPO_ROOT/images/wls-dev" \
      --build-arg SSH_PUBKEY="$(sed -n '1p' "$PUBKEY")"
    printf '%s\n' "$fp_current" > "$local_stamp_file"
  fi

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
# Ensure namespace exists before creating namespace-scoped configmap YAML.
kc apply -f "$REPO_ROOT/k8s/namespace.yaml" >/dev/null
  kc create configmap weblogic-authorized-keys \
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
PV_PHASE=$(kc get pv pv-weblogic-home -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")
if [ "$PV_PHASE" = "Released" ]; then
  echo "  WARNING: PV is in 'Released' state (leftover from previous PVC)."
  echo "  Patching claimRef to make it Available again..."
  kc patch pv pv-weblogic-home \
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
    bash prepare_docker/pd/deploy-ssh-keys.sh
else
  echo "[skip] Phase 5: SSH node prep"
fi

# ── Phase 6: wait for pods ────────────────────────────────────────────────────
if [ "$DO_WAIT" -eq 1 ]; then
  step "Phase 6/7 – Waiting for pods (timeout=$WAIT_TIMEOUT)"
  for label in app=wls-admin app=wls-managed-1 app=wls-managed-2 app=wls-managed-3 app=test-db; do
    printf "  waiting: %-25s ... " "-l $label"
    if kc wait pod -l "$label" -n "$NAMESPACE" \
         --for=condition=ready --timeout="$WAIT_TIMEOUT" 2>/dev/null; then
      echo "Ready"
    else
      echo "TIMEOUT (check: kc describe pod -l $label -n $NAMESPACE)"
    fi
  done
  echo ""
  kc get pods -n "$NAMESPACE" -o wide
else
  echo "[skip] Phase 6: pod wait"
fi

# ── Phase 7: SSH connectivity test ────────────────────────────────────────────
if [ "$DO_SSH_TEST" -eq 1 ]; then
  step "Phase 7/7 – SSH connectivity test via NodePorts"
  NODE_IP=""
  NODE_IP=$(kc get nodes \
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
echo "  Teardown: ./prepare_docker/pd/teardown_namespace.sh --all --purge-data -y"
echo "═══════════════════════════════════════════════════════════════════"


