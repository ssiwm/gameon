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
from audio_dsp import SR, Rng, ms, sec
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
    _build_core_weapons()
    build_weapons_ext()


def _build_core_weapons() -> None:

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

    # Łuska na ziemi: sprężysty ping mosiądzu z odbiciami. Gra ją Vfx.casing() przy lądowaniu
    # fizycznej łuski (klucz `shell`, głośność w vfx.gd strojona pod peak ≈ −1,5 dBFS).
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
        finalize("shell_%d" % (i + 1), d.reverb(x, ir("dead"), wet=.15), peak=-1.5)
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


# ============================================================ BROŃ — rozszerzenie (1.6)
# Nowe bronie z GDD §6, foley przeładowań, potwierdzenia trafień, podnoszenie.

TAU = 2.0 * np.pi


def build_weapons_ext() -> None:
    group("sfx/weapons")

    # SRUT-8 — ciężka strzelba: głębszy sub, osiem cracków śrutu, długi ogon
    for i in range(3):
        r = Rng(0x2D00 + i * 6113)
        x = gun(r, body=(vary(r, (125, 112, 100)[i], .05), vary(r, (36, 32, 28)[i], .05)), body_tau=vary(r, .05, .06),
                body_dur=0.36, crack_f=vary(r, 2100, .1), crack_amt=1.15,
                blast=(vary(r, 6000, .1), vary(r, 600, .12)), blast_tau=vary(r, .052, .1),
                blast_amt=1.5, punch_f=vary(r, 280, .1), punch_amt=1.15, mech=.3, mech_f=1900.0,
                tail_rt=(.7, 1.0, 1.4)[i], tail_wet=(.32, .38, .44)[i], drive=2.6, dur=0.95, pellets=8, sub=(.9, 1.2, 1.5)[i])
        finalize("srut8_shot_%d" % (i + 1), x, lufs=-12.5)

    # Pompka: zamek do tyłu (szum + dzwonek metalu) i do przodu z łuską — dwa wariaty
    for i in range(2):
        r = Rng(0x2E00 + i * 4177)
        back = d.mix([(d.filt(d.white(ms(120), r), "bp", vary(r, 1100, .1), 1.3) * d.env_perc(ms(120), .01, .06), 1.0),
                      (ring(r, [vary(r, 1700, .08), vary(r, 3100, .08)], [.05, .03], dur=.12), .45, .02)], ms(140))
        fwd = d.mix([(thump(.08, 240, 100, .02, .03), 1.0), (tick(r, vary(r, 2100, .08), 1.5, 14, .004), 1.0),
                     (ring(r, [vary(r, 780, .1), vary(r, 2200, .1)], [.07, .04], dur=.14), .7)], ms(180))
        x = d.mix([(back, .8, 0.0), (fwd, 1.0, .17 + r.uniform(0, .02))], ms(420))
        finalize("srut8_pump_%d" % (i + 1), d.reverb(x, ir("close"), wet=.15), peak=-4.0)

    # LR-7: rozruch (świst wznoszący + trzaski) i pętla promienia (brzęczenie 120 Hz + trzaski)
    r = Rng(0x2F00)
    n = ms(280)
    wh = d.osc("saw", d.glide_exp(260, 2100, n, .16), n) * d.env_pts(n, [(0, 0), (.03, .9), (.18, .55), (.28, 0)])
    wh = d.filt(wh, "lp", 4200.0) * .7
    crk = d.filt(d.white(n, r), "hp", 2500.0) * d.env_perc(n, .002, .06) * .5
    finalize("lr7_start", d.reverb(d.mix([(wh, 1.0), (crk, .6, .02)], n), ir("close"), wet=.14), lufs=-19.0)

    asset("lr7_beam_loop", "sfx/weapons/lr7_beam_loop", loop=True)
    n = sec(2.0)
    t = np.arange(n) / SR
    r = Rng(0x2F10)
    hum = sum(a * np.sin(TAU * f * t + p) for f, a, p in ((120.0, 1.0, 0.0), (240.0, .55, .8), (360.0, .32, 1.7), (1200.0, .10, .4)))
    amod = 0.75 + 0.25 * np.sin(TAU * 30.0 * t)                               # 60 cykli w pętli
    whine = np.sin(TAU * 1800.0 * t + 2.0 * np.sin(TAU * 4.0 * t)) * .08
    spit = d.circ_filter(d.white(n, r), lambda z: d.hp(z, 3500.0)) * (np.maximum(0, np.sin(TAU * 7.0 * t + 1.0)) ** 8) * .5
    x = (hum * amod + whine + spit)
    finalize("lr7_beam_loop", x, loop=True, lufs=-20.0)

    # HKM-9: zapłon „whump” i pętla płomienia (szum szerokopasmowy z trzepotem)
    r = Rng(0x3010)
    n = ms(520)
    rush = d.sweep(d.colored(n, r, .8), "bp", d.env_pts(n, [(0, 300), (.12, 1400), (.5, 700)]), q=.7) * d.env_pts(n, [(0, 0), (.03, 1.0), (.2, .8), (.5, 0)])
    whump = thump(.35, 110, 38, .09, .16) * 1.3
    tick_ = d.filt(d.white(ms(30), r), "bp", 2400, .9) * d.env_perc(ms(30), .0005, .01) * 2.0
    x = d.mix([(rush, 1.0), (whump, 1.0), (tick_, .5)], n)
    finalize("hkm9_ignite", d.reverb(d.saturate(x, 1.6), ir("close"), wet=.16), lufs=-17.0)

    asset("hkm9_flame_loop", "sfx/weapons/hkm9_flame_loop", loop=True)
    n = sec(2.0)
    t = np.arange(n) / SR
    r = Rng(0x3020)
    base = d.colored(n, r, .8)
    rush = d.circ_filter(base, lambda z: d.bp(z, 700.0, .6)) * (.65 + .35 * np.sin(TAU * 14.0 * t + 1.0))   # trzepot 28 cykli
    low = d.circ_filter(base, lambda z: d.lp(z, 160.0)) * 1.2
    crackle = d.circ_filter(d.white(n, r), lambda z: d.hp(z, 2800.0)) * (np.maximum(0, np.sin(TAU * 11.0 * t)) ** 12) * .6
    x = d.mix([(rush, 1.0), (low, .9), (crackle, .7)], n)
    finalize("hkm9_flame_loop", x, loop=True, lufs=-19.0)

    # GNIEW-4: „bump” granatnika — niski korpus + pusty rezonans lufy
    for i in range(2):
        r = Rng(0x3100 + i * 5003)
        n = ms(700)
        body = thump(.30, vary(r, 95, .08), 36, .06, .11) * 1.2
        blast = burst(ms(120), r, vary(r, 3500, .1), 500, .03, color=.3) * .9
        tube = ring(r, [vary(r, 210, .06), vary(r, 430, .06), vary(r, 890, .06)], [.18, .12, .08], dur=.4) * .6
        bloop = d.osc("sine", d.glide_exp(520, 140, ms(120), .04), ms(120)) * d.env_perc(ms(120), .001, .05) * .5
        x = d.mix([(body, 1.0), (blast, 1.0), (tube, .8, .004), (bloop, .6, .01)], n)
        finalize("gniew4_shot_%d" % (i + 1), d.reverb(d.saturate(x, 1.8), ir("hall"), wet=.3), peak=-2.0)

    # SOKOL-6: odpalenie mikrorakiety — syk i świst
    for i in range(3):
        r = Rng(0x3200 + i * 3989)
        n = ms(520)
        k = (0.8, 1.0, 1.25)[i]
        sw = d.sweep(d.white(n, r), "bp", d.env_pts(n, [(0, 1300 * k), (.08, 3800 * k), (.25, 2400 * k), (.52, 900 * k)]), q=(0.8, 1.1, 1.6)[i])
        sw = sw * d.env_pts(n, [(0, 0), (.015, 1.0), (.15, .7), (.52, 0)])
        pop = d.mix([(thump(.06, 260, 120, .015, .03), 1.0), (tick(r, 2600, 1.4, 12, .003), .8)], ms(80))
        x = d.mix([(sw, 1.0), (pop, 1.0)], n)
        finalize("sokol6_shot_%d" % (i + 1), d.reverb(x, ir("close"), wet=.16), lufs=-19.0)

    # WIDMO-1: ładowanie 1,2 s (wznosząca się cewka) i strzał (trzask + sub + wyładowanie)
    r = Rng(0x3300)
    n = sec(1.2)
    t = np.arange(n) / SR
    f = d.env_pts(n, [(0, 140), (.9, 1100), (1.2, 3300)])
    whine = d.osc("saw", f, n) * .5 + d.osc("sine", f * 2.01, n) * .35
    trem = .6 + .4 * np.sin(TAU * np.cumsum(6.0 + 38.0 * (t / 1.2) ** 2) / SR)
    hum = d.osc("sine", 60.0, n) * .7
    crk = d.filt(d.white(n, r), "hp", 4000.0) * (t / 1.2) ** 3 * .35
    x = d.mix([(whine * trem, 1.0), (hum, .8), (crk, .7)], n) * d.env_pts(n, [(0, 0), (.12, .6), (1.15, 1.0), (1.2, 0)])
    finalize("widmo1_charge", d.filt(x, "lp", 9000.0), lufs=-19.0, fade_out_ms=20)

    for i in range(2):
        r = Rng(0x3310 + i * 2741)
        n = ms(1500)
        crack = d.filt(d.white(ms(14), r), "hp", 900.0, order=3) * d.env_perc(ms(14), .0002, .004) * 6.0
        sub = thump(1.0, vary(r, 62, .06), 20, .22, .38, attack=.002) * 1.5
        zap = d.osc("saw", d.glide_exp(7200, 280, ms(260), .05), ms(260)) * d.env_perc(ms(260), .0005, .07) * .6
        zap = d.filt(zap, "bp", vary(r, 2400, .1), .6) * 1.2
        body = d.sweep(d.colored(n, r, 1.0), "lp", d.glide_exp(5200, 130, n, .22), q=.8) * d.env_perc(n, .001, .24) * 1.6
        arcs = np.zeros(n)
        for _ in range(26):
            k = ms(r.uniform(5, 420))
            tk = tick(r, r.uniform(2500, 8000), 1.6, r.uniform(2, 8), .001)
            if k + len(tk) < n:
                arcs[k:k + len(tk)] += tk * r.uniform(.1, .5) * np.exp(-k / ms(500))
        x = d.mix([(crack, 1.0), (sub, 1.0), (zap, .8, .002), (body, 1.0), (arcs, 1.0)], n)
        x = d.saturate(x, 2.0)
        finalize("widmo1_shot_%d" % (i + 1), d.reverb(x, ir("hall"), wet=.34), peak=-1.5, fade_out_ms=100)

    # CIEGNO-6: cięciwa (dźwięczny „twang”) + świst bełtu — cicha broń
    for i in range(2):
        r = Rng(0x3400 + i * 2113)
        n = ms(420)
        tw = ring(r, [vary(r, 168, .06), vary(r, 336, .06), vary(r, 505, .06)], [.35, .22, .12], dur=.4) * 1.0
        sn = d.mix([(thump(.05, 400, 160, .01, .02), 1.0), (tick(r, 1700, 1.2, 20, .006), .8)], ms(60))
        whz = d.sweep(d.white(ms(160), r), "bp", d.glide_exp(4200, 1500, ms(160), .06), 1.4) * d.env_perc(ms(160), .004, .05) * .4
        x = d.mix([(tw, .9), (sn, 1.0), (whz, .6, .005)], n)
        finalize("ciegno6_shot_%d" % (i + 1), d.reverb(x, ir("close"), wet=.15), peak=-5.0)

    # Kilof: ciężki zamach (niższy i wolniejszy niż maczeta)
    for i in range(2):
        r = Rng(0x3500 + i * 3331)
        n = ms(520)
        sw = d.sweep(d.colored(n, r, .6), "bp", d.env_pts(n, [(0, (170, 280)[i]), (.16, (560, 900)[i]), (.26, (1500, 2300)[i]), (.5, (340, 520)[i])]), q=(1.0, 1.8)[i])
        sw = sw * d.env_pts(n, [(0, 0), (.12, .5), (.23, 1.0), (.36, .3), (.52, 0)]) ** 1.2
        wood = thump(.12, vary(r, 130, .1), 60, .03, .05) * .35
        x = d.mix([(sw, 1.0), (wood, 1.0, .19)], n)
        finalize("kilof_swing_%d" % (i + 1), d.reverb(x, ir("close"), wet=.12), lufs=-18.0)

    # Przeładowania specyficzne: łuska do komory, ogniwo, granat, kondensator, cięciwa
    for i in range(3):
        r = Rng(0x3600 + i * 2339)
        f0 = vary(r, 2200, .12)
        x = d.mix([(tick(r, f0, 2.0, 12, .003), 1.0), (ring(r, [f0 * .55, f0 * 1.4], [.05, .03], dur=.1), .5),
                   (thump(.07, vary(r, 180, .1), 80, .015, .025), .6, .004)], ms(160))
        finalize("reload_shell_%d" % (i + 1), d.reverb(x, ir("dead"), wet=.12), peak=-5.0)

    for i in range(2):
        r = Rng(0x3700 + i * 2677)
        latch = d.mix([(tick(r, (1500, 2400)[i], 1.8, 14, .004), 1.0), (thump(.08, (130, 200)[i], 80, .02, .03), .6)], ms(120))
        slide = d.filt(d.white(ms(150), r), "bp", (900, 1700)[i], 1.2) * d.env_curve(ms(150), 0, 1, 1.4) * d.env_exp(ms(150), .08)
        seat = d.mix([(thump(.09, 210, 90, .02, .03), 1.0), (tick(r, 2600, 1.6, 10, .003), .7)], ms(120))
        up = d.osc("sine", d.glide_exp((200, 320)[i], (1200, 2000)[i], ms(380), .22), ms(380)) * d.env_pts(ms(380), [(0, 0), (.05, .5), (.3, .6), (.38, 0)]) * .35
        x = d.mix([(latch, 1.0, 0.0), (slide, .5, .06), (seat, 1.0, .30), (up, 1.0, .42)], ms(900))
        finalize("reload_cell_%d" % (i + 1), d.reverb(x, ir("close"), wet=.13), peak=-4.0)

    r = Rng(0x3800)
    creak = d.sweep(d.colored(ms(260), r, .8), "bp", d.glide(380, 760, ms(260)), 3.0) * d.env_pts(ms(260), [(0, 0), (.04, .6), (.22, .4), (.26, 0)])
    ins = d.mix([(thump(.1, 150, 70, .02, .04), 1.0), (tick(r, 1500, 1.4, 16, .005), .8)], ms(150))
    clack = d.mix([(tick(r, 2300, 1.8, 14, .004), 1.0), (thump(.09, 200, 90, .02, .03), .8), (ring(r, [900, 2600], [.08, .04], dur=.15), .4)], ms(200))
    x = d.mix([(creak, .8, 0.0), (ins, 1.0, .38), (clack, 1.0, .72)], ms(1000))
    finalize("reload_launcher_1", d.reverb(x, ir("room"), wet=.16), peak=-4.0)

    r = Rng(0x3900)
    hum = d.osc("sine", d.glide_exp(90, 520, ms(700), .3), ms(700)) * d.env_pts(ms(700), [(0, 0), (.1, .5), (.55, .7), (.7, 0)]) * .5
    clunk = d.mix([(thump(.14, 130, 55, .03, .06), 1.0), (tick(r, 1400, 1.2, 20, .006), .8)], ms(240))
    lat = d.mix([(tick(r, 2800, 2.0, 12, .003), 1.0), (ring(r, [1500, 3300], [.07, .04], dur=.15), .5)], ms(180))
    x = d.mix([(clunk, 1.0, 0.0), (hum, 1.0, .12), (lat, 1.0, .88)], ms(1100))
    finalize("reload_rail_1", d.reverb(x, ir("room"), wet=.16), peak=-4.0)

    r = Rng(0x3A00)
    x = np.zeros(ms(1000))
    for k in range(7):                                            # zapadki naciągu cięciwy
        tk = d.mix([(tick(r, 1100 + 90 * k, 2.2, 10, .003), 1.0), (thump(.04, 300, 150, .01, .015), .3)], ms(60))
        o = ms(6 + k * 72)
        x[o:o + len(tk)] += tk[:len(x) - o] * (.6 + .06 * k)
    seat = d.mix([(thump(.08, 190, 80, .02, .03), 1.0), (tick(r, 2400, 1.6, 12, .004), .9)], ms(120))
    x = d.mix([(x, 1.0), (seat, 1.0, .66)], ms(1000))
    finalize("reload_bolt_1", d.reverb(x, ir("close"), wet=.12), peak=-5.0)

    # Potwierdzenia trafień (UI): krótkie, jasne, nie męczą przy 9 trafieniach/s
    for i in range(2):
        r = Rng(0x3B00 + i * 997)
        x = d.mix([(tick(r, vary(r, 3400, .06), 3.0, 9, .002), 1.0),
                   (ring(r, [vary(r, 2300, .04)], [.02], dur=.04), .35)], ms(50))
        finalize("hitmark_%d" % (i + 1), x, peak=-9.0, trim=False)
    r = Rng(0x3B10)
    x = d.mix([(tick(r, 4200, 3.0, 9, .002), 1.0), (ring(r, [1900, 3300], [.05, .03], dur=.1), .7, .018)], ms(110))
    finalize("hitmark_crit", x, peak=-5.0, trim=False)
    r = Rng(0x3B20)
    x = d.mix([(thump(.12, 150, 64, .03, .05), 1.0), (tick(r, 2900, 2.5, 10, .003), .9), (ring(r, [1200, 2100], [.08, .05], dur=.12), .5, .01)], ms(180))
    finalize("killmark", d.saturate(x, 1.5), peak=-4.0)
    r = Rng(0x3B30)
    x = d.mix([(tick(r, 900, 1.2, 14, .004), 1.0), (thump(.05, 190, 100, .015, .02), .5)], ms(60))
    finalize("armor_tick", x, peak=-10.0, trim=False)

    # Podniesienie amunicji i broni
    r = Rng(0x3C00)
    x = d.mix([(tick(r, 2100, 1.8, 14, .004), 1.0), (thump(.07, 190, 90, .02, .03), .7, .004),
               (ring(r, [3600, 5200], [.06, .04], dur=.1), .5, .03), (tick(r, 2900, 1.6, 10, .003), .7, .07)], ms(200))
    finalize("ammo_pickup", d.reverb(x, ir("dead"), wet=.12), peak=-6.0)
    r = Rng(0x3C10)
    x = d.mix([(thump(.12, 150, 60, .03, .05), 1.0), (tick(r, 1500, 1.4, 18, .005), .9, .004),
               (tick(r, 2600, 2.0, 10, .003), .9, .09), (ring(r, [1100, 2400], [.1, .06], dur=.2), .5, .01)], ms(300))
    finalize("weapon_pickup", d.reverb(x, ir("close"), wet=.14), peak=-5.0)
