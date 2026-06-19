# YAML Fill Workflow für ansible_mk

## Übersicht

```
k8s/overlays/{dev,prod,test}/       ← Source of Truth (Templates)
           ↓
 [yaml_config_support CLI]           ← Configured via env.py -> env_wl_flowpad.py
           ↓
k8s/ready2apply/                    ← Generated, filled, ready to deploy
           ↓
./prepare_docker/bootstrap_cluster.sh OR scripts/deploy_manual_no_operator.sh
           ↓
Deployed on k8s cluster
```

## Setup

### 1. Prüfe die Konfiguration

```bash
cd /home/flow/dev_mk/ansible_mk
ls -l env.py
# env.py sollte auf env_wl_flowpad.py zeigen
```

### 2. Installiere yaml_config_support

```bash
# Falls noch nicht geschehen
pip install -e /home/flow/dev_flow/yaml_config_support
```

## Workflow

### Step 1: Fülle die Manifeste

```bash
cd /home/flow/dev_mk/ansible_mk

# Mit Wrapper-Skript (Overlay wird als Argument übergeben)
python3 /home/flow/dev_flow/yaml_config_support/scripts/cli_yaml_config_fill.py dev --overlay dev

# Beispiel für prod
python3 /home/flow/dev_flow/yaml_config_support/scripts/cli_yaml_config_fill.py prod --overlay prod
```

Das generiert: `k8s/ready2apply/deploy-wls-admin-dev.yaml` (und weitere)

### Step 2: Deploye

```bash
# Mit automatischer ready2apply-Detection + Fallback
./prepare_docker/bootstrap_cluster.sh

# Oder manual
scripts/deploy_manual_no_operator.sh -n weblogic
```

## Fallback-Logik

Beide Deploy-Skripte prüfen automatisch:

1. **Zuerst**: `k8s/ready2apply/<datei>.yaml` (gefüllt)
2. **Fallback**: `k8s/overlays/{minikube,manual}/<datei>.yaml` (Original)

Das ermöglicht ein **schrittweises Rollout** ohne komplette Migration.

## Wichtige Dateien

| Datei | Zweck |
|-------|-------|
| `env.py` | Symlink auf aktive Umgebungskonfiguration |
| `env_wl_flowpad.py` | Maßgebende CLI-Konfiguration |
| `k8s/overlays/{env}/` | Template-Overlays (Source of Truth) |
| `group_vars/all.yml` | Gemeinsame Werte |
| `group_vars/env_{dev,prod,test}.yml` | Environment-spezifische Werte |
| `k8s/ready2apply/` | Generierte Manifeste (ignoriert, wird bei Bedarf regeneriert) |
| `prepare_docker/bootstrap_cluster.sh` | Main deployment script |
| `scripts/deploy_manual_no_operator.sh` | Manual deployment option |

## Fehlerbehandlung

### ready2apply/ ist leer
→ Führe den Fill-Schritt erneut aus

### `env`-Importfehler im CLI-Wrapper
→ Aufruf aus Repo-Root starten und prüfen, dass `env.py` auf `env_wl_flowpad.py` zeigt

### Manifeste verwenden alte Werte
→ Prüfe `group_vars/` und regeneriere `ready2apply/`

## Notizen

- `ready2apply/` wird **nicht** in Git committed (nur `.gitkeep` + README)
- Maßgebend ist `env_wl_flowpad.py` (indirekt via `env.py`)
- Source of Truth bleibt in den **Overlays** und **group_vars**
- Die CLI ist optional; du kannst auch direkt die Overlays deployen

