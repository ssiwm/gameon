"""Raport FUN z dziennika sesji (FUN_PLAN.md §5): czy zmiany P0–P2 zmieniły rytm gry — przed / po wybranym buildzie.

Czyta pliki `user://sessions/*.jsonl` (session_log.gd) i dzieli próby misji na dwie grupy po numerze buildu (`--split`, domyślnie 1.7.401 —
pierwszy build z pakietem P0). Dla każdej grupy liczy to, co FUN_PLAN.md §1 zmierzył przed zmianami (D1–D8) i czego §5 wymaga po nich:

  Uwaga      udział czasu w pasmach (< 40, 40–59, 60–79, 80–99, 100) z próbek `pos`, mediana czasu do pierwszego ≥ 60, oddechy (`peak`)
             na próbę, udział hałasu wrogów (`noise.enemy`) w całej Uwadze
  Stalker    minuty obudzonego Stalkera, ucieczki o włos (`close_call`) na minutę, udział Stalkera w upadkach ludzi
  Q          użycia na próbę, udział udanych (nie zwietrzałych), udział użytych przy obudzonym Stalkerze
  wyniki     sukcesy / próby wg mapy i trudności, próby od punktu kontrolnego (`mission_start.checkpoint`) i ich sukcesy, próby na sesję,
             wejścia „od razu następna misja” (`mission_start.via` = direct), HP bossa przy nieudanej próbie (`mission_end.boss`, od 1.7.423)
  broń       udział największej broni w zabójstwach, skrzynie mocy (`power`) na próbę
  nagrody    cichy cel (`mission_end.silent`) wg mapy, sejfy (`strongbox`) na próbę, suma ucieczek / wabików / podniesień z `players`

Pola P0 są w dzienniku od 1.7.401, P1 od 1.7.402, P2 od 1.7.403 — starsze próby dają tylko część raportu (puste pola = brak danych).

Użycie (z prototype/): python tools/fun_report.py [--dir KATALOG] [--split 1.7.401] [--since 2026-10-27] [--difficulty NORMAL]
                                                  [--min-humans 1] [--min-time 60] [--json PLIK]
  --split        pierwszy build grupy „po” (porównanie numerów wersji, część po „+” pomijana)
  --min-time     pomija próby krótsze niż tyle sekund (testy, natychmiastowe wyjścia)
"""
import argparse
import glob
import json
import os
import statistics
import sys
from collections import Counter, defaultdict

BANDS = [("<40", 0, 40), ("40-59", 40, 60), ("60-79", 60, 80), ("80-99", 80, 100), ("100", 100, 101)]
POS_EVERY = 3.0                                           # session_log.gd POS_EVERY


def default_dir():
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "Godot", "app_userdata", "Dead Air '87 Prototype", "sessions")


def ver(build):
    """'1.7.401+abc' → (1, 7, 401); nieczytelny numer → (0,)."""
    try:
        return tuple(int(x) for x in str(build).split("+")[0].split("-")[0].split("."))
    except ValueError:
        return (0,)


def med(values):
    return round(statistics.median(values), 1) if values else None


def rate(n, d):
    return round(n / d, 2) if d else None


def load(args):
    """Pliki → lista sesji: {file, attempts: [{start, end, events: [...]}]}; zdarzenia między mission_start a mission_end należą do próby."""
    sessions = []
    for path in sorted(glob.glob(os.path.join(args.dir, "*.jsonl"))):
        name = os.path.basename(path)
        if args.since and name[:10] < args.since:
            continue
        cur = None
        attempts = []
        for line in open(path, encoding="utf-8", errors="replace"):
            try:
                e = json.loads(line)
            except ValueError:
                continue
            ev = e.get("ev")
            if ev == "mission_start":
                cur = {"start": e, "end": None, "events": []}
            elif ev == "mission_end" and cur is not None:
                cur["end"] = e
                if keep(cur, args):
                    attempts.append(cur)
                cur = None
            elif cur is not None and ev not in ("perf", "system"):
                cur["events"].append(e)
        if attempts:
            sessions.append({"file": name, "attempts": attempts})
    return sessions


def keep(a, args):
    s, e = a["start"], a["end"]
    if s.get("mode") not in (None, "campaign") or s.get("kind") == "hub":
        return False
    if float(e.get("time", 0)) < args.min_time:
        return False
    if args.difficulty and s.get("difficulty") != args.difficulty:
        return False
    return int(s.get("humans", 1)) >= args.min_humans


def awake_minutes(a):
    """Minuty obudzonego Stalkera w próbie (zdarzenia stalker awake / asleep, koniec próby zamyka przedział)."""
    total, since = 0.0, None
    for e in a["events"]:
        if e.get("ev") != "stalker":
            continue
        if e.get("what") in ("awake", "pass_in") and since is None:
            since = float(e.get("t", 0))
        elif e.get("what") in ("asleep", "pass_out") and since is not None:
            total += float(e.get("t", 0)) - since
            since = None
    if since is not None:
        total += float(a["end"].get("time", since)) - since
    return max(0.0, total) / 60.0


def group_report(attempts, n_sessions):
    r = {"attempts": len(attempts), "sessions": n_sessions}
    if not attempts:
        return r
    # --- Uwaga: pasma z próbek pos, czas do pierwszego ≥ 60, oddechy, hałas wrogów
    bands, first60 = Counter(), []
    for a in attempts:
        seen = None
        for e in a["events"]:
            if e.get("ev") != "pos":
                continue
            n = float(e.get("noise", 0))
            for name, lo, hi in BANDS:
                if lo <= n < hi:
                    bands[name] += 1
            if n >= 60 and seen is None:
                seen = float(e.get("t", 0))
        if seen is not None:
            first60.append(seen)
    tot = sum(bands.values())
    noise_all, noise_enemy = 0.0, 0.0
    for a in attempts:
        for k, v in (a["end"].get("noise") or {}).items():
            noise_all += float(v.get("sum", 0))
            if k == "enemy":
                noise_enemy += float(v.get("sum", 0))
    peaks = sum(1 for a in attempts for e in a["events"] if e.get("ev") == "peak")
    r["attention"] = {"bands_pct": {k: round(100 * bands[k] / tot) for k, _, _ in BANDS} if tot else None,
                      "first_60_median_s": med(first60), "breaths_per_attempt": rate(peaks, len(attempts)),
                      "enemy_noise_share": rate(noise_enemy, noise_all) if noise_all else None}
    # --- Stalker: minuty obudzenia, ucieczki o włos, udział w upadkach ludzi
    awake = sum(awake_minutes(a) for a in attempts)
    close = sum(1 for a in attempts for e in a["events"] if e.get("ev") == "stalker" and e.get("what") == "close_call")
    downs = [e for a in attempts for e in a["events"] if e.get("ev") == "down" and not e.get("bot")]
    swings = [e for a in attempts for e in a["events"] if e.get("ev") == "stalker" and e.get("what") in ("swing_hit", "swing_miss") and not e.get("bot")]
    r["stalker"] = {"awake_minutes": round(awake, 1), "close_calls": close, "close_calls_per_awake_min": rate(close, awake),
                    "human_downs": len(downs), "stalker_down_share": rate(sum(1 for d in downs if d.get("source") == "stalker"), len(downs)),
                    "swings_at_humans": len(swings), "hit_rate": rate(sum(1 for s in swings if s.get("what") == "swing_hit"), len(swings))}
    # --- Q
    q = [e for a in attempts for e in a["events"] if e.get("ev") == "overcharge"]
    r["lure"] = {"uses": len(q), "per_attempt": rate(len(q), len(attempts)), "fresh_share": rate(sum(1 for e in q if not e.get("stale")), len(q)),
                 "awake_share": rate(sum(1 for e in q if e.get("awake")), sum(1 for e in q if "awake" in e))}
    # --- wyniki
    by = defaultdict(lambda: [0, 0])
    for a in attempts:
        key = "%s %s" % (a["start"].get("map"), a["start"].get("difficulty"))
        by[key][0] += 1
        by[key][1] += 1 if a["end"].get("result") == "success" else 0
    cp = [a for a in attempts if a["start"].get("checkpoint")]
    direct = [a for a in attempts if a["start"].get("via") == "direct"]
    r["results"] = {"by_map": {k: "%d/%d" % (v[1], v[0]) for k, v in sorted(by.items())},
                    "attempts_per_session": rate(len(attempts), n_sessions),
                    "checkpoint_attempts": len(cp), "checkpoint_success": sum(1 for a in cp if a["end"].get("result") == "success"),
                    "direct_next": len(direct)}
    # --- boss: ile HP zostało przy nieudanej próbie (`mission_end.boss`, od 1.7.423)
    left = defaultdict(list)
    for a in attempts:
        b = a["end"].get("boss")
        if b and a["end"].get("result") != "success" and b.get("max_hp"):
            left["%s %s" % (b.get("kind"), a["start"].get("difficulty"))].append(100.0 * float(b.get("hp", 0)) / float(b["max_hp"]))
    r["results"]["boss_hp_left_pct"] = {k: "mediana %s%% (min %d%%, n=%d)" % (med(v), round(min(v)), len(v)) for k, v in sorted(left.items())}
    # --- broń i skrzynie mocy
    wk = Counter()
    for a in attempts:
        for k, w in (a["end"].get("weapons") or {}).items():
            wk[k] += int(w.get("kills", 0))
    kills = sum(wk.values())
    top = wk.most_common(1)[0] if wk else None
    power = [e for a in attempts for e in a["events"] if e.get("ev") == "power"]
    r["weapons"] = {"top": "%s %d%%" % (top[0], round(100 * top[1] / kills)) if top and kills else None,
                    "power_pickups": len(power), "power_by_weapon": dict(Counter(e.get("weapon") for e in power))}
    # --- nagrody
    silent = defaultdict(lambda: [0, 0])
    for a in attempts:
        if a["end"].get("result") == "success" and "silent" in a["end"]:
            m = a["start"].get("map")
            silent[m][0] += 1
            silent[m][1] += 1 if a["end"]["silent"] else 0
    boxes = sum(1 for a in attempts for e in a["events"] if e.get("ev") == "strongbox")
    pl = Counter()
    for a in attempts:
        for p in (a["end"].get("players") or {}).values():
            for k in ("escapes", "lures", "revives"):
                pl[k] += int(p.get(k, 0))
    r["rewards"] = {"silent_kept": {m: "%d/%d" % (v[1], v[0]) for m, v in sorted(silent.items())},
                    "strongboxes": boxes, "strongboxes_per_attempt": rate(boxes, len(attempts)), "players": dict(pl)}
    # --- latarka i baterie (BATTERY_PLAN.md B0, od 1.7.450): próbki pos ludzi z `bat`, liczniki mission_end.battery
    lamp_on, low, samples, mins = 0, 0, 0, []
    for a in attempts:
        lo = {}
        for e in a["events"]:
            if e.get("ev") != "pos":
                continue
            for q in e.get("p", []):
                if q.get("bot") or "bat" not in q:
                    continue
                samples += 1
                lamp_on += 1 if q.get("lamp") else 0
                low += 1 if int(q["bat"]) < 20 else 0
                lo[q.get("who")] = min(lo.get(q.get("who"), 100), int(q["bat"]))
        mins.extend(lo.values())
    bat = Counter()
    for a in attempts:
        for k, v in (a["end"].get("battery") or {}).items():
            bat[k] += int(v)
    r["battery"] = {"lamp_share": rate(lamp_on, samples), "below_20_share": rate(low, samples), "min_pct_median": med(mins) if mins else None,
                    "empty_per_attempt": rate(bat["empty"], len(attempts)), "picked": bat["picked"], "dropped": bat["dropped"], "charger": bat["charger"],
                    "attempts_with_data": sum(1 for a in attempts if "battery" in a["end"])}
    return r


def report(sessions, split):
    groups = {"before": ([], set()), "after": ([], set())}
    for s in sessions:
        for a in s["attempts"]:
            g = "after" if ver(a["start"].get("build", "")) >= split else "before"
            groups[g][0].append(a)
            groups[g][1].add(s["file"])
    return {"split": ".".join(str(x) for x in split),
            "before": group_report(groups["before"][0], len(groups["before"][1])),
            "after": group_report(groups["after"][0], len(groups["after"][1]))}


def print_report(rep):
    print("== Raport FUN (FUN_PLAN.md §5): przed / po buildzie %s" % rep["split"])
    for g, title in (("before", "PRZED"), ("after", "PO")):
        r = rep[g]
        print("\n== %s: %d prób w %d plikach" % (title, r["attempts"], r["sessions"]))
        if not r["attempts"]:
            continue
        at, st, lu, rs, wp, rw = r["attention"], r["stalker"], r["lure"], r["results"], r["weapons"], r["rewards"]
        print("   Uwaga: pasma %% czasu %s;  pierwsze ≥ 60 po %s s;  oddechy na próbę %s;  udział hałasu wrogów %s"
              % (at["bands_pct"], at["first_60_median_s"], at["breaths_per_attempt"], at["enemy_noise_share"]))
        print("   Stalker: obudzony %s min;  ucieczki o włos %s (%s/min);  zamachy w ludzi %s, trafione %s;  udział w upadkach ludzi %s (z %d)"
              % (st["awake_minutes"], st["close_calls"], st["close_calls_per_awake_min"], st["swings_at_humans"], st["hit_rate"],
                 st["stalker_down_share"], st["human_downs"]))
        print("   Q: %d użyć (%s na próbę), udane %s, przy obudzonym %s" % (lu["uses"], lu["per_attempt"], lu["fresh_share"], lu["awake_share"]))
        print("   wyniki: %s" % rs["by_map"])
        print("           prób na plik %s;  od punktu kontrolnego %d (sukcesy %d);  „od razu następna misja” %d"
              % (rs["attempts_per_session"], rs["checkpoint_attempts"], rs["checkpoint_success"], rs["direct_next"]))
        if rs["boss_hp_left_pct"]:
            print("           HP bossa przy nieudanej próbie: %s" % rs["boss_hp_left_pct"])
        print("   broń: największy udział %s;  skrzynie mocy %d %s" % (wp["top"], wp["power_pickups"], wp["power_by_weapon"] or ""))
        bt = r.get("battery") or {}
        if bt.get("attempts_with_data"):
            print("   latarka: świeci %s czasu, poniżej 20%% %s;  najniższa bateria (mediana) %s%%;  puste na próbę %s;  baterie zebrane %d, wypadło %d;  ładowarka %d× (prób z danymi %d)"
                  % (bt["lamp_share"], bt["below_20_share"], bt["min_pct_median"], bt["empty_per_attempt"], bt["picked"], bt["dropped"], bt["charger"],
                     bt["attempts_with_data"]))
        print("   nagrody: cichy cel (dotrzymany/sukcesy) %s;  sejfy %d (%s na próbę);  gracze %s"
              % (rw["silent_kept"], rw["strongboxes"], rw["strongboxes_per_attempt"], rw["players"]))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", default=default_dir())
    ap.add_argument("--split", default="1.7.401")
    ap.add_argument("--since", default="")
    ap.add_argument("--difficulty", default="")
    ap.add_argument("--min-humans", type=int, default=1)
    ap.add_argument("--min-time", type=float, default=60.0)
    ap.add_argument("--json", default="")
    args = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8")         # konsola Windows (cp1250) nie zna „≥”
    except (AttributeError, ValueError):
        pass
    if not os.path.isdir(args.dir):
        print("Brak katalogu z dziennikami: %s" % args.dir, file=sys.stderr)
        return 1
    rep = report(load(args), ver(args.split))
    print_report(rep)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(rep, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
