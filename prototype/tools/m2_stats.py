"""Statystyki przebiegów z1_m2 (m2_runs.json): fazy, pasy, upadki, Stalker, hałas. Użycie: python m2_stats.py <m2_runs.json> [min_build]"""
import sys, json, collections, statistics as st
runs = json.load(open(sys.argv[1]))
minb = int(sys.argv[2]) if len(sys.argv) > 2 else 0
def bn(r): return int(r["start"].get("build", "0.0.0").split('+')[0].split('.')[2])
runs = [r for r in runs if bn(r) >= minb]
print("przebiegów", len(runs), "buildy", bn(runs[0]), "-", bn(runs[-1]))
def med(a): return round(st.median(a), 1) if a else None
res = collections.Counter((r["start"].get("difficulty"), (r["end"] or {}).get("result", "brak")) for r in runs)
print("wyniki", sorted(res.items()))
# odcinki czasu
segs = collections.defaultdict(list)
for r in runs:
    g = [o["t"] for o in r["obj"] if o.get("what") == "generator"]
    prev = 0.0
    for i, t in enumerate(g):
        segs["G%d" % (i + 1)].append(t - prev); prev = t
    if len(g) == 4 and r["end"] and r["end"].get("result") == "success":
        segs["ewakuacja"].append(r["end"]["time"] - g[3]); segs["cała"].append(r["end"]["time"])
    order = [(round(o["pos"][0] / 16), round(o["pos"][1] / 16)) for o in r["obj"] if o.get("what") == "generator"]
    segs["kolejność"].append(tuple(c for c, _ in order))
for k in ["G1", "G2", "G3", "G4", "ewakuacja", "cała"]:
    a = segs[k]; print(k, "n", len(a), "mediana", med(a), "min", round(min(a)) if a else None, "max", round(max(a)) if a else None)
print("kolejność generatorów", collections.Counter(segs["kolejność"]).most_common(6))
# próbki pozycji: poziom i pas
def level(y):
    rr = y / 16.0
    return "pow" if rr <= 27 else ("hala" if rr <= 41 else "tunel")
band = collections.Counter(); bandph = collections.Counter(); crouch = collections.Counter(); tot = 0
lev = collections.Counter()
for r in runs:
    for p in r["pos"]:
        for pl in p["p"]:
            if pl.get("bot") or pl.get("dead"): continue
            c = int(pl["pos"][0] / 16); L = level(pl["pos"][1])
            band[(L, c // 20 * 20)] += 1; lev[(p.get("phase"), L)] += 1; tot += 1
            if pl.get("crouch"): crouch[(L, c // 20 * 20)] += 1
print("próbek", tot, "(x3 s)"); print("faza/poziom", sorted(lev.items()))
for L in ("pow", "hala", "tunel"):
    print(L, " ".join("%d:%ds(%d%%k)" % (b, band[(L, b)] * 3 // len(runs), 100 * crouch[(L, b)] // max(1, band[(L, b)])) for b in range(0, 288, 20) if band[(L, b)]))
# upadki
dn = collections.Counter(); src = collections.Counter(); dph = collections.Counter(); pts = []
for r in runs:
    for d in r["downs"]:
        if d.get("bot"): continue
        c = int(d["pos"][0] / 16); L = level(d["pos"][1])
        dn[(L, c // 20 * 20)] += 1; src[d.get("source")] += 1; dph[(d.get("phase"), L)] += 1; pts.append((c, round(d["pos"][1] / 16), d.get("source"), d.get("phase"), round(d["t"])))
print("upadki ludzi", sum(dn.values()), sorted(dn.items())); print("źródła", src.most_common()); print("faza/poziom", sorted(dph.items()))
print(pts)
# Stalker
whats = collections.Counter(); first = []; awake_noise = []
for r in runs:
    a = [s for s in r["stalker"] if s.get("what") == "awake"]
    for s in r["stalker"]: whats[s.get("what")] += 1
    if a: first.append(a[0]["t"]); awake_noise.append(a[0].get("noise"))
print("stalker zdarzenia", whats.most_common()); print("pierwsze przebudzenie: mediana", med(first), "min", min(first) if first else None, "n", len(first), "z", len(runs))
# hałas: kiedy pierwszy raz >= 40 / 80 / 100
for th in (40, 80, 100):
    ts = []; cs = []
    for r in runs:
        for p in r["pos"]:
            if p.get("noise", 0) >= th:
                ts.append(p["t"]); hp = [pl for pl in p["p"] if not pl.get("bot")]
                if hp: cs.append(int(hp[0]["pos"][0] / 16))
                break
    print("Uwaga >=", th, "pierwszy raz: mediana t", med(ts), "kol.", med(cs), "n", len(ts))
g1 = [o["t"] for r in runs for o in r["obj"] if o.get("n") == 1]
print("side: ", collections.Counter((r["end"] or {}).get("side") for r in runs))
# hałas wg źródła
ns = collections.Counter()
for r in runs:
    for k, v in ((r["end"] or {}).get("noise") or {}).items(): ns[k] += v.get("sum", 0)
t = sum(ns.values()) or 1
print("hałas źródła", [(k, round(100 * v / t)) for k, v in ns.most_common()])
