#!/usr/bin/env bash
# belege.sh - sammelt die Nachweise fuer Auftrag 2 in einen Ordner "belege/"
#
# Jeder Unterbefehl schreibt in einen eigenen Unterordner und haelt fest, mit
# welchem Befehl und zu welchem Zeitpunkt der Beleg entstanden ist. Fehler
# werden mitprotokolliert statt verschluckt: ein fehlgeschlagener Befehl ist
# ebenfalls ein Beleg.
#
# Aufruf:   ./scripts/belege.sh <unterbefehl>
#           ./scripts/belege.sh hilfe
#
# Nicht eingreifend:  rahmen, phase-a, phase-b, phase-c, phase-d, test1
# Mit Eingriff:       test2, test3, test4, test5   (stellen selbst wieder her)
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MON="$(cd "${SELF}/.." && pwd)"
ROOT="$(cd "${MON}/.." && pwd)"
LAB="${ROOT}/01_Startumgebung"
BELEGE="${ROOT}/belege"
DASHBOARD="${DASHBOARD_URL:-http://127.0.0.1:8090}"

# Adressen aus den installierten Konfigurationen uebernehmen, sonst Vorgabe.
SNAPSHOT="${HFC_OUT_DIR:-/var/lib/hf-ops-collector/state}/${HFC_OUT_FILE:-snapshot.json}"
if [ -r /etc/hf-ops-collector/collector.env ]; then
  SNAPSHOT="$( . /etc/hf-ops-collector/collector.env 2>/dev/null
               echo "${HFC_OUT_DIR:-/var/lib/hf-ops-collector/state}/${HFC_OUT_FILE:-snapshot.json}" )"
fi
RELAY="http://172.31.240.1:8899"
if [ -r /etc/hf-ops-ai-relay/relay.env ]; then
  RELAY="$( . /etc/hf-ops-ai-relay/relay.env 2>/dev/null
            echo "http://${AIR_BIND_HOST:-172.31.240.1}:${AIR_BIND_PORT:-8899}" )"
fi

ts()    { date -u +%Y-%m-%dT%H:%M:%SZ; }
stamp() { date -u +%Y%m%dT%H%M%SZ; }
say()   { printf '\n== %s\n' "$*"; }
note()  { printf '   %s\n' "$*"; }

DIR=""
setdir() {
  DIR="${BELEGE}/$1"
  mkdir -p "${DIR}"
  printf '%s\n' "$(ts)" > "${DIR}/.erfasst_am"
}

# cap <dateiname> <beschreibung> -- <befehl ...>
# Schreibt Kopfzeile, Befehl, Ausgabe und Exit-Code in die Datei.
cap() {
  local file="$1" desc="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  local target="${DIR}/${file}"
  {
    printf '# %s\n' "${desc}"
    printf '# Zeitpunkt (UTC): %s\n' "$(ts)"
    printf '# Befehl: %s\n' "$*"
    printf '# ---\n'
  } > "${target}"
  "$@" >> "${target}" 2>&1
  local rc=$?
  printf '# ---\n# Exit-Code: %s\n' "${rc}" >> "${target}"
  if [ "${rc}" -eq 0 ]; then note "ok    ${file}"; else note "rc=${rc} ${file}"; fi
  return 0
}

# Lesbare Kurzfassung des Dashboard-Zustands
zustand_kurz() {
  curl -fsS --max-time 10 "${DASHBOARD}/api/state" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("datenlage:", d.get("data_status"), "| alter:", d.get("age_seconds"), "s",
      "| messzeitpunkt:", d.get("measured_at"))
for s in d.get("services", []):
    h = s.get("health") or {}
    print("  %-8s status=%-10s prozess=%-9s health=%-9s %s" % (
        s.get("service", "?"), s.get("status", "?"), s.get("process_state") or "-",
        h.get("state") or "-", (s.get("status_reason") or "")[:60]))
'
}

# Die vier geforderten Elemente der letzten Analyse
analyse_lesbar() {
  curl -fsS --max-time 10 "${DASHBOARD}/api/ai" | python3 -c '
import json, sys
d = json.load(sys.stdin)
a = d.get("last_analysis") or {}
if not a:
    print("noch keine Analyse vorhanden")
    raise SystemExit(1)
print("modell:", a.get("model"), "| dauer:", a.get("duration_ms"), "ms")
print("grundlage:", a.get("based_on"))
print("prompt:", a.get("prompt_chars"), "Zeichen")
print("am laengenlimit abgeschnitten:", a.get("truncated"))
for key, value in (a.get("sections") or {}).items():
    print("--- %s ---" % key)
    print(value)
if not a.get("sections"):
    print("--- unstrukturierter Modelltext ---")
    print(a.get("raw"))
'
}

holen() { curl -fsS --max-time 10 "$@"; }
lab()   { ( cd "${LAB}" && sudo docker compose "$@" ); }

pruefe_umgebung() {
  [ -d "${LAB}" ] || { echo "FEHLER: ${LAB} fehlt. Liegt das Repo unter ${ROOT}?" >&2; exit 1; }
  mkdir -p "${BELEGE}"
}

# ---------------------------------------------------------------------------

cmd_rahmen() {
  setdir "00_rahmen"
  say "Rahmenangaben"
  cap umgebung.log "Host und Werkzeuge" -- bash -c \
    'hostname; uname -a; echo; docker --version; docker compose version; python3 --version'
  cap ollama_modelle.log "Vorhandene Ollama-Modelle" -- bash -c \
    'ollama list 2>&1 || curl -fsS --max-time 5 http://127.0.0.1:8080/api/tags'
  cap git_stand.log "Stand des Quellordners" -- bash -c \
    "cd '${ROOT}' && git rev-parse --short HEAD && git status --short && git log --oneline -5"
  cap dienste.log "Zustand der eigenen Host-Dienste" -- bash -c \
    'systemctl status hf-ops-collector --no-pager -n 5; echo; systemctl status hf-ops-ai-relay --no-pager -n 5'
  cap ports.log "Belegte lokale Ports" -- bash -c \
    'ss -ltnp 2>/dev/null || ss -ltn'
  note "Noch von Hand ins Protokoll: Datum der Durchfuehrung."
}

cmd_phase_a() {
  setdir "01_phaseA_statische_analyse"
  say "Phase A: Analyse vor dem ersten Start"
  for f in "${ROOT}/Auftrag2_PhaseA_Statische_Analyse.md" "${LAB}/Statische_Analyse.md"; do
    [ -f "$f" ] && cp -p "$f" "${DIR}/" && note "kopiert: $(basename "$f")"
  done
  cap zeitnachweis.log "Zeitstempel der Analyse gegen Zeitstempel der Laborquellen" -- bash -c \
    "stat -c '%y  %n' '${ROOT}'/Auftrag2_PhaseA_Statische_Analyse.md '${LAB}'/Statische_Analyse.md \
       '${LAB}'/compose.yaml '${LAB}'/*/app.py 2>/dev/null"
  cap git_historie.log "Git-Historie der Analysedatei, falls vorhanden" -- bash -c \
    "cd '${ROOT}' && git log --follow --format='%ad  %h  %s' --date=iso -- Auftrag2_PhaseA_Statische_Analyse.md"
  note "Pruefe selbst: liegt der Zeitstempel der Analyse VOR deinem ersten Start?"
  note "Falls nicht belegbar, im Protokoll ehrlich benennen statt behaupten."
}

cmd_phase_b() {
  setdir "02_phaseB_erster_start"
  say "Phase B: Zustand der unveraenderten Umgebung (nur lesend)"
  cap compose_config.log "Aufgeloeste Konfiguration der Laborumgebung" -- bash -c \
    "cd '${LAB}' && sudo docker compose config"
  cap ps.log "Containerzustand" -- bash -c "cd '${LAB}' && sudo docker compose ps -a"
  for s in api web worker; do
    cap "health_${s}.json" "Healthcheck-Ausgabe ${s}" -- bash -c \
      "cd '${LAB}' && sudo docker inspect --format '{{json .State.Health}}' \
         \"\$(sudo docker compose ps -q ${s})\" | python3 -m json.tool"
  done
  cap logs_worker_vor_reparatur.log "Worker-Logs VOR jeder Reparatur, mit Zeitstempel" -- bash -c \
    "cd '${LAB}' && sudo docker compose logs --timestamps --tail 60 worker"
  cap logs_api.log "API-Logs" -- bash -c "cd '${LAB}' && sudo docker compose logs --timestamps --tail 20 api"
  cap logs_web.log "Web-Logs" -- bash -c "cd '${LAB}' && sudo docker compose logs --timestamps --tail 20 web"
  cap curl_web_health.log "Health der Laborumgebung ueber den veroeffentlichten Port" -- bash -c \
    'curl -fsS --max-time 5 http://127.0.0.1:8081/health'
  note "WICHTIG: logs_worker_vor_reparatur.log vor Test 4 sichern, danach sind diese Zeilen weg."
  note "Die PDF-Nachweise deines ersten Starts liegen auf dem Mac. Lege sie hier dazu:"
  note "  ${DIR}/"
}

cmd_phase_c() {
  setdir "03_phaseC_eigenes_monitoring"
  say "Phase C: eigenes Monitoring auf echten Daten"
  cap check_snapshot.log "Gegenprobe auf der Kommandozeile" -- bash -c \
    "'${MON}/collector/scripts/check-snapshot.sh' --logs"
  cap api_state.json "Aufbereiteter Zustand des Dashboards" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/state' | python3 -m json.tool"
  cap zustand_kurz.log "Lesbare Kurzfassung des Zustands" -- zustand_kurz
  cap dashboard_health.json "Eigener Health des Dashboards" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/health' | python3 -m json.tool"
  cap snapshot_roh.json "Rohdaten des Collectors" -- bash -c "cat '${SNAPSHOT}'"
  cap kein_docker_socket.log "Nachweis: der Dashboard-Container hat keinen Docker-Socket" -- bash -c \
    "cd '${MON}' && sudo docker compose config | grep -A4 'volumes:' ; echo '--- Mounts im laufenden Container ---' ; \
     sudo docker inspect --format '{{json .Mounts}}' \"\$(cd '${MON}' && sudo docker compose ps -q dashboard)\" | python3 -m json.tool"
  cap unbekannte_route.log "Unbekannte Route liefert einen Fehlerstatus" -- bash -c \
    "curl -s -o /dev/null -w 'HTTP %{http_code}\n' '${DASHBOARD}/gibtsnicht'"
  note "Screenshot der Seite ${DASHBOARD} von Hand ablegen unter:"
  note "  ${DIR}/dashboard_screenshot.png"
}

cmd_phase_d() {
  setdir "04_phaseD_ai"
  say "Phase D: AI-Anbindung aus dem Programm"
  cap relay_health.json "Zustand des AI-Relays" -- bash -c \
    "'${MON}/ai-relay/scripts/check-relay.sh'"
  cap ai_status.json "AI-Erreichbarkeit laut Dashboard" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/ai' | python3 -m json.tool"
  cap ai_analyse.json "Echte Modellanfrage aus dem Programm" -- bash -c \
    "curl -s --max-time 180 -X POST '${DASHBOARD}/api/analyze' | python3 -m json.tool"
  cap ai_analyse_lesbar.log "Die vier geforderten Elemente" -- analyse_lesbar
  cap netzgrenze.log "Nachweis: Relay nur aus dem Dashboard-Netz erreichbar" -- bash -c \
    "echo '--- Lauschadressen ---'; ss -ltn | grep -E '8899|8080|8090' || echo 'nichts gefunden'; \
     echo '--- Subnetz des Dashboard-Netzes ---'; \
     sudo docker network inspect hf-ops-dashboard --format '{{json .IPAM.Config}}' 2>/dev/null | python3 -m json.tool"
  cap allowlist_gegenprobe.log "Nicht freigegebenes Modell wird abgelehnt" -- bash -c \
    "curl -s -o /dev/null -w 'HTTP %{http_code}, erwartet 403\n' --max-time 10 \
       -H 'Content-Type: application/json' \
       -d '{\"model\":\"llama3\",\"prompt\":\"test\"}' '${RELAY}/v1/analyze'"
  note "Die Analyse im Protokoll selbst bewerten: was ist belegt, was ist Vermutung, was falsch."
}

cmd_phase_f() {
  setdir "10_phaseF_security"
  say "Phase F: Belege fuer die Security-Fragen"

  cap f1_docker_zugriff.log "Wer kann den Docker-Daemon ansprechen" -- bash -c \
    "echo '--- Socket ---'; ls -l /var/run/docker.sock; \
     echo '--- Gruppe docker ---'; getent group docker || echo 'keine Gruppe docker'; \
     echo '--- eigener Benutzer ---'; id; \
     echo '--- Benutzer der Host-Dienste ---'; \
     systemctl show hf-ops-collector -p User -p DynamicUser 2>/dev/null; \
     systemctl show hf-ops-ai-relay  -p User -p DynamicUser 2>/dev/null"

  cap f2_socket_akzeptiert_schreibend.log \
      "Die Docker-API kennt kein Leserecht: POST wird angenommen (Anfrage bewusst unvollstaendig, es entsteht nichts)" -- bash -c \
    "echo '--- lesend ---'; \
     sudo curl -s -o /dev/null -w 'GET  /_ping                        -> HTTP %{http_code}\n' \
       --unix-socket /var/run/docker.sock http://localhost/_ping; \
     echo '--- schreibend, ohne Rumpf, erzeugt keinen Container ---'; \
     sudo curl -s -o /dev/null -w 'POST /containers/create ohne Rumpf -> HTTP %{http_code}\n' \
       --unix-socket /var/run/docker.sock -X POST http://localhost/v1.43/containers/create; \
     echo 'Ein 4xx/5xx der API ist die Antwort auf einen fehlerhaften Rumpf,'; \
     echo 'nicht eine Ablehnung der Methode. Die Route ist erreichbar.'"

  cap f3_lesend_verraet_daten.log "Auch lesende Routen geben Environment im Klartext heraus" -- bash -c \
    "cd '${LAB}' && for s in api web worker; do \
       echo \"== \$s ==\"; \
       sudo docker inspect --format '{{json .Config.Env}}' \"\$(sudo docker compose ps -q \$s)\" \
         | python3 -m json.tool; \
     done"

  cap f4_dashboard_ohne_socket.log "Der Dashboard-Container hat keinen Zugang zur Docker-API" -- bash -c \
    "cd '${MON}'; echo '--- Mounts ---'; \
     sudo docker inspect --format '{{json .Mounts}}' \"\$(sudo docker compose ps -q dashboard)\" \
       | python3 -m json.tool; \
     echo '--- Benutzer und Rechte im Container ---'; \
     sudo docker inspect --format 'User={{.Config.User}} ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} CapDrop={{.HostConfig.CapDrop}} SecurityOpt={{.HostConfig.SecurityOpt}}' \
       \"\$(sudo docker compose ps -q dashboard)\""

  cap f5_haertung_collector.log "Was der Collector darf und was nicht" -- bash -c \
    "systemctl cat hf-ops-collector 2>/dev/null | grep -vE '^\s*#|^\s*$'; \
     echo '--- Bewertung durch systemd ---'; \
     systemd-analyze security hf-ops-collector 2>/dev/null | tail -3"

  cap f5_haertung_relay.log "Was das AI-Relay darf und was nicht" -- bash -c \
    "systemctl cat hf-ops-ai-relay 2>/dev/null | grep -vE '^\s*#|^\s*$'; \
     echo '--- Bewertung durch systemd ---'; \
     systemd-analyze security hf-ops-ai-relay 2>/dev/null | tail -3"

  cap f6_hostnetz_waere_erreichbar.log \
      "Was ein Container mit Host-Netzwerk zusaetzlich erreichen wuerde" -- bash -c \
    "echo 'Alle lokal gebundenen Dienste des Hosts:'; \
     PATH=\"\$PATH:/usr/sbin:/sbin\"; \
     sudo ss -ltnp 2>/dev/null || ss -ltn 2>/dev/null || netstat -ltnp 2>/dev/null || \
       echo 'weder ss noch netstat vorhanden'"

  cap f7_bindungen.log "Wohin die eigenen Dienste gebunden sind" -- bash -c \
    "echo '--- Dashboard ---'; cd '${MON}' && sudo docker compose port dashboard 8000; \
     echo '--- Laborumgebung ---'; cd '${LAB}' && sudo docker compose port web 8000; \
     echo '--- alle Lauscher auf den beteiligten Ports ---'; \
     ss -ltn | grep -E '8080|8081|8090|8899|3000' || echo 'keine'"

  cap f8_keine_geheimnisse_in_logs.log \
      "Das Relay protokolliert Groesse und Dauer, keine Promptinhalte" -- bash -c \
    "journalctl -u hf-ops-ai-relay -n 40 --no-pager 2>/dev/null | tail -20"

  cap f9_modelltext_wird_escaped.log \
      "Modelltext wird als Text ausgegeben, nicht als HTML ausgefuehrt" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/' > /tmp/seite.html 2>/dev/null; \
     echo -n 'Roher script-Tag in der Seite: '; \
     grep -c '<script>alert' /tmp/seite.html 2>/dev/null || echo 0; \
     echo -n 'Escaped ausgegeben (&lt;): '; grep -c '&lt;' /tmp/seite.html 2>/dev/null || echo 0; \
     echo '--- gesetzte Schutz-Kopfzeilen ---'; \
     curl -sSI --max-time 10 '${DASHBOARD}/' | grep -iE 'content-security-policy|x-content-type|referrer'; \
     rm -f /tmp/seite.html"

  note "Die Antworten selbst gehoeren in Phase_F_Security.md, in deine Worte."
}

cmd_test1() {
  setdir "05_test1_unveraenderte_umgebung"
  say "Test 1: unveraenderte Umgebung, AI analysiert echte Daten"
  cap ps.log "Containerzustand" -- bash -c "cd '${LAB}' && sudo docker compose ps -a"
  cap check_snapshot.log "Eigene Erfassung" -- bash -c "'${MON}/collector/scripts/check-snapshot.sh' --logs"
  cap api_state.json "Zustand laut Dashboard" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/state' | python3 -m json.tool"
  cap dashboard_health.json "Dashboard-Health" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/health' | python3 -m json.tool"
  cap ai_analyse.json "AI-Analyse auf diesen Daten" -- bash -c \
    "curl -s --max-time 180 -X POST '${DASHBOARD}/api/analyze' | python3 -m json.tool"
  note "Soll: api und web gesund, worker fehlerhaft, passende Logzeilen, Analyse auf echten Daten."
}

cmd_test2() {
  setdir "06_test2_ai_nicht_erreichbar"
  say "Test 2: AI nicht erreichbar (Eingriff, stellt selbst wieder her)"
  note "Nur die Zieladresse der eigenen Anwendung wird umgebogen."
  note "Ollama und das Relay werden nicht angefasst."
  ( cd "${DIR}" && sudo DASHBOARD_URL="${DASHBOARD}" "${MON}/ai-relay/scripts/faultcase-ai.sh" ) \
    > "${DIR}/ablauf.log" 2>&1
  local rc=$?
  printf '# Exit-Code des Skripts: %s\n' "${rc}" >> "${DIR}/ablauf.log"
  sudo chown -R "$(id -u):$(id -g)" "${DIR}" 2>/dev/null
  note "Ablauf in ablauf.log, Protokoll des Skripts daneben."
  cap ai_status_nachher.json "AI-Status nach der Wiederherstellung" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/ai' | python3 -m json.tool"
}

cmd_test3() {
  setdir "07_test3_erfassung_gestoert"
  say "Test 3: Datenerfassung gestoert (Eingriff, stellt selbst wieder her)"
  ( cd "${DIR}" && sudo DASHBOARD_URL="${DASHBOARD}/health" "${MON}/collector/scripts/faultcase-collector.sh" ) \
    > "${DIR}/ablauf.log" 2>&1
  local rc=$?
  printf '# Exit-Code des Skripts: %s\n' "${rc}" >> "${DIR}/ablauf.log"
  sudo chown -R "$(id -u):$(id -g)" "${DIR}" 2>/dev/null
  cap analyse_auf_alten_daten.json "Analyse waehrend der Stoerung wurde abgelehnt" -- bash -c \
    "curl -s --max-time 30 -X POST '${DASHBOARD}/api/analyze' | python3 -m json.tool"
  cap check_snapshot_nachher.log "Zustand nach der Wiederherstellung" -- bash -c \
    "'${MON}/collector/scripts/check-snapshot.sh'"
  note "Soll: alte Daten erscheinen nie als frisch oder gesund, Sequenz laeuft danach wieder."
}

cmd_test4_vorher() {
  setdir "08_test4_worker_repariert"
  say "Test 4, Teil 1: Hypothese pruefen, noch kein Eingriff"
  cap vergleich_route_konfiguration.log "Route im Code gegen Wert in der Konfiguration" -- bash -c \
    "grep -n 'jobs\|jobz\|JOB_PATH' '${LAB}/api/app.py' '${LAB}/worker/app.py' '${LAB}/compose.yaml'"
  cap wirksamer_wert.json "Tatsaechlich wirksamer Wert im laufenden Container" -- bash -c \
    "cd '${LAB}' && sudo docker inspect --format '{{json .Config.Env}}' \
       \"\$(sudo docker compose ps -q worker)\" | python3 -m json.tool"
  cap zustand_vorher.json "Zustand vor dem Eingriff" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/state' | python3 -m json.tool"
  cap logs_vorher.log "Worker-Logs vor dem Eingriff" -- bash -c \
    "cd '${LAB}' && sudo docker compose logs --timestamps --tail 60 worker"
  printf '%s\n' "$(ts)" > "${DIR}/zeitpunkt_vor_eingriff.txt"
  note "Jetzt die Hypothese im Protokoll festhalten, DANN:"
  note "  cd ${LAB} && sudo JOB_PATH=PFAD_AUS_DEINEM_VERGLEICH docker compose up -d worker"
  note "Danach: ./scripts/belege.sh test4-nachher"
}

cmd_test4_nachher() {
  setdir "08_test4_worker_repariert"
  say "Test 4, Teil 2: Wirkung belegen"
  printf '%s\n' "$(ts)" > "${DIR}/zeitpunkt_nach_eingriff.txt"
  note "25 s warten, bis der Healthcheck greift"
  sleep 25
  cap ps_nachher.log "Containerzustand nach dem Eingriff" -- bash -c "cd '${LAB}' && sudo docker compose ps -a"
  cap health_nachher.json "Healthcheck-Ausgabe nach dem Eingriff" -- bash -c \
    "cd '${LAB}' && sudo docker inspect --format '{{json .State.Health}}' \
       \"\$(sudo docker compose ps -q worker)\" | python3 -m json.tool"
  cap wirksamer_wert_nachher.json "Wirksamer Wert nach der Containerneuerstellung" -- bash -c \
    "cd '${LAB}' && sudo docker inspect --format '{{json .Config.Env}}' \
       \"\$(sudo docker compose ps -q worker)\" | python3 -m json.tool"
  cap logs_nachher.log "Neue Logzeilen" -- bash -c \
    "cd '${LAB}' && sudo docker compose logs --timestamps --tail 30 worker"
  cap zustand_nachher.json "Zustand nach dem Eingriff" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/state' | python3 -m json.tool"
  cap ai_analyse_nachher.json "Neue AI-Analyse als Beleg der Wirkung" -- bash -c \
    "curl -s --max-time 180 -X POST '${DASHBOARD}/api/analyze' | python3 -m json.tool"
  {
    printf '# Zeitachse\n# Zeitpunkt (UTC): %s\n# ---\n' "$(ts)"
    printf 'Eingriff zwischen:\n'
    printf '  vorher : %s\n' "$(cat "${DIR}/zeitpunkt_vor_eingriff.txt" 2>/dev/null)"
    printf '  nachher: %s\n' "$(cat "${DIR}/zeitpunkt_nach_eingriff.txt" 2>/dev/null)"
    printf '\nLetzte Fehlerzeile vor dem Eingriff:\n'
    grep ERROR "${DIR}/logs_vorher.log" 2>/dev/null | tail -1
    printf '\nErste Zeilen nach dem Eingriff:\n'
    sed -n '5,8p' "${DIR}/logs_nachher.log" 2>/dev/null
  } > "${DIR}/zeitachse.log"
  note "ok    zeitachse.log"
}

cmd_test5() {
  setdir "09_test5_container_fehlt"
  say "Test 5: fehlender Containerzustand (Eingriff, stellt selbst wieder her)"
  note "Der Worker-Container wird entfernt. Seine Logzeilen sind danach weg."
  printf '%s\n' "$(ts)" > "${DIR}/zeitpunkt_eingriff.txt"
  lab rm -sf worker > "${DIR}/eingriff.log" 2>&1
  sleep 10
  cap check_snapshot_fehlend.log "Erfassung bei fehlendem Container" -- bash -c \
    "'${MON}/collector/scripts/check-snapshot.sh'"
  cap zustand_fehlend.json "Anzeige bei fehlendem Container" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/state' | python3 -m json.tool"
  cap dashboard_health_fehlend.json "Dashboard bleibt gesund" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/health' | python3 -m json.tool"

  say "Gegenprobe: gestoppt ist nicht dasselbe wie fehlend"
  lab up -d worker > /dev/null 2>&1
  sleep 20
  lab stop worker > /dev/null 2>&1
  sleep 10
  cap check_snapshot_gestoppt.log "Erfassung bei gestopptem Container" -- bash -c \
    "'${MON}/collector/scripts/check-snapshot.sh'"
  cap zustand_gestoppt.json "Anzeige bei gestopptem Container" -- bash -c \
    "curl -fsS --max-time 10 '${DASHBOARD}/api/state' | python3 -m json.tool"

  say "Wiederherstellung"
  lab up -d worker > "${DIR}/wiederherstellung.log" 2>&1
  sleep 25
  cap check_snapshot_nachher.log "Zustand nach der Wiederherstellung" -- bash -c \
    "'${MON}/collector/scripts/check-snapshot.sh'"
  note "Soll: fehlend und gestoppt sind zwei verschiedene Zustaende, nie 'alles gesund'."
}

cmd_index() {
  pruefe_umgebung
  say "Inhaltsverzeichnis schreiben"
  local out="${BELEGE}/README.md"
  {
    printf '# Belege Auftrag 2\n\n'
    printf 'Erzeugt mit `02_Monitoring/scripts/belege.sh`. Jede Datei traegt im Kopf\n'
    printf 'den Zeitpunkt, den ausgefuehrten Befehl und den Exit-Code.\n\n'
    printf 'Stand: %s\n\n' "$(ts)"
    printf '| Ordner | Erfasst am | Dateien |\n|---|---|---|\n'
    local d
    for d in "${BELEGE}"/*/; do
      [ -d "$d" ] || continue
      local name erfasst anzahl
      name="$(basename "$d")"
      erfasst="$(cat "${d}/.erfasst_am" 2>/dev/null || echo '-')"
      anzahl="$(find "$d" -maxdepth 1 -type f ! -name '.erfasst_am' | wc -l)"
      printf '| `%s` | %s | %s |\n' "${name}" "${erfasst}" "${anzahl}"
    done
    printf '\n## Dateien im Einzelnen\n\n'
    for d in "${BELEGE}"/*/; do
      [ -d "$d" ] || continue
      printf '### %s\n\n' "$(basename "$d")"
      local f
      for f in "$d"*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in .erfasst_am) continue;; esac
        printf -- '- `%s` %s\n' "$(basename "$f")" \
          "$(head -1 "$f" 2>/dev/null | sed 's/^# //' | cut -c1-70)"
      done
      printf '\n'
    done
  } > "${out}"
  note "geschrieben: ${out}"
}

cmd_hilfe() {
  cat <<EOF
belege.sh - Nachweise fuer Auftrag 2 einsammeln

Ziel:  ${BELEGE}
Labor: ${LAB}
Dash:  ${DASHBOARD}

Ohne Eingriff in die Umgebung:
  rahmen         Host, Werkzeuge, Modelle, Git-Stand, Dienste, Ports
  phase-a        statische Analyse und ihre Zeitstempel
  phase-b        unveraenderte Umgebung, Logs VOR jeder Reparatur
  phase-c        eigenes Monitoring auf echten Daten
  phase-d        AI-Status, echte Modellanfrage, Netzgrenze, Allowlist
  phase-f        Belege fuer die sechs Security-Fragen
  test1          unveraenderte Umgebung mit AI-Analyse

Mit Eingriff, jeweils mit Wiederherstellung:
  test2          AI nicht erreichbar
  test3          Datenerfassung gestoert
  test4-vorher   Hypothese pruefen, Zustand und Logs sichern
  test4-nachher  nach deinem Eingriff: Wirkung belegen
  test5          fehlender Container, Gegenprobe gestoppt

Sammelbefehle:
  alles-ohne-eingriff   rahmen, phase-a bis phase-d, test1
  index                 Inhaltsverzeichnis belege/README.md schreiben
EOF
}

# ---------------------------------------------------------------------------

case "${1:-hilfe}" in
  rahmen)        pruefe_umgebung; cmd_rahmen;;
  phase-a)       pruefe_umgebung; cmd_phase_a;;
  phase-b)       pruefe_umgebung; cmd_phase_b;;
  phase-c)       pruefe_umgebung; cmd_phase_c;;
  phase-d)       pruefe_umgebung; cmd_phase_d;;
  phase-f)       pruefe_umgebung; cmd_phase_f;;
  test1)         pruefe_umgebung; cmd_test1;;
  test2)         pruefe_umgebung; cmd_test2;;
  test3)         pruefe_umgebung; cmd_test3;;
  test4-vorher)  pruefe_umgebung; cmd_test4_vorher;;
  test4-nachher) pruefe_umgebung; cmd_test4_nachher;;
  test5)         pruefe_umgebung; cmd_test5;;
  alles-ohne-eingriff)
    pruefe_umgebung
    cmd_rahmen; cmd_phase_a; cmd_phase_b; cmd_phase_c; cmd_phase_d; cmd_phase_f; cmd_test1; cmd_index
    ;;
  index)         cmd_index;;
  hilfe|-h|--help) cmd_hilfe;;
  *) printf 'Unbekannter Unterbefehl: %s\n\n' "$1" >&2; cmd_hilfe; exit 1;;
esac

printf '\nFertig. Belege unter: %s\n' "${BELEGE}"
