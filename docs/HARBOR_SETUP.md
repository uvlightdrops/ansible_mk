# Harbor Setup für WebLogic Kubernetes Deployment

Dieser Guide zeigt, wie du dein WebLogic Container Image in Harbor vorbereitetest und ImagePullSecrets konfigurierst.

## Voraussetzungen

- Zugriff auf Harbor Registry (z.B. `harbor.example.com`)
- `skopeo` CLI lokal vorinstalliert
- Speichern von Harbor-Credentials für später

---

## Schritt 1: Harbor Project erstellen (falls nicht existiert)

Gehe zu Harbor UI:

1. **Projects** → **New Project**
2. Name: `weblogic`
3. Access Level: `Private` (sicherer)
4. Erstellen

---

## Schritt 2: Beliebiges Image in Harbor hochladen (mit skopeo)

**Wir nutzen `skopeo` — kein Docker, kein Root, kein lokaler Download nötig!**
`skopeo copy` überträgt direkt Registry → Registry (stream-basiert).

### Variante A: Script (empfohlen — liest Credentials aus `secrets.yml`)

```bash
# Einmalig secrets.yml befüllen:
#   group_vars/secrets.yml → vault_harbor_* Variablen setzen

# postgres:15 in Harbor laden:
bash scripts/harbor_push_image.sh postgres:15

# WebLogic Image laden:
bash scripts/harbor_push_image.sh oracle/weblogic:14.1.1.0-jdk17-ol8
```

Das Script gibt am Ende direkt den passenden **Kustomize-Snippet** aus:
```yaml
images:
  - name: postgres
    newName: harbor.example.com/weblogic/postgres
    newTag: "15"
```
→ Diesen in `k8s/overlays/manual/kustomization.yaml` unter `images:` eintragen.

### Variante B: Manuell mit skopeo

```bash
export HARBOR_HOST="harbor.CHANGEME.example.com"
export HARBOR_USER="dein_username"
export HARBOR_PASS="dein_passwort"

# Direkt von Docker Hub → Harbor (kein lokaler Speicher!)
skopeo copy \
  docker://postgres:15 \
  docker://${HARBOR_HOST}/weblogic/postgres:15 \
  --dest-creds="${HARBOR_USER}:${HARBOR_PASS}"

# WebLogic Image:
skopeo copy \
  docker://oracle/weblogic:14.1.1.0-jdk17-ol8 \
  docker://${HARBOR_HOST}/weblogic/wls:14.1.1.0-jdk17 \
  --dest-creds="${HARBOR_USER}:${HARBOR_PASS}"

# Überprüfen:
skopeo inspect \
  docker://${HARBOR_HOST}/weblogic/postgres:15 \
  --creds="${HARBOR_USER}:${HARBOR_PASS}"
```

### Option C: `docker save`-Archiv mit `skopeo` nach Harbor pushen (dockerloser Zielhost)

Wenn das Manual-Image als Tar vorliegt, z. B. auf USB:

```bash
cd /home/flow/dev_mk/ansible_mk
cp scripts/manual_harbor.env.example scripts/manual_harbor.env
# scripts/manual_harbor.env anpassen (IMAGE_TAR, WLS_IMAGE, optional DEST_CREDS)

scripts/push_to_harbor.sh
```

Oder ohne Env-Datei direkt:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/push_to_harbor.sh \
  --tar /media/<user>/<usb>/wls-dev_manual_1.3.tar \
  --source-image wls-dev:1.3 \
  --target-image harbor.example.com/<projekt>/wls-dev:1.3 \
  --dest-creds '<user>:<pass>'
```

Das Skript verwendet intern:

```bash
skopeo copy \
  docker-archive:/media/<user>/<usb>/wls-dev_manual_1.3.tar:wls-dev:1.3 \
  docker://harbor.example.com/<projekt>/wls-dev:1.3
```

---

## Schritt 3: Verifizieren

```bash
# Weboberfläche: Harbor → Projects → weblogic → Images
# Oder CLI: (falls Registry API verfügbar)
curl -u $HARBOR_USER:$HARBOR_PASS \
  "https://harbor.example.com/api/v2.0/projects/weblogic/repositories?page=1&page_size=10"
```

---

## Schritt 4: ImagePullSecret im Kubernetes erstellen

Das Playbook referenziert das Secret `wls-image-secret` in der Domain CR.  
Du musst es vorher manuell anlegen:

```bash
# Mit Base64-codierten Credentials
kubectl create secret docker-registry wls-image-secret \
  --docker-server=harbor.example.com \
  --docker-username=$HARBOR_USER \
  --docker-password=$HARBOR_PASSWORD \
  --docker-email="no-reply@example.com" \
  -n wl

# Verifizieren:
kubectl get secret wls-image-secret -n wl -o yaml
kubectl get secret wls-image-secret -n wl -o jsonpath='{.data.*}' | base64 -d | jq '.'
```

---

## Schritt 5: WebLogic Image-Name konfigurieren

Editiere `group_vars/secrets.yml`:

```yaml
vault_weblogic_image: "harbor.example.com/weblogic/wls:14.1.1.0-jdk17"
```

Falls du einen privaten Namespace nutzen möchtest:

```yaml
vault_weblogic_image: "harbor.example.com/mycompany/weblogic/wls:14.1.1.0-jdk17"
```

---

## Schritt 5b: Manuellen Deployment-Pfad mit Harbor nutzen

Fuer den manuellen Pfad ohne Operator:

```bash
cd /home/flow/dev_mk/ansible_mk
cp scripts/manual_harbor.env.example scripts/manual_harbor.env
# scripts/manual_harbor.env anpassen (KC_CMD, WLS_IMAGE, optional DB_IMAGE)
scripts/deploy_manual_harbor.sh
```

Ohne Config-Datei:

```bash
cd /home/flow/dev_mk/ansible_mk
scripts/deploy_manual_harbor.sh \
  --kc-cmd "kubectl --context <dein-context>" \
  --image harbor.example.com/<projekt>/wls-dev:1.3 \
  --db-image harbor.example.com/<projekt>/postgres:15
```

Hinweis: `--db-image` ist nur noetig, wenn eure Policy auch das Standard-Image `postgres:15` blockiert.

Wichtig: Der Dateiname eines `docker save`-Archivs ist nur Transport-Metadaten. Der Harbor-Name kommt **nicht** vom Tar-Dateinamen, sondern vom Ziel `docker://...` bei `skopeo copy` bzw. `scripts/push_to_harbor.sh --target-image ...`.

Wenn ein Archiv **mehrere Images/Manifeste** enthält, musst du bei `docker-archive:` zusätzlich die Quell-Image-Referenz angeben, z. B. `:wls-dev:1.3`. Genau das macht `scripts/push_to_harbor.sh` automatisch über `--source-image`.

---

## Schritt 6: Image Pull Policy

Falls du lokale, getestete Versionen verwenden möchtest:

```yaml
# In group_vars/all.yml oder environment-specific:

imagePullPolicy: IfNotPresent  # Use local image if available; fallback to Pull
# oder:
imagePullPolicy: Always        # Always pull (safer for CI/CD)
```

### Wann den Image-Tag hochsetzen?

- **Ja, Version hochsetzen**, wenn sich der Image-Inhalt geändert hat und das Ergebnis reproduzierbar in Harbor/Kubernetes landen soll.
- Besonders wichtig bei `imagePullPolicy: IfNotPresent`: Cluster-Nodes können sonst ein altes, gleichnamiges Image aus dem Cache behalten.
- Für das Repo bedeutet das aktuell typischerweise: lokaler Build `wls-dev:1.3` → bei echter neuer Version z. B. `wls-dev:1.4` bauen, pushen und in den Value-Dateien/Manifests referenzieren.

---

## Troubleshooting

### ImagePullBackOff Error

```bash
# Symptom:
kubectl describe pod <pod-name> -n wl
# → Events: ImagePullBackOff, pull access denied

# Behebung:
# 1. Secret prüfen
kubectl get secret wls-image-secret -n wl -o yaml

# 2. Credentials prüfen
echo -n "user:password" | base64

# 3. Image-URL prüfen
kubectl get secret wls-image-secret -n wl -o jsonpath='{.data.\.dockercfg}' | base64 -d | jq '.auths'

# 4. Zugriff auf Image testen (ohne Docker)
skopeo inspect \
  docker://harbor.example.com/weblogic/wls:14.1.1.0 \
  --creds="${HARBOR_USER}:${HARBOR_PASSWORD}"
```

### Secret nach dem erstellen aktualisieren

```bash
# Falls Credentials sich ändern:
kubectl delete secret wls-image-secret -n wl
kubectl create secret docker-registry wls-image-secret \
  --docker-server=harbor.example.com \
  --docker-username=$NEW_USER \
  --docker-password=$NEW_PASSWORD \
  -n wl

# Pods neustarten, um neues Secret zu laden
kubectl rollout restart deployment/wls-admin -n wl
kubectl rollout restart statefulset/wls-managed-1 -n wl
# ... etc
```

---

## Checkliste für diesen Schritt

- [ ] Harbor Project `weblogic` erstellt
- [ ] WebLogic Image zu Harbor gepusht (mit `skopeo`)
- [ ] Image-Name und Tag notiert: `harbor.example.com/weblogic/wls:14.1.1.0-jdk17`
- [ ] ImagePullSecret `wls-image-secret` in Namespace `weblogic` erstellt
- [ ] Credentials im Secret geprüft + verifiziert
- [ ] `vault_weblogic_image` in `group_vars/secrets.yml` aktualisiert
- [ ] Image-Zugriff getestet: `skopeo inspect docker://<image> --creds="user:pass"`

---

## Next: Playbook starten

Wenn alles vorbereitet:

```bash
cd /home/flow/dev_mk/ansible_mk

# Pre-flight-Check
bash scripts/overlays/hosted/preflight_check.sh wl

# Ansible spielen starten (hosted cluster)
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml
```

---

## Sicherheits-Note

- **Credentials**: Nutze Ansible Vault oder External Secrets statt reiner YAML
- **Image-Registry**: Verwende private und gesicherte Registries
- **Secret-Management**: Rotiere Regular Credentials in Harbor
