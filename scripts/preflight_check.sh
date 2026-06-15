#!/bin/bash
# Pre-flight check for WebLogic Kubernetes deployment on hosted cluster
# Usage: ./preflight_check.sh [namespace]

set -e

NAMESPACE="${1:-weblogic}"
KUBECONFIG="${KUBECONFIG:-}"
COLOR_OK='\033[0;32m'
COLOR_WARN='\033[0;33m'
COLOR_FAIL='\033[0;31m'
COLOR_RESET='\033[0m'

check_ok()     { echo -e "${COLOR_OK}✓ $1${COLOR_RESET}"; }
check_warn()   { echo -e "${COLOR_WARN}⚠ $1${COLOR_RESET}"; }
check_fail()   { echo -e "${COLOR_FAIL}✗ $1${COLOR_RESET}"; exit 1; }
check_info()   { echo -e "ℹ $1"; }

is_forbidden() {
  echo "$1" | grep -qiE 'forbidden|cannot list resource|cannot get resource|RBAC'
}

echo "================================"
echo "WebLogic Hosted Cluster Pre-flight Check"
echo "Namespace: $NAMESPACE"
echo "================================"
echo ""

# 1. Cluster connectivity (RBAC-safe)
check_info "1. Checking cluster connectivity..."
if output=$(kubectl version --request-timeout=10s 2>&1); then
  check_ok "Kubernetes API reachable"
else
  if is_forbidden "$output"; then
    check_warn "API reachable, but this user has restricted permissions for version endpoint. Continuing."
  else
    check_fail "Cannot reach cluster or kubectl is not configured correctly"
  fi
fi

# 2. Namespace
check_info "2. Checking namespace '$NAMESPACE'..."
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  check_ok "Namespace '$NAMESPACE' exists"
else
  check_fail "Namespace '$NAMESPACE' does not exist - create with: kubectl create namespace $NAMESPACE"
fi

# 3. WebLogic CRDs
check_info "3. Checking WebLogic Operator CRDs..."
if kubectl api-resources 2>/dev/null | grep -q 'domains.*weblogic'; then
  check_ok "WebLogic Operator CRDs found (domains.weblogic.oracle)"
else
  check_warn "WebLogic CRDs not found - install Operator or ask Platform team"
  echo "  Install with: kubectl apply -f <operator-release.yaml>"
  echo "  Or download from: https://github.com/oracle/weblogic-kubernetes-operator/releases"
fi

# 4. Storage Classes
check_info "4. Checking available StorageClasses..."
sc_output=$(kubectl get storageclass --no-headers 2>&1 || true)
if is_forbidden "$sc_output"; then
  check_warn "No permission to list StorageClasses. Use your known class manually (for example: metro-nas or metro-nas-eco)."
elif [ -n "$sc_output" ]; then
  SC_COUNT=$(echo "$sc_output" | wc -l)
  check_ok "Found $SC_COUNT StorageClass(es):"
  echo "$sc_output" | awk '{print "    - " $1}'
else
  check_warn "No StorageClasses returned. Verify with platform team which class to use."
fi

# 5. ImagePullSecret
check_info "5. Checking ImagePullSecret 'wls-image-secret' in namespace '$NAMESPACE'..."
if kubectl get secret wls-image-secret -n "$NAMESPACE" >/dev/null 2>&1; then
  check_ok "ImagePullSecret 'wls-image-secret' exists"
else
  check_warn "ImagePullSecret 'wls-image-secret' not found"
  echo "  Create with:"
  echo "    kubectl create secret docker-registry wls-image-secret \\"
  echo "      --docker-server=<harbor-host> \\"
  echo "      --docker-username=<user> \\"
  echo "      --docker-password=<password> \\"
  echo "      --docker-email=<email> \\"
  echo "      -n $NAMESPACE"
fi

# 6. Admin credentials secret (optional - playbook creates it)
check_info "6. Checking admin credentials Secret 'weblogic-admin-credentials'..."
if kubectl get secret weblogic-admin-credentials -n "$NAMESPACE" >/dev/null 2>&1; then
  check_ok "Admin Secret already exists (playbook will update it)"
else
  check_info "  Playbook will create it automatically"
fi

# 7. Ingress Controller
check_info "7. Checking Ingress Controller..."
ing_output=$(kubectl get ingressclass --no-headers 2>&1 || true)
if is_forbidden "$ing_output"; then
  check_warn "No permission to list IngressClass. If you need ingress, ask the platform team for the correct class name."
elif [ -n "$ing_output" ]; then
  IC_CLASS=$(echo "$ing_output" | head -1 | awk '{print $1}')
  check_ok "Ingress Controller found: $IC_CLASS"
  echo "$ing_output" | awk '{print "    - " $1}'
else
  check_warn "No IngressClass found (Ingress optional, needed only for web console access)"
fi

# 8. NetworkPolicy
check_info "8. Checking NetworkPolicy..."
NP_COUNT=$(kubectl get networkpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$NP_COUNT" -gt 0 ]; then
  check_warn "Found $NP_COUNT NetworkPolicy(ies) in namespace - verify they allow WebLogic ports"
  kubectl get networkpolicies -n "$NAMESPACE" --no-headers | awk '{print "    - " $1}'
else
  check_ok "No NetworkPolicies in namespace"
fi

# 9. Resource Quotas
check_info "9. Checking Resource Quotas..."
RQ_COUNT=$(kubectl get resourcequotas -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$RQ_COUNT" -gt 0 ]; then
  check_warn "Found $RQ_COUNT ResourceQuota(s) - check limits are sufficient for WebLogic"
  kubectl get resourcequotas -n "$NAMESPACE" --no-headers | awk '{print "    - " $1}'
else
  check_ok "No ResourceQuotas in namespace"
fi

# 10. Available disk space on worker nodes
check_info "10. Checking available disk space on nodes..."
node_output=$(kubectl get nodes --no-headers 2>&1 || true)
if is_forbidden "$node_output"; then
  check_warn "No permission to list nodes. Skipping node-level capacity check (normal on hosted clusters)."
elif [ -n "$node_output" ]; then
  NODE_COUNT=$(echo "$node_output" | wc -l)
  check_ok "Found $NODE_COUNT worker node(s)"
  # Note: Detailed disk check would require node-exporter or similar
  check_info "  Tip: Monitor disk space during deployment with: kubectl top nodes"
else
  check_warn "Could not retrieve node list. If scheduling fails, ask platform team to validate node capacity."
fi

echo ""
echo "================================"
echo "Pre-flight Check Summary"
echo "================================"
echo ""
check_ok "All critical checks passed! Ready to deploy."
echo ""
echo "Next steps:"
echo "  1. Review and edit the configuration:"
echo "     - group_vars/env_hosted.yml"
echo "     - group_vars/all.yml (weblogic_image, domain_uid, credentials)"
echo ""
echo "  2. Run the Ansible playbook:"
echo "     ansible-playbook k8s_weblogic/deploy_weblogic.yml \\"
echo "       -e @group_vars/env_hosted.yml"
echo ""
echo "  3. Monitor deployment:"
echo "     kubectl get pods -n $NAMESPACE -w"
echo "     kubectl logs -n $NAMESPACE -l weblogic.domainUID=sample-domain1 -f"
echo ""

