"""
bake_weather.py — dźwięk pogody (WEATHER_PLAN.md W2–W4): wersje PUBLICZNE (synteza) wszystkich kluczy pogody.

Wersje z nagrań tych samych kluczy piecze bake_hybrid.weather() (audio_licensed/, poza repo). Gra (weather_sound.gd) gra:
  * deszcz: tło z trzech warstw (lekki / średni / ulewa) przenikanych wg siły pogody, krople na materiałach (metal, deski, ziemia,
    liście, beton, woda) z emiterów przy kolumnach mapy, deszcz na dachu (blacha, deski), strumień z okapu, krople na kapturze;
  * wiatr: trzy warstwy (niski pomruk, korony, świst), podmuch (pętla, którą zegar pogody podnosi obwiednią podmuchu), świst w oknie;
  * grzmot: trzask (tylko blisko), toczenie bliższe (1–3) i dalekie (4–6), drżenie szyb pod dachem.

Pętle mają ≥ 60 s (kryterium planu: bez słyszalnej powtórki w 2 min) i różne długości, więc warstwy nie wracają razem. Są w grupie
amb/ (Ogg Vorbis, strumieniowane); WAV-y tej grupy są tylko pośrednim produktem bake'u (w .gitignore — 60 s stereo to 11 MB).

Krople = ziarna: kilka jąder uderzenia na materiał (szum pasmowy, rezonans modalny, plusk) splecionych z losowym ciągiem impulsów
(fftconvolve), zawiniętych w pętlę (fold_loop) — okresowe z konstrukcji, bez szwu. Stereo z dwóch niezależnych realizacji.
"""

from __future__ import annotations

import math

import numpy as np
import scipy.signal as sg

import audio_dsp as d
from audio_dsp import SR, Rng, ms, sec
from bake_common import asset, finalize, ir, ring

TAU = d.TAU

# klucz → (długość pętli [s], stereo, LUFS)
LOOPS = {
    "amb_rain_light": (61.0, True, -17.0),
    "amb_rain_mid": (67.0, True, -16.0),
    "amb_rain_heavy": (71.0, True, -15.0),
    "rain_on_metal": (61.0, False, -20.0),
    "rain_on_wood": (62.0, False, -20.0),
    "rain_on_dirt": (63.0, False, -21.0),
    "rain_on_leaves": (64.0, False, -20.0),
    "rain_on_concrete": (65.0, False, -20.0),
    "rain_on_water": (66.0, False, -20.0),
    "rain_roof_metal": (67.0, True, -17.0),
    "rain_roof_wood": (61.0, True, -18.0),
    "rain_eave": (62.0, False, -20.0),
    "rain_mask": (60.0, True, -24.0),
    "amb_wind_low": (73.0, True, -19.0),
    "amb_wind_trees": (67.0, True, -19.0),
    "amb_wind_whistle": (61.0, True, -22.0),
    "wind_gust": (60.0, False, -19.0),
    "wind_window": (61.0, False, -22.0),
}
# jednorazowe: klucz → LUFS (aktywne)
SHOTS = {
    "thunder_crack": -17.0,
    "thunder_roll": -19.0,
    "thunder_rattle": -24.0,
}
N_CRACK, N_ROLL, N_RATTLE = 3, 6, 2


def _per(n: int, cycles: int, rng: Rng) -> np.ndarray:
    """Wolna zmienność okresowa w pętli (całkowite liczby cykli) 0..~1."""
    t = np.arange(n) / n
    v = 0.55 + 0.25 * np.sin(TAU * cycles * t + rng.uniform(0, TAU)) + 0.15 * np.sin(TAU * (cycles * 3 + 1) * t + rng.uniform(0, TAU)) \
        + 0.08 * np.sin(TAU * (cycles * 7 + 2) * t + rng.uniform(0, TAU))
    return np.clip(v, 0.05, 1.2)


def _grains(n: int, rng: Rng, rate: float, kernels: list, mod: np.ndarray | None = None, alo: float = 0.15) -> np.ndarray:
    """Ciąg kropel: `rate` na sekundę, jądra losowane z `kernels`, siła ~ U(alo,1)²; `mod` (0..1+) przerzedza krople w czasie."""
    cnt = int(rate * n / SR)
    pos = rng.integers(0, n, cnt)
    amp = rng.uniform(alo, 1.0, cnt) ** 2
    if mod is not None:
        keep = rng.uniform(0.0, 1.2, cnt) < mod[pos]
        pos, amp = pos[keep], amp[keep]
    which = rng.integers(0, len(kernels), pos.shape[0])
    klen = max(len(k) for k in kernels)
    out = np.zeros(n + klen)
    for j, k in enumerate(kernels):
        sel = which == j
        if not np.any(sel):
            continue
        imp = np.zeros(n)
        np.add.at(imp, pos[sel], amp[sel])
        y = sg.fftconvolve(imp, k)
        out[:len(y)] += y
    return d.fold_loop(out, n)


def _noise_k(rng: Rng, f: float, q: float, dur_ms: float, tau: float) -> np.ndarray:
    m = ms(dur_ms)
    return d.filt(d.white(m, rng), "bp", f, q) * d.env_perc(m, 0.00006, tau) * 4.0


def _plink_k(rng: Rng, f: float, dur_ms: float) -> np.ndarray:
    m = ms(dur_ms)
    return d.osc("sine", d.glide(f, f * rng.uniform(1.5, 2.1), m), m) * d.env_perc(m, 0.0008, dur_ms / 1000.0 * 0.3)


def _bed(n: int, rng: Rng, slope: float, lo: float, hi: float) -> np.ndarray:
    """Szum tła pasmowy (okresowy)."""
    return d.circ_filter(d.colored(n, rng, slope), lambda z: d.lp(d.hp(z, lo), hi, order=2))


def _add(*parts: np.ndarray) -> np.ndarray:
    """Suma jąder różnej długości (krótsze dopełnione ciszą)."""
    n = max(len(p) for p in parts)
    return sum(d.pad_to(p, n) for p in parts)


# ------------------------------------------------------------------ jądra kropel wg materiału

def _k_drop(rng: Rng, mat: str) -> list:
    r = rng
    if mat == "metal":
        ks = []
        for _ in range(6):
            f = r.uniform(1300, 3400)
            ks.append(_add(ring(r, [f, f * 2.27, f * 3.91], [0.25, 0.14, 0.07], [1.0, 0.5, 0.25], dur=0.3, jitter=0.01) * 0.6,
                           _noise_k(r, r.uniform(4000, 7000), 1.2, 6, 0.0015) * 0.3))
        for _ in range(2):
            f = r.uniform(280, 520)
            ks.append(ring(r, [f, f * 1.83, f * 2.9], [0.5, 0.3, 0.2], [1.0, 0.5, 0.3], dur=0.6, jitter=0.01) * 0.7)
        return ks
    if mat == "wood":
        return [_add(_noise_k(r, r.uniform(260, 700), 1.4, 30, 0.010) * 1.2, _noise_k(r, r.uniform(1800, 3200), 1.5, 6, 0.0015) * 0.25)
                for _ in range(6)]
    if mat == "dirt":
        return [d.lp(_noise_k(r, r.uniform(700, 1800), 0.8, 14, 0.005), 3000.0) for _ in range(6)]
    if mat == "leaves":
        return [_noise_k(r, r.uniform(2600, 7000), 0.9, 8, 0.0028) for _ in range(6)]
    if mat == "concrete":
        return [_add(_noise_k(r, r.uniform(1500, 5200), 0.7, 16, 0.006), _noise_k(r, r.uniform(350, 600), 1.0, 14, 0.004) * 0.3)
                for _ in range(6)]
    if mat == "water":
        return [_add(_plink_k(r, r.uniform(650, 2000), r.uniform(30, 60)) * 0.8, _noise_k(r, r.uniform(2500, 5000), 0.8, 10, 0.004) * 0.5)
                for _ in range(6)]
    raise KeyError(mat)


DROP_RATE = {"metal": 70.0, "wood": 90.0, "dirt": 420.0, "leaves": 520.0, "concrete": 320.0, "water": 60.0}
DROP_WASH = {"metal": (0.6, 2500.0, 9000.0, 0.25), "wood": (1.2, 120.0, 1400.0, 0.35), "dirt": (1.0, 150.0, 2500.0, 0.45),
             "leaves": (0.4, 1500.0, 9000.0, 0.5), "concrete": (0.5, 600.0, 7000.0, 0.45), "water": (0.6, 800.0, 6000.0, 0.45)}


def _drops(n: int, rng: Rng, mat: str) -> np.ndarray:
    mod = _per(n, 2, rng.fork(1))
    g = _grains(n, rng.fork(2), DROP_RATE[mat], _k_drop(rng.fork(3), mat), mod)
    slope, lo, hi, w = DROP_WASH[mat]
    wash = _bed(n, rng.fork(4), slope, lo, hi) * (0.6 + 0.4 * mod)
    return d.mix([(g / (d.peak(g) + 1e-9), 1.0), (wash / (d.peak(wash) + 1e-9), w)], n)


# ------------------------------------------------------------------ tło deszczu

RAIN_BED = {  # gęstość kropel [1/s], udział szumu, udział huku (ulewa), plinki [1/s]
    "amb_rain_light": (220.0, 0.35, 0.0, 6.0),
    "amb_rain_mid": (700.0, 0.6, 0.15, 9.0),
    "amb_rain_heavy": (1700.0, 0.9, 0.45, 12.0),
}


def _rain_bed(n: int, rng: Rng, key: str) -> np.ndarray:
    dens, hiss_w, roar_w, plinks = RAIN_BED[key]
    mod = _per(n, 3, rng.fork(1))
    ks = _k_drop(rng.fork(2), "leaves") + _k_drop(rng.fork(3), "dirt")
    g = _grains(n, rng.fork(4), dens, ks, mod)
    pl = _grains(n, rng.fork(5), plinks, _k_drop(rng.fork(6), "water"), mod)
    hiss = _bed(n, rng.fork(7), 0.15, 1800.0, 9000.0) * (0.7 + 0.3 * mod)
    roar = _bed(n, rng.fork(8), 1.6, 60.0, 420.0) * (0.6 + 0.4 * mod)
    u = lambda x: x / (d.peak(x) + 1e-9)
    return d.mix([(u(g), 1.0), (u(pl), 0.35), (u(hiss), hiss_w), (u(roar), roar_w)], n)


# ------------------------------------------------------------------ dach, okap, maska

def _roof(n: int, rng: Rng, metal: bool) -> np.ndarray:
    mod = _per(n, 2, rng.fork(1))
    if metal:
        ks = []
        for _ in range(8):
            f = rng.uniform(380, 1100)
            ks.append(ring(rng, [f, f * 2.31, f * 4.1], [0.35, 0.2, 0.1], [1.0, 0.5, 0.25], dur=0.45, jitter=0.01))
        g = _grains(n, rng.fork(2), 260.0, ks, mod)
        drum = _bed(n, rng.fork(3), 1.6, 40.0, 220.0)
        hiss = _bed(n, rng.fork(4), 0.6, 1200.0, 4000.0)
        parts = [(g, 1.0), (drum, 0.6), (hiss, 0.35)]
    else:
        ks = [_noise_k(rng, rng.uniform(140, 420), 1.2, 40, 0.016) for _ in range(6)]
        g = _grains(n, rng.fork(2), 340.0, ks, mod)
        hiss = _bed(n, rng.fork(4), 1.0, 200.0, 1300.0)
        parts = [(g, 1.0), (hiss, 0.5)]
    return d.mix([(p / (d.peak(p) + 1e-9) * (0.7 + 0.3 * mod), w) for p, w in parts], n)


def _eave(n: int, rng: Rng) -> np.ndarray:
    t = np.arange(n) / SR
    flutter = 0.6 + 0.25 * np.sin(TAU * round(5.3 * n / SR) * t / (n / SR)) + 0.15 * d.circ_filter(
        d.colored(n, rng.fork(1), 2.0), lambda z: d.lp(z, 8.0, order=1)) / 0.4
    stream = _bed(n, rng.fork(2), 0.8, 500.0, 2800.0) * np.clip(flutter, 0.1, 1.5)
    splash = _grains(n, rng.fork(3), 30.0, _k_drop(rng.fork(4), "water") + _k_drop(rng.fork(5), "concrete"))
    u = lambda x: x / (d.peak(x) + 1e-9)
    return d.mix([(u(stream), 1.0), (u(splash), 0.6)], n)


def _mask(n: int, rng: Rng) -> np.ndarray:
    mod = _per(n, 2, rng.fork(1))
    fabric = [d.lp(_noise_k(rng, rng.uniform(500, 1200), 0.7, 40, 0.015), 1500.0) for _ in range(5)]
    plastic = [_noise_k(rng, rng.uniform(3000, 5200), 1.6, 6, 0.0018) for _ in range(4)]
    a = _grains(n, rng.fork(2), 14.0, fabric, mod)
    b = _grains(n, rng.fork(3), 5.0, plastic, mod)
    u = lambda x: x / (d.peak(x) + 1e-9)
    return d.mix([(u(a), 1.0), (u(b), 0.35)], n)


# ------------------------------------------------------------------ wiatr

def _wind_low(n: int, rng: Rng) -> np.ndarray:
    mod = _per(n, 3, rng.fork(1))
    return _bed(n, rng.fork(2), 2.0, 25.0, 170.0) * mod + _bed(n, rng.fork(3), 1.4, 120.0, 600.0) * 0.25 * mod ** 2


def _wind_trees(n: int, rng: Rng) -> np.ndarray:
    mod = _per(n, 5, rng.fork(1))
    fc = 500.0 + 1600.0 * np.clip(mod, 0, 1.2)
    rustle = d.circ_filter(d.colored(n, rng.fork(2), 0.7), lambda z: d.sweep(d.hp(z, 300.0), "lp", np.tile(fc, 3), 0.7))
    return rustle * mod ** 1.5


def _wind_whistle(n: int, rng: Rng) -> np.ndarray:
    t = np.arange(n) / SR
    T = n / SR
    out = np.zeros(n)
    for j in range(3):
        f = 520.0 + 260.0 * j + 140.0 * np.sin(TAU * (2 + j) * t / T + rng.uniform(0, TAU)) + 60.0 * np.sin(TAU * (9 + 2 * j) * t / T)
        x = d.circ_filter(d.white(n, rng.fork(10 + j)), lambda z, f=f: d.sweep(z, "bp", np.tile(f, 3), 32.0))
        out += x * np.clip(_per(n, 3 + j, rng.fork(20 + j)) - 0.3, 0.0, 1.0) ** 2
    breath = _bed(n, rng.fork(3), 1.0, 300.0, 1800.0) * 0.15
    return out + breath


def _wind_gust(n: int, rng: Rng) -> np.ndarray:
    mod = _per(n, 7, rng.fork(1))
    fc = 260.0 + 1300.0 * np.clip(mod, 0, 1.2) ** 1.5
    x = d.circ_filter(d.colored(n, rng.fork(2), 1.2), lambda z: d.sweep(z, "lp", np.tile(fc, 3), 0.8))
    return x * (0.4 + 0.6 * mod)


def _wind_window(n: int, rng: Rng) -> np.ndarray:
    t = np.arange(n) / SR
    T = n / SR
    out = np.zeros(n)
    for j in range(2):
        f = 900.0 + 420.0 * j + 180.0 * np.sin(TAU * (3 + j) * t / T + rng.uniform(0, TAU)) + 70.0 * np.sin(TAU * (13 + j) * t / T)
        x = d.circ_filter(d.white(n, rng.fork(10 + j)), lambda z, f=f: d.sweep(z, "bp", np.tile(f, 3), 45.0))
        out += x * np.clip(_per(n, 4 + j, rng.fork(20 + j)) - 0.2, 0.0, 1.0) ** 1.5
    return out + _bed(n, rng.fork(3), 0.8, 400.0, 3000.0) * 0.12


# ------------------------------------------------------------------ grzmot

def _crack(rng: Rng) -> np.ndarray:
    n = sec(3.2)
    x = np.zeros(n)
    for _ in range(int(rng.integers(8, 16))):
        at = int(rng.uniform(0.0, 0.28) * SR)
        k = _noise_k(rng, rng.uniform(1200, 7000), 0.8, rng.uniform(6, 25), rng.uniform(0.002, 0.008)) * rng.uniform(0.4, 1.0)
        x[at:at + len(k)] += k[:max(0, n - at)]
    m = sec(2.6)
    body = d.sweep(d.white(m, rng), "lp", d.glide_exp(11000.0, 300.0, m, 0.35), 0.8) * d.env_perc(m, 0.002, 0.45)
    sub = d.osc("sine", d.glide_exp(70.0, 32.0, m, 0.6), m) * d.env_perc(m, 0.01, 0.8)
    x = d.mix([(x / (d.peak(x) + 1e-9), 1.0), (body / (d.peak(body) + 1e-9), 0.8), (sub, 0.5)], n)
    return d.reverb(x, ir("hall_st"), wet=0.35)


def _roll(rng: Rng, far: bool) -> np.ndarray:
    dur = rng.uniform(15.0, 19.0) if far else rng.uniform(11.0, 15.0)
    n = sec(dur)
    lp_hz = rng.uniform(380, 620) if far else rng.uniform(1500, 2800)
    st = []
    for ch in range(2):
        r = rng.fork(ch + 1)
        base = d.lp(d.brown(n, r), lp_hz, order=2)
        env = np.zeros(n)
        t0 = 0.0 if not far else rng.uniform(0.0, 0.6)
        k = 0
        while t0 < dur * 0.85 and k < 16:
            a = r.uniform(0.08, 0.5) if not far else r.uniform(0.4, 1.2)
            dcy = r.uniform(0.6, 2.4) if not far else r.uniform(1.2, 3.0)
            amp = math.exp(-t0 / (dur * 0.35)) * r.uniform(0.4, 1.0)
            m = sec(a + dcy * 3)
            seg = d.env_perc(m, a, dcy) * amp
            s0 = int(t0 * SR)
            env[s0:s0 + m] = np.maximum(env[s0:s0 + m], seg[:max(0, n - s0)])
            t0 += r.uniform(0.3, 2.2) * (1.0 + 0.15 * k)
            k += 1
        sub = d.lp(d.brown(n, r.fork(9)), 60.0, order=2) * env ** 0.7 * 0.8
        st.append(base * env + sub)
    x = np.stack(st)
    x = x * d.env_pts(n, [(0, 1), (dur - 1.5, 1), (dur, 0)])
    return d.reverb_stereo(x, ir("cave_st"), wet=0.25 if far else 0.15)


def _rattle(rng: Rng) -> np.ndarray:
    n = sec(2.2)
    x = np.zeros(n)
    t = 0.0
    hz = rng.uniform(18, 28)
    while t < 1.9:
        amp = math.sin(math.pi * min(t / 1.9, 1.0)) ** 0.7
        k = _add(_noise_k(rng, rng.uniform(2200, 4200), 2.0, 8, 0.0016), ring(rng, [rng.uniform(2400, 3200)], [0.04], [0.4], dur=0.05))
        s0 = int(t * SR)
        x[s0:s0 + len(k)] += k[:max(0, n - s0)] * amp * rng.uniform(0.5, 1.0)
        t += 1.0 / hz * rng.uniform(0.7, 1.3)
    return d.reverb(x, ir("room"), wet=0.2)


# ------------------------------------------------------------------ zapis

GEN = {
    "amb_rain_light": lambda n, r: _rain_bed(n, r, "amb_rain_light"),
    "amb_rain_mid": lambda n, r: _rain_bed(n, r, "amb_rain_mid"),
    "amb_rain_heavy": lambda n, r: _rain_bed(n, r, "amb_rain_heavy"),
    "rain_on_metal": lambda n, r: _drops(n, r, "metal"),
    "rain_on_wood": lambda n, r: _drops(n, r, "wood"),
    "rain_on_dirt": lambda n, r: _drops(n, r, "dirt"),
    "rain_on_leaves": lambda n, r: _drops(n, r, "leaves"),
    "rain_on_concrete": lambda n, r: _drops(n, r, "concrete"),
    "rain_on_water": lambda n, r: _drops(n, r, "water"),
    "rain_roof_metal": lambda n, r: _roof(n, r, True),
    "rain_roof_wood": lambda n, r: _roof(n, r, False),
    "rain_eave": _eave,
    "rain_mask": _mask,
    "amb_wind_low": _wind_low,
    "amb_wind_trees": _wind_trees,
    "amb_wind_whistle": _wind_whistle,
    "wind_gust": _wind_gust,
    "wind_window": _wind_window,
}


def build_weather() -> None:
    """Synteza wszystkich kluczy pogody → audio/amb/weather/ (Ogg w grze). Wołane z bake_amb.build_ambience()."""
    for i, (key, (dur, stereo, lufs)) in enumerate(LOOPS.items()):
        asset(key, "amb/weather/" + key, loop=True)
        n = sec(dur)
        r = Rng(0xB100 + i)
        fn = GEN[key]
        x = d.stereo_noise_bed(lambda rr: fn(n, rr), r, corr=0.2) if stereo else fn(n, r)
        finalize(key, x, loop=True, lufs=lufs)
    r = Rng(0xB200)
    for i in range(N_CRACK):
        key = "thunder_crack_%d" % (i + 1)
        asset(key, "amb/weather/" + key)
        finalize(key, _crack(r.fork(i)), lufs=SHOTS["thunder_crack"], fade_out_ms=300)
    for i in range(N_ROLL):
        key = "thunder_roll_%d" % (i + 1)
        asset(key, "amb/weather/" + key)
        finalize(key, _roll(r.fork(10 + i), far=i >= 3), lufs=SHOTS["thunder_roll"] - (3.0 if i >= 3 else 0.0), fade_out_ms=800)
    for i in range(N_RATTLE):
        key = "thunder_rattle_%d" % (i + 1)
        asset(key, "amb/weather/" + key)
        finalize(key, _rattle(r.fork(20 + i)), lufs=SHOTS["thunder_rattle"], fade_out_ms=200)
