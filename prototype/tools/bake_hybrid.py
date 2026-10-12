"""
bake_hybrid.py — wersje assetów Z NAGRAŃ z bibliotek (AUDIO_PLAN.md).

Dwa rodzaje przepisów:
  * wersje z nagrań dla GRY — weapons(), stalker(), enemies(), world(), player(), ui(), ambience(): wołane na końcu
    builderów (bake_weapons.py, bake_sfx.py, bake_amb.py),
    po syntezie tych samych kluczy, przez bc.hybrid(). Plik trafia do audio_licensed/ (poza repo), a gra woli go
    od syntetycznego z audio/. Bez plików źródłowych na dysku nic się nie dzieje — zostaje sama synteza;
  * WERSJE ALTERNATYWNE do odsłuchu przed decyzją — CANDIDATES → build_alts() przez bc.alt(): katalog z --alts,
    gry nie dotykają. Po odsłuchu wybrana rodzina przechodzi do funkcji swojego buildera, odrzucona znika.

    python tools/audio_lib_fetch.py sync                    # pobierz nagrania z rejestru
    python tools/bake_audio.py                              # synteza → audio/, wersje z nagrań → audio_licensed/
    python tools/audio_ab.py --licensed                     # odsłuch: synteza obok wersji z nagrań

Zasady składania (wnioski z pomiaru źródeł; brzmienie ocenia się uchem na stronie A/B):
  * Strzał = nagranie bliskie (trzask, góra pasma) + nagranie z otwartego terenu (środek, naturalny ogon)
    + syntetyczny sub (kopnięcie, którego mikrofony przy lufie nie łapią). Ataki warstw równane co do próbki.
  * Krok = pojedynczy krok wycięty z nagranego marszu; bez dokładanego basu (but go nie ma).
  * Głos = nagranie obniżone jak taśma (wolniej = niżej i dłużej), z oktawą w dół pod spodem.
  * Mechanika broni = nagranie + te same niskie stuki, których używa synteza (samo nagranie jest cienkie).
  * Pogłosu hali nie pieczemy poza głosem Stalkera (tak samo jak w wersji syntetycznej) — dokłada go silnik.
  * Głośność docelowa = ZMIERZONA głośność wersji syntetycznej tego samego klucza (średnia rodziny, LUFS po finalize);
    nominalne cele z bake_weapons.py / bake_sfx.py synteza osiąga tylko w części, bo ogranicza ją szczyt.
    Dzięki temu miks gry nie zależy od tego, która wersja gra.

Werdykty odsłuchów A/B (2026-10-12), szczegóły w AUDIO_PLAN.md §7.
Z nagrań: m83_shot, spread12_shot, srut8_shot, srut8_pump, gniew4_shot, ciegno6_shot (wersja 2), explosion, impact_hard,
impact_flesh, shell, reload, reload_shell, maczeta, hkm9_flame_loop, foley_gear, ammo_pickup, weapon_pickup,
item_pickup, medkit_pickup, scrap_pickup, tag_pickup;
stalker_growl, stalker_shriek, stalker_step,
stalker_whisper_loop (niski oddech),
amb_far_cry; trzosek_attack, trzosek_death (wilkołak), wolek_attack, wolek_death, slepiec_death, podsluchacz_scream, leech_growl,
leech_shriek, zyla_roar; door, glass_break, thunder, amb_creak, amb_gust, amb_thud; step_concrete, step_metal, step_dirt,
step_water, land_hard (buty), player_hurt, player_down; ui_confirm, mission_start; amb_forest, amb_rain, amb_rain_roof, amb_wind.
Odrzucone na rzecz syntezy (przepisy usunięte, zostają w historii repo): p64_shot, sokol6_shot, whizz,
dry_fire, hkm9_ignite, kilof_swing, slepiec_attack, zyla_growl. Po odsłuchu w grze
wymienione: Trzosek (owadzi terkot był za wysoki → pies z warkotem ogara), lądowanie (upadek ciała → buty na obie stopy).
"""

from __future__ import annotations

import numpy as np

import audio_dsp as d
from audio_dsp import Rng, ms
import bake_common as bc
from bake_common import finalize, ir, ring, thump, vary


def _keys(base: str, n: int) -> list[str]:
    return ["%s_%d" % (base, i + 1) for i in range(n)]


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


# ============================================================ BRONIE (bake_weapons.build_weapons)

# --- M-83: AKM z 1 m (trzy strzały co ok. 200 ms) i AK-47 w otwartym terenie (pięć pojedynczych).
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


def _m83_bake() -> None:
    for i in range(6):
        finalize("m83_shot_%d" % (i + 1), _m83_shot(i), lufs=-14.0)


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


# --- HKM-9: pętla płomienia (ryk ognia + syk palnika gazowego); zapłon został syntetyczny.
FLAME_NEEDS = ["fire_ignition_03", "gas_burner_4"]


def _flame_loop_bake() -> None:
    xf = ms(300)                                                     # zakładka szwu pętli
    roar = bc.src("fire_ignition_03", 4.0, 2.0 + 0.3)
    hiss = bc.src("gas_burner_4", 10.0, 2.0 + 0.3)
    n = min(len(roar), len(hiss))
    x = roar[:n] / (np.std(roar) + 1e-9) + 0.9 * hiss[:n] / (np.std(hiss) + 1e-9)
    finalize("hkm9_flame_loop", d.seam_xfade(d.filt(x, "hp", 40.0), xf), loop=True, lufs=-19.0)


# --- Szelest ekwipunku przy chodzeniu (foley_gear): pojedyncze ruchy oporządzenia z nagrania biegu, obniżone i przyciemnione.
# Synteza (szum + metaliczne stuknięcia 1,8–5 kHz) była w grze wysoka i sztuczna — gra przy co trzecim kroku.
GEAR_NEEDS = ["gear_running_10"]
GEAR_LUFS = -28.8                                                    # zmierzona głośność dawnej syntezy (średnia rodziny)


def _gear_bake() -> None:
    for i, t0 in enumerate((13.181, 8.980, 4.183)):
        x = _clip("gear_running_10", t0 - 0.01, 0.32, -2.0, 0.30, tail=.12)
        finalize("foley_gear_%d" % (i + 1), d.lp(d.filt(x, "hp", 120.0, order=2), 3500.0), lufs=GEAR_LUFS)


# --- Podnoszenie amunicji i broni: prawdziwy chwyt zamiast syntetycznego sygnału (tyknięcia z dzwonkiem 3,6–5,2 kHz).
# Amunicja: naboje przesypujące się w dłoni + miękki chwyt torby. Broń: chwyt karabinu obniżony o 5 półtonów,
# z chwytem przedmiotu i uderzeniem w dole pasma.
PICKUP_AMMO_NEEDS = ["cartridge_handling_018", "bag_grab_04"]
PICKUP_WEAPON_NEEDS = ["rifle_pickup_004", "object_grab_04"]
PICKUP_AMMO_LUFS = -18.2                                             # zmierzona głośność dawnej syntezy
PICKUP_WEAPON_LUFS = -21.2


def _pickup_ammo_bake() -> None:
    rattle = d.lp(_clip("cartridge_handling_018", 0.08, 0.5, -3.0, 0.36, tail=.16), 5000.0)
    grab = d.lp(_clip("bag_grab_04", 0.0, 0.3, -1.0, 0.24, tail=.10), 3000.0)
    x = d.limiter(_unit(d.filt(d.mix([(rattle, 1.0, .02), (grab, 0.6)], ms(390)), "hp", 90.0, order=2)), -5.0)
    finalize("ammo_pickup", d.reverb(x, ir("dead"), wet=.12), lufs=PICKUP_AMMO_LUFS)


def _pickup_weapon_bake() -> None:
    x = d.mix([(d.lp(_clip("rifle_pickup_004", 0.0, 0.5, -5.0, 0.48, tail=.16), 4500.0), 1.0),
               (d.lp(_clip("object_grab_04", 0.0, 0.5, -4.0, 0.44, tail=.16), 2500.0), 0.6), (thump(.14, 130, 55, .03, .06), 0.8)], ms(500))
    x = d.limiter(_unit(d.filt(x, "hp", 45.0, order=2)), -5.0)
    finalize("weapon_pickup", d.reverb(x, ir("close"), wet=.14), lufs=PICKUP_WEAPON_LUFS)


# --- Podnoszenie pozostałych przedmiotów (gra: level.gd PICKUP_SOUND): każdy rodzaj brzmi jak to, czym jest.
# Głośność = zmierzona głośność syntezy tego samego klucza.
PICKUP_ITEM_NEEDS = ["bag_grab_04"]
PICKUP_MEDKIT_NEEDS = ["zipper_smallbag", "bag_grab_04"]
PICKUP_SCRAP_NEEDS = ["scrap_pile_03"]
PICKUP_TAG_NEEDS = ["chain_clinking_04", "bag_grab_04"]


def _pickup_item_bake() -> None:                                     # flary, zaopatrzenie: miękki chwyt torby
    x = d.lp(d.filt(_clip("bag_grab_04", 0.0, 0.3, -1.0, 0.24, tail=.10), "hp", 70.0, order=2), 4000.0)
    finalize("item_pickup", d.reverb(x, ir("dead"), wet=.12), lufs=-19.0)


def _pickup_medkit_bake() -> None:                                   # apteczka: chwyt + krótki suwak torby
    zipr = d.lp(_clip("zipper_smallbag", 1.07, 0.4, -3.0, 0.36, tail=.12), 6000.0)
    grab = d.lp(_clip("bag_grab_04", 0.0, 0.3, -1.0, 0.24, tail=.10), 3000.0)
    x = d.limiter(_unit(d.filt(d.mix([(grab, 0.7), (zipr, 1.0, .04)], ms(410)), "hp", 80.0, order=2)), -5.0)
    finalize("medkit_pickup", d.reverb(x, ir("dead"), wet=.12), lufs=-19.0)


def _pickup_scrap_bake() -> None:                                    # złom: garść żelastwa
    x = d.mix([(d.lp(_clip("scrap_pile_03", 0.50, 0.7, -4.0, 0.50, tail=.25), 5000.0), 1.0), (thump(.08, 150, 70, .02, .035), 0.4)], ms(520))
    x = d.limiter(_unit(d.filt(x, "hp", 70.0, order=2)), -5.0)
    finalize("scrap_pickup", d.reverb(x, ir("dead"), wet=.14), lufs=-19.5)


def _pickup_tag_bake() -> None:                                      # nieśmiertelnik: dwa brzęknięcia blaszek na łańcuszku
    a = _clip("chain_clinking_04", 0.41, 0.12, -5.0, 0.14, tail=.08)
    b = _clip("chain_clinking_04", 1.11, 0.36, -5.0, 0.40, tail=.2)
    grab = d.lp(_clip("bag_grab_04", 0.0, 0.3, -1.0, 0.24, tail=.10), 2500.0)
    x = d.lp(d.mix([(a, 0.7), (b, 1.0, .09), (grab, 0.35)], ms(500)), 6500.0)
    x = d.limiter(_unit(d.filt(x, "hp", 90.0, order=2)), -5.0)
    finalize("tag_pickup", d.reverb(x, ir("close"), wet=.16), lufs=-19.0)


def weapons() -> None:
    """Wersje z nagrań dla broni — wołane na końcu bake_weapons.build_weapons()."""
    bc.hybrid(["item_pickup"], _pickup_item_bake, PICKUP_ITEM_NEEDS)
    bc.hybrid(["medkit_pickup"], _pickup_medkit_bake, PICKUP_MEDKIT_NEEDS)
    bc.hybrid(["scrap_pickup"], _pickup_scrap_bake, PICKUP_SCRAP_NEEDS)
    bc.hybrid(["tag_pickup"], _pickup_tag_bake, PICKUP_TAG_NEEDS)
    bc.hybrid(["ammo_pickup"], _pickup_ammo_bake, PICKUP_AMMO_NEEDS)
    bc.hybrid(["weapon_pickup"], _pickup_weapon_bake, PICKUP_WEAPON_NEEDS)
    bc.hybrid(_keys("foley_gear", 3), _gear_bake, GEAR_NEEDS)
    bc.hybrid(_keys("m83_shot", 6), _m83_bake, M83_NEEDS)
    bc.hybrid(_keys("spread12_shot", 3), _spread12_bake, SPREAD12_NEEDS)
    bc.hybrid(_keys("srut8_shot", 3), _srut8_bake, SRUT8_NEEDS)
    bc.hybrid(_keys("srut8_pump", 2), _pump_bake, PUMP_NEEDS)
    bc.hybrid(_keys("gniew4_shot", 2), _gniew4_bake, GNIEW4_NEEDS)
    bc.hybrid(_keys("ciegno6_shot", 2), _ciegno6_bake, CIEGNO6_NEEDS)
    bc.hybrid(_keys("explosion", 2), _explosion_bake, list(EXPLOSION_SRC))
    bc.hybrid(_keys("impact_hard", 3), _impact_hard_bake, list(IMPACT_HARD_SRC))
    bc.hybrid(_keys("impact_flesh", 3), _impact_flesh_bake, [sid for sid, _ in IMPACT_FLESH_SRC])
    bc.hybrid(_keys("shell", 3), _shell_bake, [sid for sid, _ in SHELL_SRC])
    bc.hybrid(_keys("reload", 3), _reload_bake, RELOAD_NEEDS)
    bc.hybrid(_keys("reload_shell", 3), _reload_shell_bake, RELOAD_SHELL_NEEDS)
    bc.hybrid(_keys("maczeta", 2), _maczeta_bake, MACZETA_NEEDS)
    bc.hybrid(["hkm9_flame_loop"], _flame_loop_bake, FLAME_NEEDS)
    # Dalekie wersje (F6 a) rodzin, których bliska wersja jest z nagrań: ta sama funkcja co dla syntezy, na plikach z nagrań.
    import bake_weapons
    for near, needs in (("m83_shot", M83_NEEDS), ("spread12_shot", SPREAD12_NEEDS), ("srut8_shot", SRUT8_NEEDS),
                        ("gniew4_shot", GNIEW4_NEEDS), ("explosion", list(EXPLOSION_SRC))):
        far = dict(bake_weapons.FAR_FAMILIES)[near]
        if "%s_1" % near in bc.HYBRID:
            bc.hybrid(_keys(far, bake_weapons.FAR_VARIANTS),
                      lambda near=near, far=far: bake_weapons.bake_far_family(bc.LICENSED, near, far), needs)


# ============================================================ STALKER (bake_sfx.build_stalker)
# Jeden stwór w całej rodzinie: warkot i krzyk pochodzą od tego samego autora nagrań, a „nieludzki" rys daje warstwa
# pisku suchego lodu na metalu. Odległy zew to ten sam krzyk słyszany z głębi kompleksu. „Szept” to niski oddech.

# --- Warkot: dwa najniższe warknięcia z nagrania, obniżone o 4 półtony.
GROWL_NEEDS = ["monster_growls_4"]
_GROWLS = ((0.12, 1.98), (12.42, 2.10))                              # (start, długość) w monster_growls_4 [s]


def _growl(x: np.ndarray, semis: float, i: int) -> np.ndarray:
    x = d.repitch(x, semis)
    n = len(x)
    low = d.lp(d.repitch(x, -12.0)[:n], 180.0)                      # oktawa niżej pod spodem: ciężar bez zamulania środka
    y = d.mix([(x / (d.peak(x) + 1e-9), 1.0), (d.pad_to(low, n) / (d.peak(low) + 1e-9), 0.35)], n)
    y = d.saturate(d.filt(y, "hp", 28.0, order=2), 1.6)
    return d.reverb(y, ir("hall"), wet=0.30 - 0.04 * i, keep_len=False)


def _growl_bake() -> None:
    for i, (t, ln) in enumerate(_GROWLS):
        x = bc.src("monster_growls_4", t, ln)
        x = x * d.env_pts(len(x), [(0, 0), (.02, 1), (ln - .12, 1), (ln, 0)])
        finalize("stalker_growl_%d" % (i + 1), _growl(x, -4.0, i), lufs=-14.0, fade_out_ms=250)


# --- Krzyk i odległy zew.
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


# --- Krok: ciężkie, mokre kroki stwora (trzy różne podłoża) + sub-uderzenie.
STALKER_STEP_SRC = (("creature_step_damp", 0.09), ("creature_step_wood", 0.0), ("creature_step_mud", 0.02))


def _stalker_step_bake() -> None:
    for i, (sid, t0) in enumerate(STALKER_STEP_SRC):
        step = _fade(d.from_onset(bc.src(sid, t0, 0.5), 1.0, thr_db=-12.0), 0.22, 0.36)
        x = d.mix([(_unit(step), 1.0), (thump(0.16, 70, 34, .04, .07), 0.9)], ms(360))
        finalize("stalker_step_%d" % (i + 1), d.filt(x, "hp", 28.0, order=2), lufs=-19.0)


# --- „Szept” (klucz stalker_whisper_loop): powolny, niski oddech — wdech i wydech złej istoty. Nagrany wydech obniżony
# o oktawę; wdech to ten sam wydech odwrócony; pod spodem cichy, falujący niski ton. Cykl 7 s. Pierwsza wersja z nagrań
# (ludzki szept) przegrała z syntezą, a jasny syk syntezy okazał się w grze za mało mroczny.
WHISPER_NEEDS = ["evil_exhale"]
WHISPER_LUFS = -18.5                                                 # zmierzona głośność pętli syntetycznej


def _sub_drone(n: int, hz: float, wobble: int = 1) -> np.ndarray:
    """Niski ton o całkowitej liczbie okresów w pętli (bez szwu), powoli falujący."""
    t = np.arange(n) / d.SR
    T = n / d.SR
    f = round(hz * T) / T
    return (np.sin(d.TAU * f * t) + 0.4 * np.sin(d.TAU * 2 * f * t)) * (0.6 + 0.4 * np.sin(d.TAU * wobble * t / T))


def _whisper_bake() -> None:
    ex = d.lp(d.filt(d.repitch(bc.src("evil_exhale", 0.10, 3.2), -12.0), "hp", 50.0, order=2), 1800.0)   # oktawa niżej: ok. 6,4 s
    n = d.sec(7.0)
    out_n, in_n = d.sec(4.1), d.sec(2.5)
    exhale = _unit(ex[:out_n] * d.env_pts(out_n, [(0, 0), (.08, 1), (2.9, 1), (4.1, 0)]))
    inhale = _unit(ex[:in_n][::-1] * d.env_pts(in_n, [(0, 0), (.9, 1), (2.3, 1), (2.5, 0)]))                # odwrócony wydech = wdech
    x = d.mix([(inhale, 0.55, 0.1), (exhale, 1.0, 2.75), (_sub_drone(n, 44.0), 0.22)], n)
    finalize("stalker_whisper_loop", d.saturate(x, 1.4), loop=True, lufs=WHISPER_LUFS)


def stalker() -> None:
    """Wersje z nagrań dla Stalkera — wołane na końcu bake_sfx.build_stalker()."""
    bc.hybrid(["stalker_whisper_loop"], _whisper_bake, WHISPER_NEEDS)
    bc.hybrid(_keys("stalker_growl", len(_GROWLS)), _growl_bake, GROWL_NEEDS)
    bc.hybrid(_keys("stalker_shriek", 2), _shriek_bake, SHRIEK_NEEDS)
    bc.hybrid(_keys("amb_far_cry", 2), _far_cry_bake, SHRIEK_NEEDS)
    bc.hybrid(_keys("stalker_step", 3), _stalker_step_bake, [sid for sid, _ in STALKER_STEP_SRC])


# ============================================================ GRACZ (bake_sfx.build_player)

# --- Krok po betonie (bramka A): but, czysty beton. Pięć kroków o zbliżonym poziomie i wyraźnym stuknięciu obcasa.
STEP_CONCRETE_NEEDS = ["boot_concrete_walk"]
_STEPS_CONCRETE = (1.10, 3.11, 4.10, 7.58, 11.58)


def _step_concrete_bake() -> None:
    for i, t in enumerate(_STEPS_CONCRETE):
        x = d.from_onset(bc.src("boot_concrete_walk", t - 0.04, 0.36), 2.0, thr_db=-20.0)
        n = min(len(x), ms(280))
        x = d.filt(x[:n] * d.env_pts(n, [(0, 1), (.16, 1), (.28, 0)]), "hp", 60.0, order=2)
        x = d.filt(x, "highshelf", 3500.0, gain_db=3.0)             # nagranie jest ciemne powyżej 4 kHz — odrobina szurnięcia podeszwy
        finalize("step_concrete_%d" % (i + 1), x, lufs=-21.5)


# --- Kroki po metalu, ziemi i wodzie: pojedyncze kroki wycięte z nagranych marszów, bez dokładanego basu.
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
# Lądowanie: dwa stąpnięcia tuż po sobie z nagrania skoków na obie stopy, obniżone, z uderzeniem w dole pasma (nagranie
# upadku ciała grało jak przewrócenie się po każdym podskoku). Sam skok jest w grze niemy — rodzina `effort` usunięta.
LAND_NEEDS = ["jump_land_two_feet"]


def _land_hard_bake() -> None:
    a = _clip("jump_land_two_feet", 3.04, 0.3, -4.0, 0.30, tail=.14)
    b = _clip("jump_land_two_feet", 5.04, 0.3, -4.0, 0.30, tail=.14)
    x = d.mix([(a, 1.0), (b, 0.9, .03), (thump(.2, 110, 45, .04, .07), 0.9)], ms(400))
    x = d.limiter(_unit(d.filt(x, "hp", 30.0, order=2)), -5.0)
    finalize("land_hard", d.reverb(x, ir("close"), wet=.15), lufs=-17.5)


def player() -> None:
    """Wersje z nagrań dla gracza — wołane na końcu bake_sfx.build_player()."""
    bc.hybrid(_keys("step_concrete", 5), _step_concrete_bake, STEP_CONCRETE_NEEDS)
    bc.hybrid(_keys("step_metal", 5), _step_metal_bake, STEP_METAL_NEEDS)
    bc.hybrid(_keys("step_dirt", 5), _step_dirt_bake, STEP_DIRT_NEEDS)
    bc.hybrid(_keys("step_water", 5), _step_water_bake, STEP_WATER_NEEDS)
    bc.hybrid(["land_hard"], _land_hard_bake, LAND_NEEDS)
    bc.hybrid(_keys("player_hurt", 2), _player_hurt_bake, PLAYER_HURT_NEEDS)
    bc.hybrid(["player_down"], _player_down_bake, PLAYER_DOWN_NEEDS)


# ============================================================ AMBIENT (bake_amb.build_ambience)

# Pętle stereo: 16 s z najrówniejszego fragmentu nagrania (audio_probe.py --steady), szew przenikany 1,5 s.
AMB_LOOPS = (                       # klucz, źródło, start [s], głośność docelowa = zmierzona głośność syntezy, ścięcie szczytów [dB]
    ("amb_forest", "forest_winter_night", 0.5, -14.6, 0.0),
    ("amb_rain", "rain_hard_loop", 1.0, -16.0, 0.0),
    ("amb_rain_roof", "rain_on_plastic", 0.5, -17.0, -12.0),      # pojedyncze głośne krople: bez ścięcia pętla wychodzi za cicha
    ("amb_wind", "wind_mountain_loop", 10.25, -19.6, 0.0),
)


def _amb_loop_bake(key: str, sid: str, t0: float, lufs: float, ceil: float) -> None:
    xf = d.sec(1.5)
    x = d.filt(bc.src(sid, t0, 16.0 + 1.5, mono=False), "hp", 40.0, order=2)
    if ceil < 0.0:
        x = d.limiter(_unit(x), ceil)
    finalize(key, d.seam_xfade(x, xf), loop=True, lufs=lufs)


def ambience() -> None:
    """Wersje z nagrań dla pętli ambientu — wołane na końcu bake_amb.build_ambience()."""
    for row in AMB_LOOPS:
        bc.hybrid([row[0]], lambda row=row: _amb_loop_bake(*row), [row[1]])


# ============================================================ ŚWIAT (bake_sfx.build_world)

# --- Drzwi (metal): skrzyp zawiasu, potem uderzenie skrzydła o futrynę; pogłos blaszanego korytarza jak w syntezie.
DOOR_NEEDS = ["door_creak_metal", "door_impact_metal"]


def _door_bake() -> None:
    for i in range(2):
        creak = bc.src("door_creak_metal", (0.30, 2.20)[i], 0.95)
        creak = _fade(creak * d.env_pts(len(creak), [(0, 0), (.05, 1), (10, 1)]), 0.75, 0.92)
        slam = _fade(d.from_onset(bc.src("door_impact_metal", (0.10, 3.44)[i], 1.2), 1.0, thr_db=-14.0), 0.60, 1.00)
        x = d.mix([(_unit(creak), 0.5, 0.0), (_unit(slam), 1.0, 0.72)], ms(1750))
        finalize("door_%d" % (i + 1), d.reverb(d.filt(x, "hp", 40.0, order=2), ir("metal"), wet=.22), lufs=-22.1)


# --- Szyba: okno wybite z dużą ilością odłamków; drugi wariant — uderzenie w szkło + rozsypanie dużych odłamków.
GLASS_NEEDS = ["glass_window_break", "glass_shards_smash", "glass_impact_break"]


def _glass_bake() -> None:
    a = _fade(d.from_onset(bc.src("glass_window_break", 0.0, 1.39), 1.0, thr_db=-14.0), 0.95, 1.30)
    hit = _fade(d.from_onset(bc.src("glass_impact_break", 0.0, 1.0), 1.0, thr_db=-14.0), 0.60, 0.95)
    shards = _fade(d.from_onset(bc.src("glass_shards_smash", 0.0, 0.92), 1.0, thr_db=-14.0), 0.60, 0.90)
    b = d.mix([(_unit(hit), 1.0, 0.0), (_unit(shards), 0.7, 0.06)], ms(1250))
    for i, x in enumerate((a, b)):
        finalize("glass_break_%d" % (i + 1), d.reverb(d.filt(x, "hp", 120.0), ir("room"), wet=.25), lufs=-21.0)


# --- Grzmot: trzy nagrane uderzenia pioruna, przycięte do ok. 6 s (ogon dalej niesie pogłos silnika).
THUNDER_SRC = ("thunder_crack_02", "thunder_clap_04", "thunder_strike_03")


def _thunder_bake() -> None:
    for i, sid in enumerate(THUNDER_SRC):
        x = _fade(d.from_onset(bc.src(sid, 0.0, 7.0), 5.0, thr_db=-26.0), 3.6, 6.0)
        finalize("thunder_%d" % (i + 1), d.filt(x, "hp", 25.0, order=2), lufs=-19.4, fade_out_ms=400)


# ============================================================ WROGOWIE (bake_sfx.build_enemies)
# Każdy gatunek ma własne źródła (inne niż Stalker) i zachowuje gest wersji syntetycznej: Trzosek — psie warknięcie
# z warkotem ogara, Wołek — ryk bestii z ciężarem w dole, Ślepiec — trzepoczący wydech z klikaniem (śmierć), Podsłuchacz —
# drżący wrzask, Pijawka — bulgot i skrzek morskiego stwora, Żyła — ryk złożony z kilku głosów naraz.
# Zapowiedź ciosu Ślepca i pomruk Żyły zostały syntetyczne (werdykt odsłuchu). Głośność = zmierzona głośność syntezy.

def _clip(sid: str, t0: float, dur: float, semis: float, end: float, tail: float = 0.12, onset: bool = True) -> np.ndarray:
    """Wycinek nagrania (od ataku albo od t0), przestrojony o `semis` półtonów, wygaszony do `end` [s]; szczyt = 1."""
    x = bc.src(sid, t0, dur)
    x = d.repitch(d.from_onset(x, 2.0) if onset else x, semis)
    n = min(len(x), d.sec(end))
    end = n / d.SR
    return _unit(x[:n] * d.env_pts(n, [(0, 0), (.004 if onset else .03, 1), (max(.04, end - tail), 1), (end, 0)]))


# Trzosek: duży pies obniżony o 6 półtonów, z warkotem ogara i oktawą w dół pod spodem („wilkołak” z odsłuchu;
# pierwsza wersja — owadzi terkot — była w grze za wysoka). Śmierć: szczeknięcie przechodzące w skowyt.
TRZOSEK_NEEDS = ["dog_bark_growl", "dog_whimper", "shepherd_barks", "hellhound_idle"]
TRZOSEK_SEMIS = -6.0
_DOG_ATTACKS = (1.51, 4.16, 17.91)                                   # warknięcia-szczeknięcia dużego psa w dog_bark_growl [s]
_DOG_WHIMPERS = (7.56, 9.80)                                         # długie skowyty w dog_whimper [s]
_DOG_YELPS = (10.77, 11.52)                                          # pojedyncze szczeknięcia owczarka [s]


def _trzosek_attack_bake() -> None:
    for i, t0 in enumerate(_DOG_ATTACKS):
        x = _clip("dog_bark_growl", t0 - 0.03, 0.75, TRZOSEK_SEMIS, 0.60, tail=.2)
        parts = [(x, 1.0), (_clip("hellhound_idle", 3.6 + 0.5 * i, 0.6, -3.0, 0.60, tail=.25, onset=False), 0.5),
                 (_unit(d.lp(d.repitch(x, -12.0)[:len(x)], 180.0)), 0.3)]
        x = d.saturate(_unit(d.filt(d.mix(parts, ms(620)), "hp", 70.0, order=2)), 2.0)
        finalize("trzosek_attack_%d" % (i + 1), d.reverb(x, ir("close"), wet=.15), lufs=-16.0, fade_out_ms=30)


def _trzosek_death_bake() -> None:
    for i, t0 in enumerate(_DOG_WHIMPERS):
        yelp = _clip("shepherd_barks", _DOG_YELPS[i] - 0.02, 0.22, TRZOSEK_SEMIS, 0.20, tail=.07)
        whine = _clip("dog_whimper", t0, 0.9, TRZOSEK_SEMIS, 0.72, tail=.35, onset=False)
        parts = [(yelp, 0.8), (whine, 1.0, 0.09), (_clip("hellhound_idle", 4.2, 0.7, -3.0, 0.70, tail=.4, onset=False), 0.4)]
        x = d.saturate(_unit(d.filt(d.mix(parts, ms(820)), "hp", 70.0, order=2)), 1.6)
        finalize("trzosek_death_%d" % (i + 1), d.reverb(x, ir("close"), wet=.15), lufs=-16.0, fade_out_ms=40)


WOLEK_ATTACK_NEEDS = ["beast01_attack_08", "beast01_threaten_06", "orc_grunt_003"]


def _wolek_attack_bake() -> None:
    a = _clip("beast01_attack_08", 0.05, 1.1, -3.0, 0.95, tail=.2)
    b = d.mix([(_clip("beast01_threaten_06", 0.05, 0.9, -2.0, 0.9, tail=.2), 1.0),
               (_clip("orc_grunt_003", 0.0, 1.1, -4.0, 0.9, tail=.25), 0.5)], ms(950))
    for i, x in enumerate((a, b)):
        x = d.mix([(x, 1.0), (thump(.3, 85, 40, .06, .1), 0.5)], ms(980))
        x = d.saturate(_unit(d.filt(x, "hp", 35.0, order=2)), 2.0)
        finalize("wolek_attack_%d" % (i + 1), d.reverb(x, ir("room"), wet=.2, keep_len=True), lufs=-14.15, fade_out_ms=60)


WOLEK_DEATH_NEEDS = ["troll_death_01", "yeti_grumble_02"]


def _wolek_death_bake() -> None:
    a = _clip("troll_death_01", 0.0, 1.8, -2.0, 1.4, tail=.4)
    b = _clip("yeti_grumble_02", 0.0, 1.3, -4.0, 1.35, tail=.4)
    for i, x in enumerate((a, b)):
        x = d.mix([(x, 1.0), (thump(.3, 95, 38, .05, .09), 0.6, .75 + .06 * i)], ms(1400))      # upadek cielska
        x = d.limiter(d.saturate(_unit(d.filt(x, "hp", 35.0, order=2)), 1.8), -4.0)
        finalize("wolek_death_%d" % (i + 1), d.reverb(x, ir("room"), wet=.2, keep_len=True), lufs=-14.3, fade_out_ms=80)


SLEPIEC_DEATH_NEEDS = ["flutter_death_05"]


def _slepiec_death_bake() -> None:
    import bake_sfx                                                  # klikanie to ta sama synteza co w wersji publicznej
    for i, t0 in enumerate((1.0, 2.8)):                              # dwa głośne odcinki trzepoczącego, urywanego wydechu
        r = Rng(0x5F00 + i * 1361)
        n = ms(950 + 80 * i)
        T = n / d.SR
        voice = _clip("flutter_death_05", t0, 1.1, -1.0 - i, T, tail=.45, onset=False)
        clicks = bake_sfx._clicks(n, r, .03, T - .2, .03, 1.22, 1900.0 + 250 * i, fade=.09)
        x = d.mix([(voice, 1.0), (_unit(clicks), 0.4)], n)
        finalize("slepiec_death_%d" % (i + 1), d.reverb(x, ir("close"), wet=.2), lufs=-17.9, fade_out_ms=60)


SCREAM_NEEDS = ["banshee_damage_07", "alien_death_01", "ethereal_pain_4"]
SCREAM_CEIL = -6.0


def _scream_bake() -> None:
    a = d.mix([(_clip("banshee_damage_07", 0.0, 0.85, 2.0, 0.7, tail=.2), 1.0),
               (_clip("banshee_damage_07", 0.0, 0.85, -1.0, 0.9, tail=.3), 0.8, .4),
               (_clip("ethereal_pain_4", 0.0, 1.7, 10.0, 0.9, tail=.3), 0.5)], d.sec(1.3))
    b = d.mix([(_clip("alien_death_01", 0.0, 1.4, 4.0, 1.0, tail=.3), 1.0),
               (_clip("banshee_damage_07", 0.0, 0.85, 3.0, 0.65, tail=.2), 0.7, .25),
               (_clip("ethereal_pain_4", 0.0, 1.7, 12.0, 0.8, tail=.3), 0.4)], d.sec(1.2))
    for i, x in enumerate((a, b)):
        t = np.arange(len(x)) / d.SR
        x = x * (.75 + .25 * np.sin(d.TAU * (11.0 + 2 * i) * t))     # drżenie alarmu — jak w syntezie
        x = d.saturate(_unit(d.filt(x, "hp", 400.0, order=2)), 2.5)
        x = d.limiter(_unit(_fade(d.reverb(x, ir("hall"), wet=.25), 1.3, 1.7)), SCREAM_CEIL - 2.0)
        finalize("podsluchacz_scream_%d" % (i + 1), x, lufs=-10.1, fade_out_ms=120)


LEECH_GROWL_NEEDS = ["aquatic_gurgling_2", "organic_texture_041", "water_movement_large_009"]


def _leech_growl_bake() -> None:
    rows = ((1.0, 1.7, -7.0, "organic_texture_041", 0.0, -2.0), (2.4, 1.5, -9.0, "water_movement_large_009", 0.05, -3.0))
    for i, (t0, ln, semis, low_sid, low_t0, low_semis) in enumerate(rows):
        gurg = _clip("aquatic_gurgling_2", t0, ln, semis, 2.4, tail=.5, onset=False)
        low = _clip(low_sid, low_t0, 2.3, low_semis, 2.4, tail=.5)
        sub = d.lp(d.repitch(gurg, -12.0)[:len(gurg)], 200.0)
        x = d.mix([(gurg, 1.0), (low, 0.8), (_unit(sub), 0.4)], d.sec(2.4))
        x = d.saturate(_unit(d.filt(x, "hp", 30.0, order=2)), 1.8)
        finalize("leech_growl_%d" % (i + 1), d.reverb(x, ir("hall"), wet=.25, keep_len=True), lufs=-14.1, fade_out_ms=250)


LEECH_SHRIEK_NEEDS = ["sea_beast_yell_04", "swamp_fish_damage_08"]


def _leech_shriek_bake() -> None:
    for i, (t0, semis) in enumerate(((0.2, -2.0), (1.6, -4.0))):
        yell = _clip("sea_beast_yell_04", t0, 1.3, semis, 1.3, tail=.35, onset=False)
        fish = _clip("swamp_fish_damage_08", 0.0, 0.8, (0.0, -2.0)[i], 0.7, tail=.2)
        x = d.mix([(yell, 1.0), (fish, 0.6), (thump(.4, 85, 36, .1, .14), 0.5)], d.sec(1.3))
        x = d.saturate(_unit(d.filt(x, "hp", 35.0, order=2)), 2.6)
        x = d.limiter(_unit(_fade(d.reverb(x, ir("hall"), wet=.28), 1.25, 1.7)), SCREAM_CEIL)
        finalize("leech_shriek_%d" % (i + 1), x, lufs=-10.55, fade_out_ms=120)


ZYLA_ROAR_NEEDS = ["dragon_roar_01", "large_beast_taunt_03", "behemoth_talk_04", "large_monster11_roar03"]


def _zyla_roar_bake() -> None:
    a = d.mix([(_clip("dragon_roar_01", 0.0, 2.0, -2.0, 1.9, tail=.5), 1.0),
               (_clip("large_beast_taunt_03", 0.0, 2.0, -1.0, 1.9, tail=.5), 0.8)], d.sec(1.9))
    b = d.mix([(_clip("behemoth_talk_04", 0.0, 1.8, -3.0, 1.9, tail=.5), 1.0),
               (_clip("dragon_roar_01", 0.0, 1.6, -5.0, 1.9, tail=.5), 0.7),
               (_clip("large_monster11_roar03", 0.0, 0.7, -6.0, 1.0, tail=.3), 0.6)], d.sec(1.9))
    for i, x in enumerate((a, b)):
        x = d.mix([(x, 1.0), (thump(.6, 80, 30, .12, .2), 0.6)], d.sec(1.9))
        x = d.saturate(_unit(d.filt(x, "hp", 30.0, order=2)), 2.8)
        x = d.limiter(_unit(_fade(d.reverb(x, ir("hall"), wet=.3), 1.9, 2.4)), SCREAM_CEIL)
        finalize("zyla_roar_%d" % (i + 1), x, lufs=-11.25, fade_out_ms=150)


# ============================================================ GRACZ I EMITERY AMBIENTU (bake_sfx.build_player / build_world)
# Głos gracza: ból z dwóch okrzyków tego samego zestawu nagrań, upadek z jęku + to samo uderzenie ciała co w syntezie.

PLAYER_HURT_NEEDS = ["male_shout_pain_132", "male_grunt_shout_317"]


def _player_hurt_bake() -> None:
    for i, (sid, end) in enumerate((("male_shout_pain_132", 0.76), ("male_grunt_shout_317", 0.62))):
        x = d.saturate(_unit(d.filt(_clip(sid, 0.0, 0.95, 0.0, end, tail=.18), "hp", 90.0, order=2)), 1.4)
        x = d.limiter(_unit(x), -5.0)                                # gęsto jak synteza: okrzyk ma się przebić przez strzały
        finalize("player_hurt_%d" % (i + 1), d.reverb(x, ir("close"), wet=.15), lufs=-12.05)


PLAYER_DOWN_NEEDS = ["male_death_low_09"]


def _player_down_bake() -> None:
    voice = _clip("male_death_low_09", 0.0, 1.7, 0.0, 1.5, tail=.4)
    x = d.mix([(voice, 1.0), (thump(.22, 110, 45, .04, .07), 0.9, .7)], d.sec(1.6))
    x = d.limiter(d.saturate(_unit(d.filt(x, "hp", 40.0, order=2)), 1.3), -4.0)
    finalize("player_down", d.reverb(x, ir("room"), wet=.2), lufs=-14.5, fade_out_ms=200)


# --- Emitery ambientu: skrzypienie konstrukcji, poryw wiatru, odległe uderzenie (grane cicho, z daleka).
CREAK_NEEDS = ["metal_creak_13", "blocked_door_creaks_09"]
_CREAKS = (("metal_creak_13", 0.05, 1.55, -5.0), ("metal_creak_13", 2.65, 2.4, -3.0), ("blocked_door_creaks_09", 2.3, 1.6, -4.0))


def _creak_bake() -> None:
    for i, (sid, t0, ln, semis) in enumerate(_CREAKS):
        x = d.lp(d.filt(_clip(sid, t0, ln, semis, 3.2, tail=.5, onset=False), "hp", 60.0, order=2), 5000.0)
        finalize("amb_creak_%d" % (i + 1), d.reverb(x, ir("hall"), wet=.3), lufs=-26.0, fade_out_ms=300)


GUST_NEEDS = ["whoosh_wind_gust_11", "wind_howl_gust"]
_GUSTS = (("whoosh_wind_gust_11", 0.25, 3.7), ("wind_howl_gust", 1.6, 4.0), ("wind_howl_gust", 4.4, 4.6))


def _gust_bake() -> None:
    for i, (sid, t0, ln) in enumerate(_GUSTS):
        x = d.filt(bc.src(sid, t0, ln), "hp", 80.0, order=2)
        T = len(x) / d.SR
        x = x * d.env_pts(len(x), [(0, 0), (.5, 1), (T - 1.0, 1), (T, 0)])
        finalize("amb_gust_%d" % (i + 1), x, lufs=-28.0, fade_out_ms=500)


THUD_NEEDS = ["deep_thud_10", "cannonball_impact_005"]


def _thud_bake() -> None:
    a = _clip("deep_thud_10", 0.0, 3.2, -2.0, 3.0, tail=1.2)
    b = _clip("cannonball_impact_005", 0.0, 1.3, -4.0, 1.5, tail=.6)
    for i, x in enumerate((a, b)):
        x = d.reverb(d.filt(x, "hp", 25.0, order=2), ir("cave"), wet=.35)
        finalize("amb_thud_%d" % (i + 1), x, lufs=-24.0, fade_out_ms=500)


def enemies() -> None:
    """Wersje z nagrań dla głosów wrogów — wołane na końcu bake_sfx.build_enemies()."""
    bc.hybrid(_keys("trzosek_attack", 3), _trzosek_attack_bake, TRZOSEK_NEEDS)
    bc.hybrid(_keys("trzosek_death", 2), _trzosek_death_bake, TRZOSEK_NEEDS)
    bc.hybrid(_keys("wolek_attack", 2), _wolek_attack_bake, WOLEK_ATTACK_NEEDS)
    bc.hybrid(_keys("wolek_death", 2), _wolek_death_bake, WOLEK_DEATH_NEEDS)
    bc.hybrid(_keys("slepiec_death", 2), _slepiec_death_bake, SLEPIEC_DEATH_NEEDS)
    bc.hybrid(_keys("podsluchacz_scream", 2), _scream_bake, SCREAM_NEEDS)
    bc.hybrid(_keys("leech_growl", 2), _leech_growl_bake, LEECH_GROWL_NEEDS)
    bc.hybrid(_keys("leech_shriek", 2), _leech_shriek_bake, LEECH_SHRIEK_NEEDS)
    bc.hybrid(_keys("zyla_roar", 2), _zyla_roar_bake, ZYLA_ROAR_NEEDS)


def world() -> None:
    """Wersje z nagrań dla dźwięków świata — wołane na końcu bake_sfx.build_world()."""
    bc.hybrid(_keys("door", 2), _door_bake, DOOR_NEEDS)
    bc.hybrid(_keys("glass_break", 2), _glass_bake, GLASS_NEEDS)
    bc.hybrid(_keys("thunder", 3), _thunder_bake, list(THUNDER_SRC))
    bc.hybrid(_keys("amb_creak", 3), _creak_bake, CREAK_NEEDS)
    bc.hybrid(_keys("amb_gust", 3), _gust_bake, GUST_NEEDS)
    bc.hybrid(_keys("amb_thud", 2), _thud_bake, THUD_NEEDS)


# ============================================================ SYGNAŁY (bake_sfx.build_ui)
# `ui_confirm` (zebrany przedmiot z zadania, uruchomiony generator, awans, sukces misji, przycisk hosta): mechaniczny stuk
# wyłącznika i zaskok napędu magnetofonu zamiast dwóch syntezatorowych blików. `mission_start`: włączenie radiostacji —
# stuk wyłącznika, fala szumu strojonego radia, krótki szum zamykanej blokady krótkofalówki.
CONFIRM_LUFS = -14.2                                                 # zmierzona głośność dawnej syntezy ui_confirm
CONFIRM_NEEDS = ["breaker_on", "tape_play_stop"]
START_NEEDS = ["breaker_on", "radio_tuning_static", "walkie_kenwood"]


def _confirm_bake() -> None:
    a = _clip("breaker_on", 0.03, 0.2, -3.0, 0.20, tail=.10)
    b = _clip("tape_play_stop", 1.69, 0.3, -2.0, 0.30, tail=.14)
    x = d.mix([(a, 1.0), (b, 0.8, .09), (thump(.08, 150, 70, .02, .035), 0.5)], ms(420))
    x = d.limiter(_unit(d.filt(x, "hp", 60.0, order=2)), -10.0)
    finalize("ui_confirm", d.reverb(x, ir("dead"), wet=.08), lufs=CONFIRM_LUFS)


def _mission_start_bake() -> None:
    clunk = _clip("breaker_on", 0.03, 0.2, -4.0, 0.22, tail=.10)
    static = bc.src("radio_tuning_static", 6.4, 1.0)
    static = _unit(d.lp(static, 4000.0) * d.env_pts(len(static), [(0, 0), (.06, 1), (.5, .6), (.95, .15), (1.0, 0)]))
    end = _clip("walkie_kenwood", 5.18, 0.42, -3.0, 0.30, tail=.14)
    x = d.mix([(clunk, 1.0), (thump(.12, 140, 55, .03, .05), 0.6), (static, 0.4, .10), (end, 0.25, 1.0)], ms(1350))
    x = d.limiter(_unit(d.filt(x, "hp", 50.0, order=2)), -9.0)
    finalize("mission_start", d.reverb(x, ir("room"), wet=.15), lufs=-15.0, fade_out_ms=120)


def ui() -> None:
    """Wersje z nagrań dla sygnałów — wołane na końcu bake_sfx.build_ui()."""
    bc.hybrid(["ui_confirm"], _confirm_bake, CONFIRM_NEEDS)
    bc.hybrid(["mission_start"], _mission_start_bake, START_NEEDS)


# ============================================================ KANDYDACI DO ODSŁUCHU

# (nazwa wersji, funkcja piekąca, potrzebne źródła) — przed decyzją; build_alts() piecze je do katalogu z --alts.
# Pusto: wszystkie dotychczasowe rodziny mają werdykt.
CANDIDATES: tuple = ()


def build_alts() -> None:
    """Wersje alternatywne do następnego odsłuchu A/B (bc.alt): bake_audio.py --only alts --alts KATALOG."""
    for name, fn, needs in CANDIDATES:
        bc.alt(name, fn, needs)
