#!/usr/bin/env bash
# belege-lb1.sh - sammelt die Terminalbelege fuer die LB1 nach belege/lb1/
#
# Deckt ab, was sich auf der Kommandozeile messen laesst: Rahmenangaben,
# T2 (Serverdaten aktualisieren), T5 (Container-Neuerstellung mit IDs vorher
# und nachher) und T6 (non-root, read-only). T1, T3, T4 und T7 brauchen den
# Browser auf dem Kali, dafuer gibt dieses Skript die Anleitung aus.
#
# In 04_Karate ablegen unter scripts/belege-lb1.sh und von dort aufrufen:
#   chmod +x scripts/belege-lb1.sh
#   ./scripts/belege-lb1.sh rahmen
#   ./scripts/belege-lb1.sh t2
#   ./scripts/belege-lb1.sh t5
#   ./scripts/belege-lb1.sh t6
#   ./scripts/belege-lb1.sh alles       # rahmen, t2, t6, t5 in dieser Folge
#   ./scripts/belege-lb1.sh anleitung   # was im Browser von Hand zu tun ist
#
# Nicht mit sudo aufrufen, sonst gehoeren die Belege root. Das Skript ruft
# sudo dort, wo es noetig ist.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${SELF}/.." && pwd)"
ROOT="$(cd "${PROJ}/.." && pwd)"
BELEGE="${BELEGE_DIR:-${ROOT}/belege/lb1}"

DIENST="${DIENST:-app}"
HOSTPORT="${HOSTPORT:-8084}"
UBUNTU_IP="${UBUNTU_IP:-192.168.110.61}"
KALI_IP="${KALI_IP:-192.168.110.70}"
LOKAL="http://127.0.0.1:${HOSTPORT}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/conf.d/lb1-8084.conf}"

ts()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
say()  { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

dc() { ( cd "${PROJ}" && sudo docker compose "$@" ); }
cid() { ( cd "${PROJ}" && sudo docker compose ps -q "${DIENST}" 2>/dev/null ); }

mkdir -p "${BELEGE}"

# cap <datei> <beschreibung> -- <befehl ...>
cap() {
  local file="$1" desc="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  local target="${BELEGE}/${file}"
  {
    printf '# %s\n' "${desc}"
    printf '# Zeitpunkt (UTC): %s\n' "$(ts)"
    printf '# Arbeitsverzeichnis: %s\n' "${PROJ}"
    printf '# Befehl: %s\n' "$*"
    printf '# ---\n'
  } > "${target}"
  "$@" >> "${target}" 2>&1
  local rc=$?
  printf '# ---\n# Exit-Code: %s\n' "${rc}" >> "${target}"
  if [ "${rc}" -eq 0 ]; then note "ok    ${file}"; else note "rc=${rc} ${file}"; fi
  return 0
}

pruefe_projekt() {
  if [ ! -f "${PROJ}/compose.yaml" ]; then
    note "FEHLER: ${PROJ}/compose.yaml fehlt."
    note "Das Skript gehoert nach <projekt>/scripts/ und wird von <projekt>/ aufgerufen."
    exit 1
  fi
}

# ---------------------------------------------------------------------------

cmd_rahmen() {
  say "Rahmenangaben"
  cap 00_rahmen.log "Host, Werkzeuge, Pfade" -- bash -c \
    "hostname -f; echo; ip -br -4 address; echo; docker --version; \
     docker compose version; echo; echo 'Projektpfad: ${PROJ}'"
  cap 01_quellstand.log "Quellstand und Projektdateien" -- bash -c \
    "cd '${ROOT}' && git rev-parse --short HEAD && git status --short; echo; \
     ls -la '${PROJ}'"
  cap 02_compose_wirksam.log "Wirksame Compose-Konfiguration mit aufgeloesten Variablen" -- bash -c \
    "cd '${PROJ}' && HOSTPORT='${HOSTPORT}' sudo docker compose config"
  cap 03_image.log "Gebautes Image" -- bash -c \
    "cd '${PROJ}' && sudo docker compose images; echo; sudo docker images | head -5"
  cap 04_nginx.log "Freigabe des Zugangsports (bereitgestellte Infrastruktur)" -- bash -c \
    "sudo cat '${NGINX_CONF}' 2>&1; echo; \
     echo '--- Listener ---'; \
     sudo ss -ltnp 2>/dev/null | grep ':${HOSTPORT}' || ss -ltn | grep ':${HOSTPORT}'"
  if sudo test -r "${NGINX_CONF}" 2>/dev/null; then
    sudo cat "${NGINX_CONF}" > "${BELEGE}/04_nginx_konfiguration.conf" 2>/dev/null \
      && sudo chown "$(id -un):$(id -gn)" "${BELEGE}/04_nginx_konfiguration.conf" 2>/dev/null \
      && note "ok    04_nginx_konfiguration.conf (Kopie fuer die Abgabe)"
  fi
  {
    printf '# Portkette\n# Zeitpunkt (UTC): %s\n# ---\n' "$(ts)"
    printf 'Browser auf Kali (%s)\n' "${KALI_IP}"
    printf '  --> Nginx  %s:%s        allow %s; deny all\n' "${UBUNTU_IP}" "${HOSTPORT}" "${KALI_IP}"
    printf '  --> proxy_pass 127.0.0.1:%s   docker-proxy\n' "${HOSTPORT}"
    printf '  --> Container-Port 8000       app.py, hoert auf 0.0.0.0\n\n'
    printf 'Animation: laeuft im Browser, CSS-Keyframes, kein Serveranteil.\n'
    printf 'Statusabfrage: alle 5 s ueber die ganze Kette bis /api/info.\n'
  } > "${BELEGE}/05_portkette.log"
  note "ok    05_portkette.log"
}

cmd_t2() {
  say "T2: Serverdaten werden aktualisiert"
  cap t2_01_zustand.log "H4: Prozesszustand und Health getrennt" -- bash -c \
    "cd '${PROJ}' && sudo docker compose ps; echo; \
     sudo docker inspect --format \
       'Health={{.State.Health.Status}} Running={{.State.Running}} RestartCount={{.RestartCount}}' \
       \"\$(sudo docker compose ps -q ${DIENST})\""
  cap t2_02_abfrage_zweimal.log "Zwei Abfragen von /api/info im Abstand von 10 s" -- bash -c \
    "echo '--- erste Abfrage ---'; date -u +%Y-%m-%dT%H:%M:%SZ; \
     curl -fsS --max-time 10 '${LOKAL}/api/info'; echo; \
     echo; echo '--- 10 s warten ---'; sleep 10; \
     echo '--- zweite Abfrage ---'; date -u +%Y-%m-%dT%H:%M:%SZ; \
     curl -fsS --max-time 10 '${LOKAL}/api/info'; echo"
  note "Soll: uptime_seconds ist in der zweiten Abfrage um etwa 10 hoeher."
  cap t2_03_health.log "/health der Anwendung" -- bash -c \
    "curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 '${LOKAL}/health'; \
     curl -fsS --max-time 10 '${LOKAL}/health'; echo"
}

cmd_t6() {
  say "T6 und H8: non-root und read-only"
  cap t6_01_benutzer.log "Benutzer im Container" -- bash -c \
    "cd '${PROJ}' && sudo docker compose exec -T ${DIENST} id"
  cap t6_02_readonly.log "Root-Dateisystem nicht beschreibbar, /tmp als tmpfs schon" -- bash -c \
    "cd '${PROJ}'; \
     echo '--- touch /beweis  (muss scheitern) ---'; \
     sudo docker compose exec -T ${DIENST} touch /beweis; \
     echo \"exit=\${PIPESTATUS[0]}\"; \
     echo; echo '--- touch /tmp/beweis  (muss gelingen) ---'; \
     sudo docker compose exec -T ${DIENST} touch /tmp/beweis && echo 'ok, /tmp ist beschreibbar'"
  cap t6_03_inspect.log "Einstellungen am laufenden Container" -- bash -c \
    "cd '${PROJ}' && sudo docker inspect --format \
      'User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}} Policy={{.HostConfig.RestartPolicy.Name}} CapDrop={{.HostConfig.CapDrop}} SecurityOpt={{.HostConfig.SecurityOpt}}' \
      \"\$(sudo docker compose ps -q ${DIENST})\""
}

cmd_t5() {
  say "T5 und H7: Container entfernen und neu erstellen"
  note "Das beendet die Anwendung kurz. Fuer T3 und T4 vorher die Seite auf dem"
  note "Kali offen haben, dann kannst du beides in einem Durchgang zeigen."

  local vorher nachher
  vorher="$(cid)"
  {
    printf '# T5 Container-Neuerstellung\n# Zeitpunkt (UTC): %s\n# ---\n' "$(ts)"
    printf 'Container-ID vorher : %s\n' "${vorher:-nicht vorhanden}"
    printf 'Image-ID vorher     : %s\n' \
      "$( (cd "${PROJ}" && sudo docker compose images -q "${DIENST}" 2>/dev/null) || echo '-')"
  } > "${BELEGE}/t5_01_vorher.log"
  note "ok    t5_01_vorher.log"

  cap t5_02_abbau.log "docker compose down" -- bash -c \
    "cd '${PROJ}' && sudo docker compose down"
  cap t5_03_luecke.log "Beweis, dass waehrend des Abbaus nichts antwortet" -- bash -c \
    "curl -sS -o /dev/null -w 'waehrend des Abbaus: HTTP %{http_code}\n' \
       --max-time 5 '${LOKAL}/health'; \
     echo '(000 bedeutet keine Verbindung, der Dienst ist wirklich weg)'"
  cap t5_04_aufbau.log "Neu bauen und starten" -- bash -c \
    "cd '${PROJ}' && HOSTPORT='${HOSTPORT}' sudo docker compose up -d --build"
  note "15 s warten, bis der Healthcheck greift"
  sleep 15

  nachher="$(cid)"
  {
    printf '# T5 Container-Neuerstellung, Ergebnis\n# Zeitpunkt (UTC): %s\n# ---\n' "$(ts)"
    printf 'Container-ID vorher : %s\n' "${vorher:-nicht vorhanden}"
    printf 'Container-ID nachher: %s\n' "${nachher:-nicht vorhanden}"
    if [ -n "${vorher}" ] && [ -n "${nachher}" ] && [ "${vorher}" != "${nachher}" ]; then
      printf 'Ergebnis            : neue Container-ID, Soll erfuellt\n'
    elif [ -z "${vorher}" ]; then
      printf 'Ergebnis            : vorher lief kein Container, Vergleich unvollstaendig\n'
    else
      printf 'Ergebnis            : ID unveraendert, Soll NICHT erfuellt, nachpruefen\n'
    fi
    printf 'Image-ID nachher    : %s\n' \
      "$( (cd "${PROJ}" && sudo docker compose images -q "${DIENST}" 2>/dev/null) || echo '-')"
  } > "${BELEGE}/t5_05_nachher.log"
  note "ok    t5_05_nachher.log"

  cap t5_06_funktion.log "Anwendung antwortet nach der Neuerstellung" -- bash -c \
    "cd '${PROJ}' && sudo docker compose ps; echo; \
     curl -sS -o /dev/null -w 'lokal     HTTP %{http_code}\n' --max-time 10 '${LOKAL}/'; \
     curl -sS -o /dev/null -w 'ueber LAN HTTP %{http_code}\n' --max-time 10 'http://${UBUNTU_IP}:${HOSTPORT}/'; \
     curl -fsS --max-time 10 '${LOKAL}/api/info'; echo"
  note "Soll: uptime_seconds beginnt wieder klein, das ist gleichzeitig T4."
}

cmd_anleitung() {
  say "Was von Hand im Browser gehoert"
  cat <<EOF

Diese vier Tests kann kein Skript belegen, sie brauchen den Browser auf dem
Kali (${KALI_IP}). URL: http://${UBUNTU_IP}:${HOSTPORT}/

T7 und T1, ein Screenshot deckt beide ab
  1. Firefox auf dem Kali, http://${UBUNTU_IP}:${HOSTPORT}/ oeffnen
  2. Start druecken, auf Tritt umschalten, Pause druecken, erneut Start
  3. Screenshot mit sichtbarer URL und Roboter in Bewegung
     -> screenshots/S01_kali_roboter.png

T2, zusaetzlich zum Terminalbeleg
  4. Screenshot des Dashboards mit Laufzeit und Pruefzeitpunkt,
     daneben das Terminal mit t2_02_abfrage_zweimal.log
     -> screenshots/S02_dashboard_laufzeit.png

T3 und T4, der wichtigste Beleg
  5. Seite auf dem Kali offen und im Vordergrund lassen.
     Firefox bremst Timer in Hintergrundtabs, sonst stimmt die Zeit nicht.
  6. Auf der VM:  cd ${PROJ} && sudo docker compose stop
  7. Innerhalb von 5 s steht "nicht erreichbar", die Serverwerte sind
     durchgestrichen, der Hinweis nennt die Uhrzeit der letzten Antwort.
     Screenshot -> screenshots/S03_ausfall.png
     Uhrzeit des Stopps und Uhrzeit der Meldung notieren, das ist das Ist zu T3.
  8. Auf der VM:  sudo docker compose start
  9. Seite NICHT neu laden. Innerhalb von 5 s ist der Dienst wieder erkannt
     und die Server-Laufzeit beginnt neu. Das ist T4.

T6, Screenshot zum Terminalbeleg
 10. Screenshot des Terminals mit id, dem gescheiterten touch /beweis und
     docker inspect -> screenshots/S04_rechte.png

Die Animation zusaetzlich live vorfuehren, ein Einzelbild beweist keine
Bewegung.

Qwen-Austausch fuer R3 ablegen unter: ${BELEGE}/qwen/
EOF
}

cmd_hilfe() {
  cat <<EOF
belege-lb1.sh - Terminalbelege fuer die LB1 einsammeln

Projekt: ${PROJ}
Ziel:    ${BELEGE}
Port:    ${HOSTPORT}  (Host)   ->  8000 (Container)
Adressen: Ubuntu ${UBUNTU_IP}, Kali ${KALI_IP}

  rahmen      Host, Quellstand, wirksame Compose-Konfiguration, Image,
              Nginx-Freigabe, Portkette
  t2          Zustand, Health und zwei Abfragen von /api/info im Abstand
  t6          non-root, read-only, Einstellungen am Container
  t5          Container entfernen und neu erstellen, IDs vorher und nachher
  alles       rahmen, t2, t6, t5 in dieser Folge
  anleitung   was im Browser auf dem Kali von Hand zu tun ist

Abweichende Werte per Umgebungsvariable:
  HOSTPORT=8084 UBUNTU_IP=192.168.110.61 KALI_IP=192.168.110.70 \\
    DIENST=app ./scripts/belege-lb1.sh alles
EOF
}

case "${1:-hilfe}" in
  rahmen)    pruefe_projekt; cmd_rahmen;;
  t2)        pruefe_projekt; cmd_t2;;
  t5)        pruefe_projekt; cmd_t5;;
  t6)        pruefe_projekt; cmd_t6;;
  alles)     pruefe_projekt; cmd_rahmen; cmd_t2; cmd_t6; cmd_t5; cmd_anleitung;;
  anleitung) cmd_anleitung;;
  hilfe|-h|--help) cmd_hilfe;;
  *) printf 'Unbekannter Unterbefehl: %s\n\n' "$1" >&2; cmd_hilfe; exit 1;;
esac

printf '\nFertig. Belege unter: %s\n' "${BELEGE}"
