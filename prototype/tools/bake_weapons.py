"""
bake_weapons.py — bronie, trafienia, wybuchy, foley wokół strzelania.

Strzał to nie „szum + sinus": składa się z warstw o różnym czasie życia, które ucho
rozpoznaje osobno (tak je zresztą nagrywa się w studiu i miksuje w silniku):

  1. CRACK    0–2 ms     szerokopasmowy transjent HF — „twardość", kierunek, odległość
  2. BLAST    2–40 ms    szum z opadającym LP (jasny → ciemny): front fali ciśnienia
  3. BODY     0–150 ms   sinus z opadającą wysokością (180→55 Hz): kopnięcie w klatkę
  4. PUNCH    5–60 ms    pasmo 300–700 Hz: „mięso" — to, co czyni strzał głośnym przy małym peaku
  5. MECH     10–30 ms   metaliczny klik zamka/iglicy z własnym rezonansem
  6. TAIL     30–400 ms  krótki ogon źródła (zamknięty pokój). Pogłos ŚRODOWISKOWY dokłada
                         silnik (szyna Reverb) — tu nie pieczemy hali, bo ta sama próbka gra
                         w lesie, w korytarzu i w jaskini.

Każdy wariant dostaje inne ziarno szumu, rozrzut parametrów (±8–12%), inny moment mechaniki
i własny ogon — przy ogniu ciągłym 10 strz./s unika to „efektu karabinu maszynowego"
(powtarzalnej próbki), którego sam pitch-jitter w silniku nie usuwa.
"""

from __future__ import annotations

import numpy as np

import audio_dsp as d
from audio_dsp import Rng, ms
from bake_common import (asset, burst, finalize, group, ir, ring, thump, tick, vary)


def gun(rng: Rng, *, body=(190.0, 55.0), body_tau=0.028, body_dur=0.16, crack_f=3200.0,
        crack_amt=1.0, blast=(9000.0, 1300.0), blast_tau=0.022, blast_amt=1.0,
        punch_f=450.0, punch_amt=0.6, mech=0.5, mech_f=3400.0, tail_rt=0.35, tail_wet=0.28,
        drive=1.8, dur=0.42, pellets=1, sub=0.0) -> np.ndarray:
    n = ms(dur * 1000)
    layers = []

    # 1. crack (pellets>1: kilka rozsuniętych o ułamki ms — „rozprysk" śrutu)
    for k in range(pellets):
        cn = ms(10)
        ck = d.filt(d.white(cn, rng), "hp", crack_f * 0.7, order=4) * d.env_perc(cn, 0.00005, 0.0012) * 5.0
        layers.append((ck, 1.5 * crack_amt * (1.0 if k == 0 else 0.6), k * rng.uniform(0.0004, 0.0016)))

    # 2. blast
    layers.append((burst(ms(180), rng, blast[0], blast[1], blast_tau, color=0.25), 1.35 * blast_amt))

    # 3. body
    layers.append((thump(body_dur, body[0], body[1], body_tau, body_tau * 1.5), 0.55))
    if sub > 0.0:                                            # dodatkowy sub (strzelba)
        layers.append((thump(0.35, 70.0, 28.0, 0.07, 0.11), sub * 0.6))

    # 4. punch
    pn = ms(70)
    punch = d.filt(d.white(pn, rng), "bp", punch_f, 0.8) * d.env_exp(pn, 0.014)
    layers.append((punch, punch_amt * 1.4))

    # 5. mechanika: klik + rezonans metalu
    mn = ms(60)
    mk = tick(rng, mech_f, 2.2, 12.0, 0.002)
    mr = d.modal([mech_f * 0.62, mech_f * 1.38, mech_f * 2.1], [0.6, 0.4, 0.2], [0.018, 0.012, 0.008], mn, rng, 0.02)
    layers.append((d.mix([(mk, 0.7), (mr, 0.3)]), mech, rng.uniform(0.010, 0.024)))

    x = d.mix(layers, n)
    x = d.filt(x, "hp", 38.0, order=4)
    x = d.saturate(x, drive)
    wet = d.make_ir(tail_rt, rng.fork(5), size=0.5 + tail_rt, damping=0.5, pre_ms=3.0, stereo=False)
    return d.reverb(x, wet, wet=tail_wet, dry=1.0)


def build_weapons() -> None:
    group("sfx/weapons")

    # M-83 „Krótki" — SMG 600 RPM: suchy, krótki, kontrolowany (długie serie nie męczą)
    for i in range(6):
        r = Rng(0x1100 + i * 104729)
        x = gun(r, body=(vary(r, 175, .10), vary(r, 58, .08)), body_tau=vary(r, .026, .12),
                crack_f=vary(r, 3000, .12), blast=(vary(r, 8200, .1), vary(r, 1200, .15)),
                blast_tau=vary(r, .018, .15), punch_f=vary(r, 480, .12), punch_amt=vary(r, .65, .15),
                mech=vary(r, .55, .2), mech_f=vary(r, 3300, .12), tail_rt=vary(r, .32, .2),
                tail_wet=vary(r, .24, .15), dur=0.30)
        finalize("m83_shot_%d" % (i + 1), x, lufs=-14.0)

    # P-64 „Igła" — sidearm: ostrzejszy crack, wyższy korpus, wyraźniejszy ogon
    for i in range(4):
        r = Rng(0x2100 + i * 15485863)
        x = gun(r, body=(vary(r, 235, .08), vary(r, 72, .08)), body_tau=vary(r, .022, .1),
                crack_f=vary(r, 4300, .1), crack_amt=1.25, blast=(vary(r, 10500, .08), vary(r, 1700, .12)),
                blast_tau=vary(r, .016, .12), punch_f=vary(r, 620, .1), punch_amt=.55,
                mech=vary(r, .6, .15), mech_f=vary(r, 4200, .1), tail_rt=vary(r, .48, .15),
                tail_wet=vary(r, .30, .12), drive=2.0, dur=0.36)
        finalize("p64_shot_%d" % (i + 1), x, lufs=-13.5)

    # SPREAD-12 — strzelba: ogromny sub, szeroki blast, 5 cracków śrutu, długi ogon
    for i in range(3):
        r = Rng(0x2900 + i * 7331)
        x = gun(r, body=(vary(r, (150, 130, 112)[i], .05), vary(r, (46, 38, 32)[i], .05)), body_tau=vary(r, (.034, .045, .06)[i], .05),
                body_dur=0.28, crack_f=vary(r, 2400, .1), crack_amt=1.1,
                blast=(vary(r, 6500, .1), vary(r, 700, .12)), blast_tau=vary(r, .040, .12),
                blast_amt=1.3, punch_f=vary(r, 330, .1), punch_amt=.95, mech=.35, mech_f=2100.0,
                tail_rt=(.55, .85, 1.25)[i], tail_wet=(.26, .34, .40)[i], drive=2.3, dur=0.75, pellets=5, sub=(.5, .8, 1.1)[i])
        finalize("spread12_shot_%d" % (i + 1), x, lufs=-13.5)

    # Przeładowanie: zwolnienie magazynka → wysunięcie → wsunięcie (stuk + klik) → przeładowanie zamka
    for i in range(3):
        r = Rng(0x3100 + i * 7919)
        f0 = vary(r, 2600, .1)
        rel = d.mix([(tick(r, f0, 2.5, 14, .003), 1.0), (ring(r, [f0 * .5, f0 * .93], [.02, .015], dur=.08), .5)])
        slide = d.filt(d.white(ms(140), r), "bp", vary(r, 1400, .1), 1.2) * d.env_curve(ms(140), 0, 1, 1.5) * d.env_exp(ms(140), .09)
        seat = d.mix([(thump(.09, 220, 90, .02, .03), 1.0), (tick(r, 1800, 1.4, 20, .004), .8)])
        mag_click = d.mix([(ring(r, [vary(r, 3600, .06), vary(r, 5300, .06)], [.03, .02], dur=.10), 1.0), (tick(r, 3000, 2, 10, .002), 1.0)])
        bolt_back = d.filt(d.white(ms(110), r), "bp", 900, 1.4) * d.env_perc(ms(110), .004, .05)
        bolt_snap = d.mix([(tick(r, vary(r, 2200, .08), 1.5, 14, .004), 1.0), (thump(.07, 260, 120, .015, .02), .5)])
        x = d.mix([(rel, 1.0, 0.0), (slide, 0.5, 0.05), (seat, 1.0, 0.30 + r.uniform(0, .03)),
                   (mag_click, 0.8, 0.38), (bolt_back, 0.7, 0.62), (bolt_snap, 1.0, 0.76)], ms(1000))
        x = d.reverb(x, ir("close"), wet=.14, dry=1.0)
        finalize("reload_%d" % (i + 1), x, peak=-3.0)

    # Suchy strzał (pusty magazyn) — sam bijak
    r = Rng(0x41)
    x = d.mix([(tick(r, 2800, 1.6, 14, .004), 1.0),
               (ring(r, [1900, 3700], [.02, .012], dur=.06), .3, .001),
               (thump(.06, 190, 110, .015, .02), .2, .002)], ms(90))
    finalize("dry_fire", d.reverb(x, ir("dead"), wet=.1), peak=-5.0)

    # Maczeta: zamach (dopplerowski przelot szumu) + opcjonalne cięcie
    for i in range(2):
        r = Rng(0x5100 + i * 31337)
        n = ms(380)
        sw = d.sweep(d.colored(n, r, .5), "bp", d.env_pts(n, [(0, 350), (.10, 1500 + i * 300), (.17, 3200), (.35, 700)]), q=1.6)
        sw = sw * d.env_pts(n, [(0, 0), (.08, .6), (.15, 1.0), (.26, .35), (.375, 0)]) ** 1.2
        cut = d.filt(d.white(ms(90), r), "bp", vary(r, 4200, .1), .9) * d.env_perc(ms(90), .0005, .02) * 3.0
        edge = ring(r, [vary(r, 5200, .05), vary(r, 7400, .05)], [.10, .06], dur=.2) * .25
        x = d.mix([(sw, 1.0), (cut, .8, .13), (edge, .5, .13)], n)
        finalize("maczeta_%d" % (i + 1), d.reverb(x, ir("close"), wet=.12), lufs=-19.0)

    # Pocisk przelatujący obok (non-pozycyjny, stereo): „zip" z dopplerem i panoramą.
    # Szum pasmowy, NIE ton — czysty sweep brzmi jak laser (wykryte na spektrogramie).
    for i, (pa, pb) in enumerate(((-.9, .9), (.9, -.9), (-.45, .35))):
        r = Rng(0x6100 + i * 8191)
        n = ms(190)
        fz = d.env_pts(n, [(0, 6800), (.03, 4600), (.08, 2800), (.19, 1500)])
        z = d.sweep(d.white(n, r), "bp", fz, q=1.1)
        z = z + 0.25 * d.sweep(d.colored(n, r, .6), "lp", fz * .7, q=.8)
        env = d.env_pts(n, [(0, 0), (.012, 1.0), (.05, .8), (.11, .35), (.19, 0)])
        zip_ = d.saturate(z * env, 1.6)
        th = (np.linspace(pa, pb, n) + 1.0) * np.pi / 4.0
        x = np.stack([zip_ * np.cos(th), zip_ * np.sin(th)])
        finalize("whizz_%d" % (i + 1), x, peak=-2.0)

    # Uderzenie pocisku w twardą powierzchnię: tarcie/odłamki + ton materiału
    for i in range(3):
        r = Rng(0x7100 + i * 6151)
        n = ms(260)
        hit = tick(r, vary(r, 3600, .12), 1.2, 14, .004) * 1.0
        thud = thump(.08, vary(r, 260, .15), 110, .015, .025) * .7
        mat = ring(r, [vary(r, 900, .2), vary(r, 1700, .2), vary(r, 2900, .2)], [.06, .04, .03], dur=.2) * .35
        deb = d.sweep(d.white(ms(160), r), "bp", d.glide_exp(5500, 2200, ms(160), .03), 1.0) * d.env_exp(ms(160), .035)
        # odłamki: kilka drobnych klików rozrzuconych po 20–120 ms
        sh = np.zeros(n)
        for _ in range(r.integers(3, 6)):
            k = ms(r.uniform(20, 140))
            sh[k:k + ms(6)] += tick(r, r.uniform(2500, 6500), 1.5, 6, .0012)[:ms(6)] * r.uniform(.15, .4)
        x = d.mix([(hit, 1.0), (thud, 1.0), (mat, 1.0), (deb, .35), (sh, 1.0)], n)
        finalize("impact_hard_%d" % (i + 1), d.reverb(x, ir("close"), wet=.18), lufs=-23.0)

    # Rykoszet: szum o wąskim paśmie opadającym (Doppler) + klik + rezonans metalu
    for i in range(2):
        r = Rng(0x8100 + i * 4099)
        n = ms(380)
        fz = d.env_pts(n, [(0, (5600, 3400)[i]), (.04, (4000, 2700)[i]), (.15, (2300, 1600)[i]), (.38, (1500, 1100)[i])])
        zing = d.sweep(d.white(n, r), "bp", fz * (1 + .02 * np.sin(np.arange(n) / d.SR * 2 * np.pi * (27, 41)[i])), q=(14.0, 7.0)[i])
        zing = zing * 3.0 * d.env_perc(n, .001, .09)
        x = d.mix([(zing, .55), (tick(r, 4200, 1.5, 12, .003), 1.0),
                   (ring(r, [vary(r, 2400, .1), vary(r, 3900, .1)], [.18, .10], dur=.3), .22),
                   (d.sweep(d.white(ms(120), r), "bp", d.glide_exp(7000, 2500, ms(120), .03), 1.2) * d.env_exp(ms(120), .03), .6)], n)
        finalize("ricochet_%d" % (i + 1), d.reverb(x, ir("room"), wet=.25), lufs=-17.0)

    # Trafienie w ciało (stwór): mokry „klaps" + miękki sub + chrzęst
    for i in range(3):
        r = Rng(0x9100 + i * 3571)
        n = ms(260)
        slap = d.filt(d.white(ms(70), r), "bp", vary(r, 900, .15), .7) * d.env_perc(ms(70), .001, .02) * 2.5
        sub = thump(.14, vary(r, 120, .1), 55, .03, .05) * 1.2
        sq = d.sweep(d.colored(ms(150), r, .8), "bp", d.glide_exp(1800, 500, ms(150), .05), 3.0) * d.env_perc(ms(150), .006, .045)
        crunch = tick(r, vary(r, 2400, .15), 1.0, 20, .005) * .5
        x = d.mix([(slap, 1.0), (sub, 1.0), (sq, .6, .012), (crunch, .6, .004)], n)
        finalize("impact_flesh_%d" % (i + 1), d.saturate(d.reverb(x, ir("close"), wet=.15), 1.6), lufs=-15.0)

    # Eksplozja: sub + napór + gruz; stereo (wielki, otacza słuchacza)
    for i in range(2):
        r = Rng(0xA100 + i * 7717)
        n = ms(2600)
        sub = thump(1.4, 78, 24, .28, .45, attack=.004) * 1.4
        body = d.sweep(d.colored(n, r, 1.2), "lp", d.glide_exp(4200, 110, n, .45), q=.9) * d.env_perc(n, .002, .38) * 2.0
        crack = d.filt(d.white(ms(40), r), "hp", 1500, order=3) * d.env_perc(ms(40), .0002, .006) * 3.0
        debris = np.zeros(n)
        for _ in range(70):
            tt = (r.uniform() ** 1.6) * 1.9 + .06
            k = ms(tt * 1000)
            ln = ms(r.uniform(3, 18))
            if k + ln < n:
                debris[k:k + ln] += tick(r, r.uniform(1800, 7000), 1.2, 18, .002)[:ln] * r.uniform(.05, .35) * np.exp(-tt * 1.4)
        rumble = d.sweep(d.colored(n, r, 2.0), "lp", 140.0 * np.ones(n), q=.8) * d.env_pts(n, [(0, 0), (.12, 1), (1.2, .5), (2.5, 0)]) * 1.6
        x = d.mix([(sub, 1.0), (body, 1.0), (crack, 1.0), (debris, 1.0), (rumble, .9)], n)
        x = d.saturate(x, 1.9)
        x = d.reverb(x, ir("hall_st"), wet=.38, keep_len=True)
        finalize("explosion_%d" % (i + 1), x, peak=-1.5, fade_out_ms=120)

    # Łuski na ziemi: sprężysty ping mosiądzu z odbiciami (≈ 0,25–0,4 s po strzale)
    for i in range(3):
        r = Rng(0xB100 + i * 2111)
        f = vary(r, 4300, .18)
        n = ms(420)
        x = np.zeros(n)
        t_b, amp = 0.0, 1.0
        for b in range(r.integers(3, 5)):
            tp = ring(r, [f * (1 + .02 * b), f * 1.52, f * 2.31], [.07, .05, .03], dur=.15)
            k0 = ms(t_b * 1000)
            seg = tp[:max(0, n - k0)]
            x[k0:k0 + len(seg)] += seg * amp
            t_b += (.085 - .018 * b) * r.uniform(.8, 1.2)
            amp *= .5
        x[:ms(6)] += tick(r, 5500, 1.5, 6, .0012)[:ms(6)] * .3
        finalize("casing_brass_%d" % (i + 1), d.reverb(x, ir("dead"), wet=.15), peak=-6.0)
    for i in range(2):
        r = Rng(0xB200 + i * 3023)
        n = ms(380)
        hull = ring(r, [vary(r, 1250, .1), vary(r, 2300, .1)], [.045, .03], dur=.14)
        base = ring(r, [vary(r, 3100, .1), vary(r, 4900, .1)], [.08, .05], dur=.2) * .5
        x = d.mix([(d.mix([(hull, 1.0), (tick(r, 900, 1.2, 14, .004), .8)]), 1.0), (base, .8, .004),
                   (hull * .45, 1.0, .11), (base * .3, 1.0, .12)], n)
        finalize("casing_shell_%d" % (i + 1), d.reverb(x, ir("dead"), wet=.15), peak=-6.0)

    # Foley ekwipunku (podczas biegu): pasy, klamry, magazynki
    for i in range(3):
        r = Rng(0xB300 + i * 1999)
        n = ms(300)
        cloth = d.sweep(d.colored(n, r, 1.0), "bp", d.glide(vary(r, 900, .2), vary(r, 1600, .2), n), 1.0) * d.env_pts(n, [(0, 0), (.04, .8), (.10, .4), (.28, 0)]) * .6
        x = cloth.copy()
        for _ in range(r.integers(2, 5)):
            k = ms(r.uniform(5, 160))
            f = r.uniform(1800, 5200)
            seg = d.mix([(tick(r, f, 3.0, 8, .0015), 1.0), (ring(r, [f * .9, f * 1.7], [.03, .02], dur=.06), .5)])[:n - k]
            x[k:k + len(seg)] += seg * r.uniform(.3, .8)
        finalize("foley_gear_%d" % (i + 1), x, peak=-8.0)

    # Szum w uszach po wybuchu/ciosie (tinnitus): dwa tony HF, powolne zanikanie
    n = d.sec(3.6)
    t = np.arange(n) / d.SR
    rng = Rng(0xB400)
    tone = d.osc("sine", 4150.0, n) + .55 * d.osc("sine", 5620.0, n) + .22 * d.osc("sine", 1290.0, n)
    tone *= (1 + .08 * np.sin(2 * np.pi * 5.3 * t))
    tone *= d.env_pts(n, [(0, 0), (.05, 1), (.7, .9), (1.8, .35), (3.6, 0)])
    finalize("ear_ring", tone, lufs=-22.0, fade_out_ms=300)
