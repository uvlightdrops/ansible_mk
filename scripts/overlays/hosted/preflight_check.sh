#!/usr/bin/env bash
set -euo pipefail

# Overlay-scoped entrypoint for hosted/operator deployments.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec "$REPO_ROOT/scripts/preflight_check.sh" "$@"

