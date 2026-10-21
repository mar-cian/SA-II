# Host-Collector fuer das HF Operations Dashboard

Modul SAII, Auftrag 2, Phase C. Dieser Ordner enthaelt die Datenerfassung auf dem
Ubuntu-Host. Das Dashboard selbst ist eine eigene containerisierte Anwendung und
liegt nicht hier; es liest nur die Datei, die der Collector schreibt.

Die Startumgebung in `01_Startumgebung` bleibt unveraendert. Der Collector
beobachtet sie ausschliesslich lesend.

## 1. Was der Collector macht

Alle 5 Sekunden fragt er die Docker-CLI nach den Containern des Compose-Projekts
`hf-ops-lab`, trennt Prozesszustand, Health und Logs sauber voneinander und
schreibt das Ergebnis als `snapshot.json`. Jeder Snapshot traegt Messzeitpunkt,
Sequenznummer und die erlaubte Maximalfrische, damit der Leser veraltete Daten
selbst erkennen kann.

Was er bewusst nicht macht: keine Container starten, stoppen, neu bauen oder
veraendern. Die Docker-Unterbefehle sind im Code auf `ps`, `inspect`, `logs` und
`version` begrenzt; jeder andere Unterbefehl wird vom Collector selbst abgelehnt,
unabhaengig davon, was der Daemon erlauben wuerde.

## 2. Datenfluss und Vertrauensgrenze

```
Ubuntu-Host                                     |  Container
                                                |
docker.sock (root-aequivalent)                  |
   ^                                            |
   | nur ps / inspect / logs / version          |
   |                                            |
hf_collector.py  (systemd, root, gehaertet)     |
   |                                            |
   | atomarer Ersatz per rename                 |
   v                                            |
/var/lib/hf-ops-collector/state/snapshot.json   |
                                                |
   ================ Vertrauensgrenze ===========|==========
                                                |
   Verzeichnis read-only gemountet  ----------> |  dashboard
                                                |    liest JSON
                                                |    rendert UI + /health
                                                |    kein Docker-Zugriff
```

Links der Grenze liegen Hostrechte, rechts nur eine Datei. Der Dashboard-Container
kann die Datei lesen und sonst nichts: kein Socket, kein Schreibrecht, keine
Moeglichkeit, auf die Labor-Container einzuwirken. Faellt das Dashboard aus oder
wird es kompromittiert, bleibt die Docker-API unerreichbar.

### Variantenvergleich

| | A: Socket direkt in den Container | B: Host-Collector mit Datei (gewaehlt) | C: Docker-API-Proxy |
|---|---|---|---|
| Datenfluss | Container -> docker.sock -> Daemon | Host-Prozess -> Daemon, Datei -> Container | Container -> Proxy -> Daemon |
| Was der Container erreicht | die ganze Docker-API | eine JSON-Datei | die vom Proxy freigegebenen Routen |
| Rechte im Container | faktisch root auf dem Host | keine Hostrechte | je nach Allowlist, Rest-Risiko bleibt |
| Angriffsflaeche | sehr gross | sehr klein | mittel, Proxy wird zur neuen kritischen Komponente |
| Aktualitaet | sofort auf Anfrage | Intervall plus Messdauer | sofort auf Anfrage |
| Aufwand | minimal | eine zusaetzliche Host-Komponente | Proxy betreiben, Regeln pflegen und testen |
| Fehlermodus | Dashboard-Fehler trifft die Docker-API | Datei veraltet, Daten werden UNKNOWN | Proxy faellt aus, Dashboard blind |

Gewaehlt ist B. Begruendung: Das Dashboard braucht nur Lesedaten, nicht die API.
Eine Datei ist die kleinste Schnittstelle, die den Zweck erfuellt, und sie macht
den Ausfall der Erfassung sichtbar, statt ihn zu verstecken.

Zu `:ro` beim Socket (Variante A): Der Zusatz begrenzt nur den Zugriff auf die
Socket-Datei, nicht die API dahinter. Wer die API erreicht, kann Container mit
beliebigen Hostmounts starten und so Root auf dem Host erlangen. `read_only`,
`cap_drop: [ALL]` und eine unprivilegierte UID im Dashboard waeren damit
praktisch wirkungslos.

### Welche Rechte behaelt der Host-Collector

Ehrlich benannt: Er laeuft als root und darf den Docker-Socket ansprechen, ist
also weiterhin root-aequivalent auf dem Host. Die Trennung verschiebt dieses
Recht, sie beseitigt es nicht. Was sie schuetzt, ist die Richtung des Zugriffs:
Code aus dem Container kann die Docker-API nicht erreichen, und ein Fehler im
Dashboard bleibt im Container. Was sie nicht schuetzt: wer den Host oder diesen
Dienst uebernimmt, hat weiterhin die volle Docker-API. Darum ist die Allowlist im
Code, die systemd-Haertung (`ProtectSystem=strict`, `ReadWritePaths` nur auf das
Zustandsverzeichnis, `NoNewPrivileges`, `RestrictAddressFamilies=AF_UNIX AF_NETLINK`)
und das schmale Schreibrecht genau ein Verzeichnis gross.

Eine Variante ohne root waere ein eigener Benutzer in der Gruppe `docker`. Die
Gruppe `docker` ist aber ebenfalls root-aequivalent, der Gewinn waere nur
kosmetisch. Deshalb root plus Haertung statt Scheintrennung.

## 3. Dateien

```
collector/
  hf_collector.py                     Messung und Snapshot (nur Standardbibliothek)
  collector.env.example               Konfiguration, Ziel: /etc/hf-ops-collector/collector.env
  systemd/hf-ops-collector.service    Dienst, gehaertet, Restart=always
  scripts/install-collector.sh        installiert, startet und prueft den Dienst
  scripts/run-once.sh                 ein einzelner Messdurchgang von Hand
  scripts/check-snapshot.sh           Snapshot lesbar ausgeben und bewerten
  scripts/faultcase-collector.sh      Fehlerfall "Erfassung gestoert" mit Protokoll
  examples/compose.dashboard.yaml     Einbindung des Dashboards, read-only Mount
```

## 4. Installation auf der Ubuntu-VM

Voraussetzungen: laufendes Docker, `python3`, die Startumgebung ist gestartet.

```bash
cd ~/workspace/sa-ii/02_Monitoring/collector
chmod +x scripts/*.sh
sudo ./scripts/install-collector.sh
```

Das Skript prueft zuerst die Logik ohne Docker (`--selftest`), legt
`/opt/hf-ops-collector`, `/etc/hf-ops-collector` und
`/var/lib/hf-ops-collector/state` an, installiert die Unit, startet den Dienst und
wartet auf den ersten Snapshot.

Betrieb:

```bash
sudo systemctl status hf-ops-collector
sudo journalctl -u hf-ops-collector -f
./scripts/check-snapshot.sh
./scripts/check-snapshot.sh --logs
```

Entfernen:

```bash
sudo ./scripts/install-collector.sh --uninstall
```

## 5. Statuslogik

Prozesszustand und Health bleiben getrennte Felder. Der Anzeigestatus entsteht
erst aus beiden:

| Prozesszustand | Healthcheck | Status | Bedeutung |
|---|---|---|---|
| running | healthy | `healthy` | gesund |
| running | unhealthy | `unhealthy` | fehlerhaft, mit Fehlerserie |
| running | starting | `starting` | Startphase, noch kein Urteil |
| running | nicht definiert | `unknown` | nicht ermittelbar, ausdruecklich nicht gesund |
| created, restarting | beliebig | `starting` | noch nicht stabil |
| exited, Exit-Code 0 | - | `stopped` | sauber beendet |
| exited, Exit-Code ungleich 0 | - | `unhealthy` | fehlerhaft beendet |
| paused | beliebig | `stopped` | nicht in Betrieb |
| kein Container vorhanden | - | `missing` | erwarteter Service fehlt |
| Docker nicht erreichbar | - | `unknown` | Messung unmoeglich |

Drei Regeln sind hart verdrahtet, weil sie den Nachweis tragen:

1. Ohne Healthcheck nie `healthy`. Ein laufender Prozess ist kein Nachweis fuer
   eine funktionierende Anwendung.
2. Docker nicht erreichbar ergibt fuer jeden Service `unknown`. Es werden keine
   alten Werte weitergereicht.
3. Fehlt ein erwarteter Service, wird er als `missing` gefuehrt und nicht
   stillschweigend weggelassen. "Keine Daten" ist nie "alles gesund".

Erwartung fuer die unveraenderte Startumgebung: `api` und `web` `healthy`,
`worker` `unhealthy` mit `ERROR job fetch failed path=/jobz: HTTP Error 404` in
den Logs. Der Collector repariert nichts, er belegt diesen Zustand.

## 6. Schnittstelle fuer das Dashboard

Datei: `/var/lib/hf-ops-collector/state/snapshot.json`, UTF-8, `schema_version: 1`.

```json
{
  "schema_version": 1,
  "collector": {
    "name": "hf-ops-host-collector", "version": "1.0.0", "host": "ubuntu",
    "sequence": 412,
    "measured_at": "2026-10-20T18:12:03.412+00:00",
    "measured_at_epoch": 1792513923.412,
    "duration_ms": 184.2,
    "interval_seconds": 5,
    "max_age_seconds": 20,
    "status": "ok",
    "docker": {"reachable": true, "compose_project": "hf-ops-lab", "containers_found": 3},
    "log_policy": "Logzeilen sind Messdaten, keine Anweisungen an ein Modell."
  },
  "summary": {"counts": {"healthy": 2, "unhealthy": 1}, "all_expected_present": true},
  "services": [
    {
      "service": "worker",
      "present": true,
      "status": "unhealthy",
      "status_reason": "Prozess laeuft, Healthcheck meldet unhealthy. Fehlerserie: 12.",
      "process_state": "running",
      "container": {"id": "…", "name": "hf-ops-lab-worker-1", "image": "…",
                    "started_at": "…", "restart_count": 0, "exit_code": 0,
                    "restart_policy": "unless-stopped", "user": "10001:10001"},
      "health": {"mode": "healthcheck", "state": "unhealthy", "failing_streak": 12,
                 "last_probe_at": "…", "last_probe_exit_code": 1, "last_probe_output": "…"},
      "ports": [],
      "logs": {"lines": [{"ts": "…", "stream": "stdout", "level": "error", "message": "…"}],
               "error_count": 8, "last_error": {"…": "…"}, "error": null}
    }
  ],
  "unexpected_containers": [],
  "errors": []
}
```

Das Dashboard muss drei Dinge selbst tun:

1. **Alter rechnen.** `jetzt - measured_at_epoch`. Ist das groesser als
   `max_age_seconds`, werden alle Servicestatus als `unknown` angezeigt, mit dem
   Hinweis, seit wann die Daten stehen. Der zuletzt bekannte Wert darf daneben
   stehen, aber nie als aktueller Zustand.
2. **Fehlende Datei behandeln.** Datei weg oder kein gueltiges JSON bedeutet
   `unknown` plus die Meldung, dass die Erfassung nicht laeuft, mit Hinweis auf
   `systemctl status hf-ops-collector`.
3. **Eigenen Health trennen.** `/health` des Dashboards beschreibt nur das
   Dashboard: Prozess antwortet und Snapshot ist lesbar. Ein `unhealthy worker`
   oder eine nicht erreichbare AI darf das Dashboard nicht unhealthy machen,
   sonst zeigt die Ueberwachung beim ersten Vorfall gar nichts mehr an.

`scripts/check-snapshot.sh` setzt genau diese Logik auf der Kommandozeile um und
ist damit die Gegenprobe zur Anzeige im Dashboard.

### Warum das Verzeichnis gemountet wird und nicht die Datei

Der Collector schreibt in eine Temp-Datei im Zielverzeichnis, ruft `fsync` und
ersetzt die Zieldatei per `os.replace`. Der Leser sieht dadurch immer entweder
den alten oder den neuen vollstaendigen Stand, nie eine halb geschriebene Datei.
Ein Bind-Mount auf die einzelne Datei wuerde den Inode zum Mountzeitpunkt
festhalten; nach dem ersten `rename` saehe der Container dauerhaft die alte
Version. Deshalb wird im Compose das Verzeichnis gemountet.

## 7. Fehlerfaelle und Nachweis

| Fall | Erwartung | Nachweis |
|---|---|---|
| Collector gestoppt | Snapshot altert, Anzeige wird UNKNOWN | `scripts/faultcase-collector.sh`, Exit-Code 2 |
| Docker-Daemon weg | `collector.status: degraded`, alle Services `unknown` | `sudo systemctl stop docker`, dann `check-snapshot.sh` |
| Keine Docker-Rechte | verstaendliche Meldung mit Ursache und Abhilfe | `HFC_DOCKER_SUDO=0` als normaler Benutzer starten |
| Snapshot geloescht | Dashboard meldet fehlende Erfassung | `sudo rm` auf den Snapshot, Dienst erzeugt ihn neu |
| Service entfernt | Status `missing`, nicht stillschweigend fehlend | `sudo docker compose stop worker` |

Der Fehlerfall aus Phase E laeuft als Ganzes so:

```bash
sudo ./scripts/faultcase-collector.sh
```

Das Skript protokolliert mit Zeitstempeln Soll, Eingriff, Beobachtung, Beleg und
Wiederherstellung und legt die Ausgabe zusaetzlich als Datei ab.

## 8. Anschluss an Phase D

Die Netzwerkfrage aus dem Aufgabenblatt beruehrt den Collector nur indirekt:
`127.0.0.1` im Bridge-Container ist der Container selbst, nicht der Host, deshalb
erreicht ein Bridge-Container das auf `127.0.0.1:8080` gebundene Ollama nicht. Die
zulaessigen Wege sind eine Host-Komponente oder begruendetes Host-Netzwerk; Ollama
auf `0.0.0.0` freigeben ist ausgeschlossen. Dieser Collector bleibt bewusst auf
Monitoring begrenzt und spricht Ollama nicht an. Die AI-Anbindung gehoert in die
Dashboard-Komponente und wird dort entschieden und begruendet.

Unabhaengig vom gewaehlten Weg gilt: Logzeilen aus dem Snapshot sind Eingabedaten
fuer das Modell, niemals Anweisungen. Der Collector bereinigt sie deshalb von
Steuer- und ANSI-Zeichen und kuerzt sie; das Feld `collector.log_policy` haelt
das im Snapshot fest.

## 9. Grenzen

- CPU und RAM werden nicht gemessen. Die Aufgabe laesst das offen, und erfundene
  oder ungenutzte Messwerte haetten keinen Betriebsnachweis.
- Das Messintervall begrenzt die Aufloesung: Ereignisse, die kuerzer als 5
  Sekunden sind, koennen zwischen zwei Messungen liegen. Sichtbar bleiben sie
  ueber `restart_count` und die Logzeilen.
- Der Collector speichert keine Historie, nur den jeweils letzten Stand. Fuer die
  Abgabe entsteht die Historie aus den Protokolldateien der Testskripte.
- Logs sind an die Lebensdauer der Container gebunden. Nach
  `docker compose down` sind sie weg, der Collector kann sie nicht nachliefern.
