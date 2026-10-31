# Plan: ekran startowy „FIELD TERMINAL” (menu główne)

Status: **zaakceptowany do wdrożenia 31.10.2026** — kierunek i trzy detale potwierdzone przez właściciela; **poprawiony 31.10.2026**
po analizie zgodności z kodem (sekcja 2b).
Baza: **main 1.7.445** (plan powstał na 1.7.441). Wdrożenie w świeżym worktree z `main` — ten plik leży dziś nieśledzony
w checkoucie na `feat/trzosek-clips`, przenieść go razem z pracą. Podstawa kodu: `prototype/scripts/main_menu.gd` (menu),
`menu_scene.gd` (tło), `ui_theme.gd` / `ui_widgets.gd` (komponenty). Materiały projektu (poza repo): `../menu_design/`.

## 1. Cel

1. Ekran startowy jest **pierwszą sceną gry**: pełnoekranowy render (nocny bór, wieża z latarnią, ognisko, operatorzy)
   zamiast rysowanego wzoru — z powolnym ruchem kamery, mgłą i ogniem.
2. **Jedna decyzja**: przycisk kampanii (`OPEN LOBBY`, patrz 2b) jest jedynym wypełnionym przyciskiem; pozostałe destynacje
   są mniejsze i ciemniejsze.
3. **Operator widoczny** od pierwszego ekranu: karta z portretem, kryptonimem, poziomem i paskiem XP; obok kompaktowy
   SQUAD LINK (towarzysz AI, JOIN). W menu nie ma jeszcze sesji — menu chowa się, gdy tylko ruszy sieć
   (`main_menu.gd`, `NoiseMgr.has_network()`), więc nie pokazujemy slotów innych graczy.
4. **Tekst na żądanie**: w spoczynku tylko tekst główny (≤ 70 słów); szczegóły po najechaniu lub fokusie.
5. **Bez zmian w rozgrywce, sieci, lobby i zapisie.** Zachowane sygnały `play_requested` (`entry` = host/join/night),
   `settings_requested`, `operators_requested`, potwierdzenie wyjścia i obsługa pada.

## 2. Zaakceptowane decyzje (31.10.2026)

| Decyzja | Wybór |
|---|---|
| Miejsce szczegółów | **Szuflada pod listą** (720 × 136), nie dymek przy kursorze |
| Pad | **Fokus odsłania to samo co hover** |
| Opóźnienia | **120 ms** wejście, **140 ms** szuflada; natychmiast przy „Reduce Effects” i na padzie |
| Tło | **Key art z gry** (generowany skryptem) w P0; diorama 3D poza zakresem |
| Panel drużyny | **Read-only + JOIN**; zaproszenia zostają w lobby / Steam |
| Kolejność | **Dwa PR-y**: P0 + P1, po akceptacji wyglądu P2 + P3 |

### 2b. Decyzje po analizie zgodności z kodem (31.10.2026)

| Problem w pierwszej wersji | Decyzja |
|---|---|
| 4 sloty drużyny zawsze puste poza Tobą (w menu nie ma sesji) | **Panel zmniejszony**: nagłówek SQUAD LINK, wiersz AI COMPANION z przełącznikiem, JOIN SESSION |
| JOIN wyłączony bez Steama — a dołączanie w LAN po IP Steama nie wymaga (`lobby.gd`) | **JOIN zawsze aktywny**; bez Steama podpis „LAN / IP”, ze Steamem „LAN / STEAM” |
| Pad dochodził tylko do 3 kart; JOIN, AI, SETTINGS, QUIT i karta operatora poza zasięgiem | **Pełna siatka fokusu** (sekcja 5, „Nawigacja”) |
| Wymiary 1920 × 0,667 dawały 9–11 px, wbrew kryterium ≥ 12 px | **Min. 12 px na siatce 1280** (= 18 px w projekcie 1920); szuflada 116 → 136 |
| „Najlepszy bieg” Nocnego Dyżuru | **Zostaje w szufladzie** — rekord jest w zapisie postaci (`Settings.shift_best_cleared` / `shift_best_time`, `player.cfg`); pierwsza analiza go przeoczyła |
| DEPLOY obiecywał start „1.3 The Nest”, a otwiera lobby | **Etykieta mówi prawdę**: `OPEN LOBBY` (PL „DO LOBBY”; brzmienie do potwierdzenia na zrzutach P1), misja podpisana `NEXT` |
| Key art z mockupu to odbita, powiększona klatka ~1320 px | **Najpierw próbny render** do akceptacji (P0, krok 1) |

Drobne ustalenia: „pasek 4 stref” to w rzeczywistości **4 misje strefy 1** (`level.gd` `CAMPAIGN`) — w kodzie i tekstach
„misje”, nie „strefy”; zrzuty przez istniejący `tools/shot_ui.gd --screen=main`; test przez rozszerzenie `--uifittest`;
bez fallbacku `--oldmenu` (P0 i P1 idą w jednym PR-ze).

## 3. Układ

Projekt w **1920 × 1080**; implementacja mnoży wartości przez **0,667** (siatka menu 1280 × 720, jak dziś `_fit()`).
Odstępy wewnętrzne: wielokrotności 8 px. Marginesy: 92 / 64 / 92 / 80 (1920) → 61 / 43 / 61 / 53 (1280).
**Najmniejszy tekst: 18 px w projekcie = 12 px na siatce 1280** (etykiety mono, podpowiedzi w pasku, wiersze szuflady).

| Strefa | Pozycja (1920 × 1080) | Zawartość |
|---|---|---|
| Brand | 92, 74 · szer. 820 | „DON'T MAKE A SOUND”, DEAD AIR, '87, „NO SIGNAL” — bez zmian (tagline i „CH-87 · FIELD TERMINAL” z mockupu tylko po potwierdzeniu na zrzutach P1) |
| Karta operatora | prawy górny · 380 × 126 | portret 68 × 94, kryptonim, LV, pasek XP; fokusowalna |
| Destynacje | 92, 424 · 720 × 408 | kampania 200, Nocny Dyżur 96, Operatorzy 96; odstęp 8 |
| Szuflada | 92, 840 · 720 × 136 | 2 × 2 pary etykieta–wartość dla wskazanej karty |
| SQUAD LINK | prawy · 380 × ~200, dół równo z listą destynacji (~632–832) | nagłówek z liczbą miejsc, wiersz AI 56, JOIN 65 |
| Pasek dolny | 0, 1000 · 1920 × 80 | SETTINGS / QUIT / wersja, ticker, podpowiedzi klawiszy |

Wysokość SQUAD LINK dokładnie ustalić na zrzutach P1; zwolnione miejsce w prawej kolumnie zostaje dla key artu.

**Budżet tekstu:** spoczynek ≤ 70 słów (mockup: ~63, po zmniejszeniu panelu mniej; wersja 1: ~115). Karta: maks. 3 linie.
Szuflada: maks. 4 pary.

## 4. Mapa odsłaniania

| Obszar | Zawsze widoczne (tekst główny) | Po najechaniu / fokusie |
|---|---|---|
| Kampania | CAMPAIGN, `NEXT` 1.3 The Nest, pasek 4 misji, OPEN LOBBY | następna misja, postęp 2 / 4 misji, trudność (zmiana w lobby), skład 1–4 i AI |
| Nocny Dyżur | NIGHT SHIFT, ENDLESS | misje i losowanie, modyfikatory, najlepszy bieg, nagroda (połowa XP) |
| Operatorzy | OPERATORS, 2 / 6 | aktywny operator, strój, roster, ostatnia misja |
| Karta operatora | portret, kryptonim, LV, pasek XP | XP 180 / 400, złom 302 |
| SQUAD LINK | nagłówek, AI COMPANION + przełącznik, JOIN SESSION z podpisem LAN / IP lub LAN / STEAM | stan przełącznika słownie (ON / OFF) |
| Ticker | LAST BROADCAST, dioda, waveform | cytat audycji (także przy fokusie w pasku dolnym) |

## 5. Komponenty i stany

- **DestinationCard** — num, nazwa (stencil 58/38), misja (whisper 26), pasek misji, OPEN LOBBY (kampania);
  stany: spoczynek, hover/fokus (czerwona szyna 2 px + trójkąt + rozjaśnione tło). Domyślny fokus na kampanii.
- **DetailsDrawer** — 720 × 136, nagłówek `01 CAMPAIGN`, siatka 2 × 2, etykieta mono 18, wartość mono 21,
  górna linia + czerwona krawędź; `mouse_filter = IGNORE`; 140 ms fade/slide 6 px; tło rezerwowane (brak przesunięć).
- **PlayerCard** — 380 × 126 → 156 po hoverze / fokusie; wiersz `XP 180 / 400 · SCRAP 302`; Enter → ekran OPERATORZY.
- **SquadPanel** — nagłówek SQUAD LINK; AI COMPANION z przełącznikiem (bez sieci `Main.companion_editable()` = true,
  zapis przez `Settings.set_ai_companion`); JOIN SESSION zawsze aktywny, podpis zależny od Steama; panel nie zmienia wysokości.
- **Ticker** — etykieta i waveform zawsze; cytat `opacity 0 → 1` po hoverze lub przy fokusie w pasku dolnym.
- **Pasek dolny** — SETTINGS, QUIT (fokusowalne), wersja, podpowiedzi (pad: `Actions.pad_mode`).
- **Tokeny** — bez nowych kolorów: `ACCENT`, `DANGER`, `TEXT`, `MUTED`, `PANEL_BG`, `LINE` z `ui_theme.gd`.

**Nawigacja (mysz, klawiatura, pad):**

| Skąd | Góra | Dół | Lewo | Prawo |
|---|---|---|---|---|
| Kampania | — | Nocny Dyżur | — | karta operatora |
| Nocny Dyżur | Kampania | Operatorzy | — | AI COMPANION |
| Operatorzy | Nocny Dyżur | SETTINGS | — | JOIN |
| Karta operatora | — | AI COMPANION | ostatnia karta | — |
| AI COMPANION | karta operatora | JOIN | ostatnia karta | — |
| JOIN | AI COMPANION | QUIT | ostatnia karta | — |
| SETTINGS | Operatorzy | — | — | QUIT |
| QUIT | JOIN | — | SETTINGS | — |

Enter / Space / A potwierdza (na AI COMPANION przełącza); Esc → ustawienia. „Ostatnia karta” = destynacja, która miała
fokus ostatnio (domyślnie kampania).

## 6. Implementacja

### P0 — tło i art (1–2 dni)

1. **Próbny render do akceptacji:** klatka z misji `z1_m1` (widok 3D bez HUD, 3840 × 2160) z kamerą ustawioną tak,
   by akcja była po prawej — **bez lustrzanego odbicia** (broń w lewej ręce). Kadr pokazać właścicielowi przed resztą P0.
   Narzędzie: istniejący zrzut widoku 3D z `prototype/tools/` — ustalić, które obsługuje brak HUD i 4K; w razie potrzeby
   dopisać flagę.
2. Nowy generator `prototype/tools/menu_backdrop.py` (Pillow): bierze zaakceptowaną klatkę z `art_src/menu/` (LFS — wpis
   w `.gitattributes`), robi gradację w palecie gry (zimne cienie, ciepłe ognisko, winieta, ziarno) i zapisuje
   `prototype/art/menu/backdrop.jpg` (lub `.webp`) w **2560 × 1440**. Import: bez mipmap, sprawdzić rozmiar w VRAM.
   Źródło i wynik generuje skrypt, nie edycja ręczna (punkt wyjścia: `menu_design/prep_assets.py`).
3. `prototype/scripts/menu_stage.gd`: tekstura tła + dolly 1.0 → 1.035 / 50 s, dwie warstwy mgły, embery, migotanie
   ognia; `Settings.fx_mult() <= 0` zatrzymuje wszystko (statyczny obraz).
4. `main_menu.gd` podmienia `menu_scene.gd` na `menu_stage.gd`; `menu_scene.gd` usunąć w tym samym PR-ze (P0 + P1 razem,
   fallback niepotrzebny). `lobby.gd` używał tego samego tła — dostaje `menu_stage.gd` (zmiana tylko wizualna).
5. Pomiar: brak nowych shaderów per-klatkę; budżet UI ≤ 1,5 ms (metoda w sekcji 7).

**Stan P0 (31.10.2026, lokalnie na `feat/main-menu-stage`, bez commita):** kadr c125 zaakceptowany (`--shotzoom=1.6 --shotat=125`,
źródło `art_src/menu/keyart_z1_m1_c125.png` w LFS); `tools/menu_backdrop.py` → `art/menu/backdrop.jpg` (BC7 + mipmapy) i `fog.png`;
`scripts/menu_stage.gd` (najazd wokół żołnierza, dwie mgły, 24 iskry, migotanie poświaty; „Reduce Effects” = stały obraz);
`menu_scene.gd` usunięty, menu i lobby na nowym tle. `--uifittest` i `--maptest` PASS. Pomiar (okno 3840 × 2160, RTX 3080):
`menu_stage._process` 0,12 ms CPU (0,03 ms przy „Reduce Effects”), GPU całego widoku ~0,9 ms.

### P1 — układ (3–5 dni)

1. `main_menu.gd`: przebudowa na strefy z sekcji 3; zachować sygnały, `entry`, quit confirm (3 s), Steam, `Characters` /
   `Profile`. Przełącznik trudności znika z menu (zostaje w lobby); trudność tylko do odczytu w szufladzie kampanii.
   Usunąć `Item` na rzecz `DestinationCard`.
2. `ui_widgets.gd`: `card()`, `drawer()`, `stat_row()`, `status_dot()`, `primary_button()`; style bez nowych kolorów.
3. `translations/ui.csv`: nowe wiersze EN/PL — CAMPAIGN, NEXT, OPEN LOBBY, START CAMPAIGN, CONTINUE, NIGHT SHIFT,
   SQUAD LINK, LAST BROADCAST, JOIN SESSION, LAN / IP, LAN / STEAM, AI COMPANION.
4. Fokus i nawigacja wg tabeli z sekcji 5; domyślny fokus na kampanii.
5. `_fit()` zostaje na siatce 1280 × 720; nowe wysokości 133 / 64 / 91 (szuflada) itd.; żaden tekst poniżej 12 px.
6. Zrzuty kontrolne po P1 (EN i PL, 1280 × 720 i 1920 × 1080) do akceptacji wyglądu, w tym brzmienie `OPEN LOBBY`
   i ewentualny nowy tagline.

**Stan P1 (31.10.2026, lokalnie, bez commita):** `main_menu.gd` przepisany na strefy (klasy `Card`, `Drawer`, `PlayerCard`, `Row`,
`Link`, `Ticker`; własne rysowanie zamiast nowych funkcji w `ui_widgets.gd`), siatka fokusu wg §5, szuflada przełącza się od razu
przy fokusie (animacje 120 / 140 ms — P2). Panel drużyny: nagłówek z kropką Steama (○ / ●), TOWARZYSZ AI, DOŁĄCZ (PL krótko —
„DOŁĄCZ DO SESJI” się nie mieściło). Cytat audycji przy fokusie w pasku albo pod kursorem, przycięty do miejsca przed podpowiedziami.
Przycisk kampanii: `OPEN LOBBY` / „DO LOBBY”. 20 nowych wierszy w `ui.csv`. `tools/shot_ui.gd`: `--hover=`, `--lang=`, `--size=`
(okno 16:10 daje zrzut 16:9 — projekt trzyma proporcje, Steam Deck to pasy). `--uifittest` i `--maptest` PASS; zrzuty
w `C:\deadair87\menu_design\p1`.

### P2 — szczegóły i stany (1,5–2,5 dnia)

1. Szuflada: `mouse_entered` / `mouse_exited` na kartach + `focus_entered` / `focus_exited`; timer 120 ms wejścia,
   100 ms schowania; przejście z karty na szufladę nie zamyka (nasłuch na wspólnym kontenerze).
2. `PlayerCard` 126 → 156; `Ticker` cytat po hoverze i przy fokusie w pasku; wszystko bez zmiany wysokości.
3. Dźwięki: `ui_move` (raz na element), `ui_click`, `ui_confirm`, `ui_deny`.
4. `Reduce Effects`: brak animacji szuflady i przełączania; natychmiastowe stany.
5. Stany brzegowe: nowy gracz (`START CAMPAIGN`, 0 / 4, 1.1 Missing Patrol), Steam offline (JOIN aktywny, podpis LAN / IP),
   quit confirm, język PL.

### P3 — QA i dokumentacja (1–2 dni)

1. Rozszerzenie `--uifittest` o menu główne: EN/PL, 1280 × 720 / 1920 × 1080 / 2560 × 1440 / 1280 × 800,
   cała siatka fokusu, szuflada, quit, wszystkie 6 akcji, JOIN aktywny bez Steama, brak przycięć, żaden tekst < 12 px.
2. `tools/shot_ui.gd --screen=main`: nowy argument `--hover=campaign|night|operators|player|squad|ticker` do zrzutów
   spoczynku i szuflady do PR-a.
3. `README.md` / `GDD.md` / `CHANGELOG.md` + bump `config/version` (zasady z `CLAUDE.md`).
4. Zrzuty EN/PL do akceptacji i domknięcie PR-a.

**Razem: 7–12 dni jednego dewelopera.** Dwa PR-y: P0 + P1, po akceptacji P2 + P3.

## 7. Kryteria akceptacji

- [ ] W spoczynku ≤ 70 słów (mockup ~63; v1 ~115).
- [ ] Każda informacja z mapy odsłaniania osiągalna po najechaniu lub fokusie.
- [ ] Hover nie przesuwa layoutu; szuflada ma zarezerwowane miejsce; SQUAD LINK nie zmienia wysokości.
- [ ] Fokus na padzie pokazuje tę samą szufladę co mysz; wszystkie akcje osiągalne padem wg tabeli nawigacji.
- [ ] Wszystkie dotychczasowe akcje: hostuj, dołącz (także bez Steama, po IP), Nocny Dyżur, operatorzy, ustawienia, wyjście.
- [ ] Przycisk kampanii widoczny bez szukania — pierwszy element po tytule, jedyny wypełniony przycisk, etykieta zgodna
      z tym, co robi (otwiera lobby).
- [ ] Żaden tekst poniżej 12 px na siatce 1280 (18 px w projekcie 1920); kontrast ≥ 4,5 : 1.
- [ ] EN i PL bez przycinania; 1280 × 720, 1920 × 1080, 2560 × 1440, Steam Deck (1280 × 800).
- [ ] 60 fps przy 1080p; koszt UI ≤ 1,5 ms; brak alokacji w klatce. **Pomiar:** okno 1920 × 1080 (nie headless),
      monitor czasu klatki Godota (`Performance.TIME_PROCESS` / profiler) z menu na wierzchu, przed i po zmianie;
      liczby w opisie PR-a.
- [ ] „Reduce Effects” zatrzymuje dolly, mgłę, embery i migotanie; szuflada i przełącznik bez animacji.
- [ ] Zero zmian w logice gry, sieci, lobby i zapisie; `--uifittest` i `--maptest` zielone.

## 8. Ryzyka

| Ryzyko | Mitygacja |
|---|---|
| Szczegóły zbyt ukryte | Hover natychmiastowy, fokus pokazuje to samo; karta zawsze ma misję, pasek i przycisk |
| Pad nie dochodzi do akcji poza kartami | Pełna siatka fokusu (sekcja 5); test w `--uifittest` przechodzi ją całą |
| Większe czcionki (≥ 12 px) nie mieszczą się w szufladzie / po polsku | Szuflada 136; `--uifittest` sprawdza przycięcia EN/PL we wszystkich rozdzielczościach |
| Kadr z gry wygląda gorzej niż mockup | Próbny render do akceptacji przed resztą P0; generator z gradacją jak w `prep_assets.py` |
| Key art starzeje się przy zmianie mapy | Obraz generuje skrypt z konkretnej misji; podmiana to jedna komenda |
| Regresja nawigacji i wyjścia | Zachowane sygnały i quit confirm; `--uifittest` rozszerzony o menu |
| Koszt UI i animacji | Jedna tekstura + gradienty; brak shaderów per-klatkę; budżet ≤ 1,5 ms |

## 9. Poza zakresem

- Diorama 3D w menu (osobna decyzja po P3).
- Zaproszenia, lista znajomych i sloty innych graczy w menu (zostają w lobby / Steam).
- Start misji z pominięciem lobby.
- Nowe tryby, zmiany w lobby, sieci i rozgrywce.
- Nowa siatka ikon i nowe kroje (używamy istniejących z `ui_theme.gd`).

## 10. Materiały i lokalizacje

- **Ten plan:** `C:\deadair87\gameon\MAIN_MENU_PLAN.md`
- **Dokument projektu (analiza, wzorce, specyfikacja):** `C:\deadair87\menu_design\projekt_ekranu_startowego.html`
  (nie zawiera poprawek z 2b — w razie sprzeczności rozstrzyga ten plan)
- **Interaktywny mockup:** `C:\deadair87\menu_design\mockup.html` (`?hover=campaign`, `?hover=squad`, `?hover=player`, `?hover=ticker`)
  — prawa kolumna i rozmiary tekstu w mockupie są sprzed sekcji 2b
- **Zrzuty:** `C:\deadair87\menu_design\out\01_ekran_startowy.png`, `02_detale_kampanii.png`, `05_detale_druzyny.png`,
  `03_analiza_obecnie.png`, `04_przed_po.png`
- **Materiały gry:** `prototype/scripts/main_menu.gd`, `menu_scene.gd`, `ui_theme.gd`, `ui_widgets.gd`, `lobby.gd`,
  `translations/ui.csv`, `prototype/tools/shot_ui.gd`, `prototype/art/fonts/`, `prototype/art/portraits/`

Plan opisuje wyłącznie UI. Plik jest **nieśledzony (untracked)** — nie commitowano go; wniosek o PR dopiero po P0 + P1.
