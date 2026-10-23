# Belege Auftrag 2

Erzeugt mit `02_Monitoring/scripts/belege.sh`. Jede Datei traegt im Kopf
den Zeitpunkt, den ausgefuehrten Befehl und den Exit-Code.

Stand: 2026-10-23T09:38:07Z

| Ordner | Erfasst am | Dateien |
|---|---|---|
| `00_rahmen` | 2026-10-22T15:52:46Z | 5 |
| `01_phaseA_statische_analyse` | 2026-10-22T15:53:16Z | 4 |
| `02_phaseB_erster_start` | 2026-10-22T15:53:23Z | 9 |
| `03_phaseC_eigenes_monitoring` | 2026-10-22T15:53:31Z | 7 |
| `04_phaseD_ai` | 2026-10-22T15:54:51Z | 6 |
| `05_test1_unveraenderte_umgebung` | 2026-10-22T15:57:49Z | 5 |
| `06_test2_ai_nicht_erreichbar` | 2026-10-22T17:46:14Z | 4 |
| `07_test3_erfassung_gestoert` | 2026-10-22T15:59:09Z | 4 |
| `08_test4_worker_repariert` | 2026-10-22T17:17:39Z | 13 |
| `09_test5_container_fehlt` | 2026-10-22T16:03:24Z | 9 |
| `10_phaseF_security` | 2026-10-22T17:46:48Z | 10 |
| `11_reproduzierbarer_start` | 2026-10-22T17:46:49Z | 14 |
| `12_freigabe_nginx` | 2026-10-23T09:37:00Z | 9 |

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

### 06_test2_ai_nicht_erreichbar

- `ablauf.log` Fehlerfall-Protokoll: AI nicht erreichbar
- `ai_status_nachher.json` AI-Status nach der Wiederherstellung
- `nachweis_ai_ausfall_20261022T173610Z.log` Fehlerfall-Protokoll: AI nicht erreichbar
- `nachweis_ai_ausfall_20261022T174614Z.log` Fehlerfall-Protokoll: AI nicht erreichbar

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
- `zeitpunkt_nach_eingriff.txt` 2026-10-22T17:17:39Z
- `zeitpunkt_vor_eingriff.txt` 2026-10-22T17:15:39Z
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

### 10_phaseF_security

- `f1_docker_zugriff.log` Wer kann den Docker-Daemon ansprechen
- `f2_socket_akzeptiert_schreibend.log` Die Docker-API kennt kein Leserecht: POST wird angenommen (Anfrage bew
- `f3_lesend_verraet_daten.log` Auch lesende Routen geben Environment im Klartext heraus
- `f4_dashboard_ohne_socket.log` Der Dashboard-Container hat keinen Zugang zur Docker-API
- `f5_haertung_collector.log` Was der Collector darf und was nicht
- `f5_haertung_relay.log` Was das AI-Relay darf und was nicht
- `f6_hostnetz_waere_erreichbar.log` Was ein Container mit Host-Netzwerk zusaetzlich erreichen wuerde
- `f7_bindungen.log` Wohin die eigenen Dienste gebunden sind
- `f8_keine_geheimnisse_in_logs.log` Das Relay protokolliert Groesse und Dauer, keine Promptinhalte
- `f9_modelltext_wird_escaped.log` Modelltext wird als Text ausgegeben, nicht als HTML ausgefuehrt

### 11_reproduzierbarer_start

- `abbau.log` Dashboard abbauen, Container und Netz entfernen
- `ai_analyse_nachher.json` Und eine Analyse laeuft wieder durch
- `ai_nachher.json` AI ist nach dem Neustart wieder erreichbar
- `aufbau.log` Dashboard aus dem Quellstand neu bauen und starten
- `check_snapshot_nachher.log` Daten sind nach dem Neustart wieder frisch
- `dashboard_health_nachher.json` Dashboard antwortet wieder
- `hostdienste_neustart.log` Collector und Relay neu starten
- `luecke.log` Beweis, dass waehrend des Abbaus nichts antwortet
- `ps_nachher.log` Containerzustand nach dem Neustart
- `zeitpunkt_fertig.txt` 2026-10-22T17:48:51Z
- `zeitpunkt_start.txt` 2026-10-22T17:46:49Z
- `zusammenfassung.log` Reproduzierbarer Start
- `zustand_nachher.json` Zustand nach dem Neustart
- `zustand_vorher.json` Zustand vor dem Neustart

### 12_freigabe_nginx

- `00_eingabe.log` Verwendete Angaben
- `01_skript_lauf.log` Einrichtung mit expose-lab.sh, Ausgabe vollstaendig
- `02_konfiguration.conf` Erzeugte Nginx-Konfiguration
- `03_nginx_aktiv.log` Konfiguration ist syntaktisch gueltig und wirklich aktiv
- `04_listener.log` Wer lauscht wo: Nginx im LAN, die Anwendungen nur lokal
- `05_test_ubuntu.log` Zugriff vom Ubuntu, erst lokal, dann ueber die LAN-Adresse
- `06_zugriffslog.log` Nginx-Zugriffsprotokoll zu den freigegebenen Ports
- `07_portkette.log` Portkette und Begruendung
- `08_offene_punkte.log` Was von Hand dazugehoert

