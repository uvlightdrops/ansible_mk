# Dokumentation: WebLogic Kubernetes Deployment

Übersicht aller Guides für Minikube und Hosted Cluster.

---

## 🚀 Schnelleinstieg

**Zielgruppe:** Du willst SCHNELL starten, Details später

→ Lese **[QUICK_START.md](QUICK_START.md)**

10 Minuten bis zum ersten Deployment.

---

## 📚 Alle Guides (Übersicht)

### 1. **[QUICK_START.md](QUICK_START.md)** - 10-Minuten Guide
- ✨ Am schnellsten zum laufenden WebLogic
- 🔧 Für Hosted Cluster ohne viel Setup-Aufwand
- 📋 Häufige Fehler + schnelle Fixes

**Zielgruppe:** Impatient? Start here.

---

### 2. **[ENVIRONMENTS.md](ENVIRONMENTS.md)** - Overlay-Konzept
- 🎯 Warum Overlays statt Git-Branches?
- 📂 Struktur: `base/`, `overlays/minikube/`, `overlays/hosted/`
- 🔄 Wie man beide Umgebungen parallel pflegt

**Zielgruppe:** Architekten, wer das Konzept verstehen will.

---

### 3. **[HOSTED_SETUP_CHECKLIST.md](HOSTED_SETUP_CHECKLIST.md)** - Vollständige Vorbereitung
- ✅ Was schon vorhanden sein muss (Namespace, StorageClass)
- ❓ Was der Plattform-Team liefern sollte
- 📝 Konkrete Handlungsschritte
- 🔗 Queries für Pre-flight Checks

**Zielgruppe:** Projekt-Lead, Plattform-Koordinator.

---

### 4. **[OPERATOR_SETUP.md](OPERATOR_SETUP.md)** - WebLogic Operator Installation
- 🔍 Wie man prüft ob der Operator läuft
- 📦 Wie man ihn selbst installiert (falls nötig)
- 🐛 Troubleshooting: CRDs nicht da, Pod crasht, etc.
- 🧩 Nutzt `k8s/operator-hosted-values.yaml` und `scripts/render_weblogic_operator_manifest.sh`

**Zielgruppe:** Wer mit Operator-Installation zu tun hat.

---

### 5. **[HARBOR_SETUP.md](HARBOR_SETUP.md)** - Image-Registry Vorbereitung
- 🐳 WebLogic Image zu Harbor hochladen (Skopeo)
- 🔑 ImagePullSecret erstellen
- 🔐 Credentials sicher verwalten
- 🐛 ImagePullBackOff Behebung

**Zielgruppe:** DevOps, wer Images verwaltet.

---

### 6. **[WEBLOGIC_DEPLOYMENT.md](WEBLOGIC_DEPLOYMENT.md)** - Klassische Deployment-Anleitung
- 🏗️ Übersicht des gesamten Setups
- 📦 Manifeste Erklärung
- 🔧 Node-Vorbereitung (Minikube)
- 🛠️ Day-2 Operations

**Zielgruppe:** Alle, für Kontext und Nachschlagewerk.

---

### 7. **[AGENTS.md](AGENTS.md)** - Minikube-spezifische Dev-Workflows
- 👷 Local Development Tricks
- 🔄 SSH-Zugriff, Pod-Debuggen
- 📊 Operator-Status-Checks

**Zielgruppe:** Lokale Entwicklung mit Minikube.

---

## 🛠️ Hilfsskripte

Alle im `scripts/`-Verzeichnis.

### `preflight_check.sh`
```bash
bash scripts/preflight_check.sh [namespace]
```

**Was es macht:**
- Prüft Cluster-Konnektivität
- Prüft ob Namespace existiert
- Prüft WebLogic CRDs (Operator)
- Listet StorageClasses auf
- Prüft ImagePullSecret
- Prüft Ingress-Controller
- Warns bei NetworkPolicies/Quotas
- Gibt Next-Steps aus

**Wann:** VOR jedem Deployment

---

### `setup_harbor_secret.sh`
```bash
bash scripts/setup_harbor_secret.sh <harbor-host> <username> [namespace]
```

**Was es macht:**
- Fragt Passwort interaktiv (sicherer)
- Erstellt Docker-Registry-Secret
- Verifiziert das Secret
- Gibt Next-Steps aus

**Wann:** Nach dem Harbor-Image-Upload

---

### `render_weblogic_operator_manifest.sh`
```bash
bash scripts/render_weblogic_operator_manifest.sh [v4.3.9]
```

**Was es macht:**
- Klont den Operator-Source-Tag
- Rendert das Helm-Chart des WebLogic Operators
- Lädt die Domain- und Cluster-CRDs herunter
- Schreibt ein direkt anwendbares `k8s/operator.yaml`

**Wann:** Wenn du weiterhin mit einer einzelnen Manifestdatei arbeiten willst

---

## 🔄 Normales Deployment-Workflow

### 1. Pre-flight (einmalig pro Cluster)

```bash
# Operator-Status?
kubectl api-resources | grep domain

# ImagePullSecret?
bash scripts/setup_harbor_secret.sh harbor.example.com user

# Alles OK?
bash scripts/preflight_check.sh weblogic
```

### 2. Konfiguration (einmalig pro Deployment)

```bash
# Image setzen
cat group_vars/all.yml | grep weblogic_image

# StorageClass prüfen
cat k8s/overlays/hosted/patch-pvc-storageclass.yaml

# Admin-Passwort (optional, am besten mit Vault!)
# See: group_vars/all.yml oder `-e weblogic_admin_password=...`
```

### 3. Deployment

```bash
# Dry-Run (optional)
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml \
  --check

# Live
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml
```

### 4. Monitoring

```bash
# Live-Status
watch kubectl get pods -n weblogic

# Admin-Logs
kubectl logs -n weblogic -l weblogic.serverName=admin-server -f

# Domain-Status
kubectl describe domain sample-domain1 -n weblogic
```

---

## 🎯 Häufigste Fragen

**Q: Kann ich Minikube und Hosted parallel pflegen?**
A: Ja! Lese [ENVIRONMENTS.md](ENVIRONMENTS.md). Das ist genau dafür die Overlay-Struktur.

**Q: Was muss EH Plattform-Team installieren?**
A: Lese [HOSTED_SETUP_CHECKLIST.md](HOSTED_SETUP_CHECKLIST.md).

**Q: Der Operator ist nicht da — was tun?**
A: Lese [OPERATOR_SETUP.md](OPERATOR_SETUP.md).

**Q: Pod bleibt in ImagePullBackOff**
A: Lese [QUICK_START.md](QUICK_START.md#häufige-fehler) oder [HARBOR_SETUP.md](HARBOR_SETUP.md#troubleshooting).

**Q: Wie deploye ich auch auf Staging/Prod?**
A: Duplicate overlay: `k8s/overlays/staging/`, `k8s/overlays/prod/`. Copy-paste und anpassen.

**Q: Ich will erstmal ohne Operator manuell weitermachen — geht das?**
A: Ja, nutze `k8s/overlays/manual/` mit `-e @group_vars/env_manual.yml`.

---

## 🏗️ Datei-Struktur

```
docs/
├── AGENTS.md                    ← Local dev / Minikube workflows
├── ENVIRONMENTS.md              ← Overlay-Konzept & Warum Overlays
├── HARBOR_SETUP.md              ← Image-Registry (Skopeo, Credentials)
├── HOSTED_SETUP_CHECKLIST.md    ← Alles was auf dem Cluster sein muss
├── INDEX.md                     ← Diese Datei
├── OPERATOR_SETUP.md            ← WebLogic Operator Installation
├── QUICK_START.md               ← 10-Minuten deploy
└── WEBLOGIC_DEPLOYMENT.md       ← Klassische Anleitung (Referenz)

scripts/
├── preflight_check.sh           ← Pre-deployment validation
├── setup_harbor_secret.sh       ← ImagePullSecret helper
└── ...

k8s/
├── base/                        ← Portable manifests
│   └── kustomization.yaml
├── overlays/
│   ├── minikube/                ← Local dev
│   │   ├── kustomization.yaml
│   │   ├── patch-*.yaml
│   │   └── ...
│   └── hosted/                  ← Production-like
│       ├── kustomization.yaml
│       ├── patch-*.yaml
│       └── ...
├── *.yaml                       ← Shared manifests
└── ...

group_vars/
├── all.yml                      ← Base configuration
├── env_minikube.yml             ← Minikube environment
├── env_hosted.yml               ← Hosted cluster environment
├── env_manual.yml               ← Manual path without Operator
└── operator-hosted-values.yaml  ← Hosted operator Helm values
```

---

## 🚨 Notfall-Links

**Etwas kaputtgegangen?**

1. `kubectl describe <resource> -n weblogic` ← Das erste Kommando!
2. [QUICK_START.md#häufige-fehler](QUICK_START.md#häufige-fehler)
3. [HOSTED_SETUP_CHECKLIST.md](HOSTED_SETUP_CHECKLIST.md)
4. Starte mit [QUICK_START.md](QUICK_START.md) neu

---

## 📝 Leseanleitung nach Szenario

### Szenario A: "Ich will JETZT deployen"
1. [QUICK_START.md](QUICK_START.md)

### Szenario B: "Ich will's richtig verstehen"
1. [ENVIRONMENTS.md](ENVIRONMENTS.md)
2. [HOSTED_SETUP_CHECKLIST.md](HOSTED_SETUP_CHECKLIST.md)
3. [WEBLOGIC_DEPLOYMENT.md](WEBLOGIC_DEPLOYMENT.md)

### Szenario C: "Ich bin neuer DevOps in dem Projekt"
1. [WEBLOGIC_DEPLOYMENT.md](WEBLOGIC_DEPLOYMENT.md)
2. [ENVIRONMENTS.md](ENVIRONMENTS.md)
3. [HARBOR_SETUP.md](HARBOR_SETUP.md)

### Szenario D: "Ich bin Architekt / Platform Engineer"
1. [ENVIRONMENTS.md](ENVIRONMENTS.md)
2. [HOSTED_SETUP_CHECKLIST.md](HOSTED_SETUP_CHECKLIST.md)
3. [OPERATOR_SETUP.md](OPERATOR_SETUP.md)

### Szenario E: "Etwas funktioniert nicht"
→ [QUICK_START.md#häufige-fehler](QUICK_START.md#häufige-fehler)

---

## 🎓 Learning Path

**Wenn du vorher noch nie mit Kubernetes Operator deployed hast:**

1. **Grundkonzepte** → [WEBLOGIC_DEPLOYMENT.md](WEBLOGIC_DEPLOYMENT.md)
2. **Umgebungs-Modell** → [ENVIRONMENTS.md](ENVIRONMENTS.md)
3. **Hosted Cluster Realität** → [HOSTED_SETUP_CHECKLIST.md](HOSTED_SETUP_CHECKLIST.md)
4. **Images in Registry** → [HARBOR_SETUP.md](HARBOR_SETUP.md)
5. **Operator Setup** → [OPERATOR_SETUP.md](OPERATOR_SETUP.md)
6. **Erste Deployment** → [QUICK_START.md](QUICK_START.md)

---

Viel Erfolg! 🚀

Fragen? → Lese die relevant Datei oben.

Bei Bugs im Repo: → Schreib Issue oder Kommen Sie vorbei.

