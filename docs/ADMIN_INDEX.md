# 📚 Admin Documentation Index

**Alle Admin-Guides für WebLogic on Kubernetes**

Letztes Update: Juni 2024

---

## 🎯 Einstieg: Welches Dokument brauchst du?

### Ich bin ganz neu hier
→ **Starte mit:** [Admin Guide - Basics verstehen](ADMIN_GUIDE.md#basics-verstehen)

### Ich muss schnell ein Problem beheben
→ **Nutze:** [Troubleshooting Entscheidungsbaum](ADMIN_TROUBLESHOOTING_TREE.md)

### Ich will schnell einen Befehl ausführen
→ **Schau in:** [Admin Quick Reference](ADMIN_QUICK_REFERENCE.md)

### Ich verstehe ein technisches Wort nicht
→ **Nachschlagen in:** [Admin Glossar](ADMIN_GLOSSARY.md)

### Ich will alles lernen (umfangreich)
→ **Lies:** [Admin Guide (vollständig)](ADMIN_GUIDE.md)

---

## 📖 Alle Dokumente mit Beschreibung

### 1. 🎯 Admin Guide (ADMIN_GUIDE.md) **← HAUPTDOKUMENT**

**Größe:** ~15 Seiten  
**Zielgruppe:** Admin-Anfänger bis Intermediate  
**Lernzeit:** 30-60 Minuten

**Inhalt:**
- Basics und Begriffe erklären
- Tägliche Aufgaben (Status prüfen, Logs lesen, Neustarten)
- Problembehebung mit Schritt-für-Schritt-Anleitung
- Sicherheit & Zugriff
- Backup & Wiederherstellung
- Monitoring & Logs
- Performance-Tuning
- Checklisten (täglich, wöchentlich, monatlich)

**Beste für:**
- Erstes Verständnis bekommen
- Tägliche Arbeitsabläufe
- Vertieftes Lernen einzelner Topics

---

### 2. ⚡ Quick Reference (ADMIN_QUICK_REFERENCE.md)

**Größe:** ~20 Seiten  
**Zielgruppe:** Admin mit etwas Erfahrung  
**Nutzungsart:** Copy-Paste

**Inhalt:**
- Schnelle Commands für häufige Tasks
- Fehlerdiagnose mit Copy-Ready-Befehlen
- Backup-Scripts
- Deployment-Scripts
- Notfall-Befehle
- Fehlersammlung

**Beste für:**
- Schnelle Referenz beim Arbeiten
- Copy-Paste-Ready Commands
- "Wie war nochmal der Befehl?"

---

### 3. 🔧 Troubleshooting Tree (ADMIN_TROUBLESHOOTING_TREE.md)

**Größe:** ~15 Seiten  
**Zielgruppe:** Admin mit Problem  
**Methode:** Interaktiver Entscheidungsbaum

**Inhalt:**
- Entscheidungsbäume für Fehlerdiagnose
- Pod-Status erklärt
- Häufige Fehler & Lösungen
- Speicher-Probleme
- Restart-Probleme
- Notfall-Checkliste

**Beste für:**
- "Mein System funktioniert nicht"
- Schnell zur Diagnose + Lösung
- Strukturiertes Troubleshooting

---

### 4. 📖 Glossar (ADMIN_GLOSSARY.md)

**Größe:** ~10 Seiten  
**Zielgruppe:** Admin mit Fragen  
**Nachschlagewerk**

**Inhalt:**
- Alle Fachbegriffe alphabetisch
- Einfache, verständliche Erklärungen
- Port-Nummern & Dateipfade
- Abkürzungen Quick-Ref

**Beste für:**
- "Was ist eigentlich ein Pod?"
- Schnelle Definition nachschlagen
- Verstehen von Kubernetes-Begriffen

---

## 🗂️ Themen-Übersicht

### Basics & Verständnis
- [Basics verstehen](ADMIN_GUIDE.md#basics-verstehen) (Guide)
- [Glossar](ADMIN_GLOSSARY.md) (vollständig)

### Tägliche Aufgaben
- [Status prüfen](ADMIN_GUIDE.md#1️⃣-status-prüfen-läuft-alles)
- [Logs ansehen](ADMIN_GUIDE.md#2️⃣-logs-ansehen-was-macht-weblogic-gerade)
- [Pod neu starten](ADMIN_GUIDE.md#3️⃣-pod-neu-starten-ich-will-weblogic-neustarten)
- [Quick Commands](ADMIN_QUICK_REFERENCE.md#-quick-command-übersicht)

### Problembehebung
- [Troubleshooting Tree](ADMIN_TROUBLESHOOTING_TREE.md) (Start)
- [Häufige Fehler](ADMIN_GUIDE.md#-problem-pod-ist-nicht-gestartet-imagepullbackoff)
- [Fehlersammlung](ADMIN_QUICK_REFERENCE.md#-fehlersammlung)

### Speicher & Performance
- [Speicher prüfen](ADMIN_GUIDE.md#5️⃣-speicher-prüfen-ist-noch-platz)
- [Performance-Probleme](ADMIN_GUIDE.md#-problem-speicher-ist-plötzlich-belegt)
- [Ressourcen-Monitoring](ADMIN_GUIDE.md#1️⃣-wichtige-metriken-regelmäßig-prüfen)

### Sicherheit
- [Passwort-Management](ADMIN_GUIDE.md#1️⃣-admin-passwort-weblogic-console)
- [SSH-Zugang](ADMIN_GUIDE.md#3️⃣-ssh-zugang-zu-den-containern)
- [Netzwerk-Sicherheit](ADMIN_GUIDE.md#4️⃣-netzwerk-sicherheit)

### Backup & Recovery
- [Backup erstellen](ADMIN_GUIDE.md#2️⃣-backup-erstellen-domain)
- [Backup-Automation](ADMIN_QUICK_REFERENCE.md#cron-job-für-automatisches-backup)
- [Aus Backup wiederherstellen](ADMIN_QUICK_REFERENCE.md#aus-backup-wiederherstellen)

### Deployment & Updates
- [Neue Version deployen](ADMIN_QUICK_REFERENCE.md#neue-version-deployen)
- [Rollback](ADMIN_QUICK_REFERENCE.md#rollback-zurück-zu-alter-version)

### Checklisten
- [Tägliche Checkliste](ADMIN_GUIDE.md#-tägliche-wartungs-checkliste-5-min)
- [Wöchentliche Checkliste](ADMIN_GUIDE.md#-wöchentliche-wartungs-checkliste)
- [Monatliche Checkliste](ADMIN_GUIDE.md#-monatliche-wartungs-checkliste)
- [Vor Änderungen](ADMIN_GUIDE.md#-vor-größeren-änderungen)

---

## 💡 Häufige Use Cases: Welches Dokument?

| Use Case | Dokument | Sektion |
|----------|----------|---------|
| "Pod lädt nicht" | Troubleshooting | Schritt 3b |
| "Speicher läuft voll" | Quick Ref | Speicher-Probleme |
| "Fehler in Logs" | Admin Guide | Logs ansehen |
| "Wie neustarten?" | Quick Ref | Restart-Szenarios |
| "Pod stürzt ab" | Troubleshooting | Schritt 3c |
| "Backup machen" | Quick Ref | Backup erstellen |
| "Was ist ein Pod?" | Glossar | Pod |
| "Tägliche Kontrolle" | Admin Guide | Checklisten |

---

## 📊 Dokumentenlaufzeit

| Dokument | Erstes Lesen | Nachschlagen | Learning Path |
|----------|-------------|----------------|---|
| Admin Guide | 45 min | 5 min | 1️⃣ Start hier |
| Quick Reference | - | 1-2 min | 2️⃣ Daily work |
| Troubleshooting | 30 min | 5-10 min | 3️⃣ Bei Problemen |
| Glossar | 20 min | <1 min | Anytime |

---

## 🎓 Learning Path für neue Admins

### Tag 1: Grundlagen
1. [ ] Lese: [Admin Guide - Basics](ADMIN_GUIDE.md#basics-verstehen)
2. [ ] Schau: [Glossar](ADMIN_GLOSSARY.md) (Top 20 Begriffe)
3. [ ] Versuche: `kubectl get pods -n weblogic` (Status prüfen)
4. [ ] Versuche: `kubectl logs -n weblogic wls-admin-0` (Logs lesen)

### Tag 2: Tägliche Aufgaben
1. [ ] Lese: [Tägliche Aufgaben](ADMIN_GUIDE.md#tägliche-aufgaben)
2. [ ] Praktiziere: Pod neu starten
3. [ ] Praktiziere: Speicher prüfen
4. [ ] Praktiziere: Konfiguration anschauen

### Woche 1: Problembehebung
1. [ ] Lese: [Troubleshooting Tree](ADMIN_TROUBLESHOOTING_TREE.md)
2. [ ] Speichere: [Quick Reference](ADMIN_QUICK_REFERENCE.md) lokal
3. [ ] Praktiziere: Fehler nachstellen & beheben
4. [ ] Mache: [Tägliche Checkliste](ADMIN_GUIDE.md#-tägliche-wartungs-checkliste-5-min)

### Woche 2-4: Vertiefung
1. [ ] Lese: [Backup & Recovery](ADMIN_GUIDE.md#backup--wiederherstellung)
2. [ ] Lese: [Monitoring & Logs](ADMIN_GUIDE.md#monitoring--logs)
3. [ ] Erstelle: Automatisierte Backup-Scripts
4. [ ] Richte ein: Tägliche Health-Checks

### Monat 2+: Mastery
1. [ ] Lese: [Performance-Tuning](ADMIN_GUIDE.md#performance--ressourcen)
2. [ ] Lese: [Sicherheit](ADMIN_GUIDE.md#sicherheit--zugriff)
3. [ ] Entwickle: Eigene Monitoring-Scripts
4. [ ] Dokumentiere: Deine Erfahrungen & Findings

---

## 📚 Externe Ressourcen

### Offizielle Dokumentation
- [Kubernetes Docs](https://kubernetes.io/docs/) - Offizielle K8s-Docs
- [kubectl Cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/) - kubectl Commands

### WebLogic-Spezifisch
- [WebLogic Operator](https://github.com/oracle/weblogic-kubernetes-operator) - GitHub
- [WebLogic Docs](https://docs.oracle.com/en/middleware/weblogic/) - Oracle WebLogic

### Troubleshooting
- [Kubernetes Debugging](https://kubernetes.io/docs/tasks/debug-application-cluster/) - K8s Debugging
- [WebLogic Logs](https://docs.oracle.com/en/middleware/weblogic/14.1.1.5/wldbg/debugging.html) - WebLogic Logging

---

## 🔍 Schnelle Suche im Index

### Nach Fehler
- ImagePullBackOff → [Quick Ref](ADMIN_QUICK_REFERENCE.md) oder [Troubleshooting 3b](ADMIN_TROUBLESHOOTING_TREE.md#schritt-3b-imagepullbackoff)
- CrashLoopBackOff → [Troubleshooting 3c](ADMIN_TROUBLESHOOTING_TREE.md#schritt-3c-crashloopbackoff-oder-exited)
- Pending → [Troubleshooting 3d](ADMIN_TROUBLESHOOTING_TREE.md#schritt-3d-pending-wartet-startet-nicht)

### Nach Aufgabe
- Status prüfen → [Admin Guide](ADMIN_GUIDE.md#1️⃣-status-prüfen-läuft-alles)
- Backup machen → [Quick Ref](ADMIN_QUICK_REFERENCE.md#-backup-erstellen)
- Pod neu starten → [Admin Guide](ADMIN_GUIDE.md#3️⃣-pod-neu-starten-ich-will-weblogic-neustarten)

### Nach Thema
- Speicher → [Admin Guide](ADMIN_GUIDE.md#5️⃣-speicher-prüfen-ist-noch-platz)
- Sicherheit → [Admin Guide](ADMIN_GUIDE.md#sicherheit--zugriff)
- Logs → [Quick Ref](ADMIN_QUICK_REFERENCE.md#-logs-durchsuchen)

---

## ✅ Checkliste für Admin-Setup

- [ ] Alle 4 Dokumente lokal / bookmarked
- [ ] Quick Reference ausgedruckt
- [ ] kubectl alias gesetzt: `alias kc="kubectl -n weblogic"`
- [ ] Troubleshooting Tree verstanden
- [ ] Tägliche Checkliste in Kalender
- [ ] Backup-Script aufgesetzt
- [ ] Team-Kontakte dokumentiert

---

## 📞 Support & Fragen

**Wenn du nicht weiterkommst:**

1. Schau in [Glossar](ADMIN_GLOSSARY.md) nach unbekannten Worten
2. Nutze [Troubleshooting Tree](ADMIN_TROUBLESHOOTING_TREE.md) für dein Problem
3. Suche in [Quick Reference](ADMIN_QUICK_REFERENCE.md) nach einem ähnlichen Fehler
4. Lese [FAQ in Admin Guide](ADMIN_GUIDE.md#häufig-gestellte-fragen-faq)
5. Kontaktiere: [Support-Kontakte](ADMIN_GUIDE.md#support--kontakte)

---

## 🎯 Tipps für Admins

**Tägliche Routine (5 min):**
```bash
kubectl get pods -n weblogic  # Status
kubectl top pods -n weblogic   # CPU/RAM
```

**Wöchentliche Routine (30 min):**
```bash
# Aus Checkliste
```

**Monatliche Routine (1h):**
```bash
# Aus Checkliste
```

---

## 📝 Versions-Info

**Diese Dokumentation gilt für:**
- WebLogic: 14.1.1.0+
- Kubernetes: 1.20+
- Minikube: 1.25+

**Erstellt:** Juni 2024  
**Letzte Aktualisierung:** Juni 2024  
**Nächste Review:** September 2024

---

**Navigation:**
- [← Zurück zu Projektdokumenten](README.md)
- [Zum Admin Guide →](ADMIN_GUIDE.md)
- [Zum Quick Reference →](ADMIN_QUICK_REFERENCE.md)

---

Viel Erfolg beim Administrieren! 🚀

