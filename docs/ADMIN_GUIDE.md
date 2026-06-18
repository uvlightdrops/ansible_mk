# 🎯 Admin-Leitfaden: WebLogic on Kubernetes

**Für: Kubernetes-Administratoren ohne WebLogic-Spezialwissen**

Dieses Handbuch erklärt alle wichtigen Admin-Aufgaben in einfacher Sprache. Keine vorherige Kubernetes-Erfahrung notwendig.

---

## 📚 Inhaltsverzeichnis

1. [**Basics verstehen**](#basics-verstehen)
2. [**Tägliche Aufgaben**](#tägliche-aufgaben)
3. [**Probleme erkennen & beheben**](#probleme-erkennen--beheben)
4. [**Sicherheit & Zugriff**](#sicherheit--zugriff)
5. [**Backup & Wiederherstellung**](#backup--wiederherstellung)
6. [**Monitoring & Logs**](#monitoring--logs)
7. [**Performance & Ressourcen**](#performance--ressourcen)
8. [**Checklisten**](#checklisten)

---

## Basics verstehen

### Was läuft hier eigentlich?

Du betreibst **WebLogic** (ein Java-Anwendungsserver) auf **Kubernetes** (einer Container-Plattform).

```
┌─────────────────────────────────────────────────┐
│           Kubernetes-Cluster                    │
│  ┌──────────────────────────────────────────┐   │
│  │     Namespace: weblogic                  │   │
│  │  ┌──────────┐  ┌──────────┐              │   │
│  │  │ admin-   │  │ managed- │ (mehrere)   │   │
│  │  │ server-0 │  │ server-1 │              │   │
│  │  │ (läuft)  │  │ (läuft)  │              │   │
│  │  └──────────┘  └──────────┘              │   │
│  │       ↓              ↓                   │   │
│  │  ┌──────────────────────────┐            │   │
│  │  │ Speicher (PVC)           │            │   │
│  │  │ /u01/domains/...         │            │   │
│  │  └──────────────────────────┘            │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Wichtige Begriffe (für dieses Projekt)

| Begriff | Bedeutung | Beispiel |
|---------|-----------|---------|
| **Pod** | Ein laufender Container (hier: WebLogic-Prozess) | `wls-admin-0` |
| **Namespace** | Isolierter Bereich im Cluster | `weblogic` |
| **PVC** | Persistenter Speicher (bleibt erhalten) | Deine Domain-Dateien |
| **Image** | Fertige Container-Vorlage | `oracle/weblogic:14.1.1.0` |
| **StatefulSet** | Verwaltung von Pods mit Identität | `wls-managed-1` |
| **Service** | Netzwerk-Zugang zu Pods | Für Admin Console |
| **ConfigMap** | Konfigurationsdateien | SSH-Schlüssel, Scripts |

---

## Tägliche Aufgaben

### 1️⃣ Status prüfen: "Läuft alles?"

**Das machst du mehrmals täglich:**

```bash
# Überblick über alle Pods
kubectl get pods -n weblogic

# Schöner Überblick mit mehr Info
kubectl get pods -n weblogic -o wide
```

**Was du sehen solltest:**
```
NAME              READY   STATUS    RESTARTS   AGE
wls-admin-0       1/1     Running   0          2d
wls-managed-1-0   1/1     Running   0          2d
wls-managed-2-0   1/1     Running   0          2d
```

**STATUS erklären:**
- ✅ `Running` = Alles OK, Pod läuft
- ⏳ `Pending` = Wartet auf Ressourcen (nicht ok, siehe Troubleshooting)
- 🔄 `CrashLoopBackOff` = Abstürze (nicht ok, Logs prüfen)
- ⚠️ `ImagePullBackOff` = Container-Image wird nicht gefunden (nicht ok)

---

### 2️⃣ Logs ansehen: "Was macht WebLogic gerade?"

```bash
# Logs vom Admin-Server (letzte 50 Zeilen)
kubectl logs -n weblogic wls-admin-0 --tail=50

# Logs live überwachen (wie "tail -f")
kubectl logs -n weblogic wls-admin-0 -f

# Logs vom letzten Neustart (falls Pod gecrasht ist)
kubectl logs -n weblogic wls-admin-0 --previous
```

**Wichtige Fehler erkennen:**
```
[WARN] - Ignorieren, nicht kritisch
[ERROR] - Fehler aufgetreten, aber WebLogic läuft noch
[CRITICAL] - Pod wird gleich abstürzen → schnell handeln!
```

---

### 3️⃣ Pod neu starten: "Ich will WebLogic neustarten"

**Option A: Einen Pod neustarten**
```bash
# Admin-Server neustarten
kubectl delete pod wls-admin-0 -n weblogic
# Kubernetes startet ihn sofort neu
```

**Option B: Alle Pods neu starten (kompletter Cluster-Neustart)**
```bash
# Alle Deployments und StatefulSets neu starten
kubectl rollout restart deployment -n weblogic
kubectl rollout restart statefulset -n weblogic

# Fortschritt beobachten
kubectl rollout status deployment -n weblogic
```

⚠️ **Warnung:** Während eines Neustarts sind die WebLogic-Services kurzzeitig nicht erreichbar!

---

### 4️⃣ Konfiguration ansehen & ändern

**Welche Einstellungen aktuell gelten?**
```bash
# Zentrale Konfiguration anschauen
cat group_vars/all.yml
```

**Wichtige Parameter:**
```yaml
namespace: wl                    # Kubernetes-Namespace
domain_uid: sample-domain1       # WebLogic Domain-Name
weblogic_admin_password: ChangeMe123!  # Admin-Passwort ⚠️
weblogic_image: harbor.../wls:14.1  # Container-Image
pv_storage: 5Gi                 # Speichergröße
```

**Konfiguration ändern:**
```bash
# Datei editieren
nano group_vars/all.yml

# WICHTIG: Nicht alle Parameter können zur Laufzeit geändert werden!
# Manche erfordern einen Neustart oder Neudeploy
```

---

### 5️⃣ Speicher prüfen: "Ist noch Platz?"

```bash
# Speicher-Status
kubectl get pvc -n weblogic

# Detaillierte Infos
kubectl describe pvc pvc-weblogic-home -n weblogic

# Wie viel ist wirklich belegt? (manuell prüfen)
kubectl exec -it wls-admin-0 -n weblogic -- df -h /u01
```

**Was soll ich sehen?**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       5G    2.1G 2.9G 42%  /u01
                ↑     ↑    ↑         ↑
            Gesamt  Belegt Frei    Prozent
```

⚠️ **Kritisch:** >90% Auslastung = Speicher bald voll!

**Speicher vergrößern:**
```bash
# NICHT im Cluster machen! Das braucht Infrastructure-Änderungen
# Kontaktiere dein Plattform-Team
```

---

### 6️⃣ Netzwerk-Zugriff testen

```bash
# Admin Console erreichbar?
kubectl get svc -n weblogic

# Port zum Admin-Server?
kubectl port-forward svc/wls-admin 7001:7001 -n weblogic
# Dann browser: http://localhost:7001/console
```

---

## Probleme erkennen & beheben

### 🔴 Problem: Pod ist nicht gestartet (ImagePullBackOff)

**Was ist passiert?**
Kubernetes kann das Container-Image nicht finden / pullen.

**Diagnose:**
```bash
# Pod-Status anschauen
kubectl describe pod wls-admin-0 -n weblogic

# Suche nach "ImagePullBackOff" oder "Failed to pull image"
```

**Behebung:**
```bash
# 1. Image korrekt?
echo $HARBOR_IMAGE  # Prüfe die Image-URL

# 2. Harbor-Secret vorhanden?
kubectl get secret -n weblogic | grep -i image
# Sollte etwas zeigen wie "wls-image-secret"

# 3. Secret ist kaputt? Neu erstellen:
kubectl delete secret wls-image-secret -n weblogic
# Dann von Anfang deployen oder Secret neu erzeugen

# 4. Pod restarten
kubectl delete pod wls-admin-0 -n weblogic
```

---

### 🔴 Problem: Pod bleibt im Pending-Status

**Was ist passiert?**
Kubernetes kann keinen Platz für den Pod finden.

**Diagnose:**
```bash
# Details anschauen
kubectl describe pod wls-managed-1-0 -n weblogic

# Suche nach "Pending" Gründen:
# - Unzureichende Ressourcen
# - StorageClass nicht vorhanden
# - Node-Affinity Regel nicht erfüllt
```

**Behebung:**

```bash
# 1. Verfügbare Ressourcen prüfen
kubectl top nodes

# 2. StorageClass anschauen
kubectl get storageclass
# Sollte "metro-nas" oder "manual" anzeigen

# 3. Persistente Volumes prüfen
kubectl get pv -n weblogic
kubectl get pvc -n weblogic

# 4. Node-Status anschauen
kubectl get nodes
# Sollte alle "Ready" sein
```

---

### 🔴 Problem: Pod läuft, aber stürzt immer ab (CrashLoopBackOff)

**Was ist passiert?**
Der WebLogic-Prozess startet, aber bleibt nicht stabil.

**Diagnose:**
```bash
# Logs vom letzten Crash ansehen
kubectl logs wls-admin-0 -n weblogic --previous

# Restart-Historie anschauen
kubectl get pod wls-admin-0 -n weblogic -o yaml | grep -i restart
```

**Häufige Gründe & Behebung:**

| Grund | Was tun |
|-------|---------|
| Zu wenig Speicher | Speicher in der Domain vergrößern oder Cleanup machen |
| Falsches WebLogic-Image | Image-URL in `group_vars/all.yml` prüfen |
| Domain-Datei kaputt | PVC mounten und Datei prüfen/reparieren |
| Java OutOfMemory | Heap-Size anpassen (in der Deployment-YAML) |

**Schnelle Reparatur:**
```bash
# WebLogic-Prozess debuggen
kubectl exec -it wls-admin-0 -n weblogic -- /bin/bash

# Im Container:
ps aux | grep java        # Läuft Java?
tail -100 /u01/domains/logs/*     # Logs schauen
```

---

### 🔴 Problem: Speicher ist plötzlich belegt

**Was ist passiert?**
Irgendwas schreibt viel in den Speicher.

**Diagnose:**
```bash
# Live-Nutzung anschauen
kubectl exec wls-admin-0 -n weblogic -- df -h /u01

# Große Dateien finden
kubectl exec wls-admin-0 -n weblogic -- \
  find /u01 -type f -size +100M -exec ls -lh {} \;

# Logs wachsen zu schnell?
kubectl exec wls-admin-0 -n weblogic -- \
  du -sh /u01/domains/*/servers/*/logs/
```

**Behebung:**

```bash
# 1. Alte Logs löschen
kubectl exec wls-admin-0 -n weblogic -- \
  rm -f /u01/domains/*/servers/*/logs/*.log.*

# 2. Temp-Dateien räumen
kubectl exec wls-admin-0 -n weblogic -- \
  rm -rf /u01/domains/*/servers/*/tmp/*

# 3. Domain neustarten (damit Cache geleert wird)
kubectl delete pod wls-admin-0 -n weblogic
```

---

### 🟡 Problem: Pod ist instabil, viele Restarts

**Diagnose:**
```bash
# Wie oft restartet?
kubectl get pod wls-admin-0 -n weblogic
# RESTARTS-Spalte > 5 = zu oft

# Wann sind die Restarts passiert?
kubectl describe pod wls-admin-0 -n weblogic
# Suche "Last State" und "Reason"
```

**Mögliche Gründe:**
- Speicher wird regelmäßig belegt
- Netzwerk-Verbindung flattert
- Java-Prozess hat Memory Leak
- Deployment der Anwendungen hat Fehler

**Was tun:**
```bash
# 1. Monitoring einrichten (siehe Monitoring-Sektion)
# 2. Logs zeitlich einengen und analysieren
# 3. Bei Bedarf Pod-Limits erhöhen
```

---

## Sicherheit & Zugriff

### 1️⃣ Admin-Passwort (WebLogic-Console)

**Wo ist das Passwort definiert?**
```bash
cat group_vars/all.yml | grep weblogic_admin_password
```

**Passwort ändern:**

⚠️ **Wichtig:** Das Passwort ist aktuell in einer Datei gespeichert. Das ist nicht sicher!

```bash
# 1. In Datei ändern (schnell, aber nicht sicher)
nano group_vars/all.yml
# Ändere die Zeile:
# weblogic_admin_password: DeinNeuesPasswort123!

# 2. Neudeployment erforderlich für Änderung
ansible-playbook k8s_weblogic/deploy_weblogic.yml

# 3. Besser: Mit Ansible Vault speichern
# (Frag dein Plattform-Team, wie das bei euch läuft)
```

---

### 2️⃣ Zugriff auf Kubernetes-Cluster kontrollieren

**Wer darf was?**
```bash
# Alle Berechtigungen in Namespace prüfen
kubectl auth can-i list pods --namespace=weblogic --as=dein-username

# Detaillierte Berechtigungen anschauen
kubectl get rolebindings -n weblogic
kubectl describe rolebinding <name> -n weblogic
```

**Neue Personen hinzufügen:**
```bash
# Frag dein Cluster-Admin-Team
# Sie müssen eine RoleBinding erstellen
```

---

### 3️⃣ SSH-Zugang zu den Containern

**Wofür braucht man das?**
- Debugging
- Manuelle Einstellungen
- Logfiles direkt ansehen

**SSH-Schlüssel Setup (schon vorhanden):**
```bash
# Welche SSH-Keys sind installiert?
kubectl get configmap -n weblogic | grep -i ssh
kubectl get secret -n weblogic | grep -i ssh

# SSH-Key selbst hinzufügen (optional)
kubectl exec -it wls-admin-0 -n weblogic -- \
  bash -c 'echo "your-public-key" >> ~/.ssh/authorized_keys'
```

---

### 4️⃣ Netzwerk-Sicherheit

**Wer kann auf WebLogic zugreifen?**
```bash
# Netzwerk-Policies anschauen
kubectl get networkpolicy -n weblogic

# Standardmäßig: Nur aus dem Cluster, nicht von draußen
# Für Admin Console brauchst du einen Ingress oder Port-Forward
```

**Port-Forwarding für Remote-Zugriff (temporär):**
```bash
# Admin Console erreichbar
kubectl port-forward svc/wls-admin 7001:7001 -n weblogic
# Dann: http://localhost:7001/console
```

---

## Backup & Wiederherstellung

### 1️⃣ Backup Strategy verstehen

**Was wird gespeichert?**
- ✅ Domain-Konfiguration: `/u01/domains/...`
- ✅ Datenbank-Einstellungen
- ✅ SSL-Zertifikate
- ❌ Docker-Image: Wird nicht gebackupt (kann neu gebaut werden)
- ❌ Anwendungs-Container-Logs: Zu groß zum Backup

**Backup-Ziele:**
- Domain-Konfiguration (selten geändert)
- Stateful Data (Datenbank)
- SSL-Zertifikate
- PVC-Inhalt

---

### 2️⃣ Backup erstellen (Domain)

**Manuelles Backup:**
```bash
# 1. Backup-Verzeichnis erstellen (lokal auf Host)
mkdir -p ~/weblogic-backups/$(date +%Y-%m-%d)

# 2. Domain-Dateien kopieren
kubectl cp weblogic/wls-admin-0:/u01/domains ~/weblogic-backups/$(date +%Y-%m-%d)/ -n weblogic

# 3. Größe prüfen
du -sh ~/weblogic-backups/$(date +%Y-%m-%d)/

# 4. Optional: Auf backup-server kopieren
scp -r ~/weblogic-backups/$(date +%Y-%m-%d)/ backup-server:/mnt/backups/
```

**Automatisches Backup (mit Cron):**
```bash
# Cron-Job einrichten (auf deinem Host)
cat >> /etc/cron.d/weblogic-backup <<EOF
0 2 * * * root bash /home/flow/dev_mk/ansible_mk/scripts/backup_domain.sh
EOF

# Script erstellen: scripts/backup_domain.sh
```

---

### 3️⃣ Backup prüfen: "Ist das Backup gut?"

```bash
# Backup-Inhalt anschauen
ls -la ~/weblogic-backups/

# Alter prüfen
find ~/weblogic-backups -type f -mtime +7 -delete  # Älter als 7 Tage = weg

# Größe übers Zeit tracken
for dir in ~/weblogic-backups/*/; do
  echo "$(date -r "$dir" +%Y-%m-%d): $(du -sh "$dir" | cut -f1)"
done
```

---

### 4️⃣ Wiederherstellen aus Backup

⚠️ **Kritisch:** Nur wenn wirklich nötig!

**Szenario: Domain-Konfiguration ist kaputt**

```bash
# 1. Pod anhalten (optional)
kubectl scale statefulset wls-admin-0 --replicas=0 -n weblogic

# 2. Backup zurück kopieren
kubectl cp ~/weblogic-backups/2024-06-15/domains weblogic/wls-admin-0:/u01/ -n weblogic

# 3. Pod starten
kubectl scale statefulset wls-admin-0 --replicas=1 -n weblogic

# 4. Logs prüfen, ob es startet
kubectl logs -f wls-admin-0 -n weblogic
```

**Szenario: Komplett neuer Cluster (Restore)**

```bash
# 1. Ganzer WebLogic-Cluster neudeploy
ansible-playbook k8s_weblogic/deploy_weblogic.yml

# 2. Alte Domain-Daten zurück kopieren (nur Domain-Dateien!)
kubectl cp ~/weblogic-backups/2024-06-15/domains weblogic/wls-admin-0:/u01/ -n weblogic

# 3. Cluster neustarten
kubectl rollout restart statefulset -n weblogic
```

---

## Monitoring & Logs

### 1️⃣ Wichtige Metriken regelmäßig prüfen

**Ressourcen-Monitoring (CPU & RAM):**
```bash
# Aktuell
kubectl top pods -n weblogic
kubectl top nodes

# Historisch (braucht Prometheus/Grafana)
# → Frag dein Monitoring-Team
```

**Was ist normal?**
| Ressource | Normal | Warnung | Kritisch |
|-----------|--------|---------|----------|
| CPU | < 20% | 50-80% | > 90% |
| RAM | < 50% | 70-85% | > 95% |
| Disk | < 60% | 75-85% | > 90% |

---

### 2️⃣ Logs strukturiert lesen

**Tägliche Log-Prüfung:**
```bash
# Letzte Fehler
kubectl logs -n weblogic wls-admin-0 | grep -i error | tail -20

# Warnungen
kubectl logs -n weblogic wls-admin-0 | grep -i warning | tail -10

# Kritische Events
kubectl logs -n weblogic wls-admin-0 | grep -i critical
```

**Log-Archivierung:**
```bash
# Logs auf Host speichern
kubectl logs -n weblogic wls-admin-0 --timestamps=true > admin-$(date +%Y%m%d).log

# Alte Logs löschen (im Container)
kubectl exec -it wls-admin-0 -n weblogic -- \
  find /u01/domains/*/servers/*/logs -name "*.log.*" -mtime +30 -delete
```

---

### 3️⃣ Probleme VORHER erkennen (Predictive Monitoring)

**Diese Indikatoren beobachten:**

```bash
# 1. Speicher-Trend
watch -n 60 'kubectl exec wls-admin-0 -n weblogic -- df -h /u01'

# 2. Log-Growth
watch -n 300 'du -sh /u01/domains/*/servers/*/logs/'

# 3. Pod-Restarts
watch 'kubectl get pods -n weblogic'

# 4. CPU-Spitzen
watch -n 10 'kubectl top pod -n weblogic'
```

**Alerts einrichten (lokal):**
```bash
# Script: scripts/monitor_alerts.sh
#!/bin/bash

DISK_USAGE=$(kubectl exec wls-admin-0 -n weblogic -- df /u01 | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -gt 80 ]; then
  echo "⚠️ WARNUNG: Speicher zu $DISK_USAGE% belegt!"
  # Mail senden oder Slack notifizieren
fi
```

---

## Performance & Ressourcen

### 1️⃣ Ressourcen anschauen & verstehen

**Aktuelle Nutzung:**
```bash
kubectl describe pod wls-admin-0 -n weblogic | grep -A5 "Limits\|Requests"

# Output z.B.:
#    Requests:
#      cpu:     1000m
#      memory:  2Gi
#    Limits:
#      cpu:     2000m
#      memory:  4Gi
```

**Was bedeutet das?**
| Parameter | Bedeutung | Beispiel |
|-----------|-----------|---------|
| **Requests** | Mindestens braucht der Pod | 1 CPU, 2 GB RAM |
| **Limits** | Maximum darf der Pod nutzen | 2 CPU, 4 GB RAM |
| **m** | Millicore (0.001 CPU) | 1000m = 1 volle CPU |
| **Gi** | Gigabyte | 2Gi = 2 GB |

---

### 2️⃣ Performance-Probleme erkennen

**Pod läuft, aber langsam?**

```bash
# 1. CPU maxed out?
kubectl top pod wls-admin-0 -n weblogic
# CPU-Wert gleich wie Limit? → Zu low limit gesetzt

# 2. RAM fast belegt?
kubectl top pod wls-admin-0 -n weblogic
# RAM-Wert > 80% von Limit? → OOM-Kill kommt bald

# 3. Disk I/O Bottleneck?
kubectl exec wls-admin-0 -n weblogic -- iostat -x 1 5

# 4. Netzwerk Bottleneck?
kubectl exec wls-admin-0 -n weblogic -- iftop -n  # braucht iftop
# Alternativ: tcpdump -i eth0 -c 100
```

---

### 3️⃣ Ressourcen erhöhen

**CPU vergrößern:**
```bash
# In Deployment-YAML ändern (z.B. deploy-wls-admin.yaml)
# Requests und Limits hochfahren

kubectl set resources deployment wls-admin \
  --requests=cpu=2,memory=4Gi \
  --limits=cpu=4,memory=8Gi \
  -n weblogic

# Pod lädt neu und größere Ressourcen werden genutzt
```

**RAM vergrößern:**
```bash
# Heap-Size ändern (WebLogic-spezifisch)
# In der Domain-Config editieren
# Oder als Umgebungsvariable:

kubectl set env deployment wls-admin \
  -e USER_MEM_ARGS="-Xms4g -Xmx8g" \
  -n weblogic

# Pod neu starten
kubectl rollout restart deployment wls-admin -n weblogic
```

**Speicher (PVC) vergrößern:**
```bash
# PVC vergrößern (wenn Storage-Backend das unterstützt)
kubectl patch pvc pvc-weblogic-home -n weblogic -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'

# Oder YAML editieren:
kubectl edit pvc pvc-weblogic-home -n weblogic
# storage: 10Gi  ← hier ändern
```

---

### 4️⃣ Tuning-Tipps

| Problem | Lösung |
|---------|--------|
| Langsamer Startup | Java Heap initial größer (`-Xms`) |
| Häufige GC-Pausen | Heap-Size erhöhen |
| OOM-Fehler | RAM-Limit hochfahren |
| Disk-Bottleneck | PVC auf schneller Storage-Klasse |
| Netzwerk-Latenzen | Pods auf gleichen Nodes (Pod-Affinity) |

---

## Checklisten

### ✅ Tägliche Wartungs-Checkliste (5 min)

```bash
# 1. Pods laufen?
kubectl get pods -n weblogic

# 2. Keine CrashLoopBackOff oder Pending?
kubectl get pods -n weblogic | grep -v Running

# 3. Speicher OK?
kubectl exec wls-admin-0 -n weblogic -- df -h /u01 | grep -E "100%|9[5-9]%"

# 4. Keine vielen Restarts?
kubectl get pods -n weblogic -o json | jq '.items[].status.containerStatuses[0].restartCount' | sort -rn | head -1

# 5. Logs schauen
kubectl logs wls-admin-0 -n weblogic --tail=20 | grep -i error
```

**Automatisieren:**
```bash
#!/bin/bash
# save as: scripts/daily_check.sh

echo "=== WebLogic Daily Check ==="
echo "1. Pod Status:"
kubectl get pods -n weblogic --no-headers | awk '{print $3}' | sort | uniq -c

echo "2. Disk Usage:"
kubectl exec wls-admin-0 -n weblogic -- df -h /u01 | tail -1

echo "3. Pod Restarts (Top 3):"
kubectl get pods -n weblogic -o json | jq '.items[] | {name: .metadata.name, restarts: .status.containerStatuses[0].restartCount}' | sort -k3 -rn | head -3

echo "4. Recent Errors:"
kubectl logs -n weblogic wls-admin-0 --tail=50 | grep -i error | tail -3 || echo "No errors"

echo "✅ Check complete"
```

---

### ✅ Wöchentliche Wartungs-Checkliste

- [ ] Backup erstellt? `kubectl cp weblogic/wls-admin-0:/u01/domains ~/backups/`
- [ ] Alte Logs gelöscht? `find /var/log/weblogic -mtime +7 -delete`
- [ ] Disk-Trend OK? (nicht zu schnell wachsend)
- [ ] Keine wiederholten Fehler in den Logs?
- [ ] Restarts pro Pod: max. 1 pro Woche OK
- [ ] Performance akzeptabel? `kubectl top pods -n weblogic`
- [ ] Security-Updates für OS/Java verfügbar?

---

### ✅ Monatliche Wartungs-Checkliste

- [ ] Alle Backups noch vorhanden & testweis restore probieren?
- [ ] Speicher-Trend: Grenzwert überschritten?
- [ ] Performance-Report erstellen (Average CPU, RAM, Disk)
- [ ] Geplanter Neustart geplant? (z.B. für Kernel-Updates)
- [ ] Zertifikate: Ablaufdatum prüfen
- [ ] Logs archivieren & verdichten
- [ ] Backup-Strategie Review

---

### ✅ Vor größeren Änderungen

- [ ] Backup erstellen
- [ ] Dry-Run machen (wenn möglich `--check` Flag)
- [ ] Wartungsfenster einplanen
- [ ] Team benachrichtigen
- [ ] Rollback-Plan erstellen
- [ ] Nach Änderung: Logs auf Fehler prüfen
- [ ] Funktionalität testen
- [ ] Dokumentation aktualisieren

---

## Häufig gestellte Fragen (FAQ)

### F: Wie starte ich WebLogic neu?
**A:** `kubectl delete pod wls-admin-0 -n weblogic`

---

### F: Wie sehe ich, wie viel CPU/RAM WebLogic braucht?
**A:** `kubectl top pod -n weblogic`

---

### F: Der Pod startet nicht. Was tun?
**A:** `kubectl describe pod <pod-name> -n weblogic` → Schau nach Events

---

### F: Speicher läuft voll. Was ist schnelle Lösung?
**A:** `kubectl exec wls-admin-0 -n weblogic -- rm -rf /u01/domains/*/servers/*/logs/*.log.*`

---

### F: Wie mache ich ein Backup?
**A:** `kubectl cp weblogic/wls-admin-0:/u01/domains ~/backup/`

---

### F: Wer darf was im Cluster machen?
**A:** `kubectl get rolebindings -n weblogic`

---

### F: Web Console von außen nicht erreichbar. Warum?
**A:** `kubectl port-forward svc/wls-admin 7001:7001 -n weblogic` oder Ingress konfigurieren

---

### F: Pod startet immer neu (CrashLoopBackOff). Warum?
**A:** `kubectl logs wls-admin-0 -n weblogic --previous` → Lies den letzten Fehler

---

### F: Muss ich manchmal Pods manuell starten?
**A:** Normalerweise nicht. Kubernetes macht das automatisch.

---

## Wichtige Dateien zum Kennen

| Datei | Zweck | Editieren? |
|-------|-------|-----------|
| `group_vars/all.yml` | Zentrale Konfiguration | ⚠️ Selten, braucht meist Neustart |
| `k8s/deploy-wls-admin.yaml` | Admin-Pod Definition | ⚠️ Nur mit Wissen |
| `k8s/domain.yaml` | Domain Custom Resource | ⚠️ Nur mit Wissen |
| `prepare_docker/` | Setup-Scripts | 🚫 Nicht anfassen |
| `scripts/` | Admin-Hilfs-Scripts | ✅ Gerne nutzen |

---

## Nützliche Commands (Quick Reference)

```bash
# STATUS CHECKEN
kubectl get pods -n weblogic                # Alle Pods Status
kubectl top pods -n weblogic                # CPU/RAM Nutzung
kubectl describe pod POD -n weblogic        # Detail-Info zu Pod

# LOGS LESEN
kubectl logs POD -n weblogic                # Letzten Logs
kubectl logs POD -n weblogic -f             # Live-Logs
kubectl logs POD -n weblogic --previous     # Letzer Crash-Logs

# RESTART
kubectl delete pod POD -n weblogic          # Pod neu starten
kubectl rollout restart deployment -n weblogic  # Alle Pods neu

# SPEICHER
kubectl get pvc -n weblogic                 # Speicher-Status
kubectl exec POD -n weblogic -- df -h /u01  # Speicher im Pod

# SSH
kubectl exec -it POD -n weblogic -- /bin/bash  # Shell öffnen

# KONFIGURATION
kubectl describe pvc/svc/deployment -n weblogic  # Details
kubectl edit deployment/statefulset -n weblogic  # Editieren

# BACKUP
kubectl cp weblogic/POD:/u01/domains ZIELDIR -n weblogic
```

---

## Support & Kontakte

**Wenn etwas nicht funktioniert:**

1. **Logs prüfen** → `kubectl logs -n weblogic wls-admin-0`
2. **Beschreibung lesen** → `kubectl describe pod -n weblogic wls-admin-0`
3. **Troubleshooting Sektion** oben konsultieren
4. **An Plattform-Team eskalieren** mit:
   - Fehlermeldung (vollständig!)
   - Output von `kubectl describe pod/svc/pvc -n weblogic`
   - Wann das Problem auftrat
   - Welche Änderungen vorher gemacht wurden

---

## Weitere Ressourcen

- **AGENTS.md** → Technische Architektur
- **QUICK_START.md** → Schnell starten (für Neulinge)
- **OPERATOR_SETUP.md** → WebLogic Operator installieren
- **Kubernetes Docs** → https://kubernetes.io/docs/

---

**Viel Erfolg beim Admin-Leben! 🚀**

Fragen? Team-Chat oder oben "Support & Kontakte".

---

**Letzte Aktualisierung:** Juni 2024
**Für:** Kubernetes-Administratoren  
**Gültig für:** WebLogic-on-Minikube Setup

