# Befehle fuer die Belege, Auftrag 2 Phase E

Zum Formular `Testprotokoll_PhaseE.md`. Alle Befehle auf der Ubuntu-VM, aus
`~/workspace/AI-Docker-Lab/02_Monitoring`, sofern nicht anders angegeben.

## Wichtig vorab

**Reihenfolge einhalten.** Test 4 und Test 5 erstellen den Worker-Container neu
beziehungsweise entfernen ihn. Seine bisherigen Logzeilen sind danach weg, weil
Logs an die Lebensdauer des Containers gebunden sind. Die alten Logs also in
Test 1 sichern, bevor du Test 4 anfaengst.

**Lesende Befehle gegen die Laborumgebung sind unbedenklich.** `ps`, `logs` und
`inspect` veraendern nichts. Nur `up`, `down`, `rm` und `stop` tun das.

## Vorbereitung, einmal pro Sitzung

```bash
cd ~/workspace/AI-Docker-Lab/02_Monitoring
mkdir -p nachweise

# Kurzfassung des Zustands, wird unten mehrfach verwendet
kurz() { python3 -c "
import json,sys
d=json.load(sys.stdin)
print('datenlage', d.get('data_status'), '| alter', d.get('age_seconds'), 's')
for s in d.get('services', []):
    print(' ', s['service'], '->', s['status'], '|', (s.get('status_reason') or '')[:72])
"; }
```

Rahmenangaben fuer den Kopf des Protokolls:

```bash
{ hostname; uname -r; docker --version; docker compose version; } \
  | tee nachweise/00_umgebung.log
ollama list            | tee -a nachweise/00_umgebung.log
git rev-parse --short HEAD | tee -a nachweise/00_umgebung.log
```

---

# Test 1: Unveraenderte Umgebung

### Zustand der Laborcontainer (nur lesend)

```bash
cd ../01_Startumgebung
sudo docker compose ps -a | tee ../02_Monitoring/nachweise/01_ps.log

# Health getrennt vom Prozesszustand belegen
for s in api web worker; do
  echo "== $s =="
  sudo docker inspect --format '{{json .State.Health}}' "$(sudo docker compose ps -q $s)" \
    | python3 -m json.tool
done | tee ../02_Monitoring/nachweise/01_health.log

# ALTE WORKER-LOGS SICHERN, vor Test 4 unbedingt noetig
sudo docker compose logs --timestamps --tail 40 worker \
  | tee ../02_Monitoring/nachweise/01_worker_logs_vor_reparatur.log
cd ../02_Monitoring
```

### Eigene Erfassung und Anzeige

```bash
./collector/scripts/check-snapshot.sh --logs | tee nachweise/01_check_snapshot.log
echo "exit=${PIPESTATUS[0]}"

curl -fsS http://127.0.0.1:8090/api/state | tee nachweise/01_state.json | kurz
curl -fsS http://127.0.0.1:8090/health | python3 -m json.tool | tee nachweise/01_health_dashboard.json
```

### AI-Analyse auf echten Daten

```bash
curl -fsS http://127.0.0.1:8090/api/ai | python3 -m json.tool | tee nachweise/01_ai_status.json

curl -s -X POST http://127.0.0.1:8090/api/analyze \
  | tee nachweise/01_ai_analyse.json \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('modell', d.get('model'), '|', d.get('duration_ms'), 'ms | grundlage', d.get('based_on'))
for k,v in (d.get('sections') or {}).items(): print(f'--- {k} ---\n{v}')"
```

Fuer das Protokoll zusaetzlich einen Screenshot der Seite `http://127.0.0.1:8090`
mit sichtbarer AI-Karte.

**Wiederherstellung:** keine, es gab keinen Eingriff.

---

# Test 2: AI nicht erreichbar

Das Skript fuehrt Soll, Eingriff, Beobachtung, Beleg und Wiederherstellung
zusammen aus und schreibt ein Protokoll mit Zeitstempeln:

```bash
sudo DASHBOARD_URL=http://127.0.0.1:8090 ./ai-relay/scripts/faultcase-ai.sh
mv nachweis_ai_ausfall_*.log nachweise/
```

Wenn du es von Hand nachvollziehen willst:

```bash
# vorher
curl -fsS http://127.0.0.1:8090/api/ai | python3 -m json.tool | tee nachweise/02_ai_vorher.json

# Eingriff: NUR die Zieladresse der eigenen Anwendung, Port 9 ist unbenutzt.
# Ollama und das Relay werden nicht angefasst.
sudo AI_RELAY_URL=http://127.0.0.1:9 docker compose up -d
sleep 6

# Ist-Zustand
curl -fsS http://127.0.0.1:8090/api/ai    | python3 -m json.tool | tee nachweise/02_ai_ausfall.json
curl -fsS http://127.0.0.1:8090/api/state | tee nachweise/02_state_ausfall.json | kurz
curl -s -o /dev/null -w 'dashboard /health HTTP %{http_code}\n' http://127.0.0.1:8090/health \
  | tee nachweise/02_health_ausfall.log

# Analyse muss sauber scheitern und darf nicht haengen
curl -s -o nachweise/02_analyse_fehler.json \
  -w 'POST /api/analyze: HTTP %{http_code} nach %{time_total}s\n' \
  -X POST http://127.0.0.1:8090/api/analyze | tee nachweise/02_analyse_http.log
cat nachweise/02_analyse_fehler.json

# Wiederherstellung
sudo docker compose up -d
sleep 6
curl -fsS http://127.0.0.1:8090/api/ai | python3 -m json.tool | tee nachweise/02_ai_nachher.json
```

Zu belegen ist: AI eindeutig `unavailable` mit Begruendung, `/api/state`
unveraendert nutzbar, Dashboard-Health weiterhin 200.

---

# Test 3: Datenerfassung gestoert

Als Ganzes mit Protokoll:

```bash
sudo DASHBOARD_URL=http://127.0.0.1:8090/health ./collector/scripts/faultcase-collector.sh
mv nachweis_collector_ausfall_*.log nachweise/
```

Von Hand:

```bash
# vorher
./collector/scripts/check-snapshot.sh | tee nachweise/03_vorher.log

# Eingriff
date -u +%Y-%m-%dT%H:%M:%SZ | tee nachweise/03_eingriff.log
sudo systemctl stop hf-ops-collector

# Alterung ueber 35 s beobachten
for i in 1 2 3 4 5; do
  printf '%s  ' "$(date -u +%H:%M:%SZ)"
  ./collector/scripts/check-snapshot.sh 2>/dev/null | grep Datenalter
  sleep 7
done | tee nachweise/03_alterung.log

# Bewertung: Exit-Code 2 heisst veraltet
./collector/scripts/check-snapshot.sh | tee -a nachweise/03_alterung.log; echo "exit=${PIPESTATUS[0]}"
curl -fsS http://127.0.0.1:8090/api/state | tee nachweise/03_state_veraltet.json | kurz

# Analyse muss abgelehnt werden, nicht auf alten Daten rechnen
curl -s -X POST http://127.0.0.1:8090/api/analyze \
  | python3 -m json.tool | tee nachweise/03_analyse_abgelehnt.json

# Wiederherstellung
sudo systemctl start hf-ops-collector
sleep 8
./collector/scripts/check-snapshot.sh | tee nachweise/03_nachher.log; echo "exit=${PIPESTATUS[0]}"
```

Zu belegen ist: alte Daten erscheinen nicht als frisch oder gesund, der zuletzt
bekannte Wert bleibt erkennbar als "zuletzt bekannt", Sequenznummer laeuft nach
dem Start wieder.

---

# Test 4: Worker reparieren

### Hypothese pruefen, vor jedem Eingriff

```bash
grep -n 'jobs\|jobz\|JOB_PATH' \
  ../01_Startumgebung/api/app.py \
  ../01_Startumgebung/worker/app.py \
  ../01_Startumgebung/compose.yaml \
  | tee nachweise/04_vergleich_route_konfiguration.log

# tatsaechlich wirksamer Wert im laufenden Container, nicht nur in der Datei
sudo docker inspect --format '{{json .Config.Env}}' \
  "$(cd ../01_Startumgebung && sudo docker compose ps -q worker)" \
  | python3 -m json.tool | tee -a nachweise/04_vergleich_route_konfiguration.log
```

Damit hast du Fundstelle, Wert und Abweichung fuer die Tabelle im Protokoll.

### Zustand vor dem Eingriff

```bash
curl -fsS http://127.0.0.1:8090/api/state | tee nachweise/04_vorher.json | kurz
date -u +%Y-%m-%dT%H:%M:%SZ | tee nachweise/04_eingriff_zeit.log
```

Pruefe, dass `nachweise/01_worker_logs_vor_reparatur.log` existiert. Nach dem
naechsten Schritt sind diese Zeilen nicht mehr abrufbar.

### Kleinste notwendige Aenderung

Nur die Laufzeitvariable setzen, keine Datei der Vorgabe anfassen. Den Wert aus
deinem Vergleich oben einsetzen:

```bash
cd ../01_Startumgebung
sudo JOB_PATH=PFAD_AUS_DEINEM_VERGLEICH docker compose up -d worker
```

`up -d` ist noetig, nicht `restart`: eine geaenderte Compose-Variable wirkt erst
bei Containerneuerstellung. Genau dieser Unterschied gehoert ins Protokoll.

### Wirkung belegen

```bash
sleep 25
sudo docker compose ps -a | tee ../02_Monitoring/nachweise/04_nachher_ps.log
sudo docker inspect --format '{{json .State.Health}}' "$(sudo docker compose ps -q worker)" \
  | python3 -m json.tool | tee ../02_Monitoring/nachweise/04_nachher_health.log
sudo docker compose logs --timestamps --tail 20 worker \
  | tee ../02_Monitoring/nachweise/04_nachher_logs.log

cd ../02_Monitoring
./collector/scripts/check-snapshot.sh | tee nachweise/04_nachher_snapshot.log
curl -fsS http://127.0.0.1:8090/api/state | tee nachweise/04_nachher.json | kurz

# neue AI-Analyse als Beleg der Wirkung
curl -s -X POST http://127.0.0.1:8090/api/analyze \
  | python3 -m json.tool | tee nachweise/04_ai_nachher.json
```

### Alte Logs zeitlich einordnen

```bash
{ echo "letzte Fehlerzeile vor dem Eingriff:"
  grep ERROR nachweise/01_worker_logs_vor_reparatur.log | tail -1
  echo "Eingriff:"; cat nachweise/04_eingriff_zeit.log
  echo "erste Zeile nach dem Eingriff:"
  head -2 nachweise/04_nachher_logs.log
} | tee nachweise/04_zeitachse.log
```

**Zurueck in den Ausgangszustand**, falls du den Fehler fuer die Demonstration
wieder brauchst:

```bash
cd ../01_Startumgebung && sudo docker compose up -d worker && cd ../02_Monitoring
```

Ohne gesetzte Variable gilt wieder die Vorgabe aus der `compose.yaml`.

---

# Test 5: Fehlender Containerzustand

Zuletzt durchfuehren. Der Container wird entfernt, seine Logs sind danach weg.

```bash
# Eingriff: Container entfernen, nicht nur stoppen
cd ../01_Startumgebung
date -u +%Y-%m-%dT%H:%M:%SZ | tee ../02_Monitoring/nachweise/05_eingriff.log
sudo docker compose rm -sf worker
cd ../02_Monitoring
sleep 8

./collector/scripts/check-snapshot.sh | tee nachweise/05_fehlend.log
curl -fsS http://127.0.0.1:8090/api/state | tee nachweise/05_state_fehlend.json | kurz
curl -s -o /dev/null -w 'dashboard /health HTTP %{http_code}\n' http://127.0.0.1:8090/health \
  | tee -a nachweise/05_fehlend.log
```

Gegenprobe, dass gestoppt und fehlend zwei verschiedene Zustaende sind:

```bash
cd ../01_Startumgebung && sudo docker compose up -d worker && sleep 20
sudo docker compose stop worker && cd ../02_Monitoring && sleep 8
./collector/scripts/check-snapshot.sh | tee nachweise/05_gestoppt.log
```

Wiederherstellung:

```bash
cd ../01_Startumgebung && sudo docker compose up -d worker && cd ../02_Monitoring
sleep 25
./collector/scripts/check-snapshot.sh | tee nachweise/05_nachher.log
```

Zu belegen ist: der fehlende Service erscheint als `fehlend` mit Begruendung,
die uebrigen Services bleiben unveraendert, und nirgends wird "keine Daten" als
gesund dargestellt.

---

# Abschluss

```bash
ls -la nachweise/ | tee nachweise/99_dateiliste.log
```

Die Dateien unter `nachweise/` werden von der `.gitignore` nicht ausgeschlossen,
du kannst sie also mit `git add nachweise/` zur Abgabe committen.
