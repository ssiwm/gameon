# Jakość postaci graczy: płeć w sylwetce, stroje, animacje, twarze — plan implementacji

**Stan (2026-11-27):** plan zamknięty (Q8 poza zakresem). Decyzje z §6 przyjęte. Q0–Q4 wdrożone w 1.7.705, Q5–Q7 w 1.7.706, poprawki po zrzutach z gry (warkocz) w 1.7.707 (po jednym PR-ze na grupę — każdy etap przebudowuje
te same sześć GLB). Q7 w węższym zakresie niż w §3: atlas obejmuje ubrania, a siatki, których gra i testy szukają po nazwie (ciało, warkocz,
oczy, brwi, rzęsy, plecak, torba medyczna, `gear`, hełm i stetoskop medyka), zostają osobno — scav ma 9 siatek zamiast 16, medyk ok. 11. Podstawa planu: przegląd sześciu modeli MPFB (`art/char3d/mpfb/`) na stykówkach
w skali gry, w zbliżeniach (tył, oba boki, twarze z nakryciem głowy i bez) i w klatkach cyklu ruchu (`shot_char3d.gd`, `shot_anim3d.gd`,
`shot_hands3d.gd`) oraz porównanie z grami gatunku (Contra: Operation Galuga, Helldivers 2, GTFO, Hunt: Showdown).
Kontynuacja `CHARACTER_PLAN.md` (E0–E2 zrobione; E3 mocap i E4 nie).

## 1. Stan dziś

| Obszar | Co jest | Problem |
|---|---|---|
| Płeć | `gender` 0/1, wzrost 1,70 / 1,80 m, mięśnie 0,55 / 0,65, waga 0,50 / 0,55 | `hair_under_hat` (`char_mpfb.py`) usuwa każdą ścianę włosów powyżej najniższej krawędzi hełmu — z `ponytail01` zostaje 238 (scav) i 41 (medyczka) trójkątów, nic nie widać. Pod hełmem kobieta i mężczyzna mają tę samą łysą czaszkę; kamizelka i plecak zakrywają talię i biodra |
| Twarz | ciało z głową: 7000 trójkątów (`BODY_TRIS`, równe upraszczanie), skóra = sam kolor 1024 px na całe ciało, szorstkość stała 0,7 | Brak mapy normalnych, szorstkości i SSS (porcelanowa skóra), brak rzęs, kobiece brwi to czarne zmarszczone łuki, zero mimiki i brudu. Głowa w grze ma ok. 19 px — twarz liczy się na zbliżeniach (kryjówka, portrety, nieśmiertelnik w raporcie) |
| Scav | kamuflaż, hełm KZ45, kamizelka, plecak + śpiwór | Plecak z TRELLIS jak zgnieciony papier; śpiwór to walec z „tarczą” na końcu; chusta to płaski łososiowy trójkąt; biała maska na biodrze czyta się jak druga głowa; drobny kamuflaż zlewa się w błoto |
| Hazmat | kombinezon przebarwiony na żółto, butle ze skryptu, maska | Płaski nasycony żółty bez fałd i szwów, jasne łaty u kobiety; butle to gołe walce z białą naklejką; kaptur jest w specyfikacji, ale go nie widać (szara „czapka” maski) |
| Medyk | szyty mundur EMT (dobry), biały hełm M1951, torba z krzyżem | Z boku (kamera gry) nie widać, że to medyk; gołe dłonie; torba z TRELLIS pogięta |
| Buty | `cloth_garments.py` (1.7.223: sznurowane wojskowe) | Na renderze błyszczące gumowce, sznurowania nie widać, te same u wszystkich |
| Animacje | klipy Quaternius UAL (CC0) + pozy z kodu | Bieg tyłem = sprint od tyłu (pochylenie do przodu, długi krok — „moonwalk”); sprint z krokiem prawie w szpagacie przy każdej prędkości; postój nieruchomy „na baczność”; `Death01` kończy się nogami w górze; M-83 wisi przed piersią, kolba poza barkiem |
| Technika | 30–41 tys. trójkątów, 11–16 siatek i materiałów na postać, tekstury 1K | Budżet z planu: 20 tys. i 1–2 materiały; tekstury wyposażenia powielone w każdym GLB |

## 2. Zasady

- Zmiany w generatorach (`tools/char_mpfb.py`, `tools/cloth_garments.py`, `tools/prep_anim3d.py`, `tools/bake_combat_anim.py`), nie w GLB.
  Po przebudowie: import headless, `python tools/tex_vram.py`, import jeszcze raz (`tex_vram.py --check` w CI).
- Każdy etap = osobna gałąź i PR (podbicie `config/version`, wiersz w `CHANGELOG.md`), zrzuty „przed / po” do akceptacji przed scaleniem.
- Modele graczy mają innych odbiorców — każdy etap, który zmienia GLB, sprawdza ich wszystkich:
  zwłoki (`corpse3d.gd`, `test_corpses.gd`), Mimik w modelu `male_scav` i Mimik-powalony (`enemy3d.gd`, `test_mimic3d.gd`),
  portrety wyglądów (`bake_look_portraits.gd` — wypiec od nowa), punkty celowania (`test_aim_points.gd`), anatomia i dłonie
  (`test_proportions.gd`), stopy i podciąganie (`test_foot_terrain.gd`, `test_mantle.gd`, `test_standing_legs.gd`), nakładki walki
  (`test_combat_motion.gd`), wagi rękawic (`glb_glove_weights.py --check`).
- Okno tylko dla narzędzi zrzutów (`--script tools/shot_*.gd`); tryby testowe wyłącznie headless (zapis profilu postaci).

## 3. Etapy

### Q0. Stykówka przeglądu postaci (0,5 dnia)

Jedno narzędzie zamiast doraźnych skryptów: `tools/shot_char_review.gd` — dla każdego z sześciu modeli tył / bok / przód w pełnej postaci,
głowa przód / 3/4 / bok z nakryciem i bez (`--bare`), siatka 3×2 i pasek w skali gry. Zapis „przed” do `concepts/char_review_before/`.
Każdy następny etap dokłada zrzut „po” tym samym narzędziem.

### Q1. Płeć w sylwetce (1,5–2 dni)

1. **Ogon spod hełmu.** `hair_under_hat`: usuwać tylko ściany, których wierzchołek leży wewnątrz czaszy hełmu (promień w górę trafia w hełm
   **i** punkt jest bliżej środka czaszy niż jej promień), zamiast wszystkiego powyżej krawędzi. Ogon od potylicy w dół zostaje.
   Gdy `ponytail01` po cięciu nadal wygląda źle — ogon albo warkocz ze skryptu (karty włosów wzdłuż krzywej `_tube`, przycinanie alfa jak
   `HAIR`), zaczepiony pod krawędzią hełmu z tyłu.
2. **Kołysanie.** Dwie–trzy kości ogona pod `mixamorig_Head` (nazwy spoza Mixamo — `char_clips.gd` przenosi tylko kości ze źródła, więc
   klipy ich nie ruszają) i `SpringBoneSimulator3D` (Godot 4.4+) w `char3d.gd`. Tylko widok; wyłączone przy `--char3d-lq` i poza ekranem.
3. **Budowa.** `FEMALE`: niższe `muscle`, wyższe `proportions`; `MALE`: wyższe `muscle`. Kurtka kobiety scav i medyczki ściągnięta w talii
   (shrinkwrap od pasa do żeber po `add_sewn`). Granice anatomii w `test_proportions.gd` (barki 0,20–0,25 H) zostają.
4. Bot (kobieta scav) zyskuje najwięcej — sprawdzić go w grze obok gracza.

Akceptacja: na pasku w skali gry (ok. 145 px) kobietę odróżnia się od mężczyzny w tym samym stroju bez podpowiedzi; ogon nie przebija
hełmu, plecaka ani kołnierza w biegu, kucaniu, upadku i na zwłokach.

### Q2. Animacje ruchu (1,5–2 dni)

1. **Bieg tyłem.** Dziś `back_run` gra sprint z ujemną fazą i odchyleniem −9°. Nowy stan `run_back` w `CLIPS`:
   wariant A — `Jog_Fwd_Loop` (UAL1) od tyłu z `upper` ≈ 0,3 i odchyleniem tułowia do tyłu; wariant B — klip biegu tyłem z CMU
   (`prep_anim3d.py --step-sync`, surowe pliki tylko lokalnie, podziękowanie w napisach); wariant C — poza z kodu (krótki krok,
   `stride` już jest w `char3d.gd`). Wybór na stykówce `shot_anim3d.gd --set=run`.
2. **Bieg o krótszym kroku.** `Jog_Fwd_Loop` jako drugi klip biegu, mieszany ze `Sprint_Loop` wg prędkości (jog do ok. 70% prędkości
   biegu, sprint powyżej); faza kroku wspólna, więc bez poślizgu.
3. **Postój.** Warstwa `idle_life.gd` (oddech, przenoszenie ciężaru, tiki) dla graczy — profil spokojniejszy niż u wrogów, bez tików
   rąk (ręce prowadzi IK z bronią); lekki rozkrok w pozie postoju. Ziarno z peera, więc każdy gracz oddycha inaczej.
4. **Upadek.** Przyciąć `scrub` klipu `down` przed wyrzutem nóg albo zamienić na `Hit_Knockback` (UAL2) + osiadanie z kodu; wstawanie
   (`getup`) musi zaczynać się z tej samej pozy.

Akceptacja: film z `shot_anim3d.gd` (bieg, bieg tyłem, start / stop, postój 5 s, upadek i wstawanie); `test_aim_points.gd`,
`test_foot_terrain.gd`, `test_mantle.gd`, `--bottest` PASS.

### Q3. Drobne poprawki strojów (1–1,5 dnia)

| Zmiana | Jak |
|---|---|
| Opaska z czerwonym krzyżem na lewym ramieniu medyka | `_ring` (jak taśma hazmatu) na `LeftArm`, biała, krzyż farbą w albedo |
| Rękawiczki medyka | `toigo_gloves_short` z jasnym odcieniem (lateks / skóra) + `fix_glove_weights` |
| Chusta scava | materiał tkaniny (khaki / oliwka, ziarno, fałdy), węzeł z boku zamiast trójkąta na piersi — albo usunąć z `gear` |
| Śpiwór | zwinięty koniec (spirala warstw zamiast tarczy), wiązania z luzem, szorstki materiał |
| Maska scava na biodrze | przyciemniona szaro-zielona, mniejsza, obrócona okularami do ciała |
| Kamuflaż | większe plamy (`cells` 42 → ok. 24) i mocniejszy kontrast plam; sprawdzić w skali gry na tle lasu i betonu |
| Buty | szorstkość 0,8–0,9 (skóra matowa), sznurowanie i bieżnik czytelne w normalnych; scav — skóra czarna, medyk — brązowa, hazmat — gumowce |

Akceptacja: zbliżenia Q0 i pasek w skali gry; `test_proportions.gd`, `test_corpses.gd`.

### Q4. Wyposażenie ze skryptu i hazmat (2–3 dni)

1. **Plecak, torba medyczna, ładownice, manierka** ze skryptu zamiast `GEAR_MODELS` z TRELLIS: bryły z fazami, klapy, kieszenie, taśmy,
   klamry; materiały wypiekane w Cycles (`texture_gear`, `bake_shading`) jak broń w `gun_proc.py`. Wymiary jak dziś
   (`GEAR_MODELS`: wysokość, głębokość), więc szelki i śpiwór zostają w tych samych miejscach. `art_src/gear/*.glb` zostają jako
   odniesienie, wypadają z generatora.
2. **Hazmat:** gumowany materiał (szorstkość 0,35–0,5, delikatny połysk), fałdy na łokciach, kolanach i w kroku (normalne),
   taśma na szwach, brud i błoto od kolan w dół, żółty mniej nasycony (`CAMO["hazmat"]["base"]`); widoczny kaptur na krawędzi maski;
   butle z zaworami, manometrem i pasami z klamrami zamiast naklejki; u kobiety usunąć jasne łaty po przebarwieniu.

Akceptacja: zbliżenia Q0, pasek w skali gry; wszystkie testy z §2.

### Q5. Twarze (2–3 dni) — albo wariant „zakryte”

1. **Głowa osobno.** Po zastosowaniu masek i przed upraszczaniem oddzielić głowę i szyję (grupy wierzchołków `Head` / `Neck`) w osobny
   obiekt z własnym budżetem (ok. 3500 trójkątów), ciało ok. 5500. Szew na kołnierzu — normalne wyrównane na styku.
2. **Skóra głowy:** tekstura 2K koloru, mapa normalnych wypiekana z siatki przed upraszczaniem plus pory z szumu, mapa szorstkości
   (czoło i nos błyszczą, policzki matowe, usta wilgotne); w grze `subsurf_scatter` na materiale skóry (Forward+).
3. **Rzęsy** (`eyelashes01` z paczki systemowej MPFB — `_is_hair` już je obsługuje), brwi w kolorze włosów i cieńsze, bez zmarszczenia.
4. **Ślady misji:** brud, pot i zarost (mężczyźni) w albedo i szorstkości; lekki grymas zmęczenia (jednostki mimiki MPFB, jeśli dadzą się
   zapiec w siatce spoczynkowej).

**Wariant „zakryte”** (zamiast 1–4): kominiarka albo chusta na twarzy scava, gogle na hełmie, maska podniesiona na czoło — jak Helldivers 2
i nasz hazmat. Tańszy, spójny z horrorem; twarze widać tylko częściowo w portretach.

Akceptacja: zbliżenia twarzy Q0 i portrety wyglądów (`bake_look_portraits.gd`) w świetle kryjówki.

### Q6. Chwyt M-83: kolba w barku (1–1,5 dnia)

Poza nominalna karabinów: kolba w barku, policzek przy kolbie (głowa skręcona i pochylona ku broni), lewa dłoń dalej na łożu.
Zmiana `WEAPON_POSE` / `_stance_pts` w `char3d.gd` i przeliczenie `aim_points`; wylot rozgrywki zostaje przy lufie modelu
(`test_aim_points.gd`, próg 1,5 px). Ryzyko: kąty skrajne (±80°) — tam kolba może wychodzić z barku; sprawdzić `shot_char3d.gd --set=aims`.

### Q7. Atlas i budżet (1,5–2 dni)

Po Q3–Q5 (te etapy zmieniają tekstury): w `char_mpfb.py` jeden atlas 2048² dla wszystkich nieprzezroczystych części (kolor, normalne, ORM),
osobny materiał włosów (alfa) i skóry głowy (SSS) — razem 2–3 materiały zamiast 11–16. Budżet całej postaci ok. 22 tys. trójkątów
(ciało 5,5 tys., głowa 3,5 tys., reszta na stroje). Pomiar `tools/bench_char3d.gd -- --n=1,5,10` przed i po; wpis do `CHAR3D_SPIKE.md`.

### Q8. Później (osobne decyzje)

- Głosy wg płci: `player_hurt*` i `player_down` w wersji męskiej i żeńskiej (nagrania z licencją — jak `audio_licensed/`), wybór wg `Look`.
- E3 z `CHARACTER_PLAN.md`: mocap (CMU / Rokoko) dla biegu, postoju i kucania.

## 4. Kolejność i czas

| Kolejność | Etap | Czas | Zależy od |
|---|---|---|---|
| 1 | Q0 stykówka | 0,5 d | — |
| 2 | Q1 płeć w sylwetce | 1,5–2 d | Q0 |
| 3 | Q2 animacje ruchu | 1,5–2 d | — (równolegle z Q1) |
| 4 | Q3 drobne poprawki strojów | 1–1,5 d | Q0 |
| 5 | Q4 wyposażenie i hazmat | 2–3 d | Q3 |
| 6 | Q5 twarze albo wariant „zakryte” | 2–3 d / 1 d | Q1 (włosy) |
| 7 | Q6 chwyt M-83 | 1–1,5 d | — |
| 8 | Q7 atlas i budżet | 1,5–2 d | Q3–Q5 |

Razem ok. 11–15 dni pracy. Pierwszy pakiet do playtestu: Q0 + Q1 + Q2 (bieg tyłem) + Q3 (opaska medyka) — ok. 4 dni.

## 5. Ryzyka

- **Ogon a kolizje:** przebijanie plecaka i kołnierza przy skłonie i upadku — ograniczenie kąta sprężyny, krótszy ogon u scava (plecak).
- **Zmiana budowy a chwyt:** węższe barki zmieniają `aim_points` — testy CI to wyłapią; ewentualnie przeliczyć `_stance_pts`.
- **Zwłoki i Mimik** biorą te same GLB: ogon i nowa głowa muszą leżeć na gruncie (`test_corpses.gd`) i działać z przemianą Mimika (M7).
- **Wydajność do Q7:** Q1 (kości ogona) i Q5 (druga siatka, SSS) dokładają koszt, zanim atlas go zdejmie — mierzyć `bench_char3d.gd` po każdym etapie.
- **Rozmiar repo:** nowe tekstury 2K głowy ×6 — WebP i kompresja VRAM (`tex_vram.py`).

## 6. Decyzje (2026-11-27)

1. **Warkocz** — scav i medyczka; hazmat bez (kaptur i maska).
2. **Bieg tyłem** — wariant A (trucht od tyłu); B (CMU) tylko, jeśli A nie przejdzie na stykówce.
3. **Twarze** — Q5 (dopracować), nie wariant „zakryte”.
4. **Chusta scava** — poprawić (nie usuwać).
5. **Q6 (kolba w barku)** — w tym planie.
6. **Q8 (głosy wg płci, mocap)** — poza zakresem.

Odstępstwo od §2: Q0–Q4 w jednym PR-ze (patrz „Stan”). W Q3 śpiwór poszedł pod plecak — na wierzchu zasłaniał w widoku z boku kark
i warkocz scava. W Q4 hazmat obu płci dostał szyty kombinezon (`cloth_garments.py`) i gumowy kołnierz (szyty kombinezon nie ma stójki).
