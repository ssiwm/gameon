"""
bake_common.py — rejestr assetów i finalizacja (poziomy, krawędzie, zapis) dla bake_audio.py.

finalize() jest JEDYNYM miejscem, które zapisuje WAV-y. Polityka (AAA-owy „loudness plan"):
  * one-shot impulsowy (strzał, krok, UI):  peak=<dB>      — normalizacja po szczycie
  * one-shot/pętla trwały (ryk, ambient):   lufs=<LUFS>    — normalizacja po głośności (K-weighted)
  * zawsze:  true-peak ≤ TP_CEIL (-1.5 dBTP), brak DC, dither TPDF, zero próbek na pełnej skali
  * one-shot: wycięcie ciszy z ogona, fade-in 1 ms, fade-out dopasowany do ogona (koniec = 0)
  * pętla: bez fade'ów (szew jest zamknięty konstrukcyjnie: circ_filter/fold_loop)
"""

from __future__ import annotations

import os
import zlib

import numpy as np

import audio_dsp as d
from audio_dsp import SR, Rng, ms

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "audio")

TP_CEIL = -1.5

# key -> (ścieżka względna, pętla?)
REG: dict[str, tuple[str, bool]] = {}
GROUPS: dict[str, list[str]] = {}
# key -> pomiary po finalizacji (do raportu bake'u)
STATS: dict[str, dict] = {}
_CUR = ["sfx/misc"]


def group(path: str) -> None:
    """Domyślny katalog dla kolejnych render()."""
    _CUR[0] = path


def asset(key: str, path: str, loop: bool = False) -> None:
    REG[key] = (path, loop)
    GROUPS.setdefault(path.split("/")[0], []).append(key)


def finalize(key: str, x: np.ndarray, *, loop: bool = False, peak: float | None = None,
             lufs: float | None = None, fade_out_ms: float | None = None,
             fade_in_ms: float = 0.6, trim: bool = True, tp: float = TP_CEIL) -> None:
    """Domyka bufor i zapisuje asset. Dokładnie jedno z: peak (dBFS) albo lufs (LUFS)."""
    assert (peak is None) != (lufs is None), "%s: podaj peak= albo lufs=" % key
    if key not in REG:
        REG[key] = (_CUR[0] + "/" + key, loop)
    path, reg_loop = REG[key]
    assert reg_loop == loop, "%s: niezgodność flagi pętli z rejestrem" % key
    full = os.path.join(AUDIO, path + ".wav")
    os.makedirs(os.path.dirname(full), exist_ok=True)

    x = np.asarray(x, dtype=np.float64)
    assert np.all(np.isfinite(x)), "%s: NaN/Inf w buforze" % key
    if loop:
        x = d.circ_filter(x, lambda t: d.dc_block(t))
    else:
        x = d.dc_block(x)
        if trim:
            x = d.trim_silence(x, -55.0)
        x = x - np.mean(x, axis=-1, keepdims=True)       # dokładnie zerowa składowa stała
        n = x.shape[-1]
        fo = fade_out_ms if fade_out_ms is not None else min(40.0, max(6.0, n / SR * 1000.0 * 0.12))
        x = d.fade_edges(x, fade_in_ms, fo)

    if lufs is not None:
        cur = d.lufs(x) if loop else d.active_lufs(x)
        g = d.db_to_lin(lufs - cur)
    else:
        p = d.peak(x)
        g = d.db_to_lin(peak) / max(p, 1e-9)
    x = x * g
    # true-peak: miękkie ograniczenie, potem — jeśli trzeba — zejście wzmocnieniem
    for _ in range(3):
        tpk = d.true_peak_db(x)
        if tpk <= tp + 0.05:
            break
        if lufs is not None and not loop and _ == 0:
            x = d.limiter(x, tp - 0.4)
        else:
            x = x * d.db_to_lin(tp - tpk - 0.05)

    d.write_wav(full, x, Rng(zlib.crc32(key.encode()) | 1))
    STATS[key] = {"dur": x.shape[-1] / SR, "ch": 1 if x.ndim == 1 else 2,
                  "lufs": d.lufs(x) if loop else d.active_lufs(x),
                  "tp": d.true_peak_db(x), "peak": d.lin_to_db(d.peak(x))}


# ------------------------------------------------------------------ narzędzia dźwiękowe

_IR_CACHE: dict = {}


def ir(kind: str) -> np.ndarray:
    """Zestaw pomieszczeń do pieczenia ogonów (deterministyczne, cache'owane)."""
    if kind in _IR_CACHE:
        return _IR_CACHE[kind]
    P = {
        # nazwa:        rt60, size, damping, pre_ms, bright, stereo
        "close":    (0.30, 0.45, 0.55, 2.0, 0.9, False),   # krótki ogon źródła (strzał, krok)
        "room":     (0.70, 1.0, 0.45, 6.0, 0.9, False),
        "hall":     (1.60, 1.9, 0.35, 14.0, 0.8, False),
        "cave":     (3.00, 2.6, 0.25, 22.0, 0.65, False),
        "metal":    (1.10, 0.9, 0.05, 4.0, 1.15, False),   # korytarz blaszany — jasny, długi
        "dead":     (0.18, 0.3, 0.8, 1.0, 0.6, False),
        "hall_st":  (1.60, 1.9, 0.35, 14.0, 0.8, True),
        "cave_st":  (3.40, 2.6, 0.25, 22.0, 0.65, True),
        "plate_st": (1.30, 1.2, 0.2, 8.0, 1.1, True),
        "gate_st":  (0.55, 0.8, 0.3, 2.0, 1.0, True),
    }[kind]
    seeds = {"close": 11, "room": 12, "hall": 13, "cave": 14, "metal": 15, "dead": 16,
             "hall_st": 17, "cave_st": 18, "plate_st": 19, "gate_st": 20}
    rt, size, damp, pre, bright, st = P
    _IR_CACHE[kind] = d.make_ir(rt, Rng(0xA110 + seeds[kind]), size=size, damping=damp,
                                pre_ms=pre, bright=bright, stereo=st)
    return _IR_CACHE[kind]


def _end_taper(y: np.ndarray, frac: float = 0.25) -> np.ndarray:
    """Płynne wyzerowanie końca bufora (cos²): ucięty ogon to klik słyszalny jako „prążek"
    w spektrogramie — wykryty na pierwszym przebiegu strzałów (thump 160 ms)."""
    n = len(y)
    k = max(2, int(n * frac))
    g = np.ones(n)
    g[n - k:] = np.cos(np.linspace(0.0, np.pi / 2, k)) ** 2
    return y * g


def vary(rng: Rng, v: float, pct: float) -> float:
    """v ± pct (jednostajnie) — rozrzut parametrów wariantów."""
    return v * (1.0 + rng.bipolar(pct))


def burst(n: int, rng: Rng, f0: float, f1: float, tau: float, q: float = 0.9,
          attack: float = 0.0003, color: float = 0.0) -> np.ndarray:
    """Impuls szumowy z opadającym filtrem LP (f0→f1) i wykładniczą obwiednią.
    color>0: szum różowawy (cieplejszy)."""
    src = d.colored(n, rng, color) if color else d.white(n, rng)
    y = d.sweep(src, "lp", d.glide_exp(f0, f1, n, tau * 0.8), q=q) * d.env_perc(n, attack, tau)
    return _end_taper(y)


def thump(dur: float, f0: float, f1: float, pitch_tau: float, amp_tau: float,
          attack: float = 0.0006) -> np.ndarray:
    """Sinus z wykładniczym opadaniem wysokości — korpus strzału, kick, uderzenie."""
    n = ms(dur * 1000)
    return _end_taper(d.osc("sine", d.glide_exp(f0, f1, n, pitch_tau), n) * d.env_perc(n, attack, amp_tau))


def tick(rng: Rng, f: float, q: float, dur_ms: float = 8.0, tau: float = 0.0015) -> np.ndarray:
    """Krótki klik pasmowy (mechanika, kontakt twardych powierzchni)."""
    n = ms(dur_ms)
    return d.filt(d.white(n, rng), "bp", f, q) * d.env_perc(n, 0.00008, tau) * 4.0


def ring(rng: Rng, freqs, t60s, amps=None, dur: float = 0.5, jitter: float = 0.01) -> np.ndarray:
    amps = amps if amps is not None else [1.0 / (1 + 0.35 * i) for i in range(len(freqs))]
    return _end_taper(d.modal(freqs, amps, t60s, ms(dur * 1000), rng, jitter))


def vowel(src: np.ndarray, kind: str = "a", bw: float = 9.0, gain: float = 1.0) -> np.ndarray:
    """Filtry formantowe (przybliżenie samogłosek) — wspólne dla głosów ludzkich i stworów."""
    F = {
        "a": ((730, 1.0), (1090, 0.6), (2440, 0.35), (3400, 0.15)),
        "o": ((570, 1.0), (840, 0.5), (2410, 0.2), (3300, 0.1)),
        "u": ((300, 1.0), (870, 0.35), (2240, 0.12), (3300, 0.08)),
        "e": ((530, 1.0), (1840, 0.5), (2480, 0.3), (3500, 0.12)),
        "i": ((270, 1.0), (2290, 0.45), (3010, 0.3), (3500, 0.12)),
        "gutt": ((420, 1.0), (760, 0.8), (1500, 0.3), (2600, 0.12)),   # krtaniowe, „zwierzęce"
    }[kind]
    return d.formant(src, F, bw) * gain


def glottal(n: int, f0, rng: Rng, jitter: float = 0.01, shimmer: float = 0.0,
            breath: float = 0.0, shape: str = "saw") -> np.ndarray:
    """Źródło głosowe: fala piłokształtna ze zmiennym f0, jitterem (nieregularność okresów)
    i szumem oddechu. f0: Hz skalar albo przebieg."""
    f = d._arr(f0, n).copy()
    if jitter:
        j = d.sweep(d.white(n, rng), "lp", 60.0 * np.ones(n), 0.7)
        f = f * (1.0 + jitter * j / (np.std(j) + 1e-9))
    y = d.osc(shape, f, n)
    if shimmer:
        s = d.lp(d.white(n, rng), 80.0)
        y = y * (1.0 + shimmer * s / (np.std(s) + 1e-9))
    if breath:
        y = y + breath * d.white(n, rng)
    return y
