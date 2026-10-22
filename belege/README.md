# Belege Auftrag 2

Erzeugt mit `02_Monitoring/scripts/belege.sh`. Jede Datei traegt im Kopf
den Zeitpunkt, den ausgefuehrten Befehl und den Exit-Code.

Stand: 2026-10-22T16:05:03Z

| Ordner | Erfasst am | Dateien |
|---|---|---|
| `00_rahmen` | 2026-10-22T15:52:46Z | 5 |
| `01_phaseA_statische_analyse` | 2026-10-22T15:53:16Z | 4 |
| `02_phaseB_erster_start` | 2026-10-22T15:53:23Z | 9 |
| `03_phaseC_eigenes_monitoring` | 2026-10-22T15:53:31Z | 7 |
| `04_phaseD_ai` | 2026-10-22T15:54:51Z | 6 |
| `05_test1_unveraenderte_umgebung` | 2026-10-22T15:57:49Z | 5 |
| `07_test3_erfassung_gestoert` | 2026-10-22T15:59:09Z | 4 |
| `08_test4_worker_repariert` | 2026-10-22T16:01:34Z | 13 |
| `09_test5_container_fehlt` | 2026-10-22T16:03:24Z | 9 |

## Dateien im Einzelnen

### 00_rahmen

- `dienste.log` Zustand der eigenen Host-Dienste
- `git_stand.log` Stand des Quellordners
- `ollama_modelle.log` Vorhandene Ollama-Modelle
- `ports.log` Belegte lokale Ports
- `umgebung.log` Host und Werkzeuge

### 01_phaseA_statische_analyse

- `Auftrag2_PhaseA_Statische_Analyse.md` Auftrag 2, Phase A: Statische Analyse der Startumgebung
- `git_historie.log` Git-Historie der Analysedatei, falls vorhanden
- `Statische_Analyse.md` Auftrag 2, Phase A: Statische Analyse
- `zeitnachweis.log` Zeitstempel der Analyse gegen Zeitstempel der Laborquellen

### 02_phaseB_erster_start

- `compose_config.log` Aufgeloeste Konfiguration der Laborumgebung
- `curl_web_health.log` Health der Laborumgebung ueber den veroeffentlichten Port
- `health_api.json` Healthcheck-Ausgabe api
- `health_web.json` Healthcheck-Ausgabe web
- `health_worker.json` Healthcheck-Ausgabe worker
- `logs_api.log` API-Logs
- `logs_web.log` Web-Logs
- `logs_worker_vor_reparatur.log` Worker-Logs VOR jeder Reparatur, mit Zeitstempel
- `ps.log` Containerzustand

### 03_phaseC_eigenes_monitoring

- `api_state.json` Aufbereiteter Zustand des Dashboards
- `check_snapshot.log` Gegenprobe auf der Kommandozeile
- `dashboard_health.json` Eigener Health des Dashboards
- `kein_docker_socket.log` Nachweis: der Dashboard-Container hat keinen Docker-Socket
- `snapshot_roh.json` Rohdaten des Collectors
- `unbekannte_route.log` Unbekannte Route liefert einen Fehlerstatus
- `zustand_kurz.log` Lesbare Kurzfassung des Zustands

### 04_phaseD_ai

- `ai_analyse.json` Echte Modellanfrage aus dem Programm
- `ai_analyse_lesbar.log` Die vier geforderten Elemente
- `ai_status.json` AI-Erreichbarkeit laut Dashboard
- `allowlist_gegenprobe.log` Nicht freigegebenes Modell wird abgelehnt
- `netzgrenze.log` Nachweis: Relay nur aus dem Dashboard-Netz erreichbar
- `relay_health.json` Zustand des AI-Relays

### 05_test1_unveraenderte_umgebung

- `ai_analyse.json` AI-Analyse auf diesen Daten
- `api_state.json` Zustand laut Dashboard
- `check_snapshot.log` Eigene Erfassung
- `dashboard_health.json` Dashboard-Health
- `ps.log` Containerzustand

### 07_test3_erfassung_gestoert

- `ablauf.log` Fehlerfall-Protokoll: Datenerfassung gestoert
- `analyse_auf_alten_daten.json` Analyse waehrend der Stoerung wurde abgelehnt
- `check_snapshot_nachher.log` Zustand nach der Wiederherstellung
- `nachweis_collector_ausfall_20261022T155909Z.log` Fehlerfall-Protokoll: Datenerfassung gestoert

### 08_test4_worker_repariert

- `ai_analyse_nachher.json` Neue AI-Analyse als Beleg der Wirkung
- `health_nachher.json` Healthcheck-Ausgabe nach dem Eingriff
- `logs_nachher.log` Neue Logzeilen
- `logs_vorher.log` Worker-Logs vor dem Eingriff
- `ps_nachher.log` Containerzustand nach dem Eingriff
- `vergleich_route_konfiguration.log` Route im Code gegen Wert in der Konfiguration
- `wirksamer_wert.json` Tatsaechlich wirksamer Wert im laufenden Container
- `wirksamer_wert_nachher.json` Wirksamer Wert nach der Containerneuerstellung
- `zeitachse.log` Zeitachse
- `zeitpunkt_nach_eingriff.txt` 2026-10-22T16:01:34Z
- `zeitpunkt_vor_eingriff.txt` 2026-10-22T16:00:52Z
- `zustand_nachher.json` Zustand nach dem Eingriff
- `zustand_vorher.json` Zustand vor dem Eingriff

### 09_test5_container_fehlt

- `check_snapshot_fehlend.log` Erfassung bei fehlendem Container
- `check_snapshot_gestoppt.log` Erfassung bei gestopptem Container
- `check_snapshot_nachher.log` Zustand nach der Wiederherstellung
- `dashboard_health_fehlend.json` Dashboard bleibt gesund
- `eingriff.log`  Container hf-ops-lab-worker-1  Stopping
- `wiederherstellung.log`  Container hf-ops-lab-api-1  Running
- `zeitpunkt_eingriff.txt` 2026-10-22T16:03:24Z
- `zustand_fehlend.json` Anzeige bei fehlendem Container
- `zustand_gestoppt.json` Anzeige bei gestopptem Container

