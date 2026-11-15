# Pogoda immersyjna — plan

Status: **plan z 2026-11-15 (main 1.7.570, b2a6361 + #681), scalony w #683.** Decyzje D1–D6 (§7) przyjęte 2026-11-15 — wszystkie warianty zalecane. **W0 + W1 w 1.7.572** (`weather_clock.gd`, test `tools/test_weather_clock.gd`, flagi `--weathert`, `--weatherseed`). Dalej równolegle: dźwięk W2–W4 i obraz W5–W7 (z obrazem W4 i W3).
Etapy W0–W7 to dźwięk i obraz (bez zmian w rozgrywce); W8 zmienia rozgrywkę i zaczyna się dopiero po playteście (GDD §16.0a).

## 1. Skąd to

Analiza jakości efektów pogody (2026-11-15, zrzuty i pomiary w `C:\deadair87\shots_weather2`, poza repo) wykazała, że pogoda jest
tania i dobrze spięta z rozgrywką (mnożniki hałasu przez `NightShift`, prognoza z radiostacji, dźwięk na zewnątrz / pod dachem / pod
ziemią), ale **jako obraz i dźwięk nie jest immersyjna**: deszcz wygląda jak nakładka, wiatr i grzmot są pojedynczymi pętlami i
uderzeniami, a mgła i błysk burzy łamią zasadę „ciemność to mechanika” (§8.3). Użytkownik chce pogody, w której wiatr, grzmot i deszcz
mają dźwięk i efekty wysokiej jakości, z inspiracjami z popularnych gier (§3).

## 2. Stan obecny (z kodu i pomiarów)

Pomiar: mapa 1.1, ta sama klatka, 4K, HIGH, RTX 3080 (`--shotweather=ID --shotat=30 --shotdelay=6`, `--perf=15`).

| Pogoda | Mediana jasności | Piksele < 8/255 | GPU |
|---|---|---|---|
| Pogodna noc | 0,7 | 90% | 12,5 ms |
| Deszcz | 0 | 93% | 11,8 ms |
| Burza bez błysku | 0 | 93% | 11,6 ms |
| Burza, pełny błysk | 14 | 29% | — |
| Mgła, HIGH | 13,7 | 37% | 12,5 ms, **+286 MB VRAM** |
| Mgła, LOW | 1,7 | 90% | — |

### 2.1 Obraz

| Obszar | Fakt | Gdzie |
|---|---|---|
| Deszcz | `CPUParticles3D`, smuga 0,014 × 0,55 m, **`unshaded`, stały kolor** (0,55; 0,62; 0,74; α 0,16) — nie łapie latarki, lamp ani flar; jeden plan, ta sama grubość blisko i daleko; deszcz 700, burza 1500 kropel na pudle ok. 15 m głębi (na ekranie mżawka) | `view3d.gd: _sync_weather`, `RAIN_3D`, `RAIN_SHADER` |
| Przycinanie | tekstura wysokości dachów na kolumnę (`_roof_texture`) — pod stropem i pod ziemią nie pada (działa dobrze) | `view3d.gd: _roof_texture` |
| Plusk | 90 cząsteczek tylko w pasie wokół lokalnego gracza | `_rain_splash` |
| Mokry świat | **brak**: grunt, deski, metal, postacie bez zmian; bez kałuż, kręgów na wodzie, okapów i kapania z dachów | — |
| Wiatr | `Level3D.set_wind(amp, lean)` — korony i runo; podmuchy tylko w burzy (sinusy `_life`), kierunek zawsze z prawej | `view3d.gd`, `level3d.gd: _wind` |
| Niebo | zachmurzenie, dryf chmur, gwiazdy, tarcza księżyca wg pogody; błysk rozświetla chmury, **bez kanału pioruna** | `level3d.gd: SKY_SHADER` |
| Błysk burzy | harmonogram z ziarna co 9–24 s; FULL dwa impulsy, REDUCED miękka poświata 0,4; plan gry tylko 12% (`FLASH_PLANE`), las w pełni (`StormFlash`) — **wrogowie odcinają się sylwetką** na jasnym lesie, pas gry ok. ×8; **dno lasu wygląda jak śnieg** (także przy 0,4) | `weather_fx.gd: _flash`, `view3d.gd` |
| Mgła | bryła mgły ×10, **własna emisja** podnosi czerń (mgła jaśniejsza niż pogodna noc), na LOW bez `FogVolume` (prawie znika) — gracze co-op z różną jakością widzą inną scenę | `view3d.gd`, `level3d.gd:4165` |
| Zmienność | pogoda **stała przez całą misję**, bez narastania i przejaśnień | `weather.gd` |
| Tłumaczenie | „NO EFFECTS” brak w `translations/ui.csv` (HUD: „POGODNA NOC · NO EFFECTS”) | `weather.gd: KINDS.clear.short` |

### 2.2 Dźwięk

| Obszar | Fakt | Gdzie |
|---|---|---|
| Deszcz | dwie pętle **16 s** stereo (`amb_rain` — „rain_hard_loop”, `amb_rain_roof` — „rain_on_plastic”), niepozycyjne; jedna intensywność; pętla 16 s wraca ok. 225 razy na godzinę (las z tego powodu ma 60 s) | `weather_fx.gd: AUDIO`, `bake_hybrid.py: AMB_LOOPS` |
| Pod ziemią | deszcz −14 dB, bez filtra (powinien być głuchy, nie tylko cichszy) | `UNDERGROUND_DB` |
| Wiatr | jedna pętla 16 s (`amb_wind`, „wind_mountain_loop”), głośność stała w czasie; podmuchy `amb_gust` i skrzypienie `amb_creak` to losowe emitery **niezależne od pogody** (grają tak samo w pogodną noc) i od podmuchów w obrazie | `audio_director.gd: EMITTERS` |
| Grzmot | 3 nagrania **mono, przycięte do ok. 6 s** (prawdziwy grzmot toczy się 10–30 s); opóźnienie 0,5–4 s losowane niezależnie od siły błysku; tylko głośność zależy od odległości (bez filtra, bez kierunku) | `weather_fx.gd: _thunder`, `bake_hybrid.py: THUNDER_SRC` |
| Kroki | w deszczu pod niebem dodatkowy plusk `step_water` (dobre) | `audio_director.gd:650` |
| Materiały | `surface_at` zna metal / ziemię / beton / wodę — gotowe do kropel na materiałach | `audio_director.gd:618` |
| Biblioteka | lokalny Sonniss (`C:\deadair87\audio_lib`): ok. 240 pozycji z deszczem, ok. 250 z wiatrem, ok. 40 grzmotów (m.in. Borg Sound „Rain Indoor Ambiences” — blaszany dach, Double Trouble Audio „Rain and Thunder”, Soundrangers „Thunder” — dalekie, Hzandbits „Howling Winds — Interior” — świst w oknach, Faunethic — krople na liściach) | `_index/*.json` |

## 3. Inspiracje z popularnych gier

| Gra | Co robi | Co bierzemy | Czego nie |
|---|---|---|---|
| **Hunt: Showdown** (Thundershower, 2025) | deszcz z emiterów punktowych: promienie z nieba wokół gracza, w miejscu trafienia emiter kropel na materiale (drewno, metal, kamień, liście) + cicha warstwa przestrzenna; wiatr, podmuchy, jęczące drzewa, dalekie grzmoty; mokre kroki; budynki skrzypią, kapie przez szczeliny, wiatr wyje w drzwiach i oknach; wszystko skaluje się z siłą burzy, która zmienia się w cyklu; mgła gęstnieje z burzą; deszcz maskuje kroki | cały model dźwięku deszczu (W2) — w 2D to tanie: „promień” = kolumna kafli; cykl siły (W1); okna i szczeliny (W3) | maskowanie, które zabija dźwięk w rozgrywce (gracze Hunta narzekali, że dźwięk przestaje się liczyć) — ważne sygnały mają pierwszeństwo w miksie |
| **Escape from Tarkov** | deszcz zmienia słyszalność ruchu, mgła ogranicza widzenie; po ankiecie (66% graczy: ulewa przeszkadza) twórcy ściszyli deszcz | priorytet sygnałów nad deszczem, osobny suwak głośności pogody (D4) | — |
| **Red Dead Redemption 2** | ślady w błocie wypełniają się wodą, błoto i brud zasychają na ubraniu | mokry świat i postacie (W6), błoto na butach (system urobku na stroju z kopania) | zużycie / statystyki od przemoczenia (nowa warstwa — §16.0a) |
| **Metro (Last Light, Exodus)** | deszcz, błoto i krew na szybce maski, wycieranie klawiszem | krople i strugi na szybce maski gazowej **postaci** (model 3D), dźwięk kropel na masce w miksie gracza | krople na ekranie i wycieranie — kamera jest z boku, nie z oczu |
| **Zelda: Breath of the Wild** | deszcz gasi ogień i utrudnia wspinaczkę, pioruny w metal | deszcz skraca palenie gniazd i plam ognia pod gołym niebem (W8 / G3) | piorun w metal, śliskie ściany — losowa kara, nieczytelna w co-op |
| **Rain World** | deszcz = licznik cyklu; minutę wcześniej tło ciemnieje, 30 s przed — drgania i dźwięk ulewy | zapowiedź zmian pogody (przyciemnienie, wiatr, daleki grzmot) zanim nadejdzie ulewa (W1) | deszcz jako zegar śmierci — nowy system |
| **S.T.A.L.K.E.R. 2** | emisja: czerwone niebo, ostrzeżenie radiowe, schronienia | ostrzeżenie radiowe przy prognozie (radiostacja już jest) | emisja — po 1.0, ewentualnie modyfikator Nocnego Dyżuru |
| **Ghost of Tsushima** | wiatr wskazuje cel zamiast HUD-u | (opcja) liście i mgła dryfują w stronę ekstrakcji po wykonaniu celu — zgodne z „brak minimapy” (§14) | — |
| **Celeste** | wiatr jako siła w skoku | — | zmienia sterowanie, frustruje, w co-op nieczytelny |

Praktyka dźwięku (Wwise / Audiokinetic, „Designing Sound”, Vessel GDC 2012): deszcz składać z warstw (wysokie „wrzenie”, średnie, szum
stereo, pojedyncze krople) sterowanych jednym parametrem intensywności; grzmot = trzask (tylko blisko) + ciało + długi, nierówny
pomruk, z opóźnieniem odległość / 343 m/s i filtrem dolnoprzepustowym rosnącym z odległością.

## 4. Zasady

1. **Ciemność to mechanika (§8.3).** Pogoda nie może trwale rozjaśniać planu gry. Mgła jest widoczna tam, gdzie świeci światło, a nie
   świeci sama; błysk rozświetla niebo i las, ale nie zamienia ich w tło do odcinania sylwetek (albo — D1 — robi to uczciwie dla obu stron).
2. **Co-op bez RPC.** Cały stan pogody (siła w czasie, wiatr, podmuchy, błyskawice z odległością i kierunkiem) liczy się z
   `Weather.seed` i `mission.elapsed` — jak dziś harmonogram błysków. Dołączający widzi to samo.
3. **Parytet jakości.** Gracze na LOW i HIGH widzą podobną widoczność (różnica mediany jasności pasa gry ≤ 3/255); LOW traci detal,
   nie mgłę.
4. **Dostępność.** REDUCED (domyślne): bez ostrego błysku i kanału pioruna. OFF: bez cząsteczek i błysków, **mgła zostaje** (D3).
   Napisy: „[Grzmot — blisko, z lewej]”. Drgania ekranu przy grzmocie tylko z ustawieniem `shake`.
5. **Miks: sygnały przed pogodą.** Stalker, zapowiedzi ataków, krzyki wrogów, radio i podpowiedzi ściszają pogodę o 4–6 dB
   (sidechain), żeby ulewa nie robiła tego, na co narzekali gracze Tarkova i Hunta.
6. **Licencje (AUDIO_PLAN.md).** Nagrania tylko w `prototype/audio_licensed/` (poza repo); każdy nowy klucz ma wersję publiczną
   (synteza warstwowa albo Stable Audio) o zmierzonej głośności równej wersji z nagrań. Każda rodzina przechodzi odsłuch A/B
   u użytkownika przed podmianą.
7. **Budżet.** Cała pogoda na HIGH 4K: ≤ +1,0 ms GPU, MEDIUM ≤ +0,6, LOW ≤ +0,3; CPU ≤ +0,5 ms; mgła ≤ +100 MB VRAM (dziś +286);
   nowe nagrania ≤ 25 MB w buildzie (Ogg, strumieniowane).
8. **Zakres (§16.0a).** W0–W7 nie zmieniają rozgrywki ani mnożników. Nowe mechaniki — tylko W8, po playteście i decyzji użytkownika.

## 5. Etapy

Każdy etap to osobny PR (wersja w `project.godot`, wiersz w `CHANGELOG.md`), zrzuty przed / po z tej samej klatki, `--perf` przed / po.
W2–W4 (dźwięk, `weather_fx.gd`, `audio_director.gd`) i W5–W7 (obraz, `view3d.gd`) dotykają różnych plików — mogą iść równolegle po W1.

### W0. Pomiar i drobiazgi (0,5 d)

- `--weathertest` (headless): harmonogramy z ziarna identyczne u dwóch instancji, siła, wiatr, błyskawice; przejścia kryjówka ↔ misja.
- Zrzuty: `--shotweather=ID --weathert=S` (chwila w krzywej pogody), `--shotflash=K` (jest); skrypt serii (4 pogody × LOW/HIGH × błysk)
  z metrykami z §6 zapisanymi do `map_analysis/weather/`.
- Tłumaczenie „NO EFFECTS” → „BEZ EFEKTÓW”.

### W1. Wspólny zegar pogody (1 d)

`weather_fx.gd` zamiast stałej siły liczy z ziarna:
- **Siłę `I(t)`** 0..1: fronty po 2–5 min — narastanie, ulewa, przejaśnienie (deszcz 0,35–1, burza 0,6–1, mgła falami gęstości 0,5–1).
  Przed ulewą zapowiedź (Rain World): wiatr rośnie, chmury gęstnieją, daleki grzmot w burzy.
- **Wiatr `W(t)`**: kierunek misji (lewo / prawo z ziarna) i siła bazowa wg pogody, plus lista podmuchów (czas, siła, długość 2–6 s).
- **Błyskawice**: czas, odległość 0,3–8 km, azymut (lewo / prawo / przód), siła z odległości.
Mnożniki rozgrywki zostają stałe (D2). Wszystkie odbiorniki (obraz, dźwięk, wiatr roślin, dym flar) czytają ten sam stan.

### W2. Dźwięk deszczu (2–3 d + odsłuch)

1. **Tło przestrzenne**: trzy warstwy intensywności (lekki, średni, ulewa) przenikane wg `I(t)`; pętle ≥ 60 s, w parach o długościach
   względnie pierwszych (np. 61 s + 47 s), żeby nie było słychać powtórki.
2. **Emitery punktowe (Hunt w 2D)**: co 0,2 s kolumny ±12 kafli od słuchacza; pierwsza bryła od góry (ta sama tablica co `_roof_texture`)
   → materiał (`surface_at`: metal, drewno / deski, ziemia, beton, woda, korony nad otwartym lasem). Pula 6–8 `AudioStreamPlayer2D`
   z pętlami kropel na materiale stoi nad najbliższymi zmianami materiału → panorama i istniejąca okluzja za darmo.
3. **Pod dachem**: deszcz na dachu nad głową z materiału dachu (blacha bębni, deski głucho), kapanie przez dziury w deskach
   (dziury z `DESTRUCTION_PLAN.md` już są w danych) i z okapów — emiter strumienia na kolumnie przejścia dach / niebo.
4. **Pod ziemią**: filtr dolnoprzepustowy (ok. 400 Hz) zamiast samego −14 dB.
5. **Blisko gracza**: krople na masce gazowej i kapturze (cicha warstwa, tylko lokalny gracz), szelest mokrego stroju przy ruchu,
   mokre kroki (są).
6. **Sidechain** wg zasady 5; osobny suwak „Weather” w ustawieniach dźwięku (D4).
Źródła: Borg Sound „Rain Indoor Ambiences” (blacha), Faunethic (liście), Double Trouble Audio, Pole Position „Thunder & Rain”;
wersja publiczna — synteza warstwowa (szum + krople) z `bake_audio.py`.

### W3. Wiatr (1,5–2 d + odsłuch)

- **Tło**: trzy warstwy (niski pomruk, korony drzew, świst) sterowane `W(t)` — głośność i filtr; pętle ≥ 60 s.
- **Podmuchy** z harmonogramu W1 jednocześnie w obrazie (pochylenie trawy, trzciny, koron, kąt deszczu, dryf mgły i dymu flar,
  liście i igliwie w powietrzu) i w dźwięku (podmuch z panoramą z kierunku wiatru, narastanie przed szczytem).
- **Budynki**: świst w oknach i szczelinach (grupa `windows`; stłuczona szyba gwiżdże głośniej), skrzypienie konstrukcji, łopot plandek.
- `amb_gust` / `amb_creak` ważone siłą wiatru (w ciszy prawie znikają, w burzy częstsze), zamiast stałych wag w `EMITTERS`.
Źródła: Hzandbits „Howling Winds — Interior / Urban Winds”, Ivo Vicic „Wind in pines” (rezerwa z odsłuchu lasu).

### W4. Grzmot i błyskawica (2 d + odsłuch)

- **Dźwięk**: warstwy trzask (tylko < 1,5 km) + ciało + długi pomruk 8–20 s z nierównymi „przetoczeniami”; opóźnienie = odległość / 343 m/s
  (przycięte do 0,3–12 s); filtr dolnoprzepustowy i głośność z odległości; panorama z azymutu; pogłos lasu. 6–9 wariantów zamiast 3,
  stereo. W budynkach filtr i drżenie szyb (krótki dźwięk), w podziemiach pył z sufitu przy bliskich (system kropel i pyłu z kopania).
- **Obraz**: siła i ostrość błysku z odległości (blisko: krótki, ostry, z cieniami z kierunku `StormFlash`; daleko: miękka poświata
  chmur od strony azymutu, bez trzasku). Kanał pioruna w shaderze nieba (2–4 klatki, tylko blisko i tylko FULL).
- **Poprawki z analizy**: dno lasu w błysku ciemniejsze i mokre (koniec „śniegu”); sylwetki wrogów wg D1.
- Napisy z kierunkiem i odległością.
Źródła: Soundrangers „Thunder”, Double Trouble Audio „Rain and Thunder”; wersja publiczna — synteza pasmowa (trzask, środek, pomruk, sub).

### W5. Deszcz w obrazie (2 d)

- Krople **oświetlane**: materiał z podświetleniem zamiast `unshaded` — świecą w snopie latarki, przy lampach, flarach i w błysku, a w
  ciemności są ledwo widoczne.
- Trzy plany głębi: blisko (grubsze, rozmyte, rzadkie), środek, daleko (gęsta zasłona tonąca w mgle głębi). `GPUParticles3D` zamiast
  CPU, gęstość burzy na ekranie ×2–3 przy tym samym koszcie; gęstość i kąt z `I(t)` i `W(t)`.
- Plusk na każdej poziomej powierzchni pod niebem w kadrze, strugi z okapów, kręgi na wodzie (normalna w shaderze wody wg `I(t)`).
- LOW: jeden plan, mniej kropel, bez plusku poza graczem.

### W6. Mokry świat (2–3 d)

- Maska otwartego nieba (z tekstury dachów) w materiałach gruntu, desek, metalu i skał: ciemniejsze albedo, niższa szorstkość,
  kałuże w płaskich miejscach (szum × maska) z odbiciem latarki i lamp — w nocy to największy zysk imersji.
- Narastanie ok. 90 s od początku deszczu, schnięcie przy przejaśnieniu (W1).
- Postacie: strój pod niebem ciemnieje i błyszczy, krople spadają po wejściu pod dach, strugi na szybce maski, błoto na butach
  (warstwa urobku na stroju z `DESTRUCTION_PLAN.md` D5).

### W7. Mgła na nowo (2 d)

- Bez własnej emisji podnoszącej czerń; widoczność mgły z halo lamp, snopa latarki i flar (zgodnie z §8.3).
- Ławice mgły dryfujące z wiatrem, gęstsza w zagłębieniach i nad wodą, falami wg `I(t)`.
- LOW: zamiennik bez `FogVolume` (bliższa mgła głębi + karty mgły przy ziemi) — parytet z zasadą 3.
- VRAM: bryła symetryczna tylko na HIGH albo pas o niższej rozdzielczości (cel ≤ +100 MB).
- Dźwięk: dalekie dźwięki świata przytłumione filtrem (spójne z „hałas −15%”), kapanie z gałęzi, cisza lasu.

### W8. Mechaniki z inspiracji (po playteście, każda osobno, decyzja użytkownika)

| # | Mechanika | Źródło | Uwagi |
|---|---|---|---|
| G1 | Grzmot jako okno hałasu: strzał do 1,5 s po bliskim grzmocie ma hałas ×0,5 | Hunt | pasuje do §8.4 „hałas jako zasób”; słychać, kiedy jest okno |
| G2 | Bliski błysk odsłania obie strony: wrogowie na chwilę widzą dalej | — | alternatywa D1 dla sylwetek |
| G3 | Deszcz gasi ogień: gniazda, plamy ognia i flary pod gołym niebem palą się krócej | BotW | pod dachem bez zmian — wybór miejsca |
| G4 | Mnożniki hałasu skalują się z `I(t)` zamiast być stałe | Hunt | ulewa maskuje mocniej, przejaśnienie słabiej |
| G5 | Mgła skraca zasięg wzroku wrogów i graczy | Tarkov | dziś mgła zmienia tylko słuch i Stalkera |
| G6 | Liście i mgła dryfują ku ekstrakcji po celu | Ghost of Tsushima | opcja zamiast strzałki kompasu |

Odrzucone: wycieranie maski (Metro — kamera z boku), wiatr jako siła ruchu (Celeste), emisja (STALKER 2) i deszcz-licznik (Rain World)
— nowe systemy poza zakresem EA; ewentualnie modyfikatory Nocnego Dyżuru po 1.0.

## 6. Kryteria akceptacji (mierzone)

| Kryterium | Dziś | Cel |
|---|---|---|
| Mgła HIGH: piksele < 8/255 w pasie gry | 37% | ≥ 75% |
| Mgła LOW vs HIGH: różnica mediany pasa gry | 12/255 | ≤ 3/255 |
| Pełny błysk: mediana pasa gry względem bez błysku | ok. ×8 (0 → 19) | wg D1; dno lasu bez „śniegu” (nasycenie barwy jak w świetle księżyca) |
| Krople w kręgu latarki vs w ciemności (jasność) | 1× | ≥ 3× |
| Gęstość deszczu burzy na ekranie (smug / Mpx) | zmierzyć w W0 | ×2–3 |
| Najkrótsza pętla pogody w miksie | 16 s | ≥ 60 s, bez słyszalnej powtórki w 2 min (odsłuch) |
| Grzmot: długość ogona, liczba wariantów | 6 s, 3 mono | 8–20 s, 6–9 stereo |
| Koszt GPU całej pogody (HIGH 4K) | ok. 0 ms | ≤ +1,0 ms |
| VRAM mgły | +286 MB | ≤ +100 MB |
| `--weathertest` | — | PASS (deterministyka, dołączający) |

## 7. Decyzje użytkownika

| # | Pytanie | Warianty | Wybrane (2026-11-15) |
|---|---|---|---|
| D1 | Sylwetki wrogów w błysku | (a) przyciemnić tło za planem gry; (b) zostawić i opisać w karcie burzy; (c) G2 — obie strony | (a) teraz, (c) do playtestu |
| D2 | Czy siła pogody zmienia mnożniki | (a) tylko obraz i dźwięk; (b) G4 od razu | (a) |
| D3 | Ustawienie OFF a mgła | (a) mgła zostaje; (b) OFF wyłącza wszystko | (a) — sprawiedliwość w co-op |
| D4 | Suwak „Weather” w dźwięku | tak / nie | tak |
| D5 | Krople na masce i plusk kroków innych graczy | tylko lokalny / wszyscy | lokalny (maska), wszyscy (kroki) |
| D6 | Kolejność | dźwięk (W2–W4) najpierw / obraz (W5–W7) najpierw / równolegle | równolegle po W1 |

## 8. Szacunek i kolejność

W0 0,5 d → W1 1 d → równolegle: dźwięk W2 + W3 + W4 (5,5–7 d + odsłuchy) oraz obraz W5 + W6 + W7 (6–7 d) → playtest → W8.
Razem ok. 13–16 dni pracy przed W8.

## 9. Źródła

- Hunt: Showdown — „Behind the Storm: Technical Design of Thundershower” (2025-08-15): https://huntshowdown.com/news/behind-the-storm-technical-design-of-thundershower-in-hunt-showdown
- PC Gamer o deszczu w Hunt: https://www.pcgamer.com/our-favorite-extraction-shooter-just-got-an-update-that-adds-its-greatest-enemy-yet-rain
- Tarkov, ankieta o głośności deszczu: https://consolepcgaming.com/escape-from-tarkov-will-adjust-rain-volume-in-upcoming-update
- PC Gamer, „What weather adds the most to a game”: https://pcgamer.com/what-weather-adds-the-most-to-a-game
- Metro, wycieranie maski: https://metrovideogame.fandom.com/wiki/Gas_Mask
- Zelda BotW, pogoda: https://zelda.fandom.com/wiki/Weather
- Rain World, deszcz: https://rainworld.miraheze.org/wiki/Rain
- STALKER 2, emisja: https://stalker.fandom.com/wiki/Emission
- Ghost of Tsushima, symulacja wiatru: https://gamedeveloper.com/design/using-vorticles-to-simulate-wind-in-i-ghost-of-tsushima-i-
- Celeste, Golden Ridge: https://celestegame.fandom.com/wiki/Chapter_4:_Golden_Ridge
- Audiokinetic, „Generating Rain With Pure Synthesis”: https://www.audiokinetic.com/en/blog/generating-rain-with-pure-synthesis/
- Farnell, „Designing Sound” — grzmot: https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/8375/designing_sound.zip/practical17.html
- RDR2, efekty pogody (relacje): https://gamingbolt.com/red-dead-redemption-2-tech-analysis-animations-physics-post-processing-effects-weather-systems-and-more
