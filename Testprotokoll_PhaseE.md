# Testprotokoll Auftrag 2, Phase E

Ausfuellen waehrend der Durchfuehrung, nicht danach aus dem Gedaechtnis.
Befehle dazu: `Belege_PhaseE.md`.

**Regel fuer jede Zeile:** Beobachtung ist, was auf dem Bildschirm steht.
Vermutung ist, was ich daraus schliesse. Beweis ist ein reproduzierbarer Test.
Die drei nicht vermischen.

---

## Rahmen

| Feld | Wert |
|---|---|
| Name | Gian-Marco Rieder |
| Modul | SAII, Local AI Engineering, Auftrag 2 |
| Datum der Durchfuehrung | |
| Host (`hostname`, `uname -r`) | |
| Docker (`docker --version`) | |
| Compose (`docker compose version`) | |
| Ollama-Modelle (`ollama list`) | |
| Repo-Stand (`git rev-parse --short HEAD`) | |

## Uebersicht

| # | Test | Durchgefuehrt am | Ergebnis | Beleg |
|---|---|---|---|---|
| 1 | Unveraenderte Umgebung, AI analysiert echte Daten | | | |
| 2 | AI nicht erreichbar | | | |
| 3 | Datenerfassung gestoert | | | |
| 4 | Worker reparieren | | | |
| 5 | Fehlender Containerzustand | | | |

Ergebnis: bestanden / abweichend / offen.

---

# Test 1: Unveraenderte Umgebung

**Soll laut Aufgabenblatt:** `web` und `api` healthy, `worker` unhealthy mit
passenden Logzeilen. Qwen analysiert die echten, erfassten Daten.

- **Datum/Zeit (UTC):**
- **Ausgangslage:**

### Ist: Containerzustand

| Service | Prozesszustand | Health | Anzeige im Dashboard | Fehlerserie | Neustarts |
|---|---|---|---|---|---|
| api | | | | | |
| web | | | | | |
| worker | | | | | |

- **Messzeitpunkt und Datenalter laut Dashboard:**
- **Passende Logzeilen (woertlich, mit Zeitstempel):**

```
```

### Ist: AI-Analyse

- **Modell und Antwortdauer:**
- **Grundlage (Messzeitpunkt, Sequenznummer):**
- **Beobachtung laut Modell:**
- **Evidenz laut Modell:**
- **Vermutete Ursache laut Modell:**
- **Naechster Schritt laut Modell:**

**Eigene Pruefung der Modellaussage** (stimmt sie mit den Messdaten ueberein,
was ist belegt, was ist Vermutung, was ist falsch):

- **Beleg (Dateien):**
- **Wiederherstellung:** nicht noetig, kein Eingriff
- **Offene Einschraenkungen:**

---

# Test 2: AI nicht erreichbar

**Soll laut Aufgabenblatt:** Nur die Ollama-Zieladresse der eigenen Anwendung
temporaer auf einen unbenutzten lokalen Port setzen. Dashboard und Monitoring
bleiben benutzbar, AI ist eindeutig unavailable. Danach korrekte Adresse
wiederherstellen.

- **Datum/Zeit (UTC):**
- **Eingriff (genauer Befehl, geaenderte Variable, alter und neuer Wert):**
- **Was ausdruecklich NICHT angefasst wurde:**

### Ist

| Pruefung | Erwartet | Beobachtet |
|---|---|---|
| `/api/ai` Status | unavailable mit Begruendung | |
| `/api/state` erreichbar | ja, Zustaende unveraendert | |
| `/health` des Dashboards | HTTP 200, healthy | |
| Analyse anfordern | scheitert sauber, haengt nicht | |
| Antwortzeit beim Scheitern | wenige Sekunden | |

- **Wortlaut der Fehlermeldung im Dashboard:**
- **Ist die AI eindeutig als nicht verfuegbar gekennzeichnet, oder koennte man
  sie fuer gesund halten:**
- **Beleg (Dateien):**
- **Wiederherstellung (Befehl, Kontrolle, Zeitpunkt):**
- **Zustand nach der Wiederherstellung:**
- **Offene Einschraenkungen:**

---

# Test 3: Datenerfassung gestoert

**Soll laut Aufgabenblatt:** Collector beenden oder den Datenzugriff gezielt
unterbrechen. Alte Daten duerfen nicht als frisch oder gesund erscheinen.
Danach wiederherstellen.

- **Datum/Zeit (UTC):**
- **Art der Stoerung (Dienst beendet / Zugriff unterbrochen):**
- **Eingriff (genauer Befehl):**

### Ist

| Zeitpunkt nach dem Eingriff | Datenalter | Anzeige der Services | Dashboard-Health |
|---|---|---|---|
| sofort | | | |
| nach ca. 15 s | | | |
| nach ca. 30 s | | | |

- **Ab welchem Alter wechselt die Anzeige auf "nicht ermittelbar":**
- **Wird der zuletzt bekannte Wert noch gezeigt, und ist er klar als
  "zuletzt bekannt" und nicht als Istzustand gekennzeichnet:**
- **Verhalten bei einer AI-Analyse waehrend der Stoerung:**
- **Exit-Code von `check-snapshot.sh`:**
- **Beleg (Dateien):**
- **Wiederherstellung (Befehl, Kontrolle, Zeitpunkt):**
- **Zustand nach der Wiederherstellung (Sequenznummer laeuft wieder):**
- **Offene Einschraenkungen:**

---

# Test 4: Worker reparieren

**Soll laut Aufgabenblatt:** Hypothese durch Vergleich von Route und
Konfiguration pruefen. Kleinste notwendige Aenderung vornehmen. Neue
Health-Pruefung und neue AI-Analyse belegen die Wirkung. Alte Logs zeitlich
einordnen.

- **Datum/Zeit (UTC):**

### Hypothese vor dem Eingriff

- **Hypothese (aus Phase A, Abschnitt Environment Variables):**
- **Wie sie geprueft wird (Route im Code gegen Wert in der Konfiguration):**

| Vergleich | Fundstelle (Datei, Zeile) | Wert |
|---|---|---|
| Route in der API | | |
| Konfiguration des Workers | | |
| Abweichung | | |

### Eingriff

- **Kleinste notwendige Aenderung (genau eine Sache):**
- **Begruendung, warum das die kleinste ist:**
- **Wurden Dateien der Vorgabe veraendert, oder nur die Laufzeitvariable:**
- **Prozessneustart, Containerneuerstellung oder beides, und warum:**

### Ist: Wirkung

| Pruefung | Vor dem Eingriff | Nach dem Eingriff |
|---|---|---|
| Prozesszustand worker | | |
| Health worker | | |
| Anzeige im Dashboard | | |
| Fehlerserie | | |
| Neue Logzeilen | | |

- **Zeitliche Einordnung der alten Logzeilen** (letzte Fehlerzeile um, erste
  Erfolgszeile um, Eingriff um):

```
```

- **Neue AI-Analyse nach dem Eingriff:**
  - Beobachtung:
  - Evidenz:
  - Vermutete Ursache:
  - Naechster Schritt:
- **Deckt sich die neue Analyse mit den Messdaten:**
- **Beleg (Dateien):**
- **Offene Einschraenkungen:**

---

# Test 5: Fehlender Containerzustand

**Soll laut Aufgabenblatt:** Fehlenden Containerzustand pruefen oder logisch
reproduzierbar testen. Niemals "keine Daten" als "alles gesund" werten.

- **Datum/Zeit (UTC):**
- **Vorgehen (Container entfernt oder gestoppt, welcher, mit welchem Befehl):**

### Ist

| Pruefung | Erwartet | Beobachtet |
|---|---|---|
| Anzeige des fehlenden Service | fehlend, mit Begruendung | |
| Anzeige der uebrigen Services | unveraendert | |
| Dashboard-Health | HTTP 200 | |
| Unterscheidung gestoppt gegen fehlend | zwei verschiedene Zustaende | |

- **Wird "keine Daten" irgendwo als gesund dargestellt:**
- **Wortlaut der Begruendung im Dashboard:**
- **Beleg (Dateien):**
- **Wiederherstellung (Befehl, Kontrolle, Zeitpunkt):**
- **Offene Einschraenkungen:**

---

# Gesamtbeurteilung

- **Was ist belegt:**
- **Was bleibt Vermutung:**
- **Was wurde nicht geprueft und warum:**
- **Bekannte Grenzen der Loesung:**
- **Was ich beim naechsten Mal anders machen wuerde:**
