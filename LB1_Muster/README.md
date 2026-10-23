# LB1-Muster: die zwei technischen Fallen geloest

**Das ist keine Abgabe.** Es ist ein lauffaehiges Muster fuer die zwei Stellen,
an denen die Service Clock aus Auftrag 3 nicht uebernommen werden darf. Roboter
und Gestaltung sind absichtlich schlicht, laut 5.2 gibt aufwendige Gestaltung
keine Zusatzpunkte.

## Was hier geloest ist

### Falle 1: `<meta http-equiv="refresh">` statt Abfrage

Die Uhr aktualisiert sich durch Neuladen der Seite. Fuer eine Uhr ist das
richtig, hier macht es drei Anforderungen unerfuellbar:

- Ein Neuladen setzt die CSS-Animation und den Pause-Zustand zurueck (A2, T1).
- Bei gestopptem Server laedt die Seite gar nicht mehr. Sie kann dann weder
  "nicht erreichbar" melden noch alte Werte kennzeichnen (A4, T3).
- Ohne gehaltenen Zustand im Browser gibt es keine alten Werte, die man als
  veraltet markieren koennte (A4, R1).

Hier stattdessen `fetch` alle 5 s mit `AbortController` und 5 s Zeitlimit. Die
Seite bleibt stehen, nur die Werte wechseln.

### Falle 2: die eigene Content-Security-Policy blockiert das eigene Skript

`default-src 'none'` aus der Uhr sperrt auch selbst geschriebenes JavaScript.
Die Policy aufzuweichen waere der falsche Weg. Hier wird genau dieses eine
Skript ueber ein Nonce je Antwort erlaubt, dazu `connect-src 'self'` fuer
`fetch`. Siehe `_send()` in `app.py`.

## Ausprobieren: im Container

Das ist der Weg, der dem Pruefungsaufbau entspricht. Non-root, read-only,
Healthcheck und Restart Policy sind dieselben wie in der Service Clock, damit
A5 und T6 abgedeckt sind.

```bash
cd ~/workspace/AI-Docker-Lab/LB1_Muster

# Falls noch ein Prozess ohne Container auf demselben Port laeuft, erst beenden:
pgrep -af 'LB1_Muster/app.py'      # kill <PID>

HOSTPORT=8084 sudo docker compose up -d --build
sleep 12
sudo docker compose ps             # muss healthy zeigen
curl -sS -o /dev/null -w 'lokal HTTP %{http_code}\n' http://127.0.0.1:8084/
```

Rechte nachweisen, das ist T6 und H8:

```bash
sudo docker compose exec app id                                  # uid=10001
sudo docker compose exec app touch /beweis 2>&1 | head -1        # read-only
sudo docker compose exec app touch /tmp/beweis && echo '/tmp beschreibbar'
sudo docker inspect --format \
  'ReadOnly={{.HostConfig.ReadonlyRootfs}} User={{.Config.User}} Policy={{.HostConfig.RestartPolicy.Name}}' \
  "$(sudo docker compose ps -q app)"
```

Beenden und wieder starten:

```bash
sudo docker compose down           # fuer den T3-Test: Seite offen lassen
sudo docker compose up -d          # T4, Laufzeit beginnt neu
```

### Warum `BIND: "0.0.0.0"` im Container richtig ist

Auf dem Host laeuft dieses Programm absichtlich auf `127.0.0.1`. Im Container
dagegen muss es auf `0.0.0.0` hoeren, sonst ist es nur innerhalb des Containers
erreichbar und `docker-proxy` kommt nicht an es heran. Die Begrenzung auf den
lokalen Zugriff kommt an dieser Stelle nicht aus der Bindung im Programm,
sondern aus der Portveroeffentlichung `127.0.0.1:8084:8000` in der
`compose.yaml`. Das ist genau die Unterscheidung, die B5 und K7 pruefen: zwei
verschiedene Grenzen, eine im Container und eine auf dem Host.

## Ausprobieren: ohne Container

Schneller beim Entwickeln, weil kein Rebuild je Aenderung noetig ist. Fuer die
Abgabe reicht es nicht, dort sind Healthcheck und Restart Policy gefordert.

```bash
cd ~/workspace/AI-Docker-Lab/LB1_Muster
PORT=8099 python3 app.py
```

Dann `http://127.0.0.1:8099` im Browser auf der VM. Mit Strg-C beenden, die Seite offen
lassen: nach hoechstens 5 s steht dort "nicht erreichbar", die Serverwerte sind
durchgestrichen und der Hinweis nennt den Stand der letzten Antwort. Der
Roboter bewegt sich weiter. Danach wieder starten, die Laufzeit beginnt neu.

## Nachgewiesen

`test_muster.py` prueft das in Chromium, inklusive Serverstopp und Neustart:

```bash
python3 -I test_muster.py
```

Ergebnis des letzten Laufs, alle Pruefungen bestanden:

| Vorgabe | Gemessen |
|---|---|
| CSP erlaubt das eigene Skript | keine Verletzung in der Konsole |
| T1 Start, Pause, Auswahl ohne Neuladen | bestaetigt, Pause behaelt die Uebung |
| T2 Laufzeit steigt, Pruefzeitpunkt aktualisiert | 1,7 s auf 6,7 s |
| T3 Ausfall nach etwa 15 s erkannt | 5,0 s im schlechtesten Fall |
| T3 alte Werte gekennzeichnet | sichtbarer Hinweis mit Uhrzeit |
| T3 Roboter laeuft weiter | Animation blieb `running` |
| T4 wieder erkannt, Laufzeit beginnt neu | 4,6 s, 10,8 s auf 4,7 s |
| Zeitlimit je Anfrage | Abbruch nach 5,0 s, nicht erst nach der Antwort |

Der schlechteste Fall hat zwei Varianten. Bei einem gestoppten Server lehnt das
Betriebssystem die Verbindung sofort ab, erkannt wird der Ausfall also nach
hoechstens einem Intervall, 5 s. Haengt der Server stattdessen, kommen die 5 s
Zeitlimit dazu, zusammen 10 s. Beides liegt unter den etwa 15 s aus T3.

## Uebernehmen in `04_Karate`

Drei Teile, in dieser Reihenfolge:

1. `STYLE` und `SCRIPT` sowie `render_page()` nach `04_Karate/app.py`
   uebernehmen und die alte `render_page()` samt der Zeile
   `<meta http-equiv="refresh">` entfernen.
2. In `_send()` die Policy aus diesem Muster uebernehmen und den Nonce
   durchreichen.
3. Deine `/api/info` behalten. Die Seite liest `application`, `uptime_seconds`
   und `time`, genau die Felder, die dein Endpunkt schon liefert.

`REFRESH_SECONDS` wird nicht mehr gebraucht, dafuer `POLL_MS` und `TIMEOUT_MS`.
Die Route `/langsam` ist nur fuer den Test des Zeitlimits da, nimm sie aus der
Abgabe heraus oder nenne sie im Abschnitt offene Punkte.

## Was du erklaeren musst

Das Muster nimmt dir die Technik ab, nicht das Verstaendnis. Auf diese drei
Fragen laufen R1, R2, B1 und B2 zu:

**Warum laeuft der Roboter weiter, wenn der Server steht?** Die Animation sind
CSS-Keyframes, die der Browser rechnet. Vom Server kommen nur die Werte im
Dashboard. Zwei getrennte Dinge in einer Seite.

**Woran erkennt das Dashboard den Ausfall?** An der fehlgeschlagenen Abfrage,
nicht an einem Statusfeld des Servers. Darum sind "Letzte Pruefung" und die
Serverwerte getrennt: der Pruefzeitpunkt wird bei jedem Versuch neu gesetzt,
auch beim gescheiterten, die Serverwerte bleiben auf dem letzten Erfolg stehen
und werden als veraltet gekennzeichnet. Ein Zeitstempel, der weiterlaeuft,
waehrend die Werte alt sind, ist der Unterschied zwischen "geprueft" und
"gueltig".

**Warum haelt Pause mit `animation-play-state` an und nicht durch Entfernen der
Klasse?** Entfernen setzt den Roboter in die Grundstellung zurueck. T1 verlangt
aber, dass die Bewegung anhaelt.

## Die dritte Falle

`expose-lab.sh` nimmt nur 8081, 8082 und 8083. Laut 5.2 stellt die Lehrperson
den Zugangsport bereit, einschliesslich Netzfreigabe und Nginx-Weiterleitung;
eine eigene Erweiterung des Skripts ist nicht verlangt. Du ordnest nur deinen
Container zu. Sobald du den Port kennst, zum Beispiel 8084:

```bash
cd ~/workspace/AI-Docker-Lab/04_Karate
sed -i 's/127\.0\.0\.1:[0-9]*:8000/127.0.0.1:8084:8000/' compose.yaml
grep ports: compose.yaml
sudo docker compose up -d --build
curl -sS -o /dev/null -w 'lokal HTTP %{http_code}\n' http://127.0.0.1:8084/
sudo docker compose ps
```

Danach pruefen, ob die Weiterleitung der Lehrperson greift:

```bash
curl -sS -o /dev/null -w 'ueber LAN HTTP %{http_code}\n' http://192.168.110.61:8084/
```

Antwortet das lokal mit 200 und ueber die LAN-Adresse nicht, liegt es an ihrer
Freigabe, nicht an deinem Container. Dieser Unterschied ist die Portkette aus
K7, H3 und B5, und du kannst ihn mit diesen zwei Aufrufen belegen.

Fuer die Abgabevorlage: `Browser auf Kali -> Nginx 192.168.110.61:8084 ->
127.0.0.1:8084 -> Container 8000 -> app.py`. Die Animation laeuft im Browser,
die Statusabfrage geht ueber die ganze Kette.

## Und die vierte

Der Code liegt per `COPY` im Image. Nach jeder Aenderung
`sudo docker compose up -d --build`, nicht `restart`. `restart` startet
denselben Prozess aus demselben Image neu und sieht deine Aenderung nicht. Das
ist R2, und der Beleg dafuer liegt schon vor: `/api/info` war nach einem
`git pull` ohne `--build` weiterhin 404, siehe
`belege/12_freigabe_nginx/05_test_ubuntu.log`.
