"""
bake_hybrid.py — wersje assetów Z NAGRAŃ z bibliotek (AUDIO_PLAN.md).

Dwa rodzaje przepisów:
  * wersje z nagrań dla GRY — funkcje wołane z builderów (bake_weapons.py, bake_sfx.py) zaraz po syntezie tego samego
    klucza, przez bc.hybrid(): plik trafia do audio_licensed/ (poza repo), a gra woli go od syntetycznego z audio/.
    Bez plików źródłowych na dysku nic się nie dzieje — zostaje sama synteza;
  * WERSJE ALTERNATYWNE do odsłuchu przed decyzją — build_alts() przez bc.alt(): katalog z --alts, gry nie dotykają.

    python tools/audio_lib_fetch.py sync                    # pobierz nagrania z rejestru
    python tools/bake_audio.py                              # synteza → audio/, wersje z nagrań → audio_licensed/
    python tools/audio_ab.py --licensed                     # odsłuch: synteza obok wersji z nagrań

Zasady składania (wnioski z pomiaru źródeł; brzmienie ocenia się uchem na stronie A/B):
  * Strzał = nagranie bliskie (trzask, góra pasma) + nagranie z otwartego terenu (środek, naturalny ogon)
    + syntetyczny sub (kopnięcie, którego mikrofony przy lufie nie łapią). Ataki warstw równane co do próbki.
  * Krok = pojedynczy krok wycięty z nagranego marszu; bez dokładanego basu (but na betonie go nie ma).
  * Głos = nagranie obniżone jak taśma (wolniej = niżej i dłużej), z oktawą w dół pod spodem.
  * Pogłosu hali nie pieczemy poza głosem Stalkera (tak samo jak w wersji syntetycznej) — dokłada go silnik.
  * Głośność (LUFS) i szczyt jak w wersji syntetycznej tego samego klucza: miks gry nie zależy od tego, którą wersję gra.

Wybrane w odsłuchu A/B 2026-10-12 (bramka A): m83_shot, step_concrete, stalker_growl.
"""

from __future__ import annotations

import numpy as np

import audio_dsp as d
from audio_dsp import Rng, ms
import bake_common as bc
from bake_common import finalize, ir, thump, vary


def _keys(base: str, n: int) -> list[str]:
    return ["%s_%d" % (base, i + 1) for i in range(n)]


# --- M-83: źródła — AKM z 1 m (trzy strzały co ok. 200 ms) i AK-47 w otwartym terenie (pięć pojedynczych).
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
    return d.limiter(x, M83_CEIL)                              # ścięcie samego czubka: ta sama głośność przy tym samym szczycie co w syntezie


def m83() -> None:
    def bake() -> None:
        for i in range(6):
            finalize("m83_shot_%d" % (i + 1), _m83_shot(i), lufs=-14.0)
    bc.hybrid(_keys("m83_shot", 6), bake, M83_NEEDS)


# --- Krok po betonie: but, czysty beton. Pięć kroków o zbliżonym poziomie i wyraźnym stuknięciu obcasa.
STEP_NEEDS = ["boot_concrete_walk"]
_STEPS = (1.10, 3.11, 4.10, 7.58, 11.58)


def step_concrete() -> None:
    def bake() -> None:
        for i, t in enumerate(_STEPS):
            x = d.from_onset(bc.src("boot_concrete_walk", t - 0.04, 0.36), 2.0, thr_db=-20.0)
            n = min(len(x), ms(280))
            x = d.filt(x[:n] * d.env_pts(n, [(0, 1), (.16, 1), (.28, 0)]), "hp", 60.0, order=2)
            x = d.filt(x, "highshelf", 3500.0, gain_db=3.0)         # nagranie jest ciemne powyżej 4 kHz — odrobina szurnięcia podeszwy
            finalize("step_concrete_%d" % (i + 1), x, lufs=-21.5)
    bc.hybrid(_keys("step_concrete", len(_STEPS)), bake, STEP_NEEDS)


# --- Warkot Stalkera: dwa najniższe warknięcia z nagrania, obniżone o 4 półtony.
GROWL_NEEDS = ["monster_growls_4"]
_GROWLS = ((0.12, 1.98), (12.42, 2.10))                              # (start, długość) w monster_growls_4 [s]


def _growl(x: np.ndarray, semis: float, i: int) -> np.ndarray:
    x = d.repitch(x, semis)
    n = len(x)
    low = d.lp(d.repitch(x, -12.0)[:n], 180.0)                      # oktawa niżej pod spodem: ciężar bez zamulania środka
    y = d.mix([(x / (d.peak(x) + 1e-9), 1.0), (d.pad_to(low, n) / (d.peak(low) + 1e-9), 0.35)], n)
    y = d.saturate(d.filt(y, "hp", 28.0, order=2), 1.6)
    return d.reverb(y, ir("hall"), wet=0.30 - 0.04 * i, keep_len=False)


def stalker_growl() -> None:
    def bake() -> None:
        for i, (t, ln) in enumerate(_GROWLS):
            x = bc.src("monster_growls_4", t, ln)
            x = x * d.env_pts(len(x), [(0, 0), (.02, 1), (ln - .12, 1), (ln, 0)])
            finalize("stalker_growl_%d" % (i + 1), _growl(x, -4.0, i), lufs=-14.0, fade_out_ms=250)
    bc.hybrid(_keys("stalker_growl", len(_GROWLS)), bake, GROWL_NEEDS)


def build_alts() -> None:
    """Wersje alternatywne do następnego odsłuchu A/B (bc.alt). Po bramce A nie ma żadnej w kolejce."""
