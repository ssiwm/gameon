"""Raport płynności gry z dziennika sesji: próbki `perf` (session_log.gd), jedna co 10 s.

Dla każdej sesji i mapy wypisuje: czas, średnie FPS, medianę p95 i p99 czasu klatki („1% low” to 1000 / p99), najdłuższą klatkę,
przestoje (klatki > 50 ms) na minutę, GPU, a od 1.7.462 główny wątek: skrypt widoku 3D (v3d), CPU renderu (rcpu), szczyty process i physics,
kroki fizyki na klatkę i ruch myszy (zdarzeń/s). Wiersz dostaje ocenę: PŁYNNIE, PRZESKOKI (co najmniej 5% klatek traci synchronizację)
albo WOLNO (poniżej 45 FPS). Pole p99 i mapa „menu” są od 1.7.461; w starszych plikach menu wygląda jak domyślna mapa z GPU poniżej 3 ms.
Flaga `--split-mouse` liczy osobno próbki z ruchem myszy (≥ 5 zdarzeń/s) i bez niego, żeby porównać je w jednej sesji.

Użycie (z prototype/): python tools/session_perf.py [--dir KATALOG] [--build 1.7.46] [--since 2026-11-01] [--last 10] [--split-mouse]
  --dir     katalog z plikami .jsonl (domyślnie %APPDATA%/Godot/app_userdata/Dead Air '87 Prototype/sessions)
  --build   tylko buildy zaczynające się od tego tekstu
  --since   tylko pliki z datą w nazwie od tego dnia (RRRR-MM-DD)
  --last    tylko N najnowszych plików (domyślnie 10; 0 = wszystkie)
"""
import argparse
import glob
import json
import os
import statistics
import sys

SAMPLE_S = 10.0
SMOOTH_P95_MS = 18.5    # 60 Hz z zapasem na pojedyncze nierówne klatki
SLOW_FPS = 45.0
MOUSE_MOVING = 5        # zdarzeń/s: poniżej tego próbka liczy się jako „bez ruchu myszy”


def default_dir():
    return os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Dead Air '87 Prototype", "sessions")


def read_session(path):
    build, maps = "?", {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("ev") == "system":
                build = row.get("build", "?")
            elif row.get("ev") == "perf":
                maps.setdefault(row.get("map", "?"), []).append(row)
    return build, maps


def verdict(fps, p95):
    if fps < SLOW_FPS:
        return "WOLNO"
    return "PŁYNNIE" if p95 <= SMOOTH_P95_MS else "PRZESKOKI"


def summarize(rows):
    p99 = [r["p99"] for r in rows if "p99" in r]
    fps = statistics.mean(r["fps"] for r in rows)
    p95 = statistics.median(r["p95"] for r in rows)
    minutes = len(rows) * SAMPLE_S / 60.0
    field = lambda key: statistics.median(r[key] for r in rows if key in r) if any(key in r for r in rows) else None
    return {
        "v3d": field("v3d"),
        "rcpu": field("rcpu"),
        "proc": field("proc"),
        "phys": field("phys"),
        "steps": field("steps"),
        "mouse": field("mouse"),
        "min": minutes,
        "fps": fps,
        "p95": p95,
        "low1": 1000.0 / statistics.median(p99) if p99 else None,
        "max": max(r["max"] for r in rows),
        "spikes": sum(r["spikes"] for r in rows) / minutes,
        "gpu": statistics.median(r["gpu"] for r in rows),
        "verdict": verdict(fps, p95),
    }


def main():
    ap = argparse.ArgumentParser(description="Raport płynności z dziennika sesji")
    ap.add_argument("--dir", default=default_dir())
    ap.add_argument("--build", default="")
    ap.add_argument("--since", default="")
    ap.add_argument("--last", type=int, default=10)
    ap.add_argument("--split-mouse", action="store_true")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    files = sorted(glob.glob(os.path.join(args.dir, "*.jsonl")))
    if args.since:
        files = [p for p in files if os.path.basename(p)[:10] >= args.since]
    if args.last > 0:
        files = files[-args.last:]

    print("%-16s %-18s %-13s %5s %5s %6s %6s %7s %7s %5s %5s %5s %6s %6s %5s %5s  %s" % (
        "sesja", "build", "mapa", "min", "FPS", "p95", "1%low", "max ms", "prz/min", "GPU", "v3d", "rcpu", "proc^", "phys^", "kroki", "mysz", "ocena"))
    num = lambda v, fmt: fmt % v if v is not None else "-"
    shown = 0
    for path in files:
        build, maps = read_session(path)
        if not build.startswith(args.build):
            continue
        for name, rows in maps.items():
            groups = {name: rows}
            if args.split_mouse:
                groups = {name + "/mysz": [r for r in rows if r.get("mouse", 0) >= MOUSE_MOVING],
                          name + "/stoi": [r for r in rows if r.get("mouse", 0) < MOUSE_MOVING]}
            for label, items in groups.items():
                if not items:
                    continue
                s = summarize(items)
                print("%-16s %-18s %-13s %5.1f %5.1f %6.1f %6s %7.0f %7.1f %5.1f %5s %5s %6s %6s %5s %5s  %s" % (
                    os.path.basename(path)[:16], build, label, s["min"], s["fps"], s["p95"], num(s["low1"], "%.0f"), s["max"], s["spikes"], s["gpu"],
                    num(s["v3d"], "%.1f"), num(s["rcpu"], "%.1f"), num(s["proc"], "%.1f"), num(s["phys"], "%.1f"), num(s["steps"], "%.2f"), num(s["mouse"], "%.0f"), s["verdict"]))
                shown += 1
    if shown == 0:
        print("brak próbek perf w %s" % args.dir)


if __name__ == "__main__":
    main()
