#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Defaults
OVERLAY_REL="k8s/overlays/manual"
OUT_DIR_REL="ready2apply"
OUT_FILE_NAME="manual-no-operator.rendered.yaml"
MODE="render-apply"           # render | apply | render-apply
RENDERER="auto"               # auto | kustomize | kubectl
DRY_RUN="false"
SHOW_DIFF="false"

usage() {
  cat <<'EOF'
Deploy manual no-operator manifests.

Usage:
  scripts/deploy_manual_no_operator.sh [OPTIONS] [overlay_dir] [out_dir]

Options:
  --overlay <path>       Overlay directory (default: k8s/overlays/manual)
  --out-dir <path>       Output directory for rendered YAML (default: ready2apply)
  --out-file <name|path> Output file name (or absolute path)
  --mode <mode>          render | apply | render-apply (default: render-apply)
  --renderer <type>      auto | kustomize | kubectl (default: auto)
  --render-only          Shortcut for: --mode render
  --apply-only           Shortcut for: --mode apply
  --dry-run              Apply with kubectl --dry-run=client
  --diff                 Run kubectl diff -f <file> before apply
  -h, --help             Show this help

Backward compatibility:
  positional #1: overlay_dir
  positional #2: out_dir

Notes:
  - Rendered output is never written into k8s/ source directories.
  - If RENDER_ONLY=true is set, mode is forced to "render".
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

resolve_renderer() {
  case "$RENDERER" in
    kustomize)
      require_cmd kustomize
      printf 'kustomize\n'
      ;;
    kubectl)
      require_cmd kubectl
      printf 'kubectl\n'
      ;;
    auto)
      if command -v kustomize >/dev/null 2>&1; then
        printf 'kustomize\n'
      elif command -v kubectl >/dev/null 2>&1; then
        printf 'kubectl\n'
      else
        die "Neither 'kustomize' nor 'kubectl' is available on this host."
      fi
      ;;
    *)
      die "Invalid renderer: $RENDERER"
      ;;
  esac
}

run_build() {
  local overlay_dir="$1"
  local renderer_resolved="$2"

  if [[ "$renderer_resolved" == "kustomize" ]]; then
    kustomize build "$overlay_dir"
  else
    kubectl kustomize "$overlay_dir"
  fi
}

run_diff() {
  local manifest_file="$1"

  require_cmd kubectl
  # kubectl diff returns:
  # 0 = no diff, 1 = diff found, >1 = error
  set +e
  kubectl diff -f "$manifest_file"
  local rc=$?
  set -e

  if [[ $rc -gt 1 ]]; then
    die "kubectl diff failed with exit code $rc"
  fi
}

run_apply() {
  local manifest_file="$1"

  require_cmd kubectl

  if [[ "$DRY_RUN" == "true" ]]; then
    kubectl apply --dry-run=client -f "$manifest_file"
  else
    kubectl apply -f "$manifest_file"
  fi
}

# Parse CLI args
POSITIONAL=()
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
    --mode)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --mode"
      MODE="$1"
      ;;
    --renderer)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --renderer"
      RENDERER="$1"
      ;;
    --render-only)
      MODE="render"
      ;;
    --apply-only)
      MODE="apply"
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
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL+=("$1")
        shift
      done
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      POSITIONAL+=("$1")
      ;;
  esac
  shift

done

# Backward compatibility with positional args
if [[ ${#POSITIONAL[@]} -ge 1 ]]; then
  OVERLAY_REL="${POSITIONAL[0]}"
fi
if [[ ${#POSITIONAL[@]} -ge 2 ]]; then
  OUT_DIR_REL="${POSITIONAL[1]}"
fi
if [[ ${#POSITIONAL[@]} -gt 2 ]]; then
  die "Too many positional arguments. Use --help for usage."
fi

# Legacy env compatibility
if [[ "${RENDER_ONLY:-false}" == "true" ]]; then
  MODE="render"
fi

case "$MODE" in
  render|apply|render-apply) ;;
  *) die "Invalid mode: $MODE" ;;
esac

OVERLAY_DIR="$(resolve_path "$OVERLAY_REL")"
OUT_DIR="$(resolve_path "$OUT_DIR_REL")"

if [[ "$OUT_FILE_NAME" = /* ]]; then
  OUT_FILE="$OUT_FILE_NAME"
else
  OUT_FILE="$OUT_DIR/$OUT_FILE_NAME"
fi

if [[ ! -f "$OVERLAY_DIR/kustomization.yaml" ]]; then
  die "No kustomization.yaml found in: $OVERLAY_DIR"
fi

mkdir -p "$OUT_DIR"

log "mode=$MODE"
log "overlay=$OVERLAY_DIR"
log "output=$OUT_FILE"

if [[ "$MODE" == "render" || "$MODE" == "render-apply" ]]; then
  RENDERER_RESOLVED="$(resolve_renderer)"
  log "renderer=$RENDERER_RESOLVED"

  TMP_OUT="$OUT_FILE.tmp"
  run_build "$OVERLAY_DIR" "$RENDERER_RESOLVED" > "$TMP_OUT"

  if [[ ! -s "$TMP_OUT" ]]; then
    rm -f "$TMP_OUT"
    die "Rendered manifest is empty: $TMP_OUT"
  fi

  mv "$TMP_OUT" "$OUT_FILE"
  log "rendered=$OUT_FILE"
fi

if [[ "$MODE" == "apply" || "$MODE" == "render-apply" ]]; then
  [[ -f "$OUT_FILE" ]] || die "Cannot apply; rendered manifest not found: $OUT_FILE"

  if [[ "$SHOW_DIFF" == "true" ]]; then
    log "running kubectl diff"
    run_diff "$OUT_FILE"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "applying with dry-run=client"
  else
    log "applying manifest"
  fi

  run_apply "$OUT_FILE"
  log "done"
fi
