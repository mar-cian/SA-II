# Vorgegebene Docker-Umgebung - Auftrag 2

## Zuerst lesen, noch nicht ausführen
Dieser Ordner ist die Ausgangslage, keine von Ihnen entwickelte Lösung. Lesen Sie `compose.yaml`, alle drei `Dockerfile` und alle drei `app.py`. Erstellen Sie vor dem ersten Build/Start eine Vorhersage zu Ports, Datenfluss, Health, Fehlern, Rechten und Speicherung. Nutzen Sie die Analysevorlage im Aufgabenblatt. Auch vorhandene Startbefehle in dieser README dürfen erst danach ausgeführt werden.

## Dateien und Zweck
- `web/`: Browseroberfläche, prüft die API-Erreichbarkeit.
- `api/`: Demoauftrag und eigener Health-Endpunkt.
- `worker/`: ruft regelmässig einen Auftrag ab, schreibt Erfolge oder Fehler ins Log.
- `compose.yaml`: verbindet die Services. Die Laufzeitkonfiguration ist Teil der Analyse.

Keine Datenbank, keine Volumes und keine dauerhaften fachlichen Daten: Der API-Demoauftrag ist statisch. Die Zeit ist dynamisch. Der Worker verarbeitet denselben Demoauftrag wiederholt; dies ist keine echte Jobqueue mit Quittierung. Logs sind begrenzt und an die Lebensdauer der Container gebunden.

## Nach Abschluss der statischen Analyse
Auf Ubuntu in diesem Ordner:

```bash
sudo docker compose config
sudo docker compose up -d --build
sudo docker compose ps -a
curl -fsS http://127.0.0.1:8081/health
sudo docker compose logs --tail 20 worker
```

Etwa 25 Sekunden bis zum stabilen Health-Ergebnis einplanen. `web` und `api` sollen healthy sein. Der Worker enthält bewusst einen diagnostizierbaren Fehler und bleibt running/unhealthy. **Noch nicht reparieren:** Sichern Sie Zustand und Logs für Ihr Dashboard. `up --wait` ist hier ungeeignet, weil es auf einen gesunden Worker warten würde.

Health gezielt abfragen:

```bash
sudo docker inspect --format '{{json .State.Health}}' \
  "$(sudo docker compose ps -q worker)"
```

Bei einem Fehler vor dem Containerstart: Docker-Dienst, Compose-Verfügbarkeit, Image-Download und Portbelegung prüfen. Bei API-Problemen: zuerst API-Logs. Der absichtliche Worker-Fehler erklärt keine Buildfehler und keinen unhealthy-Webservice.

## Zurücksetzen und beenden
Ohne zusätzliche Environment-Variable verwendet Compose wieder seine Vorgabe. Eigene `.env`-Dateien können diese beeinflussen; Änderungen dokumentieren.

```bash
sudo docker compose down
sudo docker compose up -d --build
```

Zum Beenden nur `sudo docker compose down`. Keine anderen Container löschen.
