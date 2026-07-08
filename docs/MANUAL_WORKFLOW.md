# Manual WebLogic Deployment Workflow (cli_yaml_config_fill + kustomize)

Dieser Guide beschreibt den **empfohlenen end-to-end Workflow** für den manuellen WebLogic-Deployment ohne Operator.

## Überblick

```
┌─────────────────────────────────────────────────────────────┐
│ Schritt 1: cli_yaml_config_fill (optional)                  │
│   - Lädt Basis-Templates aus k8s/overlays/manual/            │
│   - Wendet Overlay-Dateien an (from yaml_config_support)     │
│   - Schreibt gefüllte YAMLs                                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│ Schritt 2: deploy_manual_workflow.sh (Kustomize Build)       │
│   - kustomize build k8s/overlays/manual                      │
│   - → ready2apply/manual-no-operator.rendered.yaml           │
│   - Multi-Document mit allen Ressourcen (Namespace, PV,...)  │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│ Schritt 3: kubectl apply                                     │
│   - Wendet das finale Manifest auf den Cluster an           │
│   - Optional: --dry-run oder --diff vorher                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Szenario A: Nur kustomize, keine cli_yaml_config_fill

**Wenn**: deine Werte bereits in `k8s/overlays/manual/` stehen (oder dort Platzhalter sind).

```bash
cd /home/flow/dev_mk/ansible_mk

# Nur render (kein apply):
RENDER_ONLY=true bash scripts/deploy_manual_workflow.sh

# Ergebnis prüfen:
cat ready2apply/manual-no-operator.rendered.yaml

# Dann apply:
bash scripts/deploy_manual_workflow.sh
```

---

## Szenario B: cli_yaml_config_fill → kustomize (empfohlen)

**Wenn**: deine Werte in separaten, geheimen Dateien liegen (Harbor-URLs, Credentials, etc.).

### Prerequisite

Die `yaml_config_support` Bibliothek liegt eine Verzeichnisebene über `ansible_mk`:

```
/home/flow/dev_mk/
  ├── ansible_mk/                    ← aktuelles Repo
  │   └── scripts/deploy_manual_workflow.sh
  └── ../yaml_config_support/        ← dein Config-Tool
      └── scripts/cli_yaml_config_fill.py
```

### Schritt 1: cli_yaml_config_fill vorbereiten

Falls du noch einen Wrapper für dein Projekt brauchst, erstelle `scripts/config_fill_wrapper.sh`:

```bash
#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_TOOL_REPO="${REPO_ROOT}/../yaml_config_support"
ENV="${1:-dev}"

python3 "$CONFIG_TOOL_REPO/scripts/cli_yaml_config_fill.py" "$ENV" \
  --outdir "$REPO_ROOT/ready2apply-config"
```

### Schritt 2: Workflow ausführen

```bash
cd /home/flow/dev_mk/ansible_mk

# 1. Werte füllen (optional)
bash scripts/config_fill_wrapper.sh dev

# 2. Kustomize build + apply
bash scripts/deploy_manual_workflow.sh --diff --dry-run

# Wenn Output OK, dann richtig applyen:
bash scripts/deploy_manual_workflow.sh
```

---

## Schritt für Schritt: Was passiert

### Phase 1: cli_yaml_config_fill (optional)

```bash
python ../yaml_config_support/scripts/cli_yaml_config_fill.py dev
```

Das Tool:
1. Lädt `templates/values_onefitsall.yaml` (aus yaml_config_support)
2. Wendet Overlays an (aus `private/` oder `project/`)
3. Schreibt `ready2apply-config/cf-dev/updated_values-dev.yaml`

**Beispiel output**:
```yaml
harbor_registry: "harbor.firma.de"
harbor_project: "weblogic"
postgres_image: "harbor.firma.de/weblogic/postgres_15:1.0"
weblogic_admin_password: "TopSecret123!"
# ... weitere aufgelöste Werte
```

### Phase 2: deploy_manual_workflow.sh (kustomize build)

```bash
bash scripts/deploy_manual_workflow.sh
```

Das Script:
1. Ruft `kustomize build k8s/overlays/manual` auf
2. Rendert alle YAMLs in `k8s/overlays/manual/` + Patches
3. Schreibt das fertige Multi-Document nach `ready2apply/manual-no-operator.rendered.yaml`

**Beispiel output** (Multi-Doc, `---` getrennt):
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: weblogic
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-weblogic-home
...
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wls-admin
spec:
  template:
    spec:
      containers:
      - image: harbor.firma.de/weblogic/postgres_15:1.0  # ← aus cli_yaml_config_fill
...
```

### Phase 3: kubectl apply

```bash
bash scripts/deploy_manual_workflow.sh
```

Das Script applyt `ready2apply/manual-no-operator.rendered.yaml` auf den Cluster.

---

## Optionen für `deploy_manual_workflow.sh`

```bash
# Nur Dry-Run (kein Apply)
bash scripts/deploy_manual_workflow.sh --dry-run

# Mit Diff vorher anschauen
bash scripts/deploy_manual_workflow.sh --diff

# Beides kombiniert
bash scripts/deploy_manual_workflow.sh --diff --dry-run

# Anderer Output-Pfad
bash scripts/deploy_manual_workflow.sh --out-dir /tmp/manifests
```

---

## Wichtige Punkte

| Punkt | Lösung |
|---|---|
| **Wo bleiben sensitive Werte?** | In `private/` Dateien (außerhalb Repo), nur bei cli_yaml_config_fill-Lauf aufgelöst |
| **Wo landet der Output?** | `ready2apply/` (gitignored wegen aufgelöster Secrets) |
| **Kann ich erst rendern, dann applyen?** | Ja: `--dry-run` zum testen, dann ohne Flag applyen |
| **Was ist in `ready2apply/...yaml`?** | Multi-Document YAML mit **allen** Ressourcen am Stück (Namespace, PV, Deployments, etc.) |
| **Wie oft muss ich cli_yaml_config_fill aufrufen?** | Nur wenn sich deine Werte ändern (z.B. andere Harbor-URL) |

---

## Troubleshooting

### Error: `No kustomization.yaml: k8s/overlays/manual`

Überprüfe, dass `k8s/overlays/manual/kustomization.yaml` existiert.

### Error: `Neither 'kustomize' nor 'kubectl' available`

Install `kustomize` (oder nutze `kubectl kustomize` falls vorhanden):

```bash
# Über Package-Manager
sudo apt install kustomize  # Debian/Ubuntu
sudo dnf install kustomize  # RHEL/Fedora

# Oder via Go
go install sigs.k8s.io/kustomize/kustomize/v5@latest
```

### Manifest ist leer oder enthält nur Namespace

- Überprüfe `k8s/overlays/manual/kustomization.yaml` auf die `resources:` Liste
- Sicherstellen, dass alle referenzierten Dateien existieren

---

## Checkliste vor dem Deploy

- [ ] `k8s/overlays/manual/` hat `kustomization.yaml`
- [ ] Alle Ressourcen-Dateien sind in der `resources:` Liste referenziert
- [ ] (Falls cli_yaml_config_fill) `yaml_config_support` ist verfügbar
- [ ] (Falls cli_yaml_config_fill) Overlay-Dateien haben die richtigen Werte
- [ ] `kustomize` oder `kubectl` ist installiert
- [ ] `kubectl` ist gegen den richtigen Cluster konfiguriert
- [ ] Namespace `weblogic` existiert (oder wird vom Manifest erzeugt)
- [ ] StorageClass ist korrekt für deine Umgebung

---

## Nächste Schritte

1. **Werte separieren**: Nutze `yaml_config_support` für Harbor-URLs/Secrets
2. **Umgebungen managen**: `--config-env prod|staging|dev` je nach Bedarf
3. **Automation**: Einbauen in CI/CD (GitLab CI, GitHub Actions, etc.)
4. **Monitoring**: Nach Deploy: Pod-Status, Logs, Domain CR Status prüfen

