"""
bake_music.py — muzyka adaptacyjna (MUSIC_PLAN.md §8, E3b od 1.7.581): mroczny ambient zamiast synthwave lat 80.

Jeden materiał, który gęstnieje (decyzje D8–D12): 64 BPM, pedał D bez zmian akordów, metal i przedmioty zamiast bębnów,
smyczek FM i taśma; jedyna melodia to motyw Stalkera. Cztery STEMY NAKŁADAJĄ SIĘ (vertical layering) — każdy dokłada
się do tej samej faktury zamiast zaczynać nowy utwór:

    S0 mus_silence  dron D z taśmy, wiatr w rurach, daleki metal                     (warstwa 0)
    S1 mus_tension  + puls serca na każdy beat, długi smyczek na D / A, tykanie      (warstwa 1)
    S2 mus_combat   + tłok ósemkami, uderzenia w rurę na 2 i 4, przesterowany dron    (warstwa 2)
    S3 mus_chase    + tremolo smyczków (klaster na D) szesnastkami, zgrzyt metalu    (warstwa 3)

Każda warstwa ma wariant B (`_b`) o tym samym rytmie i innej barwie; runtime zmienia całą sekcję naraz na początku pętli
(E2). Poza warstwami: motyw Stalkera (mus_stalker_far / _near), kadencje (mus_combat_end / mus_chase_end, z przedbiegiem
PRE), sygnały cue_horde / cue_elite i stingery sting_tension / sting_chase — z tego samego materiału.

E4 (momenty): sceny ponad warstwami, na tej samej siatce — boss mus_boss_1..3 (fazy dokładają się), odwrót mus_retreat
(60 s), uderzenie momentu mus_hit (na beat) i kadencja śmierci bossa mus_boss_end (na takt), obie z przedbiegiem PRE.

Siatka: 64 BPM → 45000 próbek/beat (całkowita liczba), 8 taktów 4/4 = 32 beaty = 1 440 000 próbek = 30 s.
Pętla zamyka się dokładnie: zdarzenia i pogłos zawijane fold_loop(), ciągłe oscylatory mają całkowitą liczbę okresów
w pętli (loopf), szum filtrowany kołowo. Wersja synthwave (do 1.7.580) jest w historii gita.

Podgląd poza grą: tools/music_preview.py (dziennik sesji albo skrypt T → WAV).
"""

from __future__ import annotations

import argparse
import os
import zlib

import numpy as np
import soundfile as sf

import audio_dsp as d
from audio_dsp import SR, Rng, sec
from bake_common import asset, finalize, group, ir, thump, tick

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
    def __init__(self, n_loop: int = LOOP_N):
        self.n_loop = n_loop
        self.buf = np.zeros((2, n_loop + TAIL))

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
        return d.fold_loop(x, self.n_loop)


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


# ------------------------------------------------------------------ E4: boss (fazy) i odwrót

def glide_back(a: float, b: float, n: int) -> np.ndarray:
    """Częstotliwość a → b → a (jęk o pół tonu: interwał motywu Stalkera)."""
    h = n // 2
    return np.concatenate([d.glide_exp(a, b, h, 0.6), d.glide_exp(b, a, n - h, 0.6)])


def stem_boss_1(rng: Rng) -> np.ndarray:
    """Faza 1: obecność bossa — dudnienie rury D1 na „raz” każdego taktu, jęk smyczka D2 ↔ E♭2 co dwa takty, fala subu."""
    s = Stem()
    for bar in range(BARS):
        s.put(pipe(mtof(26), rng, 4.5, 0.7), bar * 4, 0.55)
        s.put(thump(1.2, 52.0, 30.0, 0.3, 0.8, attack=0.004), bar * 4, 0.6)
    seg = 2 * 4 * 60.0 / BPM + 0.8
    n = sec(seg)
    for bar in (0, 2, 4, 6):
        gl = glide_back(mtof(38), mtof(39), n)
        s.put(bowed(gl, seg, rng, 0.25), bar * 4, 0.34, pan=-0.3 if bar % 4 else 0.3)
    out = s.render(ir("cave_st"), wet=0.45)
    t = np.arange(LOOP_N) / SR
    sub = np.sin(TAU * loopf(D1) * t) * (0.5 + 0.5 * lfo(4, -np.pi / 2)) ** 2 * 0.22    # fala co dwa takty
    out = out + np.stack([sub, sub])
    return tape(d.circ_filter(out, lambda x: d.compress(x, -20.0, 2.5, 15.0, 220.0)), 0.003, 1.2)


def stem_boss_2(rng: Rng) -> np.ndarray:
    """Faza 2: „galop” 3-3-2 ósemkami (rura, rura, blacha) — rytm tylko bossa; pod nim tremolo wiolonczel D2 + A2."""
    s = Stem()
    for bar in range(BARS):
        b0 = bar * 4
        s.put(pipe(mtof(38), rng, 2.4, 1.0), b0, 0.6, pan=-0.15)
        s.put(piston(rng, 0.8), b0, 0.6)
        s.put(pipe(mtof(38), rng, 2.0, 0.8), b0 + 1.5, 0.42, pan=0.15)
        s.put(piston(rng, 0.8), b0 + 1.5, 0.4)
        s.put(plate(rng, 130.0, 1.6), b0 + 3.0, 0.5, pan=0.25 if bar % 2 else -0.25)
    seg = 2 * 4 * 60.0 / BPM + 0.6
    n = sec(seg)
    tr = tremolo(n, 0.55)
    env = d.env_pts(n, [(0, 0.5), (seg * 0.8, 1.0), (seg, 0.6)])
    for bar in (0, 2, 4, 6):
        for i, m in enumerate((38, 45)):
            s.put(bowed(mtof(m), seg, rng, 0.35) * tr * env, bar * 4, 0.15, pan=(-0.35, 0.35)[i])
    out = s.render(ir("hall_st"), wet=0.25)
    out = d.saturate(out, 1.25)
    return tape(d.circ_filter(out, lambda x: d.compress(x, -18.0, 3.0, 8.0, 140.0)), 0.002, 1.2)


def stem_boss_3(rng: Rng) -> np.ndarray:
    """Faza 3: wysoki klaster D5 / E♭5 tremolo, zgrzyt rośnie ku każdej parze taktów, metalowy „zegar” szesnastkami."""
    s = Stem()
    seg = 2 * 4 * 60.0 / BPM + 0.6
    n = sec(seg)
    tr = tremolo(n, 0.85)
    for bar in (0, 2, 4, 6):
        for i, m in enumerate((74, 75)):
            s.put(bowed(mtof(m), seg, rng, 0.6) * tr, bar * 4, 0.1, pan=(-0.45, 0.45)[i])
        sc = scrape(sec(7.5), rng, 300.0, 3200.0)
        s.put(sc * d.env_pts(sec(7.5), [(0, 0), (7.0, 1), (7.5, 0)]), bar * 4, 0.15, pan=0.35 if bar % 4 else -0.35)
    for st in range(BEATS * 4):
        acc = 1.0 if st % 4 == 0 else (0.55 if st % 2 == 0 else 0.35)
        s.put(tick(rng, 4600.0, 6.0, 5.0), st * 0.25, 0.06 * acc, pan=0.3 if st % 2 else -0.3)
    for bar in (3, 7):
        s.put(pipe(mtof(51), rng, 3.0, 1.0), bar * 4 + 2.5, 0.35, pan=0.2)          # E♭3 — tarcie z pedałem
    out = s.render(ir("hall_st"), wet=0.3)
    return tape(d.circ_filter(out, lambda x: d.compress(x, -18.0, 2.5, 10.0, 160.0)), 0.003, 1.2)


RETREAT_N = 2 * LOOP_N                 # odwrót: 60 s (dwie pętle siatki), pierwsza połowa pchnięcie, druga napięcie


def stem_retreat(rng: Rng) -> np.ndarray:
    """Odwrót: ósemki tłumionej rury na D2 (oktawa w dół na „raz”), tremolo wiolonczel rośnie co cztery takty;
    w drugiej połowie tremolo przechodzi na F / E♭ i dochodzi blacha na 2 i 4 — napęd bez melodii, na tym samym pedale."""
    bars = RETREAT_N // (SPB * 4)
    s = Stem(RETREAT_N)
    for bar in range(bars):
        b0 = bar * 4
        s.put(pipe(mtof(26), rng, 3.0, 0.7), b0, 0.5)
        for e in range(8):
            g = 0.36 if e % 2 == 0 else 0.22
            if bar >= bars // 2 and e in (3, 6):
                g += 0.08                                          # druga połowa: akcent przesunięty, pcha do przodu
            s.put(pipe(mtof(38 if e % 4 else 50), rng, 0.7, 0.45), b0 + e * 0.5, g, pan=0.2 if e % 2 else -0.2)
        if bar >= bars // 2:
            for beat in (1, 3):
                s.put(plate(rng, 200.0, 1.2), b0 + beat, 0.32, pan=0.3)
    seg = 4 * 4 * 60.0 / BPM + 0.6
    n = sec(seg)
    tr = tremolo(n, 0.6)
    cresc = d.env_pts(n, [(0, 0.15), (seg - 0.8, 1.0), (seg, 0.4)])
    for bar in range(0, bars, 4):
        pair = (38, 45) if bar < bars // 2 else ((41, 46) if bar % 8 == 0 else (39, 45))
        for i, m in enumerate(pair):
            s.put(bowed(mtof(m), seg, rng, 0.4) * tr * cresc, bar * 4, 0.16, pan=(-0.35, 0.35)[i])
    out = s.render(ir("hall_st"), wet=0.22)
    return tape(d.circ_filter(out, lambda x: d.compress(x, -18.0, 2.5, 10.0, 150.0)), 0.002, 1.2)


def hit_moment(rng: Rng) -> np.ndarray:
    """Uderzenie momentu (boss się budzi, zmiana fazy, start odwrotu): blacha, rura D1, sub i krótki jęk D2 / E♭2."""
    x = oneshot(4.5)
    put1(x, plate(rng, 150.0, 3.0, 1.3), 0.0, 0.9)
    put1(x, pipe(mtof(26), rng, 4.5, 1.0), 0.0, 0.9)
    put1(x, thump(1.8, 75.0, 28.0, 0.25, 0.8, attack=0.002), 0.0, 1.1)
    n = sec(3.5)
    for i, m in enumerate((38, 39)):
        put1(x, bowed(mtof(m), 3.5, rng, 0.5) * d.env_pts(n, [(0, 1.0), (3.5, 0.0)]) ** 1.5, 0.0, 0.22, pan=(-0.3, 0.3)[i])
    return d.reverb_stereo(x, ir("hall_st"), wet=0.35, dry=1.0)


def cadence_boss(rng: Rng) -> np.ndarray:
    """Śmierć bossa: ostatnie uderzenie i długa pusta kwinta D2 / A2 / D3 w pogłosie, zgrzyt opada — „po wszystkim”."""
    x = oneshot(10.0)
    put1(x, plate(rng, 120.0, 4.5, 1.4), 0.0, 1.0)
    put1(x, pipe(mtof(26), rng, 7.0, 1.0), 0.0, 1.0)
    put1(x, thump(2.4, 70.0, 26.0, 0.4, 1.2, attack=0.002), 0.0, 1.2)
    n = sec(9.0)
    for i, m in enumerate((38, 45, 50)):
        put1(x, bowed(mtof(m), 9.0, rng, 0.3) * d.env_pts(n, [(0, 0.0), (0.8, 1.0), (9.0, 0.0)]) ** 1.3, 0.1, 0.2, pan=(-0.4, 0.0, 0.4)[i])
    sc = scrape(sec(4.0), rng, 2200.0, 180.0)
    put1(x, sc * d.env_pts(sec(4.0), [(0, 1.0), (4.0, 0.0)]), 0.0, 0.18)
    return d.reverb_stereo(x, ir("cave_st"), wet=0.45, dry=1.0)


def build_stingers() -> None:
    rng = Rng(0x5710)
    # napięcie: zgrzyt metalu narasta, pod nim smyczek D / E♭ i miękkie tąpnięcie na końcu
    x = oneshot(2.6)
    n = sec(2.2)
    put1(x, scrape(n, rng, 300.0, 1800.0) * d.env_pts(n, [(0, 0), (1.8, 1), (2.2, 0)]), 0.0, 0.5)
    for i, m in enumerate((50, 51)):
        put1(x, bowed(mtof(m), 2.4, rng, 0.4) * d.env_pts(sec(2.4), [(0, 0.2), (1.8, 1.0), (2.4, 0.0)]), 0.0, 0.25, pan=(-0.3, 0.3)[i])
    put1(x, thump(1.0, 62.0, 34.0, 0.2, 0.3, attack=0.01), 1.9, 0.7)
    x = d.reverb_stereo(x, ir("cave_st"), wet=0.4, dry=0.8)[:, sec(PRE):]
    asset("sting_tension", "music/sting_tension")
    finalize("sting_tension", x, lufs=-17.0, fade_out_ms=300)

    # pościg: uderzenie w blachę i rurę, sub, krótki klaster smyczków z tremolo
    x = oneshot(3.0)
    put1(x, plate(rng, 190.0, 2.0, 1.4), 0.0, 1.0)
    put1(x, pipe(mtof(38), rng, 2.6, 1.0), 0.0, 0.8)
    put1(x, thump(1.5, 95.0, 30.0, 0.22, 0.45, attack=0.002), 0.0, 1.2)
    n = sec(1.8)
    for i, m in enumerate((62, 63, 69)):
        put1(x, bowed(mtof(m), 1.8, rng, 0.7) * tremolo(n, 0.8) * d.env_pts(n, [(0, 1.0), (1.8, 0.0)]), 0.0, 0.16, pan=(-0.4, 0.0, 0.4)[i])
    x = d.saturate(d.reverb_stereo(x, ir("hall_st"), wet=0.4, dry=0.8), 1.6)[:, sec(PRE):]
    asset("sting_chase", "music/sting_chase")
    finalize("sting_chase", x, lufs=-10.0, fade_out_ms=300)


CADENCE_PRE = PRE
CADENCE_SKIP_BARS = ()                 # pedał D: każdy takt przyjmuje kadencję (synthwave omijał dominantę A w taktach 4 i 8)

# Palety segmentów: klucz palety -> warianty każdej warstwy (cisza, napięcie, walka, pościg). Runtime szuka palety po
# map_id poziomu („z1_b1”), potem po strefie („z1”), na końcu „default”. Pierwszy wariant warstwy startuje grę.
SEGMENTS = {
    "default": (("mus_silence", "mus_silence_b"), ("mus_tension", "mus_tension_b"),
                ("mus_combat", "mus_combat_b"), ("mus_chase", "mus_chase_b")),
    # boss 1.4: zaczyna od sekcji B (blacha zamiast rury, niższe smyczki)
    "z1_b1": (("mus_silence_b", "mus_silence"), ("mus_tension_b", "mus_tension"),
              ("mus_combat_b", "mus_combat"), ("mus_chase_b", "mus_chase")),
}
# Kadencja grana, gdy warstwa gaśnie (indeks = warstwa); "" = zwykłe wyciszenie
CADENCES = ("", "", "mus_combat_end", "mus_chase_end")


def _rng(key: str) -> Rng:
    return Rng(zlib.crc32(("e3:" + key).encode()) & 0xFFFF)


def build_music() -> None:
    group("music")
    loops = (("mus_silence", lambda r: stem_silence(r), -27.0), ("mus_silence_b", lambda r: stem_silence(r, True), -27.0),
             ("mus_tension", lambda r: stem_tension(r), -26.0), ("mus_tension_b", lambda r: stem_tension(r, True), -26.0),
             ("mus_combat", lambda r: stem_combat(r), -21.0), ("mus_combat_b", lambda r: stem_combat(r, True), -21.0),
             ("mus_chase", lambda r: stem_chase(r), -22.0), ("mus_chase_b", lambda r: stem_chase(r, True), -22.0),
             ("mus_stalker_far", stem_stalker_far, -31.0), ("mus_stalker_near", stem_stalker_near, -25.0),
             ("mus_boss_1", stem_boss_1, -24.0), ("mus_boss_2", stem_boss_2, -23.0), ("mus_boss_3", stem_boss_3, -24.0),
             ("mus_retreat", stem_retreat, -21.0))
    for key, fn, target in loops:
        asset(key, "music/" + key, loop=True)
        x = fn(_rng(key))
        assert x.shape == (2, RETREAT_N if key == "mus_retreat" else LOOP_N), (key, x.shape)
        finalize(key, x, loop=True, lufs=target)
    # kadencje: przedbieg PRE ciszy musi zostać (runtime startuje je z przesunięciem), więc bez narastania na początku;
    # ogon pogłosu w całości (trim przy −55 dBFS przed normalizacją ucinał go słyszalnie)
    for key, fn, target in (("mus_combat_end", cadence_combat, -19.0), ("mus_chase_end", cadence_chase, -17.0),
                            ("mus_boss_end", cadence_boss, -16.0), ("mus_hit", hit_moment, -15.0)):
        asset(key, "music/" + key)
        finalize(key, fn(_rng(key)), lufs=target, fade_out_ms=600, fade_in_ms=0.0, trim=False)
    for key, fn, target in (("cue_horde", cue_horde, -16.0), ("cue_elite", cue_elite, -17.0)):
        asset(key, "music/" + key)
        finalize(key, fn(_rng(key))[:, sec(PRE):], lufs=target, fade_out_ms=400, trim=False)
    build_stingers()
