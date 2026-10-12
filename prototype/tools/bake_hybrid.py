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
srut8_pump, gniew4_shot, explosion (F3, część 1); ciegno6_shot w wersji 2, impact_hard, impact_flesh, shell (F3, część 2).
Odrzucone na rzecz syntezy — przepisy usunięte, zostają w historii repo: p64_shot (SIG P229 z 1 m), sokol6_shot (start
fajerwerku), whizz (przeloty pocisków), foley_gear (oporządzenie z marszu), dry_fire (kurek M1911).
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


def _calm_point(x: np.ndarray, start: int, span: int) -> int:
    """Indeks w [start, start+span) o najmniejszym skoku między sąsiednimi próbkami. Pętla zszyta przez seam_xfade jest
    ciągła co do próbki, ale w jasnym, głośnym materiale sam skok międzypróbkowy bywa duży — wybieramy spokojne miejsce."""
    return start + int(np.argmin(np.abs(np.diff(x[start - 1:start + span]))))


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


# --- SINEW-6 (wersja 2; pierwsza — samo zwolnienie cięciwy z brzękiem — była w odsłuchu „zbyt krótka i jednostajna").
# Strzał z kuszy to ciąg zdarzeń, nie jedno pyknięcie: zamek → strzał cięciwy i uderzenie ramion o ogranicznik →
# gasnące drganie ramion → świst odlatującego bełtu. Głośny, ostry początek, potem dwa cichsze plany.
CIEGNO6_NEEDS = ["crossbow_loose", "crossbow_functions", "whip_21", "arrow_whoosh", "bow_midflight"]


def _ciegno6_bake() -> None:
    for i in range(2):
        r = Rng(0x3480 + i * 2113)
        latch = _fade(d.from_onset(bc.src("crossbow_functions", 1.00, 0.08), 0.3, thr_db=-18.0), 0.02, 0.05)
        snap = d.repitch(d.from_onset(bc.src("crossbow_loose", 0.06, 0.34), 0.5), (0.0, -1.5)[i])
        crack = _fade(d.from_onset(bc.src("whip_21", 0.0, 0.5), 0.5, thr_db=-8.0), 0.06, 0.16)       # trzask bicza od samego czubka
        thunk = thump(0.10, vary(r, 150, .08), vary(r, 62, .08), 0.02, 0.035)                        # ramiona o ogranicznik
        f0 = vary(r, 132, .06)
        thrum = ring(r, [f0, f0 * 2.01, f0 * 3.03, f0 * 4.2], [.55, .38, .22, .12], [1.0, .6, .35, .2], dur=.62)
        tt = np.arange(len(thrum)) / d.SR
        thrum = thrum * (1.0 + 0.55 * np.sin(d.TAU * vary(r, 27, .1) * tt) * np.exp(-tt / 0.18))     # brzęczenie gasnące w ok. 0,2 s
        whoosh = bc.src(("arrow_whoosh", "bow_midflight")[i], (0.18, 0.12)[i], 0.60)
        whoosh = _fade(whoosh * d.env_pts(len(whoosh), [(0, 0), (.03, 1), (10, 1)]), 0.30, 0.56)     # narasta i odchodzi
        x = d.mix([(_unit(latch), 0.45, 0.0), (_unit(snap), 1.0, 0.012), (_unit(crack), 0.5, 0.012), (thunk, 0.7, 0.014),
                   (thrum, 0.42, 0.016), (_unit(whoosh), 0.34, 0.045)], ms(760))
        finalize("ciegno6_shot_%d" % (i + 1), d.reverb(d.filt(x, "hp", 45.0, order=2), ir("close"), wet=.15), lufs=-21.7)


# --- Trafienie pocisku w twarde: cegła/beton, skała, ściana — krótko, bo pogłos dokłada silnik.
IMPACT_HARD_SRC = ("impact_concrete_brick", "impact_rock_4", "impact_22")


def _impact_hard_bake() -> None:
    for i, sid in enumerate(IMPACT_HARD_SRC):
        x = _fade(_decay(d.from_onset(bc.src(sid, 0.0, 0.6), 1.0, thr_db=-10.0), 0.02, 0.07), 0.20, 0.32)
        finalize("impact_hard_%d" % (i + 1), d.reverb(d.filt(x, "hp", 80.0), ir("close"), wet=.18), lufs=-23.0)


# --- Trafienie w ciało: uderzenie pocisku, mokre trafienie, tępy cios.
IMPACT_FLESH_SRC = (("impact_body_thump", 0.0), ("impact_body_flesh_25", 0.12), ("stab_punch_hit", 0.03))


def _impact_flesh_bake() -> None:
    for i, (sid, t0) in enumerate(IMPACT_FLESH_SRC):
        x = _fade(d.from_onset(bc.src(sid, t0, 0.5), 1.0, thr_db=-10.0), 0.22, 0.38)
        finalize("impact_flesh_%d" % (i + 1), d.saturate(d.reverb(x, ir("close"), wet=.15), 1.6), lufs=-15.0)


# --- Łuska na ziemi: mosiężna łuska odbijająca się od drewna, pocisk na drewnie, łuska strzelby na betonie.
SHELL_SRC = (("shell_bounce_wood_05", 0.0), ("bullet_drop_wood_04", 0.0), ("shell_land_concrete_02", 0.0))


def _shell_bake() -> None:
    for i, (sid, t0) in enumerate(SHELL_SRC):
        x = _fade(d.from_onset(bc.src(sid, t0, 0.5), 1.0, thr_db=-10.0), 0.18, 0.30)
        x = d.limiter(d.saturate(_unit(d.filt(x, "hp", 300.0)), 1.5), -7.0)      # ścięcie czubka: dzwonienie łuski słyszalne przy tym samym szczycie
        finalize("shell_%d" % (i + 1), d.reverb(x, ir("dead"), wet=.15), lufs=-19.4)


def weapons() -> None:
    """Wersje z nagrań dla broni — wołane na końcu bake_weapons.build_weapons(), po syntezie tych samych kluczy."""
    m83()
    bc.hybrid(_keys("spread12_shot", 3), _spread12_bake, SPREAD12_NEEDS)
    bc.hybrid(_keys("srut8_shot", 3), _srut8_bake, SRUT8_NEEDS)
    bc.hybrid(_keys("srut8_pump", 2), _pump_bake, PUMP_NEEDS)
    bc.hybrid(_keys("gniew4_shot", 2), _gniew4_bake, GNIEW4_NEEDS)
    bc.hybrid(_keys("ciegno6_shot", 2), _ciegno6_bake, CIEGNO6_NEEDS)
    bc.hybrid(_keys("explosion", 2), _explosion_bake, list(EXPLOSION_SRC))
    bc.hybrid(_keys("impact_hard", 3), _impact_hard_bake, list(IMPACT_HARD_SRC))
    bc.hybrid(_keys("impact_flesh", 3), _impact_flesh_bake, [sid for sid, _ in IMPACT_FLESH_SRC])
    bc.hybrid(_keys("shell", 3), _shell_bake, [sid for sid, _ in SHELL_SRC])


# ============================================================ F3, część 3 — kandydaci do odsłuchu
# Wniosek z poprzednich odsłuchów: krótkie, jasne dźwięki „przy graczu" z samych nagrań przegrywały z syntezą, która ma
# pełniejszy dół. Dlatego mechanika broni dostaje pod nagranie te same niskie stuki, których używa synteza.

# --- Przeładowanie magazynka na osi czasu syntezy: wyjęcie (0 s) → wsunięcie i zatrzask (0,30 s) → przeładowanie zamka (0,62 s).
RELOAD_NEEDS = ["g36c_mag_foley", "saiga12_cocking"]
_MAG_OUT = (6.607, 14.363, 28.696)                                  # pojedyncze stuknięcia: magazynek wychodzi
_MAG_IN = (4.166, 9.416, 11.509)                                    # podwójne: wsunięcie + zatrzask
_RACK = (4.461, 6.113, 7.847)                                       # zamek do tyłu i do przodu (ok. 0,1 s)


def _reload_bake() -> None:
    for i in range(3):
        r = Rng(0x3100 + i * 7919)
        out = _fade(bc.src("g36c_mag_foley", _MAG_OUT[i] - 0.01, 0.22), 0.12, 0.20)
        mag = _fade(bc.src("g36c_mag_foley", _MAG_IN[i] - 0.01, 0.26), 0.16, 0.24)
        rack = _fade(bc.src("saiga12_cocking", _RACK[i] - 0.01, 0.30), 0.20, 0.28)
        seat = thump(.09, 220, 90, .02, .03)
        snap = thump(.07, 260, 120, .015, .02)
        t_in = 0.30 + r.uniform(0, .03)
        x = d.mix([(_unit(out), 0.8, 0.0), (_unit(mag), 1.0, t_in), (seat, 0.6, t_in + 0.05),
                   (_unit(rack), 0.9, 0.62), (snap, 0.4, 0.70)], ms(1000))
        finalize("reload_%d" % (i + 1), d.reverb(x, ir("close"), wet=.14), lufs=-22.2)


# --- Nabój do strzelby: wsunięcie naboju, wyrzut łuski, to samo wsunięcie o 2 półtony niżej.
RELOAD_SHELL_NEEDS = ["shell_load_eject"]


def _reload_shell_bake() -> None:
    for i, (t, semis) in enumerate(((2.845, 0.0), (4.280, 0.0), (2.845, -2.0))):
        click = d.from_onset(d.repitch(bc.src("shell_load_eject", t, 0.30), semis), 1.0, thr_db=-10.0)   # od głównego kliknięcia
        x = d.mix([(_unit(_fade(click, 0.12, 0.18)), 1.0), (thump(.05, 200, 95, .012, .02), 0.5, 0.05)], ms(200))
        finalize("reload_shell_%d" % (i + 1), d.reverb(x, ir("dead"), wet=.12), lufs=-20.1)


# --- Maczeta: zamach długą klingą (świst z metalicznym „szzing") + krótki świst noża na ataku.
MACZETA_NEEDS = ["blade_swing_scrape_14", "knife_swing_04"]


def _maczeta_bake() -> None:
    for i in range(2):
        blade = d.repitch(d.from_onset(bc.src("blade_swing_scrape_14", 0.0, 0.7), 2.0, thr_db=-20.0), (0.0, 1.5)[i])
        whoosh = d.repitch(bc.src("knife_swing_04", 0.0, 0.24), (-3.0, -1.0)[i])
        x = d.mix([(_unit(_fade(blade, 0.22, 0.40)), 1.0), (_unit(whoosh), 0.6, 0.02)], ms(400))
        finalize("maczeta_%d" % (i + 1), d.reverb(x, ir("close"), wet=.12), lufs=-19.9)


# --- Kilof: wolny zamach długim trzonkiem, o 3 półtony niżej (ciężkie narzędzie).
KILOF_NEEDS = ["broom_stick_swings"]
_STICK = (6.12, 8.13)


def _kilof_bake() -> None:
    for i, t in enumerate(_STICK):
        sw = d.repitch(bc.src("broom_stick_swings", t - 0.04, 0.54), -3.0)
        sw = _fade(sw * d.env_pts(sw.shape[-1], [(0, 0), (.03, 1), (10, 1)]), 0.42, 0.56)
        finalize("kilof_swing_%d" % (i + 1), d.reverb(d.filt(sw, "hp", 90.0, order=4), ir("close"), wet=.12), lufs=-18.4)


# --- HKM-9: zapłon (początek nagrania dużego zapłonu) i pętla płomienia (ryk ognia + syk palnika gazowego).
FLAME_NEEDS = ["fire_ignition_03", "gas_burner_4"]


def _flame_bake() -> None:
    ignite = _fade(d.from_onset(bc.src("fire_ignition_03", 0.0, 0.9), 1.0), 0.40, 0.66)
    finalize("hkm9_ignite", d.reverb(d.saturate(_unit(ignite), 1.6), ir("close"), wet=.16), lufs=-17.0)
    xf = ms(300)                                                     # zakładka szwu pętli
    roar = bc.src("fire_ignition_03", 4.0, 2.0 + 0.3)
    hiss = bc.src("gas_burner_4", 10.0, 2.0 + 0.3)
    n = min(len(roar), len(hiss))
    x = roar[:n] / (np.std(roar) + 1e-9) + 0.9 * hiss[:n] / (np.std(hiss) + 1e-9)
    finalize("hkm9_flame_loop", d.seam_xfade(d.filt(x, "hp", 40.0), xf), loop=True, lufs=-19.0)


# ============================================================ F5: Stalker — kandydaci do odsłuchu
# Jeden stwór w całej rodzinie: warkot (z bramki A) i krzyk pochodzą od tego samego autora nagrań, a „nieludzki" rys
# daje wspólna warstwa pisku suchego lodu na metalu. Odległy zew to ten sam krzyk słyszany z głębi kompleksu.

SHRIEK_NEEDS = ["screeching_monster_2", "blackboss_scream_04", "dry_ice_shriek_3"]
SHRIEK_CEIL = -6.0


def _shriek_voice(i: int) -> np.ndarray:
    """Krzyk Stalkera bez pogłosu: skrzek (góra) + ryk (korpus) + pisk suchego lodu + uderzenie w dole."""
    screech = _fade(d.repitch(d.from_onset(bc.src("screeching_monster_2", 0.0, 1.0), 1.0), (-3.0, -5.0)[i]), 0.75, 1.05)
    roar = _fade(d.repitch(d.from_onset(bc.src("blackboss_scream_04", 0.0, 1.3), 1.0), (2.0, 0.0)[i]), 0.70, 1.05)
    ice = bc.src("dry_ice_shriek_3", (0.6, 1.5)[i], 1.1)
    ice = _fade(ice * d.env_pts(len(ice), [(0, 0), (.04, 1), (10, 1)]), 0.60, 1.00)
    sub = thump(0.25, 90, 38, .05, .09)
    x = d.mix([(_unit(screech), 1.0), (_unit(roar), 0.55), (_unit(ice), 0.22), (sub, 0.5)], ms(1050))
    return d.saturate(_unit(d.filt(x, "hp", 30.0, order=2)), 3.0)


def _shriek_bake() -> None:
    for i in range(2):
        x = _fade(d.reverb(_shriek_voice(i), ir("hall"), wet=.28), 1.10, 1.60)
        x = d.limiter(_unit(x), SHRIEK_CEIL)                         # gęsto jak w syntezie: krzyk ma dominować nad miksem
        finalize("stalker_shriek_%d" % (i + 1), x, lufs=-10.4, fade_out_ms=120)


def _far_cry_bake() -> None:
    for i in range(2):
        x = d.filt(d.filt(_shriek_voice(i), "bp", 620.0 - 60.0 * i, 0.9), "lp", 1400.0)
        x = _fade(d.reverb(x, ir("cave"), wet=0.9, dry=0.25), 3.6, 5.0)
        finalize("amb_far_cry_%d" % (i + 1), x, lufs=-26.0, fade_out_ms=400)


# --- Krok Stalkera: ciężkie, mokre kroki stwora (trzy różne podłoża) + sub-uderzenie.
STALKER_STEP_SRC = (("creature_step_damp", 0.09), ("creature_step_wood", 0.0), ("creature_step_mud", 0.02))


def _stalker_step_bake() -> None:
    for i, (sid, t0) in enumerate(STALKER_STEP_SRC):
        step = _fade(d.from_onset(bc.src(sid, t0, 0.5), 1.0, thr_db=-12.0), 0.22, 0.36)
        x = d.mix([(_unit(step), 1.0), (thump(0.16, 70, 34, .04, .07), 0.9)], ms(360))
        finalize("stalker_step_%d" % (i + 1), d.filt(x, "hp", 28.0, order=2), lufs=-19.0)


# --- Szept Stalkera (pętla 4,2 s): nagrany szept + cichy upiorny głos pod spodem, w hali; szew przenikany.
WHISPER_NEEDS = ["whisper_4c", "ghostly_voice_male"]


def _whisper_bake() -> None:
    n, xf, lead = d.sec(4.2), ms(400), ms(600)                      # `lead`: rozbieg pogłosu, którego pętla nie zawiera
    a = bc.src("whisper_4c", 1.5, 6.0)
    b = _fade(bc.src("ghostly_voice_male", 1.15, 3.3), 2.6, 3.3)
    x = d.mix([(_unit(a), 1.0), (_unit(b), 0.35, 1.2)], lead + n + xf + ms(20))
    x = d.reverb(d.filt(x, "hp", 250.0), ir("hall"), wet=.25, keep_len=True)
    lead = _calm_point(x, lead + xf, ms(20)) - xf                    # szew w spokojnym miejscu przebiegu
    finalize("stalker_whisper_loop", d.seam_xfade(x[lead:lead + n + xf], xf), loop=True, lufs=-18.5)


# ============================================================ F4: gracz — kandydaci do odsłuchu
# Kroki jak beton z bramki A: pojedyncze kroki wycięte z nagranego marszu, bez dokładanego basu, głośność jak w syntezie.

def _steps(base: str, sid: str, times: tuple, length: float, lufs: float, hp: float = 60.0,
           onset_db: float = -20.0, ceil: float = 0.0) -> None:
    """`ceil` < 0: ścięcie samego czubka (chlupnięcia i stuknięcia mają ostry szczyt, przez który krok wychodzi za cichy)."""
    for i, t in enumerate(times):
        x = d.from_onset(bc.src(sid, t - 0.04, length + 0.12), 3.0, thr_db=onset_db)
        x = d.filt(_fade(x, length * 0.55, length), "hp", hp, order=2)
        if ceil < 0.0:
            x = d.limiter(_unit(x), ceil)
        finalize("%s_%d" % (base, i + 1), x, lufs=lufs)


STEP_METAL_NEEDS = ["boot_metal_walk"]
STEP_DIRT_NEEDS = ["dirt_walk_loop"]
STEP_WATER_NEEDS = ["puddle_splashes"]
_STEPS_METAL = (1.42, 3.01, 4.51, 6.86, 9.91)                      # głośniejsza stopa nagranego marszu po blasze
_STEPS_DIRT = (2.47, 3.66, 4.25, 5.38, 7.08)                       # kroki „ziemne" (bez chrzęstu żwiru)
_STEPS_WATER = (0.24, 1.60, 2.35, 5.31, 13.88)                     # pojedyncze chlupnięcia w kałuży


def _step_metal_bake() -> None:
    _steps("step_metal", "boot_metal_walk", _STEPS_METAL, 0.30, -21.5)


def _step_dirt_bake() -> None:
    _steps("step_dirt", "dirt_walk_loop", _STEPS_DIRT, 0.28, -23.0, onset_db=-12.0)


def _step_water_bake() -> None:
    _steps("step_water", "puddle_splashes", _STEPS_WATER, 0.34, -20.0, hp=90.0, onset_db=-14.0, ceil=-9.0)


# --- Twarde lądowanie: upadek ciała na beton (stopy) + sub-uderzenie.
LAND_NEEDS = ["bodyfall_concrete"]


def _land_hard_bake() -> None:
    fall = _fade(d.from_onset(bc.src("bodyfall_concrete", 0.10, 0.6), 1.0, thr_db=-12.0), 0.25, 0.42)
    x = d.mix([(_unit(fall), 1.0), (thump(.2, 120, 50, .03, .06), 0.9)], ms(420))
    x = d.limiter(_unit(d.filt(x, "hp", 30.0, order=2)), -5.0)
    finalize("land_hard", d.reverb(x, ir("close"), wet=.15), lufs=-17.5)


# (nazwa wersji, funkcja piekąca, potrzebne źródła) — kandydaci do następnego odsłuchu
CANDIDATES: tuple = (
    ("hybrid", _step_metal_bake, STEP_METAL_NEEDS),
    ("hybrid", _step_dirt_bake, STEP_DIRT_NEEDS),
    ("hybrid", _step_water_bake, STEP_WATER_NEEDS),
    ("hybrid", _land_hard_bake, LAND_NEEDS),
    ("hybrid", _shriek_bake, SHRIEK_NEEDS),
    ("hybrid", _far_cry_bake, SHRIEK_NEEDS),
    ("hybrid", _stalker_step_bake, [sid for sid, _ in STALKER_STEP_SRC]),
    ("hybrid", _whisper_bake, WHISPER_NEEDS),
    ("hybrid", _reload_bake, RELOAD_NEEDS),
    ("hybrid", _reload_shell_bake, RELOAD_SHELL_NEEDS),
    ("hybrid", _maczeta_bake, MACZETA_NEEDS),
    ("hybrid", _kilof_bake, KILOF_NEEDS),
    ("hybrid", _flame_bake, FLAME_NEEDS),
)


def build_alts() -> None:
    """Wersje alternatywne do następnego odsłuchu A/B (bc.alt): bake_audio.py --only alts --alts KATALOG."""
    for name, fn, needs in CANDIDATES:
        bc.alt(name, fn, needs)
