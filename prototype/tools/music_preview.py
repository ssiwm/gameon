"""
music_preview.py — podgląd muzyki adaptacyjnej poza grą (MUSIC_PLAN.md §8, E3a).

Odtwarza przebieg z dziennika sesji (zdarzenia `music`, `music_motif`, `music_cue`) przez kopię logiki
MusicDirector (wygładzenie T, progi, MIN_ON / MIN_STEP, pościg ≥ CHASE_MIN_ON, przerwa CHASE_REST) i AudioDirector
(kwantyzacja wejść, przenikanie w dB, sekcje na początku pętli, kadencja na takcie, motyw Stalkera, sygnały z wyciszeniem)
i składa z tego stereo WAV. Bez efektów świata — tylko szyna muzyki, tak jak by grała w tej sesji.

Surowe T w dzienniku jest zapisane tylko przy zmianie warstwy; między zdarzeniami trzymamy ostatnią wartość.

    python tools/music_preview.py --log <sesja.jsonl> --from 300 --to 480 --out podglad.wav
    python tools/music_preview.py --script "0:0,8:20,40:45,75:80,115:30,150:0" --out pokaz.wav

`--script` zamiast dziennika: surowe T w punktach czas:wartość (pokaz warstw po kolei: cisza → napięcie → walka → pościg → koniec).

Siatka, palety i kadencje z tools/bake_music.py, pliki z audio/music (albo --dir: inny katalog z tymi samymi kluczami).
"""

from __future__ import annotations

import argparse
import json
import os
import random

import numpy as np
import soundfile as sf

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
MUSIC_DIR = os.path.join(HERE, "..", "audio", "music")

# --- MusicDirector (scripts/music_director.gd)
UP = (14.0, 36.0, 66.0)
DOWN = (9.0, 28.0, 58.0)
ATTACK_TAU, RELEASE_TAU = 1.2, 5.0
MIN_ON, MIN_STEP = 12.0, 5.0
CHASE_MIN_ON, CHASE_REST = 20.0, 30.0
HORDE_COOLDOWN, ELITE_COOLDOWN = 180.0, 20.0

# --- AudioDirector (scripts/audio_director.gd, manifest)
BLEND = (6.0, 4.0, 2.5, 1.5)
FADE_OUT = (10.0, 8.0, 6.0, 5.0)
DROP_HOLD = (0.0, 2.0, 3.0, 4.0)
FLOOR_DB = -40.0
SEG_XF = 0.6
SEG_RUN = (2, 4)
CADENCE_CUT = 0.7
CADENCE_MIN_GAIN = 0.6
MOTIF_FADE_IN, MOTIF_FADE_OUT = 3.0, 6.0
CUE_DB = -2.0
DT = 0.01



def music_cfg() -> dict:
    """Siatka, palety i kadencje z generatora — ten sam stan co manifest w grze."""
    import bake_music as bm
    return {"bpm": bm.BPM, "beats": bm.BEATS, "skip_bars": tuple(bm.CADENCE_SKIP_BARS), "pre": bm.CADENCE_PRE,
            "layers": bm.SEGMENTS["default"], "cadences": bm.CADENCES, "motif": ("mus_stalker_far", "mus_stalker_near")}


def fade_gain(x: float) -> float:
    return 0.0 if x <= 0.0 else 10.0 ** (FLOOR_DB * (1.0 - min(x, 1.0)) / 20.0)


def pick_layer(t: float, prev: int) -> int:
    up = -1
    for i, u in enumerate(UP):
        if t >= u:
            up = i + 1
    if up >= prev:
        return up
    keep = prev
    while keep > up and t < DOWN[keep - 1]:
        keep -= 1
    return keep


def read_log(path: str):
    raw_pts, motif_pts, cue_pts = [(0.0, 0.0)], [(0.0, 0)], []
    end = 0.0
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            t = float(r.get("t", 0.0))
            end = max(end, t)
            ev = r.get("ev", "")
            if ev == "music":
                raw_pts.append((t, float(r.get("raw", 0.0))))
            elif ev == "music_motif":
                motif_pts.append((t, int(r.get("to", 0))))
            elif ev == "music_cue":
                cue_pts.append((t, str(r.get("cue", ""))))
    return raw_pts, motif_pts, cue_pts, end


def step_at(pts, t):
    v = pts[0][1]
    for pt, pv in pts:
        if pt > t:
            break
        v = pv
    return v


def load(key: str, folder: str) -> np.ndarray:
    x, sr = sf.read(os.path.join(folder, key + ".wav"), always_2d=True)
    assert sr == SR, key
    return x.T.astype(np.float64)


def simulate(raw_pts, motif_pts, cue_pts, end: float, cfg: dict, seed: int):
    """Przebieg sterowania: per krok DT głośności każdego wariantu, motywu i lista jednorazowych (czas, klucz, dB)."""
    rng = random.Random(seed)
    beat = 60.0 / cfg["bpm"]
    bar = 4.0 * beat
    loop = beat * cfg["beats"]
    bars = cfg["beats"] // 4
    n_layers = len(cfg["layers"])
    steps = int(end / DT) + 1
    vols = [np.zeros((len(cfg["layers"][i]), steps)) for i in range(n_layers)]
    mvol = np.zeros((2, steps))
    shots: list[tuple[float, str, float]] = []
    # director
    threat, base, on_t, in_t, chase_rest = 0.0, -1, 0.0, 0.0, 0.0
    horde_cd, elite_cd = 0.0, 0.0
    cue_i = 0
    # engine
    started, t0 = False, 0.0
    layer, drop_to, drop_at = -1, None, -1.0
    target = [0.0] * n_layers
    gain = [0.0] * n_layers
    enter_at = [0.0] * n_layers
    fast = [False] * n_layers
    cad_key, cad_land = "", -1.0
    sec, sec_left, xf_end = 0, rng.randint(*SEG_RUN), -1.0
    cur = [0] * n_layers
    prev = [-1] * n_layers
    next_ok = 0.0
    mx = [0.0, 0.0]
    duck_db, duck_hold = 0.0, 0.0
    log_layers = []
    for k in range(steps):
        t = k * DT
        # --- MusicDirector.step
        raw = step_at(raw_pts, t)
        tau = ATTACK_TAU if raw > threat else RELEASE_TAU
        threat += (raw - threat) * (1.0 - np.exp(-DT / tau))
        want = pick_layer(threat, base)
        chase_rest = max(0.0, chase_rest - DT)
        if want == 3 and base < 3 and chase_rest > 0.0:
            want = 2
        hold = CHASE_MIN_ON if base == 3 else MIN_STEP
        if want < base and (in_t < hold or (want < 0 and on_t < MIN_ON)):
            want = base
        if base == 3 and want < 3:
            chase_rest = CHASE_REST
        in_t = in_t + DT if want == base else 0.0
        on_t = on_t + DT if want >= 0 else 0.0
        changed = want != base
        base = want
        mstate = step_at(motif_pts, t)
        far, near = ((0.0, 0.0), (0.85, 0.0), (0.3, 0.85))[max(0, min(2, mstate))]
        # --- start stemów (pierwsza warstwa albo motyw)
        if not started and (base >= 0 or far > 0 or near > 0):
            started, t0 = True, t
        pos = t - t0 if started else 0.0
        # --- AudioDirector.music_set_layer
        if started and changed:
            log_layers.append((round(t, 1), base))
            if base >= layer:
                drop_to, drop_at = None, -1.0
                cad_key, cad_land = "", -1.0
                for i in range(base + 1):
                    if target[i] < 1.0:
                        target[i] = 1.0
                        grid = beat * (1.0, 1.0, 0.5, 0.25)[min(i, 3)]
                        dq = grid - (pos % grid)
                        enter_at[i] = t + (0.0 if dq > grid - 0.02 else dq)
                layer = base
            else:
                drop_to, drop_at = base, t + DROP_HOLD[max(0, layer)]
        if not started:
            continue
        # --- zejście z kadencją
        if drop_to is not None and t >= drop_at:
            if cad_key == "":
                for i in range(min(layer, n_layers - 1), drop_to, -1):
                    if cfg["cadences"][i] and gain[i] >= CADENCE_MIN_GAIN:
                        cad_key = cfg["cadences"][i]
                        break
                if cad_key:
                    wait = bar - (pos % bar)
                    nxt = (int(pos // bar) + 1) % bars
                    if wait < cfg["pre"] + 0.03:
                        wait += bar
                        nxt = (nxt + 1) % bars
                    while nxt in cfg["skip_bars"]:
                        wait += bar
                        nxt = (nxt + 1) % bars
                    cad_land = t + wait
                    shots.append((cad_land - cfg["pre"], cad_key, 0.0))
            if cad_key == "" or t >= cad_land:
                for i in range(drop_to + 1, n_layers):
                    target[i] = 0.0
                    fast[i] = bool(cad_key) and bool(cfg["cadences"][i])
                layer, drop_to, drop_at = drop_to, None, -1.0
                cad_key, cad_land = "", -1.0
        # --- sekcje na początku pętli
        if xf_end >= 0.0 and t >= xf_end:
            prev = [-1] * n_layers
            xf_end = -1.0
        to_b = loop - (pos % loop)
        if to_b <= SEG_XF and t >= next_ok:
            next_ok = t + to_b + 1.0
            sec_left -= 1
            if sec_left <= 0:
                sec_left = rng.randint(*SEG_RUN)
                n_max = max(len(v) for v in cfg["layers"])
                if n_max > 1:
                    nxt = rng.randint(0, n_max - 2)
                    sec = nxt + 1 if nxt >= sec else nxt
                    xf_end = t + to_b
                    for i in range(n_layers):
                        v = sec % len(cfg["layers"][i])
                        if v != cur[i]:
                            prev[i], cur[i] = cur[i], v
        # --- sygnały (reguły od 1.7.580: horda tylko na starcie walki, co 180 s)
        horde_cd = max(0.0, horde_cd - DT)
        elite_cd = max(0.0, elite_cd - DT)
        while cue_i < len(cue_pts) and cue_pts[cue_i][0] <= t:
            ck = cue_pts[cue_i][1]
            cue_i += 1
            if ck == "cue_horde" and horde_cd <= 0.0 and base <= 1:
                horde_cd = HORDE_COOLDOWN
                shots.append((t, "cue_horde", CUE_DB))
                duck_db, duck_hold = min(duck_db, -6.0), max(duck_hold, 2.5)
            elif ck == "cue_elite" and elite_cd <= 0.0:
                elite_cd = ELITE_COOLDOWN
                shots.append((t, "cue_elite", CUE_DB))
                duck_db, duck_hold = min(duck_db, -6.0), max(duck_hold, 2.5)
        if duck_hold > 0.0:
            duck_hold -= DT
        else:
            duck_db = min(0.0, duck_db + DT * 6.0)
        duck = 10.0 ** (duck_db / 20.0)
        # --- głośności
        for i in range(n_layers):
            if target[i] > 0.5:
                fast[i] = False
                if t >= enter_at[i]:
                    gain[i] = min(1.0, gain[i] + DT / BLEND[i])
            else:
                gain[i] = max(0.0, gain[i] - DT / (CADENCE_CUT if fast[i] else FADE_OUT[i]))
            g = fade_gain(gain[i]) * duck
            kx = 1.0
            if prev[i] >= 0 and xf_end >= 0.0:
                kx = min(1.0, max(0.0, 1.0 - (xf_end - t) / SEG_XF))
            for v in range(len(cfg["layers"][i])):
                w = kx if v == cur[i] else (1.0 - kx if v == prev[i] else 0.0)
                vols[i][v, k] = g * w
        for j, tg in enumerate((far, near)):
            mx[j] = min(tg, mx[j] + DT / MOTIF_FADE_IN) if mx[j] < tg else max(tg, mx[j] - DT / MOTIF_FADE_OUT)
            mvol[j, k] = fade_gain(mx[j]) * duck
    return vols, mvol, shots, t0, log_layers


def render(cfg: dict, folder: str, vols, mvol, shots, t0: float, t_from: float, t_to: float) -> np.ndarray:
    n_out = int((t_to - t_from) * SR)
    out = np.zeros((2, n_out))
    s0 = int(t_from * SR)

    def env(row: np.ndarray) -> np.ndarray:
        ts = (np.arange(n_out) + s0) / SR
        return np.interp(ts, np.arange(len(row)) * DT, row)

    def tiled(x: np.ndarray) -> np.ndarray:
        # pętla gra od t0; próbka bezwzględna s → (s − t0·SR) mod długość
        idx = (np.arange(n_out) + s0 - int(t0 * SR)) % x.shape[1]
        return x[:, idx]

    for i, keys in enumerate(cfg["layers"]):
        for v, key in enumerate(keys):
            e = env(vols[i][v])
            if e.max() <= 1e-5:
                continue
            out += tiled(load(key, folder)) * e
    for j, key in enumerate(cfg["motif"]):
        e = env(mvol[j])
        if e.max() > 1e-5 and os.path.exists(os.path.join(folder, key + ".wav")):
            out += tiled(load(key, folder)) * e
    for ts, key, db in shots:
        path = os.path.join(folder, key + ".wav")
        if not os.path.exists(path):
            continue
        x = load(key, folder) * 10.0 ** (db / 20.0)
        a = int(ts * SR) - s0
        lo, hi = max(0, a), min(n_out, a + x.shape[1])
        if hi > lo:
            out[:, lo:hi] += x[:, lo - a:hi - a]
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log", default="")
    ap.add_argument("--script", default="", help="surowe T: czas:wartość,czas:wartość,…")
    ap.add_argument("--dir", default=MUSIC_DIR, help="katalog z WAV-ami muzyki (domyślnie audio/music)")
    ap.add_argument("--from", dest="t_from", type=float, default=0.0)
    ap.add_argument("--to", dest="t_to", type=float, default=0.0)
    ap.add_argument("--seed", type=int, default=87)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    cfg = music_cfg()
    folder = a.dir
    if a.script:
        raw_pts = [(0.0, 0.0)] + [(float(p.split(":")[0]), float(p.split(":")[1])) for p in a.script.split(",")]
        motif_pts, cue_pts, end = [(0.0, 0)], [], raw_pts[-1][0] + 25.0
    else:
        raw_pts, motif_pts, cue_pts, end = read_log(a.log)
    t_to = a.t_to if a.t_to > 0 else end
    vols, mvol, shots, t0, layers = simulate(raw_pts, motif_pts, cue_pts, t_to + 1.0, cfg, a.seed)
    x = render(cfg, folder, vols, mvol, shots, t0, a.t_from, t_to)
    pk = np.abs(x).max()
    if pk > 0.97:
        x *= 0.97 / pk
    sf.write(a.out, x.T, SR, subtype="PCM_16")
    win = [(t, l) for t, l in layers if a.t_from <= t <= t_to]
    print("%s: %.0f s, warstwy %s, jednorazowe %d" % (a.out, t_to - a.t_from, win,
                                                       sum(1 for ts, _, _ in shots if a.t_from <= ts <= t_to)))


if __name__ == "__main__":
    main()
