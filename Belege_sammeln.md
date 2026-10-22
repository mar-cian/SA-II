# Belege sammeln, Auftrag 2

Alle Nachweise landen in einem Ordner `belege/` im Repo-Wurzelverzeichnis und
lassen sich von dort als Ganzes committen. Erzeugt werden sie mit
`02_Monitoring/scripts/belege.sh`, einem Unterbefehl je Phase und Versuch.

Zum Ausfuellen gehoert `Testprotokoll_PhaseE.md`.

## Brauchst du Belege fuer die frueheren Phasen

Ja. Die Abgabe verlangt ausdruecklich "datierte statische Analyse vor Start,
Architektur- und Security-Vergleich, Vorher/Nachher-Belege, AI- und
Collector-Ausfallnachweis". Das meiste hast du bereits, es muss nur eingesammelt
und datiert werden:

| Phase | Was als Beleg zaehlt | Woher |
|---|---|---|
| A, statische Analyse | deine Analyse plus Nachweis, dass sie vor dem ersten Start entstand | `belege.sh phase-a` |
| B, erster Start | Containerzustand, Health, Logs der unveraenderten Umgebung | `belege.sh phase-b` plus deine PDF vom ersten Start |
| C, eigenes Monitoring | Anzeige auf echten Daten, kein Docker-Socket im Container | `belege.sh phase-c` |
| D, AI | echte Modellanfrage aus dem Programm, Netzgrenze, Allowlist | `belege.sh phase-d` |
| E, Fehlerfaelle | fuenf Versuche mit Soll, Ist, Beleg, Wiederherstellung | `belege.sh test1` bis `test5` |
| F, Security | Befunde zu den sechs Fragen, Antworten von Hand | `belege.sh phase-f` plus `Phase_F_Security.md` |

## Ordnerstruktur

```
belege/
  README.md                          Inhaltsverzeichnis, vom Skript erzeugt
  00_rahmen/                         Host, Werkzeuge, Modelle, Git-Stand, Dienste
  01_phaseA_statische_analyse/
  02_phaseB_erster_start/
  03_phaseC_eigenes_monitoring/
  04_phaseD_ai/
  05_test1_unveraenderte_umgebung/
  06_test2_ai_nicht_erreichbar/
  07_test3_erfassung_gestoert/
  08_test4_worker_repariert/
  09_test5_container_fehlt/
```

Jede Datei traegt im Kopf den Zeitpunkt, den ausgefuehrten Befehl und den
Exit-Code. Ein fehlgeschlagener Befehl wird mitprotokolliert, nicht verschluckt:
auch das ist ein Beleg.

---

# Ablauf

Alles aus `~/workspace/AI-Docker-Lab/02_Monitoring`. Pro Schritt erst den Befehl,
dann das Formular ausfuellen, bevor du weitergehst.

## Schritt 0: vorbereiten

```bash
cd ~/workspace/AI-Docker-Lab/02_Monitoring
chmod +x scripts/belege.sh
./scripts/belege.sh hilfe
```

Die Kopfzeilen zeigen, wohin geschrieben wird und welche Adressen verwendet
werden. Stimmen Labor- und Dashboard-Pfad, weiter.

## Schritt 1: Rahmen

```bash
./scripts/belege.sh rahmen
```

Danach im Formular den Kopfteil ausfuellen: Host, Docker-Version,
Compose-Version, Modelle, Repo-Stand. Die Werte stehen in
`belege/00_rahmen/umgebung.log` und `git_stand.log`.

## Schritt 2: Phase A

```bash
./scripts/belege.sh phase-a
```

Lies `belege/01_phaseA_statische_analyse/zeitnachweis.log`. Liegt der
Zeitstempel deiner Analyse vor dem Zeitstempel deines ersten Starts, ist der
Checkpoint belegt. Wenn nicht, benenne das im Protokoll ehrlich, statt ein
Datum zu behaupten.

## Schritt 3: Phase B

```bash
./scripts/belege.sh phase-b
```

Erfasst den Zustand der unveraenderten Umgebung, ohne einzugreifen. Wichtig ist
`logs_worker_vor_reparatur.log`: diese Zeilen brauchst du in Versuch 4 fuer die
zeitliche Einordnung, und nach der Containerneuerstellung sind sie weg.

Lege die PDF-Nachweise deines ersten Starts vom Mac dazu:

```
belege/02_phaseB_erster_start/
```

## Schritt 4: Phase C

```bash
./scripts/belege.sh phase-c
```

Belegt unter anderem, dass der Dashboard-Container keinen Docker-Socket hat.
Mach zusaetzlich einen Screenshot von `http://127.0.0.1:8090` und lege ihn als
`belege/03_phaseC_eigenes_monitoring/dashboard_screenshot.png` ab.

## Schritt 5: Phase D

```bash
./scripts/belege.sh phase-d
```

Dauert einige Sekunden, weil eine echte Modellanfrage laeuft. Danach stehen in
`ai_analyse_lesbar.log` die vier Elemente. Bewerte sie im Formular selbst: was
ist durch die Messdaten belegt, was ist Vermutung, was ist falsch.

## Schritt 6: Versuch 1

```bash
./scripts/belege.sh test1
```

Soll: `api` und `web` gesund, `worker` fehlerhaft mit passenden Logzeilen, die
AI analysiert diese echten Daten.

## Schritt 7: Versuch 2, AI nicht erreichbar

```bash
./scripts/belege.sh test2
```

Greift ein und stellt selbst wieder her. Umgebogen wird nur die Zieladresse der
eigenen Anwendung auf einen unbenutzten Port. Ollama und das Relay bleiben
unberuehrt. Das Protokoll mit Zeitstempeln liegt danach im Ordner.

Zu belegen: AI eindeutig `unavailable` mit Begruendung, `/api/state` weiter
nutzbar, Dashboard-Health weiterhin 200.

## Schritt 8: Versuch 3, Datenerfassung gestoert

```bash
./scripts/belege.sh test3
```

Beendet den Collector, beobachtet die Alterung, belegt, dass alte Daten nicht
als frisch oder gesund erscheinen, und startet ihn wieder.

## Schritt 9: Versuch 4, Worker reparieren

Drei Teile, dazwischen arbeitest du selbst.

```bash
# 9a) Hypothese pruefen, noch kein Eingriff
./scripts/belege.sh test4-vorher
```

Jetzt im Formular die Vergleichstabelle ausfuellen: Route im Code, Wert in der
Konfiguration, Abweichung. Die Fundstellen stehen in
`vergleich_route_konfiguration.log`, der tatsaechlich wirksame Wert in
`wirksamer_wert.json`.

```bash
# 9b) kleinste notwendige Aenderung, nur die Laufzeitvariable
cd ../01_Startumgebung
sudo JOB_PATH=PFAD_AUS_DEINEM_VERGLEICH docker compose up -d worker
cd ../02_Monitoring
```

`up -d`, nicht `restart`: eine geaenderte Compose-Variable wirkt erst bei
Containerneuerstellung. Genau dieser Unterschied gehoert ins Protokoll.

```bash
# 9c) Wirkung belegen, wartet 25 s auf den Healthcheck
./scripts/belege.sh test4-nachher
```

Erzeugt auch `zeitachse.log` mit letzter Fehlerzeile, Eingriffszeitpunkt und
erster Zeile danach.

Willst du den Fehler fuer die Kurzdemonstration wieder herstellen:

```bash
cd ../01_Startumgebung && sudo docker compose up -d worker && cd ../02_Monitoring
```

## Schritt 10: Versuch 5, fehlender Container

Zuletzt. Der Worker-Container wird entfernt, seine Logzeilen sind danach weg.

```bash
./scripts/belege.sh test5
```

Macht auch die Gegenprobe: erst entfernt, also `fehlend`, dann gestoppt, also
`gestoppt`. Erst beides zusammen belegt, dass dein Dashboard die Zustaende
unterscheidet und "keine Daten" nirgends als gesund durchgeht. Stellt am Ende
wieder her.

## Schritt 11: Inhaltsverzeichnis

```bash
./scripts/belege.sh index
cat ../belege/README.md
```

## Schritt 12: ins Repo

```bash
cd ~/workspace/AI-Docker-Lab
git add belege/ Testprotokoll_PhaseE.md
git status --short
git commit -m "Belege und Testprotokoll Auftrag 2"
git push
```

Vorher kurz durchsehen, dass keine Zugangsdaten in den Logs stehen. Die
`.gitignore` haelt `.env`, Schluessel und Caches draussen, aber sie liest keine
Logdateien mit.

---

# Abkuerzung

Alles ohne Eingriff in einem Durchgang:

```bash
./scripts/belege.sh alles-ohne-eingriff
```

Das deckt Rahmen, Phase A bis D, Versuch 1 und das Inhaltsverzeichnis ab. Die
Versuche 2 bis 5 bleiben einzeln, weil sie eingreifen und du dazwischen
beobachten und notieren musst.

---

# Was das Skript nicht erledigt

- **Screenshots.** Mindestens einen von der Dashboard-Seite mit sichtbarer
  AI-Karte, am besten je einen im Normalzustand und waehrend eines Fehlerfalls.
- **Die PDF vom ersten Start.** Die liegt auf dem Mac, lege sie unter
  `belege/02_phaseB_erster_start/` ab.
- **Die Antworten zu Phase F.** Die Befunde sammelt `belege.sh phase-f`, die
  sechs Fragen und das Material dazu stehen in `Phase_F_Security.md`. Die
  Antworten gehoeren in deine eigenen Worte, du verteidigst sie in der Abnahme.
- **Die Bewertung der Modellantwort.** Ob die AI richtig lag, entscheidest du,
  nicht das Skript.
