# Service Clock

Kleine zustandslose Webanwendung fuer Auftrag 3. Zeigt den eigenen
Betriebszustand: konfigurierter Name, Status, Zeit in einer konfigurierten
Zeitzone, Laufzeit seit Prozessstart und Anzahl bedienter Anfragen.

Entwurf, Abgrenzung und Testfaelle: `PFLICHTENHEFT.md`.

## Arbeitsverzeichnis

```
03_ServiceClock/
  PFLICHTENHEFT.md      Zweck, Endpunkte, Daten, Testfaelle, Persistenzentscheidung
  app.py                Anwendung, nur Standardbibliothek
  Dockerfile            eigenes Image, nicht privilegierter Benutzer
  .dockerignore
  compose.yaml          Port, Restart Policy, Healthcheck, Rechte
  README.md             diese Datei
  QWEN_PROTOKOLL.md     Entscheidungsprotokoll zum AI-Einsatz
  TESTPROTOKOLL.md      Formular fuer die Testfaelle
  scripts/abnahme.sh    fuehrt die Abnahme aus und sammelt Belege
```

Alle Befehle unten werden aus `03_ServiceClock/` ausgefuehrt.

## Voraussetzungen

- Docker mit Compose-Plugin, auf dieser VM ueber `sudo` angesprochen
- Netzzugang beim Build, weil das Image `tzdata` nachinstalliert
- `python3` auf dem Host nur fuer die Testskripte, nicht fuer die Anwendung
- Ports 8080, 3000, 8081 und 8090 bleiben unangetastet

## Ports

| Wo | Adresse | Zweck |
|---|---|---|
| Host | `127.0.0.1:8095` | Zugriff, bewusst nur lokal gebunden |
| Container | `8000` | Anwendung |

Vom Mac oder Kali aus geht der Zugriff ueber einen SSH-Tunnel, nicht ueber eine
Netzfreigabe:

```bash
ssh -N -L 127.0.0.1:8095:127.0.0.1:8095 vmadmin@<ubuntu-ip>
```

## Start

```bash
cd ~/workspace/AI-Docker-Lab/03_ServiceClock
sudo docker compose up -d --build
sudo docker compose ps
```

Etwa 10 Sekunden warten. In der Startphase meldet die Anwendung `starting` mit
HTTP 503, danach `healthy` mit HTTP 200. Der Healthcheck hat dafuer ein
`start_period` von 10 s.

Aufrufen, im Browser auf der VM: `http://127.0.0.1:8095`

## Tests

```bash
curl -fsS http://127.0.0.1:8095/health | python3 -m json.tool
curl -fsS http://127.0.0.1:8095/api/clock | python3 -m json.tool
curl -s -o /dev/null -w 'unbekannte Route: HTTP %{http_code}\n' http://127.0.0.1:8095/gibtsnicht
curl -s -o /dev/null -w 'POST: HTTP %{http_code}\n' -X POST http://127.0.0.1:8095/
sudo docker compose logs --tail 20 clock
sudo docker compose exec clock id        # muss uid=10001 zeigen, nicht root
```

Die vollstaendige Abnahme mit Belegsammlung:

```bash
chmod +x scripts/abnahme.sh
sudo ./scripts/abnahme.sh
```

Konfiguration ausprobieren, ohne Dateien zu aendern:

```bash
# Anzeigename, wird sicher in HTML ausgegeben
sudo SERVICE_NAME='<script>alert(1)</script>' docker compose up -d
curl -fsS http://127.0.0.1:8095/ | grep -o '&lt;script&gt;[^<]*'

# ungueltige Zeitzone: Prozess laeuft weiter, Health meldet degraded
sudo CLOCK_TZ=Nirgendwo/Nirgends docker compose up -d
sleep 8 && curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:8095/health
sudo docker compose ps                    # Container wird unhealthy

# zurueck auf die Vorgabe
sudo docker compose up -d
```

Nach Codeaenderungen neu bauen:

```bash
sudo docker compose up -d --build
```

## Prozessneustart, Containerneuerstellung und Health-Status

Drei verschiedene Dinge, die sich am Verhalten unterscheiden lassen:

| Vorgang | Befehl | Container-ID | `RestartCount` | Laufzeit und Zaehler |
|---|---|---|---|---|
| Prozessneustart | `docker compose restart clock` | bleibt | bleibt | zurueckgesetzt |
| unerwarteter Abbruch | `docker compose kill -s SIGKILL clock` | bleibt | **steigt** | zurueckgesetzt |
| Containerneuerstellung | `down`, dann `up -d` | **neu** | wieder 0 | zurueckgesetzt |
| Health-Status | keiner davon | unveraendert | unveraendert | Aussage der Anwendung ueber sich selbst |

Der Health-Status ist keine Folge dieser Vorgaenge, sondern eine eigene Aussage:
`starting` in der Startphase, `degraded` bei unaufloesbarer Zeitzone, sonst
`healthy`. Ein laufender Prozess ist also kein Nachweis fuer eine
funktionierende Anwendung.

`down` und `up -d` beweist keine automatische Wiederanlaufregel, weil der Start
dabei von Hand ausgeloest wird. Den Nachweis liefert erst der unerwartete
Abbruch: nach `kill -s SIGKILL` startet Docker den Container wegen
`restart: unless-stopped` selbst neu, und `RestartCount` steigt.

```bash
sudo docker inspect --format 'ID={{.Id}} RestartCount={{.RestartCount}} Policy={{.HostConfig.RestartPolicy.Name}}' \
  "$(sudo docker compose ps -q clock)"
```

## Stoppen

```bash
sudo docker compose stop            # Container bleibt bestehen
sudo docker compose down            # Container und Netz entfernen
sudo docker compose down --rmi local   # zusaetzlich das eigene Image entfernen
```

`stop` setzt die Restart Policy ausser Kraft: ein bewusst gestoppter Container
ist kein unerwarteter Absturz und wird nicht neu gestartet. Das ist der
Unterschied zwischen `unless-stopped` und `always`.

## Datenhaltung

**Kein Volume, bewusst.** Die Anwendung haelt keine Nutzdaten. Alles ist
entweder Konfiguration aus dem Environment oder ein Messwert des laufenden
Prozesses.

Bei Prozessneustart und bei Containerneuerstellung werden zurueckgesetzt:

| Wert | Verhalten |
|---|---|
| `started_at` | neu gesetzt |
| `uptime_seconds` | beginnt wieder bei 0 |
| `requests_served` | beginnt wieder bei 0 |

Unveraendert bleiben `SERVICE_NAME` und `CLOCK_TZ`, weil sie aus der
Konfiguration kommen und nicht aus dem Prozess.

Es gibt damit nichts, was eine Containerneuerstellung ueberdauern muesste. Ein
Volume wuerde keinen Nutzen bringen und zusaetzliche Schreibrechte auf dem Host
verlangen.

## Sicherheit

| Massnahme | Wo |
|---|---|
| Benutzer 10001, nicht root | `Dockerfile` und `compose.yaml` |
| `read_only: true` | `compose.yaml`, Schreiben nur in `/tmp` als tmpfs |
| `cap_drop: [ALL]` | alle Capabilities entfernt |
| `no-new-privileges:true` | keine Rechteerhoehung durch setuid |
| Bindung auf `127.0.0.1` | nicht im Netz erreichbar |
| HTML-Ausgabe escaped | `esc()` in `app.py`, betrifft `SERVICE_NAME` |
| Content-Security-Policy | `default-src 'none'`, nur eigene Stile |
| begrenzte Logs | `max-size: 2m`, `max-file: 2` |
| kein Volume | keine Schreibrechte auf Hostpfade |

Offen bleibt: Die Anwendung hat keine Authentifizierung. Wer den Port erreicht,
sieht Name, Zeit und Zaehler. Deshalb die Bindung auf Loopback.
