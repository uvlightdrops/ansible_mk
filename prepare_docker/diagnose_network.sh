#!/usr/bin/env bash
set -euo pipefail

# diagnose_network.sh
# Untersucht die Netzwerkkonfiguration auf einem neuen Host:
#   - Netzwerkinterfaces und IP-Adressen
#   - Belegte Subnetze / mögliche Konflikte mit 192.168.x.x
#   - Docker-Bridge-Netzwerke
#   - Minikube-Profil-Netzwerk (falls bereits vorhanden)
#   - Empfehlung für config.local.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ── helpers ───────────────────────────────────────────────────────────────────
hr() { printf '\n%s\n' "────────────────────────────────────────────────────────"; }
section() { hr; printf '  %s\n' "$*"; hr; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }
info() { printf '  · %s\n' "$*"; }

# ── 1. Host-Netzwerkinterfaces ─────────────────────────────────────────────────
section "1) Host-Netzwerkinterfaces (ip a)"
ip -brief address show 2>/dev/null || ifconfig 2>/dev/null || warn "ip/ifconfig nicht gefunden"

# ── 2. Routen ─────────────────────────────────────────────────────────────────
section "2) Routing-Tabelle"
ip route show 2>/dev/null || netstat -rn 2>/dev/null || warn "ip route / netstat nicht gefunden"

# ── 3. Belegte 192.168.x.x-Subnetze ──────────────────────────────────────────
section "3) Belegte 192.168.x.x-Subnetze (potenzielle Minikube-Konflikte)"
USED_192=$(ip route show 2>/dev/null | grep '192\.168\.' | awk '{print $1}' | sort -u || true)
if [ -z "$USED_192" ]; then
  ok "Kein 192.168.x.x-Subnetz aktuell belegt – Minikube kann frei wählen."
else
  for net in $USED_192; do
    warn "Bereits belegt: $net"
  done
  info "Minikube (Docker-Driver) bevorzugt 192.168.49.0/24 oder 192.168.58.0/24."
  info "Falls Konflikt: minikube start mit --network-plugin=cni oder anderem Profile."
fi

# ── 4. Docker-Bridge-Netzwerke ────────────────────────────────────────────────
section "4) Docker-Netzwerke"
if command -v docker >/dev/null 2>&1; then
  docker network ls
  echo ""
  info "Detaillierte Subnetz-Info:"
  docker network ls --format '{{.Name}}' | while read -r net; do
    subnet=$(docker network inspect "$net" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)
    driver=$(docker network inspect "$net" --format '{{.Driver}}' 2>/dev/null || true)
    [ -n "$subnet" ] && info "$net ($driver): $subnet"
  done
else
  warn "Docker nicht verfügbar oder nicht gestartet."
fi

# ── 5. Minikube-Status ────────────────────────────────────────────────────────
section "5) Minikube-Profile und Netzwerk"
if command -v minikube >/dev/null 2>&1; then
  echo "Installierte Profile:"
  minikube profile list 2>/dev/null || warn "Keine Profile gefunden / minikube noch nicht initialisiert."
  echo ""
  echo "Status Profil '$MK_PRF':"
  minikube status -p "$MK_PRF" 2>/dev/null || info "Profil '$MK_PRF' läuft nicht (OK – noch nicht gestartet)."
  echo ""
  echo "Minikube-Node-IPs (Profil '$MK_PRF'):"
  minikube -p "$MK_PRF" node list 2>/dev/null || info "Noch keine Nodes (Cluster nicht gestartet)."
  echo ""
  echo "Minikube-IP (falls Cluster läuft):"
  minikube ip -p "$MK_PRF" 2>/dev/null || info "Keine IP – Cluster nicht gestartet."
else
  warn "minikube nicht im PATH."
fi

# ── 6. SSH-Key-Verfügbarkeit ──────────────────────────────────────────────────
section "6) SSH-Keys"
for keyfile in "$PUBKEY" "$PRIVKEY"; do
  if [ -f "$keyfile" ]; then
    ok "vorhanden: $keyfile"
  else
    warn "FEHLT: $keyfile"
  fi
done

# ── 7. Empfehlung für config.local.sh ─────────────────────────────────────────
section "7) Empfehlung: prepare_docker/config.local.sh"
cat <<EOF
Passe folgende Werte auf diesem Host an:

  MK_PRF_DEFAULT="${MK_PRF}"
  PUBKEY_DEFAULT="<pfad zum pub-key>"
  PRIVKEY_DEFAULT="<pfad zum priv-key>"

Aktuelle Defaults (aus config.defaults.sh + ggf. config.local.sh):
  MK_PRF        = ${MK_PRF}
  NAMESPACE     = ${NAMESPACE}
  PUBKEY        = ${PUBKEY}
  PRIVKEY       = ${PRIVKEY}
  PV_PATH       = ${PV_PATH}
  IMAGE_TAG     = ${IMAGE_TAG}

Workflow nach Anpassung:
  ./prepare_docker/bootstrap_cluster.sh
  MK_PRF=${MK_PRF} ANSIBLE_SSH_KEY=${PRIVKEY} ./scripts/generate_inventory.py
EOF

hr
echo ""
echo "  Diagnose abgeschlossen."
echo ""

