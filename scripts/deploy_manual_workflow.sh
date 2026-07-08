#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Defaults
OVERLAY_REL="k8s/overlays/manual"
OUT_DIR_REL="ready2apply"
OUT_FILE_NAME="manual-no-operator.rendered.yaml"
DRY_RUN="false"
SHOW_DIFF="false"

usage() {
  cat <<'EOF'
Workflow: kustomize build → kubectl apply.

This script assumes:
  - cli_yaml_config_fill has ALREADY been run (optional, user responsibility)
  - k8s/overlays/manual/ contains the templates/resources to build
  - kustomize build renders to ready2apply/

Usage:
  scripts/deploy_manual_workflow.sh [OPTIONS]

Options:
  --overlay <path>         Overlay directory (default: k8s/overlays/manual)
  --out-dir <path>         Output directory (default: ready2apply)
  --out-file <name|path>   Output file name
  --dry-run                Apply with --dry-run=client
  --diff                   Run kubectl diff before apply
  -h, --help               Show this help

Workflow steps:
  1. (User prerequisite) cli_yaml_config_fill fills templates with values
  2. kustomize build k8s/overlays/manual > ready2apply/...
  3. kubectl apply -f ready2apply/...

Example:
  # Step 1: Fill (from yaml_config_support repo, user's responsibility)
  python ../yaml_config_support/scripts/cli_yaml_config_fill.py dev

  # Step 2-3: Build + Apply
  bash scripts/deploy_manual_workflow.sh
  bash scripts/deploy_manual_workflow.sh --diff --dry-run
EOF
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command not found: $1"
}

resolve_path() {
  local candidate="$1"
  if [[ "$candidate" = /* ]]; then
    printf '%s\n' "$candidate"
  else
    printf '%s/%s\n' "$REPO_ROOT" "$candidate"
  fi
}

resolve_kustomizer() {
  if command -v kustomize >/dev/null 2>&1; then
    printf 'kustomize\n'
  elif command -v kubectl >/dev/null 2>&1; then
    printf 'kubectl\n'
  else
    die "Neither 'kustomize' nor 'kubectl' available."
  fi
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overlay)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --overlay"
      OVERLAY_REL="$1"
      ;;
    --out-dir)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --out-dir"
      OUT_DIR_REL="$1"
      ;;
    --out-file)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --out-file"
      OUT_FILE_NAME="$1"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --diff)
      SHOW_DIFF="true"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

OVERLAY_DIR="$(resolve_path "$OVERLAY_REL")"
OUT_DIR="$(resolve_path "$OUT_DIR_REL")"
OUT_FILE="$OUT_DIR/$OUT_FILE_NAME"

[[ -f "$OVERLAY_DIR/kustomization.yaml" ]] || die "No kustomization.yaml: $OVERLAY_DIR"
mkdir -p "$OUT_DIR"

log "Workflow: kustomize build → apply"
log "overlay=$OVERLAY_DIR"
log "output=$OUT_FILE"

# ========== BUILD ==========
KUSTOMIZER="$(resolve_kustomizer)"
log "renderer=$KUSTOMIZER"

TMP="$OUT_FILE.tmp"
if [[ "$KUSTOMIZER" == "kustomize" ]]; then
  kustomize build "$OVERLAY_DIR" > "$TMP"
else
  kubectl kustomize "$OVERLAY_DIR" > "$TMP"
fi

[[ -s "$TMP" ]] || die "Rendered manifest is empty"
mv "$TMP" "$OUT_FILE"
log "built=$OUT_FILE"

# ========== DIFF ==========
if [[ "$SHOW_DIFF" == "true" ]]; then
  require_cmd kubectl
  log "running kubectl diff"
  set +e
  kubectl diff -f "$OUT_FILE"
  rc=$?
  set -e
  [[ $rc -le 1 ]] || die "kubectl diff failed with rc=$rc"
fi

# ========== APPLY ==========
require_cmd kubectl

if [[ "$DRY_RUN" == "true" ]]; then
  log "applying dry-run"
  kubectl apply --dry-run=client -f "$OUT_FILE"
else
  log "applying"
  kubectl apply -f "$OUT_FILE"
fi

log "done"
