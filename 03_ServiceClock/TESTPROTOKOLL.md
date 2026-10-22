# Testprotokoll Service Clock

Auftrag 3. Testfaelle aus `PFLICHTENHEFT.md`, Abschnitt 6. Waehrend der
Durchfuehrung ausfuellen, nicht danach aus dem Gedaechtnis.

Die Spalte Beleg nennt die Datei unter `belege/` oder den Befehl mit seiner
Ausgabe. Das meiste erzeugt `sudo ./scripts/abnahme.sh` in einem Durchgang.

## Rahmen

| Feld | Wert |
|---|---|
| Datum der Durchfuehrung | |
| Host, Docker, Compose | |
| Image-ID (`docker images service-clock`) | |
| Repo-Stand (`git rev-parse --short HEAD`) | |

## Testfaelle

| # | Test | Erwartetes Verhalten | Tatsaechliches Verhalten | Beleg | Datum |
|---|---|---|---|---|---|
| T1 | `GET /` kurz nach dem Start | HTML mit Name und Status, Status `starting` | | | |
| T2 | `GET /` nach der Startphase | Status `healthy`, Zeit und Laufzeit sichtbar | | | |
| T3 | `GET /` zweimal im Abstand von 3 s | Zeit, Laufzeit und Zaehler haben sich geaendert, `started_at` nicht | | | |
| T4 | `GET /health` nach der Startphase | JSON, `status: healthy`, HTTP 200 | | | |
| T5 | `GET /health` in der Startphase | JSON, `status: starting`, HTTP 503 | | | |
| T6 | `GET /gibtsnicht` | JSON mit Fehler und gueltigen Routen, HTTP 404 | | | |
| T7 | `POST /` | JSON mit Fehler, HTTP 405, Kopfzeile `Allow: GET` | | | |
| T8 | `SERVICE_NAME` mit HTML-Sonderzeichen | wird als Text angezeigt, nicht ausgefuehrt | | | |
| T9 | `CLOCK_TZ` ungueltig | Prozess laeuft, `/health` meldet `degraded`, HTTP 503, Container wird unhealthy | | | |
| T10 | Benutzer im Container | `uid=10001`, nicht root; Rootfs read-only, `/tmp` beschreibbar | | | |
| T11 | `docker compose restart clock` | gleiche Container-ID, `RestartCount` unveraendert, Zaehler zurueckgesetzt | | | |
| T12 | `docker compose down` und `up -d` | neue Container-ID, `RestartCount` wieder 0, Anwendung erreichbar | | | |
| T13 | `docker compose kill -s SIGKILL clock` | Restart Policy startet selbst neu, `RestartCount` steigt um 1 | | | |
| T14 | Codeaenderung, dann `up -d --build` | neue Image-ID, Aenderung sichtbar | | | |

## Prozessneustart, Containerneuerstellung, Health-Status

Die drei sauber auseinandergehalten, mit den gemessenen Werten:

| Vorgang | Container-ID vorher | Container-ID nachher | `RestartCount` vorher | nachher | Laufzeit nachher |
|---|---|---|---|---|---|
| `restart` | | | | | |
| `kill -s SIGKILL` | | | | | |
| `down` und `up -d` | | | | | |

**Eigene Formulierung des Unterschieds:**



**Warum `down` und `up -d` allein keine automatische Wiederanlaufregel beweist:**



## Datenhaltung

Die Anwendung ist zustandslos und hat kein Volume. Welche fluechtigen Werte
nach einer Containerneuerstellung zurueckgesetzt waren:

| Wert | vorher | nachher |
|---|---|---|
| `started_at` | | |
| `uptime_seconds` | | |
| `requests_served` | | |
| `service` (aus der Konfiguration) | | |
| `timezone` (aus der Konfiguration) | | |

**Begruendung, warum kein Volume noetig ist:**



## Offene Einschraenkungen

Ehrlich benennen, was nicht geprueft wurde oder nicht funktioniert:

- Keine Authentifizierung. Wer den Port erreicht, sieht Name, Zeit und Zaehler.
  Deshalb Bindung auf `127.0.0.1`.
- Der Anfragezaehler zaehlt alle Anfragen, auch die des Healthchecks. Das ist
  gewollt, macht die Zahl aber nicht zu einer Besucherstatistik.
-
-

## Gesamtbeurteilung

- **Was ist belegt:**
- **Was bleibt Vermutung:**
- **Was wuerde ich beim naechsten Mal anders machen:**
