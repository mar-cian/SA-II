#!/usr/bin/env python3
"""Lauffaehiges Muster fuer die zwei technischen Fallen der LB1.

Dieses Programm ist KEINE Abgabe. Es ist ein Muster, das die beiden Stellen
loest, an denen die Service Clock aus Auftrag 3 nicht uebernommen werden darf:

  1. Die Uhr aktualisiert sich mit <meta http-equiv="refresh">. Ein Neuladen
     setzt die CSS-Animation und den Pause-Zustand zurueck, und bei einem
     Serverausfall laedt die Seite gar nicht mehr. Dann kann sie weder
     "nicht erreichbar" melden noch alte Werte kennzeichnen.
     Hier stattdessen: fetch im Intervall, Seite bleibt stehen.

  2. Eine Content-Security-Policy mit default-src 'none' blockiert auch
     eigenes JavaScript. Hier mit einem Nonce je Antwort erlaubt, statt die
     Policy aufzuweichen.

Die Endpunkte /api/info und /health haben denselben Vertrag wie die Service
Clock, damit die Seite dort unveraendert laeuft.

Start:   python3 app.py            (hoert auf 127.0.0.1:8099)
         PORT=9000 python3 app.py
"""
from __future__ import annotations

import base64
import datetime as dt
import html
import json
import os
import secrets
import signal
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_NAME = os.getenv("APP_NAME") or "HF Karate Robot"
PORT = int(os.getenv("PORT", "8099"))
BIND = os.getenv("BIND", "127.0.0.1")
STARTED_MONO = time.monotonic()
STARTED_AT = dt.datetime.now(dt.timezone.utc)

# Abfrageintervall und Zeitlimit je Anfrage, beide aus der Vorgabe 5.2.
# Damit ist der schlechteste Fall bis zur Erkennung 5 s Wartezeit plus 5 s
# Zeitlimit, also 10 s. Die Vorgabe aus T3 erlaubt etwa 15 s.
POLL_MS = int(os.getenv("POLL_MS", "5000"))
TIMEOUT_MS = int(os.getenv("TIMEOUT_MS", "5000"))


def uptime() -> float:
    return round(time.monotonic() - STARTED_MONO, 1)


def esc(value) -> str:
    if value is None:
        return "-"
    return html.escape(str(value), quote=True)


STYLE = """
:root{--bg:#f6f7f9;--card:#fff;--fg:#14171c;--muted:#5c6570;--line:#dfe3e8;
--ok:#1a7f46;--warn:#9a6700;--bad:#b3261e;--haut:#f0c59a;--anzug:#2f6fdb}
@media (prefers-color-scheme:dark){:root{--bg:#14171c;--card:#1c2026;--fg:#e9ecef;
--muted:#9aa4af;--line:#2c323a;--ok:#4ac07c;--warn:#e0a83a;--bad:#ff6b5e}}
*{box-sizing:border-box}
body{margin:0;padding:28px 16px;background:var(--bg);color:var(--fg);
font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:620px;margin:0 auto;display:grid;gap:16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:20px 22px}
h1{font-size:20px;margin:0 0 2px}
h2{font-size:14px;margin:0 0 14px;color:var(--muted);font-weight:600;
text-transform:uppercase;letter-spacing:.04em}
.sub{color:var(--muted);font-size:13px;margin:0 0 16px}

/* Buehne und Roboter: nur CSS, keine Grafikdateien. */
.buehne{background:#fafbfc;border:1px solid var(--line);border-radius:8px;
height:210px;position:relative;overflow:hidden}
@media (prefers-color-scheme:dark){.buehne{background:#171b21}}
.boden{position:absolute;left:0;right:0;bottom:34px;height:1px;background:var(--line)}
.roboter{position:absolute;left:50%;bottom:34px;width:120px;height:150px;
margin-left:-60px}
.kopf{position:absolute;left:38px;top:0;width:44px;height:38px;border-radius:8px;
background:var(--anzug)}
.auge{position:absolute;top:14px;width:7px;height:7px;border-radius:50%;background:#fff}
.auge.l{left:48px}
.auge.r{left:66px}
.rumpf{position:absolute;left:40px;top:40px;width:40px;height:58px;border-radius:7px;
background:var(--anzug)}
.guertel{position:absolute;left:40px;top:92px;width:40px;height:7px;background:#14171c}
.arm{position:absolute;top:46px;width:34px;height:12px;border-radius:6px;
background:var(--haut);transform-origin:left center}
.arm.l{left:14px;transform:rotate(150deg);transform-origin:right center}
.arm.r{left:76px;transform:rotate(-8deg)}
.bein{position:absolute;top:99px;width:14px;height:50px;border-radius:6px;
background:#3c4654;transform-origin:top center}
.bein.l{left:44px}
.bein.r{left:64px}

/* Die Animation haengt an der gewaehlten Uebung, nicht am Startknopf. */
.uebung-schlag .arm.r{animation:schlag .55s ease-in-out infinite}
.uebung-tritt  .bein.r{animation:tritt .7s ease-in-out infinite}
@keyframes schlag{
  0%,100%{transform:rotate(-8deg) scaleX(1)}
  45%    {transform:rotate(-8deg) scaleX(1.75)}
}
@keyframes tritt{
  0%,100%{transform:rotate(0deg)}
  50%    {transform:rotate(-78deg)}
}
/* Pause haelt die Bewegung an der Stelle an, statt sie zurueckzusetzen.
   Das Entfernen der Klasse wuerde den Roboter in die Grundstellung springen
   lassen, und T1 verlangt ausdruecklich ein Anhalten. */
.pausiert .arm.r,.pausiert .bein.r{animation-play-state:paused}

.steuerung{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
button{font:inherit;font-size:14px;padding:7px 14px;border-radius:7px;
border:1px solid var(--line);background:var(--card);color:var(--fg);cursor:pointer}
button[aria-pressed="true"]{border-color:var(--anzug);color:var(--anzug);font-weight:600}
button:focus-visible{outline:2px solid var(--anzug);outline-offset:2px}
.hinweis{margin:10px 0 0;font-size:12px;color:var(--muted)}

dl{display:grid;grid-template-columns:auto 1fr;gap:7px 16px;margin:0;font-size:13px}
dt{color:var(--muted)}
dd{margin:0;font-variant-numeric:tabular-nums}
.pill{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;
font-weight:600;border:1px solid}
.v-ok{color:var(--ok);border-color:var(--ok);background:rgba(74,192,124,.12)}
.v-weg{color:var(--bad);border-color:var(--bad);background:rgba(255,107,94,.12)}
.veraltet dd.serverwert{color:var(--warn);text-decoration:line-through}
.alterhinweis{margin:12px 0 0;font-size:13px;color:var(--warn);display:none}
.veraltet .alterhinweis{display:block}
footer{font-size:12px;color:var(--muted);text-align:center}
"""

SCRIPT = """
'use strict';
// Werte kommen aus dem Server, damit Vorgabe und Anzeige nicht auseinanderlaufen.
const INTERVALL = Number(document.body.dataset.poll);
const ZEITLIMIT = Number(document.body.dataset.timeout);

// --- Teil 1: Roboter. Laeuft rein im Browser, ohne Server. -----------------
const roboter = document.getElementById('roboter');
const knopfStart = document.getElementById('start');
const uebungsknoepfe = Array.from(document.querySelectorAll('[data-uebung]'));
let uebung = 'schlag';
let laeuft = false;

function zeichneRoboter() {
  roboter.className = 'roboter uebung-' + uebung + (laeuft ? '' : ' pausiert');
  knopfStart.textContent = laeuft ? 'Pause' : 'Start';
  knopfStart.setAttribute('aria-pressed', String(laeuft));
  for (const k of uebungsknoepfe) {
    k.setAttribute('aria-pressed', String(k.dataset.uebung === uebung));
  }
}
knopfStart.addEventListener('click', () => { laeuft = !laeuft; zeichneRoboter(); });
for (const k of uebungsknoepfe) {
  // Die Uebung laesst sich auch im Lauf wechseln, ohne Neuladen.
  k.addEventListener('click', () => { uebung = k.dataset.uebung; zeichneRoboter(); });
}
zeichneRoboter();

// --- Teil 2: Statusabfrage. Die einzige Stelle, die den Server braucht. ----
const feldVerbindung = document.getElementById('verbindung');
const feldGeprueft   = document.getElementById('geprueft');
const feldName       = document.getElementById('appname');
const feldLaufzeit   = document.getElementById('laufzeit');
const feldServerzeit = document.getElementById('serverzeit');
const feldAlter      = document.getElementById('alterhinweis');
const kasten         = document.getElementById('status');

let letzterStand = null;      // letzte erfolgreiche Antwort
let letzterErfolg = null;     // wann sie kam

function uhrzeit(zeitpunkt) {
  return zeitpunkt.toLocaleTimeString('de-CH', { hour12: false });
}

function zeichneStatus(erreichbar, versuchtUm, fehlertext) {
  // Der Pruefzeitpunkt wird bei JEDEM Versuch neu gesetzt, auch beim
  // gescheiterten. Die Serverwerte dagegen bleiben auf dem letzten Erfolg
  // stehen und werden als veraltet gekennzeichnet. Genau diese Trennung
  // verlangt die Vorgabe.
  feldGeprueft.textContent = uhrzeit(versuchtUm);
  feldVerbindung.textContent = erreichbar ? 'erreichbar' : 'nicht erreichbar';
  feldVerbindung.className = 'pill ' + (erreichbar ? 'v-ok' : 'v-weg');

  if (letzterStand === null) {
    feldName.textContent = '-';
    feldLaufzeit.textContent = '-';
    feldServerzeit.textContent = '-';
    kasten.classList.remove('veraltet');
    if (!erreichbar) {
      feldAlter.textContent = 'Noch keine Antwort erhalten: ' + fehlertext;
      kasten.classList.add('veraltet');
    }
    return;
  }

  feldName.textContent = letzterStand.application;
  feldLaufzeit.textContent = letzterStand.uptime_seconds + ' s';
  feldServerzeit.textContent = letzterStand.time;

  if (erreichbar) {
    kasten.classList.remove('veraltet');
  } else {
    kasten.classList.add('veraltet');
    feldAlter.textContent = 'Werte veraltet, letzte Antwort um '
      + uhrzeit(letzterErfolg) + ' (' + fehlertext + ')';
  }
}

async function pruefen() {
  const abbruch = new AbortController();
  const wecker = setTimeout(() => abbruch.abort(), ZEITLIMIT);
  const versuchtUm = new Date();
  try {
    const antwort = await fetch('/api/info', {
      signal: abbruch.signal, cache: 'no-store'
    });
    if (!antwort.ok) { throw new Error('HTTP ' + antwort.status); }
    letzterStand = await antwort.json();
    letzterErfolg = new Date();
    zeichneStatus(true, versuchtUm);
  } catch (fehler) {
    // Schon der erste Fehlversuch gilt als Ausfall. Drei Versuche abzuwarten
    // wuerde das Zeitfenster von etwa 15 s aus T3 reissen.
    const grund = (fehler.name === 'AbortError')
      ? 'Zeitlimit ' + (ZEITLIMIT / 1000) + ' s ueberschritten'
      : String(fehler.message || fehler);
    zeichneStatus(false, versuchtUm, grund);
  } finally {
    clearTimeout(wecker);
  }
}

pruefen();
setInterval(pruefen, INTERVALL);
"""


def render_page(nonce: str) -> str:
    return f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(APP_NAME)}</title>
<style>{STYLE}</style>
</head>
<body data-poll="{POLL_MS}" data-timeout="{TIMEOUT_MS}">
<div class="wrap">

  <div class="card">
    <h1>{esc(APP_NAME)}</h1>
    <p class="sub">Der Roboter uebt Karate. Die Bewegung laeuft im Browser.</p>
    <div class="buehne">
      <div class="boden"></div>
      <div id="roboter" class="roboter uebung-schlag pausiert">
        <div class="kopf"></div><div class="auge l"></div><div class="auge r"></div>
        <div class="rumpf"></div><div class="guertel"></div>
        <div class="arm l"></div><div class="arm r"></div>
        <div class="bein l"></div><div class="bein r"></div>
      </div>
    </div>
    <div class="steuerung">
      <button id="start" type="button" aria-pressed="false">Start</button>
      <button type="button" data-uebung="schlag" aria-pressed="true">Schlag</button>
      <button type="button" data-uebung="tritt" aria-pressed="false">Tritt</button>
    </div>
    <p class="hinweis">Start, Pause und Uebungswahl ohne Neuladen. Pause haelt
      die Bewegung an der Stelle an.</p>
  </div>

  <div class="card" id="status">
    <h2>Serverzustand</h2>
    <dl>
      <dt>Verbindung</dt><dd><span id="verbindung" class="pill v-weg">pruefe</span></dd>
      <dt>Letzte Pruefung</dt><dd id="geprueft">-</dd>
      <dt>Anwendung</dt><dd id="appname" class="serverwert">-</dd>
      <dt>Laufzeit Server</dt><dd id="laufzeit" class="serverwert">-</dd>
      <dt>Serverzeit</dt><dd id="serverzeit" class="serverwert">-</dd>
    </dl>
    <p class="alterhinweis" id="alterhinweis"></p>
    <p class="hinweis">Abfrage alle {POLL_MS // 1000} s, Zeitlimit
      {TIMEOUT_MS // 1000} s je Anfrage. Quelle: <code>/api/info</code>.</p>
  </div>

  <footer>Muster, keine Abgabe. Maschinenlesbar:
    <code>/api/info</code> und <code>/health</code>.</footer>
</div>
<script nonce="{nonce}">{SCRIPT}</script>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "lb1-muster/1.0"

    def log_message(self, fmt, *args):  # knapp halten
        print("  %s %s" % (self.command, self.path), flush=True)

    def _send(self, code: int, body: bytes, mime: str, nonce: str = "") -> None:
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        # default-src 'none' blockiert auch eigenes JavaScript. Statt die
        # Policy aufzuweichen, wird genau dieses eine Skript ueber ein Nonce
        # erlaubt. connect-src 'self' ist fuer fetch noetig.
        policy = ("default-src 'none'; style-src 'unsafe-inline'; "
                  "connect-src 'self'; base-uri 'none'; form-action 'none'; "
                  "frame-ancestors 'none'")
        if nonce:
            policy += f"; script-src 'nonce-{nonce}'"
        self.send_header("Content-Security-Policy", policy)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self._send(code, body, "application/json; charset=utf-8")

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
        if path == "/":
            nonce = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
            self._send(200, render_page(nonce).encode("utf-8"),
                       "text/html; charset=utf-8", nonce)
        elif path == "/health":
            self._json(200, {"status": "healthy", "application": APP_NAME,
                             "uptime_seconds": uptime()})
        elif path in ("/api/info", "/api/clock"):
            self._json(200, {"application": APP_NAME, "status": "running",
                             "time": now, "uptime_seconds": uptime(),
                             "started_at": STARTED_AT.isoformat(timespec="seconds")})
        elif path == "/langsam":
            # Nur zum Pruefen des Zeitlimits: antwortet absichtlich zu spaet.
            time.sleep(TIMEOUT_MS / 1000 + 3)
            self._json(200, {"application": APP_NAME, "status": "spaet"})
        else:
            self._json(404, {"error": "route not found", "path": path,
                             "valid_routes": ["/", "/health", "/api/info",
                                              "/api/clock"]})

    def do_POST(self) -> None:
        self.send_response(405)
        self.send_header("Allow", "GET")
        self.send_header("Content-Length", "0")
        self.end_headers()


def main() -> None:
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    server.daemon_threads = True
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: server.shutdown())
    print(f"INFO Muster laeuft auf http://{BIND}:{PORT}", flush=True)
    print(f"INFO Abfrage alle {POLL_MS} ms, Zeitlimit {TIMEOUT_MS} ms", flush=True)
    server.serve_forever()
    server.server_close()
    print("INFO beendet", flush=True)


if __name__ == "__main__":
    main()
