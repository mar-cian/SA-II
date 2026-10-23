# Qwen-Entscheidungsprotokoll

Auftrag 3 verlangt mindestens drei wesentliche Qwen-Vorschlaege, je mit Prompt,
kurzem Antwortauszug, eigener Pruefung und Entscheidung. Mindestens einen
Vorschlag musst du fachlich korrigieren oder begruendet ablehnen.

**Grundregel aus dem Aufgabenblatt: Erfinde keinen AI-Fehler.** Trage hier nur
ein, was Qwen tatsaechlich geantwortet hat. Sind alle Vorschlaege passend,
pruefe bewusst eine fragwuerdige Alternative und dokumentiere, wie Qwen damit
umgeht. Dafuer liegen unten fertige Prompts bereit.

## Weg A: ueber Open WebUI, Beleg von Hand

Fuer Auftrag 3 ist das zulaessig. Qwen ist hier Engineering-Assistent, ein
programmatischer Aufruf im laufenden Produkt wird ausdruecklich nicht verlangt.
Das Verbot von manuellem Kopieren betraf Phase D von Auftrag 2.

```bash
cd ~/workspace/AI-Docker-Lab/03_ServiceClock
chmod +x scripts/*.sh
cat prompts/03_healthcheck_curl.txt      # Text zum Kopieren
```

Prompt in Open WebUI einfuegen, Modell `coder-schnell` waehlen, senden. Antwort
mit der Kopierschaltflaeche uebernehmen und ablegen:

```bash
./scripts/beleg-qwen.sh healthcheck prompts/03_healthcheck_curl.txt
# Antwort einfuegen, dann Strg-D in einer leeren Zeile
```

Das schreibt Prompt und Antwort mit Zeitstempel, Modell und Quellvermerk nach
`belege/qwen/`. Im Protokoll festhalten, dass die Anfragen ueber Open WebUI
liefen; das ist ehrlich und zulaessig.

Fuer den Review die Dateien mitgeben:

```bash
./scripts/review-prompt.sh       > /tmp/review_config.txt
./scripts/review-prompt.sh logik > /tmp/review_code.txt
cat /tmp/review_config.txt       # Inhalt in Open WebUI einfuegen
./scripts/beleg-qwen.sh review_config /tmp/review_config.txt
```

## Weg B: ueber die API, Beleg automatisch

```bash
cd ~/workspace/AI-Docker-Lab/03_ServiceClock
chmod +x scripts/*.sh

./scripts/frag-qwen.sh entwurf       prompts/01_entwurf.txt
./scripts/frag-qwen.sh healthcheck   prompts/03_healthcheck_curl.txt
./scripts/frag-qwen.sh rootbetrieb   prompts/04_root_betrieb.txt
./scripts/frag-qwen.sh portfreigabe  prompts/05_portfreigabe.txt

# Review der Konfiguration, passt bequem in 4096 Kontext
./scripts/review-prompt.sh | ./scripts/frag-qwen.sh review_config -

# Review des Codes. Ohne den CSS-Block, der fuer Security nichts hergibt,
# und mit groesserem Kontext, weil 10000 Zeichen in 4096 nicht hineinpassen.
./scripts/review-prompt.sh logik | NUM_CTX=8192 ./scripts/frag-qwen.sh review_code -
```

Die Prompt-Laengen kannst du vorher pruefen:

```bash
for w in config logik code alles; do
  printf '%-7s %6s Zeichen\n' "$w" "$(./scripts/review-prompt.sh $w 2>/dev/null | wc -c)"
done
```

Dass du den Kontext fuer den Code-Review von 4096 auf 8192 erhoeht hast,
gehoert ins Protokoll. Das Aufgabenblatt verlangt, Daten und Tokenlimit
sinnvoll abzustimmen und eine Erhoehung zu dokumentieren.

Jeder Aufruf legt Prompt und Antwort unveraendert unter
`belege/qwen/<zeitstempel>_<name>_prompt.txt` und `_antwort.md` ab. Damit ist
belegbar, dass die Antwort nicht nachtraeglich aufgeschrieben wurde.

Der Review ist bewusst geteilt: alle Dateien zusammen sind rund 14000 Zeichen
und sprengen das Kontextfenster von 4096, die Antwort waere gekuerzt. Getrennt
geprueft bleibt sie vollstaendig. Wird eine Antwort trotzdem abgeschnitten,
fordere laut Aufgabenblatt eine neue, kuerzere Diagnose an.

Ein zweites Modell zum Vergleich, optional:

```bash
./scripts/frag-qwen.sh review_genau prompts/03_healthcheck_curl.txt coder-genau
```

---

# Vorschlag 1

**Prompt** (Datei):

**Antwortauszug** (woertlich, gekuerzt):

```
```

**Eigene Pruefung** (stimmt das, womit habe ich es geprueft):

**Entscheidung:** umgesetzt / korrigiert / abgelehnt

**Begruendung:**

**Beleg** (Datei unter `belege/`, Befehl, Ergebnis):

---

# Vorschlag 2

**Prompt** (Datei):

**Antwortauszug:**

```
```

**Eigene Pruefung:**

**Entscheidung:** umgesetzt / korrigiert / abgelehnt

**Begruendung:**

**Beleg:**

---

# Vorschlag 3

**Prompt** (Datei):

**Antwortauszug:**

```
```

**Eigene Pruefung:**

**Entscheidung:** umgesetzt / korrigiert / abgelehnt

**Begruendung:**

**Beleg:**

---

# Woran du die Antworten misst

Zu den drei fragwuerdigen Alternativen, die das Aufgabenblatt nennt, hier die
nachpruefbaren Fakten. Sie sind dein Massstab, wenn du Qwens Antwort bewertest.

## a) Healthcheck mit curl (`prompts/03_healthcheck_curl.txt`)

**Fakt:** `python:3.12-slim` enthaelt kein `curl`. Ein Healthcheck mit `curl`
scheitert dauerhaft, der Container bleibt fuer immer `unhealthy`, obwohl die
Anwendung einwandfrei antwortet. Das ist der Klassiker, bei dem der
Health-Status etwas voellig anderes misst als die Funktion.

**Nachweis:**

```bash
sudo docker compose exec clock sh -c 'command -v curl || echo "kein curl im Image"'
sudo docker run --rm python:3.12-slim sh -c 'command -v curl || echo "kein curl im Basis-Image"'
```

**Richtige Loesung:** Probe mit der Standardbibliothek, so wie in der
`compose.yaml` umgesetzt:

```yaml
test: ["CMD", "python", "-c",
       "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
```

Akzeptiert Qwen den curl-Healthcheck, ist das dein zu korrigierender Vorschlag.
Lehnt Qwen ihn ab, dokumentiere das und nimm eine der anderen Alternativen.

## b) Root-Betrieb (`prompts/04_root_betrieb.txt`)

**Fakt:** Die Anwendung braucht keinen privilegierten Port und keinen
Schreibzugriff. Root im Container ist dieselbe UID 0 wie auf dem Host; bei einem
Ausbruch oder einer Fehlkonfiguration eines Mounts wirkt sie auch dort. Der
Komfortgewinn beim Entwickeln rechtfertigt das nicht, zumal `/tmp` als tmpfs
beschreibbar ist.

**Nachweis, dass es ohne Root funktioniert:**

```bash
sudo docker compose exec clock id                      # uid=10001, nicht 0
sudo docker compose exec clock sh -c 'touch /tmp/x && echo "tmpfs beschreibbar"'
sudo docker compose exec clock sh -c 'touch /app/x 2>&1 || echo "Rootfs ist read-only"'
curl -s -o /dev/null -w 'Anwendung antwortet trotzdem: HTTP %{http_code}\n' http://127.0.0.1:8083/health
```

## c) Unnoetige Portfreigabe (`prompts/05_portfreigabe.txt`)

**Fakt:** `ports: ["8083:8000"]` ohne Adresse bindet auf `0.0.0.0`, also auf
allen Schnittstellen. Die Anwendung hat keine Authentifizierung, damit sieht
jeder im Netz Name, Zeit und Zaehler. `EXPOSE` im Dockerfile ist dabei keine
Schutzmassnahme, sondern nur Dokumentation. Die engere Loesung ist die Bindung
auf Loopback plus ein SSH-Tunnel.

**Nachweis:**

```bash
sudo docker compose port clock 8000        # zeigt die wirksame Bindung
ss -ltn | grep 8083                        # 127.0.0.1 oder 0.0.0.0
```

## Weitere haeufige Fehlvorschlaege, falls du eine Reserve brauchst

| Vorschlag | Warum er nicht stimmt | Nachweis |
|---|---|---|
| `restart: always` statt `unless-stopped` | startet auch einen bewusst gestoppten Container wieder, ein gewolltes Stoppen ist dann nicht mehr moeglich | `docker compose stop`, danach `docker compose ps` |
| Volume fuer die Anwendung anlegen | sie haelt keine Nutzdaten, das Volume wuerde nur Schreibrechte auf dem Host verlangen | `docker inspect --format '{{.Mounts}}'` zeigt keine noetigen Mounts |
| `latest` statt fester Version im Basis-Image | Builds sind nicht mehr reproduzierbar | zwei Builds zu verschiedenen Zeiten vergleichen |
| `docker compose restart` nach Aenderung einer Compose-Variable | `restart` uebernimmt geaenderte Variablen nicht, dafuer braucht es `up -d` | Variable aendern, `restart`, dann `docker inspect .Config.Env` lesen |

---

# Abschliessende Bewertung

- **Wie nuetzlich war Qwen insgesamt:**
- **Wo lag es sachlich daneben:**
- **Was habe ich uebernommen und danach erneut getestet:**
- **Was habe ich abgelehnt und warum:**
- **Offene Punkte:**
