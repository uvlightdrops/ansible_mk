#!/usr/bin/env bash
# scripts/setup_venv.sh
#
# Erstellt ein Python-venv mit Ansible (ohne sudo benötigt).
# Einmalig ausführen, danach nur noch: source .venv/bin/activate
#
# Voraussetzung auf dem Control-Node (Jumphost/Workstation):
#   python3 (meist vorhanden, kein sudo nötig)
#   pip     (kommt mit python3)
#
# Auf dem Ziel-Host (Remote) braucht Ansible nur:
#   python3 (kein Ansible, kein sudo nötig)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"
REQUIREMENTS_TXT="${REPO_ROOT}/requirements.txt"
REQUIREMENTS_YML="${REPO_ROOT}/requirements.yml"
COLLECTIONS_PATH="${REPO_ROOT}/.venv/collections"

cd "${REPO_ROOT}"

echo "=== ansible_mk venv setup ==="
echo "Repo:        ${REPO_ROOT}"
echo "Venv:        ${VENV_DIR}"
echo ""

# ── 1. venv anlegen ──────────────────────────────────────────────────────────
if [[ ! -d "${VENV_DIR}" ]]; then
  echo "→ Erstelle venv..."
  python3 -m venv "${VENV_DIR}"
else
  echo "→ venv existiert bereits, überspringe Erstellung."
fi

# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

# ── 2. pip-Packages installieren ─────────────────────────────────────────────
echo ""
echo "→ Installiere pip-Packages (requirements.txt)..."
pip install --quiet --upgrade pip
pip install --quiet -r "${REQUIREMENTS_TXT}"

# ── 3. Ansible Collections installieren ─────────────────────────────────────
echo ""
echo "→ Installiere Ansible Collections (requirements.yml)..."
mkdir -p "${COLLECTIONS_PATH}"
ansible-galaxy collection install \
  -r "${REQUIREMENTS_YML}" \
  -p "${COLLECTIONS_PATH}" \
  --force

# ── 4. ansible.cfg mit Collections-Pfad aktualisieren ───────────────────────
# ansible.cfg liest collections_paths automatisch, wenn gesetzt
if ! grep -q "collections_path" "${REPO_ROOT}/ansible.cfg" 2>/dev/null; then
  echo ""
  echo "→ Füge collections_path zu ansible.cfg hinzu..."
  echo "" >> "${REPO_ROOT}/ansible.cfg"
  echo "# venv-lokale Collections (von setup_venv.sh):" >> "${REPO_ROOT}/ansible.cfg"
  echo "collections_path = .venv/collections" >> "${REPO_ROOT}/ansible.cfg"
fi

# ── 5. Zusammenfassung ───────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║  ✅  Setup abgeschlossen!                          ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Aktiviere die Umgebung mit:"
echo ""
echo "    source .venv/bin/activate"
echo ""
echo "Danach direkt loslegen:"
echo ""
echo "    ansible --version"
echo "    ansible-playbook k8s_weblogic/deploy_weblogic.yml -e @group_vars/env_manual.yml"
echo ""
echo "Um die Umgebung zu deaktivieren:"
echo "    deactivate"
echo ""

