"""Bronie w wysokiej rozdzielczości (1.7.17) — jeden projekt, dwa arkusze:
  gun_icons.png  64×24  ikony do HUD i kodeksu (pełna broń, powiększana),
  guns.png       72×28  broń w świecie (2× gęstość pikseli, rysowana w grze w skali 0,5 → rozmiar na ekranie jak 36×14): ten sam projekt przeskalowany tak, by chwyt wypadł w dłoni (HAND) a wylot lufy
                        w HAND.x + gun_len (weapons.gd) — kolba za dłonią jest ucięta, jak w starym arkuszu.
Renderowane silnikiem postaci (char_art: render 4×, rampy, obrys, warstwa świecąca), widok z boku, lufa w prawo.
Kolejność wierszy = gun_row z weapons.gd.
"""
import math
from char_art import Hi, Frame, ramp
from char_monsters import _finish
from char_monsters_hd import Sc

FW, FH = 64, 24                    # ikona (HUD, kodeks)
WORLD_DENSITY = 2                  # ile pikseli arkusza przypada na piksel świata (gra rysuje sprite w skali 1/2)
WFW, WFH = 36 * WORLD_DENSITY, 14 * WORLD_DENSITY   # sprite w świecie
HAND = (6.5 * WORLD_DENSITY, 7.0 * WORLD_DENSITY)    # dłoń (pivot obrotu) w klatce, w pikselach arkusza; zgodne z weapon_view.gd
# nazwa → (x chwytu, y chwytu, x wylotu w rysunku ikony, skala rysunku→świat); gun_len = (x wylotu − x chwytu) · skala
GRIP = {
    "m83": (26.0, 15.5, 63.0, 0.50), "spread12": (26.0, 15.2, 62.4, 0.50), "p64": (28.0, 13.4, 61.0, 0.42),
    "srut8": (26.0, 15.2, 62.6, 0.50), "lr7": (28.5, 14.8, 63.8, 0.50), "hkm9": (32.5, 15.4, 63.0, 0.50),
    "gniew4": (36.0, 12.5, 61.0, 0.56), "sokol6": (28.5, 14.5, 60.0, 0.50), "widmo1": (32.5, 14.0, 64.0, 0.55),
    "ciegno6": (28.0, 15.4, 62.0, 0.50), "maczeta": (10.0, 12.0, 62.0, 0.42), "kilof": (12.0, 14.0, 62.4, 0.40),
}


def gun_len(name):
    """Odległość dłoń → wylot w świecie [px]; ta liczba idzie do `gun_len` w weapons.gd."""
    gx, _gy, mx, k = GRIP[name]
    return round((mx - gx) * k)
NAMES = ["m83", "spread12", "p64", "srut8", "lr7", "hkm9", "gniew4", "sokol6", "widmo1", "ciegno6", "maczeta", "kilof"]
BANDS = (-0.05, 0.25, 0.55, 0.85)


def _mats(hi):
    M = {}
    M["steel"] = hi.material(ramp((150, 154, 166), cool=(0.18, 0.18, 0.34)), bands=BANDS)
    M["steel_l"] = hi.material(ramp((190, 194, 204), cool=(0.18, 0.18, 0.34)), bands=BANDS)
    M["steel_d"] = hi.material(ramp((84, 88, 102), cool=(0.16, 0.16, 0.34)), bands=BANDS)
    M["poly"] = hi.material(ramp((58, 60, 70), cool=(0.14, 0.14, 0.32)), bands=BANDS)
    M["poly_l"] = hi.material(ramp((86, 88, 100), cool=(0.14, 0.14, 0.32)), bands=BANDS)
    M["wood"] = hi.material(ramp((128, 80, 42), cool=(0.2, 0.12, 0.28)), bands=BANDS)
    M["wood_d"] = hi.material(ramp((84, 52, 28), cool=(0.18, 0.1, 0.28)), bands=BANDS)
    M["brass"] = hi.material(ramp((206, 156, 62), cool=(0.24, 0.16, 0.3)), bands=BANDS)
    M["olive"] = hi.material(ramp((84, 98, 58), cool=(0.18, 0.16, 0.3)), bands=BANDS)
    M["olive_d"] = hi.material(ramp((56, 66, 40), cool=(0.16, 0.14, 0.3)), bands=BANDS)
    M["red"] = hi.material(ramp((176, 52, 40), cool=(0.22, 0.1, 0.24)), bands=BANDS)
    M["slate"] = hi.material(ramp((88, 104, 132), cool=(0.18, 0.16, 0.34)), bands=BANDS)
    M["slate_d"] = hi.material(ramp((52, 62, 84), cool=(0.16, 0.14, 0.34)), bands=BANDS)
    M["cyan"] = hi.material(ramp((90, 200, 230), warm=(0.9, 1.0, 1.0), cool=(0.1, 0.25, 0.5)), bands=(-0.4, 0.0, 0.4, 0.8))
    M["dark"] = hi.material(ramp((22, 22, 30), cool=(0.08, 0.08, 0.2)), bands=(0.2, 0.5, 0.8, 0.95))
    M["cord"] = hi.material(ramp((206, 198, 166), cool=(0.24, 0.2, 0.3)), bands=BANDS)
    return M


def _glow_dots(glow, pts, col, a=255):
    for x, y in pts:
        glow.put(int(round(x)), int(round(y)), (*col, a))


def _grip(hi, M, x, y, h=8.0, lean=-0.35, w=3.4, mat="poly"):
    hi.poly([(x, y), (x + w, y), (x + w + lean * h * -1 - 0.4, y + h), (x - 0.4 + lean * h * -1 * 0.2, y + h)], M[mat])


def gun(name, world=False):
    fw, fh = (WFW, WFH) if world else (FW, FH)
    if world:
        gx, gy, mx, k = GRIP[name]
        k *= WORLD_DENSITY                                  # ten sam rozmiar w świecie, więcej pikseli
        hi = Sc(fw, fh, k, HAND[0] - gx * k, HAND[1] - gy * k)
    else:
        hi = Sc(fw, fh)
    M = _mats(hi)
    glow_pts = []
    gcol = (120, 220, 255)
    cy = 12.0
    if name == "m83":
        # pistolet maszynowy: szkieletowa kolba, szyna, wygięty magazynek
        hi.capsule((4, cy - 2), (18, cy - 3), 1.0, 1.0, M["steel_d"])                       # szkielet kolby
        hi.capsule((4, cy + 3), (18, cy + 1.5), 1.0, 1.0, M["steel_d"])
        hi.capsule((4, cy - 2), (4, cy + 3), 1.2, 1.2, M["poly"])
        hi.rbox((30, cy - 0.5), 26, 7.4, M["poly"])
        hi.rbox((30, cy - 3.0), 25, 3.0, M["steel"])                                         # górna szyna
        for k in range(8):
            hi.rbox((19.5 + k * 3.0, cy - 5.0), 1.6, 1.4, M["steel_l"])                      # zęby szyny Picatinny
        hi.rbox((47, cy - 0.4), 14, 5.6, M["poly_l"])                                         # łoże
        for k in range(4):
            hi.capsule((42 + k * 3.0, cy - 2.4), (42 + k * 3.0, cy + 1.6), 0.5, 0.5, M["dark"])   # otwory chłodzące
        hi.capsule((53, cy - 1.4), (60, cy - 1.4), 1.2, 1.0, M["steel"])                       # lufa
        hi.rbox((61, cy - 1.4), 4.0, 3.6, M["steel_d"])                                        # tłumik/hamulec
        hi.poly([(57.2, cy - 3.2), (59.4, cy - 3.2), (58.6, cy - 6.2)], M["steel"])            # muszka
        hi.poly([(20.0, cy - 3.6), (23.5, cy - 3.6), (22.5, cy - 6.6), (21.0, cy - 6.6)], M["steel"])  # szczerbinka
        hi.poly([(31, cy + 3), (37, cy + 3), (38.5, cy + 10), (36, cy + 12), (33, cy + 11)], M["poly"])   # magazynek
        hi.capsule((33.4, cy + 6.0), (36.0, cy + 6.4), 0.7, 0.7, M["brass"])                  # okienko nabojów
        hi.poly([(24, cy + 3), (28.4, cy + 3), (27.4, cy + 11), (23.6, cy + 10.2)], M["poly"])             # chwyt
        hi.capsule((29.4, cy + 4.0), (33.0, cy + 6.2), 0.5, 0.5, M["steel_d"])                  # kabłąk
        hi.rbox((36.5, cy - 1.8), 5.0, 1.8, M["dark"])                                          # okno wyrzutu
        glow_pts = [(61, cy - 1.4)]
        gcol = (255, 200, 120)
    elif name == "spread12":
        # półautomatyczna strzelba: drewniana kolba i łoże, żebro nad lufą
        hi.poly([(2, cy - 4), (21, cy - 3.0), (21, cy + 3.0), (6, cy + 8), (2, cy + 7)], M["wood"])    # kolba
        hi.poly([(2, cy - 4), (4.6, cy - 4), (4.6, cy + 7), (2, cy + 7)], M["dark"])                  # gumowy kapsel
        for k in range(3):
            hi.capsule((8 + k * 3.2, cy - 2), (9 + k * 3.2, cy + 2.4), 0.3, 0.3, M["wood_d"])          # słoje
        hi.rbox((27, cy - 0.5), 14, 7.0, M["steel"])                                                   # komora
        hi.rbox((27, cy - 0.8), 11, 2.6, M["steel_l"])
        hi.rbox((27.4, cy + 2.0), 6, 1.6, M["dark"])                                                   # okno wyrzutu
        hi.capsule((34, cy - 2.0), (61, cy - 2.0), 1.4, 1.4, M["steel"])                               # lufa
        hi.capsule((34, cy + 1.2), (56, cy + 1.2), 1.1, 1.1, M["steel_d"])                             # rura magazynka
        hi.rbox((47, cy + 0.6), 18, 5.2, M["wood"])                                                    # łoże
        for k in range(5):
            hi.capsule((39 + k * 3.4, cy - 1.2), (39 + k * 3.4, cy + 3.0), 0.35, 0.35, M["wood_d"])
        hi.poly([(58.4, cy - 3.6), (60.2, cy - 3.6), (59.4, cy - 6.0)], M["steel_l"])                  # muszka
        hi.capsule((28, cy - 4.0), (60, cy - 4.0), 0.5, 0.5, M["steel_l"])                             # żebro
        hi.poly([(24, cy + 3.0), (28.4, cy + 3.0), (27.2, cy + 10.4), (23.4, cy + 9.4)], M["wood"])    # chwyt
        hi.capsule((29.4, cy + 4.0), (33, cy + 5.6), 0.5, 0.5, M["steel_d"])
        glow_pts = [(61, cy - 2.0)]
        gcol = (255, 190, 110)
    elif name == "p64":
        hi.rbox((34, cy - 3.0), 30, 6.6, M["steel"])                                                   # zamek
        hi.rbox((33, cy - 4.4), 26, 2.4, M["steel_l"])
        for k in range(5):
            hi.capsule((22 + k * 1.5, cy - 5.2), (22 + k * 1.5, cy - 1.6), 0.35, 0.35, M["steel_d"])    # nacięcia
        hi.capsule((40, cy + 1.6), (60, cy + 1.6), 1.0, 1.0, M["steel_d"])                             # lufa pod zamkiem
        hi.rbox((50, cy - 0.6), 26, 4.6, M["poly"])                                                    # szkielet
        hi.rbox((56, cy - 0.6), 6, 3.6, M["steel_d"])
        hi.poly([(24, cy + 1.0), (32, cy + 1.0), (29.6, cy + 11.4), (23.2, cy + 10.4)], M["poly"])        # chwyt
        for k in range(4):
            hi.capsule((25.0 - k * 0.5, cy + 4.0 + k * 1.6), (30.0 - k * 0.5, cy + 4.0 + k * 1.6), 0.3, 0.3, M["poly_l"])  # radełkowanie
        hi.capsule((33, cy + 3.0), (40, cy + 3.0), 0.5, 0.5, M["steel_d"])                             # kabłąk
        hi.capsule((40, cy + 3.0), (38, cy + 6.4), 0.5, 0.5, M["steel_d"])
        hi.capsule((33, cy + 3.0), (34.4, cy + 6.4), 0.5, 0.5, M["steel_d"])
        hi.capsule((34.4, cy + 6.4), (38, cy + 6.4), 0.5, 0.5, M["steel_d"])
        hi.poly([(58, cy - 5.8), (59.8, cy - 5.8), (59.0, cy - 7.6)], M["steel_l"])
        hi.poly([(25, cy - 5.6), (28.4, cy - 5.6), (27.6, cy - 7.6), (25.6, cy - 7.6)], M["steel_l"])
        glow_pts = [(62, cy + 1.6)]
        gcol = (255, 200, 120)
    elif name == "srut8":
        # ciężka strzelba pompka: wentylowana osłona, pompka, hamulec wylotowy
        hi.poly([(2, cy - 4), (20, cy - 3.0), (20, cy + 3.0), (6, cy + 8), (2, cy + 7)], M["wood"])
        hi.poly([(2, cy - 4), (4.6, cy - 4), (4.6, cy + 7), (2, cy + 7)], M["dark"])
        hi.rbox((27, cy - 0.5), 14, 7.4, M["steel_d"])
        hi.capsule((34, cy - 2.4), (57, cy - 2.4), 1.8, 1.8, M["steel"])                              # gruba lufa
        hi.rbox((46, cy - 2.6), 22, 4.2, M["steel_d"])                                                # osłona wentylowana
        for k in range(9):
            hi.capsule((36 + k * 2.4, cy - 4.0), (36 + k * 2.4, cy - 1.2), 0.4, 0.4, M["dark"])
        hi.capsule((34, cy + 1.6), (54, cy + 1.6), 1.3, 1.3, M["steel_d"])                            # rura magazynka
        hi.rbox((45, cy + 2.4), 14, 5.0, M["wood_d"])                                                  # pompka
        for k in range(5):
            hi.capsule((39 + k * 2.8, cy + 0.6), (39 + k * 2.8, cy + 4.6), 0.4, 0.4, M["wood"])
        hi.rbox((59.5, cy - 2.4), 6, 5.6, M["steel_d"])                                               # hamulec wylotowy
        for k in range(3):
            hi.capsule((57.6 + k * 1.8, cy - 4.6), (57.6 + k * 1.8, cy - 0.2), 0.35, 0.35, M["dark"])
        hi.poly([(24, cy + 3.0), (28.4, cy + 3.0), (27.2, cy + 10.4), (23.4, cy + 9.4)], M["wood"])
        hi.capsule((29.4, cy + 4.0), (33, cy + 5.6), 0.5, 0.5, M["steel_d"])
        glow_pts = [(62, cy - 2.4)]
        gcol = (255, 190, 110)
    elif name == "lr7":
        # działo energetyczne: radiator z żebrami, taśma energii (świeci), emiter z soczewką
        hi.rbox((10, cy), 12, 7.0, M["poly"])
        hi.rbox((30, cy - 0.4), 32, 8.4, M["poly"])
        for k in range(9):
            hi.rbox((17 + k * 3.2, cy - 5.4), 2.0, 2.4, M["steel_d"])                                 # żebra radiatora
        hi.rbox((30, cy - 0.4), 28, 3.6, M["dark"])                                                    # kanał taśmy energii
        hi.rbox((30, cy - 0.4), 26, 1.8, M["cyan"])
        for k in range(6):
            hi.capsule((19 + k * 4.0, cy - 1.0), (21 + k * 4.0, cy + 0.2), 0.4, 0.4, M["steel_l"])
        hi.rbox((51, cy + 0.2), 10, 6.0, M["steel"])                                                   # korpus emitera
        hi.rbox((59, cy + 0.2), 6, 7.6, M["steel_d"])
        hi.ellipse((62.0, cy + 0.2), 1.8, 2.6, M["cyan"])                                              # soczewka
        hi.poly([(26, cy + 3.6), (31, cy + 3.6), (29.6, cy + 11.4), (25.0, cy + 10.4)], M["poly"])
        hi.rbox((38, cy + 5.4), 8, 3.0, M["steel_d"])                                                  # ogniwo
        hi.rbox((38, cy + 5.4), 6, 1.4, M["cyan"])
        glow_pts = [(x, cy - 0.6) for x in range(17, 43, 2)] + [(62, cy), (62, cy + 1), (61, cy + 0.6), (38, cy + 5.4), (40, cy + 5.4)]
    elif name == "hkm9":
        # miotacz ognia: czerwony zbiornik z pasem ostrzegawczym, wąż, rura z osłoną, pilot
        hi.ellipse((12, cy + 1.4), 10.0, 7.0, M["red"])                                                # zbiornik
        hi.rbox((12, cy + 1.4), 20, 4.6, M["red"], curve=0.5)
        hi.poly([(5.6, cy - 4.0), (9.6, cy - 5.2), (9.6, cy + 6.8), (5.6, cy + 6.0)], M["brass"])         # pas ostrzegawczy
        hi.poly([(13.0, cy - 5.4), (16.6, cy - 4.6), (16.6, cy + 6.6), (13.0, cy + 7.2)], M["brass"])
        hi.capsule((3, cy - 4.4), (9, cy - 6.2), 0.8, 0.8, M["dark"])
        hi.capsule((21, cy + 2.2), (26, cy + 5.4), 1.5, 1.5, M["poly"])                              # wąż
        hi.capsule((26, cy + 5.4), (33, cy + 2.4), 1.5, 1.5, M["poly"])
        hi.capsule((21, cy + 1.6), (26, cy + 4.8), 0.5, 0.5, M["poly_l"])
        hi.rbox((34, cy), 16, 6.6, M["steel"])                                                          # komora
        hi.capsule((42, cy - 0.8), (59, cy - 0.8), 2.0, 2.0, M["steel"])                               # rura z osłoną
        hi.rbox((50, cy - 1.0), 14, 5.0, M["steel_d"])
        for k in range(5):
            hi.capsule((44 + k * 2.6, cy - 3.0), (44 + k * 2.6, cy + 1.2), 0.4, 0.4, M["dark"])
        hi.rbox((60.5, cy - 0.8), 4.0, 5.6, M["steel_d"])                                              # dysza
        hi.capsule((60, cy - 3.2), (62.4, cy - 3.2), 0.4, 0.4, M["steel_l"])
        hi.poly([(30, cy + 3.4), (35, cy + 3.4), (33.6, cy + 11.4), (29.0, cy + 10.4)], M["poly"])
        hi.capsule((36.4, cy + 4.0), (40, cy + 6.0), 0.5, 0.5, M["steel_d"])
        glow_pts = [(63, cy - 0.8), (62, cy - 0.8), (63, cy), (62, cy - 1.6), (62, cy - 3.4)]
        gcol = (255, 150, 60)
    elif name == "gniew4":
        # granatnik: oliwkowa tuba z obręczami, bęben z mosiężnymi pociskami
        hi.poly([(2, cy - 2), (10, cy - 2.4), (10, cy + 3), (4, cy + 6), (2, cy + 4)], M["poly"])       # kolba
        hi.rbox((34, cy - 2.0), 46, 9.4, M["olive"])
        hi.rbox((34, cy - 4.6), 44, 3.0, M["olive_d"], bias=0.1) if False else None
        for x in (16, 28, 40, 52):
            hi.rbox((x, cy - 2.0), 2.2, 11.4, M["steel_d"])                                            # obręcze
        hi.rbox((57, cy - 2.0), 7.0, 11.4, M["steel"])                                                  # wylot
        hi.ellipse((60.5, cy - 2.0), 1.6, 4.0, M["dark"])
        hi.ellipse((30, cy + 6.6), 8.4, 4.6, M["steel_d"])                                              # bęben
        for k in range(5):
            hi.ellipse((24.6 + k * 2.8, cy + 7.4), 1.1, 1.6, M["brass"])                                 # pociski w bębnie
        hi.poly([(34, cy + 3.0), (39, cy + 3.0), (37.4, cy + 11.0), (32.6, cy + 10.2)], M["poly"])
        hi.poly([(10, cy - 5.6), (13, cy - 5.6), (12, cy - 8.2), (10.6, cy - 8.2)], M["steel_l"])
        hi.poly([(54, cy - 5.6), (56.4, cy - 5.6), (55.6, cy - 7.8)], M["steel_l"])
        hi.capsule((14, cy - 5.0), (52, cy - 5.0), 0.5, 0.5, M["olive_d"])
        glow_pts = [(26 + k * 2.8, cy + 6.8) for k in range(5)]
        gcol = (255, 210, 110)
    elif name == "sokol6":
        # wyrzutnia mikrorakiet: kontener, front z tubami i czubkami rakiet, czujnik naprowadzania
        hi.poly([(2, cy - 2), (9, cy - 2.4), (9, cy + 3), (4, cy + 6), (2, cy + 4)], M["poly"])
        hi.rbox((34, cy - 1.0), 46, 11.4, M["slate"])
        hi.rbox((34, cy - 5.0), 46, 3.0, M["slate_d"])
        for k in range(3):
            hi.capsule((18 + k * 12, cy - 6.6), (18 + k * 12, cy + 4.8), 0.6, 0.6, M["steel_d"])         # żebra kontenera
        for r_, c_ in ((0, -3.0), (1, 1.0), (2, 5.0)):                                                  # front: trzy rzędy tub
            hi.ellipse((56.4, cy + c_ - 1.2), 2.2, 1.9, M["dark"])
            hi.poly([(54.8, cy + c_ - 1.2), (58.4, cy + c_ - 1.2), (56.6, cy + c_ - 3.6)], M["red"]) if False else None
        for c_ in (-3.4, 0.6, 4.6):
            hi.ellipse((57.4, cy + c_ - 0.8), 2.0, 1.8, M["dark"])
            hi.ellipse((57.8, cy + c_ - 0.8), 1.1, 1.0, M["red"])                                       # czubek rakiety
        hi.rbox((21, cy - 7.0), 7.0, 3.0, M["steel"])                                                    # głowica naprowadzania
        hi.ellipse((24, cy - 7.0), 1.2, 1.2, M["red"])
        hi.poly([(26, cy + 5.0), (31, cy + 5.0), (29.6, cy + 12.0), (25.2, cy + 11.0)], M["poly"])
        hi.rbox((43, cy - 3.4), 9, 2.4, M["steel"])                                                      # panel wskaźników
        glow_pts = [(24, cy - 7), (41, cy - 3.6), (43, cy - 3.6), (57, cy - 3.6), (57, cy + 0.4), (57, cy + 4.4)]
        gcol = (255, 90, 70)
    elif name == "widmo1":
        # działo szynowe: dwie szyny, cewki (świecą), kondensator, jarzący się wylot
        hi.poly([(2, cy - 2), (10, cy - 2.8), (10, cy + 3), (4, cy + 6), (2, cy + 4)], M["poly"])
        hi.rbox((34, cy - 2.6), 50, 3.0, M["steel"])                                                    # górna szyna
        hi.rbox((34, cy + 1.2), 50, 3.0, M["steel_d"])                                                  # dolna szyna
        hi.rbox((34, cy - 0.7), 48, 1.4, M["dark"])                                                      # szczelina z łukiem
        for k in range(8):
            x = 14 + k * 5.0
            hi.rbox((x, cy - 0.7), 2.6, 9.6, M["steel_d"])                                               # cewki
            hi.rbox((x, cy - 0.7), 1.2, 8.0, M["cyan"])
        hi.rbox((20, cy + 7.0), 12, 4.0, M["poly"])                                                      # kondensator
        hi.rbox((20, cy + 7.0), 9, 1.4, M["cyan"])
        hi.rbox((59, cy - 0.7), 8.0, 7.4, M["steel"])                                                    # wylot
        hi.ellipse((62.6, cy - 0.7), 1.6, 2.6, M["cyan"])
        hi.poly([(30, cy + 3.8), (35, cy + 3.8), (33.4, cy + 11.4), (28.8, cy + 10.4)], M["poly"])
        glow_pts = [(14 + k * 5.0, cy - 0.7 + dy) for k in range(8) for dy in (-3, -1, 1, 3)] + [(62, cy - 1), (62, cy), (63, cy - 0.7), (20, cy + 7), (22, cy + 7), (17, cy + 7)]
    elif name == "ciegno6":
        # kusza: drewniane łoże, stalowe ramiona, napięta cięciwa, bełt z lotkami
        hi.poly([(2, cy - 2.4), (22, cy - 1.6), (22, cy + 3.6), (6, cy + 6.4), (2, cy + 4.4)], M["wood"])
        hi.rbox((36, cy + 0.6), 32, 5.0, M["wood"])                                                     # łoże
        for k in range(5):
            hi.capsule((24 + k * 3.8, cy - 1.0), (24 + k * 3.8, cy + 2.6), 0.3, 0.3, M["wood_d"])
        hi.capsule((26, cy - 2.4), (56, cy - 2.4), 0.9, 0.9, M["steel_l"])                              # bełt: wałek
        hi.poly([(54, cy - 3.8), (62, cy - 2.4), (54, cy - 1.0)], M["steel_l"])                          # grot
        for k in range(3):
            hi.poly([(26 + k * 1.6, cy - 2.4), (24 + k * 1.6, cy - 5.0), (28 + k * 1.6, cy - 2.4)], M["cord"])   # lotki
        hi.capsule((50, cy - 11), (50, cy - 2.4), 0.4, 0.4, M["cord"])                                   # cięciwa
        hi.capsule((50, cy + 6), (50, cy - 2.4), 0.4, 0.4, M["cord"])
        hi.capsule((46, cy - 0.8), (52, cy - 11.5), 1.4, 0.9, M["steel"])                                # ramiona (zagięte do przodu)
        hi.capsule((52, cy - 11.5), (56, cy - 12.6), 0.9, 0.5, M["steel_l"])
        hi.capsule((46, cy + 2.4), (52, cy + 8.4), 1.4, 0.9, M["steel"])
        hi.capsule((52, cy + 8.4), (56, cy + 9.2), 0.9, 0.5, M["steel_l"])
        hi.rbox((47, cy + 0.8), 5.0, 4.2, M["steel_d"])                                                  # nasada ramion
        hi.poly([(26, cy + 3.4), (30.4, cy + 3.4), (29.4, cy + 9.4), (25.4, cy + 8.6)], M["wood_d"])      # spust / język
        glow_pts = []
    elif name == "maczeta":
        # szeroka głownia z rowkiem i jasną krawędzią, jelec, owijana rękojeść
        hi.poly([(2, cy + 2), (3, cy - 2.6), (20, cy - 2.6), (20, cy + 2.8)], M["wood"])                 # rękojeść
        for k in range(5):
            hi.capsule((4 + k * 3.4, cy - 2.4), (6.4 + k * 3.4, cy + 2.6), 0.5, 0.5, M["cord"])           # owinięcie
        hi.rbox((21, cy), 3.2, 9.6, M["steel_d"])                                                         # jelec
        hi.poly([(23, cy - 4.2), (52, cy - 4.6), (62, cy - 0.4), (52, cy + 4.2), (23, cy + 3.8)], M["steel"])   # głownia
        hi.poly([(23, cy + 2.4), (52, cy + 2.8), (62, cy - 0.4), (52, cy + 4.2), (23, cy + 3.8)], M["steel_l"])  # fazowana krawędź
        hi.capsule((26, cy - 1.0), (54, cy - 1.0), 0.6, 0.5, M["steel_d"])                               # rowek
        hi.capsule((25, cy - 3.2), (50, cy - 3.4), 0.4, 0.4, M["steel_l"])
        for k in range(4):
            hi.ellipse((29 + k * 6.0, cy + 3.4), 0.5, 0.4, M["steel_d"])                                  # wyszczerbienia
        glow_pts = []
    elif name == "kilof":
        # długi trzonek ze słojami, głowica z dwoma dziobami zagiętymi ku trzonkowi
        hi.capsule((2, cy + 2.0), (52, cy + 2.0), 1.6, 1.6, M["wood"])
        for k in range(8):
            hi.capsule((6 + k * 5.4, cy + 1.2), (8.4 + k * 5.4, cy + 2.8), 0.3, 0.3, M["wood_d"])
        for k in range(4):
            hi.capsule((3 + k * 2.0, cy + 0.6), (4 + k * 2.0, cy + 3.6), 0.5, 0.5, M["cord"])
        hi.rbox((50, cy + 2.0), 5.0, 6.4, M["steel_d"])                                                   # oprawa głowicy
        hi.capsule((50, cy + 2.0), (50, cy - 2.0), 1.8, 1.8, M["steel"])
        hi.poly([(48, cy - 1.8), (53, cy - 1.8), (62, cy + 0.8), (60, cy + 1.6), (52, cy + 0.4), (44, cy + 1.6), (40, cy + 0.8)], M["steel"]) if False else None
        # dziób (szpic) w przód, dłuto w tył
        hi.poly([(48.4, cy - 3.8), (52.6, cy - 3.6), (62.4, cy + 2.0), (53.4, cy + 0.8), (49.0, cy + 0.6)], M["steel"])
        hi.poly([(47.8, cy - 3.8), (48.4, cy + 0.6), (41.0, cy + 3.4), (39.0, cy + 1.6), (44.0, cy - 2.6)], M["steel_l"])
        hi.capsule((49, cy - 3.2), (60, cy + 1.2), 0.45, 0.35, M["steel_l"])
        glow_pts = []
    if world:
        skin = hi.material(ramp((226, 174, 142), cool=(0.3, 0.2, 0.34)))
        Hi.ellipse(hi, HAND, 2.0 * WORLD_DENSITY, 1.8 * WORLD_DENSITY, skin)         # dłoń na chwycie (pivot obrotu)
        Hi.ellipse(hi, (HAND[0] + 1.0 * WORLD_DENSITY, HAND[1] - 0.8 * WORLD_DENSITY), 1.2 * WORLD_DENSITY, 0.8 * WORLD_DENSITY, skin)
    fr = _finish(hi, 0.3)
    if world:
        fr.outline(0.3)                                   # obrys 2 px arkusza = 1 px świata, jak u reszty sprite'ów
    glow_fr = Frame(fw, fh)
    _glow_dots(glow_fr, [hi._t(p) for p in glow_pts], gcol)
    return fr, glow_fr


def tip_x(fr, glow):
    """Skrajnie prawy niepusty piksel (ciało lub żar) — do sprawdzenia zgodności z gun_len."""
    best = -1
    for f in (fr, glow):
        for row in f.px:
            for x, p in enumerate(row):
                if p is not None and (len(p) < 4 or p[3] > 0):
                    best = max(best, x)
    return best


ICON_ANIMS = [(n, 1, 1, False) for n in NAMES]
