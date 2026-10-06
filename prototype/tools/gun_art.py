"""Pixel-art 12 broni Dead Air '87 (arkusz art/sprites/guns.png, klatka 24×9).

Każda broń to siatka znaków 24×9 (wiersz = y, kolumna = x), rysowana „ręcznie” piksel po pikselu,
żeby miała pełną kontrolę nad światłem: źródło z lewej-góry, rampa 4–5 tonów na materiał (jasny
połysk → światło → ton → cień → głęboki cień, z przesunięciem w chłodne cienie), detale (szczerbinki,
żebra, nity, wentylacje). Obrys 1 px dokłada `sheet()` z bake_sprites.py — spójny z graczem i wrogami.

Konwencje, od których zależy reszta gry (nie ruszać bez zmiany `weapons.gd`):
  * dłoń (pivot obrotu w grze) = (4, 4); 2×2 piksele dłoni są w siatce (h/H) na x=3..4, y=3..4,
  * lufa w stronę +x; ostatni piksel lufy = 3 + gun_len (wylot = x dłoni + gun_len),
  * zawartość mieści się w x ≤ 22 i y ∈ [1, 7] — obrys potrzebuje 1 px wokół.

Znaki: patrz LEGEND. Znak z drugim kolorem (glow) trafia też do guns_glow.png — warstwy unshaded,
która świeci w ciemności (taśma energii LR-7, cewki SPECTER-1, płomień pilota HKM-9 …).
"""

W, H = 24, 9
HAND = (4, 4)

# nazwa → x ostatniego piksela lufy = 3 + gun_len z weapons.gd (wylot = HAND.x + gun_len)
MUZZLE_X = {
    "m83": 15, "spread12": 17, "p64": 12, "srut8": 18, "lr7": 16, "hkm9": 17,
    "gniew4": 17, "sokol6": 16, "widmo1": 19, "ciegno6": 16, "maczeta": 15, "kilof": 16,
}


def _rgb(r, g, b):
    return (int(r * 255), int(g * 255), int(b * 255), 255)


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def ramp(base, warm=(1.0, 0.97, 0.88), spread=1.0):
    """5 tonów: połysk, światło, ton, cień, głęboki cień (cienie chłodniejsze, światła cieplejsze)."""
    b = _rgb(*base)
    hi = _mix(b, _rgb(*warm), min(0.85, 0.70 * spread))
    lt = _mix(b, _rgb(*warm), 0.32 * spread)
    sh = (int(b[0] * 0.66), int(b[1] * 0.69), int(b[2] * 0.82), 255)
    dk = (int(b[0] * 0.38), int(b[1] * 0.41), int(b[2] * 0.56), 255)
    return hi, lt, b, sh, dk


STEEL = ramp((0.60, 0.62, 0.68))
POLY = ramp((0.27, 0.28, 0.33))
WOOD = ramp((0.47, 0.30, 0.16))
OLIVE = ramp((0.29, 0.34, 0.22))
RED = ramp((0.66, 0.20, 0.16))
SLATE = ramp((0.34, 0.40, 0.50))
BRASS = ramp((0.82, 0.62, 0.24))
CORD = ramp((0.80, 0.76, 0.64))
SKIN = ramp((0.86, 0.68, 0.54))

# znak → (kolor korpusu, kolor warstwy świecącej | None)
LEGEND = {
    ".": (None, None),
    # stal
    "W": (STEEL[0], None), "w": (STEEL[1], None), "m": (STEEL[2], None), "s": (STEEL[3], None), "d": (STEEL[4], None),
    # czarny polimer
    "P": (POLY[1], None), "p": (POLY[2], None), "q": (POLY[4], None), "k": (POLY[3], None),
    # drewno
    "U": (WOOD[0], None), "T": (WOOD[1], None), "t": (WOOD[2], None), "u": (WOOD[3], None), "v": (WOOD[4], None),
    # oliwka (granatnik)
    "O": (OLIVE[1], None), "o": (OLIVE[2], None), "n": (OLIVE[3], None), "N": (OLIVE[4], None),
    # czerwony lakier (zbiornik)
    "R": (RED[1], None), "r": (RED[2], None), "g": (RED[3], None), "G": (RED[4], None),
    # łupek (kontener rakiet)
    "B": (SLATE[1], None), "M": (SLATE[2], None), "L": (SLATE[3], None), "l": (SLATE[4], None),
    # mosiądz
    "Y": (BRASS[1], None), "y": (BRASS[2], None), "z": (BRASS[3], None),
    # sznur / cięciwa
    "F": (CORD[1], None), "f": (CORD[3], None),
    # ostrze (krawędź)
    "x": (_rgb(0.96, 0.97, 1.0), None),
    # energia: ciało (ciemny odcień, widać w świetle) + glow (jasny, widać w ciemności)
    "C": (_rgb(0.55, 0.90, 1.0), _rgb(0.80, 0.98, 1.0)),
    "c": (_rgb(0.25, 0.65, 0.85), _rgb(0.35, 0.82, 1.0)),
    "b": (_rgb(0.10, 0.30, 0.45), _rgb(0.14, 0.50, 0.78)),
    # żar / płomień pilota / dioda
    "E": (_rgb(1.0, 0.78, 0.40), _rgb(1.0, 0.82, 0.45)),
    "e": (_rgb(0.95, 0.46, 0.14), _rgb(1.0, 0.52, 0.16)),
    "D": (_rgb(0.85, 0.20, 0.12), _rgb(1.0, 0.25, 0.14)),
    # dłoń
    "h": (SKIN[1], None), "H": (SKIN[3], None),
}

# ---------------------------------------------------------------------------------------------
# Rysowanie: zamiast ręcznie liczonych 24-znakowych wierszy broń składa się z pociągnięć
#   h(x, y, "znaki")  — poziomo od (x, y)        v(x, y, "znaki")  — pionowo od (x, y)
#   r(x, y, w, h, c)  — prostokąt jednym znakiem
# Późniejsze pociągnięcia nadpisują wcześniejsze; dłoń (h/H na 3..4 × 3..4) jest dokładana na końcu.

def h(x, y, s):
    return ("h", x, y, s)


def v(x, y, s):
    return ("v", x, y, s)


def r(x, y, w, hh, c):
    return ("r", x, y, w, hh, c)


def build(strokes, hand=True):
    g = [["."] * W for _ in range(H)]

    def put(x, y, ch):
        if 0 <= x < W and 0 <= y < H:
            g[y][x] = ch

    for st in strokes:
        if st[0] == "h":
            for i, ch in enumerate(st[3]):
                if ch != " ":
                    put(st[1] + i, st[2], ch)
        elif st[0] == "v":
            for i, ch in enumerate(st[3]):
                if ch != " ":
                    put(st[1], st[2] + i, ch)
        else:
            for yy in range(st[4]):
                for xx in range(st[3]):
                    put(st[1] + xx, st[2] + yy, st[5])
    if hand:
        put(3, 3, "h"); put(4, 3, "h"); put(3, 4, "H"); put(4, 4, "H")
    return ["".join(row) for row in g]


STROKES = {}
ARTS = {}


def _gun(name, *strokes, hand=True):
    STROKES[name] = strokes
    ARTS[name] = build(strokes, hand)


# ---------------------------------------------------------------------------------------------
# M-83 — pistolet maszynowy: szkieletowa kolba, szyna z szczerbinką, wygięty magazynek
_gun("m83",
     h(1, 2, "wm"), h(1, 3, "d"), h(1, 4, "ms"),                         # szkieletowa kolba
     h(5, 1, "dmdmdmdm"), h(13, 1, "d"),                                 # szyna + muszka
     h(3, 2, "WwwwWwwwwwwwW"),                                           # górna płaszczyzna
     h(5, 3, "mmmddm"), h(11, 3, "msssd"),                               # komora z oknem wyrzutu, łoże
     h(5, 4, "ssssss"), h(11, 4, "dddd"),
     r(7, 5, 3, 2, "p"), v(7, 5, "PP"), v(9, 5, "qq"), h(8, 7, "pq"),    # magazynek
     v(3, 5, "pp"), v(4, 5, "qq"), h(2, 7, "pp"),                        # chwyt
     h(5, 5, "dd"))

# SPREAD-12 — półautomatyczna strzelba: drewniana kolba i łoże, żebro nad lufą, muszka
_gun("spread12",
     v(1, 2, "kkkk"), h(2, 2, "UT"), v(2, 3, "Tt"), h(2, 5, "tut"),      # kolba z gumowym kapslem
     h(10, 1, "mwmwmwm"), h(17, 1, "d"),                                 # żebro + muszka
     h(4, 2, "WwwwWwwwwwwwwW"),                                          # komora + lufa
     h(5, 3, "mmYdm"), h(10, 3, "mmmmmmms"), h(17, 3, "d"),
     h(5, 4, "sdddd"),
     h(10, 4, "TTtTtT"), h(10, 5, "tttttu"), h(16, 4, "d"),              # łoże
     v(14, 2, "ds"), h(5, 5, "dd"))

# P-64 — pistolet: zamek z nacięciami, krótka lufa, pochylony chwyt, kabłąk
_gun("p64",
     h(5, 1, "d"), h(11, 1, "d"),
     h(4, 2, "WwwwwwwwW"),
     h(5, 3, "msmsmmsd"),
     h(5, 4, "sssssdd"),
     h(4, 5, "Ppp"), h(4, 6, "Ppq"), h(3, 7, "Ppq"),
     h(7, 5, "d"), h(8, 4, "d"))

# PELLET-8 — ciężka strzelba pompka: wentylowana osłona, rura magazynka, pompka, hamulec wylotowy
_gun("srut8",
     v(1, 2, "kkkk"), h(2, 2, "UT"), v(2, 3, "Tt"), h(2, 5, "tut"),
     h(10, 1, "mdmdmdmd"),
     h(4, 2, "W" + "w" * 14),
     h(5, 3, "mmYdm"), h(10, 3, "mmmmmmmm"),
     h(5, 4, "sdddd"),
     r(16, 1, 3, 3, "d"), h(16, 1, "sd"), h(16, 2, "m"),                 # hamulec wylotowy
     h(9, 4, "TtTtTt"), h(9, 5, "tttttu"), h(10, 6, "uuuuv"),            # pompka
     h(17, 4, "d"), h(5, 5, "dd"))

# LR-7 — działo energetyczne: radiator z żebrami, taśma energii (świeci), emiter z soczewką
_gun("lr7",
     h(1, 3, "md"),
     h(5, 1, "mdmdmdm"),
     h(3, 2, "PPpPPPpPPP"),
     h(5, 3, "bcCcCcb"), h(12, 3, "p"),
     h(5, 4, "ppppppp"),
     h(13, 2, "WwwW"), h(13, 3, "msdC"), h(13, 4, "ddd"),
     r(5, 5, 4, 2, "p"), h(5, 5, "Pc"), h(5, 6, "Pp"),
     v(3, 5, "pq"))

# HKM-9 — miotacz ognia: czerwony zbiornik z pasem ostrzegawczym, wąż, rura z osłoną, pilot
_gun("hkm9",
     h(2, 4, "rr"), h(1, 5, "RRRrr"), h(1, 6, "RyyyG"), h(2, 7, "ggG"),   # zbiornik
     h(5, 5, "dd"), h(6, 4, "dd"),
     h(4, 2, "WwwwW"), h(5, 3, "mmmm"), h(9, 2, "wwwwwwww"), h(9, 3, "msssssss"),
     h(10, 1, "dmdmdm"), h(9, 4, "dddd"), h(11, 2, "d"), h(13, 2, "d"),
     r(16, 1, 2, 4, "d"), h(16, 1, "s"),
     h(18, 3, "E"), h(17, 3, "e"),
     h(8, 4, "D"))

# WRATH-4 — granatnik: oliwkowa tuba z obręczami, bęben z mosiężnymi pociskami, szczerbinki
_gun("gniew4",
     h(1, 2, "pp"), h(1, 3, "pq"),
     h(6, 1, "d"), h(14, 1, "d"),
     h(3, 2, "OOOOOOOOOOOOO"), h(3, 3, "oooooooooooo"), h(3, 4, "oooooooooooo"), h(3, 5, "nnnnnnnnnnnn"),
     v(7, 2, "WmmN"), v(11, 2, "WmmN"),
     r(16, 2, 2, 4, "m"), v(16, 2, "WmmN"), v(17, 2, "wsdd"),
     h(6, 6, "mYyYyYm"), h(6, 7, "ddddddd"),
     v(3, 6, "pp"), v(4, 6, "qq"))

# FALCON-6 — wyrzutnia mikrorakiet: kontener, front z tubami i czubkami rakiet, czujnik naprowadzania
_gun("sokol6",
     h(5, 1, "dD"),
     h(2, 2, "BBBBBBBBBBBBB"), h(2, 3, "MMMMMMMMMMMMM"), h(2, 4, "MMMMMMMMMMMMM"), h(2, 5, "LLLLLLLLLLLLL"),
     v(7, 2, "llll"), h(9, 3, "yy"), h(9, 4, "yy"), h(12, 2, "w"),
     r(15, 2, 2, 4, "m"), h(15, 2, "wd"), h(15, 3, "mD"), h(15, 4, "md"), h(15, 5, "sD"),
     v(1, 3, "ll"),
     v(3, 6, "pp"), v(4, 6, "qq"))

# SPECTER-1 — działo szynowe: dwie szyny, cewki (świecą), kondensator z diodą, jarzący się wylot
_gun("widmo1",
     r(1, 2, 2, 3, "p"), v(1, 2, "PPp"),
     h(3, 2, "WwwwwwwwwwwwwwwW"),
     h(5, 3, "dcdCdcdCdcdCdcC"),
     h(5, 4, "mssssssssssssss"),
     v(8, 1, "c"), v(11, 1, "c"), v(14, 1, "c"), v(17, 1, "c"),
     v(8, 5, "b"), v(11, 5, "b"), v(14, 5, "b"), v(17, 5, "b"),
     h(5, 5, "Pp"), h(5, 6, "pP"),
     v(3, 5, "pq"))

# CIĘGNO-6 — kusza: drewniane łoże, stalowe ramiona zagięte do przodu, napięta cięciwa, bełt z lotkami
_gun("ciegno6",
     r(1, 3, 2, 4, "T"), h(1, 3, "UT"), h(1, 4, "Tt"), h(1, 5, "tt"), h(1, 6, "ut"),   # kolba
     h(3, 4, "TTTTTTTTTT"), h(3, 5, "ttttttttttu"), h(5, 6, "d"),                      # łoże + język spustu
     h(9, 3, "FfwwwwWW"),                                                              # bełt: lotki, wałek, grot
     v(10, 1, "fFFfFFf"),                                                              # cięciwa
     h(11, 1, "f"), h(11, 7, "f"),
     v(12, 2, "wmmmm"), v(13, 2, "dddddd"), h(12, 1, "wd"), h(12, 7, "wd"),   # ramiona
     v(12, 3, "WmM"), h(13, 4, "s"))                                                   # nasada ramion

# MACZETA — szeroka głownia z rowkiem i jasną krawędzią, jelec, owijana rękojeść
_gun("maczeta",
     v(1, 3, "Uu"), h(2, 3, "TF"), h(2, 4, "tf"), h(5, 3, "F"), h(5, 4, "f"),
     v(6, 1, "smmmd"),
     h(7, 2, "mWwwwwwwm"),
     h(7, 3, "wwsssssswW"),
     h(7, 4, "xwwwwwwwx"), h(8, 5, "xxxxxxx"), h(14, 4, "xx"))

# KILOF — długi trzonek ze słojami i owinięciem, głowica z dwoma dziobami zagiętymi ku trzonkowi
_gun("kilof",
     h(1, 3, "UTTtTTTTtTTTT"), h(1, 4, "ttutttttutttt"),
     h(5, 3, "F"), h(5, 4, "f"), h(6, 3, "F"), h(6, 4, "f"), v(1, 3, "vv"),
     h(12, 1, "xW"), h(13, 2, "wW"), h(14, 3, "wm"), h(14, 4, "wms"),     # dziób (szpic)
     h(14, 5, "mm"), h(13, 6, "mw"), h(12, 7, "ww"),                      # dziób (dłuto)
     v(14, 3, "W"), v(15, 3, "m"), v(15, 4, "s"), h(16, 4, "d"), v(13, 3, "ss"))

def problems():
    """Lista usterek siatek: wymiary, znaki, dłoń 2×2 na (3..4, 3..4), wylot lufy zgodny z weapons.gd."""
    out = []
    for name, rows in ARTS.items():
        if len(rows) != H:
            out.append("%s: %d wierszy zamiast %d" % (name, len(rows), H))
            continue
        bad = False
        for y, row in enumerate(rows):
            if len(row) != W:
                out.append("%s y=%d: %d znaków zamiast %d" % (name, y, len(row), W))
                bad = True
            for ch in row:
                if ch not in LEGEND:
                    out.append("%s y=%d: nieznany znak %r" % (name, y, ch))
                    bad = True
        if bad:
            continue
        for y in (3, 4):
            for x in (3, 4):
                if rows[y][x] not in "hH":
                    out.append("%s: brak dłoni w (%d,%d)" % (name, x, y))
        right = max(x for row in rows for x, ch in enumerate(row) if ch != ".")
        if right > 22:
            out.append("%s: zawartość do x=%d (obrys potrzebuje x ≤ 22)" % (name, right))
        if not MUZZLE_X[name] <= right <= MUZZLE_X[name] + 1:
            out.append("%s: skrajny piksel x=%d, a gun_len wymaga lufy do x=%d (+1 na płomień/szpic)" % (name, right, MUZZLE_X[name]))
        if any(ch != "." for ch in rows[0]) or any(ch != "." for ch in rows[H - 1]):
            out.append("%s: pierwszy i ostatni wiersz mają być puste (miejsce na obrys)" % name)
    return out


def check():
    errs = problems()
    assert not errs, "gun_art:\n  " + "\n  ".join(errs)
