# 📖 Glossar: Technische Begriffe einfach erklärt

Dieses Glossar erklärt alle Fachbegriffe in diesem Projekt ohne Technik-Überschuss.

---

## A

### Admin-Server
**Was ist das?**
Der zentrale WebLogic-Server, der die Domain verwaltet. Wie ein "Masterserver".

**Wo läuft er?**
Als Pod: `wls-admin-0`

**Wofür brauchst du das?**
- Verwaltung der Domäne
- Steuerung von Managed Servers
- Web-Konsole (7001/console)

**Was ist normal?**
Sollte immer laufen. Wenn weg → kritisch!

---

### Affinity (Pod-Affinity)
**Was ist das?**
Regel, die sagt "dieser Pod sollte auf diesem Node laufen".

**Beispiel:**
"Managed Server 1 sollte immer auf Node 'worker-1' laufen"

**Wann ist das wichtig?**
- Performance (schnelle Kommunikation zwischen Pods)
- Licensing (einige Software braucht bestimmte Hardware)
- Compliance (Daten müssen in bestimmtem Rechenzentrum sein)

---

## B

### Backup
**Was ist das?**
Kopie aller wichtigen Dateien, um sie später wiederherstellen zu können.

**Wo sind deine Daten?**
- Domain-Konfiguration
- Datenbank-Connections
- SSL-Zertifikate

**Wie oft?**
Mindestens täglich!

---

## C

### ConfigMap
**Was ist das?**
Container mit Konfigurationsdateien (nicht der Code, nur Einstellungen).

**Beispiel in deinem Projekt:**
`gen-ssh-keys-config.yaml` - SSH-Einstellungen

**Wie wird das verwendet?**
Wird beim Pod-Start als Datei "eingehängt" (mounted).

---

## D

### Deployment (vs. StatefulSet)
**Deployment:**
- Für stateless Apps (keine Persistierung)
- Pods sind austauschbar (Pod 1 = Pod 2 = Pod 3)
- Beispiel: Webserver mit Load-Balancer

**StatefulSet:**
- Für stateful Apps (mit Daten/Zustand)
- Pods haben Identität (Pod 1 ≠ Pod 2)
- Jeder Pod hat eindeutigen Namen
- Beispiel in deinem Fall: `wls-managed-1`, `wls-managed-2`, etc.

---

## E

### Event
**Was ist das?**
Eine Benachrichtigung über etwas, das im Cluster passiert ist.

**Beispiele:**
- "Pod gestartet"
- "Image konnte nicht gepullt werden"
- "Speicher voll"

**Wo sehe ich Events?**
`kubectl describe pod <name>` → Sektion "Events:"

---

## F

### Floating IP
**Was ist das?**
Eine virtuelle IP-Adresse, die zwischen mehreren Servern "wandern" kann.

**Wann braucht du das?**
Für High Availability (wenn Admin-Server ausfällt, übernimmt Backup).

---

## G

### Graceful Shutdown
**Was ist das?**
Ein kontrolled Herunterfahren, wo die App vorher aufgeräumt wird.

**Gegenteil:** Hard Kill = sofort weg (Breaking!).

**Wie lange dauert das?**
i.d.R. 30 Sekunden bis 2 Minuten.

---

## H

### Headless Service
**Was ist das?**
Ein Service ohne Load-Balancer IP.

**Wofür?**
Damit StatefulSets stabil DNS-Namen bekommen.

**In deinem Projekt:**
`wls-managed-1`, `wls-managed-2` haben jeweils eigenen DNS-Namen.

---

## I

### Ingress
**Was ist das?**
Ein Eingang ins Cluster von außen.

**Wie funktioniert das?**
Externe Requests → Ingress-Controller → Service → Pod

**In deinem Projekt:**
Mit Ingress könntest du von außen auf Admin-Console zugreifen (statt Port-Forward).

---

## J

### Java Heap
**Was ist das?**
Der Speicherbereich, den Java für deine App reserviert.

**Warum ist das wichtig?**
- Zu klein → OutOfMemory Error
- Zu groß → Andere Pods haben kein Speicher

**Wie stellt man das ein?**
`-Xms` = minimale Heap  
`-Xmx` = maximale Heap  
Beispiel: `-Xms2g -Xmx4g` = Start mit 2GB, max 4GB

---

## K

### kubectl
**Was ist das?**
Das Kommandozeilen-Tool, um mit Kubernetes zu reden.

**Wie ist dein Alias?**
`kc` = `kubectl -n weblogic`

**Wichtig:**
Kommt mit "kube" (Cloud-Plattform) + "control" (steuern).

---

## L

### Labels & Selectors
**Labels:**
"Tags" auf Objekten, um sie zu organisieren.

**Beispiel:**
`app: wls-admin`, `tier: backend`

**Selectors:**
Suchfilter mit Labels.

**Beispiel:**
`kubectl get pods -l app=wls-admin` = Alle Pods mit Label app=wls-admin

---

## M

### Managed Server
**Was ist das?**
Ein Arbeits-WebLogic-Server, der vom Admin-Server verwaltet wird.

**Anzahl in deinem Projekt:**
3 Stück: `wls-managed-1`, `wls-managed-2`, `wls-managed-3`

**Wofür?**
Für deine Anwendungen (Geschäftslogik).

---

### Minikube
**Was ist das?**
Ein Test-Kubernetes-Cluster auf deinem lokalen PC.

**Dein Profil:**
`wlcluster` (4 Nodes: 1 Control + 3 Worker)

**Wann brauchst du das?**
Für Development & Testing, nicht für Production!

---

## N

### Namespace
**Was ist das?**
Isolierter Arbeitsbereich im Cluster.

**Dein Namespace:**
`weblogic`

**Warum das gut ist:**
- Verschiedene Teams können gleichzeitig darin arbeiten
- Berechtigungen separat pro Team
- Resources separat tracken

---

### Node
**Was ist das?**
Ein einzelner Computer/Server im Kubernetes-Cluster.

**In deinem Projekt:**
4 Nodes:
- `wlcluster` (Control Plane)
- `wlcluster-m02` (Worker)
- `wlcluster-m03` (Worker)
- `wlcluster-m04` (Worker)

---

## O

### OutOfMemory (OOM)
**Was ist das?**
Pod braucht mehr Speicher als erlaubt.

**Was passiert?**
Pod wird automatisch gelöscht ("OOMKilled").

**Behebung:**
Memory-Limit erhöhen oder App optimieren.

---

## P

### Pod
**Was ist das?**
Der kleinste runnable Objekt in Kubernetes.

**Vereinfacht:**
Pod ≈ Container (hier: WebLogic-Prozess)

**Deine Pods:**
- `wls-admin-0`
- `wls-managed-1-0`
- `wls-managed-2-0`
- `wls-managed-3-0`

---

### PVC (PersistentVolumeClaim)
**Was ist das?**
Ein Antrag auf Speicherplatz ("Ich brauche 5GB").

**Vereinfacht:**
PVC = Reservierter Speicher für deine Domain-Daten.

**In deinem Projekt:**
`pvc-weblogic-home` (5GB oder mehr)

---

### PV (PersistentVolume)
**Was ist das?**
Der echte Speicherplatz (Festplatte, NAS, Cloud-Storage).

**Unterschied zu PVC:**
- PV = physischer Speicher
- PVC = Antrag auf Speicher

**Vereinfacht:**
PV ≈ echte Platte  
PVC ≈ Reservierung darauf

---

## Q

### QoS (Quality of Service)
**Was ist das?**
Priorität eines Pods bei Speicherknappheit.

**Level:**
1. **Guaranteed** = Guaranteed (Requests = Limits)
2. **Burstable** = Kann aber nicht garantiert (Requests < Limits)
3. **BestEffort** = Kein Guarantee

**Wofür wichtig?**
Bei Speicherknappheit: BestEffort wird zuerst gelöscht!

---

## R

### Replica
**Was ist das?**
Eine Kopie eines Pods.

**Beispiel:**
Deployment mit 3 Replicas = 3 identische Pods laufen parallel.

**In deinem Projekt:**
StatefulSets haben jeweils 1 Replica (nicht mehrere, weil Identität wichtig).

---

### Rollout
**Was ist das?**
Ein Update von Pods ohne komplett down zu gehen.

**Wie funktioniert das?**
1. Neuen Pod starten
2. Warten bis ready
3. Alten Pod stoppen
4. Repeat

**In deinem Projekt:**
`kubectl rollout restart deployment wls-admin`

---

## S

### Secret
**Was ist das?**
ConfigMap, aber für sensible Daten (Passwörter, Keys).

**In deinem Projekt:**
- `weblogic-admin-secret` = Passwörter
- `wls-image-secret` = Harbor-Auth-Daten

**Wichtig:**
Nicht im Git speichern! Verschlüsseln mit Vault!

---

### Service
**Was ist das?**
Ein "Eingang" zu deinen Pods.

**Ohne Service:**
Pod-IP ist zu instabil, ständig andere IP.

**Mit Service:**
Stabile DNS-Name + Load-Balancer.

**In deinem Projekt:**
`wls-admin` = Service, der auf den Admin-Pod zeigt.

---

### StatefulSet
**Was ist das?**
Verwaltung von Pods, die Identität und Reihenfolge brauchen.

**Eigenheiten:**
- Pods haben feste Namen (nicht zufällig)
- Starten in Reihenfolge
- Volumes bleiben erhalten

**Deine StatefulSets:**
- `wls-admin` (1 Replica)
- `wls-managed-1` (1 Replica)
- `wls-managed-2` (1 Replica)
- `wls-managed-3` (1 Replica)

---

### StorageClass
**Was ist das?**
Vorlage für neue PVs ("Speichermaterial").

**Beispiele in deinem Cluster:**
- `manual` = lokale Festplatte
- `metro-nas` = Shared Network Storage

---

## T

### Taint & Tolerations
**Taint:**
"Diese Node mag bestimmte Pods nicht" (z.B. nur GPU-Pods)

**Tolerations:**
"Dieser Pod verträgt sich mit dieser Taint"

**Szenario:**
Node mit GPU hat Taint "gpu=true", nur GPU-Pods haben Tolerations dafür.

---

## U

### Update Strategy
**Was ist das?**
Plan für das Hochfahren neuer Versionen.

**RollingUpdate (standard):**
Pod für Pod aktualisieren, keine Downtime.

**Recreate:**
Alle Pods gleichzeitig neu → Kurze Downtime.

---

## V

### Volume
**Was ist das?**
Speicher, den ein Pod nutzen kann.

**Typen:**
- **emptyDir** = Temporär (weg wenn Pod weg)
- **hostPath** = Dateien vom Host
- **PVC** = Persistenter Storage (bleibt erhalten)

---

## W

### WebLogic Operator
**Was ist das?**
Ein spezieller Kubernetes-Controller für WebLogic-Domains.

**Was macht er?**
- Überwacht Domain Custom Resources (YAML-Dateien)
- Deployt automatisch Pods
- Kümmert sich um Domain-Lifecycle

**Ist der vorhanden?**
`kubectl api-resources | grep domain`

---

## X

### X509 Certificate
**Was ist das?**
Ein SSL/TLS-Zertifikat für verschlüsselte Verbindungen.

**Format:**
`.pem` oder `.crt` Datei

**Wo in deinem Projekt?**
Im PVC: `/u01/domains/certs/`

---

## Y

### YAML
**Was ist das?**
Datei-Format für Kubernetes-Objekte.

**Beispiel:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mein-pod
spec:
  containers:
  - name: weblogic
    image: oracle/weblogic:14.1.1.0
```

**Wichtig:**
Einrückung ist KRITISCH! (2 Spaces, kein Tab)

---

## Z

### Zone (Availability Zone)
**Was ist das?**
Physisches Rechenzentrum oder Gebäude.

**Wofür wichtig?**
Disaster Recovery: Pods auf verschiedene Zonen verteilen.

**In deinem Projekt:**
Nur ein Cluster/eine Zone → nicht relevant (local dev).

---

## Abkürzungen Quick-Ref

| Abk. | Bedeutung | Beispiel |
|------|-----------|---------|
| **API** | Application Programming Interface | kubectl = Kubernetes API Client |
| **CNAME** | Canonical Name | DNS-Alias |
| **CPU** | Central Processing Unit | 1000m = 1 Kern |
| **CRD** | Custom Resource Definition | Domain = custom Resource |
| **DNS** | Domain Name System | wls-admin.weblogic.svc |
| **GiB** | Gibibyte (1024³ bytes) | 2Gi = 2 GiB |
| **HA** | High Availability | Redundanz, kein Single Point of Failure |
| **IPAM** | IP Address Management | Wer verteilt die IPs? |
| **YAML** | YAML Ain't Markup Language | Konfigurationsformat |
| **RBAC** | Role Based Access Control | Wer darf was? |

---

## Wichtige Port-Nummern

| Port | Service | Zugang |
|------|---------|--------|
| **7001** | Admin Console | http://localhost:7001/console |
| **7002** | Admin Server (SSL) | https://localhost:7002/console |
| **8001** | Managed Server 1 | App-Server |
| **8002** | Managed Server 2 | App-Server |
| **8003** | Managed Server 3 | App-Server |
| **30222-30225** | SSH NodePorts | `ssh docker@host -p 30222` |

---

## Wichtige Dateipfade (im Container)

| Pfad | Was ist da? | Größe (ca.) |
|-----|-----------|-----------|
| `/u01/oracle` | WebLogic Installation | 5-10 GB |
| `/u01/domains` | Domain-Konfiguration & Logs | 1-5 GB |
| `/u01/domains/*/servers/*/logs` | Wichtigste Logs! | 100 MB - 5 GB |
| `/u01/domains/*/servers/*/tmp` | Temporäre Dateien | 10-100 MB |
| `~/.ssh/authorized_keys` | SSH-Keys | Bytes |

---

## Command-Struktur verstehen

```bash
kubectl          # Kubernetes-Befehls-Tool
  get            # Hol mir Info
  pods           # Von Pods
  -n weblogic    # In Namespace weblogic
  -o wide        # Mit mehr Spalten
  
# Ergebnis: "Gib mir alle Pods im Namespace weblogic, mit viel Info"
```

---

## Häufige Fehler im Glossar

### "CrashLoopBackOff" bedeutet...
Pod stürzt ab, Kubernetes versucht neu zu starten, stürzt wieder ab...

### "ImagePullBackOff" bedeutet...
Container-Image kann nicht gepullt werden (nicht vorhanden, Auth-Fehler).

### "Pending" bedeutet...
Kubernetes kann Platz für Pod nicht finden (Speicher, Ressourcen, etc.).

### "OOMKilled" bedeutet...
Pod hat zu viel RAM verbraucht, wurde gelöscht.

---

**Version:** 1.0 | **Datum:** Juni 2024

Fragen? Gib ein Wort in eine Suchmaschine ein + "Kubernetes" = sollte dir helfen!

