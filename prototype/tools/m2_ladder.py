# -*- coding: utf-8 -*-
"""Szkic układu 1.2 „Drabina" (MAPS_PLAN.md §4): trzy zejścia do tunelu drezyny w miejscach istniejących wysokich komór tunelu
i przepust pod dziedzińcem. Nic się nie przesuwa — same wykopy w litej skale i kilka przestawionych znaczników.
Uruchomienie: python m2_ladder.py <z1_m2.gd sprzed układu> <katalog wyjściowy> [--parts=ACB | --stage=1|2|3]
  --parts: A = przepust i studnia stacji (D1), C = magazyn za kratką (D2), B = zsyp w skrytce (D3); --stage=N to dawne etapy v1 (1: C, 2: CA, 3: CAB).
  Siatka wejściowa to z1_m2.gd sprzed wdrożenia (np. `git show 9ab0940e:prototype/scripts/maps/z1_m2.gd`) — generator sprawdza, że kopie w litej skale.
Wersja 2 (2026-11-10, po przeglądzie): zawał podestu studni przy nadawaniu (COLLAPSE), Wołek na środku watahy, rekwizyty ACCENTS z włazów,
Ćma 10 kolumn od wnęki."""
import re, sys, json, os

src_path, out_dir = sys.argv[1], sys.argv[2]
parts = 'CAB'
for a in sys.argv[3:]:
    if a.startswith('--stage='): parts = {1: 'C', 2: 'CA', 3: 'CAB'}[int(a.split('=')[1])]
    if a.startswith('--parts='): parts = a.split('=')[1].upper()
src = open(src_path, encoding='utf-8').read()
head, body = src[:src.index('const MAP := [')], src[src.index('const MAP := ['):]
rows = re.findall(r'^\t"([^"]*)",?$', body, re.M)
H, W = len(rows), len(rows[0])
assert (H, W) == (56, 288), (H, W)
g = [list(r) for r in rows]

def at(c, r): return g[r][c]
def put(c, r, ch, expect=None):
    if expect is not None: assert g[r][c] in expect, (c, r, g[r][c], expect)
    g[r][c] = ch
def carve(c0, c1, r0, r1):
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            assert g[r][c] in '#Cb', (c, r, g[r][c])
            g[r][c] = 'b'
def plat(c0, c1, r, ch='='):
    for c in range(c0, c1 + 1):
        assert g[r][c] in 'b#C.', (c, r, g[r][c])
        g[r][c] = ch
def move(ch, c0, r0, c1, r1, back='b'):
    assert g[r0][c0] == ch, (ch, c0, r0, g[r0][c0]); assert g[r1][c1] in 'b.', (c1, r1, g[r1][c1])
    g[r0][c0] = back; g[r1][c1] = ch

meta = {"parts": parts, "risers": []}

if "C" in parts:

    # --- etap 1: zejście wschodnie — magazyn za kratką `+` (kol. 215-220, w. 37-39) nad komorą 3 tunelu (kol. 200-216, w. 41-43)
    move('a', 216, 39, 217, 39)
    plat(215, 216, 40)                       # właz w podłodze magazynu
    plat(213, 216, 42); plat(213, 216, 44); plat(212, 215, 46); plat(209, 212, 48); plat(213, 215, 49)   # skok w górę wymaga wolnych 2 kafli nad celem: stopnie w. 42 i 44 pod włazem; stemple w kol. 208 i 216 zostają
    # Stopień w w. 49 (32 px nad torem) mieści się w handcar.aboard() (do 40 px nad pokładem) — stojący na nim jechałby z drezyną.
    # Wyżej się nie da: bez w. 49 graf nie wchodzi z toru na schody (sprawdzone w v2). Poprawka w kodzie: handcar.aboard() (MAPS_PLAN.md §4, zasada 4).
    move('J', 208, 50, 202, 50, back='w'); move('Z', 214, 50, 207, 50)   # Skoczek stał na stopie stempla kol. 208 — stempel zostaje do toru      # wiszące pod stropem komory: poza schodami; v2: Ćma w kol. 207, 10 kol. od wnęki 195-197 (zasada 4)
    meta["risers"].append({"name": "C", "top": [218, 39], "bottom": [206, 50], "barrier": "+"})

if "A" in parts:
    # --- etap 2: przepust pod dziedzińcem + studnia stacji pod rusztowaniem (kol. 60-65) nad komorą 1 (kol. 60-78, w. 41-43)
    move('a', 40, 25, 33, 25, back='.')
    move('T', 44, 25, 52, 25, back='.')  # wataha dalej od włazu
    # v2: Wołek z kol. 58 (2 kol. od włazu studni — wake_near 70 px liczone w linii prostej przez skałę, kucając 35) na środek watahy,
    # nad przepustem (64 px w pionie): przejście ciche tylko na kucaka, wyjście ze studni 11 kol. od niego. Najbliższy Trzosek przy studni
    # (kol. 52) jest 8 kol. od włazu (128 px > 112 px wake_near na HARD), przy wejściu (kol. 46) 4 kol. od włazu przepustu (64 px > 56 kucając na HARD).
    move('W', 58, 25, 49, 25, back='.')
    plat(39, 42, 26, '-')                # właz przepustu równo z gruntem
    carve(39, 42, 27, 29); plat(39, 40, 28, '-')
    carve(43, 59, 28, 29)                # przepust: 2 kafle wysokości, 17 kolumn
    plat(60, 65, 26, '-')                # właz studni przy drzwiach stacji
    carve(60, 65, 27, 38)
    plat(62, 65, 28); plat(60, 63, 30); plat(62, 65, 32); plat(60, 63, 34); plat(62, 65, 36); plat(60, 63, 38)
    carve(66, 66, 36, 38); put(66, 38, '%')                   # zejście zabite deskami
    carve(67, 70, 36, 40); plat(67, 70, 39)                   # podest kablowy nad komorą
    plat(67, 70, 41); plat(69, 72, 43); plat(67, 70, 45); plat(68, 71, 49)   # w. 47 (kol. 62-71) już jest; stemple w kol. 64 i 72 zostają
    # v2: zawał przy nadawaniu — podest kablowy (kol. 67-70, w. 36-40) zasypuje się FINALE_DELAY s po ostatnim generatorze, żeby po nadawaniu
    # do wyjścia E dało się dojść tylko torem (drezyną). Deski w kol. 66 zostają poza obszarem (collapse nie usuwa przegród) — za nimi skała.
    meta["collapse"] = [[67, 36, 70, 40]]
    head = head.replace('const UNDERGROUND_ROW := 30\n', 'const UNDERGROUND_ROW := 30\n## Zawał przy nadawaniu (MAPS_PLAN.md §4): podest między studnią stacji a tunelem drezyny — po nadawaniu do wyjścia tylko torem.\nconst COLLAPSE := [[67, 36, 70, 40]]\n', 1)
    # v2: rekwizyty Poly Haven z włazów (x=648 → kol. 40 na włazie przepustu, x=968 → kol. 60 na włazie studni)
    assert 'Vector2(648, 416)' in head and 'Vector2(968, 416)' in head
    head = head.replace('Vector2(648, 416)', 'Vector2(584, 416)', 1).replace('Vector2(968, 416)', 'Vector2(920, 416)', 1)
    # płotki przy starcie (akcent 6, model `fence`) zdjęte na prośbę użytkownika 2026-11-10
    head = head.replace('[Vector2(152, 416), 6], [Vector2(184, 416), 6], ', '', 1)
    move('L', 76, 50, 92, 50)            # Ślepiec dalej od studni
    move('J', 70, 50, 76, 50)
    meta["risers"].append({"name": "A", "top": [62, 25], "bottom": [66, 50], "barrier": "%"})
    meta["culvert"] = {"in": [40, 25], "out": [62, 25]}

if "B" in parts:
    # --- etap 3: zsyp w skrytce za murem `q` (kol. 143-149, w. 37-39) nad komorą 2 (kol. 130-150, w. 41-43)
    move('u', 145, 39, 144, 39)
    plat(145, 146, 40)                   # właz; kol. 143-144 zostają gruntem — tam stoi znak strefy wydobycia (--maptest: wejście strefy)
    plat(145, 148, 42); plat(143, 146, 44); plat(139, 142, 45); plat(139, 142, 49)   # w. 47 (kol. 137-143) już jest; stemple w kol. 136 i 144 zostają
    move('J', 144, 50, 132, 50)
    meta["risers"].append({"name": "B", "top": [147, 39], "bottom": [136, 50], "barrier": "q"})

out_rows = [''.join(r) for r in g]
assert all(len(r) == W for r in out_rows)
changed = sum(a != b for ra, rb in zip(rows, out_rows) for a, b in zip(ra, rb))
meta["changed_cells"] = changed
name = 'z1_m2_ladder_' + ''.join(sorted(parts))
json.dump({"rows": out_rows, "meta": meta}, open(os.path.join(out_dir, name + '.json'), 'w'))
new_body = body
for a, b in zip(rows, out_rows):
    if a != b: new_body = new_body.replace('\t"%s"' % a, '\t"%s"' % b, 1)
open(os.path.join(out_dir, name + '_draft.gd'), 'w', encoding='utf-8', newline='\n').write(head + new_body)
print(name, 'zmienionych kafli:', changed)
