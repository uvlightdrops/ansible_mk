# 🔧 Troubleshooting Entscheidungsbaum

**Dein WebLogic-Problem? Folge diesem Baum, um schnell zur Lösung zu kommen.**

Starten Sie mit: **Sieht dein Cluster OK aus?**

---

## START: Cluster-Status prüfen

```bash
kubectl get pods -n weblogic -o wide
```

**Schritt 1: Was siehst du in der STATUS-Spalte?**

```
                           ┌─ Alle "Running" + Ready: 1/1?
                           │  → ALLES OK, kein Problem! ✅
                           │
Alle Pods anschauen ────┤
                           │
                           └─ Mindestens einer NICHT Running?
                              → Weiter zu "Schritt 2"
```

---

## Schritt 2: Fehlertyp identifizieren

```bash
kubectl get pods -n weblogic
```

**Was ist der STATUS?**

```
┌────────────────────────────────────────┐
│          POD STATUS TREE                │
├────────────────────────────────────────┤
│                                        │
├─ Running, aber Ready: 0/1?             │
│  └─ GEHE ZU: "Schritt 3a"              │
│                                        │
├─ ImagePullBackOff?                     │
│  └─ GEHE ZU: "Schritt 3b"              │
│                                        │
├─ CrashLoopBackOff / Exited?            │
│  └─ GEHE ZU: "Schritt 3c"              │
│                                        │
├─ Pending?                              │
│  └─ GEHE ZU: "Schritt 3d"              │
│                                        │
└─ Unknown / Terminating?                │
   └─ GEHE ZU: "Notfall-Befehle"         │
```

---

## Schritt 3a: Pod Running, aber nicht Ready (CrashLoop?)

**STATUS: `Running` aber `Ready: 0/1`**

### Test: Probiere das zuerst

```bash
# 1. Was ist in den Logs?
kubectl logs wls-admin-0 -n weblogic | tail -50

# 2. Startup-Fehler?
kubectl logs wls-admin-0 -n weblogic --previous
```

### Häufige Gründe:

```
┌─────────────────────────────────────────┐
│    "Running but not Ready" → Gründe:    │
├─────────────────────────────────────────┤
│                                         │
├─ Startup braucht länger als erwartet?  │
│  └─ WARTEN & beobachten (5-10 min)     │
│     kubectl logs -f wls-admin-0        │
│                                         │
├─ Readiness Probe fehlgeschlagen?       │
│  └─ kubectl describe pod...             │
│     → Liveness/Readiness fehlschlagen   │
│  └─ Heap zu klein?                      │
│     → GEHE ZU: Performance & Memory     │
│                                         │
├─ Java startet gar nicht?                │
│  └─ kubectl logs ... | grep -i error    │
│  └─ Logs zeigen fehler?                 │
│     → GEHE ZU: Schritt 3c (CrashLoop)   │
│                                         │
└─ Liveness Probe: Pod wird ständig gelöscht │
   └─ Readiness Probe zu streng?         │
      → Timeout erhöhen in Deployment    │
```

**Schnelle Maßnahmen:**

```bash
# Option 1: Einfach warten
watch kubectl get pods -n weblogic

# Option 2: Logs live beobachten
kubectl logs -f wls-admin-0 -n weblogic

# Option 3: Pod Logs detailliert
kubectl describe pod wls-admin-0 -n weblogic | grep -A10 "Liveness\|Readiness"

# Option 4: Pod neu starten
kubectl delete pod wls-admin-0 -n weblogic
```

---

## Schritt 3b: ImagePullBackOff

**STATUS: `ImagePullBackOff`**

Kubernetes kann das Container-Image nicht finden.

### Diagnose (in der Reihenfolge):

```bash
# 1. Welches Image wird versucht zu pullen?
kubectl describe pod wls-admin-0 -n weblogic | grep -i image

# 2. Gibt es ein Authentifizierungs-Secret?
kubectl get secret -n weblogic | grep -i image

# 3. Secret-Details anschauen
kubectl describe secret wls-image-secret -n weblogic
```

### Entscheidungsbaum:

```
┌─ Image URL korrekt?
│  ├─ JA: → Weiter zu nächster Frage
│  └─ NEIN: 
│     ├─ Edit group_vars/all.yml
│     ├─ weblogic_image: CORRECT_URL eintragen
│     ├─ ansible-playbook deployen
│     └─ Pod startet neu
│
├─ Secret existiert?
│  ├─ NEIN:
│  │  ├─ bash scripts/setup_harbor_secret.sh harbor.example.com user
│  │  ├─ kubectl apply -f
│  │  └─ Pod neu starten
│  └─ JA: → Weiter zu nächster Frage
│
├─ Secret hat richtige Auth?
│  ├─ NEIN:
│  │  ├─ kubectl delete secret wls-image-secret -n weblogic
│  │  ├─ Neu erstellen: bash scripts/setup_harbor_secret.sh ...
│  │  └─ Pod neu starten
│  └─ JA: → Image existiert nicht in Registry
│
└─ Image in Registry vorhanden?
   ├─ NEIN:
   │  ├─ Image pushen
   │  ├─ oder anderen Tag verwenden
   │  └─ group_vars/all.yml aktualisieren
   └─ JA: Netzwerk-Fehler → IT-Team fragen
```

### Schnelle Behebung:

```bash
# Option A: Secret neu erstellen
kubectl delete secret wls-image-secret -n weblogic
bash scripts/setup_harbor_secret.sh harbor.example.com user
kubectl apply -f <generated secret yaml>

# Option B: Pod neu starten (wenn Secret jetzt OK)
kubectl delete pod wls-admin-0 -n weblogic

# Option C: Image URL korrigieren
nano group_vars/all.yml
# weblogic_image: harbor.../wls:CORRECT_TAG
ansible-playbook k8s_weblogic/deploy_weblogic.yml
```

---

## Schritt 3c: CrashLoopBackOff oder Exited

**STATUS: `CrashLoopBackOff`, `Exited`, oder ständige Restarts**

Pod startet, aber stürzt sofort ab.

### Diagnose:

```bash
# 1. Letzten Crash-Logs anschauen
kubectl logs wls-admin-0 -n weblogic --previous | tail -100

# 2. Error-Zeilen rausfiltern
kubectl logs wls-admin-0 -n weblogic --previous | grep -i "error\|exception\|fatal"

# 3. Im Container nachschauen
kubectl exec -it wls-admin-0 -n weblogic -- tail -50 /u01/domains/*/servers/*/logs/*.log

# 4. Ist Java überhaupt gestartet?
kubectl exec wls-admin-0 -n weblogic -- ps aux | grep java
```

### Häufige Gründe & Lösungen:

```
┌────────────────────────────────────────────┐
│   CrashLoop → Häufige Fehler               │
├────────────────────────────────────────────┤
│                                            │
├─ OutOfMemory (OOM)?                        │
│  Logs zeigen: "OutOfMemoryError"           │
│  └─ LÖSUNG: RAM erhöhen                    │
│     kubectl set resources deployment ...   │
│     --limits=memory=8Gi                    │
│     kubectl rollout restart deployment     │
│                                            │
├─ Domain-Dateien kaputt?                    │
│  Logs zeigen: "Cannot find domain"         │
│  └─ LÖSUNG: Aus Backup wiederherstellen    │
│     kubectl cp backup/domains ... -n wl    │
│     kubectl delete pod ...                 │
│                                            │
├─ Falsches Image?                           │
│  Logs zeigen: "Java not found"             │
│  └─ LÖSUNG: Image-URL prüfen               │
│     GEHE ZU: Schritt 3b (ImagePullBackOff) │
│                                            │
├─ Datenpermissions-Fehler?                  │
│  Logs zeigen: "Permission denied"          │
│  └─ LÖSUNG: chmod/chown in Domain          │
│     kubectl exec ... -- chown docker:docker /u01 │
│     kubectl delete pod ...                 │
│                                            │
├─ Java nicht gestartet?                     │
│  Logs zeigen: nichts, oder Java error      │
│  └─ LÖSUNG: JAVA_OPTS prüfen               │
│     kubectl set env deployment ...         │
│     -e USER_MEM_ARGS="-Xms2g -Xmx4g"      │
│     kubectl rollout restart deployment     │
│                                            │
└─ Domain/Admin-Passwort falsch?             │
   Logs zeigen: "Authentication failed"      │
   └─ LÖSUNG: Passwort ändern + redeploy     │
      nano group_vars/all.yml                │
      ansible-playbook deploy...             │
```

### Schnelle Reparatur (Schritt für Schritt):

```bash
# 1. BACKUP ERST (falls nicht schon gemacht)
mkdir -p ~/emergency-backup
kubectl cp weblogic/wls-admin-0:/u01/domains ~/emergency-backup/ -n weblogic 2>/dev/null || true

# 2. Logs vollständig speichern
kubectl logs wls-admin-0 -n weblogic --previous > crash-logs.txt 2>&1
cat crash-logs.txt  # Analysieren

# 3. RAM erhöhen (häufigster Grund)
kubectl set resources deployment wls-admin \
  --limits=memory=8Gi \
  -n weblogic

# 4. Pod neu starten
kubectl rollout restart deployment wls-admin -n weblogic

# 5. Beobachten
kubectl logs -f wls-admin-0 -n weblogic

# 6. Wenn immer noch Crash: Domain-Restore
kubectl delete pod wls-admin-0 -n weblogic
# Warten
kubectl cp ~/weblogic-backups/LATEST/domains weblogic/wls-admin-0:/u01/ -n weblogic
kubectl delete pod wls-admin-0 -n weblogic
```

---

## Schritt 3d: Pending (Wartet, startet nicht)

**STATUS: `Pending`**

Kubernetes findet keinen Platz für den Pod.

### Diagnose:

```bash
# 1. Warum Pending?
kubectl describe pod wls-admin-0 -n weblogic | grep -A20 "Events:"

# 2. Node-Ressourcen
kubectl top nodes

# 3. Speicher reicht?
kubectl get pvc -n weblogic
kubectl describe pvc pvc-weblogic-home -n weblogic

# 4. Node-Affinity erfüllt?
kubectl describe node <node-name> | grep -i taint
```

### Entscheidungsbaum:

```
┌─ Was sagen die Events?
│
├─ "Insufficient memory/cpu"?
│  ├─ Pod-Limits zu hoch?
│  │  └─ kubectl set resources ... --limits=memory=2Gi
│  │
│  └─ Node hat echt zu wenig?
│     └─ Mehr Nodes hinzufügen (Plattform-Team)
│
├─ "StorageClass not found"?
│  ├─ PVC-StorageClass prüfen
│  │  kubectl get storageclass
│  │
│  └─ StorageClass in PVC-YAML korrigieren
│     kubectl edit pvc pvc-weblogic-home -n weblogic
│
├─ "no matching pod affinity"?
│  ├─ Pod affinity rules zu streng
│  │
│  └─ Rules in Deployment korrigieren
│     oder Nodes taggen
│
└─ "unschedulable" ohne weiteren Grund?
   └─ kubectl describe node <node>
      Taint/Tolerations prüfen
```

### Schnelle Lösungen:

```bash
# Option 1: Pod-Limits reduzieren
kubectl set resources deployment wls-admin \
  --limits=memory=2Gi \
  -n weblogic
# Dann: kubectl delete pod ... (neu mit Limits starten)

# Option 2: StorageClass checken
kubectl get pvc -n weblogic
# Sollte "Bound" sein
# Falls nicht:
kubectl edit pvc pvc-weblogic-home -n weblogic
# StorageClass korrigieren → speichern

# Option 3: Node-Taints entfernen (extreme Maßnahme!)
# NUR wenn Plattform-Team zustimmt
kubectl taint nodes <node-name> key=value:NoSchedule-

# Option 4: Backup, neu deployen (letzte Auswahl)
kubectl cp weblogic/wls-admin-0:/u01/domains ~/backup/ -n weblogic
kubectl delete ns weblogic --grace-period=0 --force
# Dann: Alles neu deployen
```

---

## Schritt 3e: Unknown oder Terminating

**STATUS: `Unknown`, `Terminating`, oder merkwürdig**

```bash
# 1. Force Delete
kubectl delete pod wls-admin-0 -n weblogic --grace-period=0 --force

# 2. Warten
sleep 10

# 3. Neu starten
kubectl delete pod wls-admin-0 -n weblogic

# Falls immer noch Probleme:
# 4. Node neu starten (extreme Maßnahme)
kubectl drain <node-name> --ignore-daemonsets
minikube stop -p wlcluster
minikube start -p wlcluster
kubectl uncordon <node-name>
```

---

## Spezial-Scenario: Speicher lädt zu schnell

```
Speicher war OK, jetzt plötzlich 90%+ belegt?
```

### Diagnose:

```bash
# Was ist groß geworden?
kubectl exec wls-admin-0 -n weblogic -- du -sh /u01/* | sort -h | tail

# Logs zu groß?
kubectl exec wls-admin-0 -n weblogic -- du -sh /u01/domains/*/servers/*/logs

# Temp-Dateien?
kubectl exec wls-admin-0 -n weblogic -- du -sh /u01/domains/*/servers/*/tmp
```

### Schnelle Lösungen (der Reihe nach):

```bash
# 1. Alte Logs löschen
kubectl exec wls-admin-0 -n weblogic -- \
  find /u01/domains/*/servers/*/logs -name "*.log.*" -mtime +7 -delete

echo "Speicher nach Cleanup:"
kubectl exec wls-admin-0 -n weblogic -- df -h /u01 | tail -1

# 2. Temp-Dateien räumen
kubectl exec wls-admin-0 -n weblogic -- \
  rm -rf /u01/domains/*/servers/*/tmp/*

# 3. Wenn immer noch voll: Pod neu starten (clearing)
kubectl delete pod wls-admin-0 -n weblogic
```

---

## Spezial-Scenario: Pod ständig neustarten (viele Restarts)

```
RESTARTS > 5 pro Tag = nicht OK
```

### Diagnose:

```bash
# Wann sind die Restarts passiert?
kubectl describe pod wls-admin-0 -n weblogic | grep -A5 "Last State"

# Logs von vor jedem Restart
kubectl logs wls-admin-0 -n weblogic --previous
```

### Gründe & Lösungen:

```
┌─ Memory Leak?
│  └─ Heap ständig voller werdend
│     → Heap-Size erhöhen oder App-Leak finden
│
├─ Regelmäßiger Speicher-Crash?
│  └─ Nachts/Mittags regelmäßig OOM
│     → Automatische Cleanup-Scripts einrichten
│
├─ Liveness Probe zu streng?
│  └─ Pod läuft, aber Probe denkt er ist weg
│     → Probe-Timeouts erhöhen
│
└─ Netzwerk-Unterbrechungen?
   └─ Pod verliert Connection, stürzt ab
      → DNS/Network-Stabilität prüfen
```

---

## Entscheidungsbaum: Schnell-Navigation

```
                         START: kubectl get pods
                               ↓
            ┌──────────────────┴──────────────────┐
            ↓                                      ↓
        Alle Running?                         Fehler sichtbar?
           ✅ OK                                  ↓
                          ┌─────────┬─────────┬─────────┬──────────┐
                          ↓         ↓         ↓         ↓          ↓
                        Running  ImagePull CrashLoop Pending   Unknown
                        (0/1)    BackOff    BackOff
                          ↓         ↓         ↓         ↓          ↓
                        3a →      3b →      3c →      3d →      3e →
                        Logs      Secret    Speicher  Storage    Force
                        Probe     URL       Heap      Affinity   Delete
```

---

## Notfall-Checkliste (wenn gar nichts mehr funktioniert)

```bash
# 1. Backup erstellen (SOFORT!)
mkdir -p ~/emergency-$(date +%s)
kubectl cp weblogic/wls-admin-0:/u01/domains ~/emergency-$(date +%s)/ -n weblogic 2>/dev/null || echo "Backup fehlgeschlagen"

# 2. Alles auf "Unknown" oder "Terminating"? Force Kill
kubectl delete pod --all -n weblogic --grace-period=0 --force

# 3. Warten
sleep 30

# 4. Status
kubectl get pods -n weblogic

# 5. Logs
kubectl logs wls-admin-0 -n weblogic 2>/dev/null || echo "Pod noch nicht gestartet"

# 6. Wenn immer noch nicht OK: ganze Domain neu
kubectl delete ns weblogic --grace-period=0 --force
# ODER
ansible-playbook k8s_weblogic/deploy_weblogic.yml
```

---

## Quick-Navigation nach Symptom

| Symptom | Gehe zu |
|---------|---------|
| "Pod lädt ewig" | Schritt 3a |
| "Cannot pull image" | Schritt 3b |
| "Java wird nicht gestartet" | Schritt 3c |
| "Pod startet gar nicht" | Schritt 3d |
| "Ständig Neustarts" | Speicher-Scenario |
| "Merkwürdiger Status" | Schritt 3e |
| "Speicher voll" | Speicher-Scenario |

---

## Wenn du immer noch steckst

**Schreib einen Bug-Report mit:**

1. Output von:
   ```bash
   kubectl get pods -n weblogic -o wide
   kubectl describe pod wls-admin-0 -n weblogic
   kubectl logs wls-admin-0 -n weblogic --previous
   ```

2. Wann ist das passiert?

3. Welche Änderungen davor?

4. Speicher/CPU verfügbar?
   ```bash
   kubectl top nodes
   kubectl top pods -n weblogic
   ```

5. Welchen Schritt hast du hier durchgearbeitet?

**Dann:** Kontaktiere dein Team/Plattform-Admin

---

**Version:** 1.0 | **Datum:** Juni 2024  
**Tipps:** Speichern & ausdrucken für schnellen Zugriff

