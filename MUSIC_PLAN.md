# Muzyka adaptacyjna — plan

Status: **plan z 2026-11-15 (main 1.7.576, 35b8c6ff).** Decyzje D1–D7 (§6) przyjęte 2026-11-15 — wszystkie warianty zalecane.
**E0 w 1.7.578** (`music_director.gd`, test `tools/test_music.gd`, zdarzenie `music` w dzienniku sesji). **E1 w 1.7.579** (motyw Stalkera `mus_stalker_far` / `mus_stalker_near`, sygnały `cue_elite` / `cue_horde`, ostatnie serce i leżenie; zdarzenia `music_motif`, `music_cue`); dalej odsłuch z testerem i E2. Równolegle `amb_machine` (stałe buczenie pod całą grą) usunięta w PR #690 (1.7.577).
Muzyka nie zmienia rozgrywki, więc etapy nie czekają na playtest (GDD §16.0a), ale po E1 i E3 są punkty odsłuchu w grze z testerem.

## 1. Skąd to

Analiza ścieżek audio (2026-11-15) pokazała, że tło gry to las, pogoda i lokalne pętle z nagrań, a pod nimi syntetyczna muzyka, która
**nie mówi graczowi prawdy o zagrożeniu**. Użytkownik chce muzyki lepiej pasującej do gry, z mechanikami podpatrzonymi w popularnych
grach i gatunkach (§3).

## 2. Stan obecny (z kodu)

- **Materiał:** 4 addytywne stemy z syntezy (`tools/bake_music.py`), pętle 20 s, 96 BPM, 32 beaty: `mus_silence` (−26 LUFS),
  `mus_tension` (−25), `mus_combat` (−21), `mus_chase` (−22), oraz `sting_tension` i `sting_chase`.
- **Sterowanie:** `hud.gd:_drive_music()` — warstwa wyłącznie z `NoiseMgr.level` (Uwaga): ≥ 20 napięcie, ≥ 45 walka, ≥ 70 pościg.
  `AudioDirector.music_set_layer()`: stemy nakładają się (0..layer), wejście kwantyzowane do beatu (siatka 1 / 1 / ½ / ¼ beatu), zejście
  z opóźnieniem 0 / 2,5 / 6 / 8 s, narastanie `MUSIC_BLEND` = 4,0 / 1,6 / 0,7 / 0,35 s, `duck_music()` dla stingerów i krzyku.
- **Brak** muzyki dla bossów, kryjówki, menu, ekranu wyniku i śmierci; `mus_silence` startuje przy pierwszym wywołaniu i gra zawsze
  (HUD z `_music_layer := -1` — prawdopodobnie już w menu; do sprawdzenia w E0).

### 2.1 Problemy

| # | Problem | Skutek |
|---|---|---|
| P1 | Uwaga ≠ zagrożenie | „Walka” po strzale w pustkę; skradający się Stalker nie zmienia muzyki → gracz uczy się ją ignorować |
| P2 | Brak prawdziwej ciszy | `mus_silence` pod całą grą; horror traci kontrast, a dźwięki świata (kroki, Stalker) mają mniej miejsca |
| P3 | Pętle 20 s | W misji 10–20 min ta sama fraza wraca 30–60 razy |
| P4 | Synteza vs świat z nagrań | Muzyka brzmi jak z innej gry niż las, deszcz i broń |
| P5 | Zejście przez wyciszenie | Walka „gaśnie”, zamiast się skończyć; brak nagrody za przetrwanie starcia |
| P6 | Brak momentów | Boss, „przetrzymaj”, odwrót, kryjówka i wynik brzmią tak samo jak reszta |

## 3. Inspiracje

| Gra / gatunek | Mechanika | U nas |
|---|---|---|
| Hunt: Showdown, Escape from Tarkov, Lethal Company | Eksploracja bez muzyki; informację niesie dźwięk świata | Cisza jako stan domyślny; muzykę trzeba „zarobić” (D1) |
| Left 4 Dead (AI Director) | Muzyka jako informacja: osobne sygnały Tanka, Witch, nadchodzącej hordy; miks osobny dla każdego gracza | Sygnały typów zagrożeń; muzyka liczona lokalnie dla każdego gracza (D6) |
| Alien: Isolation, Resident Evil 2 (2019) | Motyw prześladowcy zależny od jego obecności i odległości | Leitmotiv Stalkera: polowanie → blisko; nigdy, gdy go nie ma (D3) |
| Dead Space | Intensywność z bliskości zagrożeń („fear emitters”), kilka poziomów, stingery | Wynik zagrożenia zamiast Uwagi (D2) |
| Doom (2016), Returnal | Segmenty łączone poziomo, przejścia na takcie, kadencja na koniec starcia | Mniej powtórzeń; walka się kończy, a nie gaśnie |
| S.T.A.L.K.E.R., Metro | Muzyka diegetyczna ze źródeł w świecie, bezpieczne miejsca | Radio w kryjówce pod stacją radiową: utwory w duchu PRL-u, stacja numeryczna (D5) |
| Contra, Deep Rock Galactic | Głośny, napędzający utwór przy fali i ewakuacji | „Przetrzymaj” i odwrót — jedyne miejsca, gdzie muzyka może być głośna |
| Darkwood, Amnesia | Drony zlane z dźwiękiem otoczenia | Paleta osobna dla każdej strefy: Bór / Obiekt 86 / Martwa Cisza (D7) |

## 4. Projekt: trzy osie

### 4.1 Oś A — stan (poziomo)

| Stan | Kiedy | Muzyka |
|---|---|---|
| Menu | ekran tytułowy | Temat główny „z eteru”: dostrajanie krótkofalówki, temat wyłania się z szumu |
| Kryjówka | hub | Diegetyczne radio (`radio_set.gd`) — 2–3 utwory + stacja numeryczna; poza zasięgiem odbiornika cisza |
| Eksploracja | brak zagrożenia | Cisza; co 2–4 min krótki „oddech” (8–20 s dronu strefy), nigdy przy aktywnym zagrożeniu |
| Kontakt | wróg świadomy gracza / Stalker poluje | Puls i dron, niski, bez melodii |
| Walka | starcie | Warstwy rytmu i uderzeń industrialnych; koniec = kadencja (ogon 2–4 s), nie wyciszenie |
| Pościg / przetrzymaj | gracz ucieka, fala, odwrót | Napędzający utwór, jedyne miejsce głośniejsze niż −20 LUFS poza bossem |
| Boss | Żyła, B1 | Sekcje przypisane do faz; zmiana fazy na takcie |
| Wynik / śmierć | `result_screen.gd`, wypad | Krótkie kadencje: sukces, porażka, śmierć (dźwięk zostaje „w taśmie”) |

### 4.2 Oś B — intensywność (pionowo, w obrębie stanu)

3–4 warstwy w każdym stanie sterowane **wynikiem zagrożenia** T (0–100), liczonym lokalnie dla gracza:

- wrogowie, którzy wiedzą o graczu, w promieniu słyszenia — z wagą typu (zwykły, elita, boss);
- świeże trafienia gracza (opada w ~6 s);
- Stalker: stan `Pass.HUNT` i odległość;
- Uwaga (`NoiseMgr.level`) jako mały składnik (np. ≤ 20% T), żeby hałas nadal „podnosił ciśnienie”.

Histereza i opóźnione zejście zostają z obecnego silnika. Stan (oś A) wybiera reguła, warstwę (oś B) — T.

### 4.3 Oś C — motywy zagrożeń (nakładki)

- **Stalker:** leitmotiv 3–4 nut, rozpoznawalny po jednym usłyszeniu; głośność i gęstość od odległości, tylko gdy naprawdę poluje (D3).
  Gra na szynie muzyki, ale muzyka ścisza się pod dźwiękami samego Stalkera (`BUS_STALKER`).
- **Elita / horda:** krótki sygnał przy pojawieniu się (jak horda w L4D), raz na zdarzenie, nie w pętli.
- **Niskie HP:** muzyka −9 dB i dolnoprzepustowo, zostaje serce (`heart_slow_loop`); leżący gracz słyszy ją jak przez ścianę.

### 4.4 Brzmienie 1987

- Analogowe syntezatory i FM (DX7) przez taśmę: wow / flutter, szum, nasycenie; krótkofalówka i fale średnie jako faktura.
- Uderzenia industrialne **próbkowane z naszych nagrań** metalu, blach i drzwi (biblioteka Sonniss) — wspólny materiał ze światem (P4).
- Paleta stref: Bór — drewno, szum, niskie dęte z taśmy; Obiekt 86 — stal, przekaźniki, FM; Martwa Cisza — chór z taśmy, rozstrojenie.

### 4.5 Zasady miksu

- Muzyka zawsze pod sygnałami rozgrywki (kroki, przeładowanie, krzyki wrogów, Stalker) — zasada Hunta jak przy pogodzie.
- Eksploracja / kontakt / walka: maks. ok. −20 LUFS; pościg, boss, odwrót: maks. ok. −16 LUFS.
- Pętle 2–4 min złożone z segmentów po 8 taktów z wariantami (oś A + losowanie segmentów), przejścia tylko na granicy taktu.

## 5. Etapy

| Etap | Zakres | Pliki (szacunek) | Wynik |
|---|---|---|---|
| **E0** | Wynik zagrożenia T zamiast samej Uwagi; prawdziwa cisza (eksploracja bez `mus_silence`); menu bez muzyki rozgrywki; czas w każdym stanie i warstwie w dzienniku sesji | `hud.gd`, `audio_director.gd`, nowy `music_director.gd`, test `tools/test_music.gd` | Muzyka mówi prawdę na obecnych stemach |
| **E1** | Leitmotiv Stalkera od odległości; sygnały elity i hordy; niskie HP | `stalker.gd`, `director.gd`, `bake_music.py` | **Odsłuch z testerem** |
| **E2** | Silnik segmentów: kolejki taktów, przejścia na takcie, ogony / kadencje, palety stref | `audio_director.gd`, manifest (`MUSIC_SEGMENTS`) | Mniej powtórzeń (P3, P5) |
| **E3** | Materiał: kontakt / walka / pościg × 3 strefy, pętle 2–4 min z wariantami, sampler z nagrań w `bake_music.py` | `bake_music.py`, `audio/music/` | **Odsłuch z testerem** |
| **E4** | Żyła i B1 (sekcje wg faz), „przetrzymaj” i odwrót | `boss_base.gd`, Żyła, B1 | Momenty (P6) |
| **E5** | Temat główny w menu, radio w kryjówce, kadencje wyniku i śmierci | `main_menu.gd`, `radio_set.gd`, `result_screen.gd` | Tożsamość gry |

Każdy etap: osobna gałąź i PR, podbicie `config/version`, wiersz w `CHANGELOG.md`, testy audio (`test_audio_loops.gd`,
`test_shutdown.gd`) i nowy `test_music.gd` (stan i warstwa dla scenariuszy: pusto, wróg świadomy, Stalker poluje, boss).

## 6. Decyzje (przyjęte 2026-11-15)

| # | Pytanie | Przyjęte | Odrzucone |
|---|---|---|---|
| D1 | Co gra w eksploracji | Cisza z rzadkimi „oddechami” dronu | Stały cichy dron; jak dziś |
| D2 | Co steruje muzyką | Wynik zagrożenia (Uwaga jako składnik) | Sama Uwaga |
| D3 | Motyw Stalkera | Uczciwy — tylko gdy naprawdę poluje | Także fałszywe alarmy |
| D4 | Źródło muzyki | Teraz synteza + sample z biblioteki; przed wydaniem kompozytor | Generator AI (ryzyko licencji); sama synteza |
| D5 | Radio w kryjówce | Tak, diegetyczne | Nie |
| D6 | Co-op | Muzyka osobna dla każdego gracza, liczona lokalnie (bez sieci) | Wspólna dla drużyny |
| D7 | Paleta | Osobna dla każdej strefy | Jedna dla całej gry |

## 7. Ryzyka

- **T wymaga danych o świadomości wrogów** — jeśli wróg nie wystawia „widzi gracza”, E0 zaczyna od dodania tej flagi (tylko odczyt).
- **Cisza może brzmieć jak błąd** — „oddechy” i ambient muszą trzymać poziom; po E0 odsłuch całej misji 1.1.
- **Materiał E3 jest najdroższy** — synteza z samplerem może nie dorównać nagraniom; D4 zakłada kompozytora przed wydaniem, a silnik
  E2 ma przyjąć jego stemy bez zmian w kodzie (format segmentów w manifeście).
- **Repo publiczne:** sample z biblioteki trafiają tylko do `audio_licensed/` (jak efekty), w repo zostaje wersja z syntezy.
