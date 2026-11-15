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

E5 (tożsamość): temat menu mus_menu (60 s) z wejściem mus_menu_in (strojenie), program radia w kryjówce radio_program
(pętla mono: ballada, stacja numeryczna, instrumental, strojenie między nimi), kadencje wyniku mus_result_win / mus_result_fail
i wipe'u mus_wipe.

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


# ------------------------------------------------------------------ E5: menu „z eteru”, radio w kryjówce, kadencje wyniku i wipe'u

def qsb(n: int, cycles: int, depth: float = 0.35, phase: float = 0.0) -> np.ndarray:
    """Zanik fal krótkich (QSB): powolne, okresowe w buforze pływanie siły sygnału."""
    t = np.arange(n) / n
    w = 0.6 * np.sin(TAU * cycles * t + phase) + 0.4 * np.sin(TAU * (cycles * 3 + 1) * t + 1.7 * phase + 0.4)
    return 1.0 - depth * (0.5 + 0.5 * w)


def am_band(x: np.ndarray, lo: float = 300.0, hi: float = 3400.0, drive: float = 1.6) -> np.ndarray:
    """Głośnik odbiornika AM: wąskie pasmo i lekki przester."""
    return d.saturate(d.lp(d.hp(x, lo, order=4), hi, order=4) * drive, 1.8) / drive


def ep_note(f: float, dur: float, rng: Rng, vel: float = 1.0) -> np.ndarray:
    """Fortepian elektryczny FM (jak DX7 E.PIANO): ton z opadającym indeksem i krótki „tine” wysoko."""
    n = sec(dur + 1.2)
    body = d.fm(f, n, ratio=1.0, index=(1.6 * vel) * d.env_exp(n, 0.35) + 0.2)
    tine = d.fm(f, n, ratio=14.0, index=0.8 * d.env_exp(n, 0.03)) * 0.12 * vel
    env = d.env_adsr(n, 0.003, 0.9, 0.35, 0.4) * d.env_pts(n, [(0, 1), (dur, 1), (dur + 1.2, 0)])
    return (body * 0.7 + tine) * env * vel


def pad_chord(ms_, dur: float, rng: Rng) -> np.ndarray:
    """Smyczki „Solina”: piły rozstrojone, filtr, wolne natarcie."""
    n = sec(dur + 0.8)
    y = np.zeros(n)
    for m in ms_:
        f = mtof(m)
        for det in (-0.004, 0.0, 0.005):
            y += d.osc("saw", f * (1 + det), n, rng.uniform(0, 1))
    y = d.lp(y / (3 * len(ms_)), 1800.0, 0.8)
    return y * d.env_adsr(n, 0.5, 0.3, 0.85, 0.8)


def flute(f: float, dur: float, rng: Rng) -> np.ndarray:
    n = sec(dur + 0.3)
    fr = d.vibrato(f, n, 5.2, 12.0, rng.uniform(0, TAU)) * np.where(np.arange(n) < sec(0.25), 1.0, 1.0)
    y = d.osc("sine", fr, n) + d.osc("sine", fr * 2, n) * 0.18
    breath = d.bp(d.white(n, rng), f * 2, 3.0) * 0.12
    return (y + breath) * d.env_adsr(n, 0.06, 0.2, 0.8, 0.25)


def lead_saw(f: float, dur: float, rng: Rng) -> np.ndarray:
    n = sec(dur + 0.2)
    fr = d.vibrato(f, n, 5.5, 8.0, rng.uniform(0, TAU))
    y = d.osc("saw", fr, n) * 0.6 + d.osc("square", fr * 1.003, n, pw=0.4) * 0.4
    y = d.sweep(y, "lp", d.glide_exp(4200.0, 1600.0, n, 0.15), 1.2)
    return y * d.env_adsr(n, 0.01, 0.15, 0.7, 0.15)


def pluck_sq(f: float, dur: float, rng: Rng, cut: float = 2600.0) -> np.ndarray:
    n = sec(dur)
    y = d.osc("square", f, n, pw=0.3)
    return d.sweep(y, "lp", d.glide_exp(cut, 400.0, n, 0.05), 1.4) * d.env_perc(n, 0.002, dur * 0.4)


def music_box(f: float, rng: Rng, dur: float = 2.2) -> np.ndarray:
    """Pozytywka: grzebień stalowy, mody belki wspornikowej."""
    n = sec(dur)
    return d.modal([f, f * 6.27, f * 17.55], [1.0, 0.3, 0.08], [dur, dur * 0.4, dur * 0.15], n, rng, 0.001) * 0.5


def kick_soft(rng: Rng) -> np.ndarray:
    return thump(0.3, 95.0, 48.0, 0.03, 0.12, attack=0.002)


def snare_dm(rng: Rng) -> np.ndarray:
    n = sec(0.25)
    tone = d.osc("sine", d.glide_exp(240.0, 180.0, n, 0.03), n) * d.env_perc(n, 0.001, 0.06)
    nz = d.bp(d.white(n, rng), 2200.0, 0.8) * d.env_perc(n, 0.001, 0.09)
    return tone * 0.5 + nz * 0.8


class Mono:
    """Bufor mono w sekundach (utwory radia, nie na siatce muzyki)."""

    def __init__(self, dur: float):
        self.buf = np.zeros(sec(dur) + sec(4.0))

    def put(self, sig: np.ndarray, at: float, g: float = 1.0) -> None:
        k = sec(at)
        m = min(len(sig), len(self.buf) - k)
        if m > 0:
            self.buf[k:k + m] += sig[:m] * g


RADIO_A_CHORDS = ((50, 57, 62, 65), (55, 58, 62, 67), (48, 55, 60, 64), (53, 57, 60, 65),
                  (46, 53, 58, 62), (55, 58, 62, 67), (45, 57, 61, 64), (50, 57, 62, 65))     # Dm Gm C F B♭ Gm A Dm
RADIO_A_MELODY = (((69, 0, 1.5), (67, 1.5, .5), (65, 2, 1), (64, 3, 1)), ((62, 0, 2), (67, 2, 1), (70, 3, 1)),
                  ((69, 0, 1.5), (67, 1.5, .5), (64, 2, 2)), ((65, 0, 3),),
                  ((74, 0, 1.5), (72, 1.5, .5), (70, 2, 1), (69, 3, 1)), ((67, 0, 1), (70, 1, 1), (74, 2, 2)),
                  ((76, 0, 1.5), (74, 1.5, .5), (73, 2, 2)), ((74, 0, 3),))


def radio_song_a(rng: Rng) -> np.ndarray:
    """Ballada „z estrady” lat 80 (76 BPM, d-moll z A-dur przed toniką): fortepian elektryczny, smyczki, flet."""
    beat = 60.0 / 76.0
    bars = 16
    m = Mono(bars * 4 * beat)
    for b in range(bars):
        t0 = b * 4 * beat
        ch = RADIO_A_CHORDS[b % 8]
        m.put(ep_note(mtof(ch[0] - 12), beat * 1.8, rng, 0.9), t0, 0.5)
        for k in (1.0, 2.5):
            for x in ch[1:]:
                m.put(ep_note(mtof(x), beat * 1.2, rng, 0.6), t0 + k * beat + rng.uniform(0, 0.012), 0.22)
        m.put(pad_chord(ch[1:], 4 * beat, rng), t0, 0.16)
        m.put(kick_soft(rng), t0, 0.35)
        for e in range(8):
            m.put(tick(rng, 6500.0, 3.0, 12.0), t0 + e * 0.5 * beat, 0.05 if e % 2 else 0.08)
        mel = RADIO_A_MELODY[b % 8]
        up = 12 if (b >= 8 and b % 8 in (4, 5, 6)) else 0
        for mm, off, du in mel:
            m.put(flute(mtof(mm + up), du * beat, rng), t0 + off * beat, 0.32)
    out = m.buf
    return d.reverb(out, ir("plate_st")[0], wet=0.22, dry=1.0, keep_len=True)


RADIO_B_CHORDS = ((50, 53, 57), (46, 50, 53), (53, 57, 60), (48, 52, 55))       # Dm B♭ F C
RADIO_B_PHRASE = ((0, 69, 1), (1, 74, 1), (2, 72, .5), (2.5, 69, 1.5), (4, 70, 1), (5, 69, .5), (5.5, 67, .5), (6, 65, 2),
                  (8, 65, .5), (8.5, 67, .5), (9, 69, 1), (10, 72, 2), (12, 72, 1), (13, 70, 1), (14, 69, 2))
RADIO_B_END = ((12, 76, 1), (13, 74, 1), (14, 72, .5), (14.5, 74, 1.5))


def radio_song_b(rng: Rng) -> np.ndarray:
    """Instrumental syntezatorowy z radia lat 80 (112 BPM): automat perkusyjny, bas ósemkami, arpeggio, prowadzący syntezator."""
    beat = 60.0 / 112.0
    bars = 24
    m = Mono(bars * 4 * beat)
    for b in range(bars):
        t0 = b * 4 * beat
        ch = RADIO_B_CHORDS[b % 4]
        for k in (0, 2):
            m.put(kick_soft(rng), t0 + k * beat, 0.6)
        if b >= 2:
            for k in (1, 3):
                m.put(snare_dm(rng), t0 + k * beat, 0.35)
        for e in range(8):
            m.put(tick(rng, 7000.0, 3.0, 10.0), t0 + e * 0.5 * beat, 0.07 if e % 2 else 0.04)
            m.put(pluck_sq(mtof(ch[0] - 12), 0.45 * beat, rng, 1200.0), t0 + e * 0.5 * beat, 0.32)
        for st in range(16):
            x = ch[(0, 1, 2, 1)[st % 4]] + 12 + (12 if st % 8 >= 4 else 0)
            m.put(pluck_sq(mtof(x), 0.22 * beat, rng), t0 + st * 0.25 * beat, 0.09)
        if 4 <= b < 20:
            ph = (b - 4) // 4
            if b % 4 == 0:
                notes = RADIO_B_PHRASE if ph % 2 == 0 else RADIO_B_PHRASE[:-3] + RADIO_B_END
                for off, mm, du in notes:
                    m.put(lead_saw(mtof(mm), du * beat * 0.95, rng), t0 + off * beat, 0.2)
    out = m.buf
    return d.reverb(out, ir("plate_st")[0], wet=0.18, dry=1.0, keep_len=True)


MORSE = {"0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...",
         "8": "---..", "9": "----."}
NUMBERS_GROUPS = ("19870", "31586", "00427", "87087")          # „87” w każdej transmisji — rok, w którym ucichło


def morse(text: str, wpm: float = 18.0, f: float = 880.0) -> np.ndarray:
    dit = 1.2 / wpm
    parts = []
    for ch in text:
        if ch == " ":
            parts.append(np.zeros(sec(dit * 7)))
            continue
        for sym in MORSE[ch]:
            n = sec(dit * (3 if sym == "-" else 1))
            tone = d.osc("sine", f, n) * d.env_pts(n, [(0, 0), (0.004, 1), (n / SR - 0.004, 1), (n / SR, 0)])
            parts.append(tone)
            parts.append(np.zeros(sec(dit)))
        parts.append(np.zeros(sec(dit * 2)))
    return np.concatenate(parts)


def radio_numbers(rng: Rng) -> np.ndarray:
    """Stacja numeryczna: sygnał interwałowy na pozytywce (motyw Stalkera, dwie oktawy wyżej) i grupy cyfr Morse'em."""
    def interval(m: Mono, t0: float) -> float:
        for mm, b, _ in MOTIF:
            m.put(music_box(mtof(mm + 24), rng), t0 + b * 0.55, 0.5)
        return t0 + 4.0 * 0.55 + 1.6
    m = Mono(48.0)
    t = 0.3
    for _ in range(3):
        t = interval(m, t)
    t += 0.8
    mo = morse(" ".join(NUMBERS_GROUPS))
    m.put(mo, t, 0.35)
    t += len(mo) / SR + 1.2
    t = interval(m, t)
    return m.buf[:sec(t + 1.5)]


def tuning(rng: Rng, dur: float = 4.0) -> np.ndarray:
    """Strojenie odbiornika: szum przez sunący filtr, gwizd heterodyny, trzaski."""
    n = sec(dur)
    nz = d.sweep(d.white(n, rng), "bp", np.geomspace(2600.0, 700.0, n) * (1 + 0.3 * np.sin(np.linspace(0, 7, n))), 2.0) * 0.5
    wh = d.osc("sine", d.glide_exp(2600.0, 900.0, n, dur * 0.4) + 180 * np.sin(np.linspace(0, 11, n)), n) * 0.08
    cr = np.zeros(n)
    for _ in range(int(dur * 9)):
        k = int(rng.integers(0, n - 200))
        cr[k:k + 120] += d.white(120, rng) * d.env_perc(120, 0.0002, 0.0015) * rng.uniform(0.2, 0.8)
    return (nz + wh + cr) * d.env_pts(n, [(0, 0), (0.4, 1), (dur - 0.4, 1), (dur, 0)])


def radio_program(rng: Rng) -> np.ndarray:
    """Program radia w kryjówce (pętla mono): ballada → strojenie → stacja numeryczna → strojenie → instrumental → strojenie.
    Wszystko przez głośnik AM, z szumem eteru i zanikami QSB; ogony zawinięte na początek, więc pętla jest bez szwu."""
    segs = [radio_song_a(rng), tuning(rng), radio_numbers(rng), tuning(rng), radio_song_b(rng) * 1.45, tuning(rng, 4.5)]   # instrumental rzadszy — wyrównany do ballady
    lens = [len(x) for x in segs]
    ov = sec(0.8)
    total = sum(lens) - ov * len(segs)
    buf = np.zeros(total + max(lens))
    k = 0
    for x in segs:
        x = d.fade_edges(x, 300.0, 800.0)
        buf[k:k + len(x)] += x
        k += len(x) - ov
    prog = d.fold_loop(buf, total)
    prog = d.circ_filter(prog, lambda x: am_band(x * 1.4))
    hiss = d.circ_filter(d.white(total, rng), lambda x: d.lp(d.hp(x, 1200.0), 6000.0)) * 0.02
    hum = np.sin(TAU * round(100.0 * total / SR) / (total / SR) * np.arange(total) / SR) * 0.006
    cycles = max(1, int(total / SR / 18))
    return (prog * qsb(total, cycles, 0.3) + hiss + hum)


MENU_N = 2 * LOOP_N                  # temat menu: 60 s na siatce muzyki (te same 64 BPM i pedał D)


def stem_menu(rng: Rng) -> np.ndarray:
    """Temat menu „z eteru”: dron D z taśmy, motyw Stalkera najpierw z odbiornika (wąskie pasmo, zaniki), potem czysto
    smyczkiem — temat wyłania się z szumu. Daleki metal; nic poza tym (D11: jedyna melodia to motyw)."""
    bed = drone_bed(rng)
    bed = np.concatenate([bed, bed], axis=1)
    radio = Stem(MENU_N)
    clean = Stem(MENU_N)
    for bar in (1, 3):
        motif_into(radio, bar * 4, rng, 0.5, 0.75)
    for bar in (9, 11):
        motif_into(clean, bar * 4, rng, 0.3, 0.5)
    r = radio.render(ir("cave_st"), wet=0.2)
    r = d.circ_filter(r, lambda x: am_band(x, 380.0, 2600.0, 2.0)) * qsb(MENU_N, 5, 0.45)
    c = clean.render(ir("cave_st"), wet=0.55)
    ev = Stem(MENU_N)
    for bar, m in ((6, 50), (14, 45)):
        ev.put(pipe(mtof(m), rng, 5.0, 0.6), bar * 4 + 2.5, 0.2, pan=-0.4 if bar == 6 else 0.4)
    e = ev.render(ir("cave_st"), wet=0.8)
    st = d.circ_filter(d.white(MENU_N, rng), lambda x: d.bp(x, 1400.0, 0.7)) * 0.012 * qsb(MENU_N, 7, 0.8, 1.0)
    out = bed * 0.8 + r + c + e + np.stack([st, np.roll(st, sec(0.02))])
    return tape(out, 0.004, 1.15)


def menu_intro(rng: Rng) -> np.ndarray:
    """Wejście do menu: strojenie odbiornika — szum, gwizd, urywek Morse'a — i zanik szumu, spod którego wychodzi dron."""
    n = sec(7.0)
    tu = tuning(rng, 6.0)
    x = np.zeros(n)
    x[:len(tu)] += tu * d.env_pts(len(tu), [(0, 0.6), (3.5, 1.0), (6.0, 0.0)])
    mo = morse("87", 20.0, 760.0)
    k = sec(1.6)
    x[k:k + len(mo)] += mo * 0.18
    x = am_band(x, 250.0, 3800.0)
    st = np.stack([x, np.roll(x, sec(0.015))])
    return d.reverb_stereo(st, ir("cave_st"), wet=0.25, dry=1.0)


def cadence_result_win(rng: Rng) -> np.ndarray:
    """Udana ekstrakcja: smyczek schodzi z A na D (koniec motywu), pusta kwinta i — cicho, wysoko — tercja wielka (ulga)."""
    x = oneshot(9.0)
    put1(x, bowed(mtof(45), 1.6, rng, 0.3) * d.env_pts(sec(1.6), [(0, 0.3), (0.6, 1.0), (1.6, 0.0)]), 0.0, 0.3)
    n = sec(7.0)
    for i, m in enumerate((38, 45, 50)):
        put1(x, bowed(mtof(m), 7.0, rng, 0.25) * d.env_pts(n, [(0, 0), (0.8, 1.0), (7.0, 0.0)]), 1.4, 0.22, pan=(-0.4, 0.0, 0.4)[i])
    put1(x, pipe(mtof(38), rng, 5.0, 0.6), 1.4, 0.4)
    put1(x, music_box(mtof(78), rng, 4.0), 2.6, 0.18, pan=0.3)            # F♯5
    put1(x, music_box(mtof(74), rng, 4.0), 3.2, 0.16, pan=-0.3)           # D5
    return tape(d.reverb_stereo(x, ir("cave_st"), wet=0.45, dry=1.0), 0.002, 1.1)


def cadence_result_fail(rng: Rng) -> np.ndarray:
    """Koniec serii (Nocny Dyżur): uderzenie w rurę, klaster D / E♭ zsuwa się o pół tonu, taśma zwalnia na końcu."""
    x = oneshot(8.0)
    put1(x, pipe(mtof(26), rng, 6.0, 0.8), 0.0, 0.8)
    put1(x, thump(1.4, 60.0, 28.0, 0.3, 0.8, attack=0.003), 0.0, 0.9)
    n = sec(6.5)
    for i, m in enumerate((50, 51)):
        gl = d.glide_exp(mtof(m), mtof(m - 1), n, 2.5)
        put1(x, bowed(gl, 6.5, rng, 0.3) * d.env_pts(n, [(0, 0), (0.5, 1.0), (6.5, 0.0)]), 0.2, 0.22, pan=(-0.35, 0.35)[i])
    y = d.reverb_stereo(x, ir("cave_st"), wet=0.4, dry=1.0)[:, :sec(PRE) + sec(7.5)]
    return tape_stop_tail(y, 2.5)


def tape_stop_tail(x: np.ndarray, dur: float) -> np.ndarray:
    """Ostatnie `dur` s zwalnia jak zatrzymywana taśma (prędkość odczytu → 0)."""
    n = x.shape[-1]
    k = n - sec(dur)
    sp = np.ones(n)
    sp[k:] = np.linspace(1.0, 0.0, n - k) ** 1.6
    pos = np.cumsum(sp) - sp[0]
    i0 = np.clip(pos.astype(np.int64), 0, n - 2)
    fr = pos - i0
    y = np.stack([c[i0] * (1 - fr) + c[i0 + 1] * fr for c in x])
    return y * d.env_pts(n, [(0, 1.0), (k / SR, 1.0), (n / SR, 0.0)]) ** 0.7


def cadence_wipe(rng: Rng) -> np.ndarray:
    """Wipe: po zatrzymaniu muzyki (silnik zwalnia stemy jak taśmę) zostaje niskie D, które dogasa, i szum końca taśmy."""
    x = oneshot(5.0)
    put1(x, thump(1.8, 48.0, 26.0, 0.4, 1.0, attack=0.01), 0.0, 0.7)
    n = sec(4.5)
    put1(x, bowed(mtof(26 + 12), 4.5, rng, 0.15) * d.env_pts(n, [(0, 1.0), (4.5, 0.0)]) ** 1.5, 0.0, 0.3)
    hiss = d.lp(d.white(n, rng), 3000.0) * d.env_pts(n, [(0, 0.0), (0.3, 1.0), (4.5, 0.0)]) * (0.6 + 0.4 * np.sin(np.linspace(0, 40, n)) ** 2)
    put1(x, hiss, 0.0, 0.05)
    return d.reverb_stereo(x, ir("cave_st"), wet=0.4, dry=1.0)


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
             ("mus_retreat", stem_retreat, -21.0), ("mus_menu", stem_menu, -23.0))
    for key, fn, target in loops:
        asset(key, "music/" + key, loop=True)
        x = fn(_rng(key))
        assert x.shape == (2, {"mus_retreat": RETREAT_N, "mus_menu": MENU_N}.get(key, LOOP_N)), (key, x.shape)
        finalize(key, x, loop=True, lufs=target)
    # kadencje: przedbieg PRE ciszy musi zostać (runtime startuje je z przesunięciem), więc bez narastania na początku;
    # ogon pogłosu w całości (trim przy −55 dBFS przed normalizacją ucinał go słyszalnie)
    for key, fn, target in (("mus_combat_end", cadence_combat, -19.0), ("mus_chase_end", cadence_chase, -17.0),
                            ("mus_boss_end", cadence_boss, -16.0), ("mus_hit", hit_moment, -15.0)):
        asset(key, "music/" + key)
        finalize(key, fn(_rng(key)), lufs=target, fade_out_ms=600, fade_in_ms=0.0, trim=False)
    # E5: grane od razu (bez siatki), więc bez przedbiegu; program radia to pętla mono (głośnik w świecie)
    for key, fn, target in (("mus_result_win", cadence_result_win, -18.0), ("mus_result_fail", cadence_result_fail, -18.0),
                            ("mus_wipe", cadence_wipe, -21.0), ("mus_menu_in", menu_intro, -24.0)):
        asset(key, "music/" + key)
        finalize(key, fn(_rng(key))[:, sec(PRE):], lufs=target, fade_out_ms=500, trim=False)
    asset("radio_program", "music/radio_program", loop=True)
    finalize("radio_program", radio_program(_rng("radio_program")), loop=True, lufs=-17.0)
    for key, fn, target in (("cue_horde", cue_horde, -16.0), ("cue_elite", cue_elite, -17.0)):
        asset(key, "music/" + key)
        finalize(key, fn(_rng(key))[:, sec(PRE):], lufs=target, fade_out_ms=400, trim=False)
    build_stingers()
