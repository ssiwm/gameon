# Gablota na broń w kryjówce — projekt do akceptacji

**Stan (2026-10-14):** przyjęty zgodnie z rekomendacjami (dwie gabloty po 4 broni, tło A grafit, wybór wg opcji 1, półka jako dekoracja, przed playtestem) i wdrożony w 1.7.219. Odstępstwo od §4 E1: bryła gabloty powstaje w Godocie z prostych brył i materiałów (`view3d.gd _build_cabinet`), nie skryptem w Blenderze — rzędy, światło i drzwi stroi się bez wypieku, wygląd jak na makiecie.

Wzór: dwa zdjęcia od użytkownika (2026-10-14): szafa ze ścianą listwową (slatwall), broń zawieszona poziomo na hakach w rzędach, punkty LED w daszku
rzucają na tło plamy światła i cienie broni, szklane drzwi, na dole półka z pistoletami i magazynkami. Makieta (Godot, modele broni z gry,
naturalna skala): `build/anim_review/gablota_widok_gry.png` (widok z kamery gry) i `build/anim_review/gablota_warianty.png` (zbliżenie, trzy kolory tła).

## 1. Stan dziś

- 8 osobnych stojaków (`g` w `scripts/maps/z1_hub.gd`), co 6 kafli (ok. 7,9 m) wzdłuż tylnej ściany, na każdym jedna broń (`WEAPONS`: SPREAD-12,
  PELLET-8, LR-7, HKM-9, WRATH-4, SPECTER-1, FALCON-6, SINEW-6). Deska ok. 1,6 m, lampa wisząca, kłódka i mosiężna tabliczka z ceną, gdy broń
  jest zamknięta (`view3d.gd _sync_guns`).
- Wybór: gracz staje przy stojaku, [E] = oględziny (kamera przechodzi do widoku z oczu, broń się kołysze, panel ze statystykami w HUD), potem
  zamiana broni albo odblokowanie za złom (`Scrap`).
- Od 1.7.218 broń na stojaku ma naturalną długość — na desce wygląda skromnie; gablota rozwiązuje to docelowo.

## 2. Propozycja

**Dwie gabloty obok siebie** na tylnej ścianie kryjówki zamiast ośmiu stojaków:

| | |
|---|---|
| Wymiary | 1,7 m szer. × 2,1 m wys. × 0,42 m gł. (postać 1,8 m; najdłuższa broń SPECTER-1 1,15 m mieści się z zapasem) |
| Gablota 1 „Karabiny · strzelby” | SPREAD-12, PELLET-8, FALCON-6, LR-7 |
| Gablota 2 „Broń specjalna” | HKM-9, WRATH-4, SPECTER-1, SINEW-6 |
| Układ | 4 rzędy co 36 cm (jak na zdjęciu 2), broń poziomo, lufą w prawo, na dwóch czarnych hakach; mosiężna tabliczka pod każdą |
| Półka na dole | P-64 (broń podręczna), magazynki, skrzynka amunicji — dekoracja, jak pistolety i magazynki na zdjęciu 2 |
| Korpus | stal malowana proszkowo na czarno, daszek z napisem (szablon), cokół; zamek szyfrowy z zieloną diodą z boku |
| Drzwi | jedno skrzydło szklane (w makiecie dwa — do zmiany), lekkie odbicia z istniejącej sondy odbić kryjówki |
| Światło | 3 ciepłe punkty LED (ok. 3000 K) w daszku na gablotę, z cieniami — plamy na tle i cienie broni jak na zdjęciu 1; zastępują lampy wiszące nad stojakami |

**Kolor tła (do wyboru, makieta: `gablota_warianty.png`):**
- **A — grafit / karbon** (zdjęcie 2): broń najczytelniejsza, klimat „zbrojownia”. *Rekomendacja.*
- **B — filc bordowy** (najbliżej fioletu ze zdjęcia 1, w palecie gry): najbardziej „ekspozycyjny”, ciepły, mocno odcina drewno kolb.
- **C — filc oliwkowy**: wojskowy, ale broń z oliwkową stalą (HKM-9) zlewa się z tłem.

**Stany broni w gablocie:**
- dostępna — pełne światło LED;
- zamknięta — przyciemniona, czerwona plomba na kabłąku, na tabliczce cena w złomie (zamiast kłódki);
- trzymana teraz przez gracza — pusty hak i jaśniejszy ślad na filcu (widać, czego brakuje);
- wybrana — mocniejsze światło nad nią i broń wysunięta kilka centymetrów ku szybie.

## 3. Wybór broni — decyzja potrzebna

Gablota trzyma 4 broni jedna nad drugą, więc „stań przy stojaku” przestaje wystarczać.

- **Opcja 1 (rekomendacja): oględziny gabloty.** Podejście + [E] → kamera przechodzi na wprost gabloty (kadr jak na zdjęciach), drzwi się
  uchylają; wybór strzałkami / gałką / myszą, wybrana broń się wysuwa, panel statystyk jak dziś; [E] bierze, odblokowanie za złom jak dziś;
  wyjście [Esc] albo odejście. Wykorzystuje istniejący tryb oględzin (`_fp`, `inspect_item`).
- **Opcja 2: celowanie w broń z widoku gry** (najbliższa celownikowi w zasięgu gabloty). Mniej pracy, ale w widoku gry broń w gablocie ma
  kilka pikseli wysokości — trudno trafić i nic nie widać.

W obu opcjach zamiana broni idzie dotychczasowym RPC (serwer waliduje), a w symulacji 2D gablota to zestaw punktów broni — sieć się nie zmienia.

## 4. Wykonanie

| Etap | Zakres | Szacunek |
|---|---|---|
| E1 | Model gabloty skryptem w Blenderze jak `gun_proc.py` (bryły z fazami, wypiekane PBR: stal proszkowa, filc / karbon, szkło, LED) → `art/items3d/cabinet.glb`; rozmieszczenie w kryjówce (nowy znak mapy zamiast 8 × `g`), broń na hakach, światło | 1 dzień |
| E2 | Interakcja wg opcji 1 lub 2; stany broni (zamknięta, trzymana, wybrana); dźwięki (szklane drzwi, hak) | 1–2 dni |
| E3 | Test (`test_proportions.gd`: wymiary gabloty, broń mieści się w rzędach), zrzuty, aktualizacja `README.md` / `GDD.md` (kryjówka) | 0,5 dnia |

Ryzyka: zmiana układu kryjówki (8 stojaków → 2 gabloty) skraca chodzenie między bronią — dekoracje na pustej ścianie (`hub_decor.gd`)
trzeba rozłożyć na nowo; tryb oględzin trzeba przerobić z „jedna broń” na „gablota + wybór”.

## 5. Do akceptacji

1. Dwie gabloty po 4 broni (czy jedna szeroka na 8)?
2. Kolor tła: A, B czy C?
3. Wybór broni: opcja 1 czy 2?
4. Półka: P-64 i magazynki jako dekoracja (czy np. przyszłe odblokowania broni podręcznej)?
5. Czy robić przed playtestem?
