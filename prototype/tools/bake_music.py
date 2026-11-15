"""
bake_music.py — muzyka adaptacyjna: cztery STEMY, które się NAKŁADAJĄ (vertical layering).

Poprzednia wersja renderowała każdą warstwę jako pełny, samodzielny utwór, a runtime
przenikał je między sobą (crossfade pełnych utworów = podwójny bas i perkusja w trakcie
przejścia). Teraz stemy są zaprojektowane jako addytywne:

    S0 mus_silence  pad + sub-pedał + rzadkie „szklane" akcenty          (zawsze gra)
    S1 mus_tension  ostinato basowe (8-tki), puls serca, melodia wysoko  (+ napięcie)
    S2 mus_combat   perkusja 16-tkowa z gated snare, bas 16-tkowy, stab   (+ walka)
    S3 mus_chase    arpeggio 16-tkowe, toomy, crash, riser, dysonans      (+ pościg)

Poza warstwami (MUSIC_PLAN.md E1): motyw Stalkera mus_stalker_far / mus_stalker_near (ta sama siatka, runtime przenika
wg odległości) i jednorazowe sygnały cue_elite / cue_horde.

Runtime (audio_director.gd) ustawia głośność stemów niezależnie i kwantyzuje wejścia do
beatu/taktu — dlatego wszystkie stemy mają IDENTYCZNĄ długość i siatkę.

Siatka: 96 BPM → 30000 próbek/beat (CAŁKOWITA liczba, więc rytm nie dryfuje przy zaokrąglaniu),
8 taktów 4/4 = 32 beaty = 960000 próbek = 20,000 s. Tonacja d-moll, progresja
| Dm | B♭ | Gm | A | Dm | B♭ | Gm | A |, z wariacją w taktach 5–8 (melodia, wypełnienie).
Pętla zamyka się dokładnie: zdarzenia i pogłos zawijane fold_loop(), częstotliwości sub-pedału
mają całkowitą liczbę cykli w pętli.
"""

from __future__ import annotations

import zlib

import numpy as np

import audio_dsp as d
from audio_dsp import SR, Rng, ms, sec
from bake_common import asset, finalize, group, ir, thump, tick, vary

TAU = d.TAU
BPM = 96.0
SPB = int(round(SR * 60.0 / BPM))      # 30000
BARS = 8
BEATS = BARS * 4
LOOP_N = SPB * BEATS                   # 960000
TAIL = sec(4.0)                        # zapas na wybrzmienia (zawijane na początek)
assert abs(SR * 60.0 / BPM - SPB) < 1e-9, "BPM musi dawać całkowitą liczbę próbek na beat"

# akordy (MIDI) — Dm, B♭, Gm, A  (A dur: C♯ = napięcie dominanty)
CHORDS = [(50, 53, 57), (46, 50, 53), (43, 46, 50), (45, 49, 52)] * 2
ROOTS = [38, 34, 31, 33] * 2           # basy (oktawa niżej)


def mtof(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def T(beat: float) -> int:
    return int(round(beat * SPB))


class Stem:
    """Bufor stereo (dłuższy o TAIL) z prostym API do kładzenia zdarzeń."""

    def __init__(self):
        self.buf = np.zeros((2, LOOP_N + TAIL))

    def put(self, sig: np.ndarray, beat: float, gain: float = 1.0, pan: float = 0.0) -> None:
        k = T(beat)
        if sig.ndim == 1:
            sig = d.pan(sig, pan) if pan != 0.0 else np.stack([sig, sig]) * 0.7071
        n = min(sig.shape[1], self.buf.shape[1] - k)
        if n > 0:
            self.buf[:, k:k + n] += sig[:, :n] * gain

    def render(self, rev=None, wet: float = 0.0, glue: bool = True) -> np.ndarray:
        x = self.buf
        if rev is not None and wet > 0.0:
            x = d.reverb_stereo(x, rev, wet=wet, dry=1.0, keep_len=False)
        x = d.fold_loop(x, LOOP_N)
        return x


# ------------------------------------------------------------------ instrumenty

def saw_pad(freqs, n: int, rng: Rng, cutoff: float = 900.0, detune: float = 9.0) -> np.ndarray:
    """Pad: dla każdej nuty 3 piły (±detune centów) — L i R z różnymi fazami i układem
    detune (szerokość stereo bez opóźnień)."""
    out = np.zeros((2, n))
    for f in freqs:
        for c in range(2):
            for k, cents in enumerate((-detune, 0.0, detune)):
                ff = f * 2.0 ** ((cents * (1 if c == 0 else -1)) / 1200.0)
                out[c] += d.osc("saw", ff, n, phase0=rng.uniform(0, 1)) * (0.5 if k == 1 else 0.35)
    return d.lp(out, cutoff, 0.8)


def pluck_bass(f: float, dur: float, rng: Rng, cut_hi=2400.0, cut_lo=260.0, q=2.4, tau=0.10,
               sub=0.45) -> np.ndarray:
    n = sec(dur)
    w = d.osc("saw", f, n) * 0.6 + d.osc("square", f * 1.002, n, pw=0.45) * 0.4
    y = d.sweep(w, "lp", d.glide_exp(cut_hi, cut_lo, n, tau), q)
    y = y + sub * d.osc("sine", f, n)
    return d.saturate(y, 1.4) * d.env_adsr(n, 0.004, 0.06, 0.85, min(0.08, dur * 0.4))


def stab(freqs, dur: float, rng: Rng, bright=3800.0) -> np.ndarray:
    n = sec(dur)
    y = np.zeros(n)
    for f in freqs:
        y += d.osc("saw", f, n, phase0=rng.uniform(0, 1)) * 0.5 + d.osc("saw", f * 1.007, n) * 0.5
    y = d.sweep(y, "lp", d.glide_exp(bright, 600.0, n, dur * 0.35), 1.6)
    return d.saturate(y * 0.4, 1.6) * d.env_perc(n, 0.003, dur * 0.35)


def kick(rng: Rng, power=1.0) -> np.ndarray:
    return d.mix([(thump(.34, 160.0, 46.0, .018, .10 * power), 1.0), (tick(rng, 3200.0, 1.0, 6, .0012), .35)])


def snare(rng: Rng) -> np.ndarray:
    n = ms(260)
    nz = d.filt(d.white(n, rng), "bp", 2100.0, 0.6) * d.env_perc(n, .0005, .075)
    body = d.osc("sine", d.glide_exp(240.0, 150.0, n, .03), n) * d.env_perc(n, .0005, .06)
    return d.saturate(d.mix([(nz, 1.2), (body, .8), (tick(rng, 4500.0, 1.0, 5, .001), .4)], n), 1.8)


def hat(rng: Rng, open_=False) -> np.ndarray:
    n = ms(260 if open_ else 70)
    return d.filt(d.white(n, rng), "hp", 7200.0, order=3) * d.env_perc(n, .0003, .09 if open_ else .014) * 1.4


def tom(f: float, rng: Rng) -> np.ndarray:
    n = ms(320)
    return d.mix([(thump(.3, f * 1.6, f, .03, .09), 1.0), (d.filt(d.white(ms(30), rng), "bp", 1500.0, .8) * d.env_perc(ms(30), .0004, .006), .5)], n)


def crash(rng: Rng, dur=2.2) -> np.ndarray:
    n = sec(dur)
    return d.filt(d.white(n, rng), "hp", 4500.0, order=2) * d.env_perc(n, .002, .5) * 1.2


def riser(n: int, rng: Rng, f0=300.0, f1=7000.0) -> np.ndarray:
    return d.sweep(d.white(n, rng), "bp", np.geomspace(f0, f1, n), 1.3) * np.linspace(0.0, 1.0, n) ** 2.2


def glass_ping(f: float, rng: Rng, dur=2.4) -> np.ndarray:
    """Szklany akcent FM (dzwonek) — opadający indeks modulacji = jasny atak, miękki zanik."""
    n = sec(dur)
    idx = 4.0 * np.exp(-np.arange(n) / (0.35 * SR)) + 0.2
    return d.fm(f, n, ratio=3.5, index=idx) * d.env_perc(n, .002, .55)


# ------------------------------------------------------------------ stemy

def stem_silence(rng: Rng) -> np.ndarray:
    s = Stem()
    bar = 4
    # pad: jeden akord na takt, każdy z nakładką (crossfade) ~1 beat z poprzednim
    for b in range(BARS):
        ch = [mtof(m) for m in CHORDS[b]] + [mtof(CHORDS[b][0] + 12)]
        seg = T(bar + 1.2)
        pad = saw_pad(ch, seg, rng, cutoff=760.0)
        pad *= d.env_adsr(seg, 1.1 * SPB / SR, 0.5, 0.85, 1.6 * SPB / SR)
        s.put(pad, b * bar, 0.5)
    # sub-pedał D1 (+ oktawa) — całkowita liczba cykli w pętli (szew bez skoku fazy)
    L = LOOP_N / SR
    t = np.arange(LOOP_N) / SR
    f1 = round(36.708 * L) / L
    sub = (np.sin(TAU * f1 * t) + 0.4 * np.sin(TAU * 2 * f1 * t)) * (0.8 + 0.2 * np.sin(TAU * 2 * t / L))
    s.buf[:, :LOOP_N] += np.stack([sub, sub]) * 0.22
    # rzadkie szklane akcenty z długim pogłosem (jedna nuta na 2 takty)
    for b, m in ((0, 74), (2, 69), (4, 77), (6, 72)):
        s.put(glass_ping(mtof(m), rng) * 0.35, b * bar + 1.5, 1.0, pan=rng.uniform(-0.6, 0.6))
    out = s.render(ir("cave_st"), wet=0.38)
    return d.circ_filter(out, lambda t: d.compress(t, -22.0, 2.0, 30.0, 400.0))


def stem_tension(rng: Rng) -> np.ndarray:
    s = Stem()
    off_sets = {0: (0, 12, 0, 7, 0, 12, 0, 10), 1: (0, 12, 0, 7, 0, 12, 0, 11),
                2: (0, 12, 0, 7, 0, 12, 0, 10), 3: (0, 12, 0, 7, 0, 12, 0, 10)}
    acc = (1.0, .55, .8, .55, .9, .55, .8, .6)
    for b in range(BARS):
        root = ROOTS[b]
        for i in range(8):
            f = mtof(root + off_sets[b % 4][i])
            # powolne „otwieranie" filtra przez całą pętlę (całkowita liczba cykli)
            phase = TAU * (b * 8 + i) / 64.0
            hi = 1900.0 + 900.0 * np.sin(phase) + (500.0 if i in (0, 4) else 0.0)
            note = pluck_bass(f, 0.46 * 60.0 / BPM * 2, rng, cut_hi=hi, cut_lo=240.0, q=2.6, tau=.09, sub=.5)
            s.put(note, b * 4 + i * 0.5, 0.55 * acc[i], pan=0.0)
        # miękki „puls serca" na 1 i 3
        for beat in (0, 2):
            s.put(thump(.4, 78.0, 40.0, .05, .12), b * 4 + beat, 0.55)
    # melodia (takty 5–8): szklane pluck'i, ECHO + pogłos, rzadkie
    melody = {4: ((0, 74, 1.5), (1.5, 77, 1.5), (3, 81, 1.0)), 5: ((0, 79, 1.5), (1.5, 77, 1.5), (3, 74, 1.0)),
              6: ((0, 70, 2.0), (2, 74, 1.5), (3.5, 79, 0.5)), 7: ((0, 73, 1.0), (1, 76, 1.5), (2.5, 81, 1.5))}
    for b, notes in melody.items():
        for off, m, _ in notes:
            s.put(glass_ping(mtof(m), rng, 1.8) * 0.5, b * 4 + off, 1.0, pan=0.25 if m % 2 else -0.25)
    # riser pod koniec taktu 4 i 8 (do ponownego wejścia w Dm)
    for b in (3, 7):
        r_ = riser(T(1.8), rng, 400.0, 5200.0) * 0.25
        s.put(r_, b * 4 + 2.2, 1.0)
    out = s.render(ir("plate_st"), wet=0.30)
    return d.circ_filter(out, lambda t: d.compress(t, -20.0, 2.5, 12.0, 200.0))


def stem_combat(rng: Rng) -> np.ndarray:
    s = Stem()
    gate = ir("gate_st")
    for b in range(BARS):
        base = b * 4
        root = ROOTS[b]
        # kick: 1, „i" 2, 3.5 — pchnięcie do przodu
        for pos, g in ((0, 1.0), (1.5, .8), (2.5, .9), (3.75, .5)):
            s.put(kick(rng) * 1.2, base + pos, g)
        # snare 2 i 4 z gated reverb (klasyk lat 80.) — mokra kopia przechodzi przez bramkę
        for pos in (1.0, 3.0):
            sn = snare(rng)
            gated = d.reverb_stereo(np.stack([sn, sn]), gate, wet=1.0, dry=0.0, keep_len=False)
            env = d.env_pts(gated.shape[1], [(0, 1), (.20, 1), (.24, 0)])
            s.put(gated * env * 0.8, base + pos, 1.0)
            s.put(sn * 0.9, base + pos, 1.0)
        # hi-haty: 16-tki z akcentem, open-hat na „i" 2 i 4
        for st in range(16):
            beat = st * 0.25
            acc = 1.0 if st % 4 == 0 else (.62 if st % 2 == 0 else .38)
            if st in (6, 14):
                s.put(hat(rng, True), base + beat, .45, pan=.3)
            else:
                s.put(hat(rng), base + beat, .35 * acc, pan=-.25 if st % 2 else .25)
        # bas 16-tkowy z oktawą w górę na synkopach
        for st in range(16):
            oct_ = 12 if st in (3, 7, 11, 15) else 0
            note = pluck_bass(mtof(root + oct_), .20, rng, cut_hi=2600.0 + 400.0 * (st % 4 == 0), cut_lo=300.0, q=2.0, tau=.06, sub=.6)
            s.put(note, base + st * 0.25, 0.55 if st % 4 else 0.7)
        # stab akordowy (synkopy)
        ch = [mtof(m + 12) for m in CHORDS[b]]
        for pos in (0.75, 2.25):
            s.put(stab(ch, 0.34, rng) * 0.9, base + pos, 0.5, pan=0.15)
    out = s.render(ir("plate_st"), wet=0.16)
    out = d.saturate(out, 1.4)
    return d.circ_filter(out, lambda t: d.compress(t, -16.0, 3.0, 8.0, 120.0))


def stem_chase(rng: Rng) -> np.ndarray:
    s = Stem()
    for b in range(BARS):
        base = b * 4
        root = ROOTS[b]
        ch = CHORDS[b]
        # arpeggio 16-tkowe (piła + kwadrat), wzór góra-dół po akordzie
        pattern = (0, 1, 2, 1, 0, 1, 2, 3)
        for st in range(16):
            m = ch[pattern[st % 8] % 3] + 24 + (12 if pattern[st % 8] == 3 else 0)
            n = sec(0.17)
            f = mtof(m)
            y = d.osc("saw", f, n) * .6 + d.osc("square", f * 1.004, n, pw=.4) * .4
            y = d.sweep(y, "lp", d.glide_exp(5200., 900., n, .06), 2.0) * d.env_perc(n, .002, .05)
            s.put(y, base + st * 0.25, .22, pan=-.4 + .8 * (st % 4) / 3.0)
        # skrzywiony bas oktawę wyżej, 8-tki
        for i in range(8):
            note = pluck_bass(mtof(root + 12), .22, rng, cut_hi=3600., cut_lo=500., q=3.0, tau=.05, sub=.1)
            s.put(d.saturate(note * 1.5, 3.0), base + i * 0.5, .28)
        # dysonansowy tritonus (co 2 takty)
        if b % 2 == 0:
            tri = [mtof(root + 24), mtof(root + 30)]
            s.put(stab(tri, 0.5, rng, 4500.) * 1.1, base + 3.0, .4)
        # crash na początku taktów 1 i 5, riser + toomy kończące 4 i 8
        if b in (0, 4):
            s.put(crash(rng), base, .35)
        if b in (3, 7):
            s.put(riser(T(1.7), rng, 500., 9000.) * .4, base + 2.2, 1.0)
            for i, f in enumerate((220., 196., 174., 155., 138., 123., 110., 98.)):
                s.put(tom(f, rng) * 1.1, base + 3.0 + i * 0.125, .5 + .05 * i, pan=-.5 + i * .14)
        # podwojone hi-haty w 32-kach co drugi takt
        if b % 2 == 1:
            for st in range(32):
                s.put(hat(rng), base + 2.0 + st * 0.0625, .15, pan=.4 if st % 2 else -.4)
    out = s.render(ir("hall_st"), wet=0.18)
    out = d.saturate(out, 1.5)
    return d.circ_filter(out, lambda t: d.compress(t, -15.0, 3.0, 6.0, 120.0))


# ------------------------------------------------------------------ warianty segmentów (MUSIC_PLAN.md E2)
# Ta sama siatka, progresja i RYTM co stem bazowy — inna tylko barwa i melodia (po odsłuchu 1.7.580: warianty z innym
# groove'em brzmiały jak zmiana tempa). Runtime gra wszystkie warianty razem i przełącza całą muzykę naraz („sekcja”)
# na początku pętli, co 2–4 pętle. Osobne funkcje zamiast parametrów: stemy bazowe zostają bit w bit (ten sam przebieg Rng).

def stem_silence_b(rng: Rng) -> np.ndarray:
    s = Stem()
    bar = 4
    # pad z noną zamiast oktawy, ciemniejszy; akordy zmieniają się na raz taktu jak w bazie
    for b in range(BARS):
        ch = [mtof(m) for m in CHORDS[b]] + [mtof(CHORDS[b][0] + 14)]
        seg = T(bar + 1.2)
        pad = saw_pad(ch, seg, rng, cutoff=640.0, detune=12.0)
        pad *= d.env_adsr(seg, 1.6 * SPB / SR, 0.5, 0.8, 1.4 * SPB / SR)
        s.put(pad, b * bar, 0.48)
    L = LOOP_N / SR
    t = np.arange(LOOP_N) / SR
    f1 = round(36.708 * L) / L
    sub = (np.sin(TAU * f1 * t) + 0.3 * np.sin(TAU * 3 * f1 * t)) * (0.8 + 0.2 * np.cos(TAU * 2 * t / L))
    s.buf[:, :LOOP_N] += np.stack([sub, sub]) * 0.2
    # szklane akcenty w taktach nieparzystych, niżej
    for b, m in ((1, 69), (3, 76), (5, 65), (7, 73)):
        s.put(glass_ping(mtof(m), rng, 3.0) * 0.32, b * bar + 2.5, 1.0, pan=rng.uniform(-0.7, 0.7))
    out = s.render(ir("cave_st"), wet=0.42)
    return d.circ_filter(out, lambda t: d.compress(t, -22.0, 2.0, 30.0, 400.0))


def stem_tension_b(rng: Rng) -> np.ndarray:
    # rytm 1:1 jak baza (ósemki z tymi samymi akcentami, puls na 1 i 3, risery w taktach 4 i 8) — inna barwa:
    # ciemniejszy filtr, dłuższe wybrzmienie, melodia w taktach 1–4 zamiast 5–8
    s = Stem()
    off_sets = {0: (0, 12, 0, 7, 0, 12, 0, 10), 1: (0, 12, 0, 7, 0, 12, 0, 11),
                2: (0, 12, 0, 7, 0, 12, 0, 10), 3: (0, 12, 0, 7, 0, 12, 0, 10)}
    acc = (1.0, .55, .8, .55, .9, .55, .8, .6)
    for b in range(BARS):
        root = ROOTS[b]
        for i in range(8):
            f = mtof(root + off_sets[b % 4][i])
            phase = TAU * (b * 8 + i) / 64.0 + np.pi
            hi = 1500.0 + 600.0 * np.sin(phase) + (400.0 if i in (0, 4) else 0.0)
            note = pluck_bass(f, 0.46 * 60.0 / BPM * 2, rng, cut_hi=hi, cut_lo=220.0, q=2.2, tau=.13, sub=.55)
            s.put(note, b * 4 + i * 0.5, 0.55 * acc[i], pan=0.0)
        for beat in (0, 2):
            s.put(thump(.4, 78.0, 40.0, .05, .12), b * 4 + beat, 0.55)
    melody = {0: ((0, 69, 2.0), (2, 74, 2.0)), 1: ((0, 70, 2.0), (2, 77, 2.0)),
              2: ((0, 70, 2.0), (2, 74, 2.0)), 3: ((0, 69, 2.0), (2, 73, 2.0))}
    for b, notes in melody.items():
        for off, m, _ in notes:
            s.put(glass_ping(mtof(m), rng, 2.4) * 0.42, b * 4 + off, 1.0, pan=0.25 if m % 2 else -0.25)
    for b in (3, 7):
        r_ = riser(T(1.8), rng, 400.0, 5200.0) * 0.22
        s.put(r_, b * 4 + 2.2, 1.0)
    out = s.render(ir("plate_st"), wet=0.34)
    return d.circ_filter(out, lambda t: d.compress(t, -20.0, 2.5, 12.0, 200.0))


def stem_combat_b(rng: Rng) -> np.ndarray:
    # rytm 1:1 jak baza (stopa, werbel 2 i 4, szesnastkowe hi-haty, bas szesnastkowy, staby na synkopach) — inna barwa:
    # bas bez skoków o oktawę, staby niżej i ciemniej, hi-haty bez otwartych
    s = Stem()
    gate = ir("gate_st")
    for b in range(BARS):
        base = b * 4
        root = ROOTS[b]
        for pos, g in ((0, 1.0), (1.5, .8), (2.5, .9), (3.75, .5)):
            s.put(kick(rng) * 1.2, base + pos, g)
        for pos in (1.0, 3.0):
            sn = snare(rng)
            gated = d.reverb_stereo(np.stack([sn, sn]), gate, wet=1.0, dry=0.0, keep_len=False)
            env = d.env_pts(gated.shape[1], [(0, 1), (.20, 1), (.24, 0)])
            s.put(gated * env * 0.7, base + pos, 1.0)
            s.put(sn * 0.9, base + pos, 1.0)
        for st in range(16):
            beat = st * 0.25
            acc = 1.0 if st % 4 == 0 else (.62 if st % 2 == 0 else .38)
            s.put(hat(rng), base + beat, .3 * acc, pan=-.25 if st % 2 else .25)
        for st in range(16):
            note = pluck_bass(mtof(root), .20, rng, cut_hi=2000.0 + 400.0 * (st % 4 == 0), cut_lo=260.0, q=2.0, tau=.07, sub=.7)
            s.put(note, base + st * 0.25, 0.55 if st % 4 else 0.7)
        ch = [mtof(m) for m in CHORDS[b]]
        for pos in (0.75, 2.25):
            s.put(stab(ch, 0.34, rng, 2400.) * 0.9, base + pos, 0.55, pan=-0.15)
    out = s.render(ir("plate_st"), wet=0.2)
    out = d.saturate(out, 1.4)
    return d.circ_filter(out, lambda t: d.compress(t, -16.0, 3.0, 8.0, 120.0))


def stem_chase_b(rng: Rng) -> np.ndarray:
    # rytm 1:1 jak baza (arpeggio szesnastkowe, bas ósemkowy, tryton co 2 takty, crash, riser i tomy w tych samych miejscach)
    # — inna barwa: arpeggio innym konturem i ciemniejsze, bez dublowanych hi-hatów
    s = Stem()
    for b in range(BARS):
        base = b * 4
        root = ROOTS[b]
        ch = CHORDS[b]
        pattern = (0, 2, 1, 2, 0, 2, 1, 3)
        for st in range(16):
            m = ch[pattern[st % 8] % 3] + 24 + (12 if pattern[st % 8] == 3 else 0)
            n = sec(0.17)
            f = mtof(m)
            y = d.osc("saw", f, n) * .5 + d.osc("square", f * 0.997, n, pw=.35) * .5
            y = d.sweep(y, "lp", d.glide_exp(3800., 700., n, .06), 1.8) * d.env_perc(n, .002, .05)
            s.put(y, base + st * 0.25, .22, pan=.4 - .8 * (st % 4) / 3.0)
        for i in range(8):
            note = pluck_bass(mtof(root + 12), .22, rng, cut_hi=3000., cut_lo=450., q=2.6, tau=.05, sub=.15)
            s.put(d.saturate(note * 1.5, 3.0), base + i * 0.5, .28)
        if b % 2 == 0:
            tri = [mtof(root + 24), mtof(root + 30)]
            s.put(stab(tri, 0.5, rng, 3600.) * 1.1, base + 3.0, .36)
        if b in (0, 4):
            s.put(crash(rng), base, .3)
        if b in (3, 7):
            s.put(riser(T(1.7), rng, 500., 7000.) * .35, base + 2.2, 1.0)
            for i, f in enumerate((220., 196., 174., 155., 138., 123., 110., 98.)):
                s.put(tom(f, rng) * 1.1, base + 3.0 + i * 0.125, .5 + .05 * i, pan=.5 - i * .14)
    out = s.render(ir("hall_st"), wet=0.2)
    out = d.saturate(out, 1.4)
    return d.circ_filter(out, lambda t: d.compress(t, -15.0, 3.0, 6.0, 120.0))


# Kadencje końca starcia: jedno uderzenie na tonice d-moll i ogon (2–4 s). Z przedbiegiem CADENCE_PRE ciszy, żeby
# runtime mógł je uruchomić odrobinę wcześniej z przesunięciem (play(from)) i trafić w początek taktu co do bufora miksu.
CADENCE_PRE = 0.25

# Palety segmentów: klucz palety -> warianty każdej warstwy (cisza, napięcie, walka, pościg). Runtime szuka palety po
# map_id poziomu („z1_b1”), potem po strefie („z1”), na końcu „default”. Pierwszy wariant warstwy startuje frazę.
SEGMENTS = {
    "default": (("mus_silence", "mus_silence_b"), ("mus_tension", "mus_tension_b"),
                ("mus_combat", "mus_combat_b"), ("mus_chase", "mus_chase_b")),
    # boss 1.4: zaczyna od ciemniejszej sekcji B
    "z1_b1": (("mus_silence_b", "mus_silence"), ("mus_tension_b", "mus_tension"),
              ("mus_combat_b", "mus_combat"), ("mus_chase_b", "mus_chase")),
}
# Kadencja grana, gdy warstwa gaśnie (indeks = warstwa); "" = zwykłe wyciszenie
CADENCES = ("", "", "mus_combat_end", "mus_chase_end")


def build_cadences() -> None:
    rng = Rng(0xCAD0)
    pre = sec(CADENCE_PRE)
    # walka: stopa + snare z bramką + crash + niski akord Dm (D2 / D3 F3 A3) i długi ogon płyty
    n = sec(4.6)
    s = np.zeros((2, pre + n))
    def put(sig, at=0.0, g=1.0):
        sig = np.stack([sig, sig]) * 0.7071 if sig.ndim == 1 else sig
        k = pre + int(at * SR)
        m = min(sig.shape[1], s.shape[1] - k)
        s[:, k:k + m] += sig[:, :m] * g
    put(kick(rng, 1.3) * 1.3)
    sn = snare(rng)
    put(d.reverb_stereo(np.stack([sn, sn]), ir("gate_st"), wet=1.0, dry=0.6, keep_len=False), 0.0, 0.8)
    put(crash(rng, 3.0), 0.0, .45)
    ch = [mtof(m) for m in (50, 53, 57, 62)]
    seg = sec(3.6)
    put(saw_pad(ch, seg, rng, cutoff=1400.0) * d.env_adsr(seg, 0.004, 0.6, 0.45, 2.4), 0.0, 0.55)
    put(pluck_bass(mtof(38), 2.6, rng, cut_hi=1800.0, cut_lo=180.0, q=2.0, tau=.5, sub=.9), 0.0, 0.8)
    put(thump(1.4, 70.0, 32.0, .2, .6, attack=.002), 0.0, 0.9)
    x = d.reverb_stereo(s, ir("plate_st"), wet=0.32, dry=1.0)
    x = d.saturate(x, 1.3)
    asset("mus_combat_end", "music/mus_combat_end")
    finalize("mus_combat_end", x, lufs=-19.0, fade_out_ms=600, fade_in_ms=0.0, trim=True)

    # pościg: crash + uderzenie sub, klaster piłowy (tryton) zjeżdża glissandem na czystą kwintę D–A
    n = sec(4.2)
    s = np.zeros((2, pre + n))
    put(crash(rng, 3.2), 0.0, .5)
    put(thump(1.6, 95.0, 30.0, .22, .7, attack=.002) * 1.3)
    put(kick(rng, 1.4) * 1.2)
    m_ = sec(3.4)
    cl = np.zeros(m_)
    for f0, f1 in ((mtof(56), mtof(57)), (mtof(62), mtof(62)), (mtof(68), mtof(69)), (mtof(50), mtof(50))):
        g_ = d.glide_exp(f0, f1, m_, 0.35)
        cl += d.osc("saw", g_, m_) * .5 + d.osc("saw", g_ * 1.006, m_) * .5
    cl = d.sweep(cl, "lp", d.glide_exp(5200., 700., m_, .9), 1.3) * d.env_adsr(m_, 0.003, 0.5, 0.5, 2.2)
    put(cl, 0.0, 0.35)
    x = d.reverb_stereo(s, ir("hall_st"), wet=0.38, dry=1.0)
    x = d.saturate(x, 1.5)
    asset("mus_chase_end", "music/mus_chase_end")
    finalize("mus_chase_end", x, lufs=-16.0, fade_out_ms=600, fade_in_ms=0.0, trim=True)


# ------------------------------------------------------------------ stingery

def build_stingers() -> None:
    rng = Rng(0x5710)
    # napięcie: szum narastający + dysonansowy metaliczny jęk + miękki sub na końcu
    n = sec(2.4)
    t = np.arange(n) / SR
    sw = d.sweep(d.colored(n, rng, 0.8), "bp", np.geomspace(250.0, 5200.0, n), 1.2) * d.env_pts(n, [(0, 0), (1.6, 1), (2.4, 0)]) ** 1.5
    mod = d.modal([110.0, 148.0, 271.0, 389.0, 607.0], [1.0, .8, .5, .4, .25], [2.0, 1.8, 1.4, 1.0, .7], n, rng, .003)
    mod = mod * d.env_pts(n, [(0, 0), (1.3, 1), (2.4, 0)])
    sub = thump(1.0, 62.0, 34.0, .2, .3, attack=.01) * d.env_pts(sec(1.0), [(0, 0), (.02, 1), (1.0, 0)])
    x = d.mix([(sw, .8), (mod, .6), (sub, .8, 1.5)], n)
    x = d.reverb_stereo(np.stack([x, x]), ir("hall_st"), wet=.5, dry=.7)
    asset("sting_tension", "music/sting_tension")
    finalize("sting_tension", x, lufs=-17.0, fade_out_ms=300)

    # pościg: uderzenie sub + metalowy crash + dysonansowy klaster piłowy (tritonus/półton)
    n = sec(2.6)
    sub = thump(1.5, 95.0, 30.0, .22, .45, attack=.002) * 1.4
    cr = d.filt(d.white(n, rng), "hp", 2500.0, order=2) * d.env_perc(n, .001, .4)
    notes = [mtof(m) for m in (50, 56, 57, 62)]
    cl = np.zeros(n)
    for f in notes:
        cl += d.osc("saw", f, n) * .5 + d.osc("saw", f * 1.01, n) * .5
    cl = d.sweep(cl, "lp", d.glide_exp(4200., 500., n, .5), 1.4) * d.env_perc(n, .004, .55)
    swell = riser(sec(.5), rng, 300., 8000.) * .5
    x = d.mix([(sub, 1.0), (cr, .5), (cl, .7), (swell, .5)], n)
    x = d.saturate(x, 2.0)
    x = d.reverb_stereo(np.stack([x, x]), ir("hall_st"), wet=.4, dry=.8)
    asset("sting_chase", "music/sting_chase")
    finalize("sting_chase", x, lufs=-10.0, fade_out_ms=300)


# ------------------------------------------------------------------ motyw Stalkera i sygnały zagrożeń (MUSIC_PLAN.md E1)
# Motyw: D3 – F3 – E3 … A2, „smyczek” FM z taśmą. Od 1.7.580 w d-moll jak stemy (wersja z trytonem E♭ / A♭ brzmiała jak obcy utwór obok).
# Dwie pętle na tej samej siatce co stemy (20 s, 96 BPM), runtime przenika je wg odległości Stalkera:
#   mus_stalker_far  — motyw co 4 takty, ciemny, w dużym pogłosie (gdzieś poluje)
#   mus_stalker_near — motyw co 2 takty, jaśniejszy, z pulsem sub i klastrem (jest blisko)
MOTIF = ((50, 0.0, 1.4), (53, 1.5, 0.5), (52, 2.0, 1.9), (45, 4.0, 3.2))   # (MIDI, beat, długość w beatach)


def bowed(f: float, dur: float, rng: Rng, bright: float = 1.0) -> np.ndarray:
    """Ton „smyczkowy” FM: wolne natarcie, wibrato opóźnione, indeks modulacji rośnie z natarciem (jak nacisk smyczka)."""
    n = sec(dur)
    fr = d.vibrato(f, n, 4.6, 14.0, rng.uniform(0, TAU)) * d.env_pts(n, [(0, 0.996), (0.25, 1.0), (dur, 1.0)])
    idx = (0.6 + 1.6 * bright) * d.env_pts(n, [(0, 0.1), (min(0.35, dur * 0.4), 1.0), (dur, 0.7)])
    y = d.fm(fr, n, ratio=1.0, index=idx, fb=0.0) * 0.6 + d.fm(fr * 0.5, n, ratio=2.0, index=idx * 0.5) * 0.4
    y = d.lp(y, 900.0 + 2600.0 * bright, 0.9)
    return y * d.env_adsr(n, min(0.22, dur * 0.3), 0.2, 0.8, min(0.5, dur * 0.35))


def motif_into(s: "Stem", beat0: float, rng: Rng, bright: float, gain: float) -> None:
    for m, b, dur in MOTIF:
        s.put(bowed(mtof(m), dur * 60.0 / BPM + 0.3, rng, bright), beat0 + b, gain, pan=rng.uniform(-0.25, 0.25))


def stem_stalker_far(rng: Rng) -> np.ndarray:
    s = Stem()
    for bar in (0, 4):
        motif_into(s, bar * 4, rng, 0.15, 0.55)
    # cichy szum taśmy pod spodem — „coś jest w eterze”
    L = LOOP_N + TAIL
    s.buf += np.stack([d.lp(d.pink(L, rng), 700.0), d.lp(d.pink(L, rng), 700.0)]) * 0.02
    out = s.render(ir("cave_st"), wet=0.6)
    out = d.tape(out, wow_hz=round(0.5 * LOOP_N / SR) / (LOOP_N / SR), wow_depth=0.004, sat=1.1)
    return d.circ_filter(out, lambda t: d.lp(t, 1500.0, order=2))


def stem_stalker_near(rng: Rng) -> np.ndarray:
    s = Stem()
    for bar in (0, 2, 4, 6):
        motif_into(s, bar * 4, rng, 0.6 if bar % 4 == 0 else 0.45, 0.7)
    # puls „serca” sub na 1 i 1,5 każdego taktu (podwójne uderzenie) — tempo stemów, żeby siedział w rytmie
    for bar in range(BARS):
        for b, g in ((0.0, 1.0), (0.5, 0.7)):
            s.put(thump(0.45, 70.0, 38.0, 0.05, 0.16, attack=0.004), bar * 4 + b, 0.55 * g)
    # klaster tryton + półton, wchodzi i gaśnie z każdym motywem
    for bar in (0, 2, 4, 6):
        n = T(8.0)
        cl = sum(d.osc("saw", mtof(m), n, phase0=rng.uniform(0, 1)) for m in (44, 50, 51)) / 3.0
        cl = d.lp(cl, 520.0, 1.2) * d.env_pts(n, [(0, 0), (n / SR * 0.4, 1), (n / SR, 0)])
        s.put(cl, bar * 4, 0.16)
    out = s.render(ir("cave_st"), wet=0.35)
    out = d.tape(out, wow_hz=round(0.5 * LOOP_N / SR) / (LOOP_N / SR), wow_depth=0.003, sat=1.25)
    return d.circ_filter(out, lambda t: d.compress(t, -20.0, 2.5, 20.0, 300.0))


def build_cues() -> None:
    rng = Rng(0xE11E)
    # elita: niska „dęta” kwinta FM (A–E–A, w d-moll) narasta do metalowego uderzenia — ktoś większy niż zwykle cię zauważył
    n = sec(3.2)
    sw = d.env_pts(n, [(0, 0), (1.1, 1), (1.25, 0.8), (3.2, 0)])
    br = sum(d.fm(mtof(m), n, ratio=1.0, index=2.2 * sw + 0.3) for m in (33, 40, 45)) / 3.0
    br = d.sweep(br, "lp", np.geomspace(300.0, 2600.0, n) * (0.4 + 0.6 * sw), 1.1) * sw
    hit = d.modal([97.0, 141.0, 233.0, 367.0, 512.0], [1.0, .7, .5, .35, .2], [2.4, 2.0, 1.5, 1.0, .7], sec(2.2), rng, .004)
    x = d.mix([(br, 0.9), (thump(1.2, 80.0, 34.0, .12, .5, attack=.003), 0.9, 1.15), (hit, 0.5, 1.15)], n)
    x = d.tape(d.saturate(x, 1.5), wow_hz=0.7, wow_depth=0.003, sat=1.1)
    x = d.reverb_stereo(np.stack([x, x]), ir("hall_st"), wet=0.45, dry=0.8)
    asset("cue_elite", "music/cue_elite")
    finalize("cue_elite", x, lufs=-16.0, fade_out_ms=400)

    # horda: przyspieszające tomy (alarm się niesie), syrena z rozstrojonych pił w górę, crash na końcu
    n = sec(4.2)
    x = np.zeros(n)
    t, gap = 0.0, 0.42
    while t < 2.9:
        x = d.mix([(x, 1.0), (tom(rng.uniform(70.0, 95.0), rng), 0.55 + 0.45 * t / 2.9, t)], n)
        t += gap
        gap = max(0.09, gap * 0.82)
    sir = (d.osc("saw", d.glide(180.0, 520.0, n, 1.6), n) + d.osc("saw", d.glide(186.0, 540.0, n, 1.6), n)) * 0.5
    sir = d.lp(sir, 1800.0, 1.4) * d.env_pts(n, [(0, 0), (2.6, 0.8), (3.0, 1), (4.2, 0)])
    x = d.mix([(x, 1.0), (sir, 0.35), (crash(rng, 1.4), 0.5, 3.0), (thump(0.8, 110.0, 32.0, .1, .35), 0.9, 3.0)], n)
    x = d.reverb_stereo(np.stack([x, x]), ir("hall_st"), wet=0.35, dry=0.85)
    asset("cue_horde", "music/cue_horde")
    finalize("cue_horde", x, lufs=-14.0, fade_out_ms=400)


def build_music() -> None:
    group("music")
    rng = Rng(0x2200)
    specs = (("mus_silence", stem_silence, -26.0), ("mus_tension", stem_tension, -25.0),
             ("mus_combat", stem_combat, -21.0), ("mus_chase", stem_chase, -22.0))
    # E2: warianty segmentów — ta sama głośność co stem bazowy, żeby przenikanie na granicy frazy nie zmieniało poziomu
    variants = (("mus_silence_b", stem_silence_b, -26.0), ("mus_tension_b", stem_tension_b, -25.0),
                ("mus_combat_b", stem_combat_b, -21.0), ("mus_chase_b", stem_chase_b, -22.0))
    for key, fn, target in specs + (("mus_stalker_far", stem_stalker_far, -31.0), ("mus_stalker_near", stem_stalker_near, -25.0)) + variants:
        asset(key, "music/" + key, loop=True)
        x = fn(rng.fork(zlib.crc32(key.encode()) & 0xFFFF))
        assert x.shape[-1] == LOOP_N, (key, x.shape)
        finalize(key, x, loop=True, lufs=target)
    build_stingers()
    build_cues()
    build_cadences()
