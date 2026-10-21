# Funktionsweise des Monitorings

Kurzuebersicht zu Auftrag 2, Phase C. Ausfuehrlich: `02_Monitoring/README.md`
und `02_Monitoring/collector/README.md`.

## Datenfluss

```
Docker-Daemon --> Collector (Host, root) --> snapshot.json --[read-only]--> Dashboard --> Browser
                                                                               |
Ollama 127.0.0.1:8080 <-- AI-Relay (Host, ohne Rechte) <------------------------
```

## Die drei Teile

**Collector** laeuft als systemd-Dienst direkt auf der Ubuntu-VM. Er fragt alle
5 Sekunden `docker ps`, `docker inspect` und `docker logs` ab und schreibt das
Ergebnis atomar nach `/var/lib/hf-ops-collector/state/snapshot.json`. Nur lesende
Befehle, alles andere lehnt er selbst ab.

**Dashboard** laeuft im Container und liest ausschliesslich diese Datei,
read-only gemountet. Es hat keinen Docker-Socket und keine Hostrechte.

**AI-Relay** laeuft ebenfalls auf dem Host, aber ohne jede Berechtigung: kein
Docker, keine Dateien, nur ein Netzsocket. Es lauscht auf dem Gateway des
Dashboard-Netzes und reicht genau eine Anfrageart an das unveraendert nur lokal
gebundene Ollama weiter.

## Warum getrennt

Der Docker-Socket ist root-aequivalent. Haette ihn der Container, waeren
`read_only`, `cap_drop: [ALL]` und die UID 10001 wirkungslos, weil der Weg nach
draussen nicht durch den Container fuehrt, sondern durch den Daemon. So bleiben
Hostrechte auf dem Host und der Container bekommt nur eine Datei.

Das Verzeichnis wird gemountet, nicht die Datei: der Collector ersetzt sie
atomar per `rename`. Ein Mount auf die Datei zeigt danach dauerhaft auf den
alten Inode.

## Drei Regeln, die alles tragen

1. Ohne Healthcheck nie `healthy`. Ein laufender Prozess beweist keine
   funktionierende Anwendung.
2. Daten aelter als 20 s: alle Services werden `nicht ermittelbar`, der letzte
   Wert bleibt nur als Zusatz sichtbar, nie als Istzustand.
3. Keine Daten sind nicht `alles gesund`, sondern `fehlend` oder
   `nicht ermittelbar` mit Ursache.

Darum ist der eigene `/health` des Dashboards unabhaengig vom beobachteten
worker und von der AI. Sonst faellt die Ueberwachung beim ersten Vorfall selbst
aus und zeigt gar nichts mehr an.

## Statuslogik

| Prozesszustand | Healthcheck | Status |
|---|---|---|
| running | healthy | gesund |
| running | unhealthy | fehlerhaft |
| running | starting | startet |
| running | nicht definiert | nicht ermittelbar |
| exited, Code 0 / paused | - | gestoppt |
| exited, Code ungleich 0 | - | fehlerhaft |
| kein Container | - | fehlend |
| Docker nicht erreichbar | - | nicht ermittelbar |

## Bedienung

```bash
cd ~/workspace/sa-ii/02_Monitoring

sudo systemctl status hf-ops-collector            # Erfassung laeuft?
./collector/scripts/check-snapshot.sh             # Gegenprobe zur Anzeige
sudo docker compose up -d                         # Dashboard starten/neu erstellen
sudo ./collector/scripts/faultcase-collector.sh   # Fehlerfall mit Protokoll
```

Erreichbar unter `http://<ubuntu-ip>:8090`.

| Route | Inhalt |
|---|---|
| `/` | Weboberflaeche, aktualisiert sich alle 5 s |
| `/api/state` | aufbereiteter Zustand als JSON |
| `/health` | Health des Dashboards selbst |
| sonst | HTTP 404 mit JSON-Fehler |

## Erwarteter Zustand der Laborumgebung

`api` und `web` gesund, `worker` fehlerhaft mit
`ERROR job fetch failed path=/jobz: HTTP Error 404` in den Logs. Ursache ist die
Abweichung zwischen `JOB_PATH=/jobz` in der Compose-Datei und der Route `/jobs`
in der API. Das Monitoring repariert nichts, es belegt diesen Zustand.

## Phase D: AI-Analyse

Der Button im Dashboard loest die ganze Kette aus: Messdaten erfassen, Prompt
bauen, HTTP-Anfrage an das Relay, Antwort verarbeiten, anzeigen.

Die Netzwerkfrage: `127.0.0.1` ist im Bridge-Container der Container selbst,
nicht der Host. Deshalb fragt das Dashboard nicht Ollama direkt, sondern das
Relay auf `172.31.240.1:8899`, dem Gateway seines eigenen Netzes. Ollama bleibt
unveraendert auf Loopback, das Dashboard bekommt kein Host-Netzwerk.

Das Relay ist kein durchreichender Proxy: nur die erlaubten Modelle, `stream`
immer false, Laenge und Dauer gedeckelt, eine Anfrage gleichzeitig. Der
Container kann damit kein Modell laden, erzeugen oder loeschen.

An das Modell gehen nur Servicename, Status, Prozesszustand, Health,
Fehlerserie, Neustarts, Exit-Code, Ports und wenige gekuerzte Logzeilen. Der
Prompt benennt sie ausdruecklich als Daten, nicht als Anweisungen.

Zurueck kommen vier Elemente: Beobachtung, Evidenz, vermutete Ursache,
naechster Schritt. Dazu gelten drei Regeln: Modelltext ist ein Vorschlag und
kein Messwert, er wird nie als HTML ausgefuehrt, und eine Analyse laeuft nur
auf frischen Daten.

## Deployment

Die vollstaendige Reihenfolge mit Pruefpunkten steht in
`02_Monitoring/DEPLOY.md`.
