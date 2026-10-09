"""
bake_sfx.py — stalker, świat, gracz, UI.

Zasady projektowe (te same, co dla broni):
  * Głosy (stalker, człowiek) = ŹRÓDŁO GŁOSOWE (fala z jitterem) → FORMANTY (rezonanse traktu).
    Samo FM brzmi jak syntezator; formanty dają „usta".
  * Metal/szkło/dzwon = SYNTEZA MODALNA (tłumione sinusy o nieharmonicznych częstotliwościach),
    nie FM.
  * Kroki = dwa zdarzenia (pięta, palce) + materiał podłoża; każdy wariant ma inne tryby/ziarno.
  * Pętle = okresowe z konstrukcji (circ_filter / fold_loop) — brak szwu.
"""

from __future__ import annotations

import numpy as np

import audio_dsp as d
from audio_dsp import SR, Rng, ms, sec
from bake_common import (asset, burst, finalize, glottal, group, ir, ring, thump, tick, vary, vowel)

TAU = d.TAU


def _norm_std(x: np.ndarray) -> np.ndarray:
    return x / (np.std(x) + 1e-9)


# ============================================================ STALKER

def build_stalker() -> None:
    group("sfx/stalker")

    # Growl — niski, nieregularny „z piersi" (najczęściej słyszany dźwięk stalkera).
    # Źródło: vocal fry (okresy z dużym jitterem ~45–60 Hz) + AM-szorstkość 24–34 Hz,
    # przepuszczone przez formanty krtaniowe. Pod spodem sub-oktawa i dudnienie.
    for i in range(2):
        r = Rng(0xC100 + i * 5171)
        n = sec(3.4)
        t = np.arange(n) / SR
        drift = _norm_std(d.lp(d.white(n, r), 1.2))
        f0 = (46.0 + 6.0 * i) * (1.0 + 0.12 * drift)
        src = glottal(n, f0, r, jitter=0.05, shimmer=0.45, breath=0.12)
        rough = 0.6 + 0.4 * np.sin(TAU * np.cumsum(28.0 + 5.0 * drift) / SR)
        voiced = vowel(src * rough, "gutt", bw=6.0)
        sub = d.osc("sine", f0 * 0.5, n) * 0.5
        # oddechy: nieregularne wzmocnienia (nie metronom)
        env = np.zeros(n)
        k = int(r.integers(5, 8))
        for j in range(k):
            st = int(n * (0.0 if j == 0 else 0.84 * j / k + r.uniform(0.0, 0.04)))
            ln = n - st
            e = np.minimum(1.0, np.arange(ln) / ms(22)) * d.env_exp(ln, 0.28 + r.uniform(0.0, 0.25))
            env[st:] += e * (0.55 + r.uniform(0.0, 0.45))
        env *= d.env_exp(n, 1.5)
        hiss = d.filt(d.colored(n, r, 0.5), "bp", 1300.0, 0.8) * 0.5
        x = d.mix([(voiced * env, 1.0), (sub * env, 0.5), (hiss * env * (0.4 + 0.3 * drift ** 2), 0.5)], n)
        x = d.saturate(x, 2.0)
        x = d.reverb(x, ir("hall"), wet=0.30, keep_len=True)
        finalize("stalker_growl_%d" % (i + 1), x, lufs=-14.0, fade_out_ms=250)

    # Szept — pętla (okresowa): bezdźwięczny szum o płynnie zmieniających się formantach
    # („sss-ooo-eee" bez słów) + rytm sylab. Nie jest szumem statycznym: obwiednia ma 7 sylab/pętlę.
    asset("stalker_whisper_loop", "sfx/stalker/stalker_whisper_loop", loop=True)
    n = sec(4.2)
    r = Rng(0xC400)
    t = np.arange(n) / SR
    T = n / SR
    base = d.colored(n, r, 0.4)
    f1 = 520 + 260 * np.sin(TAU * 2 * t / T) + 90 * np.sin(TAU * 5 * t / T + 1.0)
    f2 = 1900 + 650 * np.sin(TAU * 3 * t / T + 0.7)
    tile3 = lambda a: np.tile(a, 3)
    v1 = d.circ_filter(base, lambda z: d.sweep(z, "bp", tile3(f1), 7.0))
    v2 = d.circ_filter(base, lambda z: d.sweep(z, "bp", tile3(f2), 9.0))
    hi = d.circ_filter(base, lambda z: d.hp(z, 3800.0)) * 0.35
    syl = np.abs(np.sin(np.pi * 7 * t / T)) ** 1.5 * (0.55 + 0.45 * np.sin(TAU * 3 * t / T + 2.1))
    syl = 0.18 + 0.82 * syl
    x = (v1 * 1.0 + v2 * 0.7 + hi * 0.5) * syl
    finalize("stalker_whisper_loop", x, loop=True, lufs=-14.0)

    # Krzyk — atak: źródło o wysokiej energii, glide w górę, wibrato, formanty krzyku, saturacja,
    # sub-uderzenie i pogłos hali. Nieprzewidywalny: dwa warianty z różnym konturem wysokości.
    for i in range(2):
        r = Rng(0xC800 + i * 2459)
        n = sec(1.1)
        t = np.arange(n) / SR
        contour = d.env_pts(n, [(0, 260), (.06, 420 + 60 * i), (.30, 780 - 80 * i), (.55, 640), (1.1, 330)])
        vib = 1.0 + 0.035 * np.sin(TAU * (6.0 + i) * t) * np.minimum(1.0, t / 0.2)
        src = glottal(n, contour * vib, r, jitter=0.02, shimmer=0.25, breath=0.20)
        sc = vowel(src, "a", bw=7.0) + 0.5 * vowel(src, "e", bw=8.0)
        env = d.env_pts(n, [(0, 0), (.012, 1), (.35, .9), (.7, .45), (1.1, 0)])
        nz = d.filt(d.white(n, r), "bp", 3200.0, 0.7) * d.env_perc(n, .003, .22)
        x = d.mix([(sc * env, 1.0), (nz, 0.45), (thump(.5, 90, 38, .1, .15), 0.9)], n)
        x = d.saturate(x * 1.4, 3.2)
        x = d.reverb(x, ir("hall"), wet=0.28, keep_len=True)
        finalize("stalker_shriek_%d" % (i + 1), x, lufs=-9.5, fade_out_ms=120)

    # Krok — ciężki, mokry: sub-uderzenie + chlupnięcie/chrzęst + ziarno; trzy warianty
    for i in range(3):
        r = Rng(0xCC00 + i * 4517)
        n = ms(420)
        th = thump(.20, vary(r, 78, .1), 36, .035, .06) * 1.2
        squelch = d.sweep(d.colored(ms(180), r, .8), "bp", d.glide_exp(1100, 380, ms(180), .05), 2.4) * d.env_perc(ms(180), .004, .05)
        crunch = tick(r, vary(r, 2600, .15), 1.0, 40, .008) * .5
        grit = d.filt(d.white(ms(260), r), "bp", vary(r, 3400, .15), .8) * d.env_exp(ms(260), .05) * .15
        x = d.mix([(th, 1.0), (squelch, .75, .006), (crunch, .6, .002), (grit, 1.0, .01)], n)
        x = d.saturate(d.reverb(x, ir("close"), wet=.2), 1.5)
        finalize("stalker_step_%d" % (i + 1), x, lufs=-19.0)

    # „Pojawienie się": odwrócony szum narastający + dudnienie + uderzenie
    r = Rng(0xCD00)
    n = ms(1100)
    swell = d.sweep(d.colored(n, r, 1.0), "bp", d.env_pts(n, [(0, 180), (.7, 3800), (1.1, 900)]), 1.6) * d.env_pts(n, [(0, 0), (.65, 1), (.7, .2), (1.1, 0)])
    hit = thump(.6, 85, 30, .12, .18) * 1.3
    x = d.mix([(swell, 1.0), (hit, 1.0, .68), (vowel(glottal(ms(500), 52, r, .05, breath=.2), "gutt") * d.env_exp(ms(500), .2), .8, .68)], n)
    finalize("stalker_appear", d.reverb(d.saturate(x, 1.8), ir("hall"), wet=.3), lufs=-13.0)

    # Odległy zew (ambient emiter, grany bardzo cicho z daleka): przefiltrowany szczyt krzyku
    for i in range(2):
        r = Rng(0xCE00 + i * 313)
        n = sec(2.2)
        contour = d.env_pts(n, [(0, 190), (.5, 330 + 60 * i), (1.2, 270), (2.2, 150)])
        t = np.arange(n) / SR
        src = glottal(n, contour * (1 + .02 * np.sin(TAU * 5.5 * t)), r, jitter=.02, breath=.25)
        x = vowel(src, "o", bw=8.0) * d.env_pts(n, [(0, 0), (.3, .8), (.9, 1), (1.6, .5), (2.2, 0)])
        x = d.lp(x, 1800.0, order=4)
        x = d.reverb(x, ir("cave"), wet=.7, keep_len=False)
        finalize("amb_far_cry_%d" % (i + 1), x, lufs=-26.0, fade_out_ms=400)


# ============================================================ ŚWIAT

def build_world() -> None:
    group("sfx/world")

    # Drzwi (metal): skrzyp tarcia (nieregularne stick-slip) + zatrzask
    for i in range(2):
        r = Rng(0xD100 + i * 3121)
        n = ms(900)
        t = np.arange(n) / SR
        f = d.env_pts(n, [(0, 420 - 60 * i), (.3, 610), (.55, 540), (.62, 300)])
        stick = np.abs(np.sin(TAU * (9 + 3 * i) * t + 1.5 * np.sin(TAU * 1.3 * t)))
        sq = d.osc("saw", f * (1 + .02 * np.sin(TAU * 7.7 * t)), n) * stick
        sq = d.filt(sq, "bp", 1500.0, 0.9) + .3 * d.sweep(d.colored(n, r, 1), "bp", f * 2.4, 3.0)
        sq *= d.env_pts(n, [(0, 0), (.04, .7), (.5, .8), (.62, .1), (.9, 0)])
        latch = d.mix([(tick(r, 1800, 1.5, 20, .005), 1.0), (ring(r, [vary(r, 420, .1), vary(r, 1190, .1), vary(r, 2650, .1)], [.25, .16, .08], dur=.5), .8),
                       (thump(.12, 150, 70, .03, .04), .8)])
        x = d.mix([(sq, .8), (latch, 1.0, .64)], n)
        finalize("door_%d" % (i + 1), d.reverb(x, ir("metal"), wet=.22), lufs=-20.0)

    # Generator — pętla okresowa (2,4 s: 50 Hz × 120 cykli, zapłon 12,5 Hz × 30)
    asset("generator_loop", "sfx/world/generator_loop", loop=True)
    n = sec(2.4)
    r = Rng(0xD200)
    t = np.arange(n) / SR
    hum = sum(a * np.sin(TAU * 50.0 * h * t + p) for h, a, p in ((1, 1.0, 0), (2, .6, .7), (3, .35, 1.3), (5, .18, 2.1)))
    fire = np.maximum(0, np.sin(TAU * 12.5 * t)) ** 6                              # cylinder pulses
    thud = d.circ_filter(fire, lambda z: d.lp(z, 220.0))
    rattle = d.circ_filter(d.colored(n, r, 1.0), lambda z: d.bp(z, 900.0, 0.8)) * (0.4 + 0.6 * fire)
    x = d.mix([(hum, .45), (thud, 1.4), (rattle, .7)], n)
    finalize("generator_loop", x, loop=True, lufs=-14.0)

    # Dzwon alarmowy — dzwon kościelny: częściowe nieharmoniczne + uderzenie, długi zanik
    r = Rng(0xD300)
    base = 196.0
    ratios = [0.5, 1.0, 1.19, 1.56, 2.0, 2.51, 3.2, 4.07]
    t60s = [3.2, 3.8, 2.4, 2.0, 1.4, 1.0, .6, .4]
    amps = [.6, 1.0, .75, .55, .5, .35, .2, .12]
    bell = ring(r, [base * k for k in ratios], t60s, amps, dur=4.0, jitter=.002)
    strike = tick(r, 3000, 1.0, 14, .004)
    x = d.mix([(bell, 1.0), (strike, .6), (thump(.2, 180, 80, .03, .05), .4)], sec(4.0))
    finalize("alarm_bell", d.reverb(x, ir("hall"), wet=.3), lufs=-12.0, fade_out_ms=400)

    # Flara: zapłon (fwoosh) + syk/trzask (pętla)
    r = Rng(0xD400)
    n = ms(700)
    ign = d.sweep(d.colored(n, r, .7), "bp", d.env_pts(n, [(0, 400), (.15, 2800), (.7, 1600)]), 1.0) * d.env_pts(n, [(0, 0), (.04, 1), (.2, .6), (.7, 0)])
    pop = thump(.12, 190, 80, .02, .03) + 0
    finalize("flare_ignite", d.reverb(d.mix([(ign, 1.0), (pop, .6)]), ir("room"), wet=.15), lufs=-16.0)

    asset("flare_loop", "sfx/world/flare_loop", loop=True)
    n = sec(3.0)
    r = Rng(0xD410)
    hiss = d.circ_filter(d.colored(n, r, .3), lambda z: d.bp(d.hp(z, 1800.0), 5000.0, .4)) * 0.8
    flick = 0.8 + 0.2 * np.sin(TAU * 4 * np.arange(n) / n) + 0.1 * np.sin(TAU * 11 * np.arange(n) / n + 1)
    crack = np.zeros(n)
    for _ in range(46):
        k = int(r.integers(0, n - ms(8)))
        crack[k:k + ms(5)] += tick(r, r.uniform(2500, 7500), 1.5, 5, .001)[:ms(5)] * r.uniform(.2, .8)
    x = d.mix([(hiss * flick, 1.0), (crack, .7)], n)
    finalize("flare_loop", x, loop=True, lufs=-12.0)

    # Szyba: uderzenie + wysypanie odłamków (setki mikro-dzwonków, krótkie, losowe tony)
    for i in range(2):
        r = Rng(0xD500 + i * 3571)
        n = ms(1500)
        crash = d.filt(d.white(ms(220), r), "hp", (1800, 1100)[i], order=2) * d.env_perc(ms(220), .0004, .045) * 2.0
        shards = np.zeros(n)
        for _ in range((60, 130)[i]):
            tt = (r.uniform() ** 1.5) * 1.2 + .005
            k = ms(tt * 1000)
            f = r.uniform(2800, 9500)
            seg = ring(r, [f, f * 1.47], [r.uniform(.03, .18), .03], dur=.2)[:n - k]
            shards[k:k + len(seg)] += seg * r.uniform(.06, .5) * np.exp(-tt * 1.8)
        thump_ = thump(.15, 160, 70, .03, .05) * .5
        x = d.mix([(crash, 1.0), (shards, 1.0), (thump_, .4)], n)
        finalize("glass_break_%d" % (i + 1), d.reverb(x, ir("room"), wet=.25), lufs=-20.0)

    # Radio: szum eteru (pętla) + sygnał
    asset("radio_static_loop", "sfx/world/radio_static_loop", loop=True)
    n = sec(2.4)
    r = Rng(0xD600)
    t = np.arange(n) / SR
    st = d.circ_filter(d.colored(n, r, .1), lambda z: d.bp(z, 3000.0, .5))
    crackle = np.zeros(n)
    for _ in range(40):
        k = int(r.integers(0, n - ms(6)))
        crackle[k:k + ms(4)] += tick(r, r.uniform(1500, 6500), 1.2, 4, .001)[:ms(4)] * r.uniform(.3, 1.0)
    swell = 0.55 + 0.45 * np.sin(TAU * 3 * t / (n / SR) + 1.0)
    finalize("radio_static_loop", d.mix([(st * swell, 1.0), (crackle, .6)], n), loop=True, lufs=-14.0)

    r = Rng(0xD700)
    n = ms(220)
    b = d.osc("square", 880.0, n) * d.env_adsr(n, .003, .02, .75, .05)
    b = d.filt(b, "lp", 3200.0)
    x = d.mix([(b, 1.0), (tick(r, 3000, 1.2, 14, .003), .4)], n)
    finalize("radio_beep", d.reverb(x, ir("dead"), wet=.1), peak=-1.5)

    # Mina kierunkowa: sygnał 1760 Hz, 0,2 s co 0,5 s — pętla dokładnie 4 impulsów
    asset("mine_beep_loop", "sfx/world/mine_beep_loop", loop=True)
    n = sec(2.0)
    t = np.arange(n) / SR
    gate = ((t % .5) < .12).astype(float)
    gate = d.lp(gate, 600.0)
    tone = d.osc("sine", 1760.0, n) + .3 * d.osc("sine", 3520.0, n)
    finalize("mine_beep_loop", tone * gate, loop=True, lufs=-19.0)

    # Taśma: zatrzymanie — pitch ↓ do zera (czytanie z malejącą prędkością) + wow
    r = Rng(0xD800)
    n = ms(1100)
    t = np.arange(n) / SR
    speed = np.exp(-t / .32)
    ph = np.cumsum(speed) / SR
    src = (d.osc("saw", 220.0 * np.ones(n), n) * 0.3 + np.sin(TAU * 110.0 * (ph * 1.0)) * .6)
    src2 = np.sin(TAU * 440.0 * ph) * .5 + np.sin(TAU * 880.0 * ph) * .2
    nz = d.lp(d.colored(n, r, .5), 4000.0) * .15
    x = (src2 + np.sin(TAU * 110.0 * ph) * .6 + nz) * d.env_pts(n, [(0, 1), (.5, .7), (1.1, 0)]) * speed ** .5
    x = d.saturate(x, 1.5)
    finalize("tape_stop", d.reverb(x, ir("dead"), wet=.1), lufs=-15.0)

    # Drgania ziemi / odległy huk (ambient emiter)
    for i in range(2):
        r = Rng(0xD900 + i * 7001)
        n = sec(3.2)
        boom = thump(2.2, 62 - 8 * i, 26, .5, .7, attack=.02) * 1.3
        rum = d.sweep(d.colored(n, r, 2.0), "lp", d.glide_exp(200, 60, n, 1.0), .8) * d.env_pts(n, [(0, 0), (.1, 1), (1.4, .4), (3.2, 0)])
        x = d.mix([(boom, 1.0), (rum, .7)], n)
        finalize("amb_thud_%d" % (i + 1), d.reverb(x, ir("cave"), wet=.35), lufs=-24.0, fade_out_ms=500)

    # Skrzypienie konstrukcji (drewno/metal) — ambient emiter: powolny glissando modalny
    for i in range(3):
        r = Rng(0xDA00 + i * 4129)
        n = sec(2.4)
        t = np.arange(n) / SR
        if i < 2:           # drewno: tarcie z wolnym przesunięciem
            f = d.env_pts(n, [(0, 150 + 40 * i), (.8, 210 + 30 * i), (1.6, 175), (2.4, 140)])
            stick = np.abs(np.sin(TAU * (7 + 2 * i) * t * (1 + .2 * np.sin(TAU * .9 * t)))) ** 2
            y = d.osc("saw", f, n) * stick
            y = d.filt(y, "bp", 520.0 + 150 * i, 1.8)
        else:               # metal: modalny jęk
            f0 = 95.0
            y = ring(r, [f0, f0 * 2.76, f0 * 5.4, f0 * 8.9], [1.6, 1.0, .6, .3], dur=2.4, jitter=.01)
            y = y * (1 + .3 * np.sin(TAU * 3.1 * t))
        y *= d.env_pts(n, [(0, 0), (.25, 1), (1.4, .7), (2.4, 0)])
        finalize("amb_creak_%d" % (i + 1), d.reverb(y, ir("hall"), wet=.3), lufs=-26.0, fade_out_ms=300)

    # Poryw wiatru (ambient emiter): swell szumu pasmowego z gwizdem
    for i in range(3):
        r = Rng(0xDB00 + i * 877)
        n = sec(4.0 + i)
        t = np.arange(n) / SR
        env = np.sin(np.pi * t / (n / SR)) ** 2
        fc = 380 + 520 * env
        x = d.sweep(d.colored(n, r, 1.0), "bp", fc, 1.1) * env
        x += 0.12 * d.sweep(d.white(n, r), "bp", 1200 + 900 * env + 80 * np.sin(TAU * .7 * t), 22.0) * env ** 2
        finalize("amb_gust_%d" % (i + 1), x, lufs=-28.0, fade_out_ms=500)


    # Grzmot (pogoda STORM): [0] blisko — trzask i krótki, ostry rumor; [1] średnio; [2] daleko — sam turlający się pomruk
    for i in range(3):
        r = Rng(0xDC00 + i * 911)
        dur = (4.5, 5.8, 7.2)[i]
        n = sec(dur)
        t = np.arange(n) / SR
        # turlający się rumor: kilka garbów o losowych czasach, zanik wykładniczy
        env = np.zeros(n)
        for j in range(5 + 2 * i):
            c = 0.02 if j == 0 else r.uniform(0.1, dur * 0.7)         # pierwszy garb zaraz na starcie (bez ciszy na początku pliku)
            w = r.uniform(0.25, 0.8)
            env += r.uniform(0.3, 1.0) * np.exp(-np.maximum(t - c, 0.0) / w) * (t >= c)
        env = env / (np.max(env) + 1e-9) * np.exp(-t / (dur * 0.55))
        cut = (300.0, 220.0, 150.0)[i]
        rumble = d.lp(d.colored(n, r, 1.9), cut, order=3) * env
        sub = np.sin(TAU * (38.0 + 9 * i) * t * (1.0 - 0.1 * t / dur)) * env * (0.9 - 0.2 * i)
        parts = [(rumble, 1.0), (sub, 0.45)]
        if i < 2:               # trzask: ostry szum szerokopasmowy z szybkim zanikiem (bliżej = mocniejszy)
            cm = ms(240)
            crack = d.filt(d.white(cm, r), "bp", 1400.0 + 600 * i, 0.5) * d.env_perc(cm, 0.0002, 0.05 + 0.03 * i)
            crack = np.concatenate([crack, np.zeros(n - cm)])
            parts.append((crack, 1.4 - 0.5 * i))
        x = d.mix(parts, n)
        finalize("thunder_%d" % (i + 1), d.reverb(x, ir("hall"), wet=0.35), lufs=-17.0, fade_out_ms=900)


# ============================================================ GRACZ

def _step_concrete(r: Rng) -> np.ndarray:
    n = ms(260)
    heel = d.mix([(tick(r, vary(r, 2400, .2), 1.1, 14, .004), 1.0), (thump(.07, vary(r, 135, .12), 70, .02, .025), .9),
                  (ring(r, [vary(r, 700, .2), vary(r, 1450, .2)], [.04, .025], dur=.12), .25)])
    toe = d.mix([(tick(r, vary(r, 1900, .2), .9, 10, .003), .55), (thump(.04, 160, 95, .015, .015), .35)])
    scuff = d.filt(d.white(ms(70), r), "bp", vary(r, 3500, .2), .6) * d.env_exp(ms(70), .018) * .2
    return d.mix([(heel, 1.0, 0.0), (toe, 1.0, r.uniform(.055, .085)), (scuff, 1.0, .012)], n)


def _step_metal(r: Rng) -> np.ndarray:
    n = ms(480)
    f0 = vary(r, 330, .25)
    modes = [f0 * k * (1 + r.bipolar(.03)) for k in (1.0, 2.32, 3.9, 5.6, 7.7)]
    plate = ring(r, modes, [.22, .16, .12, .08, .05], [1.0, .7, .5, .35, .25], dur=.4, jitter=0)
    heel = d.mix([(tick(r, vary(r, 3800, .2), 1.3, 12, .0035), 1.0), (thump(.06, 160, 90, .02, .02), .6), (plate, .8)])
    toe = d.mix([(tick(r, vary(r, 3000, .2), 1.3, 10, .003), .5), (plate, .25)])
    return d.mix([(heel, 1.0, 0.0), (toe, 1.0, r.uniform(.06, .09))], n)


def _step_dirt(r: Rng) -> np.ndarray:
    n = ms(300)
    thud = d.filt(d.white(ms(110), r), "lp", vary(r, 520, .2), order=2) * d.env_perc(ms(110), .003, .03) * 2.2
    body = thump(.09, vary(r, 95, .15), 55, .025, .03) * .5
    crunch = np.zeros(n)
    for _ in range(int(r.integers(5, 10))):
        k = ms(r.uniform(5, 160))
        crunch[k:k + ms(10)] += tick(r, r.uniform(2800, 7500), 1.0, 10, .002)[:ms(10)] * r.uniform(.08, .3)
    heel = d.mix([(thud, 1.0), (body, 1.0), (crunch, 1.0)])
    toe = d.mix([(d.filt(d.white(ms(80), r), "lp", 700.0) * d.env_perc(ms(80), .003, .02) * 1.2, 1.0), (crunch[:ms(80)], .6)])
    return d.mix([(heel, 1.0, 0.0), (toe, .6, r.uniform(.06, .09))], n)


def _step_water(r: Rng) -> np.ndarray:
    n = ms(550)
    splash = d.sweep(d.colored(ms(300), r, .6), "bp", d.glide_exp(1200, 3600, ms(300), .08), .8) * d.env_pts(ms(300), [(0, 0), (.012, 1), (.1, .45), (.3, 0)])
    low = d.filt(d.white(ms(180), r), "lp", 420.0) * d.env_perc(ms(180), .004, .05) * 2.0
    parts = [(splash, .9), (low, .9), (thump(.08, 120, 60, .025, .03), .5)]
    for _ in range(int(r.integers(2, 5))):              # bąble
        k = r.uniform(.03, .32)
        f0 = r.uniform(500, 1200)
        bn = ms(r.uniform(20, 50))
        bub = d.osc("sine", d.glide(f0, f0 * 2.2, bn), bn) * d.env_perc(bn, .002, bn / SR * .35) * r.uniform(.15, .4)
        parts.append((bub, 1.0, k))
    return d.mix(parts, n)


def build_player() -> None:
    group("sfx/player")
    surfaces = ((0xE100, "concrete", _step_concrete, -21.5), (0xE200, "metal", _step_metal, -21.5),
                (0xE300, "dirt", _step_dirt, -23.0), (0xE400, "water", _step_water, -20.0))
    for seed, name, fn, target in surfaces:
        for i in range(5):
            r = Rng(seed + i * 7717)
            finalize("step_%s_%d" % (name, i + 1), fn(r), lufs=target)

    # Lądowanie z wysokości: uderzenie ciała + ekwipunek
    r = Rng(0xE500)
    x = d.mix([(thump(.2, 120, 50, .03, .06), 1.2), (d.filt(d.white(ms(150), r), "lp", 900.0) * d.env_perc(ms(150), .002, .04) * 2, .9),
               (tick(r, 2200, 1.0, 20, .005), .5), (ring(r, [2900, 4400, 6100], [.06, .04, .03], dur=.2), .18, .012)], ms(450))
    finalize("land_hard", d.reverb(x, ir("close"), wet=.15), lufs=-17.5)

    # Wysiłek (wydech przy skoku): krótki bezdźwięczny „hh-ah" z lekką dźwięcznością
    for i in range(2):
        r = Rng(0xE600 + i * 2749)
        n = ms(380)
        src = d.colored(n, r, .4)
        vw = ("a", "o")[i]
        a = vowel(src, vw, bw=5.0) * .5
        voiced = vowel(glottal(n, d.env_pts(n, [(0, (135, 168)[i]), (.3, (108, 130)[i])]), r, jitter=.02, breath=.5), vw, bw=6.0) * .55
        x = (a + voiced) * d.env_pts(n, [(0, 0), (.035, 1), (.12, .7), (.38, 0)])
        finalize("effort_%d" % (i + 1), d.reverb(x, ir("dead"), wet=.1), lufs=-16.0)

    # Krzyk bólu: źródło głosowe + wibrato, formanty „a→o", lekka saturacja
    for i in range(2):
        r = Rng(0xE700 + i * 1871)
        dur = (0.62, 0.42)[i]
        n = ms(dur * 1000)
        t = np.arange(n) / SR
        pts = ([(0, 180), (.08, 270), (.25, 235), (.62, 160)], [(0, 250), (.05, 330), (.18, 280), (.42, 200)])[i]
        f0 = d.env_pts(n, pts) * (1 + .012 * np.sin(TAU * (6.5 + 2 * i) * t))
        src = glottal(n, f0, r, jitter=.015 + .01 * i, shimmer=.15, breath=.18 + .1 * i)
        v1, v2 = (("a", "o"), ("e", "a"))[i]
        y = vowel(src, v1, bw=6.0) * (1 - .4 * (t / dur)) + vowel(src, v2, bw=7.0) * (.4 * (t / dur))
        y *= d.env_pts(n, [(0, 0), (.02, 1), (.2 * dur / .62, .85), (.45 * dur / .62, .5), (dur, 0)])
        y = d.saturate(y * 1.3, 1.6)
        finalize("player_hurt_%d" % (i + 1), d.reverb(y, ir("close"), wet=.15), lufs=-9.0)

    # Upadek (down): długie jęknięcie opadające + uderzenie ciała
    r = Rng(0xE800)
    n = sec(1.3)
    t = np.arange(n) / SR
    f0 = d.env_pts(n, [(0, 210), (.2, 240), (.7, 150), (1.3, 85)]) * (1 + .02 * np.sin(TAU * 5.5 * t))
    src = glottal(n, f0, r, jitter=.03, shimmer=.25, breath=.25)
    y = vowel(src, "o", bw=6.0) * d.env_pts(n, [(0, 0), (.03, 1), (.5, .8), (1.0, .35), (1.3, 0)])
    fall = d.mix([(thump(.22, 110, 45, .04, .07), 1.2), (d.filt(d.white(ms(250), r), "lp", 800.0) * d.env_perc(ms(250), .003, .06) * 2, .8),
                  (ring(r, [2700, 4100, 5900], [.08, .05, .03], dur=.3), .15, .02)])
    x = d.mix([(y, 1.0), (fall, 1.0, .55)], n)
    finalize("player_down", d.reverb(d.saturate(x, 1.3), ir("room"), wet=.2), lufs=-12.0, fade_out_ms=200)

    # Podniesienie: gwałtowny wdech + ciepły, narastający interwał kwinty (nadzieja)
    r = Rng(0xE900)
    n = sec(1.1)
    t = np.arange(n) / SR
    inh = d.sweep(d.colored(n, r, .5), "bp", d.env_pts(n, [(0, 700), (.3, 1500)]), 1.3) * d.env_pts(n, [(0, 0), (.18, .9), (.32, 0)]) * 1.3
    chord = (d.osc("sine", 220.0, n) + .6 * d.osc("sine", 330.0, n) + .3 * d.osc("sine", 440.0, n)) * d.env_pts(n, [(0, 0), (.25, 0), (.55, .8), (1.1, 0)])
    chord = d.lp(d.mix([(chord, 1.0)]), 1800.0)
    x = d.mix([(inh, 1.0), (chord, .6)], n)
    finalize("revive", d.reverb(x, ir("room"), wet=.25), lufs=-21.0, fade_out_ms=200)

    # Serce — „lub-dub": każde uderzenie to dwa sub-impulsy z opadającą wysokością; pętla = 4 uderzenia
    for key, bpm in (("heart_fast_loop", 132.0), ("heart_slow_loop", 74.0)):
        asset(key, "sfx/player/" + key, loop=True)
        beat = 60.0 / bpm
        loop_n = int(round(4 * beat * SR))
        gap = 0.09 + 0.25 * beat
        lub = d.mix([(thump(.20, 72, 42, .045, .07), 1.0), (d.filt(d.white(ms(70), Rng(1)), "lp", 240.0) * d.env_perc(ms(70), .003, .016) * 1.5, .5)])
        dub = d.mix([(thump(.18, 62, 38, .04, .06), .7), (d.filt(d.white(ms(60), Rng(2)), "lp", 200.0) * d.env_perc(ms(60), .003, .014) * 1.3, .35)])
        buf = np.zeros(loop_n + sec(1.0))
        for b in range(4):
            k = int(round(b * beat * SR))
            s = 1.0 if b % 2 == 0 else .86
            buf[k:k + len(lub)] += lub * s
            k2 = k + int(round(gap * SR))
            buf[k2:k2 + len(dub)] += dub * s
        x = d.saturate(d.fold_loop(buf, loop_n), 1.6)
        finalize(key, x, loop=True, lufs=-14.5)

    # Oddech przy wysiłku — pętla 3,0 s = 4 cykle wdech/wydech (0,75 s), okresowa
    asset("breath_loop", "sfx/player/breath_loop", loop=True)
    n = sec(3.0)
    r = Rng(0xEA00)
    base = d.colored(n, r, .6)
    ex = d.circ_filter(base, lambda z: vowel(z, "a", bw=4.0)) * 1.0
    cyc = n // 4
    env = np.zeros(n)
    for b in range(4):
        s = b * cyc
        inh = d.env_pts(cyc, [(0, 0), (.20, .55), (.31, 0)]) * .6
        exh = d.env_pts(cyc, [(.30, 0), (.36, 1), (.52, .5), (.75, 0)])
        env[s:s + cyc] = (inh + exh)[:cyc]
    env = d.circ_filter(env, lambda z: d.lp(z, 60.0))
    finalize("breath_loop", ex * (0.05 + env), loop=True, lufs=-14.0)


# ============================================================ UI

def build_ui() -> None:
    group("sfx/ui")
    r = Rng(0xF000)

    # Klik: sprężysty „przełącznik" lat 80.
    x = d.mix([(tick(r, 3200, 1.6, 12, .003), 1.0), (d.osc("sine", 1250.0, ms(40)) * d.env_perc(ms(40), .0005, .008), .4)], ms(70))
    finalize("ui_click", d.reverb(x, ir("dead"), wet=.08), peak=-1.5)

    # Potwierdzenie: dwa wznoszące syntezatorowe bliki (kwarta) z krótkim echem
    def blip(f, dur, lpf):
        n = ms(dur)
        s = d.osc("saw", f, n) * .5 + d.osc("square", f * 1.003, n, pw=.35) * .5
        s = d.sweep(s, "lp", d.glide_exp(lpf, lpf * .3, n, dur / 1000 * .4), 1.8)
        return s * d.env_adsr(n, .003, .03, .6, .05)
    x = d.mix([(blip(587.0, 110, 5200.0), 1.0, 0.0), (blip(784.0, 150, 6500.0), 1.0, .085)], ms(320))
    x = d.echo_tail(x, [140, 280], [.25, .1], 3500.0)
    finalize("ui_confirm", x, peak=-1.5)

    # Odmowa: niski, matowy podwójny buczek
    def buzz(f, dur):
        n = ms(dur)
        s = d.osc("square", f, n, pw=.4)
        return d.filt(s, "lp", 900.0) * d.env_adsr(n, .004, .03, .7, .04)
    finalize("ui_deny", d.mix([(buzz(150.0, 90), 1.0, 0.0), (buzz(118.0, 130), 1.0, .11)], ms(260)), peak=-1.5)

    # Ostrzeżenie o stalkerze: niski „sonar" 180 Hz z pogłosem
    n = ms(520)
    p = d.osc("sine", d.glide_exp(210, 165, n, .12), n) * d.env_perc(n, .012, .12)
    p += .35 * d.osc("sine", d.glide_exp(420, 330, n, .12), n) * d.env_perc(n, .012, .08)
    finalize("warn_pulse", d.reverb(p, ir("room"), wet=.25), peak=-1.5, fade_out_ms=60)

    # Ładowanie Przesterowania: narastający sweep piły z ratchetem
    n = ms(520)
    t = np.arange(n) / SR
    f = d.glide_exp(130, 960, n, .35) * 0 + d.env_pts(n, [(0, 130), (.5, 980)])
    s = d.osc("saw", f, n) * (0.6 + 0.4 * (np.sin(TAU * 38 * t) > 0))
    s = d.sweep(s, "lp", d.env_pts(n, [(0, 400), (.5, 5200)]), 2.0)
    nz = d.sweep(d.white(n, r), "bp", d.env_pts(n, [(0, 800), (.5, 5000)]), 1.5) * .35
    x = (s + nz) * d.env_pts(n, [(0, 0), (.03, 1), (.4, .8), (.52, 0)])
    finalize("oc_load", d.saturate(x, 1.6), peak=-1.5)
