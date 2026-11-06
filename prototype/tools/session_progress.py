"""Raport progresji z dziennika sesji (PROGRESSION_PLAN.md P0.5).

Czyta pliki `user://sessions/*.jsonl` (session_log.gd; podkatalogi, np. `_perf_test`, pomija) i wypisuje to, czego plan potrzebuje
do strojenia progresji: tempo kampanii (misje na sesję, najdalsza mapa, wipe'y na sukces), złom i XP na udaną misję i na minutę
wg mapy, poziomy i perki graczy, zakupy w kryjówce (`hub_buy`), próbki, udział broni w zabójstwach i Nocny Dyżur. Na końcu
sygnały ostrzegawcze z progami z PROGRESSION_PLAN.md §4.

Sekcja „Niszczenie” (DESTRUCTION_PLAN.md „Pomiar po wdrożeniu”): zdarzenia `break`, `crate`, `lamp`, `window`, `barricade`, `support`
i `cave` (od 1.7.485–1.7.492; `break` od 1.7.493) — ile prób w ogóle coś niszczy, czym i kto (gracze / wrogowie), łup ze skrzyń,
barykady (ile przybitych, ile sekund wytrzymały, kto je rozbił), zawały i czy po zniszczeniu budzą się Stalker albo elity;
od 1.7.503 także `dig_find` — znajdźki wykopane w strefach wydobycia (D5): ile, czym, co wypadło; od 1.7.504 `dig_fall` —
spadające wyspy w strefach (ile, jak duże).

Pola XP / poziomu / perków (`xp`, `level`, `perks` w `mission_start.equipment`, wiersz `xp`, `players[id].kinds` i `xp_kills`)
oraz `hub_buy` są w dzienniku od 1.7.391 — starsze pliki dają tylko część raportu (wyniki, czasy, złom od 1.7.347).

Użycie (z prototype/): python tools/session_progress.py [--dir KATALOG] [--build 1.7.39] [--since 2026-10-27] [--difficulty NORMAL]
                                                      [--min-humans 2] [--json PLIK]
  --dir          katalog z plikami .jsonl (domyślnie %APPDATA%/Godot/app_userdata/Dead Air '87 Prototype/sessions)
  --build        tylko buildy zaczynające się od tego tekstu
  --since        tylko pliki z datą w nazwie od tego dnia (RRRR-MM-DD)
  --difficulty   EASY / NORMAL / HARD
  --min-humans   tylko próby z co najmniej tyloma ludźmi (np. 2 = sesje co-op z testerami)
  --json PLIK    zapisz raport także jako JSON
"""
import argparse
import glob
import json
import os
import statistics
import sys
from collections import Counter, defaultdict

CAMPAIGN = ["z1_m1", "z1_m2", "z1_m3", "z1_b1"]          # level.gd CAMPAIGN
WRECK_EVENTS = ("break", "crate", "lamp", "window", "barricade", "support", "cave", "dig_find", "dig_fall")   # DESTRUCTION_PLAN.md, dziennik sesji
WAKE_WINDOW_S = 20.0                                       # pobudka Stalkera / elity tyle sekund po zniszczeniu liczy się jako „ściągnięta”
DESTRUCTION_SINCE = (1, 7, 485)                            # pierwsze rekwizyty do rozbicia (D1) — starsze próby nie wchodzą do sekcji niszczenia


def build_version(build):
    """„1.7.492+abc1234” → (1, 7, 492); nieczytelne → ()."""
    try:
        return tuple(int(x) for x in str(build).split("+")[0].split("."))
    except ValueError:
        return ()
LEVEL_STEPS = (50, 100)                                    # profile.gd STEP_BASE, STEP_PER_LEVEL


def default_dir():
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "Godot", "app_userdata", "Dead Air '87 Prototype", "sessions")


def xp_for_level(n):
    return sum(LEVEL_STEPS[0] + LEVEL_STEPS[1] * k for k in range(1, n))


def med(values):
    return round(statistics.median(values), 1) if values else None


def load(args):
    """Pliki → lista sesji: {file, attempts: [...], buys: [...]} w kolejności zapisu."""
    sessions = []
    for path in sorted(glob.glob(os.path.join(args.dir, "*.jsonl"))):
        name = os.path.basename(path)
        if args.since and name[:10] < args.since:
            continue
        cur = None
        attempts, buys, hints = [], [], []
        last_success = None
        for line in open(path, encoding="utf-8", errors="replace"):
            try:
                e = json.loads(line)
            except ValueError:
                continue
            ev = e.get("ev")
            if ev == "mission_start":
                cur = {"start": e, "end": None, "xp": [], "wreck": [], "wakes": []}
            elif ev == "mission_end" and cur is not None:
                cur["end"] = e
                attempts.append(cur)
                last_success = cur if e.get("result") == "success" else None
                cur = None
            elif ev == "xp" and last_success is not None:
                last_success["xp"].append(e)          # raport XP przychodzi po mission_end udanej próby
            elif ev in WRECK_EVENTS and cur is not None:
                cur["wreck"].append(e)
            elif cur is not None and ((ev == "stalker" and e.get("what") == "awake") or (ev == "elite" and e.get("what") == "wake")):
                cur["wakes"].append(float(e.get("t", 0.0)))
            elif ev == "hub_buy":
                buys.append(e)
            elif ev == "hint":
                hints.append(e.get("id"))
        attempts = [a for a in attempts if keep(a, args)]
        if attempts or buys:
            sessions.append({"file": name, "attempts": attempts, "buys": buys, "hints": hints})
    return sessions


def keep(a, args):
    s = a["start"]
    if args.build and not str(s.get("build", "")).startswith(args.build):
        return False
    if args.difficulty and s.get("difficulty") != args.difficulty:
        return False
    return int(s.get("humans", 1)) >= args.min_humans


def report(sessions):
    rep = {}
    attempts = [a for s in sessions for a in s["attempts"]]
    campaign = [a for a in attempts if a["start"].get("mode") == "campaign"]

    # --- sesje i tempo kampanii
    per_session = [len(s["attempts"]) for s in sessions if s["attempts"]]
    furthest = Counter()
    for s in sessions:
        done = [CAMPAIGN.index(a["start"]["map"]) for a in s["attempts"] if a["start"].get("map") in CAMPAIGN]
        if done:
            furthest[CAMPAIGN[max(done)]] += 1
    rep["sessions"] = {"files": len(sessions), "attempts_per_session_median": med(per_session),
                       "first_map": dict(Counter(s["attempts"][0]["start"].get("map") for s in sessions if s["attempts"])),
                       "furthest_map": dict(furthest)}

    # --- mapy: wyniki, czas, złom, XP
    maps = {}
    for m in CAMPAIGN:
        rows = [a for a in campaign if a["start"].get("map") == m]
        if not rows:
            continue
        succ = [a for a in rows if a["end"].get("result") == "success"]
        wipes = [a for a in rows if a["end"].get("result") == "wipe"]
        quits = [a for a in rows if a["end"].get("result") == "quit"]       # od 1.7.397: drużyna wyszła w trakcie (how: exit / leave)
        t = [float(a["end"].get("time", 0)) for a in succ]
        banked = [int(a["end"]["scrap"].get("loot", 0)) + int(a["end"]["scrap"].get("bonus", 0)) for a in succ if "scrap" in a["end"]]
        per_min = [b / (float(a["end"]["time"]) / 60.0) for a, b in zip([a for a in succ if "scrap" in a["end"]], banked) if float(a["end"].get("time", 0)) > 0]
        xp_mission, xp_kills, kinds = [], [], Counter()
        for a in succ:
            for x in a["xp"]:
                xp_mission.append(int(x.get("mission", 0)))
            for p in (a["end"].get("players") or {}).values():
                if "xp_kills" in p:
                    xp_kills.append(int(p["xp_kills"]))
                kinds.update(p.get("kinds", {}))
        xp_total = (med(xp_mission) or 0) + (med(xp_kills) or 0) if xp_mission else None
        # od 1.7.400 (NOBOT_PLAN.md): próby bez bota — host wyłączył towarzysza albo w sesji nie było bota (3+ ludzi)
        nobot = [a for a in rows if a["start"].get("ai_companion") is False or int(a["start"].get("bots", 1)) == 0]
        split = {}
        for name, part in (("z botem", [a for a in rows if a not in nobot]), ("bez bota", nobot)):
            if part:
                split[name] = {"attempts": len(part), "success": sum(1 for a in part if a["end"].get("result") == "success"),
                               "wipes": sum(1 for a in part if a["end"].get("result") == "wipe")}
        maps[m] = {"attempts": len(rows), "success": len(succ), "wipes": len(wipes), "quits": len(quits), "bot_split": split,
                   "quit_after_wipe": sum(1 for a in quits if int(a["end"].get("attempts", 1)) > 1),
                   "wipes_per_success": round(len(wipes) / len(succ), 2) if succ else None,
                   "time_success_median_s": med(t), "scrap_banked_median": med(banked),
                   "scrap_per_min_median": med(per_min), "side_rate": round(sum(1 for a in succ if a["end"].get("side")) / len(succ), 2) if succ else None,
                   "xp_mission_median": med(xp_mission), "xp_kills_median": med(xp_kills), "xp_per_success": xp_total,
                   "xp_per_min": round(xp_total / (med(t) / 60.0), 1) if xp_total and med(t) else None,
                   "kills_by_kind": dict(kinds.most_common())}
    rep["maps"] = maps

    # --- poziomy i perki (z equipment w mission_start; od 1.7.391)
    eq = [e for a in attempts for e in a["start"].get("equipment", []) if "level" in e]
    lv = Counter(int(e["level"]) for e in eq)
    perk_ok = [bool(e.get("perks")) for e in eq if int(e["level"]) >= 2]
    perk2_ok = [len(e.get("perks", [])) >= 2 for e in eq if int(e["level"]) >= 4]
    # minuty misji (wszystkie próby) do kolejnych poziomów gracza 1 (host: ten sam profil we wszystkich plikach)
    minutes, reached = 0.0, {}
    for a in attempts:
        for e in a["start"].get("equipment", []):
            if int(e.get("who", 0)) == 1 and "level" in e:
                for n in range(2, int(e["level"]) + 1):
                    reached.setdefault(n, round(minutes, 1))
        minutes += float(a["end"].get("time", 0)) / 60.0
    rep["profile"] = {"level_at_start": dict(sorted(lv.items())), "perk_rate_l2": round(sum(perk_ok) / len(perk_ok), 2) if perk_ok else None,
                      "two_perks_rate_l4": round(sum(perk2_ok) / len(perk2_ok), 2) if perk2_ok else None,
                      "host_minutes_to_level": reached,
                      "curve": {n: xp_for_level(n) for n in range(2, 11)}}

    # --- kryjówka: zakupy, odmowy, saldo
    buys = [b for s in sessions for b in s["buys"]]
    ok = [b for b in buys if b.get("ok")]
    spent = Counter()
    for b in ok:
        spent[b.get("kind", "?")] += int(b.get("cost", 0))
    visits = [a["start"] for a in campaign if "hub_seconds" in a["start"]]
    bank = [int(a["start"]["workshop"]["bank"]) for a in campaign if "workshop" in a["start"]]
    rep["hub"] = {"operations": len(buys), "ok": len(ok), "poor_rate": round(sum(1 for b in buys if b.get("reason") == "poor") / len(buys), 2) if buys else None,
                  "reasons": dict(Counter(b.get("reason") for b in buys if not b.get("ok"))),
                  "spent_by_kind": dict(spent), "count_by_kind": dict(Counter(b.get("kind") for b in ok)),
                  "hub_seconds_median": med([float(v["hub_seconds"]) for v in visits]), "visits": len(visits),
                  "bank_first_last": [bank[0], bank[-1]] if bank else None, "bank_max": max(bank) if bank else None}

    # --- próbki i badania
    samples = [int(a["start"]["workshop"].get("samples", 0)) for a in campaign if "workshop" in a["start"]]
    rep["samples"] = {"bank_last": samples[-1] if samples else None, "bank_max": max(samples) if samples else None,
                      "research_ok": sum(1 for b in ok if b.get("kind") == "research")}

    # --- broń
    wk = Counter()
    for a in attempts:
        for k, w in (a["end"].get("weapons") or {}).items():
            wk[k] += int(w.get("kills", 0))
    total = sum(wk.values())
    rep["weapons"] = {"kills": dict(wk.most_common()), "top_share": round(wk.most_common(1)[0][1] / total, 2) if total else None,
                      "bought": [b.get("id") for b in ok if b.get("kind") == "weapon"]}

    rep["night_shift"] = {"attempts": sum(1 for a in attempts if a["start"].get("mode") == "night_shift")}
    # przedmioty (od 1.7.467): mission_end.items; próby bez tego pola (starsze buildy) nie liczą się do średniej
    with_items = [a for a in attempts if "items" in a["end"]]
    items = Counter()
    for a in with_items:
        items.update(a["end"]["items"])
    rep["items"] = {"attempts_with_data": len(with_items), "total": dict(items.most_common())}
    hints = Counter()
    for s in sessions:
        hints.update(s.get("hints", []))
    rep["hints"] = dict(hints.most_common())
    rep["destruction"] = destruction([a for a in attempts if build_version(a["start"].get("build", "")) >= DESTRUCTION_SINCE])
    rep["warnings"] = warnings(rep)
    return rep


def destruction(attempts):
    """Niszczenie (DESTRUCTION_PLAN.md „Pomiar po wdrożeniu”): co, czym, kto, czy się opłaca, czy ściąga wrogów."""
    by_map = defaultdict(lambda: {"attempts": 0, "with_any": 0, "events": Counter(), "opened_per_attempt": []})
    mats = defaultdict(Counter)              # materiał → czym rozbity
    who = Counter()                          # gracz / wróg (rodzaj) / inne (wybuch bez sprawcy)
    crates = {"n": 0, "scrap": 0, "battery": 0, "planks": 0}
    nails, full, held, held_by = 0, 0, [], Counter()
    attempts_nailing = 0
    caves, crushed = 0, []
    support_by, lamp_by, window_by = Counter(), Counter(), Counter()
    dig_by, dig_item = Counter(), Counter()
    dig_fall = []
    noise_at_break = []
    loud, woke = 0, 0
    for a in attempts:
        mp = by_map[a["start"].get("map", "?")]
        mp["attempts"] += 1
        evs = a.get("wreck", [])
        if evs:
            mp["with_any"] += 1
        opened = set()
        nailed_here = False
        for e in evs:
            ev = e.get("ev")
            mp["events"][ev] += 1
            if ev == "break":
                mats[e.get("mat", "?")][e.get("by", "?")] += 1
                who["wróg: " + e["src"] if e.get("src") else ("gracz" if int(e.get("shooter", -1)) > 0 else "inne")] += 1
                opened.add(e.get("name"))
                noise_at_break.append(float(e.get("noise", 0)))
                if "held" in e:
                    held.append(float(e["held"]))
                    held_by[e.get("src") or e.get("by", "?")] += 1
            elif ev == "crate":
                crates["n"] += 1
                crates["scrap"] += int(e.get("scrap", 0))
                crates["battery"] += int(e.get("battery", 0))
                crates["planks"] += int(e.get("planks", 0))
            elif ev == "barricade":
                nails += 1
                nailed_here = True
                if int(e.get("boards", 0)) >= 3:
                    full += 1
            elif ev == "cave":
                caves += 1
                crushed.append(int(e.get("crushed", 0)))
            elif ev == "support":
                support_by[e.get("by", "?")] += 1
            elif ev == "lamp":
                lamp_by[e.get("by") or "?"] += 1
            elif ev == "window":
                window_by[e.get("by") or "?"] += 1
            elif ev == "dig_find":
                dig_by[e.get("by", "?")] += 1
                dig_item[e.get("item") or "nic"] += 1
            elif ev == "dig_fall":
                dig_fall.append(int(e.get("cells", 0)))
            if ev in ("break", "crate", "lamp", "window", "cave", "dig_fall"):
                loud += 1
                t = float(e.get("t", 0.0))
                if any(t <= w <= t + WAKE_WINDOW_S for w in a.get("wakes", [])):
                    woke += 1
        mp["opened_per_attempt"].append(len(opened))
        attempts_nailing += 1 if nailed_here else 0
    maps = {}
    for k, m in sorted(by_map.items()):
        maps[k] = {"attempts": m["attempts"], "with_any_rate": round(m["with_any"] / m["attempts"], 2) if m["attempts"] else None,
                   "events": dict(m["events"].most_common()), "opened_median": med(m["opened_per_attempt"])}
    n = len(attempts)
    return {
        "attempts": n,
        "maps": maps,
        "with_any_rate": round(sum(1 for a in attempts if a.get("wreck")) / n, 2) if n else None,
        "break_by_material": {k: dict(v.most_common()) for k, v in mats.items()},
        "break_who": dict(who.most_common()),
        "noise_at_break_median": med(noise_at_break),
        "crates": crates,
        "barricade": {"nails": nails, "full": full, "attempts_nailing": attempts_nailing, "broken": len(held),
                      "held_median_s": med(held), "broken_by": dict(held_by.most_common())},
        "cave": {"n": caves, "crushed_total": sum(crushed), "crushed_median": med(crushed), "support_by": dict(support_by.most_common())},
        "lamp_by": dict(lamp_by.most_common()),
        "window_by": dict(window_by.most_common()),
        "dig_find": {"n": sum(dig_by.values()), "by": dict(dig_by.most_common()), "item": dict(dig_item.most_common())},
        "dig_fall": {"n": len(dig_fall), "cells_median": med(dig_fall)},
        "wake_after": {"events": loud, "woke": woke, "rate": round(woke / loud, 2) if loud else None, "window_s": WAKE_WINDOW_S},
    }


def destruction_warnings(d):
    """Sygnały do strojenia niszczenia (DESTRUCTION_PLAN.md „Pomiar po wdrożeniu”); progi wstępne."""
    out = []
    attempts = d["attempts"]
    if attempts >= 5 and d["with_any_rate"] is not None and d["with_any_rate"] < 0.2:
        out.append("tylko %.0f%% prób cokolwiek niszczy — gracze nie widzą albo nie potrzebują zniszczalnych elementów" % (d["with_any_rate"] * 100))
    b = d["barricade"]
    if attempts >= 5 and b["nails"] == 0:
        out.append("nikt nie przybił deski (D2b) — podpowiedź, koszt albo miejsca")
    if b["broken"] >= 3 and b["held_median_s"] is not None and b["held_median_s"] < 5:
        out.append("barykady padają po medianie %.1f s — za słabe, żeby kupić czas" % b["held_median_s"])
    w = d["wake_after"]
    if w["events"] >= 10 and w["rate"] is not None and w["rate"] > 0.5:
        out.append("%.0f%% zniszczeń budzi Stalkera / elitę w %.0f s — hałas może być za drogi" % (w["rate"] * 100, w["window_s"]))
    return out


def warnings(rep):
    """Progi z PROGRESSION_PLAN.md §4."""
    out = []
    m = rep["maps"]
    base = (m.get("z1_m1") or {}).get("scrap_per_min_median")
    for k in ("z1_m2", "z1_m3"):
        v = (m.get(k) or {}).get("scrap_per_min_median")
        if base and v and v < 0.7 * base:
            out.append("%s: złom na minutę %.1f < 70%% z 1.1 (%.1f) — §2.2, P2.1" % (k, v, base))
    w = (m.get("z1_m3") or {}).get("wipes_per_success")
    if w and w > 3:
        out.append("1.3: %.1f wipe'ów na sukces" % w)
    six = rep["profile"]["host_minutes_to_level"].get(6)
    if six is not None and six < 60:
        out.append("L6 (ostatnie odblokowanie) po %.0f min misji — §2.3, P2.2" % six)
    pr = rep["profile"]["perk_rate_l2"]
    if pr is not None and pr < 0.6:
        out.append("perk założony tylko w %.0f%% startów z L ≥ 2" % (pr * 100))
    poor = rep["hub"]["poor_rate"]
    if poor is not None and poor > 0.3:
        out.append("%.0f%% operacji w warsztacie odrzuconych za brak złomu" % (poor * 100))
    hs = rep["hub"]["hub_seconds_median"]
    if hs and hs > 180:
        out.append("mediana czasu w kryjówce %.0f s > 180 s" % hs)
    s = rep["samples"]
    if s["bank_max"] and s["bank_max"] >= 3 and s["research_ok"] == 0:
        out.append("próbki w banku (do %d), a badań 0 — §2.4, P1.3" % s["bank_max"])
    ts = rep["weapons"]["top_share"]
    if ts and ts > 0.7:
        out.append("jedna broń ma %.0f%% zabójstw" % (ts * 100))
    if furthest_only_first(rep):
        out.append("większość sesji kończy się na 1.1 — §2.1, P1.1")
    return out


def furthest_only_first(rep):
    f = rep["sessions"]["furthest_map"]
    n = sum(f.values())
    return n >= 3 and f.get("z1_m1", 0) > n / 2


def print_report(rep):
    s = rep["sessions"]
    print("== Sesje: %d plików, mediana %s prób na sesję" % (s["files"], s["attempts_per_session_median"]))
    print("   pierwsza mapa: %s;  najdalsza: %s" % (s["first_map"], s["furthest_map"]))
    print("\n== Mapy (kampania, udane próby)")
    print("   %-6s %5s %5s %5s %6s %6s %7s %8s %7s %6s %7s %7s %6s" % ("mapa", "prób", "sukc", "wipe", "przerw", "w/s", "czas s", "złom", "zł/min", "cel%", "XP mis", "XP zab", "XP/min"))
    for k, m in rep["maps"].items():
        print("   %-6s %5d %5d %5d %6d %6s %7s %8s %7s %6s %7s %7s %6s" % (k, m["attempts"], m["success"], m["wipes"], m["quits"], m["wipes_per_success"],
              m["time_success_median_s"], m["scrap_banked_median"], m["scrap_per_min_median"],
              None if m["side_rate"] is None else int(m["side_rate"] * 100), m["xp_mission_median"], m["xp_kills_median"], m["xp_per_min"]))
        if m["quits"]:
            print("          przerwane: %d, w tym po wipe'ie (próba > 1): %d" % (m["quits"], m["quit_after_wipe"]))
        if "bez bota" in m.get("bot_split", {}):
            print("          %s" % ";  ".join("%s: prób %d, sukc %d, wipe %d" % (k, v["attempts"], v["success"], v["wipes"]) for k, v in m["bot_split"].items()))
        if m["kills_by_kind"]:
            print("          zabójstwa ludzi wg rodzaju: %s" % m["kills_by_kind"])
    p = rep["profile"]
    print("\n== Profil: poziomy na starcie prób %s" % p["level_at_start"])
    print("   perk przy L ≥ 2: %s;  dwa perki przy L ≥ 4: %s" % (p["perk_rate_l2"], p["two_perks_rate_l4"]))
    print("   gracz 1 (host) — minuty misji do poziomu: %s" % p["host_minutes_to_level"])
    h = rep["hub"]
    print("\n== Kryjówka: %d wizyt, mediana %s s; operacje %d (udane %d), odrzucone za brak złomu %s" % (h["visits"], h["hub_seconds_median"], h["operations"], h["ok"], h["poor_rate"]))
    print("   wydany złom wg rodzaju: %s" % h["spent_by_kind"])
    print("   liczba zakupów: %s;  odmowy: %s" % (h["count_by_kind"], h["reasons"]))
    print("   bank (pierwsza / ostatnia próba): %s, najwyżej %s" % (h["bank_first_last"], h["bank_max"]))
    sm = rep["samples"]
    print("\n== Próbki: w banku %s (najwyżej %s), udane badania %d" % (sm["bank_last"], sm["bank_max"], sm["research_ok"]))
    w = rep["weapons"]
    print("== Broń: zabójstwa %s;  największy udział %s;  kupione bronie %s" % (w["kills"], w["top_share"], w["bought"]))
    print("== Nocny Dyżur: %d prób" % rep["night_shift"]["attempts"])
    print("== Przedmioty: %s (prób z danymi: %d)" % (rep["items"]["total"], rep["items"]["attempts_with_data"]))
    print("== Podpowiedzi pokazane: %s" % rep["hints"])
    print_destruction(rep["destruction"])
    print("\n== Sygnały (PROGRESSION_PLAN.md §4)")
    for line in rep["warnings"] or ["brak"]:
        print("   - " + line)


def print_destruction(d):
    print("\n== Niszczenie (DESTRUCTION_PLAN.md): prób od %s: %d, z czymkolwiek zniszczonym %s" % (
        ".".join(str(x) for x in DESTRUCTION_SINCE), d["attempts"], d["with_any_rate"]))
    if not d["attempts"]:
        return
    for k, m in d["maps"].items():
        print("   %-6s prób %d, z niszczeniem %s, rozbitych przegród na próbę (mediana) %s;  %s" % (k, m["attempts"], m["with_any_rate"], m["opened_median"], m["events"]))
    print("   przegrody wg materiału i czym: %s" % d["break_by_material"])
    print("   kto rozbija: %s;  Uwaga po rozbiciu (mediana) %s" % (d["break_who"], d["noise_at_break_median"]))
    c = d["crates"]
    print("   skrzynie: %d (złom %d, baterie %d, deski %d)" % (c["n"], c["scrap"], c["battery"], c["planks"]))
    b = d["barricade"]
    print("   barykady: przybitych desek %d (komplet 3 desek: %d) w %d próbach; rozbite %d, wytrzymały (mediana) %s s, rozbił: %s" % (
        b["nails"], b["full"], b["attempts_nailing"], b["broken"], b["held_median_s"], b["broken_by"]))
    cv = d["cave"]
    print("   zawały: %d, zasypanych wrogów %d (mediana %s);  stemple łamane: %s" % (cv["n"], cv["crushed_total"], cv["crushed_median"], cv["support_by"]))
    print("   lampy: %s;  okna: %s" % (d["lamp_by"], d["window_by"]))
    df = d["dig_find"]
    print("   znajdźki wykopane w strefach: %d, czym: %s, co wypadło: %s" % (df["n"], df["by"], df["item"]))
    print("   spadłe wyspy w strefach: %d (narożników, mediana %s)" % (d["dig_fall"]["n"], d["dig_fall"]["cells_median"]))
    w = d["wake_after"]
    print("   pobudki Stalkera / elit do %.0f s po zniszczeniu: %d z %d (%s)" % (w["window_s"], w["woke"], w["events"], w["rate"]))
    for line in destruction_warnings(d):
        print("   ! " + line)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", default=default_dir())
    ap.add_argument("--build", default="")
    ap.add_argument("--since", default="")
    ap.add_argument("--difficulty", default="")
    ap.add_argument("--min-humans", type=int, default=1)
    ap.add_argument("--json", default="")
    args = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8")         # konsola Windows (cp1250) nie zna „≥”
    except (AttributeError, ValueError):
        pass
    if not os.path.isdir(args.dir):
        print("Brak katalogu z dziennikami: %s" % args.dir, file=sys.stderr)
        return 1
    rep = report(load(args))
    print_report(rep)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(rep, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
