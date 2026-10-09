"""
bake_amb.py — łóżka ambientu (pętle stereo).

Każda pętla jest OKRESOWA W n PRÓBKACH z konstrukcji: szum kształtowany w dziedzinie FFT,
filtrowany kołowo (3× kafel → środek), LFO o całkowitej liczbie cykli, zdarzenia losowe
zawijane fold_loop(). Szwu nie ma, więc nie ma klików ani dziury w energii (loop_xfade).

Stereo = DWIE niezależne realizacje generatora (L i R) — naturalna szerokość i pełna
zgodność z mono (brak opóźnienia Haas / filtra grzebieniowego, który wykazał audyt).
Wspólne, wolne zjawiska (podmuch) są współdzielone, żeby obraz nie rozpadał się na dwa światy.
"""

from __future__ import annotations

import numpy as np

import audio_dsp as d
from audio_dsp import SR, Rng, ms, sec
from bake_common import asset, finalize, group, ir, ring, thump, tick

TAU = d.TAU


def _tile3(a):
    return np.tile(a, 3)


def _wind(n: int, rng: Rng, shared: np.ndarray) -> np.ndarray:
    t = np.arange(n) / SR
    T = n / SR
    base = d.colored(n, rng, 1.5)
    own = 0.25 * np.sin(TAU * 2 * t / T + rng.uniform(0, TAU)) + 0.12 * np.sin(TAU * 5 * t / T + rng.uniform(0, TAU))
    gust = np.clip(shared + own, 0.05, 1.5)
    fc = 240 + 520 * gust
    x = d.circ_filter(base, lambda z: d.sweep(z, "lp", _tile3(fc), 0.9))
    howl_f = 640 + 260 * np.sin(TAU * 2 * t / T + 0.8) + 120 * np.sin(TAU * 7 * t / T)
    howl = d.circ_filter(d.white(n, rng), lambda z: d.sweep(z, "bp", _tile3(howl_f), 28.0))
    return x * gust + 0.10 * howl * gust ** 3


def _forest(n: int, rng: Rng, shared: np.ndarray) -> np.ndarray:
    t = np.arange(n) / SR
    T = n / SR
    air = d.circ_filter(d.colored(n, rng, 1.4), lambda z: d.lp(z, 340.0, order=3)) * 0.9
    rustle_env = (0.15 + 0.85 * np.clip(shared, 0, 1.2) ** 2) * (0.6 + 0.4 * np.sin(TAU * 11 * t / T + rng.uniform(0, TAU)))
    rustle = d.circ_filter(d.colored(n, rng, 0.4), lambda z: d.bp(d.hp(z, 1500.0), 4600.0, 0.45)) * rustle_env * 0.25
    out = d.mix([(air, 1.0), (rustle, 0.8)], n)
    # świerszcze: kilka osobników, każdy powtarza „cyrp" (3 impulsy) w okresie dopasowanym do pętli
    crick = np.zeros(n + sec(0.5))
    for _ in range(5):
        f = rng.uniform(3700.0, 5300.0)
        reps = int(rng.integers(int(T / 0.62), int(T / 0.34)))
        per = n / reps
        off = rng.uniform(0, per)
        amp = rng.uniform(0.25, 0.6)
        for k in range(reps):
            st = int(off + k * per)
            for p in range(3):
                pn = ms(15)
                seg = np.sin(TAU * f * np.arange(pn) / SR) * d.env_perc(pn, 0.002, 0.006)
                s0 = st + int(p * 0.021 * SR)
                crick[s0:s0 + pn] += seg * amp * (1.0 if p != 1 else 1.15)
    crick = d.fold_loop(crick, n)
    # świerszcze mają niskie natężenie i wąskie pasmo — nie powinny być słyszalne jako „szum"
    return d.mix([(out, 1.0), (crick, 0.42)], n)


def _machine(n: int, rng: Rng, shared: np.ndarray) -> np.ndarray:
    t = np.arange(n) / SR
    T = n / SR
    hum = sum(a * np.sin(TAU * 50.0 * h * t + rng.uniform(0, TAU)) for h, a in ((1, 1.0), (2, 0.7), (3, 0.42), (4, 0.22), (6, 0.12)))
    ballast = 0.25 * np.sin(TAU * 120.0 * t + rng.uniform(0, TAU))
    fan_am = 0.65 + 0.35 * np.sin(TAU * 7.0 * t + rng.uniform(0, TAU))           # 7 Hz łopatki (56 cykli)
    fan = d.circ_filter(d.colored(n, rng, 0.8), lambda z: d.bp(z, 760.0, 0.7)) * fan_am * 0.8
    rumble = d.circ_filter(d.colored(n, rng, 2.0), lambda z: d.lp(z, 95.0, order=3)) * 1.2
    clanks = np.zeros(n + sec(2.0))
    for _ in range(3):
        k = int(rng.uniform(0, n))
        f = rng.uniform(220, 600)
        c = d.mix([(tick(rng, 1400, 1.2, 20, .006), 1.0),
                   (ring(rng, [f, f * 2.4, f * 4.1], [.5, .3, .2], dur=.9), .6)])
        clanks[k:k + len(c)] += c * rng.uniform(.35, .7)
    clanks = d.reverb(clanks, ir("metal"), wet=.5, keep_len=False)
    clanks = d.fold_loop(clanks, n)
    return d.mix([(hum, 0.22), (ballast, 0.18), (fan, 1.0), (rumble, 0.8), (clanks, 0.35)], n)


def _drips(n: int, rng: Rng) -> np.ndarray:
    st = np.zeros((2, n + sec(4.0)))
    for _ in range(14):
        k = int(rng.uniform(0, n))
        f = rng.uniform(550, 1500)
        dn = ms(rng.uniform(28, 55))
        drop = d.osc("sine", d.glide(f, f * 1.9, dn), dn) * d.env_perc(dn, .001, dn / SR * .28)
        drop = d.mix([(drop, 1.0), (tick(rng, rng.uniform(3500, 6500), 1.5, 8, .0015), .25)])
        p = d.pan(drop, rng.uniform(-.8, .8))
        st[:, k:k + p.shape[1]] += p * rng.uniform(.3, 1.0)
    wet = d.reverb(st, ir("cave_st"), wet=1.0, dry=.35, keep_len=False)
    wet = wet[:, :n + sec(4.0)] if wet.shape[1] > n + sec(4.0) else d.pad_to(wet, n + sec(4.0))
    return d.fold_loop(wet, n)


def _air(n: int, rng: Rng, shared: np.ndarray) -> np.ndarray:
    t = np.arange(n) / SR
    T = n / SR
    f_sub = round(36.7 * T) / T
    sub = np.sin(TAU * f_sub * t + rng.uniform(0, TAU)) * (0.7 + 0.3 * np.sin(TAU * 1 * t / T))
    breath = d.circ_filter(d.colored(n, rng, 1.8), lambda z: d.lp(z, 190.0, order=3)) * (0.5 + 0.5 * np.sin(TAU * 2 * t / T + rng.uniform(0, TAU)))
    h2 = np.sin(TAU * 2 * f_sub * t + rng.uniform(0, TAU)) * 0.5
    h3 = np.sin(TAU * 3 * f_sub * t + rng.uniform(0, TAU)) * 0.28 * (0.6 + 0.4 * np.sin(TAU * 2 * t / T))
    return d.mix([(sub, 0.5), (h2, 0.35), (h3, 0.3), (breath, 1.1)], n)


def _drops(n: int, rng: Rng, per_sec: float, shared: np.ndarray, decay: float = 0.0035) -> np.ndarray:
    """Gęsty tekstualny trzask kropel: losowe impulsy (położenie i siła), każdy krótki, pasmowy; liczba kropel faluje z `shared` (siła deszczu)."""
    cnt = int(per_sec * n / SR)
    x = np.zeros(n + sec(0.2))
    for _ in range(cnt):
        k = int(rng.uniform(0, n))
        if rng.uniform(0, 1.2) > float(shared[k % n]):         # mocniejszy deszcz = więcej kropel
            continue
        m = ms(rng.uniform(4, 9))
        seg = d.filt(d.white(m, rng), "bp", rng.uniform(3200, 8200), 0.7) * d.env_perc(m, 0.00005, decay)
        x[k:k + m] += seg * rng.uniform(0.25, 1.0) * 6.0
    return d.fold_loop(x, n)


def _rain(n: int, rng: Rng, shared: np.ndarray) -> np.ndarray:
    """Deszcz na gruncie i listowiu (pętla): szum pasmowy 2–9 kHz + trzask kropel + większe plinki w kałużach."""
    t = np.arange(n) / SR
    T = n / SR
    own = 0.12 * np.sin(TAU * 4 * t / T + rng.uniform(0, TAU))
    force = np.clip(0.75 + 0.35 * (shared - 0.55) + own, 0.35, 1.2)
    hiss = d.circ_filter(d.colored(n, rng, 0.15), lambda z: d.bp(d.hp(z, 1800.0), 5200.0, 0.32)) * force
    body = d.circ_filter(d.colored(n, rng, 1.2), lambda z: d.lp(d.hp(z, 120.0), 520.0, order=2)) * 0.45 * force
    drops = _drops(n, rng, 520.0, force)
    plinks = np.zeros(n + sec(0.4))
    for _ in range(int(9 * T)):
        k = int(rng.uniform(0, n))
        f = rng.uniform(700, 2100)
        dn = ms(rng.uniform(30, 60))
        p = d.osc("sine", d.glide(f, f * 1.7, dn), dn) * d.env_perc(dn, 0.0008, dn / SR * 0.3)
        plinks[k:k + dn] += p * rng.uniform(0.12, 0.4)
    plinks = d.fold_loop(plinks, n)
    return d.mix([(hiss, 1.0), (body, 0.55), (drops, 0.5), (plinks, 0.35)], n)


def _rain_roof(n: int, rng: Rng, shared: np.ndarray) -> np.ndarray:
    """Deszcz na dachu / blasze nad głową (pętla): tupot kropel na rezonującej płycie + stłumiony szum."""
    t = np.arange(n) / SR
    T = n / SR
    force = np.clip(0.75 + 0.3 * (shared - 0.55), 0.35, 1.15)
    muffled = d.circ_filter(d.colored(n, rng, 0.6), lambda z: d.bp(z, 2400.0, 0.4)) * 0.8 * force
    thump = d.circ_filter(d.colored(n, rng, 1.6), lambda z: d.lp(z, 260.0, order=2)) * 0.5 * force
    patter = np.zeros(n + sec(0.6))
    cnt = int(95 * T)
    for _ in range(cnt):
        k = int(rng.uniform(0, n))
        if rng.uniform(0, 1.2) > float(force[k % n]):
            continue
        f0 = rng.uniform(380, 780)
        hit = ring(rng, [f0, f0 * 2.31, f0 * 4.1], [0.12, 0.08, 0.05], [1.0, 0.55, 0.3], dur=0.14, jitter=0.01)
        patter[k:k + len(hit)] += hit * rng.uniform(0.2, 0.9)
    patter = d.fold_loop(patter, n)
    return d.mix([(muffled, 0.8), (thump, 0.6), (patter, 0.55)], n)


def build_ambience() -> None:
    group("amb")
    specs = [
        ("amb_wind", 12.0, _wind, -18.0, 0xA100),
        ("amb_forest", 12.0, _forest, -14.0, 0xA200),
        ("amb_machine", 8.0, _machine, -15.0, 0xA300),
        ("amb_air", 10.0, _air, -18.0, 0xA500),
        ("amb_rain", 12.0, _rain, -16.0, 0xA600),
        ("amb_rain_roof", 10.0, _rain_roof, -17.0, 0xA700),
    ]
    for key, dur, fn, target, seed in specs:
        asset(key, "amb/" + key, loop=True)
        n = sec(dur)
        r = Rng(seed)
        t = np.arange(n) / SR
        T = n / SR
        # wolna, WSPÓLNA dla L/R zmienność (podmuch / szelest) — całkowite liczby cykli
        shared = 0.55 + 0.30 * np.sin(TAU * 1 * t / T + 0.4) + 0.20 * np.sin(TAU * 3 * t / T + 2.1) + 0.12 * np.sin(TAU * 8 * t / T)
        bed = d.stereo_noise_bed(lambda rr: fn(n, rr, shared), r, corr=0.25)
        finalize(key, bed, loop=True, lufs=target)

    asset("amb_drips", "amb/amb_drips", loop=True)
    n = sec(8.0)
    r = Rng(0xA400)
    bed = _drips(n, r)
    floor = d.stereo_noise_bed(lambda rr: d.circ_filter(d.colored(n, rr, 1.6), lambda z: d.lp(z, 300.0, order=2)) * 0.12, r)
    finalize("amb_drips", bed + floor, loop=True, lufs=-20.0)
