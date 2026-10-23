#!/usr/bin/env bash
# karate.sh - bequemer Griff fuer Start, Stopp und Pruefung des Containers.
#
# Das Skript zeigt vor jeder Handlung den Befehl, den es ausfuehrt, und die
# zugehoerige H-ID aus der Abgabe. Damit bleibt es bequem, ohne dass die
# eigentlichen Befehle verschwinden: du kannst sie aus der Ausgabe in die
# Abgabevorlage uebernehmen.
#
#   ./scripts/karate.sh start     H2  Container starten
#   ./scripts/karate.sh stop      H5  anhalten, Container bleibt bestehen
#   ./scripts/karate.sh an        H6  nach stop wieder anlaufen lassen
#   ./scripts/karate.sh neu       H1+H7  neu bauen und neu erstellen
#   ./scripts/karate.sh status    H4  Zustand, Health, Erreichbarkeit
#   ./scripts/karate.sh logs      H4  letzte Logzeilen
#   ./scripts/karate.sh rechte    H8  Benutzer und read-only pruefen
#   ./scripts/karate.sh id            Container- und Image-ID
#   ./scripts/karate.sh weg       H7  Container und Netz entfernen
set -uo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIENST="${DIENST:-app}"
HOSTPORT="${HOSTPORT:-8084}"
UBUNTU_IP="${UBUNTU_IP:-192.168.110.61}"
LOKAL="http://127.0.0.1:${HOSTPORT}"

say()  { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
uhr()  { printf '   Uhrzeit: %s\n' "$(date +%T)"; }

# lauf <h-id> <befehl ...>  zeigt den Befehl und fuehrt ihn aus
lauf() {
  local hid="$1"; shift
  printf '   [%s] + %s\n' "${hid}" "$*"
  "$@"
  local rc=$?
  [ "${rc}" -ne 0 ] && note "Exit-Code ${rc}"
  return "${rc}"
}

dc() { ( cd "${PROJ}" && HOSTPORT="${HOSTPORT}" sudo docker compose "$@" ); }

cid()  { ( cd "${PROJ}" && sudo docker compose ps -q "${DIENST}" 2>/dev/null ); }
imid() { ( cd "${PROJ}" && sudo docker compose images -q "${DIENST}" 2>/dev/null ); }

# Warnt, wenn der Port noch vom Prozess ohne Container belegt ist.
pruefe_port() {
  local blocker
  blocker="$(pgrep -af 'LB1_Muster/app.py' 2>/dev/null | head -1)"
  if [ -n "${blocker}" ]; then
    note "ACHTUNG: es laeuft noch ein Prozess ohne Container:"
    note "  ${blocker}"
    note "Erst beenden, sonst ist Port ${HOSTPORT} belegt:"
    note "  kill ${blocker%% *}"
    return 1
  fi
  return 0
}

erreichbar() {
  local wo="$1" url="$2"
  printf '   %-10s ' "${wo}"
  curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 "${url}" \
    || printf 'keine Antwort\n'
}

cmd_start() {
  say "Container starten"
  pruefe_port || return 1
  uhr
  lauf H2 sudo env HOSTPORT="${HOSTPORT}" docker compose -f "${PROJ}/compose.yaml" up -d
  note "12 s warten, bis der Healthcheck greift"
  sleep 12
  cmd_status
}

cmd_neu() {
  say "Neu bauen und neu erstellen"
  pruefe_port || return 1
  note "Image-ID vorher   : $(imid)"
  note "Container-ID vorher: $(cid)"
  uhr
  lauf "H1+H7" sudo env HOSTPORT="${HOSTPORT}" docker compose -f "${PROJ}/compose.yaml" up -d --build
  note "12 s warten"
  sleep 12
  note "Image-ID nachher   : $(imid)"
  note "Container-ID nachher: $(cid)"
  note "Nach einer Codeaenderung ist genau das noetig, nicht restart."
  cmd_status
}

cmd_stop() {
  say "Anhalten, Container bleibt bestehen"
  uhr
  note "Diese Uhrzeit ist der Ist-Wert fuer T3. Seite auf dem Kali offen lassen."
  lauf H5 sudo docker compose -f "${PROJ}/compose.yaml" stop
  uhr
  lauf H4 sudo docker compose -f "${PROJ}/compose.yaml" ps
  erreichbar "ueber LAN" "http://${UBUNTU_IP}:${HOSTPORT}/"
  note "502 kommt von Nginx: es steht, nur der Container dahinter ist weg."
  note "Im Browser auf dem Kali steht jetzt 'nicht erreichbar'. S03 aufnehmen."
}

cmd_an() {
  say "Wieder anlaufen lassen"
  uhr
  note "Seite auf dem Kali NICHT neu laden, sonst ist T4 nicht belegt."
  lauf H6 sudo docker compose -f "${PROJ}/compose.yaml" start
  note "8 s warten"
  sleep 8
  cmd_status
  note "Im Browser steht wieder 'erreichbar', Laufzeit beginnt neu. S04 aufnehmen."
}

cmd_weg() {
  say "Container und Netz entfernen"
  note "Container-ID vorher: $(cid)"
  uhr
  lauf H7 sudo docker compose -f "${PROJ}/compose.yaml" down
  erreichbar "lokal" "${LOKAL}/health"
  note "000 oder 502 bedeutet: der Dienst ist wirklich weg."
}

cmd_status() {
  say "Zustand"
  lauf H4 sudo docker compose -f "${PROJ}/compose.yaml" ps
  local c; c="$(cid)"
  if [ -n "${c}" ]; then
    lauf H4 sudo docker inspect --format \
      'Health={{.State.Health.Status}} Running={{.State.Running}} RestartCount={{.RestartCount}}' "${c}"
  else
    note "kein Container vorhanden"
  fi
  erreichbar "lokal" "${LOKAL}/"
  erreichbar "ueber LAN" "http://${UBUNTU_IP}:${HOSTPORT}/"
  note "Running=true allein beweist keine funktionierende Anwendung, darum Health daneben."
}

cmd_logs() {
  say "Letzte Logzeilen"
  lauf H4 sudo docker compose -f "${PROJ}/compose.yaml" logs --tail 30 "${DIENST}"
}

cmd_rechte() {
  say "Benutzer und read-only pruefen"
  lauf H8 sudo docker compose -f "${PROJ}/compose.yaml" exec -T "${DIENST}" id
  printf '   [H8] + docker compose exec %s touch /beweis   (muss scheitern)\n' "${DIENST}"
  dc exec -T "${DIENST}" touch /beweis
  note "Exit-Code ${?}, erwartet ist ungleich 0 mit 'Read-only file system'"
  printf '   [H8] + docker compose exec %s touch /tmp/beweis  (muss gelingen)\n' "${DIENST}"
  dc exec -T "${DIENST}" touch /tmp/beweis && note "ok, /tmp ist beschreibbar (tmpfs)"
  local c; c="$(cid)"
  [ -n "${c}" ] && lauf H8 sudo docker inspect --format \
    'User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}} Policy={{.HostConfig.RestartPolicy.Name}} CapDrop={{.HostConfig.CapDrop}}' "${c}"
}

cmd_id() {
  say "Kennungen"
  note "Container-ID: $(cid)"
  note "Image-ID    : $(imid)"
  note "Hostport    : 127.0.0.1:${HOSTPORT}  ->  Container 8000"
}

cmd_hilfe() {
  # Kopfkommentar ausgeben, bis zur ersten Codezeile.
  awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
  printf '\nProjekt: %s\nHostport: %s\n' "${PROJ}" "${HOSTPORT}"
}

case "${1:-hilfe}" in
  start)  cmd_start;;
  stop)   cmd_stop;;
  an|start-wieder) cmd_an;;
  neu)    cmd_neu;;
  weg|down) cmd_weg;;
  status) cmd_status;;
  logs)   cmd_logs;;
  rechte) cmd_rechte;;
  id)     cmd_id;;
  hilfe|-h|--help) cmd_hilfe;;
  *) printf 'Unbekannt: %s\n\n' "$1" >&2; cmd_hilfe; exit 1;;
esac
