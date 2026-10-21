# AI-Relay: Host-Komponente fuer den Ollama-Zugriff

Auftrag 2, Phase D. Dieses Relay ist die Antwort auf die Netzwerkfrage des
Aufgabenblatts.

## Die Netzwerkfrage

Ollama lauscht auf `127.0.0.1:8080` des Ubuntu-Hosts. Im Bridge-Container ist
`127.0.0.1` der Container selbst, nicht der Host. Der Dashboard-Container
erreicht Ollama daher auf diesem Weg nie, auch nicht ueber
`host.docker.internal`: die Gateway-Adresse existiert zwar, aber dort lauscht
nichts, weil Ollama nur an Loopback gebunden ist.

Drei moegliche Antworten:

| | A: Ollama auf 0.0.0.0 | B: Host-Netzwerk fuer das Dashboard | C: Host-Relay (gewaehlt) |
|---|---|---|---|
| Eingriff | vorgegebener Dienst wird geaendert | Container verliert Netztrennung | neue kleine Host-Komponente |
| Wer erreicht Ollama | jeder im Netz | alles auf dem Host, inkl. Container | nur Container im Dashboard-Netz |
| Erreichbare API | die ganze Ollama-API | die ganze Ollama-API | ein fachlicher Endpunkt |
| Portbindung | offen | `ports:` wirkt nicht mehr | bleibt wie sie ist |
| Zulaessig laut Aufgabenblatt | nein, ausdruecklich ausgeschlossen | ja, mit Begruendung | ja, als Host-Komponente |

Gewaehlt ist C. Ollama bleibt unveraendert, das Dashboard bleibt im Bridge-Netz,
und der Container erreicht genau eine Funktion statt einer ganzen API.

## Datenfluss

```
Dashboard-Container                 |  Ubuntu-Host
                                    |
POST /v1/analyze  ----------------> |  hf_ai_relay.py        (systemd, DynamicUser)
  {model, prompt, num_predict}      |     prueft Allowlist, Limits, Auslastung
                                    |     |
   === Vertrauensgrenze =========== |     v  POST /api/chat
                                    |  Ollama auf 127.0.0.1:8080  (unveraendert)
<--- {ok, content, duration_ms} --- |
```

Das Relay lauscht auf `172.31.240.1:8899`, dem Gateway des Netzes
`hf-ops-dashboard` aus `../compose.yaml`. Damit ist es aus diesem Netz
erreichbar und vom LAN aus nicht. Wird das Subnetz dort geaendert, muss
`AIR_BIND_HOST` in `/etc/hf-ops-ai-relay/relay.env` mitgeaendert werden.

## Warum kein transparenter Proxy

Das Relay reicht die Ollama-API nicht durch, sondern bietet einen einzigen
fachlichen Endpunkt an. Der Container kann deshalb kein Modell laden, erzeugen
oder loeschen, auch wenn er es versuchte. Durchgesetzt werden:

- **Modell-Allowlist**: nur `coder-schnell` und `coder-genau`, sonst HTTP 403.
- **`stream: false`** immer, unabhaengig vom Aufrufer.
- **Laengenlimit**: `num_predict` wird auf 400 gedeckelt, `num_ctx` auf 4096.
- **Groessenlimit**: Anfragen ueber 16 KiB werden mit HTTP 413 abgelehnt.
- **Zeitlimit**: 100 s gegenueber Ollama, danach HTTP 504.
- **Eine Anfrage gleichzeitig**: die zweite bekommt HTTP 429 `relay_busy`.
- **Festes Ziel**: Host und Pfad von Ollama stehen in der Konfiguration. Der
  Aufrufer kann sie nicht beeinflussen.

Logzeilen und Modelltext werden nie als Anweisung behandelt. Das Relay
protokolliert Modell, Groesse und Dauer, aber keine Promptinhalte, damit keine
Labordaten im Journal landen.

## Rechte

Anders als der Collector braucht das Relay **keine** Hostrechte: keinen
Docker-Zugriff, keine Dateien, keinen eigenen Systembenutzer. Die Unit laeuft
mit `DynamicUser=yes` unter einem Wegwerfbenutzer, `ProtectSystem=strict`,
`ProtectHome=true` und `RestrictAddressFamilies=AF_INET AF_INET6`. Unix-Sockets
sind damit auch technisch ausser Reichweite, der Docker-Socket also ebenfalls.

Die beiden Host-Komponenten sind bewusst getrennt: Monitoring liest Docker und
darf nichts ins Netz, das Relay spricht ins Netz und darf Docker nicht sehen.

## Dateien

```
ai-relay/
  hf_ai_relay.py                      Relay (nur Standardbibliothek)
  relay.env.example                   Konfiguration, Ziel: /etc/hf-ops-ai-relay/relay.env
  systemd/hf-ops-ai-relay.service     Dienst, DynamicUser, gehaertet
  scripts/install-relay.sh            installiert, startet und prueft
  scripts/check-relay.sh              Zustand pruefen, --probe fuer echte Anfrage
  scripts/faultcase-ai.sh             Fehlerfall "AI nicht erreichbar" mit Protokoll
```

## Installation

```bash
cd ~/workspace/sa-ii/02_Monitoring/ai-relay
chmod +x scripts/*.sh
sudo ./scripts/install-relay.sh
./scripts/check-relay.sh
./scripts/check-relay.sh --probe      # echte Modellanfrage, dauert einige Sekunden
```

Das Relay lauscht auf der Gateway-Adresse des Dashboard-Netzes. Existiert das
Netz noch nicht, ist diese Adresse am Host noch nicht vorhanden. Der Dienst
bindet trotzdem (`IP_FREEBIND`) und ist erreichbar, sobald das Dashboard einmal
gestartet wurde. Die Startreihenfolge ist dadurch egal.

## Endpunkte

| Route | Inhalt |
|---|---|
| `GET /health` | Relay-Zustand, Erreichbarkeit von Ollama, vorhandene Modelle |
| `GET /v1/models` | Namen der vorhandenen und der erlaubten Modelle |
| `POST /v1/analyze` | `{"model","prompt","num_predict"}` nach `{"ok","content",...}` |
| sonst | HTTP 404 mit JSON |

Fehlercodes: `bad_request` 400, `model_not_allowed` 403, `oversized` 413,
`relay_busy` 429, `ollama_unreachable` / `ollama_http_error` / `model_missing`
502, `ollama_timeout` 504.

`GET /health` liefert bewusst immer HTTP 200. Ollama nicht erreichbar heisst
`ollama_reachable: false`, nicht unhealthy: das Relay selbst funktioniert und
meldet korrekt.

## Fehlerfaelle

| Fall | Erwartung | Nachweis |
|---|---|---|
| Ollama gestoppt | `ollama_reachable: false`, Dashboard zeigt AI unavailable | `./scripts/check-relay.sh`, Exit-Code 1 |
| Modell fehlt | klare Meldung mit vorhandenen Modellen | `AIR_DEFAULT_MODEL` auf einen falschen Namen setzen |
| Fremdes Modell angefragt | HTTP 403, Anfrage erreicht Ollama nicht | in `check-relay.sh` enthalten |
| Zwei Analysen gleichzeitig | zweite bekommt HTTP 429 | zwei Klicks kurz nacheinander |
| Relay nicht erreichbar | Dashboard meldet AI unavailable, Monitoring laeuft weiter | `sudo ./scripts/faultcase-ai.sh` |

Der Fehlerfall aus Phase E, Versuch 2 laeuft als Ganzes so:

```bash
sudo ./scripts/faultcase-ai.sh
```

Das Skript biegt nur die Zieladresse des Dashboards auf einen unbenutzten Port
um, belegt mit Zeitstempeln, dass die AI eindeutig als unavailable gilt und
Monitoring und Dashboard-Health unveraendert nutzbar bleiben, und stellt danach
wieder her. Ollama und das Relay werden dabei nicht angefasst.

## Grenzen

- Das Relay authentifiziert nicht. Es verlaesst sich darauf, dass nur Container
  im Netz `hf-ops-dashboard` seine Adresse erreichen. Laeuft dort ein weiterer
  Container, erreicht auch dieser das Relay. Im Labor ist das vertretbar, in
  einer echten Umgebung gehoerte ein Token davor.
- Es gibt keine Warteschlange. Die zweite gleichzeitige Anfrage wird abgelehnt,
  nicht aufgehoben.
- Das Relay prueft Modellantworten nicht inhaltlich. Es begrenzt Form, Laenge
  und Dauer; die fachliche Bewertung bleibt Aufgabe des Menschen.
