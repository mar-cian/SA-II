# SA II: AI Operations Dashboard und AI Docker Builder

HF Informatik, Modul SAII, Local AI Engineering. Ueberwachung der vorgegebenen
Docker-Laborumgebung mit programmatischer AI-Analyse.

## Inhalt

| Ordner | Inhalt |
|---|---|
| `01_Startumgebung/` | vorgegebene Laborumgebung, **unveraendert** |
| `02_Monitoring/collector/` | Host-Collector, liest Docker nur lesend, schreibt `snapshot.json` |
| `02_Monitoring/dashboard/` | containerisierte Weboberflaeche mit eigenem `/health` und AI-Analyse |
| `02_Monitoring/ai-relay/` | Host-Komponente fuer den Zugang zum lokal gebundenen Ollama |
| `03_ServiceClock/` | Auftrag 3: eigene zustandslose Anwendung mit Qwen als Assistent |

Dokumentation:

| Datei | Inhalt |
|---|---|
| `02_Monitoring/DEPLOY.md` | Deployment in sauberer Reihenfolge, mit Pruefpunkten |
| `02_Monitoring/README.md` | Aufbau, Endpunkte, Zugriff, Datenhaltung, Phase D |
| `02_Monitoring/collector/README.md` | Docker-Zugriff: Variantenvergleich und Vertrauensgrenzen |
| `02_Monitoring/ai-relay/README.md` | Netzwerkfrage und Begruendung der gewaehlten Variante |
| `Funktionsweise_Monitoring.md` | Kurzuebersicht ueber das Zusammenspiel |
| `03_ServiceClock/PFLICHTENHEFT.md` | Auftrag 3: Zweck, Endpunkte, Daten, Testfaelle |
| `03_ServiceClock/QWEN_PROTOKOLL.md` | Auftrag 3: Entscheidungsprotokoll zum AI-Einsatz |
| `Auftrag2_PhaseA_Statische_Analyse.md` | statische Analyse vor dem ersten Start |

## Ports

| Komponente | Adresse auf Ubuntu | Aufgabe |
|---|---|---|
| Ollama | `127.0.0.1:8080` | lokale KI-API, bleibt ohne LAN-Freigabe |
| Open WebUI | `127.0.0.1:3000` | Oberflaeche zu Ollama, vorgegeben |
| Web | `127.0.0.1:8081` | Oberflaeche der Startumgebung |
| Dashboard | `127.0.0.1:8082` | Status und KI-Diagnose, Auftrag 2 |
| Service Clock | `127.0.0.1:8083` | eigene Anwendung, Auftrag 3 |
| AI-Relay | `172.31.240.1:8899` | nur aus dem Dashboard-Netz, nicht vom Host-Loopback |

Alles bewusst auf Loopback gebunden. Zugriff von einem anderen Rechner laeuft
ueber einen SSH-Tunnel, nicht ueber eine Netzfreigabe:

```bash
ssh -N -L 127.0.0.1:8082:127.0.0.1:8082 \
       -L 127.0.0.1:8083:127.0.0.1:8083 vmadmin@<ubuntu-ip>
```

Das AI-Relay steht bewusst nicht in dieser Liste: es lauscht auf dem Gateway des
Dashboard-Netzes und ist damit nur aus diesem Netz erreichbar, nicht vom Host
und nicht aus dem LAN.

## Architektur

```
Docker-Daemon --> collector (Host, root) --> snapshot.json --[ro]--> |
                                                                     | dashboard
Ollama 127.0.0.1:8080 <-- ai-relay (Host, ohne Rechte) <------------- | (Container)
                                                                     |
                        ======== Vertrauensgrenze =================  |
```

Der Dashboard-Container hat keinen Docker-Socket, kein Host-Netzwerk und keine
Hostrechte. Er liest eine Datei und ruft einen Endpunkt. Beide Zugriffswege sind
bewusst getrennt: der Collector darf Docker lesen und nicht ins Netz, das Relay
darf ins Netz und sieht Docker nicht.

## Schnellstart

Vollstaendig mit Pruefpunkten in `02_Monitoring/DEPLOY.md`. Kurzfassung auf der
Ubuntu-VM:

```bash
cd 01_Startumgebung && sudo docker compose up -d --build && sleep 25
cd ../02_Monitoring/collector && sudo ./scripts/install-collector.sh
cd .. && sudo docker compose up -d --build
cd ai-relay && sudo ./scripts/install-relay.sh && ./scripts/check-relay.sh --probe
```

Dashboard danach im Browser **auf der VM**: `http://127.0.0.1:8082`

## Verbindliche Regeln der Loesung

1. Ohne Healthcheck nie `healthy`. Ein laufender Prozess beweist keine
   funktionierende Anwendung.
2. Daten aelter als die Grenze: alle Services `nicht ermittelbar`, der letzte
   Wert bleibt nur als Zusatzinformation sichtbar.
3. Keine Daten sind nicht `alles gesund`, sondern `fehlend` oder
   `nicht ermittelbar` mit Ursache.
4. Der eigene `/health` des Dashboards haengt weder am beobachteten Worker noch
   an der AI. Sonst faellt die Ueberwachung beim ersten Vorfall selbst aus.
5. Modelltext ist ein Vorschlag, kein Messwert. Er wird nie als HTML
   ausgefuehrt und ueberschreibt keine erfassten Werte.
6. Eine AI-Analyse laeuft nur auf frischen Daten.

## Nachweise

```bash
02_Monitoring/collector/scripts/check-snapshot.sh        # Gegenprobe zur Anzeige
02_Monitoring/ai-relay/scripts/check-relay.sh --probe    # echte Modellanfrage
sudo 02_Monitoring/collector/scripts/faultcase-collector.sh   # Erfassung gestoert
sudo 02_Monitoring/ai-relay/scripts/faultcase-ai.sh           # AI nicht erreichbar
```

Die beiden Fehlerfall-Skripte schreiben ein Protokoll mit Zeitstempeln: Soll,
Eingriff, Beobachtung, Beleg, Wiederherstellung.

## Hinweise

- `01_Startumgebung/` ist Vorgabe und bleibt unveraendert. Der bewusst eingebaute
  Worker-Fehler wird nicht repariert, sondern belegt.
- Keine Secrets, Modellgewichte oder Build-Caches im Repo, siehe `.gitignore`.
- Ports 8080 (Ollama) und 3000 (Open WebUI) bleiben unangetastet, 8081 gehoert
  der Laborumgebung. Das Dashboard verwendet 8082.
