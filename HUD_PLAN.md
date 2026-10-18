# Plan: HUD minimalny (kierunek: zrzut z New World)

Status: **wdrożone w 1.7.273–1.7.275 (etapy 1–3 w jednym stosie PR-ów)** — broń i sprzęt jako modele 3D, życie i hałas w lewym dolnym rogu,
koledzy w lewym górnym, pasek kierunku z opisem celu, tekst misji w prawym górnym rogu, wygaszanie. Stan z 2026-10-17.
**Zmiana w 1.7.285:** rogi zamienione — hałas (VU-metr, linia NOISE, pogoda, SAFE) w lewym górnym, całe życie drużyny w lewym dolnym
(własny wiersz na górze bloku, koledzy pod nim). Wiersz 4 tabeli poniżej opisuje układ sprzed tej zmiany.
**Zmiana w 1.7.286:** pasek kierunku (wiersz 2) zastąpił rzut mapy `scripts/hud_minimap.gd`: okno ±38 m siatki poziomu z mgłą i tymi samymi znacznikami.
Makieta kierunku (poza repo): `gameon/concepts/hud_minimal/index.html` w głównym checkoucie. Podstawa kodu: `prototype/scripts/hud.gd`.

**Odstępstwa od planu poniżej:** przełącznik CLASSIC / MINIMAL pominięty (jeden układ, bez kosztu podwójnych testów); celownik zostaje
dotychczasowy (rozszerzający się krzyżyk w `weapon_view.gd` niesie informację o rozrzucie — kropka do osobnej decyzji); pasek sterowania
pokazuje się sam tylko profilom do poziomu 2 (`TOAST_LEVEL_MAX`), reszta F1; F1 przywołuje też opis celu; LV i XP tylko po zdobyciu XP;
kryjówka: bez paska kierunku, opis celu i gotowość zostają widoczne cały czas. Nie sprawdzono wzrokowo: kryjówki i bossa w nowym układzie.

## 1. Co robi wzór

Zrzut ma sześć elementów i **żadnej ramki**:

| Miejsce | Element | Zasada |
|---|---|---|
| góra-lewo | nick + jeden cienki pasek | tożsamość i zdrowie w jednej linii |
| góra-środek | kompas z rombami i dystansem | cały kierunek celu w jednej cienkiej linii |
| pod kompasem | „CONTRABAND CACHES / UNDERWAY / ALTA MESA” | tekst bez tła, pojawia się na zmianę zadania i gaśnie |
| góra-prawo | „SOUTH COAST / SILVERADO” | sam tekst, wyrównany do prawej |
| dół-lewo | ikona statusu + cienki pasek | jedno spojrzenie |
| dół-prawo | jedna ramka broni + 3 kafelki z licznikiem i klawiszem pod spodem | jedyne ramki na ekranie to przedmioty, które trzymasz |
| środek | kropka zamiast celownika | |

Wspólna cecha: **kontrast robi światło i cień (winieta u góry i dołu), nie panele**. Typografia w kapitalikach, jeden akcent (pomarańcz) na stan zadania.

## 2. Diagnoza obecnego HUD-u (zrzut 1920×1080, 3 graczy, hałas 6%)

- **6 kart z ramką** (hałas, cel, RUN, drużyna, broń, sprzęt) o tej samej wadze + stały pasek sterowania u dołu = 7 prostokątów i 1 linia tekstu **w spokoju**, kiedy nic się nie dzieje. Pierwsza reguła z UI_PLAN §3 („pusty ekran jest straszniejszy”) nie jest spełniona.
- **Cel** zajmuje najszerszą kartę na górze (OBJ_W 250, 3 poziomy tekstu), choć zmienia się rzadko. Kierunku do celu HUD w ogóle nie podaje, gracz szuka go wzrokiem.
- **Sprzęt rozbity na dwie karty** (`_gear_card` + `_equip_card`) i cztery sloty broni w stałym rzędzie, z czego trzy zawsze puste na zrzucie.
- **RUN** (trudność, zegar, złom, LV, pasek XP, „+XP”) to siedem informacji, z których żadna nie jest potrzebna w trakcie walki.
- **Baner misji** („1.1 MISSING PATROL” + radio) w środku ekranu przykrywa scenę i konkuruje z ostrzeżeniem „SOMETHING IS LISTENING”.
- Co działa i zostaje: VU-metr hałasu (znak firmowy), segmentowe życie, klawisze w kapslach, poziomy T1/T2/T3 i wygaszanie T2 (`_drive_tiers`), paleta kość / krew / lampa.

## 3. Cel

1. Zero ramek i paneli w grze, także wokół broni i sprzętu: modele 3D stoją na tle sceny (cień pod spodem), bez prostokątów.
2. W spokoju na ekranie: życie + hałas, broń, cienki pasek u góry. Reszta ≤ 35% krycia (istniejący T2) albo ukryta.
3. Kierunek celu, odległość i pozycje drużyny w **jednej** linii u góry.
4. Informacje o zadaniu i strefie jako tekst, który pojawia się na zmianę i gaśnie po ok. 6 s.
5. Nie łamać reguł z UI_PLAN: tekst min. 14 px (12 px etykiety) na 720p, kolor nie niesie znaczenia sam, „Reduce effects”, skalowanie SMALL/NORMAL/LARGE, tłumaczenia przez `tr()`.

## 4. Układ docelowy (numery jak w wizualizacji)

| # | Strefa | Zawartość | Zastępuje (w `hud.gd`) |
|---|---|---|---|
| 1 | góra-lewo | **reszta drużyny**: romb w kolorze slotu, nazwa, 4 cienkie segmenty życia; DOWN/REVIVING czerwonym tekstem + cienki pasek wykrwawienia. W solo pusto | wiersze `_squad_box` poza własnym (`_make_squad_row`, `_update_squad_row`) |
| 2 | góra-środek | **pasek kierunku**: cienka linia z podziałką, romb gracza w środku, znaczniki: cel (lampa, wypełniony), wyjście (obrys), koledzy (kolor slotu), powaleni (krew, pulsuje), z dystansem w m. Poza zasięgiem przypięty do krawędzi ze strzałką. Pod nim cienki pasek bossa (nazwa + 4-segmentowy pasek) | `_obj_card` (poza tekstem), `_boss_row`, `taken_arrow.gd` (logika zostaje) |
| 2b | pod paskiem | **toast celu**: nazwa celu (stencil), stan w lampie („0 / 4”), szept (Special Elite), linia „1.1 · MISSING PATROL”. Pokazuje się przy zmianie celu / fazy, gaśnie po ok. 6 s; przytrzymanie klawisza „cel” przywołuje go z powrotem | `_obj_caption`, `_obj_text`, `_obj_hint`, baner w `_build_center` (`_warn`, `_warn_sub`) |
| 3 | góra-prawo | **strefa jako tekst**: nazwa misji (stencil), „1.1 · NORMAL · 00:03”, złom. LV i XP tylko jako „+12 XP · LV 23” na 3 s po zdobyciu | `_run_card` (karta, pasek XP, `_lv_label`), `_xp_feed` |
| 4 | dół-lewo | **ja + hałas**: mały VU-metr (104 px), nazwa/slot, 4 segmenty życia, jedna linia „NOISE CALM · 6%”. Stan zmienia kolor (kość → lampa → krew) | `_noise_card`, własny wiersz drużyny, `_safe_chip` (w kryjówce zamiast VU zostaje samo „SAFE”) |
| 5 | dół-środek | **broń jako model 3D, bez ramki**: model aktualnej broni (ten sam `.glb` co w grze), obok amunicja 72 px / zapas, pod spodem nazwa, tryb i koszt strzału, cienkie linie przeładowania i ciepła lufy. Rząd 1–4 z miniaturami 3D nad bronią, widoczny 2 s po zmianie broni (aktywny w lampie) | `_gear_card` (część broni), `_slots`, `_slot_icons`, `GunIcon` (obecnie rysuje sylwetkę; zastąpić renderem modelu 3D, patrz niżej) |
| 6 | dół-prawo | **sprzęt jako modele 3D, bez ramek**: wabik Q, flara F, wybrany przedmiot ALT, latarka L. Liczba przy rogu modelu, klawisz pod spodem jako podkreślona litera; latarka z cienkim paskiem baterii pod modelem. Pusty: model szary, liczba w krwi | `_equip_card`, `Pips` (rombowe ładunki znikają), `_gren_name`, `_battery` |
| 7 | dół-środek, nad bronią | **podpowiedź kontekstowa**: klawisz (podkreślona litera) + czynność, bez karty; postęp jako cienka linia. Pasek sterowania tylko w pierwszej misji i pod F1 | `_prompt_card`, `_controls` (`CONTROLS_SHOW_S` 20 → pierwsza misja profilu) |
| 8 | środek | **kropka** 6 px, rozszerza się przy koszcie hałasu strzału (opcja) | celownik z `CROSS_SCALE` |

### Modele 3D w HUD-zie (korekta 2026-10-17)

Broń i sprzęt rysujemy z modeli gry, nie z ikon 2D. Zrobione w makiecie: render ortograficzny `.glb` z przezroczystym tłem, przycięty do zawartości, światło 2-punktowe (skrypt `icons3d.gd` w scratchpadzie sesji; do przeniesienia do `tools/` jako `bake_hud_icons.gd`).

- **Są modele:** wszystkie bronie (`art/char3d/gun_*.glb`), granat, flara, dym, fosfor, mina, ładunek, skaner, apteczka (`art/items3d/*.glb`).
- **Brakowało modeli wabika Q i latarki L** (Overcharge to w grze wybuch hałasu broni, `lamp.glb` to lampa sufitowa). Zamodelowane skryptem: `concepts/hud_minimal/models/make_hud_models.py` (Blender 5.2, bryły z fazowaniem, czyste materiały PBR bez tekstur) → `flashlight.glb` (olive, radełkowany uchwyt, przełącznik, szkło) i `lure.glb` (megafon z chwytem pistoletowym: wabik jako „nadajnik hałasu”). Ikony wyrenderowane tym samym skryptem Godota co reszta, więc światło jest spójne. Modele są proste (bez zużycia i tekstur Tripo); przed wejściem do gry warto je zestarzyć (wypalone tekstury jak `prep_items3d.py`) albo wygenerować nowe.
- **Wdrożenie w Godocie:** wypiekanie PNG przy imporcie (jak `bake_sprites.py`, bez kosztu w grze) jest tańsze niż żywy `SubViewport` w HUD-zie. Żywy model (obrót przy zmianie broni) tylko w oględzinach `[F]` (`weapon_inspect.gd`, już istnieje).
- **Klawisze:** w całym HUD-zie podkreślona litera zamiast kapsla (`W.keycap` zostaje w menu).

Tło czytelności: dwa gradienty (góra 22%, dół 26% wysokości), alfa 0,55–0,6, zamiast kart. Cień tekstu 8 px, nie obrys 3 px (obrys na małym tekście robi szum, UI_PLAN §3 pkt 2).

### Stany hałasu (z wizualizacji)

- **CALM (< 30%)**: T2 do 35% po 4 s, VU ze wskazówką w strefie zielonej, linia stanu w kości.
- **UNEASY (40–59%)**: wskazówka i linia stanu w lampie, T2 wraca do 100%.
- **HUNTED (≥ 60%)**: linia stanu w krwi i pulsuje (nie przy „Reduce effects”), szept „SOMETHING IS LISTENING”, czerwona winieta (istniejący `horror_fx.gd`, nie nowy efekt). Progi czytamy z `NoiseMgr`, nie na sztywno.

## 5. Etapy (każdy to osobny PR, każdy z zrzutami przed / po)

| Etap | Zakres | Ryzyko | Weryfikacja |
|---|---|---|---|
| **H0** | Tokeny: `UiTheme.flat_box()` (pusty styl), gradienty `scrimT/B`, cień tekstu zamiast obrysu, `_card()` przyjmuje `flat := true`. Przełącznik tymczasowy `Settings.hud_style` (CLASSIC / MINIMAL) na czas playtestu; potem usunąć | niskie | `shot_hud.gd` obie wartości |
| **H1** | Dół: broń jako model 3D na środku (amunicja, nazwa, dwie linie przeładowania i ciepła), sprzęt jako 4 modele 3D po prawej; rząd slotów z miniaturami 2 s po zmianie; wypiekanie ikon z `.glb` do `art/hud/` (`tools/bake_hud_icons.gd`) | średnie: `_drive_weapons` (~85 linii) pisze do ~12 węzłów; modele wabika i latarki są (`make_hud_models.py`), do zestarzenia | `--size=1280x720/1920x1080`, `--ui=0/1/2`, brak amunicji, przeładowanie, 1 / 4 gracze |
| **H2** | Dół-lewo + góra-lewo: własne życie z VU-metrem, reszta drużyny jako lista | średnie: sieć, boty, `--down`, `--humans=1..4` | `--down`, `--humans=1..4`, hałas 0 / 45 / 70, daltonizm |
| **H3** | Góra: pasek kierunku + toast celu + tekst strefy; bez karty RUN i `_obj_card` | **wysokie**: nowy `CompassStrip`, dane o celach i wyjściu z `mission.gd` / `level.gd`, boss | misje 1.1, 1.3, boss, kryjówka (hub: `_brief`, `_radio` zostają jak są) |
| **H4** | Wygaszanie i zdarzenia: toast na zmianę celu, +XP po zdobyciu, sterowanie tylko w pierwszej misji, kropka zamiast celownika, uproszczenie banera misji | niskie | pełny przebieg misji nagraniem (`trailer/capture.sh`) |
| **H5** | Sprzątanie: usunięcie CLASSIC, martwych węzłów i stałych (`SQUAD_W`, `ROW_H`, `TOP_H`, `OBJ_W`, `SESSION_W`), CHANGELOG, `README.md`, tłumaczenia w `ui.csv` | niskie | `--import`, CI |

Kolejność H0 → H1 → H2 → H3 → H4 → H5; H1 i H2 dotykają innych fragmentów pliku, ale oba w `hud.gd`, więc **jeden pisze naraz** (konflikty).

## 6. Decyzje do podjęcia

1. **Gdzie hałas?** Rekomendacja: dół-lewo przy życiu (jak pasek zdrowia we wzorze), VU-metr zostaje. Alternatywa: zostaje w lewym górnym rogu, a lista drużyny schodzi pod niego. Dół-lewo daje czystszy górny róg i łączy „ja” w jedno miejsce.
2. **Pasek kierunku w grze 2D z widokiem 3D.** Świat jest długim korytarzem (oś X), więc „kompas” to pozycje na osi względem gracza, nie kąty. Trzeba sprawdzić: czy są pionowe odcinki mapy (strefy 2+), skala jednostek → metry, i czy cel ma zawsze jedną pozycję (mission.gd).
3. **Karta XP/LV w trakcie gry** znika. Czy zostaje gdzieś stały podgląd (np. pod F1 / Tab)? Rekomendacja: Tab = przypomnienie celu + LV/XP + zegar na 4 s.
4. **Czy zostawić tryb CLASSIC na stałe** jako opcję dostępności (kontrast kart)? Rekomendacja: nie; „Reduce effects” i skalowanie wystarczą, a dwa układy to podwójny koszt testów.
5. **Czcionka w tytułach**: wzór używa szeryfowych kapitalików. Rekomendacja: zostać przy Big Shoulders Stencil (tożsamość gry, UI_PLAN), szept = Special Elite.

## 7. Ryzyka

- **Konflikty:** `gameon-hub` ma świeższy `hud.gd` (1.7.272, papier w świecie 3D i komunikaty o 20% mniejsze, gałąź `feat/msg-paper3d`). Start dopiero po jej scaleniu, inaczej H1–H3 będą się rozjeżdżać z `_note`/`_hint`.
- **Czytelność na ciemnych scenach** (jak wzór): bez ramek tekst opiera się na gradiencie i cieniu. Sprawdzić na jasnych scenach (flary, ogień) i w kryjówce.
- **Mniej informacji naraz** to także mniej uczenia nowych graczy: pierwsza misja zostaje z paskiem sterowania i podpowiedziami (`hints.gd`).
- **Daltonizm:** romby kolegów w kolorze slotu mają też nazwę (P3, P4); powaleni mają napis DOWN, nie tylko kolor.
- **Nie sprawdzono:** układu przy 4 graczach i bossie w nowym stylu (to schemat z jedną sceną), dystansów w metrach, wpływu na FPS (HUD rysuje się w `Control`, gradienty to dwa `TextureRect`).
