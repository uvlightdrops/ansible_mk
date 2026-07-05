#!/usr/bin/env bash
# =============================================================================
# harbor_push_image.sh
# Kopiert ein öffentliches Image direkt in die eigene Harbor-Registry.
# Nutzt skopeo (kein Docker/Root nötig).
#
# Voraussetzung: group_vars/secrets.yml muss befüllt sein (vault_harbor_* Vars)
#
# Nutzung:
#   bash scripts/harbor_push_image.sh postgres:15
#   bash scripts/harbor_push_image.sh library/postgres:15
#   bash scripts/harbor_push_image.sh oracle/weblogic:14.1.1.0-jdk17-ol8
# =============================================================================
set -euo pipefail

# ---- Pfade ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_FILE="$REPO_ROOT/group_vars/secrets.yml"

# ---- Voraussetzungen prüfen -------------------------------------------------
if ! command -v skopeo &>/dev/null; then
  echo "❌ skopeo nicht gefunden."
  echo "   Führe dieses Script auf einem Host aus, auf dem skopeo verfügbar ist"
  echo "   (z.B. dein Admin-/Workstation-Host ohne Docker-Zwang)."
  exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "❌ $SECRETS_FILE nicht gefunden."
  echo "   → cp group_vars/secrets.yml.example group_vars/secrets.yml"
  echo "   → Datei befüllen, dann erneut ausführen."
  exit 1
fi

# ---- Secrets aus secrets.yml lesen (via Python/PyYAML) ---------------------
read_secret() {
  python3 -c "
import yaml
with open('$SECRETS_FILE') as f:
    d = yaml.safe_load(f)
val = str(d.get('$1', ''))
# Einfache Jinja2-Referenzen auflösen (1 Ebene)
for k, v in d.items():
    if isinstance(v, str) and '{{' not in v:
        val = val.replace('{{ ' + k + ' }}', v).replace('{{' + k + '}}', v)
print(val)
"
}

HARBOR_HOST=$(read_secret vault_harbor_registry)
HARBOR_PROJECT=$(read_secret vault_harbor_project)
HARBOR_USER=$(read_secret vault_harbor_user)
HARBOR_PASS=$(read_secret vault_harbor_password)

if [[ -z "$HARBOR_HOST" || "$HARBOR_HOST" == *"CHANGEME"* ]]; then
  echo "❌ vault_harbor_registry ist nicht gesetzt. Bitte secrets.yml befüllen."
  exit 1
fi
if [[ -z "$HARBOR_USER" || "$HARBOR_USER" == *"CHANGEME"* ]]; then
  echo "❌ vault_harbor_user ist nicht gesetzt. Bitte secrets.yml befüllen."
  exit 1
fi

# ---- Argument: Quell-Image --------------------------------------------------
SOURCE_IMAGE="${1:-}"
if [[ -z "$SOURCE_IMAGE" ]]; then
  echo "Nutzung: $0 <image:tag>"
  echo "Beispiele:"
  echo "  $0 postgres:15"
  echo "  $0 oracle/weblogic:14.1.1.0-jdk17-ol8"
  exit 1
fi

# Ziel-Tag: nur letzten Teil (ohne Registry-Prefix)
IMAGE_BASENAME=$(echo "$SOURCE_IMAGE" | sed 's|.*/||')
TARGET_IMAGE="${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE_BASENAME}"

echo ""
echo "🔄 Quelle : docker://$SOURCE_IMAGE"
echo "🎯 Ziel   : docker://$TARGET_IMAGE"
echo "👤 User   : $HARBOR_USER @ $HARBOR_HOST"
echo ""

# ---- skopeo copy (Registry → Registry, kein lokaler Pull!) ------------------
skopeo copy \
  "docker://${SOURCE_IMAGE}" \
  "docker://${TARGET_IMAGE}" \
  --dest-creds="${HARBOR_USER}:${HARBOR_PASS}"

echo ""
echo "✅ Fertig! Image verfügbar unter: $TARGET_IMAGE"
echo ""

# Kustomize-Snippet für Overlay ausgeben
IMAGE_NAME=$(echo "$IMAGE_BASENAME" | cut -d: -f1)
IMAGE_TAG=$(echo  "$IMAGE_BASENAME" | cut -d: -f2)
echo "👉 Füge das in deinen Kustomize-Overlay ein (k8s/overlays/manual/kustomization.yaml):"
echo ""
echo "   images:"
echo "     - name: ${IMAGE_NAME}"
echo "       newName: ${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE_NAME}"
echo "       newTag: \"${IMAGE_TAG}\""
