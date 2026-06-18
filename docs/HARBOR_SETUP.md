# Harbor Setup für WebLogic Kubernetes Deployment

Dieser Guide zeigt, wie du dein WebLogic Container Image in Harbor vorbereitetest und ImagePullSecrets konfigurierst.

## Voraussetzungen

- Zugriff auf Harbor Registry (z.B. `harbor.example.com`)
- `skopeo` oder `docker` CLI lokal vorinstalliert
- Speichern von Harbor-Credentials für später

---

## Schritt 1: Harbor Project erstellen (falls nicht existiert)

Gehe zu Harbor UI:

1. **Projects** → **New Project**
2. Name: `weblogic`
3. Access Level: `Private` (sicherer)
4. Erstellen

---

## Schritt 2: WebLogic Image in Harbor uploaden

### Option A: Mit Skopeo (empfohlen, da du das schon nutzt)

```bash
# 1. Harbor Login prep (ggf. interaktiv)
export HARBOR_HOST="harbor.example.com"
export HARBOR_USER="<dein-username>"

# 2. Image hochladen (mit Authentifizierung)
skopeo copy docker://oracle/weblogic:14.1.1.0-jdk11-ol8 \
  docker://$HARBOR_HOST/weblogic/wls:14.1.1.0 \
  --dest-creds=$HARBOR_USER:$(pass show harbor-password)

# Oder einfacher: skopeo wird dich dann interaktiv fragen
skopeo copy docker://oracle/weblogic:14.1.1.0-jdk11-ol8 \
  docker://$HARBOR_HOST/weblogic/wls:14.1.1.0
```

### Option B: Mit Docker (falls lokal vorhanden)

```bash
# 1. Docker Login
docker login harbor.example.com

# 2. Tag und Push
docker tag oracle/weblogic:14.1.1.0-jdk11-ol8 \
  harbor.example.com/weblogic/wls:14.1.1.0

docker push harbor.example.com/weblogic/wls:14.1.1.0
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

## Schritt 5: WebLogic Image-Name in Ansible konfigurieren

Editiere `group_vars/all.yml`:

```yaml
weblogic_image: "harbor.example.com/weblogic/wls:14.1.1.0"
```

Falls du einen privaten Namespace nutzen möchtest:

```yaml
weblogic_image: "harbor.example.com/mycompany/weblogic/wls:14.1.1.0"
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

---

## Schritt 6: Image Pull Policy

Falls du lokale, getestete Versionen verwenden möchtest:

```yaml
# In group_vars/all.yml oder environment-specific:

imagePullPolicy: IfNotPresent  # Use local image if available; fallback to Pull
# oder:
imagePullPolicy: Always        # Always pull (safer for CI/CD)
```

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

# 4. Manuelles Login testen
docker login harbor.example.com
docker pull harbor.example.com/weblogic/wls:14.1.1.0
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
- [ ] WebLogic Image zu Harbor gepusht (mit `skopeo` oder `docker`)
- [ ] Image-Name und Tag notiert: `harbor.example.com/weblogic/wls:14.1.1.0`
- [ ] ImagePullSecret `wls-image-secret` in Namespace `wl` erstellt
- [ ] Credentials im Secret geprüft + verifiziert
- [ ] `weblogic_image` in `group_vars/all.yml` aktualisiert
- [ ] Lokal getestet: `docker pull <image>` mit Credentials aus dem Secret

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

