# 📋 Admin Quick Reference: Checklisten & Commands

Diese Datei enthält Copy-Paste-ready Commands für schnelle Admin-Tasks.

---

## 🟢 GRÜN: Tägliche Prüfung (Status OK?)

```bash
# ==== ALLE PODS LAUFEN? ====
kubectl get pods -n weblogic -o wide
# Sollte: NAME | READY | STATUS | RESTARTS | AGE
# Alle sollten "Running" sein


# ==== SPEICHER OK? ====
kubectl exec wls-admin-0 -n weblogic -- df -h /u01 | tail -2
# Output z.B.: Filesystem | Size | Used | Avail | Use% | Mounted
# ⚠️  Wenn Use% > 85% → Aufräumen erforderlich!


# ==== CPU/RAM NORMAL? ====
kubectl top pods -n weblogic
# Wenn eine Spalte über 80% → watchten!


# ==== KEINE CRASHES? ====
kubectl get pods -n weblogic -o json | jq '.items[].status.containerStatuses[0] | select(.restartCount > 0) | {name: .containerID, restarts: .restartCount}'
# Wenn RESTARTS > 3 pro Tag → Logs anschauen!


# ==== SCHNELLE FEHLERPRÜFUNG ====
kubectl logs -n weblogic wls-admin-0 | grep -i "error\|critical" | tail -5
# Keine Output → gut!
# Output mit ERROR/CRITICAL → Lesen & handeln!
```

---

## 🔴 PROBLEM: Pod läuft nicht

### Diagnose
```bash
# 1. Was ist der Status?
kubectl get pod wls-admin-0 -n weblogic

# 2. Detaillierte Fehlermeldung
kubectl describe pod wls-admin-0 -n weblogic
# Suche nach: "Reason:" und "Message:"

# 3. Logs von letztem Versuch
kubectl logs wls-admin-0 -n weblogic --previous
```

### Häufige Fehler & Lösungen

#### ❌ ImagePullBackOff
```bash
# Fehler: Container-Image wird nicht gefunden

# 1. Image URL checken
kubectl get deployment wls-admin -n weblogic -o yaml | grep image:

# 2. Image-Secret checken
kubectl get secret wls-image-secret -n weblogic -o yaml

# 3. Kann das Image gepullt werden?
kubectl describe pod wls-admin-0 -n weblogic | grep -A5 "Events:"

# BEHEBUNG:
# Neuen Image-Secret erstellen (mit Plattform-Team)
# ODER
# Lokales Image verwenden
```

#### ❌ Pending (Wartet auf Platz)
```bash
# Fehler: Pod kann nicht gestartet werden

# 1. Events ansehen
kubectl describe pod wls-admin-0 -n weblogic | grep -A10 "Events:"

# 2. Node-Ressourcen prüfen
kubectl top nodes

# 3. PVC existiert?
kubectl get pvc -n weblogic

# BEHEBUNG:
# A) Storage Problem:
kubectl describe pvc pvc-weblogic-home -n weblogic
# Falls "Pending": StorageClass Problem (Plattform-Team)

# B) Node hat kein Platz:
kubectl top nodes
# Wenn >90% → Pod-Limits reduzieren oder Nodes hinzufügen
```

#### ❌ CrashLoopBackOff (Abstürze)
```bash
# Fehler: Pod startet, stürzt ab, startet wieder...

# 1. Letzte Logs vor Crash
kubectl logs wls-admin-0 -n weblogic --previous | tail -50

# 2. Event-Log
kubectl describe pod wls-admin-0 -n weblogic | grep -A20 "Events:"

# 3. Im Container nachschauen
kubectl exec -it wls-admin-0 -n weblogic -- /bin/bash
# Im Container:
tail -100 /u01/domains/*/servers/*/logs/*.log
ps aux | grep java

# BEHEBUNG:
# Häufig: Heap zu klein
# Lösung: Pod-Memory Limits erhöhen (siehe PERFORMANCE Sektion)
```

#### ❌ ImagePullBackOff / Private Registry
```bash
# Problem: Harbor Secret ist kaputt oder falsch

# BEHEBUNG (Schritt für Schritt):
# 1. Secret löschen
kubectl delete secret wls-image-secret -n weblogic

# 2. Neu erstellen (interaktiv)
bash scripts/setup_harbor_secret.sh harbor.example.com username

# 3. Pod neu starten (damit neues Secret verwendet wird)
kubectl delete pod wls-admin-0 -n weblogic

# 4. Prüfen
kubectl get pod wls-admin-0 -n weblogic
```

---

## 🟡 PROBLEM: Speicher wird eng

```bash
# ==== DIAGNOSE ====
# Wieviel ist belegt?
kubectl exec wls-admin-0 -n weblogic -- df -h /u01

# Was ist groß?
kubectl exec wls-admin-0 -n weblogic -- du -sh /u01/* | sort -h

# Welche Dateien sind am größten?
kubectl exec wls-admin-0 -n weblogic -- find /u01 -type f -size +100M -exec ls -lh {} \;


# ==== SCHNELLE LÖSUNGEN (BACKUP ZUERST!) ====

# 1. Alte Logs löschen (Speicher-Killer #1)
kubectl exec wls-admin-0 -n weblogic -- \
  find /u01/domains/*/servers/*/logs -name "*.log.*" -mtime +7 -delete
# Speichert i.d.R. 500MB - 5GB!

# 2. Temp-Cache räumen
kubectl exec wls-admin-0 -n weblogic -- \
  rm -rf /u01/domains/*/servers/*/tmp/*

# 3. Domain-Temp-Dateien
kubectl exec wls-admin-0 -n weblogic -- \
  rm -rf /u01/domains/*/servers/*/_WL_internal/*

# 4. Komplett aufräumen (ACHTUNG: Kann Breaking!)
# Nur wenn Punkte 1-3 nicht ausreichen!
kubectl delete pod wls-admin-0 -n weblogic
# Pod startet neu mit sauberem Temp


# ==== NACH CLEANUP PRÜFEN ====
kubectl exec wls-admin-0 -n weblogic -- df -h /u01
# Sollte wieder sinken!
```

---

## 🟠 PROBLEM: Pod braucht länger zu starten

```bash
# ==== DIAGNOSE ====
# Logs vom Startup anschauen
kubectl logs wls-admin-0 -n weblogic -f

# Wie lange braucht es?
kubectl describe pod wls-admin-0 -n weblogic | grep "Started:"

# Heap-Größe prüfen (siehe Logs)
kubectl logs wls-admin-0 -n weblogic | grep "Xms\|Xmx"


# ==== OPTIMIERUNG ====

# 1. Heap größer (schnellerer Startup)
kubectl set env deployment wls-admin \
  -e USER_MEM_ARGS="-Xms4g -Xmx8g" \
  -n weblogic

# 2. Pod neu starten
kubectl rollout restart deployment wls-admin -n weblogic

# 3. Startup beobachten
kubectl logs wls-admin-0 -n weblogic -f
```

---

## 🔵 RESTART-SZENARIOS

### Einzelnen Pod neu starten
```bash
# Admin Server
kubectl delete pod wls-admin-0 -n weblogic

# Managed Server 1
kubectl delete pod wls-managed-1-0 -n weblogic
```

### ALLE Pods neu starten (Cluster-Neustart)
```bash
# Variante 1: Graceful Restart (gibt App Zeit zum Shutdown)
kubectl rollout restart deployment -n weblogic
kubectl rollout restart statefulset -n weblogic

# Warten bis alle neu starten
kubectl rollout status deployment -n weblogic
kubectl rollout status statefulset -n weblogic

# Variante 2: Alle auf einmal löschen (hart!)
kubectl delete pods -n weblogic --all

# Fortschritt prüfen
watch kubectl get pods -n weblogic
```

---

## 💾 BACKUP & RESTORE

### Backup erstellen
```bash
# ==== 1. Vorbereitung ====
mkdir -p ~/weblogic-backups/$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR=~/weblogic-backups/$(date +%Y-%m-%d_%H-%M-%S)

# ==== 2. Domain kopieren ====
kubectl cp weblogic/wls-admin-0:/u01/domains $BACKUP_DIR/ -n weblogic

# ==== 3. Backup-Größe prüfen ====
du -sh $BACKUP_DIR/

# ==== 4. Optional: Auf anderen Server kopieren ====
scp -r $BACKUP_DIR backup-host:/mnt/backups/

# ==== 5. Backup auflisten ====
ls -la ~/weblogic-backups/
```

### Aus Backup wiederherstellen
```bash
# ==== VORSICHT: Nur im Notfall! ====

# ==== 1. Alte Domain sichern (mehrfach backup) ====
BACKUP_DIR=~/weblogic-backups/$(date +%Y-%m-%d_%H-%M-%S-restore-backup)
mkdir -p $BACKUP_DIR
kubectl cp weblogic/wls-admin-0:/u01/domains $BACKUP_DIR/ -n weblogic

# ==== 2. Pod anhalten (optional, aber empfohlen) ====
kubectl scale statefulset wls-admin --replicas=0 -n weblogic
sleep 10

# ==== 3. Alte Domain löschen ====
kubectl exec wls-admin-0 -n weblogic -- rm -rf /u01/domains

# ==== 4. Backup zurück kopieren ====
kubectl cp QUELLE_BACKUP/domains weblogic/wls-admin-0:/u01/domains -n weblogic

# ==== 5. Pod wieder starten ====
kubectl scale statefulset wls-admin --replicas=1 -n weblogic

# ==== 6. Startup beobachten ====
kubectl logs -f wls-admin-0 -n weblogic

# ==== 7. Alles OK? ====
kubectl get pods -n weblogic
# Sollte Running sein
```

---

## 🔐 SICHERHEIT & ZUGRIFF

### Admin-Passwort ändern
```bash
# ==== ACHTUNG: Erfordert Neudeployment! ====

# 1. Aktuelles Passwort anschauen
grep weblogic_admin_password group_vars/all.yml

# 2. Neues Passwort setzen
nano group_vars/all.yml
# Ändere: weblogic_admin_password: DeinNeuesPasswort123

# 3. Domain neu deployen
ansible-playbook k8s_weblogic/deploy_weblogic.yml

# 4. Admin Server wird neu gestartet
kubectl logs -f wls-admin-0 -n weblogic
```

### SSH-Key hinzufügen (für Remote-Admin)
```bash
# Auf Host:
PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)

# Im Pod installieren
kubectl exec -it wls-admin-0 -n weblogic -- bash <<EOF
echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
EOF

# Danach SSH-Login testen
ssh -i ~/.ssh/id_rsa docker@10.0.0.5  # Pod-IP nutzen
```

### Wer darf was?
```bash
# Alle Role Bindings anschauen
kubectl get rolebindings -n weblogic

# Details
kubectl describe rolebinding <name> -n weblogic

# Kann ich das tun?
kubectl auth can-i list pods -n weblogic --as=username

# Was darf ich alles?
kubectl api-resources --verbs=create --namespaced=true
```

---

## 📊 MONITORING & PERFORMANCE

### Live-Monitoring
```bash
# ==== REAL-TIME ANSCHAUEN ====

# CPU & RAM Live
watch -n 2 'kubectl top pods -n weblogic'

# Pod-Status Live
watch -n 5 'kubectl get pods -n weblogic'

# Speicher Live
watch -n 10 'kubectl exec wls-admin-0 -n weblogic -- df -h /u01'

# Log Live
kubectl logs -f wls-admin-0 -n weblogic
```

### Performance-Report
```bash
# ==== SNAPSHOT ERSTELLEN ====
echo "=== WebLogic Performance Report ===" > perf-report.txt
echo "Date: $(date)" >> perf-report.txt
echo "" >> perf-report.txt

echo "=== CPU & RAM ===" >> perf-report.txt
kubectl top pods -n weblogic >> perf-report.txt

echo "" >> perf-report.txt
echo "=== Node Resources ===" >> perf-report.txt
kubectl top nodes >> perf-report.txt

echo "" >> perf-report.txt
echo "=== Storage ===" >> perf-report.txt
kubectl exec wls-admin-0 -n weblogic -- df -h /u01 >> perf-report.txt

echo "" >> perf-report.txt
echo "=== Pod Restarts (7 Tage) ===" >> perf-report.txt
kubectl get pods -n weblogic -o json | jq '.items[] | {name: .metadata.name, restarts: .status.containerStatuses[0].restartCount}' >> perf-report.txt

# Report anschauen
cat perf-report.txt
```

### Ressourcen-Limits anpassen
```bash
# ==== CPU ERHÖHEN ====
kubectl set resources deployment wls-admin \
  --requests=cpu=2 \
  --limits=cpu=4 \
  -n weblogic

# ==== RAM ERHÖHEN ====
kubectl set resources deployment wls-admin \
  --requests=memory=4Gi \
  --limits=memory=8Gi \
  -n weblogic

# ==== PRÜFEN ====
kubectl describe deployment wls-admin -n weblogic | grep -A5 "Limits\|Requests"

# ==== JAVA HEAP ERHÖHEN (WebLogic-spezifisch) ====
kubectl set env deployment wls-admin \
  -e USER_MEM_ARGS="-Xms4g -Xmx8g" \
  -n weblogic
kubectl rollout restart deployment wls-admin -n weblogic
```

---

## 🐛 DEBUGGING & LOGS

### Logs durchsuchen
```bash
# ==== ALLE FEHLER DER LETZTEN 2 STUNDEN ====
SINCE=$(date -d '2 hours ago' --rfc-3339=seconds)
kubectl logs wls-admin-0 -n weblogic --since-time="$SINCE" | grep -i error

# ==== NUR KRITISCHE FEHLER ====
kubectl logs wls-admin-0 -n weblogic | grep -i critical

# ==== NACH WORT SUCHEN ====
kubectl logs wls-admin-0 -n weblogic | grep "OutOfMemory"

# ==== LETZTEN X ZEILEN ====
kubectl logs wls-admin-0 -n weblogic --tail=100

# ==== MIT TIMESTAMPS ====
kubectl logs wls-admin-0 -n weblogic -f --timestamps=true

# ==== VON MEHREREN PODS ====
kubectl logs -n weblogic -l app=wls-admin --all-containers=true
```

### Im Container arbeiten
```bash
# ==== SHELL ÖFFNEN ====
kubectl exec -it wls-admin-0 -n weblogic -- /bin/bash

# ==== DANACH IM CONTAINER: ====
pwd                              # Wo bin ich?
ls -la /u01/domains              # Domain-Dateien
cat /u01/domains/*/logs          # Logs anschauen
ps aux | grep java               # Läuft Java?
env | grep JAVA                  # Java-Settings
df -h                            # Disk
free -h                          # RAM
netstat -tlnp | grep 7001        # Ports

# ==== DANN SHELL VERLASSEN ====
exit
```

### Events anschauen
```bash
# ==== ALLE EVENTS IM NAMESPACE ====
kubectl get events -n weblogic --sort-by='.lastTimestamp'

# ==== EVENTS VOM POD ====
kubectl describe pod wls-admin-0 -n weblogic | grep -A30 "Events:"

# ==== LETZTEN 10 EVENTS ====
kubectl get events -n weblogic --sort-by='.lastTimestamp' | tail -10
```

---

## 🔄 DEPLOYMENT & UPDATES

### Neue Version deployen
```bash
# ==== 1. Backup ZUERST! ====
mkdir -p ~/backup-pre-deploy-$(date +%Y%m%d)
kubectl cp weblogic/wls-admin-0:/u01/domains ~/backup-pre-deploy-$(date +%Y%m%d)/ -n weblogic

# ==== 2. Dry-Run (was würde passieren?) ====
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml \
  --check

# ==== 3. Wenn OK → echtes Deployment ====
ansible-playbook k8s_weblogic/deploy_weblogic.yml \
  -e @group_vars/env_hosted.yml

# ==== 4. Status beobachten ====
watch kubectl get pods -n weblogic

# ==== 5. Nach Deployment prüfen ====
kubectl logs -f wls-admin-0 -n weblogic
# Auf Fehler prüfen
```

### Rollback (zurück zu alter Version)
```bash
# ==== 1. Backup-Verzeichnis prüfen ====
ls -la ~/backup-pre-deploy-*/

# ==== 2. Alte Version zurück kopieren ====
kubectl cp ~/backup-pre-deploy-DATUM/domains weblogic/wls-admin-0:/u01/domains -n weblogic

# ==== 3. Pod neu starten ====
kubectl delete pod wls-admin-0 -n weblogic

# ==== 4. Prüfen ====
kubectl logs -f wls-admin-0 -n weblogic
```

---

## 🧹 WARTUNG & CLEANUP

### Alte Logs archivieren
```bash
# ==== TÄGLICHES CLEANUP SCRIPT ====
#!/bin/bash
# Speichern: scripts/daily_cleanup.sh

echo "Archiviere alte Logs..."
kubectl exec wls-admin-0 -n weblogic -- \
  find /u01/domains/*/servers/*/logs -name "*.log.*" -mtime +7 -delete

echo "Lösche temporäre Dateien..."
kubectl exec wls-admin-0 -n weblogic -- \
  rm -rf /u01/domains/*/servers/*/tmp/*

echo "Speicher-Status:"
kubectl exec wls-admin-0 -n weblogic -- df -h /u01 | tail -2

echo "✅ Cleanup fertig"
```

### Cron-Job für automatisches Backup
```bash
# ==== IN CRONTAB EINTRAGEN ====
# crontab -e

# Täglich 2 Uhr: Backup
0 2 * * * bash /home/flow/dev_mk/ansible_mk/scripts/backup_domain.sh

# Täglich 3 Uhr: Cleanup
0 3 * * * bash /home/flow/dev_mk/ansible_mk/scripts/daily_cleanup.sh

# Sonntags: Full Health Check
0 1 * * 0 bash /home/flow/dev_mk/ansible_mk/scripts/health_check.sh >> /var/log/weblogic-health.log


# ==== BACKUP SCRIPT ERSTELLEN ====
cat > scripts/backup_domain.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/mnt/backups/weblogic/$(date +%Y-%m-%d_%H-%M-%S)"
mkdir -p "$BACKUP_DIR"
kubectl cp weblogic/wls-admin-0:/u01/domains "$BACKUP_DIR/" -n weblogic
echo "✅ Backup erstellt: $BACKUP_DIR"
# Alte Backups löschen (älter als 30 Tage)
find /mnt/backups/weblogic -mtime +30 -type d -exec rm -rf {} \;
EOF

chmod +x scripts/backup_domain.sh
```

### PVC aufräumen (Speicher freigeben)
```bash
# ==== WARNUNG: BREAKING! ====
# Dies löscht ALLES auf dem PVC!

# ==== NUR IM NOTFALL ====
# 1. Backup erstellen (s. oben)
# 2. Pod anhalten
kubectl scale statefulset wls-admin --replicas=0 -n weblogic

# 3. PVC löschen
kubectl delete pvc pvc-weblogic-home -n weblogic

# 4. Neue PVC erstellen
kubectl apply -f k8s/pv.yaml

# 5. Alte Domain zurück kopieren (von Backup)
kubectl cp BACKUP/domains weblogic/wls-admin-0:/u01/domains -n weblogic

# 6. Pod wieder hochfahren
kubectl scale statefulset wls-admin --replicas=1 -n weblogic
```

---

## ⚡ NOTFALL-BEFEHLE

### "Alles ist kaputt - schnell neu starten!"
```bash
# ==== NOTFALL-RESET ====
# 1. Backup (FALLS NOCH MÖGLICH)
kubectl cp weblogic/wls-admin-0:/u01/domains ~/emergency-backup/ -n weblogic 2>/dev/null || echo "Backup fehlgeschlagen"

# 2. Alle Pods löschen
kubectl delete pods --all -n weblogic

# 3. Warten
sleep 30

# 4. Status prüfen
kubectl get pods -n weblogic

# 5. Logs schauen
kubectl logs wls-admin-0 -n weblogic -f
```

### "Kubectl geht nicht - was tun?"
```bash
# Minikube Shell
minikube -p wlcluster ssh

# Im Minikube:
docker ps | grep weblogic
docker logs <container-id>
docker exec -it <container-id> /bin/bash
```

### "Pod lädt ewig - abbrechen"
```bash
# Pod mit Timeout neu starten
timeout 120 kubectl delete pod wls-admin-0 -n weblogic || \
  kubectl delete pod wls-admin-0 -n weblogic --grace-period=0 --force
```

---

## 📞 FEHLERSAMMLUNG

| Fehler | Ursache | Lösung |
|--------|---------|--------|
| `ImagePullBackOff` | Image nicht vorhanden | Secret prüfen, Image URL checken |
| `CrashLoopBackOff` | Prozess stürzt ab | Logs mit `--previous` prüfen |
| `Pending` | Keine Ressourcen | PVC/Nodes/Limits prüfen |
| `ErrImagePull` | Auth-Fehler | Harbor-Secret erneuern |
| `OOMKilled` | Zu wenig RAM | Memory-Limit erhöhen |
| `Disk Quota Exceeded` | Speicher voll | Logs/Temp löschen |
| `Connection refused` | Service nicht erreichbar | Service/Port prüfen |

---

## 🎯 Quick-Command Übersicht

```bash
# ==== DAILY 5-MIN CHECK ====
watch -n 5 'kubectl get pods -n weblogic && echo "---" && kubectl top pods -n weblogic 2>/dev/null | head -5'

# ==== ALLE PROBLEME ZEIGEN ====
kubectl get pods -n weblogic | grep -v Running || echo "✅ Alle Pods OK"

# ==== SPEICHER LIMIT NÄHERT SICH ====
kubectl exec wls-admin-0 -n weblogic -- df /u01 | awk 'NR==2 && $5+0 > 80 {print "⚠️  WARNUNG: Speicher " $5 " belegt"}'

# ==== AUTOMATISCHER HEALTH-CHECK ====
until kubectl get pod wls-admin-0 -n weblogic | grep Running; do echo "Wartet..."; sleep 5; done

# ==== KOMPLETTER STATUS DUMP ====
kubectl get all -n weblogic -o wide > /tmp/weblogic-status-$(date +%s).txt && echo "Gespeichert!"
```

---

**Tipps:**
- Diese Datei in Favoriten speichern oder ausdrucken
- Commands mit Ctrl+C kopieren und rechts einfügen
- Bei `<POD-NAME>` und `<NAMESPACE>` anpassen
- Immer erst testen im `-n weblogic` (isoliert)

**Version:** 1.0 | **Datum:** Juni 2024

