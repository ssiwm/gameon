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

Wybrane w odsłuchu A/B 2026-10-12: m83_shot, step_concrete, stalker_growl (bramka A); spread12_shot, srut8_shot,
srut8_pump, gniew4_shot, ciegno6_shot, explosion (F3, część 1). Odrzucone na rzecz syntezy: p64_shot (SIG P229 z 1 m)
i sokol6_shot (start fajerwerku) — przepisy usunięte, zostają w historii repo.
"""

from __future__ import annotations

import numpy as np

import audio_dsp as d
from audio_dsp import Rng, ms
import bake_common as bc
from bake_common import finalize, ir, ring, thump, vary


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


# ============================================================ F3: bronie
# Te same klucze co w syntezie z bake_weapons.py. Głośność docelowa = ZMIERZONA głośność wersji syntetycznej (średnia rodziny,
# LUFS po finalize) — nominalne cele z bake_weapons.py synteza osiąga tylko w części, bo ogranicza ją szczyt. Dzięki temu
# miks gry nie zależy od tego, która wersja gra. Nowe rodziny zaczynają jako kandydaci (CANDIDATES → build_alts);
# po odsłuchu wybrane przechodzą do weapons() i grają w grze.

def _unit(x: np.ndarray) -> np.ndarray:
    return x / (d.peak(x) + 1e-9)


def _fade(x: np.ndarray, hold: float, end: float) -> np.ndarray:
    """Pełny poziom do `hold` [s], potem liniowo do zera w `end` [s] (bufor przycięty do `end`)."""
    n = min(x.shape[-1], d.sec(end))
    return x[..., :n] * d.env_pts(n, [(0, 1), (hold, 1), (end, 0)])


def _decay(x: np.ndarray, hold: float, tau: float) -> np.ndarray:
    """Zaciśnięcie ogona: pełny poziom przez `hold` [s], potem wykładniczo ze stałą `tau` [s]. Nagrania ze strzelnicy
    niosą długi, głośny pogłos miejsca — w grze pogłos dokłada silnik, a strzał ma być krótki."""
    t = np.arange(x.shape[-1]) / d.SR
    return x * np.where(t < hold, 1.0, np.exp(-(t - hold) / tau))


def _glue(x: np.ndarray, drive: float, ceil: float) -> np.ndarray:
    """Sklejenie warstw strzału: odcięcie infradźwięków, nasycenie, ścięcie samego czubka (głośność przy tym samym szczycie)."""
    return d.limiter(d.saturate(_unit(d.filt(x, "hp", 38.0, order=4)), drive), ceil)


# --- Strzelby: Saiga-12 z 1 m (pięć pojedynczych strzałów z długim ogonem).
SPREAD12_NEEDS = ["saiga12_close_1m"]
SRUT8_NEEDS = ["saiga12_close_1m", "usas12_close_1m"]
_SAIGA = (8.00, 12.00, 16.00, 28.00, 32.01)
_USAS = (0.102, 0.395)


def _spread12_bake() -> None:
    for i, k in enumerate((0, 1, 3)):
        r = Rng(0x1200 + i * 7919)
        shot = _fade(_decay(d.from_onset(bc.src("saiga12_close_1m", _SAIGA[k] - 0.03, 0.80), 0.5), 0.05, 0.20), 0.30, 0.70)
        sub = thump(0.30, vary(r, 84, .06), vary(r, 34, .06), 0.05, 0.085)
        finalize("spread12_shot_%d" % (i + 1), _glue(d.mix([(_unit(shot), 1.0), (sub, 1.3)], ms(700)), 1.9, -4.0), lufs=-15.6)


def _srut8_bake() -> None:
    """Ciężka strzelba: ta sama Saiga o 3 półtony niżej (dłuższa i ciemniejsza) + front USAS-12 + większy sub."""
    for i, k in enumerate((2, 4, 0)):
        r = Rng(0x0880 + i * 7919)
        shot = d.repitch(d.from_onset(bc.src("saiga12_close_1m", _SAIGA[k] - 0.03, 0.80), 0.5), -3.0)
        shot = _fade(_decay(shot, 0.06, 0.28), 0.40, 0.92)
        front = _fade(d.from_onset(bc.src("usas12_close_1m", _USAS[i % 2] - 0.02, 0.28), 0.5), 0.10, 0.26)
        sub = thump(0.40, vary(r, 70, .06), vary(r, 28, .06), 0.07, 0.12)
        x = d.mix([(_unit(shot), 1.0), (_unit(front), 0.55), (sub, 1.7)], ms(920))
        finalize("srut8_shot_%d" % (i + 1), _glue(x, 2.0, -4.0), lufs=-14.8)


PUMP_NEEDS = ["shotgun_quick_pump"]
_PUMPS = (0.045, 1.065)                                             # dwa przeładowania pompką w nagraniu [s]


def _pump_bake() -> None:
    for i, t in enumerate(_PUMPS):
        x = _fade(bc.src("shotgun_quick_pump", t, 0.42), 0.34, 0.41)
        x = d.filt(d.filt(x, "hp", 90.0), "lowshelf", 400.0, gain_db=3.0)
        finalize("srut8_pump_%d" % (i + 1), d.reverb(x, ir("close"), wet=.12), lufs=-25.5)


# --- WRATH-4: odpalenie granatnika (nagranie granatnika dymnego: sam wystrzał, bez lądowania granatu) + niski korpus.
GNIEW4_NEEDS = ["grenade_launcher_smoke"]


def _gniew4_bake() -> None:
    for i in range(2):
        r = Rng(0x3100 + i * 5003)
        pop = d.repitch(d.from_onset(bc.src("grenade_launcher_smoke", 0.0, 1.15), 0.5), (0.0, -1.5)[i])
        pop = _fade(_decay(pop, 0.04, 0.16), 0.30, 0.80)
        body = thump(.30, vary(r, 95, .08), 36, .06, .11)
        x = d.saturate(_unit(d.filt(d.mix([(_unit(pop), 1.0), (body, 1.6)], ms(800)), "hp", 32.0, order=2)), 1.6)
        finalize("gniew4_shot_%d" % (i + 1), d.reverb(x, ir("hall"), wet=.3), peak=-2.0)


# --- SINEW-6: zwolnienie cięciwy kuszy (nagranie) + syntetyczny brzęk cięciwy pod spodem.
CIEGNO6_NEEDS = ["crossbow_loose"]


def _ciegno6_bake() -> None:
    for i in range(2):
        r = Rng(0x3400 + i * 2113)
        snap = d.repitch(d.from_onset(bc.src("crossbow_loose", 0.06, 0.34), 0.5), (0.0, -1.5)[i])
        twang = ring(r, [vary(r, 168, .06), vary(r, 336, .06), vary(r, 505, .06)], [.35, .22, .12], dur=.4)
        x = d.mix([(_unit(snap), 1.0), (twang, 0.35)], ms(420))
        finalize("ciegno6_shot_%d" % (i + 1), d.reverb(x, ir("close"), wet=.15), peak=-5.0)


# --- Wybuch: dwa nagrania dużych eksplozji (stereo) + syntetyczny sub.
EXPLOSION_SRC = ("explosion_large_08", "explosion_deep_02")


def _explosion_bake() -> None:
    for i, sid in enumerate(EXPLOSION_SRC):
        x = _fade(d.from_onset(bc.src(sid, 0.0, 2.8, mono=False), 1.0), 1.7, 2.6)
        r = Rng(0xA100 + i * 7717)
        sub = thump(1.4, 78, 24, .28, .45, attack=.004)
        crack = d.filt(d.white(ms(40), r), "hp", 1500, order=3) * d.env_perc(ms(40), .0002, .006) * 3.0   # ostry front jak w syntezie
        x = d.mix([(_unit(x), 1.0), (sub, 0.45), (crack, 0.5)], x.shape[-1])
        x = d.saturate(_unit(d.filt(x, "hp", 24.0, order=2)), 1.5)
        finalize("explosion_%d" % (i + 1), x, lufs=-16.7, fade_out_ms=120)


def weapons() -> None:
    """Wersje z nagrań dla broni — wołane na końcu bake_weapons.build_weapons(), po syntezie tych samych kluczy."""
    m83()
    bc.hybrid(_keys("spread12_shot", 3), _spread12_bake, SPREAD12_NEEDS)
    bc.hybrid(_keys("srut8_shot", 3), _srut8_bake, SRUT8_NEEDS)
    bc.hybrid(_keys("srut8_pump", 2), _pump_bake, PUMP_NEEDS)
    bc.hybrid(_keys("gniew4_shot", 2), _gniew4_bake, GNIEW4_NEEDS)
    bc.hybrid(_keys("ciegno6_shot", 2), _ciegno6_bake, CIEGNO6_NEEDS)
    bc.hybrid(_keys("explosion", 2), _explosion_bake, list(EXPLOSION_SRC))


# (nazwa wersji, funkcja piekąca, potrzebne źródła) — kandydaci do następnego odsłuchu
CANDIDATES: tuple = ()


def build_alts() -> None:
    """Wersje alternatywne do następnego odsłuchu A/B (bc.alt): bake_audio.py --only alts --alts KATALOG."""
    for name, fn, needs in CANDIDATES:
        bc.alt(name, fn, needs)
