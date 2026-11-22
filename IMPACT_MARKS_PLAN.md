# IMPACT_MARKS_PLAN — ślady po kulach i granatach w świecie

Stan wyjścia: main 1.7.653 (c009767f, 2026-11-22). Kontynuacja `DESTRUCTION_PLAN.md` D4 (kosmetyka walki, 1.7.500).
Prośba autora: „zaplanuj dodanie śladów po kulach/granatach w środowisku gry”. Ten plik to analiza i plan; stan wdrożenia niżej.

**Stan (2026-11-22):** decyzje 1–10 przyjęte zgodnie z zaleceniami (sekcja „Decyzje”). E0–E3 wdrożone w jednym PR (gałąź
`feat/impact-marks`, 1.7.655, osobne commity E0 i E1–E3); E4 (domknięcie) w tym samym PR. Zostaje ocena na playteście.

**Odkrycia przy wdrożeniu:**
- **Ślad w płaszczyźnie gry jest prawie niewidoczny.** Kule lecą w płaszczyźnie XY, więc trafiają bok kafla albo wierzch podłogi, a kamera
  patrzy na nie krawędzią (wierzch podłogi 1 m głębi to kilka pikseli wysokości). Dlatego każdy ślad na bryle (skała, beton, blacha, lód,
  śnieg, strefa wydobycia) ma **odprysk na czole bryły**: drugi dekal rzutowany wzdłuż −Z na `Level3D.front_z` (w strefie przekroju na
  ścianie przekroju, `Front3D.LAYER_WALL`), 1,5 × średnicy śladu, przy krawędzi trafienia. Tak samo gniazdo śrutu, osmalenie i dziobaki.
- **Rozmiar (decyzja 2):** 9 cm dla 7,62 w betonie to ok. 5 px na 1080p i ślad ginął w teksturze betonu — podniesione do 12 cm, ciemny
  wylot ok. 30% średnicy (był 2–3% powierzchni) i cień niecki gęstniejący ku środkowi.
- **Limity niższe niż w planie:** 64 / 112 / 160 śladów i 12 / 20 / 32 osmaleń (odprysk to drugi dekal). Pomiar: 8 świateł + 365 elementów
  klastrowanych przy 500 trafieniach w kadrze (limit 512), czas GPU świata bez mierzalnej zmiany.
- Na przegrodach (deski, cegła) bez dekala — ślad zostawia maska uszkodzeń (E0).

Skala: kafel 16 px ≈ 1,31 m, 1 px ≈ 8 cm (`Level3D.PX` = 1,8 / 22 m). Kamera `FOV` 40°.

## Werdykt

Ślady już są, ale w wersji minimum: jeden płaski dekal na trafienie (albedo bez normalnej), jedna tekstura na powierzchnię, osmalenie
tylko na gruncie pod wybuchem. Do tego dochodzą cztery błędy cyklu życia, które wyjdą, gdy ślady będą wyraźniejsze:

1. **Ślady nie znikają z mapą.** Dekale leżą w `_world`, a nie w geometrii mapy `_geo`. Nic ich nie czyści poza limitem sztuk. Przechodzą
   więc na następną mapę, w te same miejsca w pikselach, i przeżywają restart misji oraz wipe.
2. **Ślady na przegrodach dublują maskę uszkodzeń.** Deski i cegła mają własne dziury i wyszczerbienia (`damage_mask.gd`, D0/S1).
   Dekal z `Vfx.impact` kładzie się na nie drugi raz. Po resecie (wipe) albo przybiciu deski maska jest czysta, a dekal wraca na nową deskę.
3. **Dekal świata maluje też wrogów i przedmioty.** `cull_mask = LAYER_WORLD`, a w tej warstwie są też wrogowie, łuski, znajdźki
   i rekwizyty. Osmalenie ma 0,5 m głębokości rzutu, więc czerni stopy wroga, który na nim stanie.
4. **Wspólny limit 160 zjada śrut.** Jeden strzał śrutem to 5–10 dekali. Kilka strzałów kasuje najstarsze ślady, także te w kadrze.

Do tego rodzaj śladu bierze się z powierzchni **kroków**, nie z wyglądu. Skała w tunelach i drewniana kładka dostają ślad ziemi (E1).

Plan: **E0** porządki cyklu życia i pomiar budżetu, **E1** lepsze ślady po kulach (głębia, warianty, kąt, kaliber, śrut), **E2** granaty
i wybuchy (osmalenie na każdej powierzchni w zasięgu, dziobaki od odłamków, krater w ziemi, żar), **E3** opcje do decyzji (sadza po ogniu,
krew na ścianie za celem), **E4** jakość, budżet i dokumenty. Wszystko to kosmetyka lokalna, bez wpływu na rozgrywkę i bez sieci.

## Co jest dziś (ustalone w kodzie)

### Kule

- **Wywołanie** (`vfx.gd:306` `Vfx.impact`): przy każdym trafieniu w świat (poza wodą, błotem i olejem) woła `view3d.mark_hit(pos, normal,
  surface)` (`vfx.gd:310-311`). Źródła:
  - kula w kafel: `projectile.gd:365-373` `_world_hit`, a `surface` daje `level.surface_at_hit` (`level.gd:2695`, dane kafla);
  - kula w przegrodę: `_world_hit(..., surface_override)` przy zatrzymaniu albo `_barrier_fx` przy przelocie — wlot i wylot
    (`projectile.gd:352-363`);
  - szyna SPECTER-1: `weapon_controller.gd:1318-1326` `_rail_visual`, także u klientów przez `_tracer_remote`.
- `Vfx.impact` wywołuje każdy peer z własnego obrazu pocisku. Ślady są więc u wszystkich, ale w nieco innych miejscach i z innym obrotem.
- **Dekal** (`view3d.gd:5565` `_mark`): `Decal` o rozmiarze `size × depth × size`, rzut wzdłuż −normalnej 2D, środek w `MARK_Z` = 0,3 m
  (płaszczyzna lotu kul), losowy obrót wokół normalnej, `cull_mask = LAYER_WORLD`, **dziecko `_world`** (`:5576`).
- **Rozmiar** (`:5470-5475`, `:5582-5584`): `HOLE_M` 9 cm × `HOLE_SIZE` (ziemia 1,5, śnieg 1,6, blacha 0,7, drewno 0,9) × losowo 0,8–1,2.
  Głębokość rzutu 0,12 m. Bez związku z kalibrem: kula 9 mm, 7,62 i śrucina dają ten sam ślad.
- **Tekstury** (`_make_mark_tex` `:5482`, `_hole_tex_for` `:5514`): liczone w GDScript przy pierwszym użyciu, RGBA 64 × 64, **tylko
  albedo**. Rodzaje: beton (krater z jasnym pyłem, także lód i nieznane), ziemia (miękka plama), drewno (dziura z przełomem), blacha
  (wgniecina z rdzawą obwódką). Jedna tekstura na rodzaj. Rozgrzewane pod planszą w `_warm_destruction("hitfx")` (`:4820-4824`).
- **Limit** `MAX_HOLES` 160 (`:5471`). Najstarszy dekal znika od razu, bez wygaszania.
- **Kąt padania** nie ma znaczenia. Kula pod kątem 10° do podłogi zostawia to samo kółko co strzał prostopadły.
- **Rykoszet** (`projectile.gd:~320-341`): iskry i dźwięk, bez śladu w miejscu odbicia (ślad daje tylko `_world_hit`).

### Wybuchy

- `Combat.explode` (`combat.gd:272`, serwer) → `Arsenal.broadcast_explosion` (`arsenal.gd:418`, RPC `call_local`) → `Vfx.explosion`
  u wszystkich. Źródła: granat ręczny (`grenade.gd:79`), WRATH-4, FALCON-6, beczka (`prop.gd:247`), ładunek burzący.
- **Osmalenie** (`vfx.gd:404-411`): jeden promień **w dół** do 0,7 × promienia wybuchu po masce 1|16. Jeśli trafi grunt, `mark_scorch`
  (`view3d.gd:5591`) kładzie jeden dekal skierowany w górę: 0,6–2,5 m (WRATH-4 48 px ≈ 2 m), głębokość 0,5 m, tekstura sadzy.
  Limit `MAX_SCORCH` 24.
- **Brak:** osmalenia na ścianie i stropie (wybuch przy murze albo w tunelu pod stropem), śladów odłamków, różnicy między ziemią
  (krater), betonem (odpryski) i blachą, żaru po wybuchu. Wybuch w powietrzu zostawia ślad tylko na gruncie bliżej niż 0,7 r.
- Przegrody (deski, cegła, kratka, stempel) dostają od wybuchu plamy w masce uszkodzeń (D0) — to zostaje. Strefy wydobycia (D5) mają
  prawdziwy krater w siatce — to też zostaje.
- Wrak beczki ma własną sadzę (`_mark(..., WRECK_SOOT_M ...)`, `view3d.gd:9835-9837`).

### Cykl życia (błędy 1–3 z werdyktu)

- `_sync_geometry` (`view3d.gd:927-955`) przy zmianie mapy czyści dzieci `_geo`, ale `_holes` i `_scorches` są dziećmi `_world`.
  W kodzie nie ma `_holes.clear()`. Zmiana misji idzie przez `level.load_map` w tej samej scenie, a `reload_current_scene`
  (`main.gd:1630`) jest tylko przy wyjściu z sesji. Kałuże krwi (`mirror_blood`, `:8311`) leżą w `_geo` i znikają z mapą — ślady powinny tak samo.
- Reset przegród (`level.reset_breakables`, `level.gd:1660`, `damage_epoch` w `view3d.gd:3917`) czyści maskę uszkodzeń, ale dekali nie rusza.
- Strefy wydobycia: dekal na czole strefy zostaje po wykopaniu komórki. Ślad 0,12 m zwykle po prostu znika (nic już nie ma w jego pudle).
  Osmalenie 0,5 m może się jednak położyć na nowej ścianie wykopu.

## Zasady

- **Tylko 3D, tylko kosmetyka.** Żadnego stanu w symulacji 2D, żadnego RPC poza istniejącymi (`broadcast_explosion`, obraz pocisku).
  Dołączający nie dostaje starych śladów (decyzja 6).
- **Przegrody i strefy wydobycia mają własne ślady** (maska uszkodzeń, siatka). Dekale tylko na niezniszczalnym świecie (zasada już
  zapisana w D4, dziś niedotrzymana).
- **Generatory w `tools/`** (CLAUDE.md): tekstury z Pythona do `art/fx/marks/`, a nie liczone w GDScript.
- **Budżet:** dekale w Forward+ to elementy klastrowane, razem ze światłami i sondami. Limit silnika to
  `rendering/limits/cluster_builder/max_clustered_elements` (domyślnie 512, w `project.godot` nieustawione). Po przekroczeniu silnik
  bez ostrzeżenia gubi elementy, także światła. Limity sztuk stroimy pomiarem w E0.

## Technika

- **Decal z normalną (+ ORM).** `Decal.texture_normal` daje krawędź krateru, którą łapie snop latarki. `texture_orm` daje matowy pył
  i błyszczący goły metal. Koszt GPU tego samego rzędu co samo albedo — do zmierzenia w E0. `normal_fade` ~0,3 zapobiega
  rozmazywaniu śladu na krawędzi kafla.
- **Warianty:** 3–4 na rodzaj, 128 × 128 (ślad kuli) i 256 × 256 (osmalenie). Silnik pakuje je do wspólnego atlasu dekali. Wybór
  wariantu i obrót z `hash(pos)`, nie z `randf()` — ten sam punkt daje ten sam ślad przy rozgrzaniu i w zrzutach testów.
- **Wydłużenie przy kącie:** pudło dekala skalowane wzdłuż kierunku lotu o 1 / max(sin α, 0,35) (α — kąt między torem a powierzchnią)
  i obrócone zgodnie z torem. Przy α < 20° na blasze i betonie zamiast dziury **rysa** (osobna tekstura) — tam, gdzie dziś jest rykoszet.
- **Kaliber:** rozmiar z `WeaponDef` / naboju (`info.pellets`, kaliber), np. pistolet 0,8, karabin 1,0, BZ/Brenneke 1,3, śrucina 0,45
  × `HOLE_M`.
- **Śrut:** paczka śrucin ze strzału w jeden kafel → najwyżej 4 osobne dekale + **jeden dekal „gniazda”** (tekstura kilku dziurek) na
  środku skupienia. Limit nie zjada się już po kilku strzałach.
- **Scalanie bliskich:** nowy ślad bliżej niż 0,4 × średnicy od istniejącego tego samego rodzaju nie tworzy węzła. Zamiast tego
  powiększa stary (do 1,6 ×) i zmienia mu wariant na „poszarpany”. Seria w jeden punkt wygląda wtedy jak wyżłobienie, a nie stos 30 dekali.
- **Wybuch na wielu powierzchniach:** z punktu wybuchu N promieni (8 przy LOW, 12 przy HIGH) po masce 1|16 do 0,8 r. Trafienia
  grupowane po kaflu i normalnej (jedno osmalenie na ścianę / strop / grunt). Rozmiar maleje z odległością, a krycie z `cos` kąta.
  Funkcja czysta (`ImpactMarks.blast_marks(space, pos, r, n)` → lista [punkt, normalna, rozmiar, powierzchnia]) — testowalna headless.
- **Żar:** osmalenie dostaje `texture_emission` (pomarańczowe żyłki), `emission_energy` gaśnie z ~2 do 0 w 3–4 s (tween). Bez światła
  i bez cienia, wrak beczki ma już swoje światło.
- **Rodzic i warstwa:** nowy węzeł `ImpactMarks` w `_geo` (znika z mapą). Wyczyszczenie przy restarcie misji idzie przez
  `level.reset_breakables` z pustym stanem albo przez nowy sygnał `level.world_reset`. Przy punkcie kontrolnym bossa ślady zostają
  (decyzja 7). Malowanie wrogów: najpierw zrzut w E0. Jeśli widać, najtańsza poprawka to płytsze pudło osmalenia (0,15–0,2 m z
  `upper_fade`). Osobna warstwa renderowania dla statycznego świata wymagałaby zmiany masek kilkunastu świateł — tylko gdy zrzut pokaże, że płytsze pudło nie wystarcza.

## Etapy

### E0 — porządki i pomiar (1 PR, wersja +1)

- Wydzielenie `scripts/impact_marks.gd` (static, bez stanu sceny: wybór tekstury, rozmiar, scalanie, promienie wybuchu) z `view3d.gd`.
  Węzeł z dekalami pod `_geo`, więc znika z mapą (błąd 1).
- Czyszczenie przy restarcie misji i wipe'ie (`_restart_mission` / `reset_breakables({})`). Przy punkcie kontrolnym ślady zostają.
- `Vfx.impact` dostaje `on_breakable` (z `_barrier_fx` i `_world_hit` z `surface_override`). Na przegrodzie robi odpryski i dźwięk,
  ale nie kładzie dekala, bo ślad zostawia maska uszkodzeń (błąd 2).
- Strefy wydobycia: przy wykopaniu komórki usuwamy ślady, których środek leży w wykopanym obszarze (`dig_zone` → `view3d`, jak
  `_clear_rubble_near`).
- **Pomiar** (`--fxtest`, okno, 1.2 i 1.3): liczba elementów klastrowanych w kadrze (światła + dekale), koszt GPU 160 / 300 / 500 dekali,
  albedo kontra albedo + normalna + ORM, czy przy 500 gaśnie któreś światło. Zrzut wroga na osmaleniu (błąd 3). Wynik w tym pliku.
- Testy: `--fxtest` — ślad znika po zmianie mapy i restarcie, zostaje przy punkcie kontrolnym, brak dekala na deskach i cegle, ślad
  usunięty po wykopaniu. `tools/test_impact_marks.gd` (headless) — funkcje czyste.

### E1 — ślady po kulach (1–2 PR)

- `tools/gen_impact_marks.py` → `art/fx/marks/hole_{concrete,rock,dirt,wood,metal,ice}_{0..3}_{albedo,normal,orm}.png` i `graze_*`
  (rysa), `pellet_cluster_*`. Wysokość z szumu i promienia, z niej normalna. Po imporcie `tools/tex_vram.py` (CLAUDE.md).
  **Rodzaj śladu wg wyglądu, nie wg kroków.** `surface` kafla to powierzchnia kroków (`level.gd:112` `KINDS`): bryła `#` to zawsze
  `dirt`, także w tunelach, gdzie w 3D wygląda jak skała. Kładka `-` (deski) też jest `dirt`. Kula w skałę tunelu i w drewnianą
  kładkę zostawia więc dziś miękką plamę ziemi. Potrzebna funkcja `mark_surface(pos, normal)`: `#` w pasie podziemi → `rock`,
  `-` → `wood`, `=` → `metal`, reszta jak `surface_at_hit`.
- Kaliber, kąt (owal + rysa), gniazdo śrutu, scalanie bliskich, wariant z `hash(pos)`.
- Ślad w miejscu rykoszetu (rysa) — dziś tylko iskry.
- Limity wg jakości (np. LOW 96 / MEDIUM 160 / HIGH 256 — liczby z pomiaru E0). Najstarszy ślad gaśnie przez 1 s (`albedo_mix`),
  zamiast znikać od razu.
- Zrzuty `--fxshots`: każda powierzchnia × kąt 90° / 30° / 10° × latarka wł./wył., seria M-83 w jeden punkt, 5 strzałów śrutem.

### E2 — granaty i wybuchy (1–2 PR)

- `blast_marks`: osmalenie na gruncie, ścianach i stropie w zasięgu (zamiast jednego promienia w dół). Wybuch w powietrzu przy ścianie
  zostawia ślad na ścianie.
- Tekstury osmalenia wg powierzchni: **ziemia/śnieg** — ciemny krater z wałem i wyrzuconą ziemią wokół (normalna daje zagłębienie);
  **beton/skała** — sadza, odprysk w środku, **dziobaki od odłamków** w pierścieniu; **blacha** — sadza i wgniecenia; **drewno**
  (kładki, rekwizyty świata) — zwęglenie. Ciecze bez śladu, jak przy kulach.
- **Odłamki poza pierścieniem:** 4–8 drobnych dekali dziobaków na ścianach i stropie w 0,8–1,5 r (losowo z `hash(pos)`, z promieni
  `blast_marks`). Tylko granaty i WRATH-4 — beczka i ładunek bez odłamków.
- **Żar** 3–4 s (emisja) i 2–3 smużki dymu z puli `spawn_burst` (bez nowych emiterów).
- Rozmiar z promienia: granat ręczny / WRATH-4 ~2 m, FALCON-6 ~1,5 m, beczka ~2,5 m z tłustą plamą, ładunek burzący ~3 m.
- Rozgrzanie nowych tekstur w `_warm_destruction("hitfx")`.
- Zrzuty: wybuch na gruncie, przy ścianie, pod stropem tunelu 1.2, w powietrzu, w ziemi i na blasze; noc z latarką.

### E3 — opcje (osobne PR-y, tylko po decyzji)

- **Sadza po ogniu:** plama ognia (`fire_patch.gd`) po zgaśnięciu zostawia osmalenie (bez żaru); strumień HKM-9 w ścianę — przyciemnienie
  co 0,5 s strumienia w jeden kafel, ze scalaniem.
- **Krew na ścianie za trafionym wrogiem:** rozprysk wylotowy na ścianie w 1–2 m za celem, kierunek z toru kuli (dziś krew tylko na podłodze:
  `mirror_blood`). To raczej temat do osobnego planu o krwi i trupach.

### E4 — domknięcie

- README (flagi testu), `DESTRUCTION_PLAN.md` D4 (odsyłacz), CHANGELOG przy każdym PR z wersją.
- Pomiar FPS przed i po w buildzie release (`--perf`/`--hitchtest`) na 1.2 w walce, wynik w tym pliku.

## Testy

- **Headless** `tools/test_impact_marks.gd`: tekstura i rozmiar wg powierzchni i kalibru, wydłużenie i rysa wg kąta, scalanie bliskich,
  gniazdo śrutu (≤ 5 węzłów na strzał), `blast_marks` na mapie testowej (grunt, ściana, strop; wybuch w powietrzu przy ścianie; nic za
  ścianą), limity wg jakości, brak śladu w cieczach i na przegrodach.
- **Okno** `--fxtest` (rozszerzenie): cykl życia z E0, zrzuty E1/E2, liczba elementów klastrowanych, kompilacje potoków przy pierwszym
  trafieniu i wybuchu po rozgrzaniu = 0.
- Regresje jak zawsze: `--destructiontest` (przegrody bez dekali, maska bez zmian), `--digtest`, `test_weapons.sh`, `--maptest`.

## Ryzyka

- **Limit elementów klastrowanych** — dekale wypierają światła lamp (miganie). Mitygacja: pomiar w E0, limity wg jakości, scalanie,
  gniazdo śrutu. W razie potrzeby podniesienie `max_clustered_elements` (koszt pamięci).
- **Ślad niewidoczny z kamery.** Kula 9 mm to kilka pikseli w 1080p. Ślady po kulach pewnie trzeba przesadzić ×1,5–2, jak odpryski w D4
  (bryłka 6 cm). Do oceny na zrzutach E1 (decyzja 2).
- **Dekal na krawędzi kafla** zawija się na sąsiednią ścianę albo róg. Mitygacja: `normal_fade` i przycięcie rozmiaru przy narożniku
  (sprawdzenie sąsiedniego kafla w `ImpactMarks`).
- **Osmalenie przez cienką ścianę.** Pudło 0,5 m może sięgnąć drugiej strony stropu 1 kafla (1,31 m — raczej nie) albo kładki. Mitygacja:
  głębokość ≤ 0,3 m i `upper_fade`.
- **Różne ślady u różnych peerów** (losowość pocisków klienta) — akceptowalne, to kosmetyka.

## Decyzje (przyjęte 2026-11-22 zgodnie z zaleceniami)

| # | Pytanie | Decyzja |
|---|---------|-----------|
| 1 | Jak długo trwają ślady? | Do końca misji (albo restartu), limit wg jakości, najstarsze gasną przez 1 s. Bez blaknięcia z czasem. |
| 2 | Realistyczny rozmiar czy czytelny? | Czytelny: ślad kuli ~1,5× prawdziwego (jak odpryski D4), ostatecznie po zrzutach E1. |
| 3 | Granat na ścianach i stropie? | Tak (E2). |
| 4 | Odłamki? | Dziobaki w teksturze osmalenia + 4–8 drobnych dekali na ścianach, tylko granaty i WRATH-4. |
| 5 | Żar po wybuchu? | Tak, sama emisja 3–4 s, bez światła. |
| 6 | Dołączający widzi stare ślady? | Nie (kosmetyka, bez sieci). |
| 7 | Punkt kontrolny bossa czyści ślady? | Nie — czyszczą tylko restart misji, wipe i zmiana mapy. |
| 8 | Sadza po ogniu (E3)? | Tak, tanio, po E2. |
| 9 | Krew na ścianach (E3)? | Osobny plan (krew i trupy), nie tutaj. |
| 10 | Skąd tekstury? | Generator Pythona `tools/gen_impact_marks.py` (albedo + normalna + ORM, warianty), nie GDScript i nie skany. Jeśli zrzuty E1 wyjdą słabo — dekale CC0 z ambientCG/Poly Haven (sprawdzone wcześniej: „Leaking”). |

## Kolejność i rozmiar

| Etap | PR | Ryzyko | Zależności |
|------|----|--------|------------|
| E0 | 1 | niskie (porządki), pomiar decyduje o limitach | — |
| E1 | 1–2 | średnie (wygląd, budżet) | E0 |
| E2 | 1–2 | średnie | E0, tekstury z E1 (generator) |
| E3 | 1 na opcję | niskie | E2 |
| E4 | w ostatnim PR | — | — |

Następny krok: playtest (czytelność śladów z kamery, budżet przy lampach, osmalenie pod wrogami).
