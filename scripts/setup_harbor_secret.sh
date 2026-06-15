#!/bin/bash
# Setup helper: Create ImagePullSecret and Harbor credentials
# Usage: ./setup_harbor_secret.sh <harbor-host> <username> [namespace]

set -e

HARBOR_HOST="${1:-}"
HARBOR_USER="${2:-}"
NAMESPACE="${3:-weblogic}"

if [ -z "$HARBOR_HOST" ] || [ -z "$HARBOR_USER" ]; then
  echo "Usage: $0 <harbor-host> <username> [namespace]"
  echo ""
  echo "Example:"
  echo "  $0 harbor.example.com myuser weblogic"
  echo ""
  exit 1
fi

echo "=========================================="
echo "Harbor ImagePullSecret Setup"
echo "=========================================="
echo "Host:      $HARBOR_HOST"
echo "User:      $HARBOR_USER"
echo "Namespace: $NAMESPACE"
echo ""

# Prompt for password
read -sp "Enter Harbor password for '$HARBOR_USER': " HARBOR_PASS
echo ""

# Verify namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "Error: Namespace '$NAMESPACE' does not exist."
  echo "Create it with: kubectl create namespace $NAMESPACE"
  exit 1
fi

# Create secret
echo ""
echo "Creating ImagePullSecret 'wls-image-secret' in namespace '$NAMESPACE'..."
kubectl create secret docker-registry wls-image-secret \
  --docker-server="$HARBOR_HOST" \
  --docker-username="$HARBOR_USER" \
  --docker-password="$HARBOR_PASS" \
  --docker-email="no-reply@example.com" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret created/updated"
echo ""

# Verify
echo "Verifying secret..."
if kubectl get secret wls-image-secret -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "✓ Secret exists in namespace '$NAMESPACE'"
  echo ""
  echo "Secret details:"
  kubectl get secret wls-image-secret -n "$NAMESPACE" -o yaml | grep -E 'name:|docker'
else
  echo "✗ Failed to create secret"
  exit 1
fi

echo ""
echo "=========================================="
echo "Next steps:"
echo "1. Update group_vars/all.yml with your WebLogic image:"
echo "   weblogic_image: \"$HARBOR_HOST/weblogic/wls:TAG\""
echo ""
echo "2. Run preflight check:"
echo "   bash scripts/preflight_check.sh $NAMESPACE"
echo ""
echo "3. Deploy with Ansible:"
echo "   ansible-playbook k8s_weblogic/deploy_weblogic.yml -e @group_vars/env_hosted.yml"
echo "=========================================="

