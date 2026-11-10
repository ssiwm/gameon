# Układ kryjówki „dwa pokłady” — plan wdrożenia

Analiza i projekt z 2026-11-09 (raport z przekrojami, zrzutami i modelem tras: prywatny artefakt, skrypty w `C:\deadair87\hub_layout`).
GDD §16.0a: gdy gracze gubią się w Kryjówce, upraszczamy układ i nie dokładamy stanowisk. Ten plan niczego nie dokłada, tylko przestawia.

## Problem (stan do 1.7.531, stary `z1_hub.gd`)

- Trzy poziomy po 7 kafli światła (9,2 m), podczas gdy budynki na misjach mają 4 kafle (5,2 m). Postać zajmuje 11% wysokości kadru.
- 184 kafle podłogi na 17 punktów z interakcją. Góra ma 50 kafli i dwa stanowiska, a odstępy między lampami sięgają 28 kafli.
- Kadr NORMAL ma 11,25 kafla wysokości, a piętro 8, więc z żadnego piętra nie widać pozostałych.
- Łańcuchy stanowisk są rozrzucone: pracownia (góra) → tokarka (dół) → ława (środek) to 35 s biegu, a strzelnica leży piętro niżej, 34 kafle od ławy.
- Stół konserwacji jest domyślnie martwy (zużycie wyłączone), a pracownia i tokarka otwierają się dopiero z postępem.
- Słupy przekroju stoją co 5 m, więc w kadrze są około czterech czarnych pasów.

## Projekt

Dwie kondygnacje po 4 kafle światła i 1 kafel stropu, jeden pion pośrodku, 53 × 20 kafli:

| Parter (wiersz podłogi 9) | Piwnica (wiersz podłogi 14) |
|---|---|
| śluza: start S, szafki p | kwatery: skrytka H, ściana wyników v |
| warsztat: konserwacja j, ława h | pracownia c, tokarka d (pod ławą) |
| pion (kol. 21–26): krata i podesty | pion |
| drzwi strzelnicy, zbrojownia (a, g, g, a) | prasa x, pirotechnika z (pod zbrojownią) |
| radiostacja R z oknem prognozy, odprawa n, strefa startu | maszynownia: generator, sprężarka, D-7, skrytka H |

Kamera trzyma oba pokłady w kadrze (`CAM_LOCK`). Pas od stropu do podłogi piwnicy to 11 wierszy, a kadr NORMAL ma 11,25 kafla.

Model tras (`hub_layout.py`: bieg 95 px/s, szacowany czas zmiany piętra), obecny układ kontra projekt:

| Trasa | Obecny | Projekt |
|---|---|---|
| Start → strefa wyjścia | 9,8 s | 7,2 s |
| Ława → strzelnica | 15,8 s | 7,2 s |
| Pracownia → tokarka → ława | 35,2 s | 15,5 s |
| Pełny obchód 17 punktów | 38,6 s | 26,9 s |

## Etapy

| Etap | Zakres | Stan |
|---|---|---|
| E0 | Dziennik kryjówki: `hub_enter`, `hub_pos` co 1 s, `hub_station`; sekcja „Kryjówka — ruch” w `session_progress.py` | PR #637 |
| E1 | Spike pod flagą `--hub2`: mapa `z1_hub2.gd`, kamera trzymana w pionie (`CAM_LOCK`), słupy na granicach pomieszczeń (`"bays"`), zrzuty | bramka przyjęta 2026-11-09 |
| E2 | Układ w grze: nowy `z1_hub.gd` (flaga `--hub2` i `z1_hub2.gd` usunięte), test bryły kryjówki (2 kondygnacje, słupy tylko w `bays`), README, GDD §10.3 | 1.7.532 |
| E3 | Kamera przekroju: oko kamery 3D z danych mapy (`EYE_UP` 3,4 m zamiast 2,2 m), granice pasa w `section_camera.gd` (bez drgania o 1 px przy WIDE), przy CLOSE kamera za graczem w obrębie pasa, test `test_hub_camera.gd` | 1.7.533 |
| E4 | Czytelność: tabliczki stanowisk, barwa światła pomieszczeń, uśpione stanowiska ciemne do pierwszego użycia, ściana wyników ×0,7 | 1.7.534 |
| E5 | Kwatery i meble stawiane ręcznie zamiast losowych z `hub_decor.gd`, właz pionu, wnęki | 1.7.535 |
| E6 | Ocena po playteście z danych E0 | |

## Decyzje (przyjęte rekomendacje planu)

1. Dwa pokłady, nie trzy zwarte: przy trzech droga do radia rośnie do 22 s.
2. Kamera zablokowana w pionie: przy NORMAL i WIDE widać oba pokłady, przy CLOSE kamera idzie za graczem w obrębie pasa.
3. Ściana wyników w kwaterach, w E4 pomniejszona do 0,7.
4. Radio przy odprawie, a nie na osobnym piętrze.

## Uwagi z E1 i E2

- Od E2 wszystkie testy kryjówki (`--maptest`, `test_front.gd` z `_check_vault`, `--workshoptest`, gabloty, `--rangetest`, `--nobottest`, bronie) sprawdzają nowy układ.
- E3: przy oku 2,2 m nad środkiem kadru (środek pasa wypada na stropie między pokładami) oko stało 1,5 m nad podłogą parteru, więc podłoga była kreską. Zrzuty przy 2,2 / 3,4 / 4,6 m: przy 3,4 m parter czyta się jak pokład, przy 4,6 m piwnica się spłaszcza. Dev `--eyeup=M` do porównań. Okno 21:9 i 16:10 nie zmienia kadru (rozciąganie „keep”, pasy po bokach).
- Do decyzji w E4: krata pionu na parterze czyta się w przekroju jak dziura w stropie; słup przekroju w płaszczyźnie z = SHELL_Z jest czarny i stoi przed całą wysokością obu pokładów.
- E4: krata pionu przedłużona w głąb do przodu płyty (tylko w wierszach płyt przekroju, nie na podestach), słup przekroju zdjęty flagą `"cut_cols": false`. Tabliczki na 2,9 m nad podłogą — przy 3,55 m piwnica chowała je za podciągami. „RELOADING PRESS” po polsku („PRASA ELABORACYJNA”) miała 4,2 m, więc tabliczka mówi „AMMO PRESS” / „PRASA AMUNICJI”. Lampa sufitowa doszła w piwnicy w kol. 19 (odstępy ≤ 10 kafli). Zrzuty świeżego profilu (uśpione stanowiska) i profilu QA w `C:\deadair87\shots_hub4`.
- E5: meble z `HUB_PROPS` (`hub_prop.gd FURNITURE`), `hub_decor.gd` i `SHAFTS` usunięte. Kwatery: piecyk, skrytka, dwie prycze piętrowe, stół ze stołkami pod tablicą wyników. Tablica przy 0,7 miała 5,7 m i zasłaniała tabliczkę KWATERY — teraz 0,4 (3,8 × 2,2 m) i wisi nad stołem (`LIFT_PX`); decyzja 3 (tablica w kwaterach) bez zmian. Właz z drabinką od 2,4 m w kol. 25, kanał kablowy do radiostacji (kol. 42, za biurkiem). Wnęki: korytarz z lampami w koszach w pionie czytał się jak czarna dziura, więc jest schowek za kratą (`grate`); kratki wentylacji w warsztacie i maszynowni. Grafiti wchodziło na drabinkę i obok tabliczek — `NO_DECALS` i pas za tabliczkami. Nowe modele niepotrzebne (cot, barrel_stove, table, stool, chair, shelf_b już były), więc bez `tex_vram.py`. Zrzuty `e5*` w `C:\deadair87\shots_hub4`.
