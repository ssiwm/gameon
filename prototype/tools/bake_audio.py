"""
bake_audio.py — generator biblioteki dźwięków Dead Air '87.

Uruchomienie:
    python3 tools/bake_audio.py            # przebake'uje brakujące pliki
    python3 tools/bake_audio.py --force    # przebake'uje wszystko
    python3 tools/bake_audio.py --only weapons stalker   # tylko wybrane grupy
    python3 tools/bake_audio.py --list      # lista assetów

Wynik:
    audio/**/*.wav            assety (deterministyczne, patrz audio_dsp.Rng)
    scripts/audio_manifest.gd  wygenerowana tablica ścieżek + flagi loop

Wszystko jest syntezą proceduralną na czystym stdlib (brak numpy w środowisku).
Docelowy materiał nagrany zastąpi te pliki 1:1 — runtime nie widzi różnicy.
"""

from __future__ import annotations

import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import audio_dsp as d  # noqa: E402
from audio_dsp import SR, Rng  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "audio")
MANIFEST = os.path.join(ROOT, "scripts", "audio_manifest.gd")

# Registry: key -> (relative path, is_loop)
REG: dict[str, tuple[str, bool]] = {}
GROUPS: dict[str, list[str]] = {}

# Domyślna ścieżka dla bieżącej grupy assetów — ustawiana przez każdy builder,
# żeby `render()` sam rejestrował klucz bez powtarzania prefiksu.
_CUR = "sfx/misc"


def asset(key: str, path: str, loop: bool = False) -> None:
    REG[key] = (path, loop)
    GROUPS.setdefault(path.split("/")[0], []).append(key)


def ms(v: float) -> int:
    return int(SR * v / 1000.0)


def render(key: str, buf: list, stereo_width: float | None = None, peak: float = 0.95,
           loop: bool = False, rms: float | None = None,
           period: int | None = None, xfade: int | None = None) -> None:
    """Normalizuje, wygładza krawędzie i zapisuje asset.

    Jeśli klucza nie ma w REG, rejestruje go pod domyślną ścieżką bieżącej grupy.

    Kolejność jest tu istotna:
      1. stereoize() — przesuwa kanał opóźnieniem Haas, więc musi się odbyć
         PRZED zapętleniem (inaczej szew rozjeżdża się w prawym kanale).
      2. buf_hp() — PRZED szwem pętli. To filtr IIR startujący od zera: puszczony
         po loop_xfade() robił stan przejściowy na początku pliku i rozrywał
         wyrównany właśnie szew (klik co obieg w amb_air, szepcie, oddechu…).
      3. szew: loop_period() gdy pętla ma rytm (period = dokładna długość
         w próbkach, builder dostarcza period + xfade), inaczej loop_xfade().
      4. normalizacja — liniowa, szwu nie psuje. Stereo: wspólne wzmocnienie
         dla obu kanałów, żeby nie przesuwać panoramy.
      5. fade krawędzi — TYLKO dla one-shotów (w pętli robiłby dziurę co obieg).

    rms= włącza normalizację po głośności (zamiast po peaku) — dla warstw
    muzyki, które nakładają się na siebie.
    """
    if key not in REG:
        REG[key] = (_CUR + "/" + key, loop)
    path, loop = REG[key]
    full = os.path.join(AUDIO, path + ".wav")
    os.makedirs(os.path.dirname(full), exist_ok=True)
    tail = min(0.5, len(buf) / SR * 0.25)

    def seam(b: list) -> list:
        b = d.buf_hp(b)
        if not loop:
            return b
        if period:
            return d.loop_period(b, period, xfade or ms(100))
        return d.loop_xfade(b, tail)

    def norm(b: list) -> list:
        return d.buf_norm_rms(b, rms) if rms else d.buf_norm(b, peak)

    def edges(b: list) -> list:
        if loop:
            return b
        return d.buf_fade(b, min(0.0015, len(b) / SR * 0.05),
                          min(0.02, len(b) / SR * 0.25))

    if stereo_width is not None:
        left, right = d.stereoize(buf, stereo_width)
        left, right = seam(left), seam(right)
        n = min(len(left), len(right))
        both = norm(left[:n] + right[:n])
        d.write_wav(full, (edges(both[:n]), edges(both[n:])), SR, 2)
    else:
        d.write_wav(full, edges(norm(seam(buf))), SR, 1)





# ============================================================ BRONIE

def gun_shot(n, rng, spread=1.0, body_lo=70.0, body_hi=230.0, dur=190.0,
             blast_hz=3000.0, snap=1.0, mech=1.0, tail_amt=0.16):
    """Uniwersalny strzał z warstwami: mechanika + korpus + blast + ogon.

    Rozpływ na te warstwy (a nie jeden szum) jest tym, co odróżnia broń
    od siebie na słuch przy mieszanym ogniu.
    """
    n_i = ms(dur)
    r = Rng(rng._next() & 0xFFFFFFFF)

    # 1. mechanika: krótki, wysoki klik (mechanizm, sprężyna)
    mech_n = ms(45)
    mech_buf = d.buf_mul(d.highpass(d.noise_white(mech_n, r), 1800.0),
                         d.env_perc(mech_n, 0.0004, 0.006))
    mech_buf = d.buf_add_scaled(
        mech_buf,
        d.buf_mul(d.osc(d.wt_square(0.35), mech_n, 5200, 3100),
                  d.env_perc(mech_n, 0.0004, 0.010)), 0.18)
    mech_buf = d.buf_offset(mech_buf, 0.004)

    # 2. korpus: głos broni (thump) z szybkim opadaniem
    body = d.buf_mul(d.osc(d.wt_square(), n_i, body_hi, body_lo),
                     d.env_exp(n_i, 0.030))
    body = d.svf(body, 900, 260, 1.1)
    body = d.buf_offset(body, 0.0015)

    # 3. blast: szum przefiltrowany z górnym opadaniem — "strzał" w powietrzu
    blast = d.svf(d.noise_white(n_i, r), blast_hz * 2.2, blast_hz * 0.35, 0.9)
    blast = d.buf_mul(blast, d.env_perc(n_i, 0.0008, 0.045))
    blast = d.buf_add_scaled(blast, d.noise_brown(ms(60), r), 0.9)

    # 4. supersoniczny snap (najbliżej ucha — tak słyszy się strzał obok)
    if snap > 0.0:
        crack = d.svf(d.noise_white(ms(14), r), 6500, 3000, 0.6)
        crack = d.buf_mul(crack, d.env_perc(ms(14), 0.0002, 0.0025))
        blast = d.buf_add_scaled(blast, crack, 0.85 * snap)

    # 5. ogon pomieszczenia
    out = d.mixdown([
        (mech_buf, 0.55 * mech),
        (body, 0.95),
        (blast, 0.85),
    ], n_i)
    if tail_amt > 0.0:
        out = d.schroeder(out, room=0.55, damp=0.45, mix=tail_amt, pre_s=0.010)
    out = d.saturate(out, 1.7)
    # indywidualny charakter egzemplarza
    k = 1.0 + rng.bipolar(0.05 * spread)
    return [x * k for x in out]


def build_weapons() -> None:
    global _CUR
    _CUR = "sfx/weapons"
    # M-83 "Krótki" — SMG 600 RPM: krótki, suchy, świetny do długich serii
    asset("m83_shot_1", "sfx/weapons/m83_shot_1")
    for i in range(4):
        rng = Rng(0x1000 + i * 104729)
        render("m83_shot_%d" % (i + 1),
               gun_shot(i, rng, 1.0, 62.0 + i * 4, 210.0 + i * 9, 165.0,
                        3400.0 - i * 180, 1.0, 1.0, 0.13))

    # P-64 "Igła" — sidearm: ostrzejszy, wyższy, krótszy ogon
    for i in range(3):
        rng = Rng(0x2000 + i * 15485863)
        render("p64_shot_%d" % (i + 1),
               gun_shot(i, rng, 1.0, 88.0 + i * 5, 300.0 + i * 12, 190.0,
                        4400.0 - i * 260, 1.0, 0.75, 0.20))

    # Przeładowanie: magazyn w górę + magazyn w górę + bolt (3 fazy)
    for i in range(3):
        rng = Rng(0x3000 + i * 7919)
        n_i = ms(620)
        clunk = d.buf_mul(d.svf(d.noise_white(ms(70), rng), 2200, 500, 2.4),
                          d.env_perc(ms(70), 0.0006, 0.018))
        clunk = d.buf_add_scaled(clunk, d.buf_mul(
            d.osc(d.wt_square(), ms(70), 190, 90), d.env_perc(ms(70), 0.0006, 0.020)), 0.35)
        out = d.mixdown([
            (d.buf_offset(clunk, 0.000), 1.0),
            (d.buf_offset(clunk, 0.155), 0.8),
            (d.buf_offset(d.buf_mul(d.svf(d.noise_white(ms(90), rng), 3600, 900, 3.0),
                                    d.env_perc(ms(90), 0.0006, 0.030)), 0.300), 0.95),
        ], n_i)
        render("reload_%d" % (i + 1), d.saturate(d.schroeder(out, 0.4, 0.5, 0.12), 1.3))

    # Suchy strzał (pusty magazyn) — informacja zwrotna
    render("dry_fire", d.mixdown([
        (d.buf_mul(d.noise_white(ms(35), Rng(0x41)), d.env_perc(ms(35), 0.0003, 0.004)), 1.0),
        (d.buf_offset(d.buf_mul(d.osc(d.wt_square(), ms(30), 1400, 700),
                                d.env_perc(ms(30), 0.0003, 0.005)), 0.012), 0.5),
    ], ms(70)))

    # Maczeta — zamach (whoosh) + cięcie
    for i in range(2):
        rng = Rng(0x5000 + i * 31337)
        n_i = ms(340)
        sw = d.svf(d.noise_white(n_i, rng), 380, 3600, 1.6)
        sw = d.buf_mul(sw, d.env_exp(n_i, 0.075))
        sw = d.buf_add_scaled(sw, d.noise_brown(n_i, rng), 0.25)
        cut = d.buf_mul(d.svf(d.noise_white(ms(90), rng), 5000, 900, 0.8),
                        d.env_perc(ms(90), 0.0006, 0.020))
        out = d.mixdown([(sw, 0.8), (d.buf_offset(cut, 0.085), 0.9)], n_i)
        render("maczeta_%d" % (i + 1), out)

    # Pocisk przelotujący obok (najważniejszy dla "run-and-gun feel")
    for i in range(3):
        rng = Rng(0x6000 + i * 8191)
        n_i = ms(260)
        wh = d.svf(d.noise_white(n_i, rng), 2600, 520, 2.2)
        amp = [math.sin(math.pi * (i / n_i)) for i in range(n_i)]
        wh = d.buf_mul(wh, amp)
        wh = d.buf_add_scaled(wh, d.buf_mul(
            d.svf(d.noise_white(n_i, rng), 5200, 1800, 3.0), amp), 0.6)
        render("whizz_%d" % (i + 1), d.saturate(wh, 2.4), 22.0)

    # Trafienie w podłoże / ścianę
    for i in range(3):
        rng = Rng(0x7000 + i * 6151)
        n_i = ms(200)
        hit = d.buf_mul(d.svf(d.noise_white(ms(30), rng), 4200, 1100, 1.4),
                        d.env_perc(ms(30), 0.0004, 0.007))
        deb = d.svf(d.noise_white(n_i, rng), 6000, 1800, 0.7)
        deb = d.buf_mul(deb, d.env_exp(n_i, 0.035))
        out = d.mixdown([(hit, 1.0), (deb, 0.30)], n_i)
        render("impact_hard_%d" % (i + 1), d.schroeder(out, 0.6, 0.4, 0.18))

    # Odbicie (ricochet) — metal
    for i in range(2):
        rng = Rng(0x8000 + i * 4099)
        n_i = ms(420)
        ric = d.osc(d.wt_sine(), n_i, 2600.0 - i * 300, 700.0, vib_hz=22.0, vib_cents=60.0)
        ric = d.buf_mul(ric, d.env_exp(n_i, 0.11))
        ric = d.buf_add_scaled(ric, d.svf(d.noise_white(ms(30), rng), 5000, 2000, 2.0), 0.4)
        render("ricochet_%d" % (i + 1), d.schroeder(ric, 0.75, 0.3, 0.28))

    # Trafienie w ciało
    for i in range(3):
        rng = Rng(0x9000 + i * 3571)
        n_i = ms(170)
        f = d.svf(d.noise_white(n_i, rng), 900, 180, 1.0)
        f = d.buf_mul(f, d.env_perc(n_i, 0.001, 0.030))
        f = d.buf_add_scaled(f, d.buf_mul(d.osc(d.wt_sine(), n_i, 160, 70),
                                          d.env_perc(n_i, 0.001, 0.045)), 0.7)
        render("impact_flesh_%d" % (i + 1), d.saturate(f, 2.2))

    # Eksplozja — do storyboardu, nie do prototypu, ale grawitacja sfx się przyda
    for i in range(2):
        rng = Rng(0xA000 + i * 7717)
        n_i = ms(1800)
        boom = d.svf(d.noise_brown(ms(600), rng), 180, 45, 1.2)
        boom = d.buf_mul(boom, d.env_exp(ms(600), 0.22))
        blast = d.svf(d.noise_white(ms(900), rng), 2400, 200, 0.8)
        blast = d.buf_mul(blast, d.env_exp(ms(900), 0.16))
        sub = d.buf_mul(d.osc(d.wt_sine(), ms(600), 68, 26), d.env_exp(ms(600), 0.15))
        out = d.mixdown([(boom, 1.0), (d.buf_offset(blast, 0.004), 0.7),
                         (d.buf_offset(sub, 0.010), 0.9)], n_i)
        render("explosion_%d" % (i + 1), d.saturate(d.schroeder(out, 0.9, 0.28, 0.34), 2.0), 8.0)


# ============================================================ STALKER

def build_stalker() -> None:
    global _CUR
    _CUR = "sfx/stalker"
    # Growl — niski, nieregularny, „z piersi". Najczęściej słyszany dźwięk w grze.
    for i in range(2):
        rng = Rng(0xB000 + i * 5171)
        n_i = ms(3400)
        g = d.fm2(n_i, 41.0 + i * 3.0, ratio=1.41, index=7.0, index_end=3.0, vib_hz=0.35, vib_cents=40.0)
        br = d.noise_brown(n_i, rng)
        br = d.svf(br, 300, 120, 0.9)
        # nieregularne „oddechy"
        env = [0.0] * n_i
        for k in range(6):
            st = int(n_i * (0.06 + 0.15 * k + rng.uniform(0.0, 0.03)))
            amp = 0.55 + rng.uniform(0.0, 0.45)
            e = d.env_exp(n_i - st, 0.30 + rng.uniform(0.0, 0.25))
            for j in range(n_i - st):
                env[st + j] += e[j] * amp
        env = d.buf_mul(d.env_exp(n_i, 0.9), env)
        out = d.mixdown([(d.buf_mul(g, env), 0.85), (d.buf_mul(br, env), 0.45)], n_i)
        render("stalker_growl_%d" % (i + 1), d.schroeder(out, 0.85, 0.25, 0.22), 30.0)

    # Szept — „czatuje", wysoki, prawie niesłyszalny. Buduje napięcie bez głośności.
    asset("stalker_whisper_loop", "sfx/stalker/stalker_whisper_loop", loop=True)
    n_i = ms(4200)
    rng = Rng(0xB400)
    w = d.svf(d.noise_white(n_i, rng), 1400, 700, 2.2)
    flutter = [0.5 + 0.5 * math.sin(TAU_ * i / SR) for i in range(0)]
    w = d.buf_mul(w, d.env_adsr(n_i, 0.6, 0.4, 0.8, 0.8))
    for i in range(n_i):
        t = i / SR
        w[i] *= 0.45 + 0.55 * abs(math.sin(TAU_ * 0.7 * t)) * (0.6 + 0.4 * math.sin(TAU_ * 2.3 * t))
    render("stalker_whisper_loop", d.schroeder(w, 0.9, 0.5, 0.30), 35.0)

    # Krzyk — atak. Krótki, głośny, nieprzewidywalny.
    for i in range(2):
        rng = Rng(0xB800 + i * 2459)
        n_i = ms(900)
        cry = d.fm2(n_i, 300.0 - i * 20, ratio=1.73, index=14.0, index_end=4.0, vib_hz=9.0, vib_cents=180.0)
        nz = d.svf(d.noise_white(n_i, rng), 4000, 900, 1.2)
        out = d.mixdown([
            (d.buf_mul(cry, d.env_adsr(n_i, 0.012, 0.25, 0.5, 0.45)), 0.9),
            (d.buf_mul(nz, d.env_perc(n_i, 0.004, 0.30)), 0.6),
            (d.buf_mul(d.osc(d.wt_sine(), ms(400), 90, 44), d.env_exp(ms(400), 0.13)), 0.8),
        ], n_i)
        render("stalker_shriek_%d" % (i + 1), d.saturate(d.schroeder(out, 0.95, 0.22, 0.30), 2.2), 18.0)

    # Krok stalkera — ciężki, niższy niż gracz, z lekkim opóźnieniem „gruntu"
    for i in range(3):
        rng = Rng(0xC000 + i * 4517)
        n_i = ms(320)
        st = d.svf(d.noise_white(ms(70), rng), 500, 90, 1.6)
        st = d.buf_mul(st, d.env_perc(ms(70), 0.001, 0.022))
        st = d.buf_add_scaled(st, d.buf_mul(d.osc(d.wt_sine(), ms(120), 74, 42),
                                            d.env_perc(ms(120), 0.001, 0.040)), 0.8)
        grit = d.svf(d.noise_white(n_i, rng), 3200, 900, 0.7)
        grit = d.buf_mul(grit, d.env_exp(n_i, 0.045))
        out = d.mixdown([(st, 1.0), (grit, 0.22)], n_i)
        render("stalker_step_%d" % (i + 1), d.schroeder(out, 0.8, 0.35, 0.26))

    # „Pojawienie się" — gdyby kiedyś chciał teleport poza kadrem
    render("stalker_appear", d.schroeder(d.mixdown([
        (d.buf_mul(d.svf(d.noise_white(ms(700), Rng(0xC400)), 200, 4200, 1.4),
                   d.env_adsr(ms(700), 0.35, 0.15, 0.5, 0.35)), 1.0),
        (d.buf_mul(d.fm2(ms(600), 120.0, 1.5, 6.0, 1.0), d.env_exp(ms(600), 0.30)), 0.6),
    ], ms(700)), 0.9, 0.3, 0.30))


TAU_ = d.TAU


# ============================================================ ŚWIAT

def build_world() -> None:
    global _CUR
    _CUR = "sfx/world"
    rng = Rng(0xD000)

    # Drzwi (metal, zamek ZSRR)
    for i in range(2):
        r = Rng(0xD100 + i * 3121)
        n_i = ms(800)
        hinge = d.fm2(ms(700), 620.0 - i * 90, ratio=2.7, index=5.0, index_end=9.0, vib_hz=6.0, vib_cents=70.0)
        hinge = d.buf_mul(hinge, d.env_adsr(ms(700), 0.02, 0.35, 0.6, 0.40))
        clack = d.buf_mul(d.svf(d.noise_white(ms(90), r), 2400, 400, 2.6),
                          d.env_perc(ms(90), 0.0006, 0.025))
        out = d.mixdown([(hinge, 0.8), (d.buf_offset(clack, 0.700), 1.0)], n_i)
        render("door_%d" % (i + 1), d.schroeder(out, 0.75, 0.35, 0.24))

    # Generator — ciągły buczenie 50 Hz z brzękiem. Pętla.
    asset("generator_loop", "sfx/world/generator_loop", loop=True)
    n_i = ms(2600)
    g = Rng(0xD200)
    buzz = d.osc(d.wt_square(0.45), n_i, 100.0, 100.0)
    sub = d.osc(d.wt_sine(), n_i, 50.0, 50.0)
    nz = d.svf(d.noise_white(n_i, g), 1800, 700, 1.4)
    eng = d.mixdown([(d.buf_mul(buzz, 0.5), 0.7), (d.buf_mul(sub, 0.5), 0.8),
                     (d.buf_mul(nz, 0.28), 0.5)], n_i)
    render("generator_loop", eng, 14.0)

    # Dzwon alarmowy — dysonans, brzmi jak kościół w wiosce (Strefa II)
    render("alarm_bell", d.schroeder(d.mixdown([
        (d.buf_mul(d.fm2(ms(2200), 196.0, ratio=1.414, index=9.0, index_end=3.0),
                   d.env_exp(ms(2200), 0.55)), 0.8),
        (d.buf_mul(d.fm2(ms(2200), 262.0, ratio=1.414, index=8.0, index_end=3.0),
                   d.env_exp(ms(2200), 0.45)), 0.6),
        (d.buf_mul(d.svf(d.noise_white(ms(80), rng), 5000, 1500, 1.2),
                   d.env_perc(ms(80), 0.001, 0.020)), 0.5),
    ], ms(2200)), 0.9, 0.22, 0.30), 20.0)

    # Flara — zapalenie plus pętla syku zdefiniowana niżej
    render("flare_ignite", d.schroeder(d.mixdown([
        (d.buf_mul(d.svf(d.noise_white(ms(500), Rng(0xD300)), 600, 3000, 1.0),
                   d.env_adsr(ms(500), 0.02, 0.2, 0.7, 0.35)), 1.0),
        (d.buf_mul(d.osc(d.wt_sine(), ms(300), 240, 120), d.env_exp(ms(300), 0.10)), 0.5),
    ], ms(500)), 0.5, 0.5, 0.10))

    asset("flare_loop", "sfx/world/flare_loop", loop=True)
    n_i = ms(3000)
    r = Rng(0xD400)
    hiss = d.svf(d.noise_white(n_i, r), 5200, 3000, 0.6)
    hiss = d.buf_mul(hiss, [0.85 + 0.15 * math.sin(d.TAU * 1.7 * i / SR) for i in range(n_i)])
    render("flare_loop", hiss, 20.0)

    # Szyba — zniekształcenie napięcia i drżenie szyby to informacja „są w środku"
    for i in range(2):
        r = Rng(0xD500 + i * 3571)
        n_i = ms(900)
        out = d.mixdown([
            (d.buf_mul(d.svf(d.noise_white(ms(160), r), 6500, 1800, 0.5),
                       d.env_perc(ms(160), 0.0005, 0.055)), 1.0),
            (d.svf(d.noise_white(n_i, r), 5200, 1400, 1.0), 0.35),
        ], n_i)
        render("glass_break_%d" % (i + 1), d.schroeder(out, 0.6, 0.25, 0.30), 26.0)

    # Radio — szum, kliknięcie i pętla „nie ma tu nikogo"
    asset("radio_static_loop", "sfx/world/radio_static_loop", loop=True)
    n_i = ms(2400)
    r = Rng(0xD600)
    st = d.svf(d.noise_white(n_i, r), 4200, 1600, 0.8)
    crackle = d.noise_pink(n_i, r)
    render("radio_static_loop", d.buf_mul(d.buf_add(st, d.buf_scale(crackle, 0.5)),
                                          [0.6 + 0.4 * abs(math.sin(d.TAU * 0.9 * i / SR))
                                           for i in range(n_i)]), 12.0)
    render("radio_beep", d.mixdown([
        (d.buf_mul(d.osc(d.wt_square(0.5), ms(120), 880, 880),
                   d.env_adsr(ms(120), 0.004, 0.02, 0.7, 0.06)), 1.0),
        (d.buf_mul(d.svf(d.noise_white(ms(20), Rng(0xD700)), 3000, 1000, 1.0),
                   d.env_perc(ms(20), 0.001, 0.006)), 0.5),
    ], ms(180)))

    # Mina kierunkowa — pytający sygnał, napięcie w słuchu
    asset("mine_beep_loop", "sfx/world/mine_beep_loop", loop=True)
    n_i = ms(2000)
    bps = []
    for i in range(n_i):
        t = (i / SR) % 0.5
        bps.append(math.exp(-t / 0.02) if t < 0.2 else 0.0)
    render("mine_beep_loop", d.buf_mul(
        d.osc(d.wt_square(0.5), n_i, 1760, 1760), bps))

    # Taśma — zatrzymanie/zapis, klimat 80.
    render("tape_stop", d.tape(d.buf_mul(
        d.svf(d.noise_white(ms(900), Rng(0xD800)), 3600, 900, 1.0),
        d.env_exp(ms(900), 0.28)), wow_hz=3.0, wow_depth=0.012, hiss=0.02, sat=2.0))


# ============================================================ GRACZ

def build_player() -> None:
    global _CUR
    _CUR = "sfx/player"
    # Kroki — cztery powierzchnie × trzy warianty. Materiał to informacja
    # gracz musi rozpoznać instynktownie (GDD: „kucanie = 0 hałasu" ma sens
    # tylko wtedy, gdy słychać, po czym chodzimy).
    def step_concrete(r):
        n_i = ms(160)
        tick = d.buf_mul(d.svf(d.noise_white(ms(40), r), 3000, 800, 1.2),
                         d.env_perc(ms(40), 0.0005, 0.010))
        low = d.buf_mul(d.osc(d.wt_sine(), ms(70), 130, 78), d.env_perc(ms(70), 0.001, 0.020))
        return d.schroeder(d.mixdown([(tick, 1.0), (low, 0.55)], n_i), 0.45, 0.45, 0.14)

    def step_metal(r):
        n_i = ms(320)
        ring = d.fm2(ms(260), 780.0 + r.uniform(-40, 60), ratio=2.41, index=6.0, index_end=1.5)
        ring = d.buf_mul(ring, d.env_exp(ms(260), 0.055))
        hit = d.buf_mul(d.svf(d.noise_white(ms(45), r), 5200, 1600, 1.6),
                        d.env_perc(ms(45), 0.0005, 0.012))
        return d.schroeder(d.mixdown([(hit, 1.0), (d.buf_offset(ring, 0.002), 0.75)], n_i),
                           0.6, 0.4, 0.20)

    def step_dirt(r):
        n_i = ms(170)
        thud = d.buf_mul(d.svf(d.noise_white(ms(80), r), 900, 200, 0.9),
                         d.env_perc(ms(80), 0.0015, 0.026))
        soft = d.buf_mul(d.svf(d.noise_white(ms(110), r), 2200, 600, 0.7),
                         d.env_exp(ms(110), 0.030))
        return d.mixdown([(thud, 1.0), (soft, 0.6)], n_i)

    def step_water(r):
        n_i = ms(420)
        splash = d.svf(d.noise_white(ms(260), r), 1200, 5200, 1.0)
        splash = d.buf_mul(splash, d.env_adsr(ms(260), 0.004, 0.09, 0.35, 0.20))
        low = d.buf_mul(d.svf(d.noise_white(ms(300), r), 700, 200, 0.8), d.env_exp(ms(300), 0.07))
        drops = d.buf_mul(d.svf(d.noise_white(ms(60), r), 5000, 2600, 2.2),
                          d.env_perc(ms(60), 0.002, 0.014))
        return d.mixdown([(splash, 1.0), (low, 0.5), (d.buf_offset(drops, 0.110), 0.45)], n_i)

    # Jawne seedy zamiast hash(name): hash() na stringu jest losowany
    # per-proces (PYTHONHASHSEED), przez co kroki wychodziły inaczej
    # przy każdym bake'ie, wbrew kontraktowi deterministyczności.
    for seed, name, fn in ((0xD100, "concrete", step_concrete),
                           (0xD200, "metal", step_metal),
                           (0xD300, "dirt", step_dirt),
                           (0xD400, "water", step_water)):
        for i in range(3):
            r = Rng(seed + i * 7717)
            render("step_%s_%d" % (name, i + 1), fn(r), 16.0 if name == "water" else None)

    # Upadek — twardy
    render("land_hard", d.schroeder(d.mixdown([
        (d.buf_mul(d.svf(d.noise_white(ms(120), Rng(0xE100)), 1200, 180, 1.1),
                   d.env_perc(ms(120), 0.001, 0.035)), 1.0),
        (d.buf_mul(d.osc(d.wt_sine(), ms(150), 105, 52), d.env_perc(ms(150), 0.001, 0.050)), 0.8),
    ], ms(300)), 0.5, 0.4, 0.18))

    # Wysiłek / oddech przy skoku — brzmi jak człowiek, nie jak robot
    for i in range(2):
        r = Rng(0xE200 + i * 2749)
        n_i = ms(320)
        e = d.fm2(n_i, 128.0, ratio=1.6, index=3.0, index_end=1.2, vib_hz=5.0, vib_cents=40.0)
        e = d.buf_mul(e, d.env_adsr(n_i, 0.05, 0.12, 0.5, 0.18))
        render("effort_%d" % (i + 1), d.saturate(e, 1.5))

    # Krzyk przy bólu — krótki, suchy (mikrofon: VAD doda +20 Uwagi, patrz GDD §8.2)
    for i in range(2):
        r = Rng(0xE300 + i * 1871)
        n_i = ms(520)
        v = d.fm2(n_i, 210.0 - i * 15, ratio=1.31, index=8.0, index_end=2.0, vib_hz=7.5, vib_cents=150.0)
        v = d.buf_mul(v, d.env_adsr(n_i, 0.02, 0.16, 0.45, 0.30))
        v = d.buf_add_scaled(v, d.buf_mul(d.svf(d.noise_white(n_i, r), 3400, 1100, 0.9),
                                           d.env_adsr(n_i, 0.03, 0.2, 0.4, 0.3)), 0.35)
        render("player_hurt_%d" % (i + 1), d.saturate(d.schroeder(v, 0.55, 0.4, 0.16), 1.6), 12.0)

    # Upadek (down) — cięższy krzyk + upadek
    render("player_down", d.schroeder(d.mixdown([
        (d.buf_mul(d.fm2(ms(900), 180.0, ratio=1.33, index=9.0, index_end=1.5,
                          vib_hz=6.0, vib_cents=200.0),
                   d.env_adsr(ms(900), 0.03, 0.3, 0.35, 0.55)), 0.9),
        (d.buf_mul(d.svf(d.noise_white(ms(300), Rng(0xE400)), 1100, 200, 1.0),
                   d.env_perc(ms(300), 0.001, 0.09)), 0.9),
    ], ms(900)), 0.5, 0.4, 0.20), 14.0)

    # Podniesienie (revive) — rosnący sygnał „jestem żywy"
    render("revive", d.buf_mul(
        d.osc(d.wt_triangle(), ms(900), 300, 620), d.env_adsr(ms(900), 0.15, 0.2, 0.7, 0.4)))

    # Serce — dwie prędkości, spinacz napięcia bez muzyki
    asset("heart_fast_loop", "sfx/player/heart_fast_loop", loop=True)
    asset("heart_slow_loop", "sfx/player/heart_slow_loop", loop=True)
    for key, bpm in (("heart_fast_loop", 132.0), ("heart_slow_loop", 74.0)):
        period = int(SR * 60.0 / bpm)
        loop_n = period * 4                  # pętla = dokładnie 4 uderzenia
        xf = ms(60)
        n_i = loop_n + xf                    # + początek 5. uderzenia do szwu
        beats = [0.0] * n_i
        # Dwukomorowy stuk: „lub" (krótsze, głośniejsze) + „dum" (dłuższe,
        # cichsze). Ciało (sinus 62→44 Hz) jest PER UDERZENIE — wcześniej jeden
        # sweep szedł przez cały plik, więc każde uderzenie miało inną wysokość,
        # a szew pętli skakał z 44 na 62 Hz.
        e1 = d.env_perc(period, 0.008, period / SR * 0.30)
        e2 = d.env_perc(period, 0.010, period / SR * 0.45)
        body = d.osc(d.wt_sine(), period, 62, 44)
        thump = d.saturate([b * (x + 0.45 * y) for b, x, y in zip(body, e1, e2)], 2.0)
        for b in range(5):
            st = b * period
            v = 0.9 if b % 2 == 0 else 0.62
            for j in range(period):
                if st + j < n_i:
                    beats[st + j] += thump[j] * v
        render(key, beats, None, 0.6, period=loop_n, xfade=xf)

    # Oddech — pętla do napiętnego oddechu (adrenalina)
    asset("breath_loop", "sfx/player/breath_loop", loop=True)
    n_i = ms(3000)
    r = Rng(0xE600)
    br = d.fm2(n_i, 175.0, ratio=1.0, index=2.0, index_end=1.2, vib_hz=3.0, vib_cents=25.0)
    nz = d.svf(d.noise_white(n_i, r), 2000, 700, 1.6)
    envl = [0.0] * n_i
    for k in range(4):
        st = int(n_i * (0.08 + 0.235 * k))
        e = d.env_adsr(n_i - st, 0.28, 0.12, 0.5, 0.35)
        for j in range(n_i - st):
            envl[st + j] += e[j] * 0.8
    render("breath_loop", d.mixdown([(d.buf_mul(br, envl), 0.6),
                                     (d.buf_mul(nz, envl), 0.4)], n_i), 10.0)


# ============================================================ UI

def build_ui() -> None:
    global _CUR
    _CUR = "sfx/ui"
    r = Rng(0xF000)
    render("ui_click", d.mixdown([
        (d.buf_mul(d.osc(d.wt_square(0.4), ms(45), 1400, 900), d.env_perc(ms(45), 0.0004, 0.008)), 0.7),
        (d.buf_mul(d.svf(d.noise_white(ms(25), r), 4000, 1500, 1.2), d.env_perc(ms(25), 0.0003, 0.005)), 0.6),
    ], ms(60)))
    render("ui_confirm", d.mixdown([
        (d.buf_mul(d.osc(d.wt_square(0.4), ms(120), 880, 1320), d.env_adsr(ms(120), 0.004, 0.03, 0.6, 0.07)), 0.8),
        (d.buf_mul(d.osc(d.wt_sine(), ms(160), 1760, 2640), d.env_adsr(ms(160), 0.006, 0.05, 0.4, 0.09)), 0.35),
    ], ms(180)))
    render("ui_deny", d.mixdown([
        (d.buf_mul(d.osc(d.wt_square(0.5), ms(180), 320, 180), d.env_adsr(ms(180), 0.004, 0.06, 0.5, 0.10)), 0.9),
    ], ms(220)))
    # Ostrzeżenie o stalkerze — pulsujący sygnał HUD (nie pętla: robi to director)
    render("warn_pulse", d.mixdown([
        (d.buf_mul(d.osc(d.wt_sine(), ms(220), 220, 165), d.env_adsr(ms(220), 0.02, 0.05, 0.6, 0.13)), 0.9),
        (d.buf_mul(d.svf(d.noise_white(ms(60), r), 900, 300, 1.0), d.env_perc(ms(60), 0.005, 0.030)), 0.4),
    ], ms(260)))
    render("oc_load", d.mixdown([
        (d.buf_mul(d.osc(d.wt_square(0.4), ms(260), 300, 760), d.env_adsr(ms(260), 0.01, 0.08, 0.55, 0.15)), 0.8),
        (d.buf_mul(d.svf(d.noise_white(ms(300), r), 1200, 4200, 1.2), d.env_exp(ms(300), 0.11)), 0.5),
    ], ms(320)), 16.0)


# ============================================================ AMBIENT

def build_ambience() -> None:
    global _CUR
    _CUR = "amb"
    # Wiatr — warstwa bazowa na zewnątrz. Poryw -> płynne LFO filtra.
    asset("amb_wind", "amb/amb_wind", loop=True)
    n_i = ms(9000)
    r = Rng(0x1100)
    w = d.noise_brown(n_i, r)
    lfo = [0.0] * n_i
    for i in range(n_i):
        t = i / SR
        g = 0.5 + 0.28 * math.sin(d.TAU * 0.11 * t) + 0.16 * math.sin(d.TAU * 0.043 * t + 1.1) \
            + 0.10 * math.sin(d.TAU * 0.29 * t + 2.3)
        lfo[i] = g
    w = d.svf(w, 420, 900, 0.8)
    for i in range(n_i):
        w[i] *= lfo[i]
    render("amb_wind", d.buf_mul(w, d.env_adsr(n_i, 1.4, 0.8, 0.9, 1.6)), 24.0)

    # Owady / las — utrzymuje „bór jest żywy" (a nie martwy)
    asset("amb_forest", "amb/amb_forest", loop=True)
    n_i = ms(7000)
    r = Rng(0x1200)
    base = d.svf(d.noise_white(n_i, r), 6000, 4200, 0.7)
    base = d.buf_mul(base, [0.35 + 0.12 * math.sin(d.TAU * 0.2 * i / SR) for i in range(n_i)])
    chirps = [0.0] * n_i
    for _ in range(90):
        st = int(r.uniform(0, n_i - ms(200)))
        f = r.uniform(3200, 6200)
        ln = ms(r.uniform(12, 45))
        ch = d.buf_mul(d.osc(d.wt_sine(), ln, f, f * r.uniform(0.85, 1.2)), d.env_perc(ln, 0.003, ln / SR * 0.4))
        for j in range(ln):
            if st + j < n_i:
                chirps[st + j] += ch[j] * 0.5
    render("amb_forest", d.mixdown([(base, 1.0), (chirps, 0.9)], n_i), 30.0)

    # Maszyneria / prąd — wnętrza Obiektu 86
    asset("amb_machine", "amb/amb_machine", loop=True)
    n_i = ms(6000)
    r = Rng(0x1300)
    hum = d.osc(d.wt_square(0.42), n_i, 100.0, 100.0)
    hum = d.buf_add_scaled(hum, d.buf_scale(d.osc(d.wt_sine(), n_i, 50.0, 50.0), 0.7), 0.6)
    grit = d.svf(d.noise_white(n_i, r), 1400, 500, 1.1)
    render("amb_machine", d.mixdown([(d.buf_mul(hum, 0.4), 0.8),
                                     (d.buf_mul(grit, 0.16), 0.6)], n_i), 18.0)

    # Krople / wilgoć
    asset("amb_drips", "amb/amb_drips", loop=True)
    n_i = ms(6000)
    r = Rng(0x1400)
    bed = d.svf(d.noise_white(n_i, r), 500, 180, 0.9)
    bed = d.buf_mul(bed, 0.35)
    drops = [0.0] * n_i
    for _ in range(16):
        st = int(r.uniform(0, n_i - ms(400)))
        f = r.uniform(700, 2100)
        ln = ms(r.uniform(40, 130))
        dr = d.buf_mul(d.osc(d.wt_sine(), ln, f, f * 0.42), d.env_exp(ln, 0.030))
        dr = d.buf_add_scaled(dr, d.buf_mul(d.svf(d.noise_white(ms(14), r), 6000, 2500, 1.4),
                                            d.env_perc(ms(14), 0.0004, 0.004)), 0.4)
        for j in range(ln):
            if st + j < n_i:
                drops[st + j] += dr[j]
    render("amb_drips", d.mixdown([(bed, 1.0), (drops, 1.0)], n_i), 28.0)

    # Powietrze w szybie (pętla napięcia, gdy nie ma jeszcze stalkera)
    asset("amb_air", "amb/amb_air", loop=True)
    n_i = ms(8000)
    r = Rng(0x1500)
    a = d.svf(d.noise_white(n_i, r), 260, 120, 0.8)
    a = d.buf_mul(a, [0.5 + 0.35 * math.sin(d.TAU * 0.07 * i / SR + 0.5) for i in range(n_i)])
    render("amb_air", d.buf_mul(a, d.env_adsr(n_i, 1.5, 1.0, 0.9, 2.0)), 26.0)


# ============================================================ MUZYKA (warstwowa)

BPM = 84.0
BEATS = 16
BEAT = 60.0 / BPM
LOOP_S = BEATS * BEAT


def _at(beat: float) -> int:
    return int(beat * BEAT * SR)


def _tall_low(freq, at, ln, amp):
    """Niskie uderzenie basowe do warstwy napięcia (sub zamiast pełnego basu)."""
    k = d.buf_mul(d.osc(d.wt_sine(), ln, freq, freq * 0.70), d.env_perc(ln, 0.001, 0.12))
    return d.buf_offset_n(d.buf_scale(k, amp), at)


def _chord(bar: int) -> tuple:
    """Dm → Bb → Gm → A. i-VI-iv-V1: klasyczny mroczny krążek zakończony
    dominantą, która ciągnie do powrotu do Dm — pętla nigdy się nie 'zamyka'."""
    return [
        (73.42, 87.31, 110.00),   # Dm
        (116.54, 146.83, 174.61),  # Bb
        (98.00, 116.54, 146.83),   # Gm
        (110.00, 138.59, 164.81),  # A
    ][bar % 4]


def build_music() -> None:
    global _CUR
    _CUR = "music"
    # Pętla = dokładnie 16 taktów (LOOP_S). Bufor ma o jedno uderzenie więcej:
    # warstwy rytmiczne grają w nim początek „taktu 5" (= takt 1, Dm), który
    # loop_period() przenika w głowę. Wcześniej loop_xfade() ucinał 0,5 s,
    # a ogony nut wydłużały plik (combat 13,1 s zamiast 11,4 s) — rytm
    # przeskakiwał przy każdym obiegu.
    loop_n = _at(BEATS)
    xf = _at(1)
    n_i = loop_n + xf
    rng = Rng(0x2200)

    def pad(freqs, detune=0.004):
        """Detunowane sawy + wolne otwarcie filtra — 'ciepły' pad lat 80."""
        acc = [0.0] * n_i
        for f in freqs:
            for k in (-1, 1):
                fk = f * (1.0 + k * detune)
                w = d.osc(d.wt_saw(24), n_i, fk, fk, phase=rng.uniform(0.0, 1.0))
                w = d.svf(w, 2400, 620, 1.0)
                d.buf_add_scaled(acc, w, 0.33)
        return acc

    def sub(freq, amp=1.0):
        o = d.osc(d.wt_sine(), n_i, freq, freq)
        return d.buf_mul(o, d.env_adsr(n_i, 1.2, 0.6, 0.9, 2.4))

    def kick(at, amp=1.0):
        ln = ms(280)
        k = d.buf_mul(d.osc(d.wt_sine(), ln, 105, 42), d.env_perc(ln, 0.001, 0.055))
        k = d.buf_add_scaled(k, d.buf_mul(d.svf(d.noise_white(ms(20), Rng(int(at * 4) + 7)), 2500, 600, 1.0),
                                          d.env_perc(ms(20), 0.0004, 0.006)), 0.5)
        return d.buf_offset_n(d.buf_scale(k, amp), _at(at))

    def hat(at, amp=1.0, dur=0.03):
        ln = ms(90)
        h = d.svf(d.noise_white(ln, Rng(int(at * 4) + 13)), 9000, 5500, 0.6)
        return d.buf_offset_n(d.buf_mul(h, d.env_perc(ln, 0.0004, dur)), _at(at))

    def tom(at, freq, amp=1.0):
        ln = ms(220)
        t = d.buf_mul(d.fm2(ln, freq, ratio=1.2, index=5.0, index_end=1.2), d.env_perc(ln, 0.001, 0.055))
        return d.buf_offset_n(d.buf_scale(t, amp), _at(at))

    def stab(at, freqs, amp=1.0, dur=0.10):
        ln = ms(420)
        acc = [0.0] * ln
        for f in freqs:
            s = d.fm2(ln, f, ratio=3.0, index=5.0, index_end=1.5)
            d.buf_add_scaled(acc, s, 0.35)
        acc = d.svf(acc, 4200, 1400, 0.8)
        acc = d.buf_mul(acc, d.env_perc(ln, 0.002, dur))
        return d.buf_offset_n(d.buf_scale(acc, amp), _at(at))

    def bass(at, freq, dur_beats, amp=1.0):
        ln = _at(dur_beats) + ms(60)
        b = d.osc(d.wt_square(0.42), ln, freq, freq * 0.985)
        b = d.svf(b, 900, 380, 1.3)
        b = d.buf_mul(b, d.env_adsr(ln, 0.005, 0.06, 0.75, dur_beats * BEAT * 0.35))
        return d.buf_offset_n(d.buf_scale(b, amp), _at(at))

    rng = Rng(0x2200)
    rnd = lambda: rng.uniform()

    # --- warstwa 0: CISZA — cichy, ciemny pad + sub + powietrze (Uwaga < 20%)
    # Wcześniej pętla dodawała WSZYSTKIE 4 akordy naraz na całą długość
    # (24 piły: A z B♭, C♯ z D) i 4 suby naraz (37/49/55/58 Hz dudniły),
    # a filtry przesuwały odcięcie przez cały bufor (2400→620 Hz), więc na
    # szwie barwa skakała. Po saturacji wychodził statyczny, nieprzyjemny
    # klaster. Teraz: jeden akord na takt z przenikaniem, sub-pedał D, stałe
    # filtry, bez saturacji i bez szumu. Takt 5 = takt 1 (Dm) — szew pętli (loop_period).
    sil = [0.0] * n_i
    bar_n = _at(4)
    xs = ms(600)                       # przenikanie akordów 0,6 s
    seg = bar_n + xs
    for bar in range(5):
        ch = _chord(bar)
        st = bar * bar_n
        env = d.env_adsr(seg, 0.6, 0.2, 0.85, 0.6)
        pd = [0.0] * seg
        for f in ch:
            for k in (-1, 1):
                fk = f * (1.0 + k * 0.0018)
                w = d.osc(d.wt_saw(12), seg, fk, fk, phase=rng.uniform(0.0, 1.0))
                d.buf_add_scaled(pd, d.svf(w, 700, 700, 0.6), 0.33)
        d.buf_add_scaled(sil, d.buf_offset_n(d.buf_mul(pd, env), st), 0.10)
    # Sub = jeden pedał D przez całą pętlę (sub per takt nakładał się przy
    # zmianie akordu: 49 + 55 Hz dudniły 6 Hz). Częstotliwość dobrana tak,
    # żeby w pętli zmieściła się całkowita liczba okresów — szew bez skoku fazy.
    loop_s = loop_n / SR
    f_ped = round(36.71 * loop_s) / loop_s
    d.buf_add_scaled(sil, d.osc(d.wt_sine(), n_i, f_ped, f_ped), 0.30)
    # Bez „powietrza": szum po wąskim filtrze dolnoprzepustowym ma losowo
    # falującą obwiednię 4–40 Hz (pomiar: 56% dudnienia wobec 0,6% padu) —
    # to był słyszalny „statyczny" szum przy Uwadze 0%. Atmosferę daje ambient.
    # Bez syku taśmy z tego samego powodu; wow zostaje (ruch padu).
    sil = d.tape(sil, wow_hz=0.23, wow_depth=0.0018, hiss=0.0, sat=1.0)
    asset("mus_silence", "music/mus_silence", loop=True)
    render("mus_silence", sil, 30.0, rms=0.045, period=loop_n, xfade=xf)

    # --- warstwa 1: NAPIĘCIE — pulsujący ostinato + rytm na rozmytych
    ten = [0.0] * n_i
    for bar in range(5):
        ch = _chord(bar)
        for b8 in range(8):
            at = bar * 4 + b8 * 0.5
            f = ch[b8 % 3] * 2.0
            ln = ms(520)
            o = d.osc(d.wt_triangle(), ln, f, f)
            o = d.svf(o, 1900, 620, 1.6)
            amp = 0.30 + (0.34 if b8 in (0, 3, 6) else 0.0)
            d.buf_add_scaled(ten, d.buf_offset_n(d.buf_mul(o, d.env_perc(ln, 0.008, 0.10)), _at(at)), amp)
        d.buf_add_scaled(ten, bass(bar * 4, ch[0] / 2.0, 1.6, 0.30), 1.0)
    ten = d.tape(ten, wow_hz=0.31, wow_depth=0.003, hiss=0.002, sat=1.25)
    asset("mus_tension", "music/mus_tension", loop=True)
    render("mus_tension", d.saturate(ten, 1.8), 26.0, rms=0.068, period=loop_n, xfade=xf)

    # --- warstwa 2: WALKA — perkusja 16., arpeggio FM, bas
    com = [0.0] * n_i
    for bar in range(5):
        ch = _chord(bar)
        for b16 in range(16):
            at = bar * 4 + b16 * 0.25
            amp = 0.34 if b16 % 4 == 0 else (0.20 if b16 % 2 == 0 else 0.11)
            d.buf_add_scaled(com, hat(at, amp, 0.022 + 0.02 * rnd()), 1.0)
        d.buf_add_scaled(com, kick(bar * 4, 0.85), 1.0)
        d.buf_add_scaled(com, kick(bar * 4 + 2.5, 0.62), 1.0)
        for step in range(8):
            at = bar * 4 + step * 0.5
            d.buf_add_scaled(com, bass(at, ch[0] / 2.0, 0.42, 0.75), 1.0)
        for step in (1.5, 3.0, 5.0, 6.5):
            f = ch[(int(step) % 3)] * 4.0
            d.buf_add_scaled(com, stab(step + bar * 4, [f, f * 1.5], 0.30, 0.07), 1.0)
    com = d.saturate(d.tape(com, wow_hz=0.4, wow_depth=0.0035, hiss=0.0028, sat=1.5), 1.8)
    asset("mus_combat", "music/mus_combat", loop=True)
    render("mus_combat", d.saturate(com, 1.8), 22.0, rms=0.118, period=loop_n, xfade=xf)

    # --- warstwa 3: POŚCIG — 16. bas, rolli tomów, klastra dysonansowe
    chs = [0.0] * n_i
    for bar in range(5):
        ch = _chord(bar)
        for b16 in range(16):
            at = bar * 4 + b16 * 0.25
            d.buf_add_scaled(chs, bass(at, ch[0] / 2.0, 0.24, 0.55), 1.0)
            d.buf_add_scaled(chs, hat(at, 0.30 if b16 % 4 else 0.5, 0.018), 1.0)
        d.buf_add_scaled(chs, kick(bar * 4, 1.0), 1.0)
        d.buf_add_scaled(chs, kick(bar * 4 + 1.75, 0.5), 1.0)
        d.buf_add_scaled(chs, kick(bar * 4 + 2.75, 0.6), 1.0)
        roll_start = bar * 4 + 2.5
        for r_i in range(8):
            d.buf_add_scaled(chs, tom(roll_start + r_i * 0.1875, 140 + r_i * 9, 0.28 + 0.05 * r_i), 1.0)
        # trójdźwięk bisektowy (tritonia) — napięcie bez melodii
        c = _chord(bar)
        d.buf_add_scaled(chs, stab(bar * 4 + 0.0, [c[1] * 4, c[1] * 4 * 1.26], 0.34, 0.05), 1.0)
        d.buf_add_scaled(chs, stab(bar * 4 + 3.0, [c[2] * 4, c[2] * 4 * 1.19], 0.34, 0.05), 1.0)
    chs = d.saturate(d.tape(chs, wow_hz=0.55, wow_depth=0.005, hiss=0.0035, sat=2.0), 2.4)
    asset("mus_chase", "music/mus_chase", loop=True)
    render("mus_chase", d.saturate(chs, 1.8), 18.0, rms=0.145, period=loop_n, xfade=xf)

    # --- stinger (przejścia, nie warstwy)
    render("sting_tension", d.buf_norm(d.tape(d.mixdown([
        (d.buf_mul(d.svf(d.noise_white(ms(1500), rng), 260, 4200, 1.2),
                   d.env_adsr(ms(1500), 1.0, 0.2, 0.6, 0.35)), 0.8),
        (d.buf_mul(d.fm2(ms(1500), 70.0, ratio=1.5, index=1.0, index_end=8.0),
                   d.env_adsr(ms(1500), 0.9, 0.2, 0.7, 0.35)), 0.6),
    ], ms(1500)), wow_hz=0.7, wow_depth=0.008, sat=1.4), 0.80), 24.0)

    render("sting_chase", d.buf_norm(d.saturate(d.mixdown([
        (d.buf_mul(d.osc(d.wt_sine(), ms(1200), 92, 41), d.env_perc(ms(1200), 0.001, 0.24)), 1.0),
        (d.buf_mul(d.svf(d.noise_white(ms(1400), rng), 5200, 700, 0.9),
                   d.env_adsr(ms(1400), 0.01, 0.35, 0.45, 0.55)), 0.8),
        (d.buf_mul(d.fm2(ms(1400), 233.0, ratio=1.41, index=12.0, index_end=2.0),
                   d.env_adsr(ms(1400), 0.02, 0.30, 0.4, 0.55)), 0.7),
    ], ms(1400)), 2.2), 0.85), 14.0)


def _tap(freq, at, ln, amp):
    k = d.buf_mul(d.osc(d.wt_sine(), ln, freq, freq * 0.7), d.env_perc(ln, 0.001, 0.12))
    return d.buf_scale(k, amp)


# ============================================================ manifest

BANK_JSON = os.path.join(AUDIO, "_bank.json")


def load_bank() -> None:
    """Wczytuje indeks z poprzednich przebiegów.

    Bez tego manifest po `bake_audio.py --only weapons` zawierałby tylko broń
    i runtime by gubił assety z poprzednich grup. Budowanie od zera (--reset)
    czyści indeks."""
    if "--reset" in sys.argv or not os.path.exists(BANK_JSON):
        return
    try:
        import json
        with open(BANK_JSON, encoding="utf-8") as f:
            for k, v in json.load(f).items():
                REG[k] = (v[0], bool(v[1]))
    except Exception as e:  # uszkodzony indeks nie może zablokować bake'u
        print("  ! nie udało się wczytać _bank.json (%s) — zapisuję od zera" % e)


def write_bank() -> None:
    import json
    os.makedirs(AUDIO, exist_ok=True)
    with open(BANK_JSON, "w", encoding="utf-8") as f:
        json.dump({k: [v[0], int(v[1])] for k, v in sorted(REG.items())}, f,
                  indent=1, ensure_ascii=False)


def write_manifest() -> None:
    lines = [
        "extends RefCounted",
        "# GENEROWANE przez tools/bake_audio.py — nie edytuj ręcznie.",
        "# Tablica ścieżek + flagi pętli. Runtime ładuje leniwie (load) i cache'uje.",
        "",
        "const PATHS := {",
    ]
    for key in sorted(REG):
        path, _ = REG[key]
        lines.append('\t"%s": "res://audio/%s.wav",' % (key, path))
    lines.append("}")
    lines.append("")
    lines.append("# Klucze, które muszą się zapętlać (nie mogą mieć fade-outu).")
    lines.append("const LOOPS := [")
    for key in sorted(REG):
        if REG[key][1]:
            lines.append('\t"%s",' % key)
    lines.append("]")
    lines.append("")
    lines.append("# Warstwy muzyki adaptacyjnej — w tej kolejności nakładają się "
                 "(kumulatywne: cisza ⊂ napięcie ⊂ walka ⊂ pościg).")
    lines.append("const MUSIC_STEMS := [\"mus_silence\", \"mus_tension\", "
                 "\"mus_combat\", \"mus_chase\"]")
    lines.append("")
    lines.append("# Sugerowane czasy przejścia w sekundach (asymetryczne celowo).")
    lines.append("const MUSIC_BLEND := [4.0, 1.6, 0.7, 0.35]")
    lines.append("")
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


# ============================================================ runner

BUILDERS = [
    ("weapons", build_weapons),
    ("stalker", build_stalker),
    ("world", build_world),
    ("player", build_player),
    ("ui", build_ui),
    ("ambience", build_ambience),
    ("music", build_music),
]


def main() -> int:
    force = "--force" in sys.argv
    only = None
    do_list = "--list" in sys.argv
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")

    load_bank()

    # Rejestracja assetów musi się wykonać przed renderowaniem, więc każdy
    # builder sam rejestruje w trakcie, a write_bank/write_manifest scalają
    # wynik z pełnym indeksem.
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        t0 = time.time()
        before = len(REG)
        fn()
        print("[%-8s] %3d assetów  %5.1fs" % (name, len(REG) - before, time.time() - t0))

    write_bank()
    write_manifest()
    total = len(REG)
    loops = sum(1 for v in REG.values() if v[1])
    print("-" * 52)
    missing = [k for k, (p, _) in REG.items()
               if not os.path.exists(os.path.join(AUDIO, p + ".wav"))]
    print("manifest: %s" % MANIFEST)
    print("bank: %d ścieżek, %d pętli, brakujących plików: %d"
          % (total, loops, len(missing)))
    for k in missing[:10]:
        print("   ! brak pliku: %s" % k)
    if do_list:
        for k in sorted(REG):
            print("   %-28s %s%s" % (k, REG[k][0], "  [loop]" if REG[k][1] else ""))
    # Godot nie słucha samego WAV-a — gra z .godot/imported/*.sample.
    # Po przebake'owaniu trzeba przepuścić import, inaczej w oknie grają
    # STARE sample'i i wszystkie poprawki brzmią jakby ich nie było.
    print("pamięć audio: %.1f MB WAV" % (
        sum(os.path.getsize(os.path.join(dp, f))
            for dp, _, fs in os.walk(AUDIO) for f in fs if f.endswith(".wav")) / 1048576.0))
    print("NASTĘPNY KROK: godot --headless --path . --import  (inaczej grają stare sample'e)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())