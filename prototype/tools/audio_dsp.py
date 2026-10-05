"""
audio_dsp.py — rdzeń syntezy i obróbki dźwięku dla bake_audio.py (numpy + scipy).

Wersja 2. Poprzedni rdzeń (stdlib) miał błędy fundamentalne, wykryte przez
tools/audio_audit.py i test_audio_dsp.py:
  * osc() zwiększał fazę o `f` próbek na krok zamiast f·len(tabeli)/SR —
    „sinus" przy całkowitych Hz dawał ciszę, reszta oscylatorów aliasowany szum
    (wysokość dźwięku nie istniała: bas, kick, pady, akordy, serce, brzęczyki UI);
  * fm2() podawał fazę w cyklach do sin() jak w radianach (piła z DC, nie FM);
  * svf() miał punkt -3 dB ~3× za nisko i +5 dB wzmocnienia w paśmie przepustowym;
  * stereoize() = opóźnienie Haas 9-30 ms na KAŻDYM dźwięku → filtr grzebieniowy,
    do -10 dB przy sumowaniu do mono.

Konwencje:
  * SR = 48000, bufor = np.ndarray float64, mono (n,) albo stereo (2, n).
  * Generatory zwracają nominalnie ±1 (szum: odchylenie std 0.4). Poziomy
    ustala dopiero finalize() w bake_audio.py.
  * Wszystko jest DETERMINISTYCZNE: losowość tylko z Rng(seed). Ten sam seed =
    ten sam plik (kontrakt bake'u).
  * Pętle robimy KOŁOWO (circular()): sygnał okresowy → filtr → środkowa kopia.
    Szew jest idealny z konstrukcji, bez crossfade'u i bez dziury w energii.
"""

from __future__ import annotations

import math
import wave

import numpy as np
from scipy import ndimage
from scipy import signal as sg

SR = 48000
TAU = 2.0 * math.pi
NYQ_SAFE = 0.45 * SR


def ms(v: float) -> int:
    return int(round(SR * v / 1000.0))


def sec(v: float) -> int:
    return int(round(SR * v))


def db_to_lin(db: float) -> float:
    return 10.0 ** (db / 20.0)


def lin_to_db(x: float) -> float:
    return 20.0 * math.log10(max(float(x), 1e-12))


# ------------------------------------------------------------------ rng

class Rng:
    """PCG64 z jawnym seedem. fork(tag) daje niezależny, deterministyczny strumień."""

    def __init__(self, seed: int = 0x9E3779B97F4A7C15):
        self.seed = int(seed) & 0xFFFFFFFFFFFFFFFF
        self.g = np.random.Generator(np.random.PCG64(self.seed))

    def fork(self, tag: int) -> "Rng":
        return Rng((self.seed * 0x9E3779B97F4A7C15 + int(tag) * 0xBF58476D1CE4E5B9 + 0x94D049BB133111EB)
                   & 0xFFFFFFFFFFFFFFFF)

    def uniform(self, lo=0.0, hi=1.0, size=None):
        return self.g.uniform(lo, hi, size)

    def normal(self, mu=0.0, sd=1.0, size=None):
        return self.g.normal(mu, sd, size)

    def bipolar(self, amp=1.0):
        return float(self.g.uniform(-amp, amp))

    def integers(self, lo, hi, size=None):
        return self.g.integers(lo, hi, size)

    def chance(self, p: float) -> bool:
        return bool(self.g.uniform() < p)

    def choice(self, seq):
        return seq[int(self.g.integers(0, len(seq)))]


# ------------------------------------------------------------------ pomocnicze

def _arr(v, n: int) -> np.ndarray:
    """Skalar albo tablica → tablica długości n (tablica krótsza: dopełniana ostatnią wartością)."""
    a = np.asarray(v, dtype=np.float64)
    if a.ndim == 0:
        return np.full(n, float(a))
    if len(a) == n:
        return a
    if len(a) > n:
        return a[:n]
    return np.concatenate([a, np.full(n - len(a), a[-1])])


def glide(f0: float, f1: float, n: int, curve: float = 1.0) -> np.ndarray:
    """Przebieg częstotliwości f0→f1. curve=1 liniowo (w Hz); curve<1 szybki start (kick)."""
    t = np.linspace(0.0, 1.0, n, endpoint=False) ** curve
    return f0 + (f1 - f0) * t


def glide_exp(f0: float, f1: float, n: int, tau: float) -> np.ndarray:
    """Wykładnicze opadanie f0→f1 ze stałą czasową tau [s] (naturalne dla kicka/toma)."""
    t = np.arange(n) / SR
    return f1 + (f0 - f1) * np.exp(-t / tau)


def pad_to(a: np.ndarray, n: int) -> np.ndarray:
    if a.shape[-1] >= n:
        return a[..., :n]
    pw = [(0, 0)] * (a.ndim - 1) + [(0, n - a.shape[-1])]
    return np.pad(a, pw)


def at(buf: np.ndarray, start: float) -> np.ndarray:
    """Opóźnia bufor o `start` SEKUND (zawsze sekundy — jedna jednostka w całym projekcie)."""
    d = int(round(start * SR))
    if d <= 0:
        return buf
    pw = [(0, 0)] * (buf.ndim - 1) + [(d, 0)]
    return np.pad(buf, pw)


def mix(parts, n: int | None = None) -> np.ndarray:
    """parts: [(bufor, wzmocnienie)] albo [(bufor, wzmocnienie, start_s)]. Mono i stereo
    mogą się mieszać (mono jest kopiowane na oba kanały)."""
    items = []
    for p in parts:
        b, g = p[0], p[1]
        if len(p) > 2:
            b = at(b, p[2])
        items.append((b, g))
    length = n if n is not None else max(b.shape[-1] for b, _ in items)
    stereo = any(b.ndim == 2 for b, _ in items)
    out = np.zeros((2, length) if stereo else length)
    for b, g in items:
        b = pad_to(b, length)
        if stereo and b.ndim == 1:
            b = np.stack([b, b])
        out += b * g
    return out


def plus(*bufs) -> np.ndarray:
    """Suma buforów o różnych długościach (krótszy dopełniany zerami)."""
    return mix([(b, 1.0) for b in bufs])


def to_mono(x: np.ndarray) -> np.ndarray:
    return x if x.ndim == 1 else x.mean(axis=0)


def pan(x: np.ndarray, p: float) -> np.ndarray:
    """Panorama stałej mocy; p ∈ [-1, 1]."""
    th = (p + 1.0) * math.pi / 4.0
    return np.stack([x * math.cos(th), x * math.sin(th)])


# ------------------------------------------------------------------ szum

def white(n: int, rng: Rng) -> np.ndarray:
    return rng.g.standard_normal(n) * 0.4


def colored(n: int, rng: Rng, slope: float) -> np.ndarray:
    """Szum o widmie mocy ~ 1/f^slope (0 = biały, 1 = różowy, 2 = brązowy).
    Kształtowanie w dziedzinie FFT daje szum DOKŁADNIE okresowy w n próbkach."""
    x = rng.g.standard_normal(n)
    X = np.fft.rfft(x)
    k = np.arange(len(X), dtype=np.float64)
    k[0] = 1.0
    X *= k ** (-slope / 2.0)
    X[0] = 0.0
    y = np.fft.irfft(X, n)
    return y / (np.std(y) + 1e-12) * 0.4


def pink(n: int, rng: Rng) -> np.ndarray:
    return colored(n, rng, 1.0)


def brown(n: int, rng: Rng) -> np.ndarray:
    return colored(n, rng, 2.0)


# ------------------------------------------------------------------ oscylatory

def _phase(f: np.ndarray, phase0: float = 0.0) -> np.ndarray:
    """Faza w CYKLACH; pierwsza próbka = phase0."""
    c = np.cumsum(f) / SR
    return phase0 + np.concatenate([[0.0], c[:-1]])


def _blep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    y = np.zeros_like(t)
    m = t < dt
    if m.any():
        x = t[m] / dt[m]
        y[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    if m.any():
        x = (t[m] - 1.0) / dt[m]
        y[m] = x * x + x + x + 1.0
    return y


def osc(shape: str, f, n: int, phase0: float = 0.0, pw: float = 0.5) -> np.ndarray:
    """Oscylator. f: Hz (skalar albo tablica długości n → glissando/wibrato).
    saw/square: PolyBLEP (bez aliasingu słyszalnego); sine: dokładny; tri: złożony z piły."""
    f = _arr(f, n)
    ph = _phase(f, phase0)
    if shape == "sine":
        return np.sin(TAU * ph)
    p = ph % 1.0
    dt = np.clip(f / SR, 1e-9, 0.49)
    if shape == "saw":
        return 2.0 * p - 1.0 - _blep(p, dt)
    if shape == "square":
        y = np.where(p < pw, 1.0, -1.0)
        return y + _blep(p, dt) - _blep((p + 1.0 - pw) % 1.0, dt)
    if shape == "tri":
        return 2.0 * np.abs(2.0 * p - 1.0) - 1.0
    raise ValueError("nieznany kształt fali: %r" % shape)


def vibrato(f0: float, n: int, hz: float, cents: float, phase0: float = 0.0) -> np.ndarray:
    """Przebieg częstotliwości z wibrato (do osc/fm)."""
    t = np.arange(n) / SR
    return f0 * 2.0 ** ((cents / 1200.0) * np.sin(TAU * hz * t + phase0))


def fm(f, n: int, ratio: float = 2.0, index=3.0, phase0: float = 0.0, fb: float = 0.0) -> np.ndarray:
    """2-operatorowy FM (modulacja fazy), jak DX7. index: skalar albo obwiednia."""
    f = _arr(f, n)
    idx = _arr(index, n)
    pc = _phase(f, phase0)
    pm = _phase(f * ratio, 0.0)
    return np.sin(TAU * pc + idx * np.sin(TAU * pm))


def modal(freqs, amps, t60s, n: int, rng: Rng | None = None, jitter: float = 0.0,
          strike_lp: float = 0.0) -> np.ndarray:
    """Synteza modalna: suma tłumionych sinusów (rezonanse metalu, szkła, dzwonu).
    t60s — czas zaniku o 60 dB dla każdego modu [s]. To jest właściwy model uderzenia
    w obiekt rezonansowy — FM tylko go udaje."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i, (f, a, t60) in enumerate(zip(freqs, amps, t60s)):
        if jitter and rng is not None:
            f = f * (1.0 + rng.bipolar(jitter))
        if f >= NYQ_SAFE:
            continue
        ph = rng.uniform(0, TAU) if rng is not None else 0.0
        out += a * np.sin(TAU * f * t + ph) * np.exp(-6.9078 * t / max(t60, 1e-3))
    return out


# ------------------------------------------------------------------ obwiednie

def env_exp(n: int, tau: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (tau * SR))


def env_perc(n: int, attack: float = 0.002, decay: float = 0.12) -> np.ndarray:
    """Narastanie liniowe (attack) → opadanie wykładnicze (stała decay)."""
    na = max(1, int(attack * SR))
    t = np.arange(n)
    out = np.exp(-(t - na) / (decay * SR))
    out[:na] = t[:na] / na
    return out


def env_adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    na, nd, nr = max(1, int(a * SR)), max(1, int(d * SR)), max(1, int(r * SR))
    nr = min(nr, n)
    hold = max(0, n - na - nd - nr)
    parts = [np.linspace(0.0, 1.0, na, endpoint=False),
             np.linspace(1.0, s, nd, endpoint=False),
             np.full(hold, s),
             np.linspace(s, 0.0, nr)]
    return pad_to(np.concatenate(parts), n)


def env_pts(n: int, pts) -> np.ndarray:
    """Obwiednia z punktów [(czas_s, amp), ...], interpolacja liniowa."""
    ts = np.array([p[0] for p in pts]) * SR
    vs = np.array([p[1] for p in pts])
    return np.interp(np.arange(n), ts, vs)


def env_curve(n: int, a: float, b: float, power: float = 2.0) -> np.ndarray:
    """a→b po krzywej t^power (power>1: powolny start, szybki koniec)."""
    return a + (b - a) * np.linspace(0.0, 1.0, n) ** power


def lfo(n: int, hz: float, depth: float = 1.0, phase: float = 0.0, floor: float = 0.0) -> np.ndarray:
    """LFO sinusoidalne o przebiegu w [floor, 1]; hz powinno dawać całkowitą liczbę
    cykli w pętli, jeśli sygnał ma być zapętlony."""
    t = np.arange(n) / SR
    s = 0.5 + 0.5 * np.sin(TAU * hz * t + phase)
    return floor + (1.0 - floor) * (1.0 - depth + depth * s)


# ------------------------------------------------------------------ filtry

def _rbj(kind: str, f: float, q: float, gain_db: float = 0.0) -> np.ndarray:
    f = min(max(f, 10.0), NYQ_SAFE)
    w0 = TAU * f / SR
    cw, sw = math.cos(w0), math.sin(w0)
    al = sw / (2.0 * max(q, 0.05))
    A = 10.0 ** (gain_db / 40.0)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == "bp":      # stałe wzmocnienie szczytowe 0 dB
        b = [al, 0.0, -al]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == "notch":
        b = [1.0, -2 * cw, 1.0]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == "peak":
        b = [1 + al * A, -2 * cw, 1 - al * A]; a = [1 + al / A, -2 * cw, 1 - al / A]
    elif kind in ("lowshelf", "highshelf"):
        sq = 2.0 * math.sqrt(A) * al
        if kind == "lowshelf":
            b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw),
                 A * ((A + 1) - (A - 1) * cw - sq)]
            a = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw),
                 (A + 1) + (A - 1) * cw - sq]
        else:
            b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw),
                 A * ((A + 1) + (A - 1) * cw - sq)]
            a = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw),
                 (A + 1) - (A - 1) * cw - sq]
    else:
        raise ValueError(kind)
    a0 = a[0]
    return np.array([[b[0] / a0, b[1] / a0, b[2] / a0, 1.0, a[1] / a0, a[2] / a0]])


def filt(x: np.ndarray, kind: str, f: float, q: float = 0.7071, gain_db: float = 0.0,
         order: int = 2) -> np.ndarray:
    """Filtr stały. lp/hp rzędu >2 = Butterworth (q ignorowane); reszta: biquad RBJ."""
    if kind in ("lp", "hp") and order > 2:
        sos = sg.butter(order, min(f, NYQ_SAFE), btype="low" if kind == "lp" else "high",
                        fs=SR, output="sos")
    else:
        sos = _rbj(kind, f, q, gain_db)
    return sg.sosfilt(sos, x, axis=-1)


def lp(x, f, q=0.7071, order=2): return filt(x, "lp", f, q, order=order)
def hp(x, f, q=0.7071, order=2): return filt(x, "hp", f, q, order=order)
def bp(x, f, q=1.0): return filt(x, "bp", f, q)


def sweep(x: np.ndarray, kind: str, f, q: float = 0.7071, block: int = 48) -> np.ndarray:
    """Filtr z przestrajaną częstotliwością odcięcia (f: tablica Hz długości n).
    Przetwarzanie blokowe z przenoszeniem stanu; q może być skalarem."""
    n = x.shape[-1]
    f = _arr(f, n)
    out = np.zeros_like(x)
    zi = None
    for s in range(0, n, block):
        e = min(s + block, n)
        sos = _rbj(kind, float(f[(s + e) // 2]), q)
        if zi is None:
            zi = np.zeros((1, 2) if x.ndim == 1 else (1, x.shape[0], 2))
        out[..., s:e], zi = sg.sosfilt(sos, x[..., s:e], axis=-1, zi=zi)
    return out


def dc_block(x: np.ndarray, fc: float = 18.0) -> np.ndarray:
    return filt(x, "hp", fc, 0.7071)


def formant(x: np.ndarray, formants, bw_q: float = 8.0) -> np.ndarray:
    """Bank rezonatorów pasmowych [(f, amp), ...] — barwa „ustna/krtaniowa" (growl, krzyk)."""
    out = np.zeros_like(x)
    for f, a in formants:
        out += a * filt(x, "bp", f, bw_q)
    return out


# ------------------------------------------------------------------ nieliniowość / dynamika

def saturate(x: np.ndarray, drive: float = 2.0, bias: float = 0.0, os: int = 4) -> np.ndarray:
    """tanh z nadpróbkowaniem (bez aliasingu harmonicznych). Jednostkowe wejście → ~jednostkowe
    wyjście. bias>0 dodaje parzyste harmoniczne (ciepło lamp/taśmy)."""
    if drive <= 0.0:
        return x
    up = sg.resample_poly(x, os, 1, axis=-1)
    y = np.tanh(drive * up + bias) - math.tanh(bias)
    y = y / math.tanh(drive)
    out = sg.resample_poly(y, 1, os, axis=-1)
    return pad_to(out, x.shape[-1]) if bias == 0 else dc_block(pad_to(out, x.shape[-1]))


def fold(x: np.ndarray, amount: float) -> np.ndarray:
    """Wavefolder — metaliczna, „elektroniczna" agresja (mało użyteczny bez oversamplingu)."""
    up = sg.resample_poly(x, 4, 1, axis=-1)
    y = np.sin(up * (1.0 + amount))
    return pad_to(sg.resample_poly(y, 1, 4, axis=-1), x.shape[-1])


def bitcrush(x: np.ndarray, bits: int = 8, hold: int = 1) -> np.ndarray:
    q = 2.0 ** (bits - 1)
    y = np.round(x * q) / q
    if hold > 1:
        y = np.repeat(y[::hold], hold)[:len(x)]
    return y


def tape(x: np.ndarray, wow_hz: float = 0.6, wow_depth: float = 0.0035, sat: float = 1.2,
         hiss: float = 0.0, rng: Rng | None = None) -> np.ndarray:
    """Taśma: wow/flutter (modulacja czasu odczytu, średnia prędkość = 1) + miękka saturacja
    + opcjonalny szum. Odczyt kołowy → pętla pozostaje zamknięta, jeśli wow_hz daje całkowitą
    liczbę cykli w buforze."""
    n = x.shape[-1]
    t = np.arange(n) / SR
    mod = (wow_depth * np.sin(TAU * wow_hz * t) + wow_depth * 0.4 * np.sin(TAU * wow_hz * 6.7 * t + 1.3))
    # przesunięcie czasu = całka z modulacji prędkości
    shift = np.cumsum(mod) / 1.0 - np.mean(np.cumsum(mod))
    pos = (np.arange(n) + shift) % n
    i0 = pos.astype(np.int64)
    fr = pos - i0
    if x.ndim == 1:
        y = x[i0] * (1.0 - fr) + x[(i0 + 1) % n] * fr
    else:
        y = np.stack([c[i0] * (1.0 - fr) + c[(i0 + 1) % n] * fr for c in x])
    if hiss and rng is not None:
        y = y + (white(n, rng) if y.ndim == 1 else np.stack([white(n, rng), white(n, rng)])) * hiss
    return saturate(y, sat) if sat else y


def compress(x: np.ndarray, thresh_db: float = -18.0, ratio: float = 3.0, attack_ms: float = 8.0,
             release_ms: float = 120.0, makeup_db: float = 0.0, block: int = 32) -> np.ndarray:
    """Kompresor feed-forward (detektor szczytów w blokach, wygładzanie attack/release)."""
    mono = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=0)
    n = len(mono)
    nb = (n + block - 1) // block
    lvl = np.pad(mono, (0, nb * block - n)).reshape(nb, block).max(axis=1)
    lvl_db = 20.0 * np.log10(np.maximum(lvl, 1e-6))
    over = np.maximum(lvl_db - thresh_db, 0.0)
    target = -over * (1.0 - 1.0 / ratio)             # redukcja docelowa [dB] (≤ 0)
    ca = math.exp(-block / (SR * attack_ms / 1000.0))
    cr = math.exp(-block / (SR * release_ms / 1000.0))
    g = np.zeros(nb)
    cur = 0.0
    for i in range(nb):
        c = ca if target[i] < cur else cr
        cur = c * cur + (1.0 - c) * target[i]
        g[i] = cur
    gs = np.interp(np.arange(n), (np.arange(nb) + 0.5) * block, g)
    return x * 10.0 ** ((gs + makeup_db) / 20.0)


def limiter(x: np.ndarray, ceiling_db: float = -1.5, lookahead_ms: float = 2.0,
            release_ms: float = 60.0) -> np.ndarray:
    """Limiter z podglądem (min-filter + wygładzanie); gwarantuje szczyt ≤ ceiling."""
    c = db_to_lin(ceiling_db)
    pk = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=0)
    g = np.minimum(1.0, c / np.maximum(pk, 1e-9))
    la = max(2, ms(lookahead_ms))
    gmin = ndimage.minimum_filter1d(g, size=la * 2, mode="nearest")
    gm = ndimage.uniform_filter1d(gmin, size=la * 2, mode="nearest")
    # powolne zwalnianie: max(g, wygładzone) w kierunku do przodu
    rel = math.exp(-1.0 / (SR * release_ms / 1000.0))
    out = np.empty_like(gm)
    cur = 1.0
    # przejście blokowe (co 16 próbek) — wystarczy dla wygładzenia release
    step = 16
    for i in range(0, len(gm), step):
        tgt = gm[i:i + step].min()
        cur = tgt if tgt < cur else rel ** step * cur + (1 - rel ** step) * tgt
        out[i:i + step] = cur
    out = np.minimum(out, gm)       # nigdy powyżej wymaganego tłumienia
    return x * out


def transient_shape(x: np.ndarray, attack_gain_db: float = 6.0, sustain_gain_db: float = 0.0,
                    fast_ms: float = 1.0, slow_ms: float = 30.0) -> np.ndarray:
    """Podbicie/stłumienie transjentu (różnica obwiedni szybkiej i wolnej)."""
    a = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=0)
    fast = ndimage.uniform_filter1d(a, max(1, ms(fast_ms)))
    slow = ndimage.uniform_filter1d(a, max(2, ms(slow_ms)))
    tr = np.clip((fast - slow) / (slow + 1e-4), 0.0, 4.0) / 4.0
    g = db_to_lin(sustain_gain_db) * (1.0 + tr * (db_to_lin(attack_gain_db) - 1.0))
    return x * g


# ------------------------------------------------------------------ przestrzeń

def _ir_band_noise(L: int, t60: float, rng: Rng) -> np.ndarray:
    t = np.arange(L) / SR
    return rng.g.standard_normal(L) * np.exp(-6.9078 * t / max(t60, 0.02))


def make_ir(rt60: float, rng: Rng, size: float = 1.0, damping: float = 0.5, pre_ms: float = 6.0,
            er_gain: float = 0.8, bright: float = 1.0, stereo: bool = True,
            max_len_s: float | None = None) -> np.ndarray:
    """Syntetyczna odpowiedź impulsowa pomieszczenia.
      rt60    — czas pogłosu [s] w średnich pasmach
      size    — skala wczesnych odbić i narastania gęstości (0.3 = szafa, 1 = sala, 3 = hala)
      damping — 0..1, im więcej tym szybciej zanikają wysokie tony (miękkie ściany/las)
      bright  — mnożnik górnych pasm
    Koniec IR jest wygaszony (okno), energia znormalizowana do 1 → mix wet/dry przewidywalny."""
    L = int(min(rt60 * 1.4 + 0.12, max_len_s or 6.0) * SR)
    t = np.arange(L) / SR
    bands = ((60, 250, 1.25), (250, 1000, 1.0), (1000, 3500, 0.8 - 0.45 * damping),
             (3500, 8000, 0.55 - 0.45 * damping), (8000, 20000, 0.35 - 0.3 * damping))
    chans = 2 if stereo else 1
    irs = []
    for c in range(chans):
        r = rng.fork(c + 1)
        tail = np.zeros(L)
        for lo, hi, mult in bands:
            hi_c = min(hi, NYQ_SAFE)
            sos = sg.butter(2, [lo, hi_c], btype="band", fs=SR, output="sos")
            band = sg.sosfilt(sos, _ir_band_noise(L, rt60 * 1.3 * max(mult, 0.08), r))
            tail += band * (bright if lo >= 3500 else 1.0)
        build = 1.0 - np.exp(-t / max(0.012 * size, 1e-3))     # narastanie gęstości echa
        tail *= build
        # wczesne odbicia: rzadkie impulsy w pierwszych ~90 ms·size, rosnąca gęstość
        er = np.zeros(L)
        n_er = int(18 + 10 * size)
        times = np.sort(r.uniform(0.002, 0.09 * size, n_er)) ** 1.0
        for k, tt in enumerate(times):
            i = int(tt * SR)
            if i < L:
                er[i] += r.bipolar(1.0) * (1.0 / (1.0 + 7.0 * tt / size))
        er = sg.sosfilt(sg.butter(1, min(7000.0 * bright, NYQ_SAFE), fs=SR, output="sos"), er)
        ir = tail * 0.045 + er * er_gain * 0.9
        pre = ms(pre_ms)
        ir = np.concatenate([np.zeros(pre), ir])[:L]
        ir *= np.minimum(1.0, (L - np.arange(L)) / (0.06 * SR))  # wygaszenie końca
        irs.append(ir)
    ir = np.stack(irs) if stereo else irs[0]
    e = math.sqrt(np.sum(ir ** 2))
    return ir / max(e, 1e-12)


def reverb(x: np.ndarray, ir: np.ndarray, wet: float = 0.25, dry: float = 1.0,
           keep_len: bool = False, hp_wet: float = 120.0) -> np.ndarray:
    """Pogłos splotowy. Wejście mono → wyjście stereo (jeśli IR stereo). Ogon NIE jest
    obcinany (wydłuża bufor), chyba że keep_len=True."""
    xm = to_mono(x)
    n = len(xm)
    if ir.ndim == 1:
        wetsig = sg.fftconvolve(xm, ir)
        wetsig = filt(wetsig, "hp", hp_wet) if hp_wet else wetsig
        out_n = n if keep_len else len(wetsig)
        return pad_to(xm, out_n) * dry + pad_to(wetsig, out_n) * wet
    chans = [sg.fftconvolve(xm, ir[c]) for c in range(2)]
    wetsig = np.stack(chans)
    if hp_wet:
        wetsig = filt(wetsig, "hp", hp_wet)
    out_n = n if keep_len else wetsig.shape[-1]
    return np.stack([pad_to(xm, out_n)] * 2) * dry + pad_to(wetsig, out_n) * wet


def reverb_stereo(x: np.ndarray, ir_st: np.ndarray, wet: float = 0.25, dry: float = 1.0,
                  keep_len: bool = False) -> np.ndarray:
    """Pogłos splotowy zachowujący obraz stereo: L*IR_L, R*IR_R (IR nieskorelowane)."""
    if x.ndim == 1:
        x = np.stack([x, x])
    w = np.stack([sg.fftconvolve(x[c], ir_st[c]) for c in range(2)])
    out_n = x.shape[-1] if keep_len else w.shape[-1]
    return pad_to(x, out_n) * dry + pad_to(w, out_n) * wet


def echo_tail(x: np.ndarray, delays_ms, gains, lp_hz: float = 4000.0) -> np.ndarray:
    """Wielokrotne echa (rozbicie dźwięku od drzew/ścian w oddali: slapback)."""
    out = x.copy() if x.ndim == 1 else x.copy()
    tot = max(ms(d) for d in delays_ms) + x.shape[-1]
    out = pad_to(out, tot)
    for d, g in zip(delays_ms, gains):
        e = filt(x, "lp", lp_hz) * g
        k = ms(d)
        out[..., k:k + x.shape[-1]] += e
    return out


def decorrelate(x: np.ndarray, rng: Rng, amount: float = 1.0) -> np.ndarray:
    """Mono → stereo przez dwie niezależne kaskady allpass (zero opóźnienia Haas):
    płaska magnituda na każdym kanale, mała strata przy sumie do mono."""
    def chain(seed_off: int) -> np.ndarray:
        r = rng.fork(100 + seed_off)
        y = x
        for _ in range(4):
            d = ms(r.uniform(0.6, 4.5) * amount + 0.2)
            g = 0.45 + 0.3 * r.uniform()
            b = np.zeros(d + 1); b[0] = g; b[-1] = 1.0
            a = np.zeros(d + 1); a[0] = 1.0; a[-1] = g
            y = sg.lfilter(b, a, y)
        return y
    return np.stack([chain(0), chain(1)])


def stereo_noise_bed(fn, rng: Rng, corr: float = 0.0) -> np.ndarray:
    """Buduje stereo z DWÓCH niezależnych realizacji generatora fn(rng) — naturalna szerokość,
    brak filtra grzebieniowego. corr∈[0,1] domiesza wspólny sygnał (środek obrazu)."""
    a, b = fn(rng.fork(11)), fn(rng.fork(12))
    if corr > 0:
        c = fn(rng.fork(13))
        a = a * math.sqrt(1 - corr) + c * math.sqrt(corr)
        b = b * math.sqrt(1 - corr) + c * math.sqrt(corr)
    return np.stack([a, b])


# ------------------------------------------------------------------ pętle

def circ_filter(x: np.ndarray, fn) -> np.ndarray:
    """Zastosuj dowolną obróbkę fn do okresowego x tak, by wynik był okresowy (3× kafel → środek)."""
    n = x.shape[-1]
    t = np.concatenate([x, x, x], axis=-1)
    return fn(t)[..., n:2 * n]


def fold_loop(x: np.ndarray, n: int) -> np.ndarray:
    """Zawija nadmiarowy ogon (poza n) na początek: zdarzenia rytmiczne z pogłosem/ogonami
    tworzą idealną pętlę (ogon ostatniej nuty wybrzmiewa pod pierwszą)."""
    if x.shape[-1] <= n:
        return pad_to(x, n)
    out = x[..., :n].copy()
    rest = x[..., n:]
    while rest.shape[-1] > 0:
        k = min(n, rest.shape[-1])
        out[..., :k] += rest[..., :k]
        rest = rest[..., k:]
    return out


def seam_xfade(x: np.ndarray, xf: int, power: bool = True) -> np.ndarray:
    """Pętla z materiału nieokresowego: skraca o xf i przenika ogon w głowę
    (power=True: prawo mocy dla nieskorelowanego, False: liniowo dla skorelowanego)."""
    n = x.shape[-1]
    if xf <= 1 or n <= 2 * xf:
        return x
    out = x[..., xf:].copy()
    th = np.linspace(0.0, 1.0, xf, endpoint=False) + 0.5 / xf
    if power:
        fin, fout = np.sin(th * math.pi / 2), np.cos(th * math.pi / 2)
    else:
        fin, fout = th, 1.0 - th
    out[..., -xf:] = out[..., -xf:] * fout + x[..., :xf] * fin
    return out


# ------------------------------------------------------------------ miary głośności

_K_SHELF = (np.array([1.53512485958697, -2.69169618940638, 1.19839281085285]),
            np.array([1.0, -1.69065929318241, 0.73248077421585]))
_K_HP = (np.array([1.0, -2.0, 1.0]), np.array([1.0, -1.99004745483398, 0.99007225036621]))


def k_weight(x: np.ndarray) -> np.ndarray:
    y = sg.lfilter(_K_SHELF[0], _K_SHELF[1], x, axis=-1)
    return sg.lfilter(_K_HP[0], _K_HP[1], y, axis=-1)


def lufs(x: np.ndarray) -> float:
    """Loudness BS.1770 (K-weighted, bez bramkowania) dla całego bufora — dla pętli i
    krótkich zdarzeń to dobry odpowiednik głośności postrzeganej."""
    y = k_weight(x)
    ms_ = np.mean(y ** 2, axis=-1)
    return -0.691 + 10.0 * math.log10(max(float(np.sum(ms_)), 1e-12))


def active_lufs(x: np.ndarray, gate_db: float = 30.0) -> float:
    """Głośność liczona tylko z okien 25 ms o poziomie w zakresie gate_db poniżej najgłośniejszego:
    krótki strzał z długim ogonem nie wychodzi „cichy" przez uśrednianie z ciszą."""
    y = k_weight(x)
    p = (y ** 2) if y.ndim == 1 else (y ** 2).sum(axis=0)
    w = ms(25)
    nb = max(1, len(p) // w)
    blk = p[:nb * w].reshape(nb, w).mean(axis=1)
    top = blk.max()
    sel = blk[blk >= top * 10.0 ** (-gate_db / 10.0)]
    return -0.691 + 10.0 * math.log10(max(float(sel.mean()), 1e-12))


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x)))


def true_peak_db(x: np.ndarray) -> float:
    up = sg.resample_poly(x, 4, 1, axis=-1)
    return lin_to_db(np.max(np.abs(up)))


def normalize_peak(x: np.ndarray, db: float = -1.5) -> np.ndarray:
    p = peak(x)
    return x if p < 1e-9 else x * (db_to_lin(db) / p)


def fade_edges(x: np.ndarray, fin_ms: float = 1.0, fout_ms: float = 8.0) -> np.ndarray:
    n = x.shape[-1]
    fi = min(ms(fin_ms), n // 4)
    fo = min(ms(fout_ms), n // 2)
    g = np.ones(n)
    if fi > 0:
        g[:fi] = 0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi)
    if fo > 0:
        g[n - fo:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / fo)
    return x * g


def trim_silence(x: np.ndarray, thr_db: float = -66.0, keep_ms: float = 5.0) -> np.ndarray:
    """Obcina ciszę z końca (ogon pogłosu poniżej progu) — pliki nie niosą ciszy w pamięci."""
    m = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=0)
    idx = np.nonzero(m > db_to_lin(thr_db))[0]
    if len(idx) == 0:
        return x
    end = min(x.shape[-1], idx[-1] + ms(keep_ms))
    return x[..., :end]


# ------------------------------------------------------------------ zapis

def write_wav(path: str, x: np.ndarray, rng: Rng | None = None) -> None:
    """16-bit PCM z dithererem TPDF (deterministycznym). x: (n,) albo (2, n)."""
    r = rng or Rng(0xD17E5)
    q = x * 32767.0
    q = q + (r.g.uniform(-0.5, 0.5, x.shape) + r.g.uniform(-0.5, 0.5, x.shape))
    pcm = np.clip(np.round(q), -32768, 32767).astype("<i2")
    ch = 1 if x.ndim == 1 else 2
    data = pcm if ch == 1 else pcm.T.reshape(-1)
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
