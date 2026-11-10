"""Drugi przebieg po m2_runs.json: wykrwawienia i wyjścia z gry, jazda drezyną, szyby hali, czas w strefach. python m2_stats2.py <m2_runs.json> [min_build]"""
import sys, json, collections, statistics as st
runs = json.load(open(sys.argv[1])); minb = int(sys.argv[2]) if len(sys.argv) > 2 else 0
def bn(r): return int(r["start"].get("build", "0.0.0").split('+')[0].split('.')[2])
runs = [r for r in runs if bn(r) >= minb]
def med(a): return round(st.median(a), 1) if a else None
def hp(p):
    for pl in p["p"]:
        if not pl.get("bot"): return pl
    return None
print("== wykrwawienie -> co dalej")
for r in runs:
    for b in r["bleed"]:
        if b.get("bot"): continue
        d = [x for x in r["downs"] if not x.get("bot") and x["t"] <= b["t"]]
        dpos = (int(d[-1]["pos"][0] / 16), int(d[-1]["pos"][1] / 16)) if d else None
        after = [p for p in r["pos"] if p["t"] > b["t"]]
        first = hp(after[0]) if after else None
        fpos = (int(first["pos"][0] / 16), int(first["pos"][1] / 16)) if first else None
        end = (r["end"] or {}).get("result", "brak"); tend = (r["end"] or {}).get("time", r["last_t"])
        gens = len([o for o in r["obj"] if o.get("what") == "generator" and o["t"] <= b["t"]])
        # ile s wracał do miejsca upadku (±10 kol.)
        back = None
        if dpos:
            for p in after:
                h = hp(p)
                if h and abs(h["pos"][0] / 16 - dpos[0]) < 10: back = round(p["t"] - b["t"]); break
        print(bn(r), r["start"]["difficulty"], "upadek", dpos, "t=%d" % b["t"], "gen", gens, "odrodzenie", fpos, "powrót po s:", back, "koniec:", end, "po %d s" % (tend - b["t"]))
print("== gdzie kończą się wyjścia z gry (quit / brak)")
for r in runs:
    end = (r["end"] or {}).get("result", "brak")
    if end in ("quit", "brak"):
        h = hp(r["pos"][-1]) if r["pos"] else None
        gens = len([o for o in r["obj"] if o.get("what") == "generator"])
        ph = r["pos"][-1].get("phase") if r["pos"] else None
        print(bn(r), r["start"]["difficulty"], "t=%d" % r["last_t"], "gen", gens, ph, "pos", (int(h["pos"][0] / 16), int(h["pos"][1] / 16)) if h else None, "upadki", len(r["downs"]), "wykrw", len(r["bleed"]))
print("== ewakuacja: G4 -> tunel -> koniec")
to_tun = []; ride = []; stops = []; spd = []
for r in runs:
    g = [o["t"] for o in r["obj"] if o.get("what") == "generator"]
    if len(g) < 4: continue
    ex = [p for p in r["pos"] if p["t"] > g[3]]
    tin = None; last = None; stop = 0; mv = 0; xs = []
    for p in ex:
        h = hp(p)
        if not h or h.get("dead"): continue
        if h["pos"][1] / 16 > 43:
            if tin is None: tin = p["t"]
            if last is not None:
                dx = last[0] - h["pos"][0]; dt = p["t"] - last[1]
                if dt > 0:
                    v = dx / dt; xs.append(v)
                    if v < 20: stop += dt
                    else: mv += dt
            last = (h["pos"][0], p["t"])
    if tin is None: continue
    end = (r["end"] or {}).get("result", "brak"); tend = (r["end"] or {}).get("time", r["last_t"])
    lastx = int(last[0] / 16) if last else None
    print(bn(r), r["start"]["difficulty"], "G4->tunel %d s" % (tin - g[3]), "w tunelu %d s" % (tend - tin), "jazda %d s, postój %d s" % (mv, stop), "ostatnia kol.", lastx, end)
    to_tun.append(tin - g[3])
    if end == "success": ride.append(tend - tin); stops.append(stop)
print("mediana G4->tunel", med(to_tun), "tunel przy sukcesie", med(ride), "postoje", med(stops))
print("== którym szybem do hali / z hali (faza celu)")
down = collections.Counter(); up = collections.Counter()
for r in runs:
    prev = None
    for p in r["pos"]:
        h = hp(p)
        if not h or h.get("dead"): continue
        c = h["pos"][0] / 16; lv = "pow" if h["pos"][1] / 16 <= 27 else ("hala" if h["pos"][1] / 16 <= 41 else "tunel")
        if prev and prev[1] != lv and "hala" in (prev[1], lv) and "tunel" not in (prev[1], lv):
            side = "zach" if c < 180 else "wsch"
            (down if lv == "hala" else up)[side] += 1
        prev = (c, lv)
print("zejścia", dict(down), "wyjścia", dict(up))
print("== czas w strefach (s na przebieg, tylko przebiegi, które tam dotarły)")
zones = [("skraj lasu 0-41", 0, 41, "pow"), ("dziedziniec 42-65", 42, 65, "pow"), ("hala stacji 66-100", 66, 100, "pow"), ("bagno 101-150", 101, 150, "pow"),
         ("nad halą 151-215", 151, 215, "pow"), ("pompownia 216-246", 216, 246, "pow"), ("maszt 247-287", 247, 287, "pow"), ("hala podziemna", 0, 287, "hala"), ("tunel", 0, 287, "tunel")]
for name, c0, c1, lv in zones:
    per = []
    for r in runs:
        n = 0
        for p in r["pos"]:
            h = hp(p)
            if not h or h.get("dead"): continue
            c = h["pos"][0] / 16; l = "pow" if h["pos"][1] / 16 <= 27 else ("hala" if h["pos"][1] / 16 <= 41 else "tunel")
            if l == lv and c0 <= c <= c1: n += 1
        if n: per.append(n * 3)
    print("%-22s n=%2d mediana %s s" % (name, len(per), med(per)))
