# Mini-Pflichtenheft: Service Clock

Auftrag 3, erstellt vor der Implementierung.

Erstellt am:

## 1. Zweck

Eine kleine, zustandslose Webanwendung, die ihren eigenen Betriebszustand
sichtbar macht: konfigurierter Name, Status, aktuelle Zeit in einer
konfigurierten Zeitzone, Laufzeit seit Prozessstart und Anzahl bedienter
Anfragen. Sie dient als nachweisbar laufende eigene Anwendung mit
Healthcheck, Restart Policy und reproduzierbarem Start.

Bewusst klein gehalten. Der Nachweis zaehlt, nicht der Funktionsumfang.

## 2. Endpunkte

| Methode | Pfad | Antwort | HTTP-Status |
|---|---|---|---|
| GET | `/` | HTML: Name, Status, dynamische Information | 200, oder 503 bei degradiert |
| GET | `/health` | JSON: Status, Begruendung, Laufzeit | 200 gesund, 503 startend oder degradiert |
| GET | `/api/info` | JSON: `application`, `status`, `time`, `uptime_seconds` | 200, oder 503 |
| GET | `/api/clock` | identische Antwort unter den eigenen Feldnamen | 200, oder 503 |
| GET | alles andere | JSON mit Fehler und gueltigen Routen | 404 |
| andere Methoden | beliebig | JSON mit Fehler | 405 |

Die Seite `/` aktualisiert sich selbst, damit die dynamische Information ohne
Zutun sichtbar weiterlaeuft.

## 3. Daten

Alles nur im Arbeitsspeicher, nichts auf Platte:

| Feld | Herkunft | Verhalten |
|---|---|---|
| `service_name` | Environment `APP_NAME` oder `SERVICE_NAME` | fest ueber die Laufzeit |
| `timezone` | Environment `CLOCK_TZ` | fest ueber die Laufzeit |
| `now` | Systemuhr, in `CLOCK_TZ` umgerechnet | aendert sich sekuendlich |
| `started_at` | Zeitpunkt des Prozessstarts | wird bei jedem Prozessstart neu gesetzt |
| `uptime_seconds` | jetzt minus `started_at` | waechst |
| `requests_served` | Zaehler im Arbeitsspeicher | waechst, wird bei Prozessstart auf 0 gesetzt |

### Persistenzentscheidung

**Kein Volume.** Begruendung: Die Anwendung haelt keine Nutzdaten. Alle Werte
sind entweder Konfiguration, die aus dem Environment kommt, oder Messwerte des
laufenden Prozesses. Ein Volume wuerde nichts aufbewahren, was einen Neustart
ueberdauern muesste, und zusaetzliche Rechte auf dem Host verlangen.

Bei Containerneuerstellung **und** bei einem Prozessneustart werden
zurueckgesetzt: `started_at`, `uptime_seconds`, `requests_served`. Das ist
gewollt, weil diese Werte den aktuellen Prozess beschreiben und nicht die
Anwendung. Unveraendert bleiben `service_name` und `timezone`, weil sie aus der
Konfiguration kommen.

`/api/info` fuehrt die Feldnamen aus dem Arbeitsblatt (`application`, `status`,
`time`, `uptime_seconds`), damit ein Aufrufer sich auf diesen Vertrag stuetzen
kann. `/api/clock` liefert dieselbe Antwort und bleibt erhalten.

## 4. Konfiguration

| Variable | Vorgabe | Wirkung |
|---|---|---|
| `APP_NAME` | `HF Service Clock` | Anzeigename, wird sicher in HTML ausgegeben |
| `SERVICE_NAME` | leer | ueberschreibt `APP_NAME`, falls gesetzt |
| `CLOCK_TZ` | `Europe/Zurich` | Zeitzone der Anzeige |
| `PORT` | `8000` | Port im Container |
| `WARMUP_SECONDS` | `5` | Startphase, in der `/health` `starting` meldet |
| `REFRESH_SECONDS` | `2` | Aktualisierungsintervall der Seite |

Eine unbekannte Zeitzone fuehrt nicht zum Absturz. Die Anwendung laeuft weiter,
faellt auf UTC zurueck und meldet sich ueber `/health` als `degraded` mit
Begruendung. So bleibt der Prozesszustand vom Health-Status unterscheidbar.

## 5. Zustaende und HTTP-Status

| Zustand | Bedingung | `/health` |
|---|---|---|
| `starting` | weniger als `WARMUP_SECONDS` seit Prozessstart | 503 |
| `degraded` | konfigurierte Zeitzone nicht aufloesbar | 503 |
| `healthy` | Startphase vorbei und Zeitzone gueltig | 200 |

## 6. Testfaelle

| # | Test | Erwartetes Verhalten |
|---|---|---|
| T1 | `GET /` kurz nach dem Start | HTML mit Name und Status, Status `starting` |
| T2 | `GET /` nach der Startphase | Status `healthy`, Zeit und Laufzeit sichtbar |
| T3 | `GET /` zweimal im Abstand von 3 s | Zeit, Laufzeit und Anfragezaehler haben sich geaendert |
| T4 | `GET /health` nach der Startphase | JSON, `status: healthy`, HTTP 200 |
| T5 | `GET /health` in der Startphase | JSON, `status: starting`, HTTP 503 |
| T6 | `GET /gibtsnicht` | JSON mit Fehler und gueltigen Routen, HTTP 404 |
| T7 | `POST /` | JSON mit Fehler, HTTP 405 |
| T8 | `SERVICE_NAME` mit HTML-Sonderzeichen | wird als Text angezeigt, nicht als Markup ausgefuehrt |
| T9 | `CLOCK_TZ` auf einen ungueltigen Wert | Prozess laeuft, `/health` meldet `degraded` mit HTTP 503 |
| T10 | Benutzer im Container pruefen | UID 10001, nicht root |
| T11 | `docker compose restart` | Prozess neu, gleiche Container-ID, Zaehler zurueckgesetzt |
| T12 | `docker compose down` und `up -d` | neue Container-ID, Anwendung wieder erreichbar |
| T13 | unerwarteter Prozessabbruch (`kill -SIGKILL`) | Restart Policy startet neu, `RestartCount` erhoeht sich |
| T14 | Codeaenderung, dann `up -d --build` | neues Image, Aenderung sichtbar |

## 7. Abgrenzung

Nicht Teil dieser Anwendung: Benutzerverwaltung, Datenhaltung, Zugriffsschutz,
AI-Anbindung. Ein Qwen-Aufruf im laufenden Produkt ist laut Aufgabenblatt fuer
Auftrag 3 nicht erforderlich; Qwen wird als Engineering-Assistent eingesetzt und
im Entscheidungsprotokoll dokumentiert.

## 8. Offene Punkte zum Zeitpunkt der Planung

- Ob die Startphase von 5 s zum Healthcheck-Intervall passt, zeigt erst der
  Lauf. Gegebenenfalls `start_period` anpassen.
- Ob `python:3.12-slim` Zeitzonendaten mitbringt, ist zu pruefen. Falls nicht,
  muss `tzdata` im Image nachinstalliert werden.
