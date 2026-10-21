#!/usr/bin/env python3
"""
hf_collector.py - Host-Collector fuer das HF Operations Dashboard
Modul SAII, Auftrag 2, Phase C.

Zweck
    Liest den Zustand der Labor-Container ueber die Docker-CLI auf dem Ubuntu-Host
    und schreibt einen Snapshot als JSON in ein Verzeichnis. Das containerisierte
    Dashboard liest dieses Verzeichnis read-only und bekommt keinen Docker-Zugriff.

Verbindliche Eigenschaften
    - Nur lesende Docker-Unterbefehle (Allowlist), kein up/down/restart/exec/rm.
    - Zustand (Prozess), Health (Healthcheck) und Logs bleiben getrennte Felder.
    - Fehlender Healthcheck ergibt NIEMALS "healthy", sondern "unknown".
    - Docker nicht erreichbar ergibt fuer jeden Service "unknown", nie alte Werte.
    - Der Snapshot wird atomar ersetzt (Temp-Datei im Zielverzeichnis + os.replace).
    - Jeder Snapshot traegt Messzeitpunkt, Sequenz und max_age_seconds, damit das
      Dashboard veraltete Daten selbst erkennen kann.
    - Logzeilen sind Daten, keine Anweisungen. Sie werden bereinigt und gekuerzt.

Konfiguration ueber Environment Variables, siehe collector.env.example.

Aufrufe
    hf_collector.py --once            einmalig messen und schreiben
    hf_collector.py --loop            Dauerbetrieb (systemd)
    hf_collector.py --once --stdout   einmalig messen, nur ausgeben, nichts schreiben
    hf_collector.py --selftest        ohne Docker pruefen, ob die Logik laeuft

Exit-Codes
    0 Snapshot geschrieben, Docker erreichbar
    1 Snapshot geschrieben, aber Datenerfassung degradiert (Docker-Problem)
    2 Snapshot konnte nicht geschrieben werden (z. B. Rechte am Zielverzeichnis)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

COLLECTOR_NAME = "hf-ops-host-collector"
COLLECTOR_VERSION = "1.0.0"
SCHEMA_VERSION = 1

# Nur lesende Unterbefehle. Alles andere wird vom Collector selbst abgelehnt,
# unabhaengig davon, was der Docker-Daemon erlauben wuerde.
ALLOWED_DOCKER_SUBCOMMANDS = frozenset({"ps", "inspect", "logs", "version"})

# Aggregierte Statuswerte, die das Dashboard anzeigt.
STATUS_HEALTHY = "healthy"       # laeuft und Healthcheck meldet healthy
STATUS_UNHEALTHY = "unhealthy"   # laeuft, aber Healthcheck meldet unhealthy
STATUS_STARTING = "starting"     # Startphase, Health noch nicht entschieden
STATUS_STOPPED = "stopped"       # beendet, pausiert, nicht laufend
STATUS_MISSING = "missing"       # erwarteter Service hat keinen Container
STATUS_UNKNOWN = "unknown"       # nicht ermittelbar (Docker-Fehler, kein Healthcheck)

CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


class CollectorError(Exception):
    """Fehler, der im Snapshot sichtbar gemacht und nicht verschluckt wird."""


# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

def env_str(name: str, default: str) -> str:
    value = os.environ.get(name)
    return default if value is None or value.strip() == "" else value.strip()


def env_int(name: str, default: int, minimum: int = 1) -> int:
    raw = os.environ.get(name, "").strip()
    if raw == "":
        return default
    try:
        return max(minimum, int(raw))
    except ValueError:
        print(f"WARN {name}={raw!r} ist keine Zahl, verwende {default}", file=sys.stderr)
        return default


class Config:
    def __init__(self) -> None:
        self.project = env_str("HFC_PROJECT", "hf-ops-lab")
        self.services = [s for s in env_str("HFC_SERVICES", "api,web,worker").split(",") if s.strip()]
        self.services = [s.strip() for s in self.services]
        self.out_dir = Path(env_str("HFC_OUT_DIR", "/var/lib/hf-ops-collector/state"))
        self.out_file = env_str("HFC_OUT_FILE", "snapshot.json")
        self.interval = env_int("HFC_INTERVAL", 5)
        # Ab diesem Alter gilt der Snapshot als veraltet. Default: 4 Intervalle.
        self.max_age = env_int("HFC_MAX_AGE", max(20, self.interval * 4))
        self.log_lines = env_int("HFC_LOG_LINES", 25)
        self.log_max_chars = env_int("HFC_LOG_MAX_CHARS", 400, minimum=80)
        self.docker_bin = env_str("HFC_DOCKER_BIN", "docker")
        self.docker_sudo = env_str("HFC_DOCKER_SUDO", "auto").lower()
        self.docker_timeout = env_int("HFC_DOCKER_TIMEOUT", 10)
        self.file_mode = int(env_str("HFC_FILE_MODE", "0644"), 8)

    def describe(self) -> dict:
        return {
            "project": self.project,
            "expected_services": list(self.services),
            "out_path": str(self.out_dir / self.out_file),
            "interval_seconds": self.interval,
            "max_age_seconds": self.max_age,
            "log_lines": self.log_lines,
            "docker_bin": self.docker_bin,
            "docker_sudo": self.docker_sudo,
            "docker_timeout_seconds": self.docker_timeout,
            "allowed_docker_subcommands": sorted(ALLOWED_DOCKER_SUBCOMMANDS),
        }


# ---------------------------------------------------------------------------
# Docker-Zugriff (nur lesend)
# ---------------------------------------------------------------------------

class Docker:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        if cfg.docker_sudo in ("1", "true", "yes", "on"):
            use_sudo = True
        elif cfg.docker_sudo in ("0", "false", "no", "off"):
            use_sudo = False
        else:  # auto
            use_sudo = os.geteuid() != 0
        # -n verhindert eine Passwortabfrage. Ein blockierender Prompt wuerde die
        # Messschleife anhalten und das Dashboard mit alten Daten zuruecklassen.
        self.prefix = ["sudo", "-n"] if use_sudo else []
        self.use_sudo = use_sudo

    def run(self, args: list[str]) -> subprocess.CompletedProcess:
        if not args or args[0] not in ALLOWED_DOCKER_SUBCOMMANDS:
            raise CollectorError(
                f"Unterbefehl '{args[0] if args else ''}' ist nicht erlaubt. "
                f"Erlaubt sind nur: {', '.join(sorted(ALLOWED_DOCKER_SUBCOMMANDS))}"
            )
        cmd = self.prefix + [self.cfg.docker_bin] + args
        try:
            return subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.cfg.docker_timeout,
                check=False,
            )
        except FileNotFoundError as exc:
            raise CollectorError(
                f"Docker-CLI '{self.cfg.docker_bin}' nicht gefunden: {exc}"
            ) from exc
        except subprocess.TimeoutExpired:
            raise CollectorError(
                f"Docker-Befehl '{' '.join(args)}' hat das Zeitlimit von "
                f"{self.cfg.docker_timeout}s ueberschritten"
            ) from None

    def run_checked(self, args: list[str]) -> str:
        proc = self.run(args)
        if proc.returncode != 0:
            raise CollectorError(explain_docker_failure(args, proc, self.use_sudo))
        return proc.stdout


def explain_docker_failure(args: list[str], proc: subprocess.CompletedProcess, use_sudo: bool) -> str:
    """Verstaendliche Meldung statt rohem Stacktrace."""
    detail = (proc.stderr or proc.stdout or "").strip().splitlines()
    first = detail[0] if detail else f"Exit-Code {proc.returncode}"
    low = first.lower()
    if "permission denied" in low and "docker.sock" in low:
        hint = ("Kein Zugriff auf den Docker-Socket. Collector als root ueber systemd "
                "starten oder HFC_DOCKER_SUDO=1 setzen. Socket-Rechte nicht lockern.")
    elif "sudo" in low and ("password" in low or "askpass" in low or "no tty" in low):
        hint = ("sudo verlangt ein Passwort. Collector als root ueber systemd starten "
                "oder eine gezielte sudoers-Regel fuer die lesenden Docker-Befehle setzen.")
    elif "cannot connect to the docker daemon" in low or "is the docker daemon running" in low:
        hint = "Docker-Daemon laeuft nicht oder ist nicht erreichbar: systemctl status docker."
    elif "zeitlimit" in low:
        hint = "Docker antwortet zu langsam. HFC_DOCKER_TIMEOUT erhoehen und Host-Last pruefen."
    else:
        hint = "Befehl manuell auf dem Host wiederholen und erste konkrete Fehlerzeile lesen."
    return f"docker {' '.join(args)} fehlgeschlagen: {first} | {hint}"


# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.isoformat(timespec="milliseconds")


def clean_text(text: str, limit: int) -> tuple[str, bool]:
    """Steuerzeichen entfernen und kuerzen. Logs bleiben reine Daten."""
    text = ANSI_ESCAPE.sub("", text)
    text = CONTROL_CHARS.sub("", text)
    text = text.replace("\r", "").rstrip()
    if len(text) > limit:
        return text[:limit] + " [gekuerzt]", True
    return text, False


def docker_time(value: str | None) -> str | None:
    """Docker-Zeitstempel normalisieren. '0001-01-01T00:00:00Z' bedeutet 'nie'."""
    if not value or value.startswith("0001-01-01"):
        return None
    return value


def log_level(message: str) -> str:
    head = message.lstrip()[:6].upper()
    if head.startswith("ERROR"):
        return "error"
    if head.startswith("WARN"):
        return "warn"
    if head.startswith("INFO"):
        return "info"
    return "raw"


# ---------------------------------------------------------------------------
# Messung
# ---------------------------------------------------------------------------

def list_project_containers(docker: Docker, project: str) -> list[str]:
    out = docker.run_checked([
        "ps", "-a",
        "--filter", f"label=com.docker.compose.project={project}",
        "--format", "{{.ID}}",
    ])
    return [line.strip() for line in out.splitlines() if line.strip()]


def inspect_containers(docker: Docker, ids: list[str]) -> list[dict]:
    if not ids:
        return []
    out = docker.run_checked(["inspect"] + ids)
    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise CollectorError(f"docker inspect lieferte kein gueltiges JSON: {exc}") from exc
    return data if isinstance(data, list) else [data]


def collect_logs(docker: Docker, cfg: Config, container_id: str) -> dict:
    """Letzte Logzeilen mit Zeitstempel. stdout und stderr werden zusammengefuehrt."""
    result: dict = {
        "source": f"docker logs --timestamps --tail {cfg.log_lines}",
        "lines": [],
        "error_count": 0,
        "last_error": None,
        "error": None,
    }
    proc = docker.run(["logs", "--timestamps", "--tail", str(cfg.log_lines), container_id])
    if proc.returncode != 0:
        result["error"] = explain_docker_failure(
            ["logs", container_id], proc, docker.use_sudo
        )
        return result

    entries = []
    for stream, text in (("stdout", proc.stdout), ("stderr", proc.stderr)):
        for raw in text.splitlines():
            if not raw.strip():
                continue
            timestamp, _, message = raw.partition(" ")
            if not timestamp.startswith("20"):  # keine Zeitstempelzeile
                timestamp, message = "", raw
            message, truncated = clean_text(message, cfg.log_max_chars)
            if not message:
                continue
            entries.append({
                "ts": timestamp or None,
                "stream": stream,
                "level": log_level(message),
                "message": message,
                "truncated": truncated,
            })

    entries.sort(key=lambda e: (e["ts"] or ""))
    entries = entries[-cfg.log_lines:]
    errors = [e for e in entries if e["level"] == "error"]
    result["lines"] = entries
    result["error_count"] = len(errors)
    result["last_error"] = errors[-1] if errors else None
    return result


def read_health(inspect: dict) -> dict:
    """Health strikt vom Prozesszustand trennen."""
    state = inspect.get("State") or {}
    health = state.get("Health")
    if not health:
        return {
            "mode": "none",
            "state": "none",
            "failing_streak": None,
            "last_probe_at": None,
            "last_probe_exit_code": None,
            "last_probe_output": None,
            "note": "Kein Healthcheck definiert. Health ist nicht ermittelbar, nicht gesund.",
        }
    probes = health.get("Log") or []
    last = probes[-1] if probes else {}
    output = last.get("Output") or ""
    output, _ = clean_text(output, 400)
    return {
        "mode": "healthcheck",
        "state": (health.get("Status") or "unknown").lower(),
        "failing_streak": health.get("FailingStreak"),
        "last_probe_at": docker_time(last.get("End")),
        "last_probe_exit_code": last.get("ExitCode"),
        "last_probe_output": output or None,
        "note": None,
    }


def aggregate_status(process_state: str, health: dict, exit_code: int | None) -> tuple[str, str]:
    """Prozesszustand und Health zu einem Anzeigestatus verbinden."""
    state = (process_state or "").lower()

    if state in ("exited", "dead"):
        if exit_code not in (None, 0):
            return STATUS_UNHEALTHY, f"Container beendet mit Exit-Code {exit_code}."
        return STATUS_STOPPED, "Container beendet mit Exit-Code 0."
    if state == "paused":
        return STATUS_STOPPED, "Container pausiert."
    if state in ("created", "restarting"):
        return STATUS_STARTING, f"Container im Zustand '{state}', Health noch nicht entschieden."
    if state != "running":
        return STATUS_UNKNOWN, f"Unbekannter Prozesszustand '{process_state}'."

    # Ab hier laeuft der Prozess. Jetzt entscheidet ausschliesslich der Healthcheck.
    hstate = health.get("state")
    if health.get("mode") == "none":
        return STATUS_UNKNOWN, ("Prozess laeuft, aber ohne Healthcheck. Ein laufender "
                                "Prozess ist kein Nachweis fuer eine funktionierende Anwendung.")
    if hstate == "healthy":
        return STATUS_HEALTHY, "Prozess laeuft, Healthcheck meldet healthy."
    if hstate == "unhealthy":
        streak = health.get("failing_streak")
        extra = f" Fehlerserie: {streak}." if streak is not None else ""
        return STATUS_UNHEALTHY, f"Prozess laeuft, Healthcheck meldet unhealthy.{extra}"
    if hstate == "starting":
        return STATUS_STARTING, "Prozess laeuft, Healthcheck ist in der Startphase."
    return STATUS_UNKNOWN, f"Health-Status '{hstate}' konnte nicht eingeordnet werden."


def port_list(inspect: dict) -> list[str]:
    ports = ((inspect.get("NetworkSettings") or {}).get("Ports") or {})
    out = []
    for container_port, bindings in sorted(ports.items()):
        if not bindings:
            out.append(f"{container_port} (nicht veroeffentlicht)")
            continue
        for binding in bindings:
            host_ip = binding.get("HostIp") or "0.0.0.0"
            host_port = binding.get("HostPort") or "?"
            out.append(f"{host_ip}:{host_port}->{container_port}")
    return out


def build_service_entry(docker: Docker, cfg: Config, service: str, inspect: dict | None) -> dict:
    if inspect is None:
        return {
            "service": service,
            "expected": service in cfg.services,
            "present": False,
            "status": STATUS_MISSING,
            "status_reason": (f"Kein Container mit Label com.docker.compose.service={service} "
                              f"im Projekt '{cfg.project}'. Service nicht gestartet oder entfernt."),
            "container": None,
            "process_state": None,
            "health": None,
            "ports": [],
            "logs": None,
        }

    state = inspect.get("State") or {}
    config = inspect.get("Config") or {}
    host_config = inspect.get("HostConfig") or {}
    process_state = (state.get("Status") or "unknown").lower()
    exit_code = state.get("ExitCode")
    health = read_health(inspect)
    status, reason = aggregate_status(process_state, health, exit_code)
    container_id = inspect.get("Id", "")

    return {
        "service": service,
        "expected": service in cfg.services,
        "present": True,
        "status": status,
        "status_reason": reason,
        "container": {
            "id": container_id[:12],
            "name": (inspect.get("Name") or "").lstrip("/"),
            "image": config.get("Image"),
            "created_at": docker_time(inspect.get("Created")),
            "started_at": docker_time(state.get("StartedAt")),
            "finished_at": docker_time(state.get("FinishedAt")),
            "restart_count": inspect.get("RestartCount"),
            "restart_policy": (host_config.get("RestartPolicy") or {}).get("Name"),
            "exit_code": exit_code,
            "pid": state.get("Pid") or None,
            "user": config.get("User") or None,
            "read_only_rootfs": host_config.get("ReadonlyRootfs"),
        },
        "process_state": process_state,
        "health": health,
        "ports": port_list(inspect),
        "logs": collect_logs(docker, cfg, container_id),
    }


def collect(cfg: Config, sequence: int) -> tuple[dict, bool]:
    """Einen Snapshot erzeugen. Rueckgabe: (snapshot, docker_erreichbar)."""
    started = time.monotonic()
    measured_at = now_utc()
    docker = Docker(cfg)
    errors: list[str] = []
    docker_reachable = True
    containers: list[dict] = []

    try:
        ids = list_project_containers(docker, cfg.project)
        containers = inspect_containers(docker, ids)
    except CollectorError as exc:
        docker_reachable = False
        errors.append(str(exc))

    by_service: dict[str, dict] = {}
    unexpected: list[dict] = []
    if docker_reachable:
        for inspect in containers:
            labels = (inspect.get("Config") or {}).get("Labels") or {}
            service = labels.get("com.docker.compose.service")
            if not service:
                continue
            # Bei mehreren Replikaten gewinnt der zuletzt gestartete Container.
            previous = by_service.get(service)
            if previous is None or (inspect.get("State") or {}).get("StartedAt", "") > \
                    (previous.get("State") or {}).get("StartedAt", ""):
                by_service[service] = inspect

    services: list[dict] = []
    if not docker_reachable:
        # Keine Messung moeglich: alles explizit als nicht ermittelbar ausweisen.
        for name in cfg.services:
            services.append({
                "service": name,
                "expected": True,
                "present": None,
                "status": STATUS_UNKNOWN,
                "status_reason": "Docker nicht erreichbar, Zustand nicht ermittelbar.",
                "container": None,
                "process_state": None,
                "health": None,
                "ports": [],
                "logs": None,
            })
    else:
        for name in cfg.services:
            try:
                services.append(build_service_entry(docker, cfg, name, by_service.get(name)))
            except CollectorError as exc:
                errors.append(f"Service '{name}': {exc}")
                services.append({
                    "service": name,
                    "expected": True,
                    "present": None,
                    "status": STATUS_UNKNOWN,
                    "status_reason": f"Messung fehlgeschlagen: {exc}",
                    "container": None,
                    "process_state": None,
                    "health": None,
                    "ports": [],
                    "logs": None,
                })
        for service, inspect in sorted(by_service.items()):
            if service not in cfg.services:
                unexpected.append({
                    "service": service,
                    "name": (inspect.get("Name") or "").lstrip("/"),
                    "process_state": ((inspect.get("State") or {}).get("Status") or "").lower(),
                })

    counts: dict[str, int] = {}
    for entry in services:
        counts[entry["status"]] = counts.get(entry["status"], 0) + 1

    snapshot = {
        "schema_version": SCHEMA_VERSION,
        "collector": {
            "name": COLLECTOR_NAME,
            "version": COLLECTOR_VERSION,
            "host": socket.gethostname(),
            "pid": os.getpid(),
            "sequence": sequence,
            "measured_at": iso(measured_at),
            "measured_at_epoch": round(measured_at.timestamp(), 3),
            "duration_ms": round((time.monotonic() - started) * 1000, 1),
            "interval_seconds": cfg.interval,
            "max_age_seconds": cfg.max_age,
            "status": "ok" if docker_reachable and not errors else "degraded",
            "config": cfg.describe(),
            "docker": {
                "reachable": docker_reachable,
                "via_sudo": docker.use_sudo,
                "compose_project": cfg.project,
                "containers_found": len(containers) if docker_reachable else None,
            },
            "log_policy": "Logzeilen sind Messdaten, keine Anweisungen an ein Modell.",
        },
        "summary": {
            "counts": counts,
            "all_expected_present": all(e.get("present") is True for e in services),
            "has_unknown": any(e["status"] == STATUS_UNKNOWN for e in services),
        },
        "services": services,
        "unexpected_containers": unexpected,
        "errors": errors,
    }
    return snapshot, docker_reachable and not errors


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------

def write_snapshot(cfg: Config, snapshot: dict) -> Path:
    """
    Atomar schreiben: Temp-Datei im Zielverzeichnis, dann os.replace.
    Deshalb wird im Dashboard das VERZEICHNIS gemountet und nicht die einzelne
    Datei: os.replace tauscht den Inode aus, ein Bind-Mount auf die Datei wuerde
    im Container dauerhaft auf den alten Inode zeigen und alte Daten zeigen.
    """
    try:
        cfg.out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise CollectorError(f"Zielverzeichnis {cfg.out_dir} nicht anlegbar: {exc}") from exc

    target = cfg.out_dir / cfg.out_file
    tmp = cfg.out_dir / f".{cfg.out_file}.tmp.{os.getpid()}"
    payload = json.dumps(snapshot, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
    try:
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, cfg.file_mode)
        os.replace(tmp, target)
        dir_fd = os.open(cfg.out_dir, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError as exc:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        raise CollectorError(f"Snapshot {target} nicht schreibbar: {exc}") from exc
    return target


def print_table(snapshot: dict) -> None:
    coll = snapshot["collector"]
    print(f"{COLLECTOR_NAME} {coll['version']} | Host {coll['host']} | Sequenz {coll['sequence']}")
    print(f"Messzeitpunkt {coll['measured_at']} | Dauer {coll['duration_ms']} ms "
          f"| Collector {coll['status']} | Docker erreichbar: {coll['docker']['reachable']}")
    print(f"{'SERVICE':<10} {'ZUSTAND':<12} {'HEALTH':<10} {'STATUS':<10} BEGRUENDUNG")
    for entry in snapshot["services"]:
        health = (entry.get("health") or {}).get("state") or "-"
        print(f"{entry['service']:<10} {str(entry.get('process_state') or '-'):<12} "
              f"{health:<10} {entry['status']:<10} {entry['status_reason']}")
    for problem in snapshot["errors"]:
        print(f"FEHLER {problem}")
    for extra in snapshot["unexpected_containers"]:
        print(f"HINWEIS zusaetzlicher Container im Projekt: {extra['name']} ({extra['service']})")


# ---------------------------------------------------------------------------
# Selbsttest ohne Docker
# ---------------------------------------------------------------------------

def selftest() -> int:
    cases = [
        (("running", {"mode": "healthcheck", "state": "healthy"}, None), STATUS_HEALTHY),
        (("running", {"mode": "healthcheck", "state": "unhealthy", "failing_streak": 4}, None), STATUS_UNHEALTHY),
        (("running", {"mode": "healthcheck", "state": "starting"}, None), STATUS_STARTING),
        (("running", {"mode": "none", "state": "none"}, None), STATUS_UNKNOWN),
        (("exited", {"mode": "none", "state": "none"}, 1), STATUS_UNHEALTHY),
        (("exited", {"mode": "none", "state": "none"}, 0), STATUS_STOPPED),
        (("paused", {"mode": "healthcheck", "state": "healthy"}, None), STATUS_STOPPED),
        (("restarting", {"mode": "healthcheck", "state": "unhealthy"}, None), STATUS_STARTING),
    ]
    failures = 0
    for (state, health, code), expected in cases:
        actual, reason = aggregate_status(state, health, code)
        mark = "ok  " if actual == expected else "FAIL"
        if actual != expected:
            failures += 1
        print(f"{mark} state={state:<11} health={health.get('state'):<9} -> {actual:<10} ({expected})")
    text, truncated = clean_text("INFO \x1b[31mrot\x1b[0m\x07 ok", 400)
    if text != "INFO rot ok" or truncated:
        print(f"FAIL Logbereinigung ergab {text!r}")
        failures += 1
    else:
        print("ok   Logbereinigung entfernt ANSI- und Steuerzeichen")
    if docker_time("0001-01-01T00:00:00Z") is not None:
        print("FAIL Nullzeitstempel wird nicht als 'nie' erkannt")
        failures += 1
    else:
        print("ok   Nullzeitstempel wird als 'nie' erkannt")
    try:
        Docker(Config()).run(["rm", "-f", "x"])
        print("FAIL schreibender Unterbefehl wurde nicht abgelehnt")
        failures += 1
    except CollectorError:
        print("ok   schreibender Unterbefehl 'rm' wird abgelehnt")
    print("Selbsttest bestanden" if failures == 0 else f"Selbsttest: {failures} Fehler")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------------------
# Hauptprogramm
# ---------------------------------------------------------------------------

_stop = False


def _handle_signal(signum, _frame) -> None:
    global _stop
    _stop = True
    print(f"INFO Signal {signum} empfangen, beende nach dem laufenden Durchgang", flush=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Host-Collector: liest Docker-Zustaende und schreibt einen JSON-Snapshot.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--once", action="store_true", help="einmalig messen (Default)")
    group.add_argument("--loop", action="store_true", help="Dauerbetrieb im Messintervall")
    group.add_argument("--selftest", action="store_true", help="Logik ohne Docker pruefen")
    parser.add_argument("--stdout", action="store_true",
                        help="Snapshot nur ausgeben, nichts schreiben")
    parser.add_argument("--quiet", action="store_true", help="keine Tabelle ausgeben")
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    cfg = Config()
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    sequence = 0
    exit_code = 0
    while True:
        sequence += 1
        snapshot, healthy_run = collect(cfg, sequence)

        if args.stdout:
            print(json.dumps(snapshot, ensure_ascii=False, indent=2))
        else:
            try:
                target = write_snapshot(cfg, snapshot)
            except CollectorError as exc:
                print(f"ERROR {exc}", file=sys.stderr, flush=True)
                if not args.loop:
                    return 2
                exit_code = 2
                target = None
            if target and not args.quiet and not args.loop:
                print(f"INFO Snapshot geschrieben: {target}")

        if not args.quiet and not args.stdout and args.loop:
            coll = snapshot["collector"]
            counts = ",".join(f"{k}={v}" for k, v in sorted(snapshot["summary"]["counts"].items()))
            print(f"INFO seq={sequence} {coll['measured_at']} collector={coll['status']} "
                  f"docker={coll['docker']['reachable']} {counts}", flush=True)
        if not args.quiet and not args.loop and not args.stdout:
            print_table(snapshot)

        if not healthy_run and exit_code == 0:
            exit_code = 1
        if not args.loop or _stop:
            break
        # Messdauer vom Intervall abziehen, damit das Intervall eingehalten wird.
        sleep_for = max(0.5, cfg.interval - snapshot["collector"]["duration_ms"] / 1000)
        slept = 0.0
        while slept < sleep_for and not _stop:
            time.sleep(min(0.5, sleep_for - slept))
            slept += 0.5
        if _stop:  # Signal waehrend der Wartezeit: sofort beenden, nicht neu messen.
            break
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
