"""Podejścia do z1_m2 z dziennika sesji: tabela przebiegów + zrzut do json. Użycie: python m2_sess.py <katalog sesji> <out.json>"""
import sys, json, glob, os, collections
D, out = sys.argv[1], sys.argv[2]
runs = []
for f in sorted(glob.glob(os.path.join(D, '*.jsonl'))):
    cur = None
    for l in open(f, encoding='utf-8'):
        try: j = json.loads(l)
        except: continue
        e = j.get('ev')
        if e == 'mission_start':
            if cur: runs.append(cur)
            cur = None
            if j.get('map') == 'z1_m2':
                cur = {"file": os.path.basename(f), "start": j, "obj": [], "downs": [], "bleed": [], "stalker": [], "pos": [], "phase": [], "end": None,
                       "elite": [], "break": [], "item": [], "strongbox": [], "power": [], "revive": [], "last_t": 0.0, "other": collections.Counter()}
            continue
        if not cur: continue
        cur["last_t"] = max(cur["last_t"], j.get('t', 0.0))
        if e == 'objective': cur["obj"].append(j)
        elif e == 'down': cur["downs"].append(j)
        elif e == 'bleed_out': cur["bleed"].append(j)
        elif e == 'stalker': cur["stalker"].append(j)
        elif e == 'pos': cur["pos"].append(j)
        elif e == 'phase': cur["phase"].append(j)
        elif e in ('elite', 'break', 'item', 'strongbox', 'power', 'revive'): cur[e].append(j)
        elif e == 'mission_end':
            cur["end"] = j; runs.append(cur); cur = None
        else: cur["other"][e] += 1
    if cur: runs.append(cur)
def real(r):
    # test automatyczny: cele w kilka sekund albo brak próbek pozycji
    if len(r["pos"]) < 15: return False
    if r["obj"] and r["obj"][0]["t"] < 30: return False
    return True
good = [r for r in runs if real(r)]
print("wszystkich startów", len(runs), "prawdziwych", len(good))
print("plik | build | trudn | ludzie+boty | wynik | czas | próby | upadki | gen t | EXTRACT t | szczyt | side")
for r in good:
    s, e = r["start"], r["end"]
    gens = [round(o["t"]) for o in r["obj"] if o.get("what") == "generator"]
    ext = [round(p["t"]) for p in r["phase"] if p.get("phase") == "EXTRACT"]
    print(r["file"][:16], s.get("build", "?").split('+')[0], s.get("difficulty"), "%d+%d" % (s.get("humans", 0), s.get("bots", 0)), s.get("attempt"),
          (e or {}).get("result", "—"), round((e or {}).get("time", r["last_t"])), "dn", len(r["downs"]), "bl", len(r["bleed"]), gens, ext,
          (e or {}).get("peak_noise"), (e or {}).get("side"))
for r in good: r["other"] = dict(r["other"])
json.dump(good, open(out, 'w'))
