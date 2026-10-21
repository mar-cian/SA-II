# Auftrag 2, Phase A: Statische Analyse

Erstellt am: 
Stand: vor dem ersten Build/Start

---

## api

**1. Base Image, kopierte Dateien, Startkommando und Prozess**
- Base Image: python:3.12-slim
- Kopierte Dateien: app.py
- Startkommando: CMD -->python, app.py
- Prozess: python läuft auf 8000

**2. Benutzer/UID, Dateisystemrechte, Capabilities und weitere Schutzmassnahmen**
- Benutzer/UID: 10001:10001
- Dateisystemrechte: Read Only
- Capabilities: alle gedropped
- Weitere Schutzmassnahmen: no-new privilege

**3. Containerport, Hostport, Bind-Adresse und eingehende/ausgehende Verbindungen**
- Containerport: 8000
- Hostport: keine
- Bind-Adresse: 
- Eingehende Verbindungen: Vom Web und Worker
- Ausgehende Verbindungen: - 

**4. Environment Variables: Compose gegenüber Code-Defaults**
- Variable: 
- Wert in Compose: 
- Default im Code: 
- Abweichung: 

**5. Persistenz**
- Überlebt Containerneuerstellung: Image
- Überlebt nicht: alles

**6. Healthcheck**
- Was wird geprüft: interval, timeout, retries, start_period
- Wann wird ein Fehler sichtbar: interval: 5s, timeout: 3s, retries nach 3x, start_period: 5s

**7. Startabhängigkeiten und Restart-Verhalten**
- Abhängig von: nichts
- Restart Policy: unless-stopped
- Verhalten bei Fehler: service Health: unhealthy

**8. Erwarteter Zustand und Health nach dem Start**
- Zustand: Running
- Health: Healthy
- Erwartete Logs: keine 
- Beleg (Datei und Zeile): -  

---

## web

**1. Base Image, kopierte Dateien, Startkommando und Prozess**
- Base Image: python:3.12-slim
- Kopierte Dateien: app.py
- Startkommando: CMD -->python, app.py
- Prozess: python läuft auf 8000

**2. Benutzer/UID, Dateisystemrechte, Capabilities und weitere Schutzmassnahmen**
- Benutzer/UID: 10001
- Dateisystemrechte: read Only
- Capabilities: all dropped
- Weitere Schutzmassnahmen: no-new-privilages:true

**3. Containerport, Hostport, Bind-Adresse und eingehende/ausgehende Verbindungen**
- Containerport: 8000
- Hostport: 127.0.0.1:8081 → 8000
- Bind-Adresse: 127.0.0.1
- Eingehende Verbindungen: Webbrowser
- Ausgehende Verbindungen: nach api

**4. Environment Variables: Compose gegenüber Code-Defaults**
- Variable: API_URL
- Wert in Compose: http://api:8000
- Default im Code: http://api:8000
- Abweichung: keine

**5. Persistenz**
- Überlebt Containerneuerstellung: keine
- Überlebt nicht: alles auser Image

**6. Healthcheck**
- Was wird geprüft: interval, retires, start_period, Custom Test (ist api & web erreichbar)
- Wann wird ein Fehler sichtbar: interval: 5s, timeout: 3s, retires: 3x, Customtest bei timeout

**7. Startabhängigkeiten und Restart-Verhalten**
- Abhängig von: api condition: service_healthy
- Restart Policy: unless-stopped
- Verhalten bei Fehler: service health: unhealty

**8. Erwarteter Zustand und Health nach dem Start**
- Zustand: Running
- Health: Healthy
- Erwartete Logs: -

---

## worker

**1. Base Image, kopierte Dateien, Startkommando und Prozess**
- Base Image: python:3.12-slim
- Kopierte Dateien: app.py
- Startkommando: CMD -->python, app.py
- Prozess: python läuft auf 8000

**2. Benutzer/UID, Dateisystemrechte, Capabilities und weitere Schutzmassnahmen**
- Benutzer/UID: 10001
- Dateisystemrechte: read_only
- Capabilities: all droped
- Weitere Schutzmassnahmen: no-new-privileges:true

**3. Containerport, Hostport, Bind-Adresse und eingehende/ausgehende Verbindungen**
- Containerport: 8000
- Bind-Adresse: 0.0.0.0
- Eingehende Verbindungen: Docker healthcheck
- Ausgehende Verbindungen: Health check nach api

**4. Environment Variables: Compose gegenüber Code-Defaults**
- Variable: api_url, Job_Path
- Wert in Compose:  http://api:8000, JOB_PATH:-/jobz
- Default im Code:  http://api:8000, JOB_PATH:-/jobs
- Abweichung: jobz/jobs

**5. Persistenz**
- Überlebt Containerneuerstellung: nichts
- Überlebt nicht: alles auser Image

**6. Healthcheck**
- Was wird geprüft: interval, timeout, retries, start_period
- Wann wird ein Fehler sichtbar: interval: 5s, timeout: 3s, retries: 3, start_period: 5s

**7. Startabhängigkeiten und Restart-Verhalten**
- Abhängig von: api: condition: service_healthy
- Restart Policy: unless-stopped
- Verhalten bei Fehler: service geht auf unhealthy

**8. Erwarteter Zustand und Health nach dem Start**
- Zustand: Running
- Health: Unhealthy
- Erwartete Logs: -