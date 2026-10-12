"""
bake_hybrid.py — assety ze źródeł nagranych i wygenerowanych (AUDIO_PLAN.md, F2: pilotaż).

Na razie wszystko tutaj to WERSJE ALTERNATYWNE do odsłuchu (bc.alt): pliki trafiają do katalogu z --alts,
a gra dalej używa syntezy z bake_weapons.py / bake_sfx.py. Po odsłuchu A/B wybrana wersja przechodzi do
właściwego buildera przez bc.hybrid(...) i dopiero wtedy podmienia WAV-y w audio/.

    python tools/bake_audio.py --only alts --alts ../build/audio_alt
    python tools/audio_ab.py --alts ../build/audio_alt

Zasady składania (wnioski z pomiaru źródeł, nie z odsłuchu — brzmienie ocenia się na stronie A/B):
  * Strzał = nagranie bliskie (trzask, góra pasma) + nagranie z otwartego terenu (środek, naturalny ogon)
    + syntetyczny sub (kopnięcie, którego mikrofony przy lufie nie łapią). Ataki warstw równane co do próbki.
  * Krok = pojedynczy krok wycięty z nagranego marszu; bez dokładanego basu (but na betonie go nie ma).
  * Głos = nagranie albo plik wygenerowany, obniżony jak taśma (wolniej = niżej i dłużej), z oktawą w dół pod spodem.
  * Pogłosu hali nie pieczemy poza głosem Stalkera (tak samo jak w wersji syntetycznej) — dokłada go silnik.
"""

from __future__ import annotations

import numpy as np

import audio_dsp as d
from audio_dsp import Rng, ms
import bake_common as bc
from bake_common import finalize, ir, thump, vary

# --- M-83: karabin automatyczny. Źródła: AKM z 1 m (trzy strzały co ok. 200 ms) i AK-47 w otwartym terenie (pięć pojedynczych).
M83_NEEDS = ["akm_close_1m", "ak47_open_2m"]
_AKM_SHOTS = (0.141, 0.369, 0.570)                  # początki strzałów w akm_close_1m [s]
_AK47_SHOTS = (0.83, 5.55, 9.54, 13.85, 17.97)      # pojedyncze strzały w ak47_open_2m [s]
M83_DRIVE = 2.0
M83_CEIL = -5.0


def _m83_shot(i: int) -> np.ndarray:
    r = Rng(0x8300 + i * 7919)
    n = ms(480)
    # bliski mikrofon: sam front strzału (następny strzał serii wchodzi po ~200 ms, więc ucinamy wcześniej)
    close = d.from_onset(bc.src("akm_close_1m", _AKM_SHOTS[i % 3] - 0.02, 0.19), 0.5)
    close = close[:ms(150)] * d.env_pts(min(len(close), ms(150)), [(0, 1), (.06, 1), (.15, 0)])
    # otwarty teren: korpus i ogon
    body = d.from_onset(bc.src("ak47_open_2m", _AK47_SHOTS[(i * 2) % 5] - 0.03, 0.75), 0.5)
    body = d.repitch(body, r.bipolar(0.35))
    body = body[:n] * d.env_pts(min(len(body), n), [(0, 1), (.24, 1), (.48, 0)])
    sub = thump(0.16, vary(r, 96, .06), vary(r, 46, .06), 0.03, 0.045)
    x = d.mix([(close / (d.peak(close) + 1e-9), 0.80), (body / (d.peak(body) + 1e-9), 1.0), (sub, 0.42)], n)
    x = d.filt(x, "hp", 38.0, order=4)
    x = d.saturate(x / (d.peak(x) + 1e-9), M83_DRIVE)         # sklejenie warstw
    return d.limiter(x, M83_CEIL)                              # ścięcie samego czubka: ta sama głośność przy tym samym szczycie co w wersji syntetycznej


def _m83() -> None:
    for i in range(6):
        finalize("m83_shot_%d" % (i + 1), _m83_shot(i), lufs=-14.0)


# --- Krok po betonie: but wojskowy, czysty beton. Pięć kroków o zbliżonym poziomie i wyraźnym stuknięciu obcasa.
STEP_NEEDS = ["boot_concrete_walk"]
_STEPS = (1.10, 3.11, 4.10, 7.58, 11.58)


def _step_concrete() -> None:
    for i, t in enumerate(_STEPS):
        x = d.from_onset(bc.src("boot_concrete_walk", t - 0.04, 0.36), 2.0, thr_db=-20.0)
        n = min(len(x), ms(280))
        x = d.filt(x[:n] * d.env_pts(n, [(0, 1), (.16, 1), (.28, 0)]), "hp", 60.0, order=2)
        x = d.filt(x, "highshelf", 3500.0, gain_db=3.0)             # nagranie jest ciemne powyżej 4 kHz — odrobina szurnięcia podeszwy
        finalize("step_concrete_%d" % (i + 1), x, lufs=-21.5)


# --- Warkot Stalkera: dwie wersje do wyboru — z nagrania i wygenerowana.
def _growl(x: np.ndarray, semis: float, i: int) -> np.ndarray:
    x = d.repitch(x, semis)
    n = len(x)
    low = d.lp(d.repitch(x, -12.0)[:n], 180.0)                      # oktawa niżej pod spodem: ciężar bez zamulania środka
    y = d.mix([(x / (d.peak(x) + 1e-9), 1.0), (d.pad_to(low, n) / (d.peak(low) + 1e-9), 0.35)], n)
    y = d.saturate(d.filt(y, "hp", 28.0, order=2), 1.6)
    return d.reverb(y, ir("hall"), wet=0.30 - 0.04 * i, keep_len=False)


GROWL_LIB_NEEDS = ["monster_growls_4"]
_GROWL_LIB = ((0.12, 1.98), (12.42, 2.10))                           # dwa najniższe warknięcia w nagraniu (start, długość)


def _growl_lib() -> None:
    for i, (t, ln) in enumerate(_GROWL_LIB):
        x = bc.src("monster_growls_4", t, ln)
        x = x * d.env_pts(len(x), [(0, 0), (.02, 1), (ln - .12, 1), (ln, 0)])
        finalize("stalker_growl_%d" % (i + 1), _growl(x, -4.0, i), lufs=-14.0, fade_out_ms=250)


GROWL_GEN_NEEDS = ["stalker_growl_gen_a", "stalker_growl_gen_b"]


def _growl_gen() -> None:
    for i, sid in enumerate(GROWL_GEN_NEEDS):
        x = bc.src(sid)
        w = min(len(x), ms(2600))                                    # plik ma 5 s z pauzami — bierzemy najgłośniejsze 2,6 s
        e = np.cumsum(np.concatenate([[0.0], x ** 2]))
        k = int(np.argmax(e[w:] - e[:-w])) if len(x) > w else 0
        x = x[k:k + w]
        ln = len(x) / d.SR
        x = x * d.env_pts(len(x), [(0, 0), (.02, 1), (max(.03, ln - .15), 1), (ln, 0)])
        finalize("stalker_growl_%d" % (i + 1), _growl(x, -3.0, i), lufs=-14.0, fade_out_ms=250)


def build_alts() -> None:
    bc.alt("hybrid", _m83, M83_NEEDS)
    bc.alt("hybrid", _step_concrete, STEP_NEEDS)
    bc.alt("hybrid", _growl_lib, GROWL_LIB_NEEDS)
    bc.alt("gen", _growl_gen, GROWL_GEN_NEEDS)
