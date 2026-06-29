#!/usr/bin/env bash
set -euo pipefail

# Push a locally available docker-archive tar to Harbor/another registry using skopeo.
# This is intended for environments where Docker is not available on the transfer host.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/scripts/manual_harbor.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

SOURCE_IMAGE="${SOURCE_IMAGE:-wls-dev:1.3}"
TARGET_IMAGE="${TARGET_IMAGE:-${WLS_IMAGE:-}}"
IMAGE_TAR="${IMAGE_TAR:-}"
DEST_CREDS="${DEST_CREDS:-}"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage: scripts/push_to_harbor.sh [options]

Options:
  --tar <path>              Path to docker-archive tar produced by docker save
							(required unless IMAGE_TAR is set in env file)
  --source-image <ref>      Image tag inside the archive (default: wls-dev:1.3)
  --target-image <ref>      Full registry target image, e.g. harbor.example.com/team/wls-dev:1.3
							(fallback: WLS_IMAGE from scripts/manual_harbor.env)
  --dest-creds <user:pass>  Optional skopeo destination credentials
  --dry-run                 Print the skopeo command without executing it
  -h, --help                Show help

Examples:
  scripts/push_to_harbor.sh \
	--tar /media/usb/wls-dev_manual_1.3.tar \
	--target-image harbor.example.com/team/wls-dev:1.3

  scripts/push_to_harbor.sh \
	--tar /media/usb/wls-dev_manual_bundle_1.3.tar \
	--source-image wls-dev:1.3 \
	--target-image harbor.example.com/team/wls-dev:1.3 \
	--dest-creds user:password
EOF
}

log() {
  echo "$*"
}

run() {
  if [ "$DRY_RUN" = "true" ]; then
	printf '[dry-run]'
	printf ' %q' "$@"
	printf '\n'
	return 0
  fi
  "$@"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
	--tar)
	  IMAGE_TAR="$2"
	  shift 2
	  ;;
	--source-image)
	  SOURCE_IMAGE="$2"
	  shift 2
	  ;;
	--target-image)
	  TARGET_IMAGE="$2"
	  shift 2
	  ;;
	--dest-creds)
	  DEST_CREDS="$2"
	  shift 2
	  ;;
	--dry-run)
	  DRY_RUN="true"
	  shift
	  ;;
	-h|--help)
	  usage
	  exit 0
	  ;;
	*)
	  echo "Unknown option: $1" >&2
	  usage
	  exit 1
	  ;;
  esac
done

if [ -z "$IMAGE_TAR" ]; then
  echo "Error: no archive specified. Use --tar or set IMAGE_TAR in scripts/manual_harbor.env." >&2
  exit 1
fi

if [ ! -f "$IMAGE_TAR" ]; then
  echo "Error: archive not found: $IMAGE_TAR" >&2
  exit 1
fi

if [ -z "$TARGET_IMAGE" ]; then
  echo "Error: no target image configured. Use --target-image or set WLS_IMAGE in scripts/manual_harbor.env." >&2
  exit 1
fi

if [ "$DRY_RUN" != "true" ] && ! command -v skopeo >/dev/null 2>&1; then
  echo "Error: skopeo not found in PATH. Use this script on a machine with skopeo installed." >&2
  exit 1
fi

SOURCE_REF="docker-archive:${IMAGE_TAR}:${SOURCE_IMAGE}"
DEST_REF="docker://${TARGET_IMAGE}"

SKOPEO_ARGS=(copy "$SOURCE_REF" "$DEST_REF")
if [ -n "$DEST_CREDS" ]; then
  SKOPEO_ARGS=(copy --dest-creds "$DEST_CREDS" "$SOURCE_REF" "$DEST_REF")
fi

log "Pushing archive image via skopeo"
log "  source archive: $IMAGE_TAR"
log "  source image:   $SOURCE_IMAGE"
log "  target image:   $TARGET_IMAGE"
run skopeo "${SKOPEO_ARGS[@]}"

log "Done. Registry image available as: $TARGET_IMAGE"

