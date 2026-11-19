# Plan: jeden styl podziemi (przekrój i pierwszy plan pod ziemią)

Status: **decyzje D1–D5 przyjęte 2026-11-19 zgodnie z rekomendacjami; U0–U4 niezaczęte.** Etap po przeglądzie spójności wizualnej z 2026-11-19 (61 zrzutów wszystkich map,
`C:\deadair87\shots_visrev`, arkusze `L1.jpg`–`L3.jpg`, `A_m2.jpg`, `B_m3.jpg`). Stan odniesienia: `main` 1.7.620 (73a60c19).

## Werdykt

Gra ma dziś dwa sposoby budowania kadru pod ziemią:

| Styl | Gdzie | Jak wygląda |
|---|---|---|
| **Przekrój** (FOREGROUND_PLAN.md F2b–F3) | tunel drezyny 1.2, podziemia 1.3 (sale i tunele), hala B1, kryjówka | strop i podłoga sięgają do `SHELL_Z` 5,6 m przed płaszczyzną gry, ściany końców sal też, na płycie rury, kable i lampy (`front3d.gd`) — korytarz ma głębię i ruch planów |
| **Płaski przekrój** | cała kopalnia 1.1 (galeria wiersze 31–33 na 200 kolumnach, sala nad nią, dolna galeria), dolna hala i szyby 1.2 | bryła gruntu kończy się na `DEPTH_FRONT` 1,1 m prostą linią, przed nią nic — kadr wygląda jak przekrój mrowiska |

Gracz przechodzi między stylami w obrębie jednej misji: w 1.2 z tunelu drezyny (przekrój) szybem do dolnej hali (płasko), w 1.3
z posterunku (przekrój) do podziemi (przekrój), ale w 1.1 całe podziemie jest płaskie. 2026-11-09 przy F3 uznano to za spójne
(„sama skała, wygląda spójnie”), ale wtedy płaski był też B1. Od 1.7.612 (#733, hala B1 jako bunkier w skale) wyjątkami zostały
już tylko 1.1 i środek 1.2 — w porównaniu wszystkich map odstają one jako jedyne.

Drugi problem wychodzi przy okazji: przekrój skały (`shell_cells` z kluczem „”, ściany `#` w `Front3D.WALL_TEX`) ma materiał `terrain`
(proceduralny, z widocznym rastrem kamyków, kadr `m1_c130_L`). Nawis i jaskinia 1.1 (#738–#741) dostały już `Level3D.rock_material()`
(skała `dig_rock` w dwóch skalach bez kratki). Duży przekrój w kopalni 1.1 w materiale `terrain` pogłębiłby łataninę z przeglądu (punkt 2).

## Zasady

1. **Ten sam mechanizm, nowe dane.** Podziemia 1.1 i 1.2 dostają wpisy `FRONT` z `"shell": true` jak podziemia 1.3: osobny wpis na salę
   (wysoki pas) i na tunel (niski pas), bo jeden wpis z różną wysokością stropu daje „balkon” (lekcja z 1.3). Nadproża między wpisami,
   ściany końców, otwory szybów w stropie i podłodze (`SHELL_CH` nie obejmuje `b`, `-`, `=`) robi istniejący kod `Level3D.set_shells`.
2. **Bez zmian w symulacji.** Mapa ASCII, kolizja, nawigacja, wzrok i dźwięk bez zmian (wyjątek: decyzja D4, czysto wizualna zamiana znaków).
3. **Nic nie wchodzi w pas gry.** Płyty tylko w wierszu stropu i podłogi z fundamentem, ściany na `LAYER_WALL` z wygaszaniem przy sylwetkach,
   elementy pierwszego planu poza wejściami stref wydobycia (`Front3D.dig_blocks`) — wszystko to sprawdza już `tools/test_front.gd`.
4. **Ciemność bez zmian (GDD §8.3).** Lampy elementów świecą tylko na `LAYER_FRONT`; płyty przekroju nie dostają własnego światła.
5. **Koszt ≤ 0,3 ms GPU na kadr** przy HIGH 4K (tunel 1.2 po scaleniu płyt: +0,2 ms w VpActors). Mierzyć naprzemiennie z wpisem i bez
   (zegar GPU pływa ok. 0,5 ms w godzinę — lekcja z DEPTH_PLAN.md N4).

## Decyzje (przyjęte 2026-11-19)

| # | Pytanie | Przyjęte |
|---|---|---|
| D1 | Zestaw elementów pierwszego planu w kopalni 1.1: istniejący `tunnel` (rury, kable, lampy) czy nowy `mine` (stemple drewniane, lutnia wentylacyjna, kabel, lampa górnicza)? | **`tunnel` w U1** (zero nowych assetów, od razu ten sam styl co 1.3), `mine` jako osobny etap U4 po ocenie w grze |
| D2 | Materiał przekroju skały pod ziemią: `terrain` jak dziś w 1.3 czy `rock_material()` jak nawis i jaskinia 1.1? | **`rock_material()` na wszystkich mapach** (także 1.3 i tunel 1.2): jedna skała w całej grze, bez rastru kamyków; zmiana w `shell_cells` i `Front3D.WALL_TEX["#"]` |
| D3 | Rampa w strefie zawału 1.1 (kolumny 216–253, wiersze 23–33, `COLLAPSE`): przekrój czy płasko? | **Płasko w U1** (skos schodami kafli nie mieści się w prostokątnych pasach, a świat jest budowany dwa razy — `GeometryAfterCollapse`); wrócić w U2, jeśli przejście na rampę razi |
| D4 | Betonowe wstawki `C` w skale (1.1 kolumny 251–257 wiersze 39 i 43; szare prostokąty w kadrze `m1_c246u`): zostawić czy zamienić na `#`? | **Zamienić na `#`** (wygląd; `C` i `#` są dla symulacji tym samym litym kaflem — sprawdzić w U1 `--maptest`) |
| D5 | Szyby 1.2 z podestami (kolumny 60–70, 145–155, 207–216, 274–280): przekrój na całą wysokość (głęboki wąwóz) czy bez? | **Bez w U3**, tylko dolna hala; szyby jako osobna próba, jeśli hala się sprawdzi |

## Etapy

### U0 — pomiar i spike (lokalnie, bez PR)
- Gałąź `spike/underground-u0`: jeden wpis 1.1 na zachodniej części galerii (kolumny 44–99, `r0` 30, `r1` 34, `set` `tunnel`).
- Zrzuty przed/po: noc i `--view3dlit`, `--shotat=60,80 --shotrow=33`, kamera WIDE / NORMAL / CLOSE; nagranie Movie Maker przejścia galerią.
- GPU: release, 4K, HIGH, latarka, 3 × 12 s naprzemiennie z wpisem i bez (`--perf`).
- Sprawdzić D2 na tym samym wycinku: przekrój w `terrain` i w `rock_material()` obok siebie.
- Bramka: użytkownik ogląda nagranie i gra w release z worktree.

### U1 — kopalnia 1.1: galeria główna i sala (PR na mapę, wersja +1)
- `z1_m1.gd FRONT`: tunel 40–99 (`r0` 30, `r1` 34), sala 100–126 (`r0` 26, `r1` 34 — sala nad galerią), tunel 127–215 (bez rampy, D3);
  wejście do galerii z szybu 40–43 zostaje otworem w stropie.
- Strefy wydobycia: przód zostaje przy przekroju (`Level3D.zone_front_z`), elementy poza `dig_blocks`.
- D2: `rock_material()` dla przekroju skały we wszystkich wpisach tunelowych (też 1.3 i tunel 1.2 — zrzuty porównawcze tych map).
- D4: zamiana wstawek `C` na `#`.
- `tools/test_front.gd`: 1.1 w liście map z przekrojem; `--maptest`, `test_niches.gd` (wnęki 1.1 przy przekroju), `test_dig_face.gd`.

### U2 — kopalnia 1.1: dolna galeria i rampa
- Dolna galeria 202–256 (`r0` 37, `r1` 43) z obiema strefami wydobycia (192–201 i 257–260) — czoła stref przy przekroju.
- Rampa w strefie zawału tylko po decyzji D3 (przed zawałem i po zawale: `set_shells` musi liczyć oba zestawy wierszy).

### U3 — dolna hala 1.2
- `z1_m2.gd FRONT`: hala 150–221 (`r0` 30, `r1` 40, `set` `tunnel`; ściany `C` — beton jak hala stacji), korytarz 145–149 do szybu.
- Kadr kontrolny `m2_c205d` (dziś: cienka podłoga i mur tła korytarza pod nią).

### U4 — zestaw `mine` (opcjonalnie, po ocenie U1 w grze)
- Modele: stempel z okorkiem (jest `stake`/`post`?), lutnia wentylacyjna z blachy, kabel na hakach, lampa górnicza w siatce — Poly Haven
  albo `tools/` (Blender, CC0); `tools/tex_vram.py` po nowych GLB.
- Podmiana `set` w 1.1 z `tunnel` na `mine`.

## Ryzyka

- **Zawał 1.1** (`COLLAPSE`, świat budowany dwa razy): `Level3D.set_shells` trzyma stan w zmiennych statycznych — przy drugiej budowie
  przekrój musi wynikać z wierszy po zawale (rumowisko `^` → lity kafel). Dlatego rampa poza U1.
- **Gniazda ćm `Z` pod stropem galerii 1.1** — płyta stropu nie może zasłaniać ich w rzucie (test: brak płyt w pasie gry wystarcza, ale
  sprawdzić znaczniki i poświatę gniazda w kadrze CLOSE).
- **Las nad galerią 1.1** gaśnie pod powierzchnią (`SURF_FADE`), ale galeria leży tylko 8–10 wierszy pod gruntem: sprawdzić, czy przekrój
  stropu i płyta podłoża lasu nie stoją razem w kadrze przy wyjściu z szybu (kol. 40–43, 193–197).
- **Wydajność**: galeria 1.1 to najdłuższy pas przekroju w grze (~175 kolumn) — płyty scalone w ciągi, ale ściany i elementy liczyć osobno.

## Czego nie robimy

- Nie zmieniamy tylnej ściany `b` (cegła w kopalni) — to osobny temat łataniny materiałów (przegląd, punkt 2).
- Nie ruszamy powierzchni, budynków ani kryjówki.
- Bez trzeciego viewportu i bez zmiany kamery (wnioski z `C:\deadair87\reports\world-depth-recommendations-2026-11-04.md`).
