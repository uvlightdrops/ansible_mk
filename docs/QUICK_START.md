# QUICK START: WebLogic auf Hosted Kubernetes

Du hast auf dem Hosted Cluster:
- ✅ Namespace `weblogic`  
- ✅ Harbor-Registry mit Skopeo
- ✅ StorageClass: `metro-nas` oder `metro-nas-eco`
- ❓ WebLogic Operator?

---

## Minute 1: Operator-Status prüfen

```bash
# Kommando
kubectl api-resources | grep domain

# Falls NICHTS angezeigt wird → STOP und lese docs/OPERATOR_SETUP.md
# Falls angezeigt wird → OK, weiter mit Minute 2
```

---

## Minute 2-5: Harbor-Image vorbereiten

```bash
# Dein WebLogic Image zu Harbor pushen (mit Skopeo)
export HARBOR="harbor.example.com"
export USER="dein-username"

skopeo copy docker://oracle/weblogic:14.1.1.0-jdk11-ol8 \
  docker://$HARBOR/weblogic/wls:14.1.1.0

# oder: Harbor selbst geben lassen
bash scripts/setup_harbor_secret.sh $HARBOR $USER weblogic
```

---

## Minute 6: ImagePullSecret erstellen

```bash
bash scripts/setup_harbor_secret.sh harbor.example.com myuser weblogic
# Script fragt dann interaktiv nach Passwort
```

---

## Minute 7: Konfiguration anpassen

```bash
cd /home/flow/dev_mk/ansible_mk

# 1. Dein Harbor-Image eintragen
cat > group_vars/all.yml <<EOF
# ... alle bestehenden Werte ...
weblogic_image: "harbor.example.com/weblogic/wls:14.1.1.0"
# ... Rest bleibt gleich ...
EOF

# 2. Admin-Passwort ggf. anpassen (am besten mit Vault later)
# via CLI: -e weblogic_admin_password="dein-passwort"

# 3. StorageClass prüfen
# edit k8s/overlays/hosted/patch-pvc-storageclass.yaml
# → metro-nas oder metro-nas-eco (nicht metro-san-eco!)
```

---

## Minute 8: Pre-flight Check

```bash
bash scripts/preflight_check.sh weblogic

# Output sollte grün sein mit "Ready to deploy"
# Falls Warnungen: Lies sie durch, nicht kritisch für erste Deployment
```

---

## Minute 9: Dry-Run (optional, aber sicher)

```bash
# Schauen was das Playbook WÜRDE machen:
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml \
  --check

# Falls keine Fehler: GO!
```

---

## Minute 10: Deployment starten

```bash
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml
```

---

## Nach dem Deployment: Logs und Status prüfen

```bash
# Pods anschauen
kubectl get pods -n weblogic -o wide

# Admin Pod Details
kubectl logs -n weblogic -l weblogic.serverName=admin-server -f

# Falls ImagePullBackOff:
kubectl describe pod <pod-name> -n weblogic

# Falls Pending:
kubectl describe pvc -n weblogic

# Domain Status
kubectl get domains -n weblogic
kubectl describe domain sample-domain1 -n weblogic
```

---

## 🚨 Häufige Fehler

### 1. Pod bleibt in `ImagePullBackOff`

```bash
# Prüfe Secret
kubectl get secret wls-image-secret -n weblogic -o yaml

# Prüfe Image-URL
kubectl get secret wls-image-secret -n weblogic -o jsonpath='{.data.\.dockercfg}' | base64 -d | jq .

# Prüfe Image selbst in Harbor
skopeo inspect docker://harbor.example.com/weblogic/wls:14.1.1.0
```

**Behebung:**
```bash
# Secret neu erstellen
kubectl delete secret wls-image-secret -n weblogic
bash scripts/setup_harbor_secret.sh harbor.example.com user weblogic

# Pod restarten (domain wird automatisch neu deployed)
kubectl delete pod -n weblogic -l weblogic.serverName=admin-server
```

---

### 2. Pod bleibt `Pending`

```bash
# Prüfe PVC
kubectl describe pvc pvc-weblogic-home -n weblogic

# Falls StorageClass falsch:
kubectl get storageclass
# und editiere k8s/overlays/hosted/patch-pvc-storageclass.yaml
```

**Behebung:** StorageClass prüfen, Playbook erneut starten

---

### 3. Domain CR wird nicht erkannt

```bash
# Prüfe Operator
kubectl get pods -n weblogic-operator
kubectl logs -n weblogic-operator -l app=weblogic-operator

# Operator fehlt? → Lese docs/OPERATOR_SETUP.md
```

---

### 4. Affinity/Taint/Label Fehler

```bash
# Pod kann keinen Node finden
kubectl describe pod <pod-name> -n weblogic

# Falls Node-Selector fehlt oder zu restriktiv:
# → Prüfe ARCHITECTURE.md oder frage Plattform-Team
```

---

## 📋 Checkliste für Dich

VOR Deployment:
- [ ] `kubectl api-resources | grep domain` zeigt etwas an
- [ ] Harbor Secret existiert: `kubectl get secret wls-image-secret -n weblogic`
- [ ] WebLogic Image in Harbor: `skopeo inspect docker://harbor/.../wls:TAG`
- [ ] `group_vars/all.yml` mit korrektem Image aktualisiert
- [ ] `k8s/overlays/hosted/patch-pvc-storageclass.yaml` mit `metro-nas` oder `metro-nas-eco`
- [ ] `scripts/preflight_check.sh weblogic` = grün

Deployment:
- [ ] `ansible-playbook ... -e @group_vars/env_hosted.yml` läuft
- [ ] Pod-Status wird angezeigt
- [ ] `logs` zeigen keine kritischen Fehler

Nach Deployment:
- [ ] Admin Server Pod ist `Running` und `Ready`
- [ ] Domain CR hat Status `Creating` oder `Ready`
- [ ] PVC ist `Bound`

---

## 🎯 Nächste Schritte

1. **Dev fertig?** → Ingress + Route einrichten für Web Console
2. **Produktionsreif?** → Vault für Secrets, Monitoring einrichten
3. **Mehrere Apps?** → Staging/Prod Overlays hinzufügen

---

## 💡 Tipps

- Alle Commands mit `-n weblogic` laufen lokal, nicht im ganzen Cluster
- `watch kubectl get pods -n weblogic` für Live-Überwachung
- Logs mit `-f` (follow) für Live-Scrolling
- Bei Fragen: `kubectl describe pod/pvc/domain <name> -n weblogic`

---

## 📞 Support-Punkte für Plattform-Team

Falls Du feststeckst, frag nach:

1. **WebLogic Operator**: "Ist der Operator installiert? Wie prüfe ich das?"
2. **ImagePullSecret**: "Darf ich Docker-Registry-Secrets selbst anlegen?"
3. **PVC / StorageClass**: "Kann ich PVCs mit StorageClass erstellen?"
4. **Namespace-Zugriff**: "Welche API-Gruppen/Verben darf ich in meinem Namespace?"
5. **Domain CRs**: "Kann ich Domain CustomResources definieren?"

---

Viel Erfolg! 🚀

