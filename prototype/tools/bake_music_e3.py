"""
bake_music_e3.py — prototyp nowego materiału muzyki (MUSIC_PLAN.md §8, E3a): mroczny ambient zamiast synthwave.

Jeden materiał, który gęstnieje (D8–D12): 64 BPM, pedał D bez zmian akordów, metal i przedmioty zamiast bębnów, jedyna
melodia to motyw Stalkera. Warstwy nakładają się jak dotąd (te same klucze co w grze), ale każda dokłada się do tej samej
faktury zamiast zaczynać nowy utwór:

    mus_silence  dron D z taśmy, wiatr w rurach, daleki metal                     (warstwa 0)
    mus_tension  + puls serca na każdy beat, długi smyczek na D / A, tykanie      (warstwa 1)
    mus_combat   + tłok ósemkami, uderzenia w rurę na 2 i 4, przesterowany dron    (warstwa 2)
    mus_chase    + tremolo smyczków (klaster na D) szesnastkami, zgrzyt metalu    (warstwa 3)

Wariant B każdej warstwy ma ten sam rytm, inną barwę. Kadencje, sygnały i motyw Stalkera z tego samego materiału.
Piecze do osobnego katalogu (nie do gry); odsłuch przez tools/music_preview.py --set e3.

    python tools/bake_music_e3.py --out C:/deadair87/music_preview/e3
"""

from __future__ import annotations

import argparse
import os
import zlib

import numpy as np
import soundfile as sf

import audio_dsp as d
from audio_dsp import SR, Rng, sec
from bake_common import ir, thump, tick

TAU = d.TAU
BPM = 64.0
SPB = int(round(SR * 60.0 / BPM))      # 45000
BARS = 8
BEATS = BARS * 4
LOOP_N = SPB * BEATS                   # 1 440 000 = 30 s
L_SEC = LOOP_N / SR
TAIL = sec(7.0)
PRE = 0.25                             # przedbieg kadencji (jak w grze)
D1 = 36.708


def mtof(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def loopf(f: float) -> float:
    """Częstotliwość z całkowitą liczbą okresów w pętli — ciągłe oscylatory bez szwu."""
    return round(f * L_SEC) / L_SEC


def T(beat: float) -> int:
    return int(round(beat * SPB))


class Stem:
    def __init__(self):
        self.buf = np.zeros((2, LOOP_N + TAIL))

    def put(self, sig: np.ndarray, beat: float, gain: float = 1.0, pan: float = 0.0) -> None:
        k = T(beat)
        if sig.ndim == 1:
            sig = d.pan(sig, pan) if pan != 0.0 else np.stack([sig, sig]) * 0.7071
        n = min(sig.shape[1], self.buf.shape[1] - k)
        if n > 0:
            self.buf[:, k:k + n] += sig[:, :n] * gain

    def render(self, rev=None, wet: float = 0.0) -> np.ndarray:
        x = self.buf
        if rev is not None and wet > 0.0:
            x = d.reverb_stereo(x, rev, wet=wet, dry=1.0, keep_len=False)
        return d.fold_loop(x, LOOP_N)


# ------------------------------------------------------------------ instrumenty (metal, przedmioty, smyczek, taśma)

def pipe(f: float, rng: Rng, dur: float = 3.0, bright: float = 1.0) -> np.ndarray:
    """Uderzenie w stalową rurę: mody pręta swobodnego (niharmoniczne), krótki klik pałki."""
    n = sec(dur)
    ratios, amps = (1.0, 2.756, 5.404, 8.933, 13.34), (1.0, 0.55, 0.32 * bright, 0.2 * bright, 0.1 * bright)
    y = d.modal([f * r for r in ratios], amps, [dur, dur * 0.7, dur * 0.45, dur * 0.3, dur * 0.2], n, rng, 0.002)
    y[:sec(0.01)] += tick(rng, 2600.0 * bright, 1.4, 10.0)[:sec(0.01)] * 0.25
    return y * 0.5


def plate(rng: Rng, f0: float = 170.0, dur: float = 1.8, hit: float = 1.0) -> np.ndarray:
    """Blacha: gęste, nieharmoniczne mody + szum uderzenia."""
    n = sec(dur)
    fr = sorted(f0 * rng.uniform(1.0, 16.0) for _ in range(18))
    y = d.modal(fr, [1.0 / (1.0 + 0.25 * i) for i in range(18)], [dur * rng.uniform(0.35, 1.0) for _ in range(18)], n, rng)
    burst = d.hp(d.white(n, rng), 1400.0) * d.env_perc(n, 0.0008, 0.05)
    return (y * 0.18 + burst * 0.35 * hit) * d.env_pts(n, [(0, 1.0), (dur, 0.0)]) ** 0.5


def piston(rng: Rng, dark: float = 1.0) -> np.ndarray:
    """Tłok / maszyna: krótki „chuch” szumu pasmowego i niskie tąpnięcie."""
    n = sec(0.38)
    ch = d.bp(d.white(n, rng), 230.0 * dark, 1.3) * d.env_perc(n, 0.004, 0.055)
    th = thump(0.32, 72.0 * dark, 40.0, 0.03, 0.08, attack=0.002)
    return d.mix([(ch, 0.9), (th, 0.8)], n)


def heart_into(s: Stem, beat: float, rng: Rng, g: float) -> None:
    s.put(thump(0.36, 60.0, 34.0, 0.04, 0.10, attack=0.003), beat, g)
    s.put(thump(0.30, 56.0, 33.0, 0.04, 0.08, attack=0.003), beat + 0.3, g * 0.55)


def bowed(f, dur: float, rng: Rng, bright: float = 0.3) -> np.ndarray:
    """Smyczek FM (jak motyw Stalkera w E1): wolne natarcie, opóźnione wibrato."""
    n = sec(dur)
    fr = d.vibrato(f, n, 4.4, 10.0, rng.uniform(0, TAU)) if np.isscalar(f) else f
    idx = (0.5 + 1.4 * bright) * d.env_pts(n, [(0, 0.1), (min(0.6, dur * 0.4), 1.0), (dur, 0.7)])
    y = d.fm(fr, n, ratio=1.0, index=idx) * 0.6 + d.fm(np.asarray(fr) * 0.5, n, ratio=2.0, index=idx * 0.5) * 0.4
    y = d.lp(y, 700.0 + 2400.0 * bright, 0.9)
    return y * d.env_adsr(n, min(0.9, dur * 0.3), 0.3, 0.85, min(1.2, dur * 0.35))


def tremolo(n: int, depth: float = 0.8) -> np.ndarray:
    """Tremolo smyczkowe szesnastkami (siatka utworu): każde pociągnięcie z miękkim atakiem."""
    t = np.arange(n) / SPB * 4.0
    ph = t - np.floor(t)
    stroke = np.minimum(1.0, ph / 0.12) * np.exp(-ph * 1.6)
    return 1.0 - depth + depth * stroke


def scrape(n: int, rng: Rng, f0: float, f1: float, q: float = 7.0) -> np.ndarray:
    """Zgrzyt metalu: szum przez wąski filtr sunący po paśmie, lekko przesterowany."""
    y = d.sweep(d.white(n, rng), "bp", np.geomspace(f0, f1, n), q)
    return d.saturate(y * 2.0, 2.2) * 0.35


def circ_noise(rng: Rng, fn) -> np.ndarray:
    """Szum długości pętli przefiltrowany kołowo — bez szwu na granicy pętli."""
    return d.circ_filter(d.white(LOOP_N, rng), fn)


def lfo(cycles: int, phase: float = 0.0) -> np.ndarray:
    return np.sin(TAU * cycles * np.arange(LOOP_N) / LOOP_N + phase)


def drone_bed(rng: Rng, third: bool = False, winds=(520.0, 830.0)) -> np.ndarray:
    """Dron D z taśmy: D1 (sinus), D2 i A2 (piły za filtrem), wiatr w rurach, szum taśmy. Wszystko okresowe w pętli."""
    t = np.arange(LOOP_N) / SR
    sub = np.sin(TAU * loopf(D1) * t) * 0.5
    saw = d.osc("saw", loopf(D1 * 2), LOOP_N) * 0.28 + d.osc("saw", loopf(D1 * 3), LOOP_N) * 0.08
    if third:
        saw += d.osc("saw", loopf(mtof(41)), LOOP_N) * 0.05      # F2: barwa moll, ten sam pedał
    saw = d.circ_filter(saw, lambda x: d.lp(x, 320.0, 0.9))
    bed = (sub + saw) * (0.85 + 0.15 * lfo(1))
    w = circ_noise(rng, lambda x: d.bp(x, winds[0], 6.0)) * 0.5 + circ_noise(rng, lambda x: d.bp(x, winds[1], 9.0)) * 0.3
    w *= (0.5 + 0.5 * lfo(3, 1.0)) ** 2 * 0.9
    hiss = circ_noise(rng, lambda x: d.lp(d.hp(x, 3000.0), 9000.0)) * 0.006
    mono = bed + w * 0.07 + hiss
    st = np.stack([mono, np.roll(mono, sec(0.013))])            # szerokość bez szwu (przesunięcie kołowe)
    return st


def tape(x: np.ndarray, depth: float = 0.003, sat: float = 1.15) -> np.ndarray:
    return d.tape(x, wow_hz=round(0.35 * L_SEC) / L_SEC, wow_depth=depth, sat=sat)


# ------------------------------------------------------------------ warstwy

def stem_silence(rng: Rng, b: bool = False) -> np.ndarray:
    bed = drone_bed(rng, third=b, winds=(610.0, 1150.0) if b else (520.0, 830.0))
    ev = Stem()
    if b:
        for bar in (3, 7):
            ev.put(scrape(sec(4.0), rng, 900.0, 300.0) * d.env_pts(sec(4.0), [(0, 0), (1.5, 1), (4.0, 0)]), bar * 4 + 1.0, 0.14, pan=0.5 if bar == 3 else -0.5)
    else:
        for bar in (1, 5):
            ev.put(pipe(mtof(50), rng, 5.0, 0.6), bar * 4 + 2.5, 0.22, pan=-0.5 if bar == 1 else 0.5)
    events = ev.render(ir("cave_st"), wet=0.8)
    return tape(bed + events)


def stem_tension(rng: Rng, b: bool = False) -> np.ndarray:
    s = Stem()
    for beat in range(BEATS):
        heart_into(s, beat, rng, 0.55 if beat % 4 == 0 else 0.42)
        s.put(tick(rng, 3900.0 if b else 5200.0, 5.0, 6.0), beat + 0.5, 0.05, pan=0.35 if beat % 2 else -0.35)
    notes = ((53, 52) if b else (50, 45))                        # A: D3 / A2, B: F3 / E3 (barwa motywu)
    for bar, m in ((0, notes[0]), (2, notes[1]), (4, notes[0]), (6, notes[1])):
        s.put(bowed(mtof(m), 2 * 4 * 60.0 / BPM + 1.0, rng, 0.2), bar * 4, 0.22, pan=-0.2 if bar % 4 else 0.2)
    out = s.render(ir("cave_st"), wet=0.3)
    return tape(d.circ_filter(out, lambda t: d.compress(t, -22.0, 2.0, 15.0, 250.0)))


def stem_combat(rng: Rng, b: bool = False) -> np.ndarray:
    s = Stem()
    for beat in range(BEATS):
        for half in (0.0, 0.5):
            s.put(piston(rng, 0.85 if b else 1.0), beat + half, 0.75 if half == 0.0 else 0.45, pan=0.15 if half else -0.15)
        if beat % 2 == 1:                                         # „werbel” to metal: 2 i 4
            if b:
                s.put(plate(rng, 210.0, 1.4), beat, 0.7, pan=0.25)
            else:
                s.put(pipe(mtof(38 + (7 if beat % 4 == 3 else 0)), rng, 2.2, 1.0), beat, 0.55, pan=0.25)
    for bar in (0, 4):
        if b:
            s.put(pipe(mtof(26), rng, 4.0, 0.8), bar * 4, 0.6)
        else:
            s.put(plate(rng, 150.0, 2.6), bar * 4, 0.55, pan=-0.2)
    # przesterowany dron D2 / D3, filtr otwiera się z każdym taktem (okresowo)
    t = np.arange(LOOP_N) / SR
    dr = d.osc("saw", loopf(D1 * 2), LOOP_N) * 0.5 + d.osc("saw", loopf(D1 * 4 * (1.0015 if b else 1.0)), LOOP_N) * 0.3
    bar_ph = (np.arange(LOOP_N) % (SPB * 4)) / (SPB * 4)
    dr = d.circ_filter(dr, lambda x: d.lp(x, 600.0, 1.2)) * (0.6 + 0.4 * bar_ph)
    dr = d.saturate(dr * (1.6 if b else 1.3), 3.0) * 0.16
    out = s.render(ir("plate_st"), wet=0.22) + np.stack([dr, np.roll(dr, sec(0.011))])
    out = d.saturate(out, 1.3)
    return tape(d.circ_filter(out, lambda t: d.compress(t, -17.0, 3.0, 8.0, 140.0)), 0.002, 1.2)


def stem_chase(rng: Rng, b: bool = False) -> np.ndarray:
    s = Stem()
    cluster = (50, 51, 57) if b else (62, 63, 69)               # B: niżej (wiolonczele), A: D4 E♭4 A4
    seg = 2 * 4 * 60.0 / BPM + 0.6
    for bar in (0, 2, 4, 6):
        n = sec(seg)
        tr = tremolo(n, 0.75)
        for i, m in enumerate(cluster):
            s.put(bowed(mtof(m), seg, rng, 0.55) * tr, bar * 4, 0.16, pan=(-0.4, 0.0, 0.4)[i])
        sc = scrape(sec(7.5), rng, *((2400.0, 300.0) if b else (300.0, 2400.0)))
        s.put(sc * d.env_pts(sec(7.5), [(0, 0), (6.5, 1), (7.5, 0)]), bar * 4, 0.12, pan=0.3 if bar % 4 else -0.3)
        s.put(thump(3.0, 40.0, 34.0, 1.0, 1.2, attack=1.5), bar * 4 + 4.0, 0.35)
    if b:
        for bar in range(BARS):
            s.put(pipe(mtof(86), rng, 2.0, 0.5), bar * 4, 0.08, pan=0.6)
    out = s.render(ir("hall_st"), wet=0.25)
    return tape(d.circ_filter(out, lambda t: d.compress(t, -18.0, 2.5, 10.0, 160.0)))


# ------------------------------------------------------------------ motyw Stalkera, kadencje, sygnały

MOTIF = ((50, 0.0, 1.4), (53, 1.5, 0.5), (52, 2.0, 1.9), (45, 4.0, 3.2))


def motif_into(s: Stem, beat0: float, rng: Rng, bright: float, gain: float) -> None:
    for m, b, dur in MOTIF:
        s.put(bowed(mtof(m), dur * 60.0 / BPM + 0.6, rng, bright), beat0 + b, gain, pan=rng.uniform(-0.25, 0.25))


def stem_stalker_far(rng: Rng) -> np.ndarray:
    s = Stem()
    for bar in (0, 4):
        motif_into(s, bar * 4, rng, 0.12, 0.5)
    out = s.render(ir("cave_st"), wet=0.65)
    return tape(d.circ_filter(out, lambda t: d.lp(t, 1400.0, order=2)), 0.004)


def stem_stalker_near(rng: Rng) -> np.ndarray:
    s = Stem()
    for bar in (0, 2, 4, 6):
        motif_into(s, bar * 4, rng, 0.45, 0.6)
    for beat in range(0, BEATS, 2):
        heart_into(s, beat, rng, 0.45)
    out = s.render(ir("cave_st"), wet=0.4)
    return tape(d.circ_filter(out, lambda t: d.compress(t, -20.0, 2.5, 20.0, 300.0)), 0.003, 1.25)


def oneshot(n_sec: float) -> np.ndarray:
    return np.zeros((2, sec(PRE) + sec(n_sec)))


def put1(buf: np.ndarray, sig: np.ndarray, at: float = 0.0, g: float = 1.0, pan: float = 0.0) -> None:
    sig = (d.pan(sig, pan) if pan else np.stack([sig, sig]) * 0.7071) if sig.ndim == 1 else sig
    k = sec(PRE) + int(at * SR)
    m = min(sig.shape[1], buf.shape[1] - k)
    buf[:, k:k + m] += sig[:, :m] * g


def cadence_combat(rng: Rng) -> np.ndarray:
    x = oneshot(5.5)
    put1(x, plate(rng, 140.0, 3.5, 1.2), 0.0, 0.9)
    put1(x, pipe(mtof(26), rng, 5.0, 0.9), 0.0, 0.9)
    put1(x, thump(1.6, 62.0, 30.0, 0.25, 0.7, attack=0.002), 0.0, 1.0)
    n = sec(5.0)
    dr = d.saturate((d.osc("saw", D1 * 2, n) * 0.5 + d.osc("saw", D1 * 4, n) * 0.3) * 1.4, 3.0)
    put1(x, d.lp(dr, 500.0, 1.0) * d.env_pts(n, [(0, 1.0), (5.0, 0.0)]) ** 2 * 0.25)
    return d.reverb_stereo(x, ir("cave_st"), wet=0.35, dry=1.0)


def cadence_chase(rng: Rng) -> np.ndarray:
    x = oneshot(5.5)
    put1(x, plate(rng, 180.0, 3.0, 1.3), 0.0, 0.9, pan=-0.2)
    put1(x, pipe(mtof(38), rng, 4.5, 1.0), 0.0, 0.8, pan=0.2)
    put1(x, thump(1.4, 70.0, 30.0, 0.2, 0.6, attack=0.002), 0.0, 1.0)
    for i, m in enumerate((62, 63, 69)):                         # klaster zostaje bez tremolo i gaśnie
        put1(x, bowed(mtof(m), 4.5, rng, 0.5) * d.env_pts(sec(4.5), [(0, 1.0), (4.5, 0.0)]), 0.0, 0.14, pan=(-0.4, 0.0, 0.4)[i])
    return d.reverb_stereo(x, ir("hall_st"), wet=0.35, dry=1.0)


def cue_horde(rng: Rng) -> np.ndarray:
    """Horda: tłok przyspiesza (alarm się niesie), na końcu rura i blacha."""
    x = oneshot(4.5)
    t, gap = 0.0, 0.45
    while t < 2.6:
        put1(x, piston(rng, 0.9), t, 0.5 + 0.5 * t / 2.6)
        t += gap
        gap = max(0.08, gap * 0.8)
    put1(x, pipe(mtof(38), rng, 3.0, 1.0), 2.7, 0.9)
    put1(x, plate(rng, 160.0, 2.0), 2.7, 0.7)
    return d.reverb_stereo(x, ir("hall_st"), wet=0.35, dry=1.0)


def cue_elite(rng: Rng) -> np.ndarray:
    """Elita: smyczek sunie z D2 na A2, narasta jasność, na szczycie uderzenie w rurę."""
    x = oneshot(4.0)
    n = sec(3.0)
    gl = d.glide_exp(mtof(38), mtof(45), n, 0.9)
    put1(x, bowed(gl, 3.0, rng, 0.7) * d.env_pts(n, [(0, 0.2), (2.0, 1.0), (3.0, 0.0)]), 0.0, 0.5)
    put1(x, pipe(mtof(45), rng, 3.0, 1.0), 2.0, 0.6)
    put1(x, thump(1.0, 66.0, 32.0, 0.15, 0.5), 2.0, 0.7)
    return d.reverb_stereo(x, ir("cave_st"), wet=0.4, dry=1.0)


# ------------------------------------------------------------------ zapis

def norm(x: np.ndarray, lufs: float, loop: bool) -> np.ndarray:
    cur = d.lufs(x) if loop else d.active_lufs(x)
    x = x * d.db_to_lin(lufs - cur)
    pk = np.abs(x).max()
    return x * (0.89 / pk) if pk > 0.89 else x                   # ok. −1 dBFS


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    loops = (("mus_silence", lambda r: stem_silence(r), -27.0), ("mus_silence_b", lambda r: stem_silence(r, True), -27.0),
             ("mus_tension", lambda r: stem_tension(r), -26.0), ("mus_tension_b", lambda r: stem_tension(r, True), -26.0),
             ("mus_combat", lambda r: stem_combat(r), -21.0), ("mus_combat_b", lambda r: stem_combat(r, True), -21.0),
             ("mus_chase", lambda r: stem_chase(r), -22.0), ("mus_chase_b", lambda r: stem_chase(r, True), -22.0),
             ("mus_stalker_far", stem_stalker_far, -31.0), ("mus_stalker_near", stem_stalker_near, -25.0))
    shots = (("mus_combat_end", cadence_combat, -19.0), ("mus_chase_end", cadence_chase, -17.0),
             ("cue_horde", cue_horde, -16.0), ("cue_elite", cue_elite, -17.0))
    for key, fn, lu in loops:
        x = fn(Rng(zlib.crc32(("e3:" + key).encode()) & 0xFFFF))
        assert x.shape == (2, LOOP_N), (key, x.shape)
        sf.write(os.path.join(a.out, key + ".wav"), norm(x, lu, True).T, SR, subtype="PCM_24")
        print("%-17s %.1f s" % (key, x.shape[1] / SR))
    for key, fn, lu in shots:
        x = fn(Rng(zlib.crc32(("e3:" + key).encode()) & 0xFFFF))
        x = d.fade_edges(x, 0.0, 400.0)
        sf.write(os.path.join(a.out, key + ".wav"), norm(x, lu, False).T, SR, subtype="PCM_24")
        print("%-17s %.1f s" % (key, x.shape[1] / SR))


if __name__ == "__main__":
    main()
