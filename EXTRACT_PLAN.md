# Plan: redesign punktu ewakuacji z flarą („zielona flara”)

Status: **plan z 2026-10-10, nic jeszcze nie wdrożone.** Zakres: wyłącznie warstwa wizualna, dźwiękowa i komunikacja punktu wyjścia
(`mission.gd` — `_draw`, HUD, audio). Reguły ekstrakcji (cała drużyna na nogach w strefie przez 3 s, `EXTRACT_TIME`, `EXIT_RADIUS_X/Y`)
**zostają bez zmian**, żeby nie ruszać balansu ani sieci; ewentualne zmiany rozgrywki są w §9 jako osobne decyzje.

Referencja do porównań: zrzut z misji 1.1 (finał „kopalnia się wali”, flara po wspinaczce szybem), trzymany lokalnie poza repo.

## 1. Cel

Punkt wyjścia ma być **najjaśniejszym, najbardziej czytelnym miejscem na mapie** i jednocześnie wyglądać jak część tego świata — jedna
fizyczna flara wbita w ziemię i jej światło — a nie jak neonowa bramka interfejsu. Gracz ma:

1. widzieć go z daleka i wiedzieć, w którą stronę iść (także gdy leży poza kadrem),
2. rozumieć, gdzie kończy się strefa (promień 34 px) bez „ścian” z geometrii,
3. widzieć w świecie postęp ekstrakcji i kogo brakuje, nie tylko pasek w HUD,
4. czuć napięcie finału (zawalenie kopalni), a nie oglądać ten sam, spokojny rysunek.

## 2. Stan obecny (z kodu)

| Element | Gdzie | Jak jest zrobiony |
|---|---|---|
| Strefa | `mission.gd`, `_draw` | trzy eliptyczne „kałuże” światła, pulsujący pierścień, **przerywana zielona linia** na ziemi co 6 px (animowana) |
| Granice strefy | `_draw` | dwa **L-kształtne wsporniki** z jasną kropką po obu stronach (`hd_flare`: polilinia 6 px / 2 px) |
| Słup światła | `_draw` | 6 warstw trapezów (HD) o malejącej szerokości, 170 px wysokości, zieleń `(0,4; 1,0; 0,5)` |
| Flara | `ItemsHd.draw(..., "flare_stuck")` + `_draw_flame_hd` | model HD wbity w ziemię, płomień z trzech warstw, iskry (9 cząstek o stałych fazach) |
| Światło | `mission.gd`, `_flare` (`PointLight2D`) | energia 1,0 ± 0,2, bez cieni |
| Komunikacja | `objective_text`, `objective_hint`, `local_extract_state` | tekst „Reach the green flare ← 3 m”, wskazówka i pasek kontekstowy w HUD |
| Finał | `mission.gd` (`finale`, `FINALE_DELAY`) | „kopalnia się wali” — tekst + trzęsienie; flara jest ta sama co w zwykłej ekstrakcji |
| Dźwięk | — | brak dedykowanego dźwięku flary wyjścia (jest tylko ogólny alarm / muzyka) |

Rysowanie odbywa się co klatkę w `_draw` węzła misji (`queue_redraw()` w `_physics_process`), więc wszystko jest lokalne i tanie,
ale nie korzysta z istniejących klocków atmosfery (smuga `light_shaft.gd`, pył, cienie).

## 3. Diagnoza (co nie gra)

1. **Dwa języki wizualne naraz.** Flara to analogowy, „brudny” przedmiot (czerwona tuba, płomień), a wokół niej jaskrawe, geometryczne
   wsporniki i kropki jak w UI. Wsporniki wyglądają jak bramka sci-fi i konkurują z flarą o uwagę.
2. **Zbyt wiele równorzędnych elementów:** słup światła, trzy kałuże, pierścień, przerywana linia, wsporniki, płomień, iskry. Nic nie
   jest wyraźnie „głównym” — a światło zalewa całe otoczenie jednolitą zielenią, spłaszczając scenę.
3. **Strefa jest narysowana, nie wynika ze świata.** Granica to linia i wsporniki; nie ma cieni ani kształtu światła, który mówiłby
   „tu jest bezpiecznie”.
4. **Brak informacji zwrotnej w świecie.** Postęp 3 s i to, kogo brakuje, widać tylko w HUD; w kadrze nic się nie zmienia, gdy ktoś
   wchodzi lub wychodzi ze strefy.
5. **Poza kadrem tylko tekst.** Kierunek i odległość w HUD, bez wskaźnika na krawędzi ekranu i bez sygnału dźwiękowego.
6. **Finał bez dramaturgii.** Ta sama spokojna flara przy zawalającej się kopalni; światło nie reaguje na kurz ani drgania.
7. **Zieleń jako jedyny nośnik znaczenia** — słabe wsparcie dla osób z zaburzeniami widzenia barw.

## 4. Zasady projektu

- **Jedno źródło prawdy: fizyczna flara.** Wszystko inne to jej światło i dym, a nie osobne „elementy interfejsu”.
- **Strefa = kałuża światła ze świata** (granica z oświetlenia i kilku fizycznych znaczników), nie linie i wsporniki.
- **Hierarchia:** 1) płomień i rdzeń światła, 2) postęp ekstrakcji, 3) słup światła/dymu, 4) reszta. Nic nie zasłania postaci ani celu.
- **Język horroru:** zimna czerń wokół, jeden ciepło-zielony punkt, który **pachnie bezpieczeństwem, ale nie jest ciepły**; światło
  ma migotać nieregularnie (nigdy sinusoidą).
- **Kosmetyka lokalna:** żadnych nowych RPC; wszystko wynika z replikowanych `phase`, `exit_pos`, `extract_progress` i pozycji graczy.
- **Poziomy jakości** (`Settings.quality_idx`) i „Reduce effects” wpływają na efekty ruchome, ale **nigdy na czytelność** punktu.

## 5. Elementy redesignu

| # | Element | Opis | Pliki | Kryterium akceptacji |
|---|---|---|---|---|
| X1 | **Flara jako obiekt** | osobny węzeł `exit_flare.gd` zamiast rysunku w `_draw` misji: model `flare_stuck`, płomień z nieregularnym migotaniem (szum, nie sinus), żarzące się iskry, mały rozbryzg żaru i dym unoszący się z tuby | nowy `exit_flare.gd`, `mission.gd`, `vfx.gd` | płomień nie jest nigdy identyczny w dwóch kolejnych sekundach; dym i iskry zależne od jakości |
| X2 | **Światło z cieniami** | `PointLight2D` flary z cieniami (postaci i skały rzucają cień na ziemię), dwie warstwy: ciepłozielony rdzeń + szeroka, słaba poświata; pulsuje nieregularnie, przy kurzu w finale przygasa | `exit_flare.gd`, `lights.gd` | cień gracza w strefie pada od flary; światło nie przepala sprite'ów (energia ≤ 1,2) |
| X3 | **Słup światła i dymu** | zamiast sześciu trapezów: stożek z `light_shaft.gd` (szum, kurz w smudze) w kolorze flary, węższy i niższy niż dziś (ok. 110 px), przechodzący w kolumnę dymu wyżej | `light_shaft.gd` (parametr koloru), `exit_flare.gd` | słup widoczny z jednego kadru dalej, ale nie zalewa tła zielenią |
| X4 | **Granica strefy z fizycznych znaczników** | zamiast L-wsporników i linii: 6–8 małych **kołków / łuczyw chemicznych** wbitych w ziemię na brzegu elipsy (modele HD z potoku przedmiotów, krótkie, każdy z własnym punktowym światełkiem), nieregularnie rozstawione | `tools/concept/items_proc_bake.py` (`stake`), `exit_flare.gd`, `items.json` | strefa czytelna bez linii; po wejściu do środka kołki jaśnieją |
| X5 | **Postęp w świecie** | gdy ktoś stoi w strefie: **pierścień-łuk** rośnie wokół podstawy flary 0 → 360° przez 3 s (jak zegar), flara jaśnieje i dźwięk narasta; po jego wyjściu łuk cofa się; **brakujący gracze** mają nad głową cienką kropkę w kolorze slotu, aż wejdą | `exit_flare.gd`, `mission.gd` (odczyt `extract_progress`, lista graczy), `player.gd` (opcjonalna kropka) | w 2-osobowej drużynie widać, kto blokuje wyjście, bez patrzenia w HUD |
| X6 | **Wskaźnik poza kadrem** | strzałka na krawędzi ekranu z odległością w metrach (kolor flary, przygaszona, pulsuje wolniej, im bliżej); znika, gdy flara jest w kadrze | `hud.gd`, `mission.gd` | strzałka nie zasłania paska broni ani kart drużyny (marginesy HUD) |
| X7 | **Finał (zawalenie)** | w trybie `finale`: kurz sypie się z sufitu na strefę, światło flary mruga wraz z wstrząsami (`Feel.shake`), co kilka sekund odłamki skalne spadają obok (kosmetyka, nie zadają obrażeń), drgające smugi; cały obraz jest ciemniejszy poza kałużą flary | `exit_flare.gd`, `mission.gd`, `vfx.gd` | finał czuć inaczej niż zwykłą ekstrakcję bez zmiany liczby wrogów |
| X8 | **Dźwięk** | pętla syku flary (pozycyjna, zasięg ok. 20 m, ścięta filtrem przez ściany), trzask przy każdym migotnięciu, narastający ton przy postępie ekstrakcji, „whoosh” przy sukcesie; w finale dudnienie | `audio.gd`, `tools/` (generator dźwięków), `mission.gd` | flarę słychać wcześniej, niż widać; poziomy głośności w ramach budżetu miksu |
| X9 | **Dostępność** | kształt i ruch niosą znaczenie, nie tylko zieleń: łuk postępu, kołki, strzałka; sprawdzić czytelność z istniejącym filtrem „Color vision” (`colorblind_fx.gd`: protanopia / deuteranopia / tritanopia) i, jeśli zieleń wypada słabo, przełączyć kolor flary na cyjan-biel przy włączonym filtrze | `exit_flare.gd`, `colorblind_fx.gd` (odczyt trybu) | punkt jest rozpoznawalny w trybie czerni i bieli oraz w trzech filtrach na zrzucie (`--colorblind=1..3`) |

## 6. Poziomy jakości

| Poziom | Co jest włączone |
|---|---|
| LOW | flara (model + płomień), światło bez cieni, kołki bez własnych świateł, łuk postępu, strzałka poza kadrem; bez dymu, bez smugi, bez kurzu i odłamków |
| MEDIUM | + światło z cieniami, słup światła (statyczny), iskry i dym, światełka kołków |
| HIGH | + animowana smuga z kurzem, kurz i odłamki w finale, wstrząsy światła |
| „Reduce effects” | brak wstrząsów, odłamków i migotania światła (stałe, łagodne); postęp, strzałka i kołki bez zmian |

## 7. Etapy

| Etap | Zakres | Pliki | Kryterium | Szac. |
|---|---|---|---|---|
| E0 | **Refaktor bez zmiany wyglądu:** wydzielić rysowanie punktu z `mission.gd::_draw` do `exit_flare.gd` (węzeł tworzony przez misję), przenieść `_flare` | `mission.gd`, nowy `exit_flare.gd` | zrzuty przed/po identyczne; `--maptest`, `--missiontest` PASS | 0,5 d |
| E1 | X1 + X2: flara jako obiekt, nieregularne migotanie, światło z cieniami | `exit_flare.gd` | cień gracza od flary; brak przepalenia | 1 d |
| E2 | X3 + X4: nowy słup i granica z kołków (model `stake` z Blendera) | `light_shaft.gd`, `items_proc_bake.py`, `exit_flare.gd` | strefa czytelna bez linii i L-wsporników (usunięte) | 1,5 d |
| E3 | X5 + X6: łuk postępu, kropki brakujących graczy, wskaźnik poza kadrem | `exit_flare.gd`, `hud.gd` | test 2 graczy: widać, kto blokuje | 1 d |
| E4 | X7 + X8: finał i dźwięk | `exit_flare.gd`, `audio.gd`, generator dźwięków | finał wyraźnie różny od zwykłej ekstrakcji | 1,5 d |
| E5 | X9 + dopracowanie: kolor przy filtrze „Color vision”, jakość, zrzuty A/B, GDD/README | `exit_flare.gd`, dokumentacja | checklista §8 przechodzi | 0,5 d |

Razem ok. **6 dni** (E0 można wdrożyć samodzielnie jako bezpieczny krok).

## 8. Weryfikacja

- **Zrzuty** (`--shot`, `--shotat`; ew. nowy `--shotextract` do ustawienia drużyny w strefie / na jej brzegu): zwykła ekstrakcja (1.2, 1.3), finał
  kopalni (1.1), noc CLEAR, deszcz, mgła, 1 i 4 graczy; porównanie LOW / MEDIUM / HIGH i „Reduce effects”.
- **Checklista czytelności:** punkt widoczny z odległości 1,5 szerokości kadru; granica strefy rozpoznawalna bez kolorów; postęp widoczny
  bez patrzenia w HUD; strzałka poza kadrem nie zakrywa HUD.
- **Testy automatyczne:** `--maptest`, `--missiontest` (przejścia faz bez zmian), `tools/test_weapons.sh` (sieć) — logika się nie zmienia.
- **Koszt:** pomiar `tools/bench_fx.gd` w finale na HIGH (budżet ≤ +1 ms na 4K względem dzisiejszego rysunku).

## 9. Ryzyka i decyzje do podjęcia

| # | Kwestia | Rekomendacja |
|---|---|---|
| D1 | Zostawić reguły ekstrakcji (3 s, cała drużyna)? | **Tak** — zmiana wizualna; ewentualne skrócenie czasu lub „prowadzenie” rannych to osobny temat balansu |
| D2 | Kołki zamiast L-wsporników — czy dodać nowy model? | **Tak**, proceduralny w `items_proc_bake.py` (jak meble kryjówki; brak zależności od Tripo) |
| D3 | Cienie od flary (koszt) | włączyć od MEDIUM; flara jest jednym źródłem, więc koszt jest mały |
| D4 | Osobna opcja palety flary | **Nie** — wystarczy istniejący filtr „Color vision” i kolor flary zależny od trybu, bez nowego ustawienia |
| D5 | Wskaźnik poza kadrem — jedna strzałka czy też zasięg dźwięku | strzałka + dźwięk; żadnego mini-radaru |
| D6 | Czy finał ma też odliczać czas (np. kruszenie sufitu coraz bliżej)? | **Nie** w tym planie: to zmienia presję rozgrywki; do ewentualnego osobnego omówienia |
| R1 | Cienie od światła flary mogą „kłuć” w oczy przy wielu graczach | ograniczyć do `SHADOW_FLARES`-owej puli jak dla flar rzucanych (zob. `flare.gd`) |
| R2 | Kołki zasłaniają nawigację botów / kolizje | wyłącznie kosmetyka, bez kolizji i bez wpływu na nawigację (`nav.gd`) |
| R3 | Nowe dźwięki zwiększają rozmiar assetów | generator procedualny, krótkie pętle (< 200 KB łącznie) |

## 10. Czego ten plan nie obejmuje

Zmiany reguł ekstrakcji, wyboru miejsca wyjścia na mapie (`exits_alt`, wybór najdalszego kandydata w `_open_extraction`), drezyny (`handcar.gd`), ekranu sukcesu i podsumowania
misji oraz grafiki klasycznej (`--classic`), która zostaje przy obecnym, prostym rysunku.
