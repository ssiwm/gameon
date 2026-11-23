"""Raport walk z Pijawką (B1) z dziennika sesji — pomiar W6-0 (DESTRUCTION_CONTENT_PLAN.md, osłony na arenie Pijawki).

Dla każdej próby na mapie z1_b1: wersja, poziom trudności, ludzie i boty, czas, wynik, HP i faza bossa na końcu (`mission_end.boss`),
upadki wg źródła (`down.source`: leech — zasadzka i chwyt, acid — kwas, trzosek — przyzwane, …), zużyte flary i przeżarte osłony
(od 1.7.662, W6-1: `break` z materiałem `cover`). Na końcu suma: ile upadków dał kwas, a ile zasadzka — pomiar przed osłonami i po nich.

    python tools/leech_report.py                       # domyślny katalog dziennika gry (Windows: %APPDATA%/Godot/app_userdata/...)
    python tools/leech_report.py --dir KATALOG --since 2026-11-23 --build 1.7.66
"""
import argparse
import collections
import glob
import json
import os
import sys

DEFAULT_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "Godot", "app_userdata", "Dead Air '87 Prototype", "sessions")


def attempts(path):
    """Próby B1 z jednego pliku dziennika: lista słowników {start, end, downs, flares}."""
    out = []
    cur = None
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        ev = r.get("ev")
        if ev == "mission_start":
            cur = {"start": r, "end": None, "downs": [], "flares": 0, "covers": 0, "file": os.path.basename(path)} if r.get("map") == "z1_b1" else None
            if cur is not None:
                out.append(cur)
        elif cur is None:
            continue
        elif ev == "down" and r.get("phase") == "BOSS":
            cur["downs"].append(r)
        elif ev == "item" and r.get("what") == "flare":
            cur["flares"] += 1
        elif ev == "break" and r.get("mat") == "cover":
            cur["covers"] += 1
        elif ev == "mission_end":
            cur["end"] = r
            cur = None
    return out


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")         # konsola Windows (cp1250) psuła polskie znaki
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--since", default="", help="najwcześniejsza data pliku dziennika (RRRR-MM-DD)")
    ap.add_argument("--build", default="", help="tylko wersje zaczynające się od tego napisu")
    a = ap.parse_args(argv)
    files = sorted(glob.glob(os.path.join(a.dir, "*.jsonl")))
    rows = []
    for f in files:
        if a.since and os.path.basename(f)[:10] < a.since:
            continue
        for at in attempts(f):
            if a.build and not str(at["start"].get("build", "")).startswith(a.build):
                continue
            rows.append(at)
    if not rows:
        print("Brak prób B1 w %s (filtry: since=%s build=%s)" % (a.dir, a.since or "-", a.build or "-"))
        return 1
    total = collections.Counter()
    human = collections.Counter()
    wins = 0
    for at in rows:
        s, e = at["start"], at["end"] or {}
        src = collections.Counter(str(d.get("source", "?")) for d in at["downs"])
        total.update(src)
        human.update(str(d.get("source", "?")) for d in at["downs"] if not d.get("bot"))
        boss = e.get("boss") or {}
        wins += 1 if e.get("result") == "success" else 0
        print("%s  %-14s %-6s ludzie %s boty %s  próba %s  %5.0f s  %-7s  boss %s/%s faza %s  flary %d  osłony %d  upadki: %s" % (
            at["file"][:16], str(s.get("build", "?"))[:14], s.get("difficulty", "?"), s.get("humans", "?"), s.get("bots", "?"),
            s.get("attempt", "?"), float(e.get("time", 0.0)), e.get("result", "—"), boss.get("hp", "?"), boss.get("max_hp", "?"),
            boss.get("phase", "?"), at["flares"], at["covers"], ", ".join("%s %d" % kv for kv in src.most_common()) or "brak"))
    n = sum(total.values())
    print()
    print("Prób: %d, zwycięstw: %d. Upadków w walce: %d (ludzie %d)." % (len(rows), wins, n, sum(human.values())))
    for k, v in total.most_common():
        print("  %-10s %3d  (%2.0f%%)  ludzie %d" % (k, v, 100.0 * v / max(n, 1), human.get(k, 0)))
    acid = total.get("acid", 0)
    print("Kwas: %d z %d upadków (%.0f%%) — przed W6-1 (1.7.661) 42%%; osłony przeżarte: %d." % (acid, n, 100.0 * acid / max(n, 1), sum(at["covers"] for at in rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
