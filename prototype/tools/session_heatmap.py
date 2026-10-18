"""Mapy cieplne i czasy odcinków z dziennika sesji (MAPS_PLAN.md P3).

Czyta pliki `user://sessions/*.jsonl` (session_log.gd) i dla każdej mapy misji rysuje rzut siatki ASCII z `scripts/maps/<id>.gd`
z trzema warstwami: **czas** (gdzie drużyna stała — z próbek `pos` co 3 s), **trasy** (linia każdego podejścia) i **upadki**
(krzyżyk w kolorze sprawcy). Do tego raport tekstowy: podejścia i wyniki, czas misji, czas do kolejnych celów (`objective`)
i udział czasu w pasach po 20 kolumn (powierzchnia / podziemia).

Logi sprzed PR #348 (dziennik bez pozycji) nie mają `pos` ani `objective` — z nich zostają tylko upadki i wyniki.

Użycie (z prototype/): python tools/session_heatmap.py [--dir KATALOG] [--out KATALOG] [--map z1_m1] [--build 1.7.27]
                                                     [--difficulty NORMAL] [--mode campaign] [--bots] [--scale 6]
  --dir         katalog z plikami .jsonl (domyślnie %APPDATA%/Godot/app_userdata/Dead Air '87 Prototype/sessions)
  --out         katalog na obrazy <mapa>_heat.png (domyślnie build/heatmap; bez obrazów: --no-images)
  --map         tylko te mapy (można powtórzyć)
  --build       tylko buildy zaczynające się od tego tekstu (np. 1.7.27 = 1.7.270–1.7.279)
  --difficulty  EASY / NORMAL / HARD;  --mode campaign / night_shift
  --bots        licz też pozycje botów (domyślnie tylko ludzie — bot chodzi za człowiekiem i podwaja jego ślad)
  --json PLIK   zapisz raport także jako JSON
"""
import argparse
import glob
import json
import os
import re
import statistics
import sys
from collections import Counter, defaultdict

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:              # raport tekstowy działa bez Pillow
    Image = None

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TILE = 16                        # px świata na kafel (level.gd TILE)
BAND = 20                        # kolumn na pas w raporcie czasu
JUMP_BREAK = 400.0               # px między próbkami: dalej = teleport (odrodzenie, test) — linia trasy się urywa

SOLID = set("#CM~misO")
PLATFORM = set("=-")
TILE_COL = {"#": (70, 58, 44), "C": (104, 104, 108), "M": (120, 96, 80), "~": (40, 80, 140), "=": (190, 190, 200), "-": (170, 120, 60),
            "b": (30, 30, 36), "w": (48, 38, 30), "m": (90, 70, 40), "O": (30, 30, 30), "i": (170, 200, 220), "s": (220, 220, 230)}
SKY = (12, 14, 22)
DOWN_COL = {"stalker": (170, 80, 255), "trzosek": (255, 70, 50), "vein": (255, 200, 0), "leech": (255, 200, 0), "wolek": (255, 140, 0),
            "skoczek": (80, 220, 255), "zerca": (255, 0, 200), "rzeznik": (255, 110, 110), "kaplan": (120, 255, 160)}
OBJ_CHARS = {"F": "tag", "G": "generator", "N": "nest", "B": "boss", "K": "boss", "H": "stash"}


def default_dir():
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "Godot", "app_userdata", "Dead Air '87 Prototype", "sessions")


def load_map(map_id):
    """Siatka ASCII i rząd podziemi z danych mapy (None, gdy mapy nie ma)."""
    path = os.path.join(ROOT, "scripts", "maps", map_id + ".gd")
    if not os.path.exists(path):
        return None
    text = open(path, encoding="utf-8").read()
    m = re.search(r"const MAP := \[(.*?)\n\]", text, re.S)
    rows = re.findall(r'"([^"]*)"', m.group(1)) if m else []
    ug = re.search(r"const UNDERGROUND_ROW := (\d+)", text)
    title = re.search(r'const TITLE := "([^"]*)"', text)
    return {"rows": rows, "underground": int(ug.group(1)) if ug else 999, "title": title.group(1) if title else map_id}


def read_attempts(directory):
    """Podejścia: od `mission_start` do `mission_end` (albo końca pliku / następnego startu) z ich zdarzeniami."""
    attempts = []
    for f in sorted(glob.glob(os.path.join(directory, "*.jsonl"))):
        cur = None
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            kind = ev.get("ev")
            if kind == "mission_start":
                if cur is not None:
                    attempts.append(cur)
                cur = {"file": os.path.basename(f), "start": ev, "end": None, "pos": [], "objective": [], "down": [], "phase": []}
            elif cur is None:
                continue
            elif kind == "mission_end":
                cur["end"] = ev
                attempts.append(cur)
                cur = None
            elif kind in ("pos", "objective", "down", "phase"):
                cur[kind].append(ev)
        if cur is not None:
            attempts.append(cur)
    return attempts


def keep(a, args):
    s = a["start"]
    if args.map and s.get("map") not in args.map:
        return False
    if args.build and not str(s.get("build", "")).startswith(args.build):
        return False
    if args.difficulty and str(s.get("difficulty", "")).upper() != args.difficulty.upper():
        return False
    if args.mode and s.get("mode") != args.mode:
        return False
    return True


def samples(a, with_bots):
    """Próbki pozycji podejścia: lista (t, gracz, x, y, leży)."""
    out = []
    for ev in a["pos"]:
        for p in ev.get("p", []):
            if p.get("bot") and not with_bots:
                continue
            xy = p.get("pos") or [0, 0]
            out.append((float(ev.get("t", 0.0)), str(p.get("who", "?")), float(xy[0]), float(xy[1]), bool(p.get("dead"))))
    return out


def median(xs):
    return statistics.median(xs) if xs else None


def fmt_s(x):
    return "—" if x is None else "%.0f s" % x


def report_map(map_id, atts, mp, args):
    """Raport jednej mapy: słownik (do JSON) + wiersze tekstu."""
    res = Counter(str((a["end"] or {}).get("result", "bez końca")) for a in atts)
    times = [float(a["end"]["time"]) for a in atts if a["end"] and a["end"].get("result") == "success"]
    lines = ["== %s %s: podejść %d (%s)" % (map_id, mp["title"] if mp else "", len(atts), ", ".join("%s %d" % kv for kv in res.most_common()))]
    lines.append("   czas udanej misji: mediana %s, zakres %s–%s" % (fmt_s(median(times)), fmt_s(min(times) if times else None), fmt_s(max(times) if times else None)))
    # czas do kolejnych celów: mediana po podejściach, osobno dla każdego rodzaju celu w kolejności zaliczania
    legs = defaultdict(list)
    for a in atts:
        prev = 0.0
        order = Counter()
        for ev in sorted(a["objective"], key=lambda e: float(e.get("t", 0.0))):
            what = str(ev.get("what"))
            order[what] += 1
            t = float(ev.get("t", 0.0))
            legs[(what, order[what])].append((t, t - prev))
            prev = t
    leg_rows = []
    if legs:
        lines.append("   cele (mediana: od startu / od poprzedniego celu, liczba podejść):")
        for (what, n) in sorted(legs, key=lambda k: median([t for t, _ in legs[k]])):
            vals = legs[(what, n)]
            m_abs, m_leg = median([t for t, _ in vals]), median([d for _, d in vals])
            leg_rows.append({"what": what, "n": n, "from_start": m_abs, "leg": m_leg, "count": len(vals)})
            lines.append("     %-9s %d: %7s / %7s  (%d)" % (what, n, fmt_s(m_abs), fmt_s(m_leg), len(vals)))
    else:
        lines.append("   cele: brak zdarzeń `objective` (logi sprzed PR #348)")
    # czas w pasach kolumn (próbka = POS_EVERY s), osobno powierzchnia / podziemia
    bands = Counter()
    ug_n = 0
    total = 0
    for a in atts:
        for _, _, x, y, _ in samples(a, args.bots):
            c, r = int(x // TILE), int((y - 1) // TILE)
            bands[c // BAND] += 1
            total += 1
            if mp and r >= mp["underground"]:
                ug_n += 1
    band_rows = []
    if total:
        lines.append("   czas wg pasów %d kolumn (udział próbek pozycji, w podziemiach %d%%):" % (BAND, round(100 * ug_n / total)))
        width = max(bands) + 1
        for b in range(width):
            share = bands[b] / total
            band_rows.append({"cols": [b * BAND, b * BAND + BAND - 1], "share": round(share, 4)})
            lines.append("     kol. %3d–%3d %5.1f%% %s" % (b * BAND, b * BAND + BAND - 1, 100 * share, "#" * round(share * 60)))
    else:
        lines.append("   czas wg pasów: brak próbek `pos` (logi sprzed PR #348)")
    downs = Counter(str(d.get("source", "?")) for a in atts for d in a["down"])
    lines.append("   upadki: %d (%s)" % (sum(downs.values()), ", ".join("%s %d" % kv for kv in downs.most_common(6))))
    data = {"map": map_id, "attempts": len(atts), "results": dict(res), "success_time_median": median(times),
            "objectives": leg_rows, "time_bands": band_rows, "underground_share": round(ug_n / total, 4) if total else None,
            "downs": dict(downs)}
    return data, lines


def render_map(map_id, atts, mp, args):
    """Obraz: rzut mapy + mapa cieplna czasu + trasy + upadki + cele z siatki."""
    rows = mp["rows"]
    h, w, s = len(rows), len(rows[0]), args.scale
    img = Image.new("RGB", (w * s, h * s), SKY)
    d = ImageDraw.Draw(img)
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            col = TILE_COL.get(ch)
            if col is None:
                continue
            if ch in PLATFORM:
                d.rectangle([c * s, r * s, c * s + s - 1, r * s + max(1, s // 3)], fill=col)
            else:
                d.rectangle([c * s, r * s, c * s + s - 1, r * s + s - 1], fill=col)
    if mp["underground"] < h:
        d.line([0, mp["underground"] * s, w * s, mp["underground"] * s], fill=(90, 60, 120))
    # czas: gęstość próbek na kafel, rozmyta, jako półprzezroczysta poświata (żółty → czerwony)
    heat = Counter()
    for a in atts:
        for _, _, x, y, _ in samples(a, args.bots):
            heat[(int(x // TILE), int((y - 1) // TILE))] += 1
    if heat:
        peak = max(heat.values())
        mask = Image.new("L", img.size, 0)
        md = ImageDraw.Draw(mask)
        for (c, r), n in heat.items():
            v = int(60 + 195 * (n / peak) ** 0.5)
            md.ellipse([c * s - s, r * s - s, c * s + 2 * s, r * s + 2 * s], fill=v)
        mask = mask.filter(ImageFilter.GaussianBlur(radius=s * 1.5))
        glow = Image.new("RGB", img.size, (255, 120, 20))
        img = Image.composite(glow, img, mask.point(lambda v: int(v * 0.75)))
        d = ImageDraw.Draw(img)
    # trasy: linia na gracza i podejście, urwana przy teleporcie
    for a in atts:
        by_who = defaultdict(list)
        for t, who, x, y, _ in samples(a, args.bots):
            by_who[who].append((t, x, y))
        for pts in by_who.values():
            pts.sort()
            for (t0, x0, y0), (t1, x1, y1) in zip(pts, pts[1:]):
                if abs(x1 - x0) + abs(y1 - y0) > JUMP_BREAK:
                    continue
                d.line([x0 / TILE * s, (y0 - 8) / TILE * s, x1 / TILE * s, (y1 - 8) / TILE * s], fill=(120, 230, 255), width=1)
    # cele z siatki mapy
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            x, y = c * s + s // 2, r * s + s // 2
            if ch in OBJ_CHARS:
                d.rectangle([x - 4, y - 4, x + 4, y + 4], fill=(255, 220, 40), outline=(0, 0, 0))
            elif ch == "S":
                d.polygon([(x, y - 5), (x - 4, y + 3), (x + 4, y + 3)], fill=(60, 230, 90))
            elif ch in "Ee":
                d.rectangle([x - 4, y - 6, x + 4, y + 3], outline=(60, 200, 255), width=2)
    # upadki
    for a in atts:
        for dn in a["down"]:
            xy = dn.get("pos")
            if not xy:
                continue
            x, y = xy[0] / TILE * s, (xy[1] - 8) / TILE * s
            col = DOWN_COL.get(str(dn.get("source")), (255, 255, 255))
            d.line([x - 4, y - 4, x + 4, y + 4], fill=col, width=2)
            d.line([x - 4, y + 4, x + 4, y - 4], fill=col, width=2)
    for x in range(0, w, BAND):
        d.text((x * s + 2, 2), str(x), fill=(130, 130, 150))
    d.text((4, h * s - 14), "%s  podejsc %d  (czas: poswiata, trasy: niebieskie, upadki: krzyzyki)" % (map_id, len(atts)), fill=(230, 230, 230))
    path = os.path.join(args.out, map_id + "_heat.png")
    img.save(path)
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", default=default_dir())
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "heatmap"))
    ap.add_argument("--map", action="append")
    ap.add_argument("--build")
    ap.add_argument("--difficulty")
    ap.add_argument("--mode")
    ap.add_argument("--bots", action="store_true")
    ap.add_argument("--scale", type=int, default=6)
    ap.add_argument("--no-images", action="store_true")
    ap.add_argument("--json")
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")      # konsola Windows (cp1250) psuła polskie znaki
    if not os.path.isdir(args.dir):
        print("Brak katalogu sesji: %s" % args.dir)
        return 1
    attempts = [a for a in read_attempts(args.dir) if keep(a, args)]
    by_map = defaultdict(list)
    for a in attempts:
        by_map[str(a["start"].get("map", "?"))].append(a)
    if not by_map:
        print("Brak podejść pasujących do filtrów w %s" % args.dir)
        return 1
    images = not args.no_images and Image is not None
    if images:
        os.makedirs(args.out, exist_ok=True)
    report = []
    for map_id in sorted(by_map):
        mp = load_map(map_id)
        data, lines = report_map(map_id, by_map[map_id], mp, args)
        if images and mp and mp["rows"]:
            data["image"] = render_map(map_id, by_map[map_id], mp, args)
            lines.append("   obraz: %s" % data["image"])
        report.append(data)
        print("\n".join(lines))
    if not args.no_images and Image is None:
        print("(bez obrazów: brak Pillow — pip install pillow)")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
