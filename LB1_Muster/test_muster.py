#!/usr/bin/env python3
"""Prueft das Muster in einem echten Browser gegen die Vorgaben T1 bis T4.

Der Test startet app.py als eigenen Prozess, laedt die Seite in Chromium,
beendet den Server mitten im Betrieb und startet ihn wieder. Er belegt damit
genau das, was mit <meta http-equiv="refresh"> nicht moeglich waere.

Aufruf:   python3 -I test_muster.py
"""
from __future__ import annotations

import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

HIER = Path(__file__).resolve().parent
PORT = int(os.getenv("TESTPORT", "8099"))
URL = f"http://127.0.0.1:{PORT}/"
CHROME = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
POLL_MS = 5000
TIMEOUT_MS = 5000

fehler: list[str] = []


def pruefe(bedingung: bool, text: str) -> None:
    print(("  OK   " if bedingung else "  FEHL ") + text, flush=True)
    if not bedingung:
        fehler.append(text)


def server_starten() -> subprocess.Popen:
    proc = subprocess.Popen(
        [sys.executable, str(HIER / "app.py")],
        env={**os.environ, "PORT": str(PORT), "POLL_MS": str(POLL_MS),
             "TIMEOUT_MS": str(TIMEOUT_MS)},
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try:
            urllib.request.urlopen(URL + "health", timeout=1).read()
            return proc
        except (urllib.error.URLError, OSError):
            time.sleep(0.2)
    raise SystemExit("Server startet nicht")


def server_beenden(proc: subprocess.Popen) -> None:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def warte_auf(seite, lese, soll, grenze_s: float) -> float:
    """Wartet, bis lese() den Sollwert liefert. Gibt die Dauer zurueck."""
    start = time.monotonic()
    while time.monotonic() - start < grenze_s:
        if lese(seite) == soll:
            return time.monotonic() - start
        seite.wait_for_timeout(250)
    return float("inf")


def verbindung(seite) -> str:
    return seite.inner_text("#verbindung").strip()


def main() -> int:
    proc = server_starten()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=CHROME)
        seite = browser.new_page()
        konsolenfehler: list[str] = []
        seite.on("console", lambda m: konsolenfehler.append(m.text)
                 if m.type == "error" else None)
        seite.goto(URL, wait_until="load")
        seite.wait_for_timeout(1500)

        print("\n== Grundlage: CSP erlaubt das eigene Skript")
        pruefe(seite.evaluate("typeof window.fetch === 'function'"),
               "Seite geladen")
        pruefe(not [k for k in konsolenfehler if "Content Security" in k
                    or "Refused to execute" in k],
               "keine CSP-Verletzung in der Konsole")
        pruefe(verbindung(seite) == "erreichbar",
               "erste Abfrage war erfolgreich")

        print("\n== T1: zwei Uebungen, Start, Pause, Auswahl ohne Neuladen")
        seite.evaluate("window.__keinNeuladen = true")
        arm = "#roboter .arm.r"
        bein = "#roboter .bein.r"
        lauf = ("(s) => getComputedStyle(document.querySelector(s))"
                ".animationPlayState")
        name = ("(s) => getComputedStyle(document.querySelector(s))"
                ".animationName")

        pruefe(seite.evaluate(lauf, arm) == "paused",
               "vor dem Start ist die Bewegung angehalten")
        seite.click("#start")
        pruefe(seite.evaluate(lauf, arm) == "running",
               "Start setzt die Bewegung in Gang")
        pruefe(seite.evaluate(name, arm) == "schlag",
               "Uebung Schlag bewegt den Arm")

        seite.click('[data-uebung="tritt"]')
        pruefe(seite.evaluate(name, bein) == "tritt",
               "Umschalten auf Tritt bewegt das Bein")
        pruefe(seite.evaluate(lauf, bein) == "running",
               "nach dem Umschalten laeuft die Bewegung weiter")

        seite.click("#start")
        pruefe(seite.evaluate(lauf, bein) == "paused",
               "Pause haelt die Bewegung an")
        pruefe(seite.evaluate(name, bein) == "tritt",
               "Pause behaelt die gewaehlte Uebung, springt nicht zurueck")
        seite.click("#start")

        pruefe(seite.evaluate("window.__keinNeuladen === true"),
               "keine der Bedienungen hat die Seite neu geladen")

        print("\n== T2: Serverdaten werden aktualisiert")
        laufzeit1 = seite.inner_text("#laufzeit")
        geprueft1 = seite.inner_text("#geprueft")
        seite.wait_for_timeout(POLL_MS + 2500)
        laufzeit2 = seite.inner_text("#laufzeit")
        geprueft2 = seite.inner_text("#geprueft")
        zahl = lambda t: float(t.replace(" s", "").strip())
        pruefe(zahl(laufzeit2) > zahl(laufzeit1),
               f"Server-Laufzeit steigt ({laufzeit1} -> {laufzeit2})")
        pruefe(geprueft2 != geprueft1,
               f"Pruefzeitpunkt aktualisiert sich ({geprueft1} -> {geprueft2})")
        pruefe("veraltet" not in seite.get_attribute("#status", "class"),
               "im Normalbetrieb sind die Werte nicht als veraltet markiert")

        print("\n== T3: Server gestoppt, Seite bleibt offen")
        # Der schlechteste Fall ist ein Stopp unmittelbar NACH einer
        # erfolgreichen Abfrage: dann liegt das volle Intervall davor.
        # Deshalb erst auf eine frische Abfrage warten und ab dem Stopp messen.
        vorher = seite.inner_text("#geprueft")
        for _ in range(80):
            if seite.inner_text("#geprueft") != vorher:
                break
            seite.wait_for_timeout(250)
        letzte_laufzeit = seite.inner_text("#laufzeit")
        t_stop = time.monotonic()
        server_beenden(proc)
        warte_auf(seite, verbindung, "nicht erreichbar", 25)
        dauer = time.monotonic() - t_stop
        pruefe(verbindung(seite) == "nicht erreichbar", "Ausfall wird gemeldet")
        pruefe(dauer <= 15.0,
               f"Ausfall nach {dauer:.1f} s erkannt (schlechtester Fall), Grenze 15 s")
        pruefe("veraltet" in seite.get_attribute("#status", "class"),
               "alte Werte sind als veraltet gekennzeichnet")
        hinweis = seite.inner_text("#alterhinweis")
        pruefe("veraltet" in hinweis.lower() and "letzte antwort" in hinweis.lower(),
               f"Hinweistext nennt den Stand: {hinweis!r}")
        pruefe(seite.inner_text("#laufzeit") == letzte_laufzeit,
               "der letzte bekannte Wert bleibt sichtbar, statt zu verschwinden")
        pruefe(seite.is_visible("#alterhinweis"),
               "der Hinweis ist auch sichtbar, nicht nur im Markup")
        pruefe(seite.evaluate(lauf, bein) == "running",
               "der Roboter bewegt sich trotz Serverausfall weiter")

        print("\n== T4: Server wieder gestartet")
        proc = server_starten()
        dauer = warte_auf(seite, verbindung, "erreichbar", 20)
        pruefe(dauer <= 15.0, f"wieder erkannt nach {dauer:.1f} s")
        pruefe("veraltet" not in seite.get_attribute("#status", "class"),
               "die Veraltet-Kennzeichnung verschwindet wieder")
        neu = zahl(seite.inner_text("#laufzeit"))
        pruefe(neu < zahl(letzte_laufzeit),
               f"Server-Laufzeit beginnt neu ({letzte_laufzeit} -> {neu} s)")

        print("\n== Zeitlimit je Anfrage")
        t0 = time.monotonic()
        abgebrochen = seite.evaluate(
            """async (grenze) => {
                 const a = new AbortController();
                 const w = setTimeout(() => a.abort(), grenze);
                 try { await fetch('/langsam', {signal: a.signal}); return 'antwort'; }
                 catch (e) { return e.name; }
                 finally { clearTimeout(w); }
               }""", TIMEOUT_MS)
        gedauert = time.monotonic() - t0
        pruefe(abgebrochen == "AbortError",
               "eine zu langsame Antwort wird abgebrochen")
        pruefe(gedauert < TIMEOUT_MS / 1000 + 2,
               f"Abbruch nach {gedauert:.1f} s, nicht erst nach der Antwort")

        browser.close()
    server_beenden(proc)

    print("\n" + "=" * 60)
    if fehler:
        print(f"{len(fehler)} Pruefung(en) fehlgeschlagen:")
        for f in fehler:
            print("  - " + f)
        return 1
    print("Alle Pruefungen bestanden.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
