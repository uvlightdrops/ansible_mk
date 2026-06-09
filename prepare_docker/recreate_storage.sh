#!/usr/bin/env bash
set -euo pipefail

# recreate_storage.sh
# Löscht und recreiert StorageClass, PersistentVolume und PersistentVolumeClaim.
# Nützlich nach einem teardown --all, wenn PV/StorageClass weg sind, aber der
# Cluster noch läuft (kein voller bootstrap_cluster.sh nötig).
#
# Optional: --purge-data  löscht /mnt/weblogic/pv-home auf allen minikube-Nodes
#           -y / --yes    überspringt Bestätigungs-Prompt
#
# Usage:
#   ./prepare_docker/recreate_storage.sh [-n namespace] [-k kc_cmd] [--purge-data] [-y]

MK_PRF="${MK_PRF:-wlcluster}"
PV_PATH="${PV_PATH:-/mnt/weblogic/pv-home}"
PURGE_DATA=0
AUTO_YES=0

source "$(dirname "$0")/common.sh"
consumed=$(parse_common_args "$@") || exit 1
shift "$consumed"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --purge-data) PURGE_DATA=1; shift ;;
    -y|--yes)     AUTO_YES=1;   shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^[^#]/{/^[^#]/q; s/^# \{0,1\}//; p}' "$0"
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== recreate_storage: namespace=$NAMESPACE  purge_data=$PURGE_DATA  profile=$MK_PRF ==="
if [ "$AUTO_YES" -eq 0 ]; then
  printf "Fortfahren? [y/N] "
  read -r ans
  case "$ans" in
    [yY]*) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ── 1. Optionales HostPath-Wipe auf allen minikube-Nodes ──────────────────────
if [ "$PURGE_DATA" -eq 1 ]; then
  echo ""
  echo "─── Purging $PV_PATH auf minikube-Nodes (Prefix: $MK_PRF) ───"
  containers=$(docker ps --format '{{.Names}}' | grep "^${MK_PRF}" || true)
  if [ -z "$containers" ]; then
    echo "Warning: keine minikube-Container mit Prefix '$MK_PRF' gefunden" >&2
  else
    for c in $containers; do
      echo "  $c: rm -rf $PV_PATH && mkdir + chown"
      docker exec --privileged -u root "$c" rm -rf "$PV_PATH" || true
      docker exec --privileged -u root "$c" mkdir -p "$PV_PATH" || true
      docker exec --privileged -u root "$c" chown -R 1000:1000 "$PV_PATH" || true
      docker exec --privileged -u root "$c" chmod 700 "$PV_PATH" || true
    done
  fi
  echo "  Purge done."
fi

# ── 2. Alte Ressourcen entfernen (falls noch vorhanden) ───────────────────────
echo ""
echo "─── Cleanup: PVC / PV / StorageClass (ignore-not-found) ───"
$KC_CMD delete pvc -n "$NAMESPACE" --all --ignore-not-found=true
$KC_CMD delete pv pv-weblogic-home --ignore-not-found=true
$KC_CMD delete storageclass manual --ignore-not-found=true

# ── 3. Namespace sicherstellen ────────────────────────────────────────────────
echo ""
echo "─── Namespace $NAMESPACE sicherstellen ───"
$KC_CMD apply -f "$REPO_ROOT/k8s/namespace.yaml"

# ── 4. StorageClass + PV + PVC neu anlegen ────────────────────────────────────
echo ""
echo "─── StorageClass / PV / PVC anlegen ───"
$KC_CMD apply -f "$REPO_ROOT/k8s/storageclass-manual.yaml"
$KC_CMD apply -f "$REPO_ROOT/k8s/pv.yaml"

# PV-Status prüfen – sollte sofort Available sein
PV_PHASE=$($KC_CMD get pv pv-weblogic-home -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")
echo "  PV-Phase nach Apply: $PV_PHASE"
if [ "$PV_PHASE" = "Released" ]; then
  echo "  Patch: entferne claimRef (Released -> Available)..."
  $KC_CMD patch pv pv-weblogic-home \
    --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]' 2>/dev/null || true
fi

$KC_CMD apply -f "$REPO_ROOT/k8s/pvc-weblogic-home.yaml"

# ── 5. Status-Ausgabe ─────────────────────────────────────────────────────────
echo ""
echo "─── Status ───"
$KC_CMD get storageclass 2>/dev/null || true
$KC_CMD get pv 2>/dev/null || true
$KC_CMD get pvc -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  recreate_storage abgeschlossen."
echo "  Nächster Schritt (nur Manifeste re-applyen, kein rebuild):"
echo "    ./prepare_docker/bootstrap_cluster.sh --no-start --no-build"
echo "═══════════════════════════════════════════════════════════════════"

