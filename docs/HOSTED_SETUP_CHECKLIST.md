# Hosted Kubernetes: Vorbereitungs-Checkliste für WebLogic Deployment

Diese Checkliste zeigt, was **DU** vorbereiten musst, bevor du das Playbook startest.

## Status der Vorbereitung

- [x] **Namespace** `weblogic` existiert (manuell eingerichtet)
- [x] **ImagePullSecret** für Harbor möglich (Skopeo-Zugang vorhanden)
- [x] **StorageClass** verfügbar: `metro-nas` oder `metro-nas-eco`
- [ ] **WebLogic CRDs** im Cluster installiert (Operator)?
- [ ] **ImagePullSecret** konkret angelegt/uploaded
- [ ] **WebLogic Container Image** in Harbor vorhanden
- [ ] **Domain Admin Secret** geplant
- [ ] **RBAC ServiceAccount** ggf. nötig
- [ ] **Ingress** für Web-UI geplant
- [ ] **NetworkPolicy** geklärt

---

## Was du jetzt tun musst

### 1. WebLogic Operator installieren – **WICHTIG**

Das Playbook deployt automatisch die **Domain CR**, aber es braucht einen **WebLogic Operator** im Cluster, der die Domain verwaltet.

**Option A: Operator ist zentral installiert (Plattform-Team)**
```bash
# Checken:
kubectl api-resources | grep domain
# Sollte etwas anzeigen mit weblogic
```

**Option B: Du installierst den Operator selbst (im Namespace oder cluster-wide)**

```bash
# 1. Download: WebLogic Operator Release
#    Gehe zu: https://github.com/oracle/weblogic-kubernetes-operator/releases
#    Wähle passende Version (z.B. v4.1.x)

# 2. Beispiel-Download:
curl -L -o /tmp/weblogic-operator.yaml \
  https://github.com/oracle/weblogic-kubernetes-operator/releases/download/v4.1.0/weblogic-operator.yaml

# 3. Änderungen für Hosted Cluster (wichtig!):
#    - Namespace: ändern auf 'weblogic' (oder wo nötig)
#    - ClusterRole/ClusterRoleBinding: ggf. auf namespaced Role einschränken
#    - Prüfe: werden CRDs mitinstalliert?

# 4. Im Playbook registrieren:
cp /tmp/weblogic-operator.yaml /home/flow/dev_mk/ansible_mk/k8s/operator.yaml

# 5. Playbook wird es dann im `hosted`-Overlay anwenden (falls apply_operator="true")
#    Oder: manuell mit kubectl apply -f /tmp/weblogic-operator.yaml
```

### 2. ImagePullSecret für Harbor vorbereiten

Das braucht die Domain CR, um Images zu pullen.

```bash
# Generiere Secret mit deinen Harbor-Credentials
kubectl create secret docker-registry wls-image-secret \
  --docker-server=<harbor-host> \
  --docker-username=<dein-user> \
  --docker-password=<dein-passwort> \
  --docker-email=<dein-email> \
  -n weblogic \
  --dry-run=client -o yaml | kubectl apply -f -

# Verifizieren:
kubectl get secrets -n weblogic
kubectl get secret wls-image-secret -n weblogic -o yaml
```

### 3. WebLogic Container Image in Harbor verfügbar

Stelle sicher, dass das Image, das du in `group_vars/all.yml` angibst, auch in Harbor vorhanden ist.

```bash
# Beispiel: du hast ein lokales WebLogic Image
skopeo copy docker://oracle/weblogic:14.1.1.0 \
  docker://<harbor-host>/weblogic/wls:14.1.1.0
```

### 4. Storage Class auswählen

In `k8s/overlays/hosted/patch-pvc-storageclass.yaml` editieren:

```yaml
spec:
  storageClassName: metro-nas
  # oder: metro-nas-eco
  # NICHT metro-san-eco (wird schon von Microservices-App genutzt)
```

### 5. Namespace sicherstellen

```bash
kubectl get namespace weblogic || kubectl create namespace weblogic
```

### 6. Domain Admin Secret planen

Das Playbook legt das automatisch an mit `admin_secret_name: weblogic-admin-credentials`, aber du solltest:

- [ ] Das Random-Passwort später ändern (im Secret oder in Vault)
- [ ] Optional: Secret vorher selbst mit sicherem Passwort anlegen
  
```bash
kubectl create secret generic weblogic-admin-credentials \
  --from-literal=username=admin \
  --from-literal=password='<secure-password>' \
  -n weblogic \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Was das Playbook für dich macht

Folgende Dinge werden **automatisch angelegt** (env_hosted.yml mit Defaults):

| Ressource | Action | Ort |
|-----------|--------|-----|
| Namespace `weblogic` | Anlegen? | `manage_namespace: false` (in env_hosted.yml) – **manuell nötig** |
| ImagePullSecret | Hier nicht! | Du musst `imagePullSecrets` in `group_vars/all.yml` manuell eintragen oder Secret vorher anlegen |
| Secret `weblogic-admin-credentials` | Anlegen/Update | `create_admin_secret: true` (automatisch) |
| PersistentVolumeClaim | Erstellen | Overlay-basiert mit `storageClassName: metro-nas` |
| Domain CR | Erstellen | via Kustomize + kubectl apply -k |

---

## Was NOCH FEHLT in der aktuellen Konfiguration

### A. ImagePullSecret in der Domain CR

Deine `k8s/domain.yaml` hat **keine** `imagePullSecrets`. Die muss rein:

```yaml
spec:
  # ...existing...
  imagePullSecrets:
    - name: wls-image-secret
```

### B. Ingress für WebLogic Web Console

Aktuell gibt es keinen Ingress. Das ist optional, aber wenn du die Admin Console brauchst:

```bash
# Optional später: Ingress anlegen
kubectl create ingress wls-admin \
  --class=<deine-ingress-class> \
  --rule="wls.yourdomain.com/*=wls-admin:7001@weblogic" \
  -n weblogic
```

### C. NetworkPolicy

Falls euer Cluster restriktiv ist (NetworkPolicy default-deny):

```bash
# Prüfen ob NetworkPolicy aktiv:
kubectl get networkpolicies -n weblogic

# Falls ja: Du brauchst eine Rule, die Ingress/egress auf DB erlaubt
# Das müsste auf Basis eurer Plattform-Policies gemacht werden
```

---

## Was der Plattform-Team geklärt haben sollte

Falls du auf Support-Bedarf sprichst:

- [ ] Ist der WebLogic Operator **cluster-weit** installiert?
  - Falls **Nein**: Darf ich ihn selbst installieren?
- [ ] Gibt es **Netzwerk-Restriktionen** (NetworkPolicy, Egress-Limits)?
- [ ] Kann ich **PVC mit StorageClass erstellen** im Namespace `weblogic`?
- [ ] Gibt es **Image-Registry-Policies** (z.B. nur bestimmte Registries erlaubt)?
- [ ] Kann ich **Ingress** definieren, falls nötig?

---

## Konkrete Handlungsschritte für JETZT

### Schritt 1: Namespace prüfen

```bash
kubectl get namespace weblogic
kubectl get namespace weblogic -o yaml
```

### Schritt 2: Operator-Status prüfen

```bash
# CRDs da?
kubectl api-resources | grep -i weblogic

# Operator Pod da?
kubectl get pods --all-namespaces | grep -i weblogic-operator
```

### Schritt 3: ImagePullSecret vorbereiten

```bash
# Nur wenn nicht schon vorhanden:
kubectl create secret docker-registry wls-image-secret \
  --docker-server=<dein-harbor> \
  --docker-username=<user> \
  --docker-password=<pw> \
  -n weblogic
```

### Schritt 4: Konfiguration anpassen

Editiere `/home/flow/dev_mk/ansible_mk/group_vars/env_hosted.yml` und die Overlays:

```bash
cd /home/flow/dev_mk/ansible_mk

# 1. Environment für hosted setzen
cat group_vars/env_hosted.yml

# 2. StorageClass auswählen
cat k8s/overlays/hosted/patch-pvc-storageclass.yaml

# 3. Domain-Bild setzen
cat group_vars/all.yml | grep weblogic_image
```

### Schritt 5: Dry-Run des Playbooks

```bash
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml \
  --check
```

Falls das durchläuft (auch im `--check` Mode), dann:

### Schritt 6: Live-Deployment

```bash
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml
```

---

## Meine konkrete nächste Hilfe

Gib mir dann:

1. **Operator-Status**: Output von `kubectl api-resources | grep weblogic`
2. **Deine Harbor-Details**: `<harbor-host>`, evtl. Namespaces
3. **Welche StorageClass**: `metro-nas` oder `metro-nas-eco`?
4. **WebLogic Image-Name**: Wo ist das Image in Harbor?

Dann mache ich dir:

- [ ] Die konkrete `env_hosted.yml` mit deinen Werten
- [ ] Das Domain-Manifest mit ImagePullSecret
- [ ] Optional: ein Init-Skript, das Harbor-Secret + Namespace prüft

---

## Fazit

**Was du VOR dem Playbook MINDESTENS tun musst:**

1. ✅ Namespace `weblogic` (schon existiert)
2. ❓ WebLogic **Operator** im Cluster (klären!)
3. ❓ **ImagePullSecret** (klären: selbst oder vom Team?)
4. ✅ **StorageClass** auswählen (metro-nas oder eco)
5. ✅ **WebLogic Image** in Harbor (prüfen ob vorhanden)

**Dann startet das Playbook:**

- Erstellt Secrets (Admin)
- Erstellt PVC
- Deployed Domain CR
- Wartet auf Pod

**Was danach noch nötig:**

- Ingress + Zertifikat (optional)
- Konfiguration anpassen
- Logs prüfen

---

## Wenn du willst, mache ich jetzt konkret:

- [ ] `env_hosted.yml` mit deinen konkreten Werten ausfüllen
- [ ] `k8s/domain.yaml` um ImagePullSecret erweitern
- [ ] Ein **Pre-flight-Check-Skript** für dich schreiben (prüft: Namespace, CRDs, StorageClass, Secret)
- [ ] Eine **Troubleshooting-Anleitung** speziell für deine Situation

