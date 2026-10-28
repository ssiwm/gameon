# Dead Air '87 — prototyp

Modele i ruch Wołka/Rzeźnika (1.7.378): [zakres przebudowy i odbiór](ENEMY_ART_AND_MOTION_REPORT.md). Podgląd zbliżeń: `-s tools/shot_enemy_motion.gd -- --kinds=wolek,rzeznik --closeup --angle=35 --dir=KATALOG`.

Co-op horror run-and-gun (retro Contra) w Godot 4.7 (Forward+). Rozgrywka to symulacja 2D, obraz jest renderowany wyłącznie w 3D (niżej: „Widok 3D”). Zakres:

- ruch 8-kierunkowy (WASD/strzałki) + strzelanie (J/LPM) + przeładowanie (R) + cios (V/PPM) + skok (SPACJA) + skradanie (SHIFT)
- czucie gry (GDD §23): coyote time, jump buffer, jump cut, hitstop, screen shake
- **mapa wielopoziomowa** (TileMapLayer z siatki ASCII w `scripts/level.gd`, 192 × 44 kafli): las + posterunek, arena z kładkami, **Skład** (hala z antresolą, dach, schody z rusztowań), tartak z bossem, a pod całością **podziemia** — sale i niskie tunele połączone trzema szybami ze schodami z kładek; kładki jednokierunkowe — wskok od spodu, zeskok **dół + skok**. Broni do znalezienia są tylko **4** (las, półka w podziemnej sali, antresola hali, rusztowanie tartaku), reszta arsenału to start + skrzynki z amunicją
- **ciemność i latarka** (GDD §8.3): aura 6 m, latarka **L** (stożek 8 m, bateria, +1 Uwagi co 10 s, budzi oświetlonych wrogów, ściąga Stalkera), flara ekstrakcji 12 m, cienie od kafli
- **Animacje walki TPP (1.7.371):** autorskie klipy MPFB z Blendera, warstwy `AnimationTree`, podparcie stóp przed nakładką ciała i IK dłoni po niej. Zegar akcji replikuje czas i fazę zamachu/przeładowania; pojedynczy nabój ma własny cykl. Fizyczne profile odrzutu modelu są oddzielone od rozrzutu i podrzutu celowania. Generator: `tools/bake_combat_anim.py`, źródło: `art_src/animations/combat.blend`; test: `tools/test_combat_motion.gd`.
- **Pozycja stojąca (1.7.372):** krótszy wykrok, rozstaw stóp dopasowany do bioder, lekko ugięte kolana prowadzone w anatomicznej osi i płaskie podeszwy. Korekta miesza się z lokomocją oraz zachowuje nakładki walki. Regresja: `tools/test_standing_legs.gd`; podgląd sześciu wyglądów z boku i od przodu: `tools/shot_standing3d.gd`.
- **12 broni** (overhaul 1.6, `WEAPONS.md`): M-83, SPREAD-12, P-83, PELLET-8, LR-7 (promień), HKM-9 (miotacz), WRATH-4 (granatnik), FALCON-6 (naprowadzane), SPECTER-1 (szyna), SINEW-6 (cicha kusza), maczeta (cichy backstab), kilof. Model rozgrzania lufy per broń — krótka seria cicha, ciągły ogień głośny; **magazynki, przeładowanie, wspólny zapas drużyny**, skrzynki z mapy i drop z wrogów, podnoszenie i wymiana broni (**E**), krytyk w głowę, spadek obrażeń z dystansem, przebicie, podpalenie, wybuchy; predykcja strzału po stronie strzelca i walidacja serwera
- wrogowie: Trzosek (wataha — **atakuje po kolei**: max 2 naraz, reszta krąży; **morale**: śmierć kolegów, zwłaszcza przewodnika, rozbija watahę; **ucieka przed Stalkerem**), Wołek (tank — **szarża** z zapowiedzią rozbija skrzynie i detonuje beczki, o ścianę ogłusza; **rzuca skrzyniami** (także w górę i w dół), a bez skrzyni **głazami** po 0,5 HP — dwa trafienia to serce, przerwa zależy od trudności), **Mimik** (udaje kolegę z drużyny i woła o pomoc; zdradzają go brak serduszek nad głową, świecące oczy i dziwny numer; demaskuje go latarka, strzał albo podejście), **Ślepiec** (nie widzi, tylko słyszy: idzie do źródła hałasu — kroki wyczuwa z bliska, strzały z daleka; kucanie i cisza go mijają, latarka go nie budzi, dotyk już tak) i **Podsłuchacz** (stoi i nasłuchuje; zobaczy albo usłyszy — krzyczy po zapowiedzi 0,9 s: +14 Uwagi i cała okolica 420 px idzie do źródła; zabij go po cichu maczetą w plecy) — śpią, budzi ich strzał w pobliżu albo bliskość gracza. **Percepcja (1.6.8)**: goni tylko to, co widzi (zasięg wzroku + linia bez ściany; kucającego z bliższa), inaczej idzie na ostatni ślad (źródło hałasu, ostatnia pozycja), rozgląda się 3,5 s, a po ~9 s bez kontaktu wraca do domu i zasypia. **Pamięć wrogów**: wabik Q użyty ponownie w tym samym miejscu (140 px, 120 s) „już nie działa” — kosztuje ładunek, nikogo nie przekierowuje; wracający do domu wróg raz sprawdza „gorące miejsce”, gdzie drużyna ostatnio strzelała. **Skoczek** wisi pod sufitem i spada na tego, kto pod nim przejdzie (2 obrażenia), a **Ćma** (światłolubna, wisi pod sufitem) leci na latarkę (gryzie) i flary (spala się). **Dyrektor grozy** (`director.gd`) mierzy napięcie drużyny i po szczycie daje 45 s oddechu, a po ≥35 s ciszy wypuszcza z ciemności grupę wędrowców, której **skład zależy od czasu od startu celu i napięcia** (na początku tylko pary Trzosków; z czasem trójki i czwórki, a przy hałasie Ślepce, od 6 min Wołek; własne tabele zestawów dla map 1.1–1.3; łatwy eskaluje wolniej, trudny szybciej) (do dwóch grup naraz, nowa z przeciwnej strony niż poprzednia — „kleszcze”; uśpiona grupa poza polem widzenia znika po 45 s, żeby nie blokowała następnych; ruszają do świeżego „gorącego miejsca”, jeśli niedawno strzelano); napięcie skaluje też straszaki. **Słuch po trasie**: dźwięk liczy się długością ścieżki po grafie A*, nie linią prostą — strzał nad sufitem podziemi nie budzi sal poniżej. Chodzi po grafie A* (skoki Trzosków, zeskoki przez kładki; Wołek nie przeskoczy — czeka i rezygnuje), wataha się rozsuwa, a Trzosek po ciosie odskakuje
- **Krzyk (G albo mikrofon)**: GDD §8.2 — krzyk = Uwaga +20 i przyciągnięcie wrogów w promieniu 25 m (budzi śpiących, Podsłuchacz alarmuje, Ślepiec słyszy); cooldown 2,5 s, efekt (fala, dźwięk) widzą wszyscy. **Mikrofon (VAD)** to opt-in z lobby (przycisk MIC: OFF → LOW → MED → HIGH): wykrywa głośny, utrzymany krzyk, ignoruje szept i mowę, adaptuje się do szumu tła; dźwięk przetwarzany tylko lokalnie, nigdy nie nagrywany ani wysyłany. Bez mikrofonu to samo robi klawisz **G** (dostępność: nic nie wymaga mikrofonu)
- **Flara (F)**: światło-przynęta bez hałasu (pula drużyny 3, max 5; +1 ze skrzyni z mapy i za każdy cel). Płonie 25 s, budzi ciekawość Trzosków (idą sprawdzić, jeśli blisko po trasie) i **odciąga ćmy** — ćma, która doleci do flary, spala się
- **Raport FUN** (od 1.7.404): `python tools/fun_report.py [--split 1.7.401]` — rytm Uwagi, Stalker, Q, wyniki, broń i nagrody z dziennika sesji przed / po buildzie (`FUN_PLAN.md` §5)
- **Ryzyko i nagroda** (od 1.7.403, `FUN_PLAN.md` P2): cichy cel — Uwaga < 60 przez cały cel główny daje +30 złomu (`mission.silent_ok`, toast przy utracie, wiersz na karcie wyniku); sejfy `STRONGBOXES` w danych mapy ([kolumna, rząd, złom]; `strongbox.gd`, 1.1 i 1.2) — trzymany [E] 3 s, 3 Uwagi/s i łoskot +12, 40 złomu do łupu misji
- **Skrzynie mocy** (od 1.7.402, `FUN_PLAN.md` P1.3): `POWER_CRATES` w danych mapy ([kolumna, rząd, broń, naboje]; 1.1 WRATH-4 × 8, 1.2 FALCON-6 × 60) → znajdźka `power`; dotknięcie daje broń poza slotami (`weapon_controller.power_w`, bez przeładowania i zacięć, zmiana broni zablokowana), po ostatnim naboju albo upadku wraca broń ze slotu; serwer liczy przydział i odrzuca strzał z broni spoza zestawu
- **Rytm Uwagi** (od 1.7.402, `FUN_PLAN.md` P1.1–P1.2): hałas samych wrogów podnosi Uwagę najwyżej z budżetu (6, odnowa 2/s), krzyk Podsłuchacza bez limitu; 15 s na 100 → spadek do 70 i 8 s oddechu (pół hałasu, „THE NOISE FADES”); pancerz zbija strzał śrutem raz, nie każdą śrucinę; cios w zwarciu przechodzi przez pole Podsłuchacza
- **Przesterowanie (Q)** — zasób: celowo podnosisz HAŁAS, żeby odciągnąć stalkera (GDD §8.4); od 1.7.401 udane Q trzyma obudzonego Stalkera przy wabiku 15 s (`NoiseMgr.LURE_LOCK` — nowy hałas go nie zawraca, przerywa snop latarki), HUD: „HE TAKES THE BAIT”, odliczanie i podpowiedź „He's on P2!”, gdy poluje przy koledze (`FUN_PLAN.md` P0.2)
- **Poziom Uwagi**: bieganie/strzały dodają, cisza odejmuje; dwie prędkości decayu
- **Stalker „ON"**: budzi się przy 60%, poluje szybciej niż czatuje, wolniejszy od gracza (88 vs 95 px/s), atak nie podnosi hałasu, po ciosie się cofa; pudło daje tę samą przerwę co trafienie (1,5 s), a pudło w człowieka tuż obok to **ucieczka o włos** (zwężony kadr, przytłumiony świat, „CLOSE CALL”, raz na 5 s — `FUN_PLAN.md` P0.1); test `--funtest`
- **groza** (`scripts/dread.gd`, lokalna i kosmetyczna): fałszywe odgłosy (kroki zza pleców, skrzypienie, drzwi, szkło, pomruk), migotanie świateł po uderzeniu, **oczy w mroku** (znikają, gdy podejdziesz lub poświecisz), a w podziemiach ciemniej i częściej; tempo rośnie z Uwagą
- **AI towarzysz (BOT)** (unika ciosów: odskakuje przed zapowiedzią — także przed zamachem Stalkera, która przerywa apteczkę i defibrylator — i cofa się od wroga w zasięgu ręki; idzie **za plecami** dowódcy — po stronie przeciwnej do jego ruchu albo, gdy stoi, celowania (zmiana po 0,8 s), więc nie wchodzi w linię ognia; test `--bottest`; ranny idzie po apteczkę, nie stoi w jednym punkcie z innymi botami) wypełnia puste sloty — 1 bot gdy jesteś sam, znika przy 3+ graczach; **host może go wyłączyć** (od 1.7.400, `NOBOT_PLAN.md`): lobby „AI companion” ON / OFF, zmiana też w kryjówce (menu pauzy), nie w misji; sam bez bota pierwszy upadek w próbie to wykrwawienie i powrót na start, drugi — wipe; drezyna pompowana z mocą 1,5; dev `--nobot`, test `--nobottest`, zrzut lobby `--shotlobby --shot=PLIK`; podnosi leżących, kuca gdy kucasz, po Q wstrzymuje ogień 8 s (broni się z ≤70 px)
- 1–4 graczy online (ENet, port **8910**), synchronizacja przez `MultiplayerSynchronizer`. **Sprawdzenie wersji** przy łączeniu (uwierzytelnienie `SceneMultiplayer`, build z `config/version` + commit, jak w stopce menu): klient z innym buildem nie wchodzi do gry i dostaje powód w lobby (dev: `--fakebuild=X`). **Utrata hosta** u klienta działa jak LEAVE SESSION — scena od nowa, wyjście z lobby Steam, lobby z komunikatem, bez ponownego dołączania z `--join` / `+connect_lobby`. **Numery graczy** P1–P4: człowiek bierze najniższy wolny, bot najwyższy (sam z botem: P1 + P4). Test: `tools/test_net_session.sh`
- **serwerowe pociski** — spawn i kolizje rozstrzyga serwer, klienci tylko rysują. **Kompensacja opóźnienia** (`lag_comp.gd`, do 150 ms): serwer sam mierzy RTT strzelca (ping/pong), a pocisk i szyna klienta trafiają wrogów w pozycjach sprzed RTT + opóźnienie interpolacji (historia pozycji 0,5 s w `enemy.gd`), więc to, co klient trafił na ekranie, jest trafione
- **friendly fire = hałas**: pocisk kolegi przelatuje (zero HP), trafiony krzyczy (+4 Uwagi, max raz na 0,6 s) i dostaje odrzut; żadna broń nie rani kolegi (ranić może tylko wybuch beczki). Bot nie strzela, gdy kolega jest na linii — podskakuje (od 1.7.411 sprawdza tor, którym poleci kula: od wylotu lufy wzdłuż kierunku przyciętego do 8 stron, z marginesem na rozrzut, a nie promień prosto do wroga; test `--bottest`); **przeskakuje skrzynie i beczki** na drodze
- **apteczki** (+1 HP): wypadają z Wołków (75%) i z Żyły (2 sztuki); podnosi ranny przez dotknięcie, bot ustępuje rannemu człowiekowi. **Serca się kumulują**: apteczka przy pełnym HP dodaje złote serce ponad 3 (sufit 6), o ile w promieniu 120 px nikt nie jest ranny; nadmiar znika po śmierci, wipe'ie i nowej misji
- 3 HP, **down/revive** (GDD §4): leżysz 10 s, kolega trzyma E 4 s → wstajesz z 2 HP; wykrwawienie = powrót na start z 1 HP; **wipe** (wszyscy leżą) = restart misji po 3 s; w 1.3 od przebudzenia Żyły **punkt kontrolny** (od 1.7.401): wipe w walce wraca do jej początku (gniazda zostają zniszczone), wykrwawienie odradza przy arenie
- audio (overhaul v2, patrz `AUDIO.md`; broń 1.6: +36 assetów): 201 ścieżek, muzyka stemowa wg Uwagi (kwantyzacja do beatu), okluzja z dyfrakcją, pogłos środowiskowy, ogłuszenie po wybuchu, pozycyjny szept stalkera; część dźwięków ma lepszą wersję z nagrań, która nie może leżeć w publicznym repo — powstaje lokalnie w `audio_licensed/` (`AUDIO.md` §4, `AUDIO_PLAN.md`), a gra wybiera ją, gdy jest (dev: `--synthaudio` wymusza samą syntezę); dźwięk zasłonięty ścianą dociera drogą po mapie — od strony przejścia i z odległości równej długości tej drogi (`sound_grid.gd`, dev: `--nosoundpath` wyłącza)
- **powierzchnie (1.7.8, `surfaces.gd`)**: podłoże zmienia ruch, kroki i hałas biegu. **Bagno/płycizna** (wolniej ×0,72, ospały rozruch, niższy skok, głośny chlupot), **błoto** (×0,58, jeszcze ciężej, tłumi hałas: ×0,35 na sekundę biegu, czyli ok. 0,6 hałasu ziemi na metr — od 1.7.295; wcześniej ×0,6 na sekundę przy wolniejszym chodzie dawało na metr tyle co ziemia), **trzcina przy brzegach cieczy** (od 1.7.306: kucający w niej widoczny dla wrogów z 0,3 zasięgu wzroku zamiast 0,6 — `level.in_reeds`, `enemy.gd` REED_SIGHT; test `--enemytest`), **plama oleju** (ślizg: prawie bez przyczepności, hamowanie i zawracanie wydłużone ~10×; od 1.7.295 palna: miotacz, granat zapalający albo flara zapalają całą plamę, woda gasi ogień, w błocie żar gaśnie szybciej — `WEAPONS.md`) — kafle `m` i `O` na mapie; lód i śnieg przygotowane pod biom zimowy. Kroki: głośniejsze (+6 dB) i różne — miękka ziemia, twardy beton, dzwoniący metal, chlupiące bagno, mlaszczące błoto; potwory też zwalniają na bagnie. Oddech cichszy (−8 dB)
- **fizyka (1.5)**: bezwładność ruchu, szybsze opadanie, przysiad/rozciąganie; łuski, szczątki, krew i plamy, iskry, rozbryzgi; **skrzynie** (pchaj, stań, zepchnij z kładki = hałas-wabik) i **beczki** (wybuchają, reakcja łańcuchowa)
- **grafika (1.5)**: pixel-art ze sprite'ami (`tools/bake_sprites.py` → `art/`), kafle z wariantami, dekoracje, tło parallax; **(1.6.1)** broń przerysowana (`tools/gun_art.py`, warstwa świecąca `guns_glow.png`), HUD i celownik o 30% mniejsze (`UI_SCALE`, `CROSS_SCALE`); **(1.6.6)** postacie przerysowane od zera (`tools/char_*.py`): rig ze stawami, render w 4× z cieniowaniem rampami i obrysem selektywnym, 8-klatkowy bieg, oddech w idle, bot z wizjerem (glow)
- **HUD (1.7.6)**: **górny środek — rzut mapy (od 1.7.286, `hud_minimap.gd`)**: okno ±38 m siatki poziomu wokół gracza z mgłą (widać tylko kafle, które drużyna już widziała), cel, wyjście i koledzy z dystansem w metrach i strzałką ↑/↓, gdy cel jest wyżej lub niżej; bez wrogów; lewy górny róg — miernik hałasu ze stanem; **lewy dolny — karta drużyny** (zdrowie własne i kolegów/botów w kolorach slotów, DOWN / REVIVING, paski wykrwawiania); **środek dołu — płaski pasek broni i zasobów** (jeden rząd: nazwa + koszt hałasu, miniatura aktualnej broni na płytce z paskiem w kolorze smugi pocisku, duży magazynek + zapas drużyny, przeładowanie i ciepło lufy, sloty z miniaturami broni, wabik, flary, latarka; nie zasłania bossa)
- **pętla misji** (GDD §4): zniszcz **4 gniazda** — dwa na powierzchni (posterunek, szczyt tartaku) i dwa **w podziemiach** (trzeba zejść szybem) — są głośne i budzą okolicę → budzi się **Żyła, matka gniazd** (boss w tartaku: paszcza otwiera się tylko na chwilę po ataku — wtedy strzelaj; ataki z zapowiedzią: macka, fala ogona po podłodze — przeskocz, plucie zarodnikami; latarka w paszczę podczas zapowiedzi ją ogłusza, Q w pobliżu ją odciąga; przy 33% HP krzyk budzi Stalkera; +1 ładunek Q) → po jej śmierci wyjście otwiera się w punkcie najdalszym od drużyny → cała stojąca drużyna 3 s przy flarze → ekran wyniku, host [Enter] = nowa misja
- **nawigacja A*** (`nav.gd`): bot chodzi za drużyną po całej mapie (skoki, zeskoki przez kładki), Stalker chodzi po powierzchniach zamiast przez ściany

## Menu główne, ustawienia, podpowiedzi (demo)

- **Ekran startowy** (`main_menu.gd`): GRAJ → lobby (host / dołączanie / tryb / trudność, `lobby.gd`, przycisk WSTECZ), USTAWIENIA, WYJŚCIE
  (drugi klik w 3 s). Pomijany w headless i przy starcie z `--host` / `--join` / `--steam-*`. **Esc / Start** otwiera menu ustawień także
  przed grą; w sesji **LEAVE SESSION** wraca do ekranu startowego (`Main.leave_session`).
- **Esc / P / Start** — menu pauzy: głośność (suwaki: ogólna, muzyka, otoczenie, efekty), wstrząsy kamery (FULL / HALF / OFF), klawisz
  skradania (HOLD / TOGGLE), obsługa broni (REALISTIC — podrzut przy myszy, oparcie, gorąca lufa i dwa przeładowania, CLASSIC — dawny rozrzut serii i dopełnianie magazynka; `WEAPONS.md` §20–22), niezawodność broni (OFF / STANDARD / VETERAN — zużycie i zacięcia, `WEAPONS.md` §24), podpowiedzi, mikrofon (krzyk), **obraz bez restartu** (rozmiar okna, V-Sync, limit klatek, jakość efektów
  LOW / MEDIUM / HIGH, efekty pogody, **jasność** ±1 EV z ekranem kalibracji), pełny ekran (też F11), **dostępność** („Reduce effects” — bez wstrząsów, aberracji, pulsu
  tętna i migotania; napisy dźwięków; filtr widzenia barw: protanopia / deuteranopia / tritanopia) i **język** (ENGLISH / POLSKI; zmiana przebudowuje
  menu od razu w nowym języku; przy pierwszym starcie bez zapisu ustawień — język systemu, od 1.7.397). **Pierwszy start bez zapisu
  ustawień (od 1.7.398):** obsługa broni CLASSIC i zacięcia OFF (GDD §16.0a), a na zintegrowanej karcie graficznej Effects quality MEDIUM
  i Render scale 75% (`Settings.first_run_graphics`; osobna karta — HIGH 100%). Karta ma szerokość z zapasem na dłuższe polskie teksty, opisy ustawień łamią się w dwa wiersze, a szczegóły kodeksu
  zajmują całą szerokość strony; `--uifittest` sprawdza, że nic nie wystaje (oba języki), a `--shotpause=N` robi zrzut karty N (z `--lang=pl`).
  Ustawienia zapisują się w `user://settings.cfg`. W trybie solo gra jest zatrzymana; w kooperacji świat idzie dalej (menu to mówi)
  i klawisze gry są wyłączone na czas menu. Nawigacja: mysz, strzałki / D-pad + A, B zamyka, LB / RB przełączają zakładki.
- **Zakładki menu:** SETTINGS · **BESTIARY** (grupy: zwykli — Trzosek, Wołek, Skoczek, Ślepiec, Podsłuchacz, Mimik, Cma; elity — Kapłan / Rzeźnik / Żerca;
  szczególni — Stalker „ON", gniazdo; bossowie — Żyła, Pijawka. Portrety to rendery modeli 3D gry (`tools/bake_portraits.gd` → `art/portraits/`), statystyki liczone
  z `Enemy.KINDS`, opis, wskazówka i licznik twoich zabójstw. Od 1.7.407 z odkrywaniem: wpis wroga, którego jeszcze nie spotkałeś, to sylwetka „???”
  (`Profile.bestiary`, `bestiary_watch.gd` — wróg na ekranie albo zabity odsłania wpis i daje komunikat; profil sprzed 1.7.407 z postępem zna wszystko;
  dev: `--bestiaryfresh`) · **WEAPONS** (grupy: główna / boczna / biała; paski porównawcze siły ognia, zasięgu, głośności i masy z kreską broni przy sobie; wszystkie 12 pozycji:
  miniatura, obrażenia, tempo, zasięg, magazynek/zapas, przeładowanie, hałas, opis i wskazówka — statystyki liczone z `WeaponDef`,
  więc nie rozjeżdżają się z grą) · GEAR · PERKS · **CONTROLS** (edytor przypisań: klik w klawisz lub przycisk pada, potem nowy;
  obsługuje także mysz, kółko, przyciski M4/M5, dodawanie (+), usuwanie (×) i akcje bez początkowego przycisku pada.
  Plan pokazuje wszystkie zmieniane akcje przed zatwierdzeniem; zamiana jest atomowa i sprawdzana w kontekstach misji,
  strzelnicy i menu. Niebezpieczny konflikt jest odrzucany. Esc zawsze anuluje/zamyka/pauzuje; osie ruchu są stałe.
  APPLY CLASSIC / APPLY MODERN wymagają świadomego zatwierdzenia. Zapis w sekcji `keys` pliku ustawień). Dane i teksty: `codex.gd`, widok: `codex_page.gd`.
- **Podpowiedzi** (`hints.gd`): krótkie, jednorazowe wskazówki w chwili, gdy mechanika się przydaje (pierwszy ruch, pierwszy
  hałas, „SOMETHING IS LISTENING", leżący kolega, latarka, flara, kryjówka). Zapamiętane — weteran ich nie zobaczy; wyłącznik w menu.
  Teksty używają znaczników `{id}` (np. `{interact}`) — klawisz bierze się z rejestru akcji, więc zmiana przypisania zmienia podpowiedź.
- **HUD** (`hud.gd`): wskaźnik hałasu to analogowy VU-metr (strefy CALM / UNEASY / HUNTED z progów `NoiseMgr`); jeden komunikat naraz
  (ostrzeżenie o hałasie > nota > podpowiedź); karta celu i dane sesji przygasają po 4 s spokoju; ściemnienie HUD-u pod kartą wyniku
  i warsztatem; karta wyniku ma tabelę graczy (zabójstwa / upadki / podniesienia) i od 1.7.401 wyróżnienia GHOST / MEDIC / BAIT / CLOSE SHAVE / BUTCHER
  (`Mission.awards`), a w kampanii host wybiera [Enter] — kryjówka albo [Interakcja] — od razu następna misja z zachowanym ekwipunkiem (`FUN_PLAN.md` P0.4–P0.5).
- **Czcionki** (`art/fonts/`, licencje w `art/fonts/licenses/`): Big Shoulders Stencil Display (nagłówki), IBM Plex Sans Condensed
  (opisy i ustawienia), IBM Plex Mono (liczby i przyrządy) — SIL OFL; Special Elite („szept”: ostrzeżenia, podpowiedzi) — Apache-2.0;
  Silkscreen tylko w klasycznej grafice. Wczytuje je `ui_theme.gd`; bez plików wraca do czcionek systemowych.
- **Czat drużyny** (`chat.gd`, klawisz **T**): Enter wysyła, Esc anuluje; wiadomość idzie do serwera, który sprawdza ją (długość 120, znaki
  sterujące, odstęp 0,6 s na gracza) i rozsyła z etykietą nadawcy (P1, P2…). Linie widać nad kartą drużyny przez 9 s. **Mono audio**
  (Ustawienia → Accessibility) wyłącza panoramę w dźwięku pozycyjnym.
- **Napisy dźwięków** (`captions.gd`, ustawienie „Sound captions”): linie `← [Gunfire]` z kierunkiem do źródła i `(far)`, z tabeli
  `CAPTIONS` w `audio_manifest.gd` (priorytet 0 — kroki, łuski — pomijany).
- **Lokalizacja** (`translations/ui.csv`, kolumny `keys` = tekst angielski i `pl`): statyczne napisy `Label` / `Button` tłumaczy silnik,
  sformatowane teksty przechodzą przez `tr()`. Nowy tekst UI: dopisz wiersz do CSV (po `godot --headless --path prototype --import`
  powstaje `ui.pl.translation`). Poza tabelą są opisy bestiariusza / broni / sprzętu, ulepszenia, perki i wygląd.
- **Wersja demo**: `Settings.DEMO` (domyślnie `true`) dodaje na ekranie końcowym misji zachętę do listy życzeń; po wpisaniu
  `Settings.STORE_URL` pojawia się klawisz [O] otwierający stronę sklepu. Lista kontrolna playtestu i publikacji: `PLAYTEST.md`.

## Poziomy trudności

Host wybiera w lobby przyciskiem **DIFFICULTY** albo flagą `--difficulty=easy|normal|hard` (domyślnie **NORMAL** = dotychczasowa gra; wybór z menu głównego albo lobby jest zapamiętywany w `user://settings.cfg`). Wartość trafia do klientów przy dołączeniu, widać ją w HUD (prawy górny róg). Mnożniki: `scripts/difficulty.gd` (autoload `Difficulty`).

| | EASY | NORMAL | HARD |
|---|---|---|---|
| HP wrogów / Żyły | ×0,7 | ×1 | ×1,35 / ×1,4 |
| Prędkość wrogów / Stalkera | ×0,85 | ×1 | ×1,15 / ×1,05 (Stalker nadal wolniejszy od gracza) |
| Zapowiedź i przerwy ataków (wrogowie, Stalker, Żyła) | ×1,3 | ×1 | ×0,8 |
| Zasięg słyszenia wrogów | ×0,8 | ×1 | ×1,25 |
| Obrażenia wrogów | Wołek 2→1 | bez zmian | bez zmian |
| Przyrost Uwagi (hałas) | ×0,75 | ×1 | ×1,25 |
| Częstość straszaków (groza) | ×0,6 | ×1 | ×1,5 |
| Drop apteczek / amunicji | ×1,5 | ×1 | ×0,7 |
| Wykrwawianie / podnoszenie kolegi | 15 s / 3 s | 10 s / 4 s | 7 s / 5 s |

## Misje i mapy (Strefa I)

**Misja 1.1 „Missing Patrol”: przechodzący Stalker (od 1.7.279).** Mapa nie ma domu Stalkera (`X`), tylko `STALKER_PASS` w danych mapy: Stalker czeka poza mapą, a gdy w fazie celu — po pierwszym nieśmiertelniku (`after_goal`) — Uwaga przekroczy 80 (na HARD 95, `noise_hard`: hałas rośnie tam o 25% szybciej), wychodzi z ciemności za plecami drużyny (węzeł grafu 380–640 px od jej środka, na tym samym piętrze, ponad 300 px od każdego człowieka; gdy z tyłu nie ma miejsca — z przodu). Przez 28 s poluje na hałas jak zwykły Stalker, potem przez najwyżej 8 s wycofuje się tam, skąd wyszedł, i znika. Następne przejście może nastąpić po 90 s, ale dopiero po spadku Uwagi poniżej progu. Odprawa go nie zapowiada (ostrzega alert hałasu); w finale i ekstrakcji nie wychodzi. Dziennik sesji: `stalker` z `what` = `pass_in` / `pass_out`. Test: `--host --mission=z1_m1 --passtest`. **Porada w obozie (od 1.7.281):** jednorazowa porada `camp` na podejściu, póki wataha śpi (latarnię patrolu i czerwone wstążki pod konarami usunięto w 1.7.308 — zbędne światła w kadrze) (`HINT_ZONES` w danych mapy → `level.hint_zones`, `hints.gd`). **Strażnica (od 1.7.282):** przed rampą kopalni wieża z zygzakiem podestów i włazem, pod dachem trzy Ćmy i Skoczek, szósty nieśmiertelnik na górnym piętrze; skrzynka z flarami przy podejściu i porada `moths` (lekcja flary: ćmy lecą do latarki i błysków z lufy, w flarze się spalają). **Powrót przez obudzony las (od 1.7.283):** mapa nie ma już wyjścia „e” przy szybie — po zawale ekstrakcja jest przy `E` na starcie (`mission._start_finale`: bez „e” zostaje najdalsze `E`), a finał wypuszcza na drogę powrotną śpiące grupy z `FINALE_SPAWNS` (`level.spawn_finale`, nazwy `Finale1…`, RPC do wszystkich peerów i dołączających; restart je usuwa). Przechodzący Stalker działa też w ewakuacji (`extract` w `STALKER_PASS`). Konar E (kol. 111–112) daje cichą drogę przez obóz także na zachód. W ewakuacji przechodzący Stalker wychodzi za plecami względem kierunku do wyjścia (`stalker.behind_side`), a nie zawsze z zachodu. **Bród (od 1.7.284):** między startem a polaną płycizna i błoto (lekcja powierzchni) z Wołkiem śpiącym na skarpie nad błotem; porada `ford`. Od 1.7.296 bród jest przejściem przez strumień: `STREAMS` w danych mapy (`level.streams`, kosmetyka) — koryto wypływa z lasu w głębi, meandruje i zwęża się, wzdłuż brzegów stoją trzciny i drzewa, w nurcie kamienie (`Level3D.build_streams`); niecka w tym miejscu nie ma tylnego brzegu.

Kampania gra misje po kolei, a nowa sesja zaczyna od misji po najdalszej ukończonej przez drużynę (od 1.7.392: `Scrap.cleared`, sekcja `[campaign]` w `progress.cfg` hosta; starszy zapis przejmuje ukończone misje z profilu hosta; po bossie znowu od 1.1). Przy tablicy odpraw w kryjówce [Interakcja] przełącza cel wyjścia na każdą ukończoną misję albo następną (`main.request_brief_cycle`, serwer sprawdza pozycję przy tablicy, cel `after_hub` trafia do klientów w `mission._sync`; zmiana odnawia odliczanie wyjścia). Kolejność: **1.2 „Przerwa w Nadawaniu"** (uruchom 4 generatory rozrzucone po mapie 288×44 — przytrzymaj [E], ok. 5,5 s i hałas — nadajnik rozbrzmiewa na cały las, Stalker idzie na źródło, wracasz na początek mapy; cel poboczny: Uwaga < 40 do ostatniego generatora) → **1.3 „Gniazdo"** (zniszcz gniazda, zabij Żyłę, ekstrakcja) → od początku. Mapy to dane w `scripts/maps/<id>.gd` (`MAP` jako siatka ASCII, `TITLE`, `OBJECTIVE`, `UNDERGROUND_ROW`, `WEAPONS`, `ACCENTS`), rejestr i kolejność kampanii (`MAPS`, `CAMPAIGN`) w `level.gd`; legenda znaczników w nagłówku `level.gd` (m.in. `G` = generator). Nowa mapa: dodaj plik, wpisz do `MAPS`/`CAMPAIGN`, uruchom `--maptest`. Host przełącza mapę u wszystkich peerów (`main._set_map`), a dołączający dostaje ją przed postacią.

**Drezyna (ucieczka z 1.2).** Po ostatnim generatorze zasilanie dostaje drezyna (`D`) na wschodnim końcu głębokiego tunelu pod mapą; wejście szybem przy maszcie. Stań na pokładzie i **trzymaj [E] — pompujesz** (nie możesz wtedy strzelać ani chodzić); dwie osoby jadą szybciej, boty na pokładzie pomagają (gdy człowiek jest przy drezynie, boty wsiadają, stoją na pokładzie i jadą z drużyną; zostawiony w tyle bot ląduje na pokładzie). Pokład leży równo z torem, więc strzały z drezyny lecą na wysokości strzałów z ziemi. Jazda hałasuje i budzi wrogów przy torze, a Stalker goni (88 px/s). Tor kończy się przy wyjściu `E`. **Kryjówka** (`z1_hub`, strefa bezpieczna — bez wrogów i straszaków) czeka między misjami kampanii: amunicja, **zbrojownia** — dwie gabloty po cztery broni (`cabinet.gd`, `ARMORY_PLAN.md`): [F] przy gablocie ustawia kamerę na wprost niej, ↑ / ↓ wybiera broń, [E] ją bierze, panel pokazuje statystyki, **tablica z odprawą** następnej misji (podejdź: cel i zagrożenia z mapy), ciepłe światło lamp, radio; ekwipunek przechodzi dalej, a [Enter] hosta rusza do następnej misji. **Układ „Stacja Dead Air” (od 1.7.265):** 72 × 36 kafli, trzy poziomy co 8 kafli połączone dwoma szybami (kraty w podłodze i podesty co 2 kafle; w dół zeskakuje się przez kratę, S+SPACE). **Środek:** śluza z dwoma punktami startu → ściana wyników → warsztat → świetlica (meble) → zbrojownia → tablica odpraw. **Góra:** radiostacja z prognozą nad tablicą odpraw. **Dół:** maszynownia i magazyn z dwiema skrytkami (`H`). Dane w `scripts/maps/z1_hub.gd` (`SHAFTS` = kolumny szybów); meble z `hub_decor.gd` stają osobno na każdym poziomie ze stanowiskami. Dev: `--shotat=KOLUMNA --shotrow=WIERSZ` wybiera piętro zrzutu (wiersz 15 = środek, 7 = góra, 23 = dół). **Strefa startu (od 1.7.266):** pasy ostrzegawcze przed drzwiami wyjścia (`LAUNCH_ZONE` w danych mapy: kolumny i wiersz podłogi). Kto w niej stoi, jest gotowy; gdy gotowi są wszyscy ludzie, rusza odliczanie 3 s (`HUB_COUNTDOWN`; to samo przy [Enter]), a wyjście ze strefy je anuluje. **Wizualizacja (od 1.7.268):** pad na podłodze strefy i kurtyna światła w kolorze stanu (czerwony: pusto, bursztynowy: część drużyny, zielony: odliczanie), reflektor z sufitu, po jednym polu na człowieka (zapalone u gotowych), duża cyfra w HUD (od 1.7.307 bez cyfr na drzwiach i koguta, a kurtyna światła gaśnie 2 m nad podłogą), napis STREFA STARTU i licznik „gotowi / wszyscy” pod lampą; dźwięk: tyk co sekundę o rosnącym tonie (`ui_click`), potwierdzenie na zerze (`ui_confirm`), odmowa i czerwony błysk przy anulowaniu (`ui_deny`). [Enter] działa jak dotąd poza strefą. Serwer czyta pozycje graczy (`main._hub_zone_ids`), klienci dostają listę gotowych w `_hub_state`. Lampa ON AIR nad drzwiami (`launch_door.gd`, model w `view3d._build_launch_door`): czerwona — nikt nie gotowy, pulsująca bursztynowa — część drużyny, zielona — wszyscy i trwa odliczanie. **Maszynownia i okno (od 1.7.267):** rekwizyty z `HUB_PROPS` w danych mapy (`hub_prop.gd`, bryły i światła w `view3d._build_hub_prop`): na dole generator z klatkową lampą (mruga, w burzy na chwilę siada) i buczeniem `generator_loop` słyszalnym tuż przy nim, rury pod stropem, sprężarka, beczki, skrzynie i kupka złomu w magazynie oraz zamknięte drzwi D-7 (czerwony pas światła pod nimi błyska, gdy co 30–80 s ktoś zastuka zza drzwi; dźwięk `amb_thud`). Na górze okno radiostacji pokazuje prognozowaną pogodę (pogodnie: gwiazdy i księżyc, deszcz: smugi, burza: smugi i błyski rozświetlające pokój, mgła: mleczna szyba). Wszystko kosmetyczne i lokalne. **Notatki (od 1.7.269, `MESSAGES_PLAN.md`):** odprawa i prognoza to notatki-papier (`note_paper.gd`) w trzech materiałach zależnych od źródła informacji: akta sztabu (Special Elite, pieczątka POUFNE) dla odprawy, wydruk z radia (VT323, odwrócony: ciemne tło i zielony tekst, perforacja) dla prognozy i kartka odręczna (Caveat, kratka, taśma, kreski za misje) dla ostrzeżeń i porad. Ciemna paleta po zmroku (`note_palette.gd`: luminancja papieru ≤ 0,3, tekst ≥ 4,5:1, pilnuje `tools/test_note_contrast.gd`), jasność notatki zależy od ciemności mapy, a plamy i przypalenia brzegów rosną z liczbą upadków drużyny w kampanii (`RunLog`). Pasek akcji dostaje klawisze jako klawisze (`UiTheme.keycaps`) i kandydatów z wagami zamiast łańcucha `elif` (`hud._prompt_candidates`, arbiter `Msg`). **Kanały komunikatów (od 1.7.270):** ostrzeżenie o hałasie, SQUAD DOWN i odliczanie wyjścia to alerty pod kartą celu (jedna wiadomość naraz wg wagi, odliczanie jako duża cyfra), XP, awans, noty i komunikaty sieciowe to stos toastów (do trzech, XP sumuje się) pod kartą RUN, a baner startu misji to karta tytułowa w dolnej trzeciej po lewej (tytuł, linie radia, jedna linia pogody; cel zostaje w karcie celu). Renderuje je `message_view.gd`, producenci wołają `Msg.post()` / `Msg.hold()`. Odprawa i prognoza chowają się na czas alertu. Wiersze `ui.csv` dopisane dla komunikatów, które ich nie miały. **Dziennik i porady (od 1.7.271):** klawisz **N** (akcja `journal`, do przypisania w CONTROLS; na padzie bez domyślnego przycisku) otwiera dziennik: ostatnie 30 komunikatów (karty tytułowe, toasty, noty, alerty zdarzeniowe, porady) z czasem sesji i spis odkrytych porad; ten sam klawisz albo Esc zamyka, gra toczy się dalej pod panelem (`journal_view.gd`, dane w `Msg.journal`). Porady z `hints.gd` idą kanałem TIP (lewy dół nad kartą drużyny, tylko gdy nie ma alertu, toastu ani karty tytułowej) i trafiają do dziennika. Dev: `--shotjournal` (otwarty dziennik z przykładowymi wpisami do zrzutu). **Papier w świecie (od 1.7.272):** odprawa wisi jako kartka na tablicy odpraw, a prognoza jako wydruk na ścianie nad radiostacją: te same notatki rysowane do tekstury w `SubViewport` (`hud._build_world_notes`) i kładzione na quadzie w scenie (`view3d._sync_world_notes`), oświetlone lampami; chowają się, gdy gracz stoi blisko i ta sama treść jest czytelna w karcie HUD. Tekstura odświeża się tylko przy zmianie celu misji, pogody lub zużycia. Wszystkie komunikaty (alerty, toasty, karta tytułowa, porady, dziennik, notatki HUD i pasek akcji) są o 20% mniejsze (`MSG_SCALE` w `hud.gd`). Projekt i plan: trzy PR-y (mapa, strefa startu, maszynownia). Mapa może mieć własny `AMBIENT`, `RACKS`, `CABINET_SLOTS` (każde „g” to gablota na tyle broni) i `BRIEF` w danych.

**Radiostacja w kryjówce (prognoza pogody, GDD §10.3):** obiekt `R` (`radio_set.gd`) — przy nim HUD pokazuje prognozę na następną misję kampanii (`weather.gd`: CLEAR NIGHT / RAIN / STORM / FOG, każda z plusami i minusami: hałas, amunicja, Uwaga na starcie, progi Stalkera). Prognozę losuje serwer przy wejściu do kryjówki, po wyjściu staje się pogodą misji (wipe ją zachowuje, Nocny Dyżur i powrót do kryjówki kasują); wartości idą do klientów przez `mission._sync`, a efekty przez te same mnożniki co modyfikatory Nocnego Dyżuru (`NightShift.*`). Baner startu misji pokazuje linię „WEATHER”.

**Efekty pogody (`weather_fx.gd` — stan i dźwięk, obraz w `view3d.gd: _sync_weather`):** kosmetyczne i lokalne. Deszcz (RAIN, STORM) pada pod otwartym niebem, dachy przycina shader kropel; harmonogram błyskawic wynika z ziarna misji (`Weather.seed`) i zegara misji, więc jest wspólny dla graczy bez RPC. Pogoda zmienia w scenie 3D zachmurzenie, gwiazdy i tarczę księżyca na niebie, siłę księżyca, gęstość mgły wolumetrycznej i mgły przy ziemi (FOG: gęsta bryła z bladą poświatą, bliższa mgła głębi), wiatr w koronach. Błysk burzy (od 1.7.384) rozświetla w pełni niebo, chmury, mgłę głębi, las i jego dno (światło `StormFlash` tylko na warstwach lasu i dna, `Level3D.LAYER_FAR`), a plan gry i postacie dostają tylko mały udział (`view3d.FLASH_PLANE`): pomiar na starcie 1.1 — plan ×2,5 przy pełnym błysku i ×1,4 przy REDUCED (wcześniej ×20,5 i ×4,3), więc błyskawica nie odsłania na chwilę ciemności wokół drużyny; karta STORM to mówi. Ustawienie **Weather effects** (menu pauzy): FULL / REDUCED (domyślne: miękka poświata zamiast błysku) / OFF. **Dźwięk:** pętle deszczu (na zewnątrz / pod dachem wg otwartości nieba) i wiatru, grzmot po błyskawicy z opóźnieniem z ziarna misji (wspólny dla graczy bez RPC), mokre kroki w deszczu; nowe assety `amb_rain`, `amb_rain_roof`, `thunder_1..3` (`tools/bake_amb.py`, `bake_sfx.py`). **Faza D (HUD):** wiersz z pogodą i skutkami pod miernikiem hałasu oraz tarcza i dioda radiostacji w kolorze prognozy. Dev: `--shotweather=clear|rain|storm|fog`, `--shotflash` (pełny błysk na stałe) albo `--shotflash=K` (stała siła 0..1, 0 = bez błysków — pomiary A/B).

**Jasność (od 1.7.383, `brightness_screen.gd`):** ekspozycja obrazu świata przed tonemappingiem w zakresie ±1 EV co 0,25 (`Settings.BRIGHTNESS_EV`), ta sama dla środowiska świata i warstwy graczy (`view3d._apply_brightness`) oraz tunelu strzelnicy; menu i HUD bez zmian. Zakres jest wąski celowo: wystarcza na monitor z „zjedzoną” albo podniesioną czernią, ale nie rozjaśnia nocy (GDD §8.3). Ekran kalibracji pokazuje trzy oczy na czystej czerni o stałych jasnościach tuż przy progu czerni (kontrast 1,1 obcina do zera wszystko poniżej ok. 0,0035 jasności liniowej), renderowane gradacją gry (`Level3D.apply_grade`); gracz ustawia jasność tak, żeby środkowe było ledwo widoczne, a lewe znikło. Pojawia się przy pierwszym starcie przed menu głównym (`Settings.brightness_calibrated`), potem z wiersza **Brightness** w ustawieniach (CANCEL / Esc przywraca poprzednią wartość). Testy: `tools/test_brightness.gd` (headless, logika ekranu i ustawienia), `tools/probe_tonemap.gd` (z oknem, Forward+: krzywa obrazu i jasności symboli przy −1…+1 EV). Dev: `--brightness=0..8` (indeks, 4 = 0 EV, bez zapisu).

Testy jazdy: `godot --headless --path . -- --host --mission=z1_m2 --ridetest --autoquit=100`; sieciowy: host `-- --host --mission=z1_m2 --ridehost --autoquit=45` i klient `-- --join=127.0.0.1 --rideclient --autoquit=40`.

Testy: `godot --headless --path . -- --maptest --autoquit=4` (kształt siatki + osiągalność z grafu nawigacji: start → cele/wrogowie/przedmioty/wyjścia i z powrotem), `godot --headless --path . -- --host --mission=z1_m2 --gentest --autoquit=35` (cała misja 1.2 i przejście 1.3 ↔ 1.2). `--mission=ID` wybiera mapę startową (testy 1.3 wymuszają `z1_m3` same).

## Profil, XP i perki

Każdy człowiek ma **lokalny profil** (`user://profile.cfg`, autoload `Profile` — poza zapisem hosta): XP, ukończone misje i założone perki. XP daje serwer (zabójstwa, misje, podnoszenie kolegi; Nocny Dyżur połowę), poziomy: L2 150, L3 400, L4 750, L5 1200, L6 1750 XP. Karta wyniku pokazuje całe XP zarobione od poprzedniego wyniku: za misję i za zabójstwa oraz podniesienia (`Profile.last_run_xp`, od 1.7.392). Komunikat o próbce i podpowiedź przy pracowni mówią, że badania wymagają kupionej broni specjalnej (LR-7, HKM-9, WRATH-4), dopóki drużyna żadnej nie ma (`Scrap.has_lab_weapon`). **Sloty perków:** 1 od L2, 2 od L4; perk odblokowuje poziom (`perks.gd`: L2 Ciche kroki, Krwiobieg, Szerokie ramię, Kowal; L4 Zimna krew, Zwiadowca, Druga szansa; L6 Weteran). Zakładasz je w kryjówce przy szafkach osobistych w świetlicy (od 1.7.349; panel SZAFKA, zakładka **PERKS**, Tab) albo oglądasz w menu pauzy (karta PERKS). Założone perki replikuje właściciel (`player.perks`), skutki (hooki w `player.gd`, `voice.gd`, `scrap.gd`, `scanner_view.gd`) czytają parametry z `perks.gd`; boty perków nie mają. Dev: `--shotperks`, `--shotperkcard` (zrzuty; nie zapisują profilu). Testy: `--weapontest` (krzywa, sloty, skutki) i test sieciowy (perki klienta widoczne na hoście).

## Nocny Dyżur (tryb endless, v1)

W lobby host przełącza `MODE: CAMPAIGN / NIGHT SHIFT` (albo `--nightshift`). **Seria 5 misji pod rząd** na tej samej mapie; **wipe kończy serię**, [Enter] na ekranie wyniku zaczyna następną misję (po serii lub porażce — nową serię). Każda kolejna misja: **HP wrogów i bossa +12%** oraz losowe modyfikatory (misje 2–3: jeden, 4–5: dwa) — OVERLOAD (Uwaga startuje od 50), AMMO FAMINE (połowa amunicji), LEAK (Stalker budzi się przy 45, zasypia przy 15), THIN WALLS (hałas +50%). Zasady misji pokazuje HUD w pierwszych sekundach. Rekord (najwięcej misji; przy pełnej serii — czas) zapisuje się lokalnie w `user://settings.cfg`; rankingu online nie ma. Stan: `scripts/night_shift.gd` (statyczny, replikowany przez `mission._sync`). Test: `godot --headless --path . -- --nightshift --host --shifttest --autoquit=8`.

## Steam (opcjonalnie): lobby, zaproszenia, relay

Gra łączy się przez ENet (IP) jak dotąd, a **Steam** jest dodatkowym transportem — bez konfiguracji routera, z zaproszeniami od znajomych i relayem Valve (graczom z różnych krajów nie trzeba otwierać portów). Kod: `scripts/steam_net.gd`. Wtyczka **GodotSteam 4.23 (GDExtension, Godot 4.4+)** leży w `addons/godotsteam/` (tylko Linux x64 + Windows x64) i zawiera już `SteamMultiplayerPeer` — **nie dodawaj** osobnego addonu steam-multiplayer-peer, bo klasy się dublują. Bez Steama przyciski w lobby są wyszarzone, a reszta gry działa normalnie.

Instalacja (raz):
1. Wtyczka jest już w repo. Aktualizacja: gałąź `gdextension-plugin` na codeberg.org/godotsteam/godotsteam (GitHub jest zarchiwizowany), skopiuj `addons/godotsteam/`.
2. Zainstaluj i uruchom klienta Steam, zaloguj się. W katalogu projektu leży `steam_appid.txt` z `480` (**Spacewar** — publiczny App ID testowy, darmowy; w bibliotece gra pokazuje się jako „Spacewar"). Testerzy muszą mieć Steama i być znajomymi hosta.
3. W lobby: **STEAM HOST** tworzy lobby (ID ląduje w schowku i w statusie), **F2** w grze otwiera okno zaproszeń Steam (overlay działa tylko, gdy gra jest uruchomiona ze Steama — np. dodana jako „grę spoza Steam"; z gołego pliku .exe zwykle go nie ma, wtedy F2 pokazuje komunikat, kopiuje ID lobby do schowka i trzeba wysłać je znajomym — wklejają i dają STEAM JOIN; bez lobby Steam, np. po HOST GAME przez IP, F2 mówi, że nie ma lobby), znajomi klikają „Dołącz do gry" albo wklejają ID i dają **STEAM JOIN**. Flagi: `--steam-host`, `--steam-join=ID`; start z zaproszenia (`+connect_lobby ID`) też działa.
4. Pod wydanie: własny App ID (Steam Direct, 100 USD zwrotne po 1000 USD przychodu) — zmień `APP_ID` w `steam_net.gd` i `steam_appid.txt`, a plik usuń z paczki sklepowej.

API GodotSteam różni się między wersjami, więc wrapper dobiera argumenty po nazwach i obsługuje dwa warianty peera (wbudowane lobby `create_lobby`/`connect_lobby` oraz surowe `create_host`/`create_client`). Wtyczka ładuje się, a sygnatury API zgadzają się z wrapperem (sprawdzone sondą w Godot 4.7.2); w grze działa wariant surowego P2P. Nie testowano z działającym klientem Steam — pierwszy test: dwa konta Steam będące znajomymi.

### Playtesty przez Steam (App ID 480)

```bash
godot --headless --path prototype --export-release "Linux"     # -> build/linux/
godot --headless --path prototype --export-release "Windows"   # -> build/windows/
cp prototype/steam_appid.txt build/linux/ ; cp prototype/steam_appid.txt build/windows/
```

Presety są w `export_presets.cfg` (szablony eksportu 4.7.2 muszą być zainstalowane). Testerom wyślij zipem cały folder (`.pck`, biblioteki i `steam_appid.txt`) — paczkę z instrukcją dla testera (`tools/testers_readme.txt` → `CZYTAJ.txt`) robi `tools/package_build.sh [Windows|Linux]` po `tools/export_build.sh`, wynik: `build/dead-air-87_<wersja>+<commit>_<system>.zip`. Każdy tester: Steam uruchomiony i zalogowany, wszyscy muszą być **znajomymi na Steamie** z hostem. Host: STEAM HOST, potem F2 albo wysłanie ID lobby; reszta: „Dołącz do gry” albo ID + STEAM JOIN. W Steamie tester widnieje jako grający w „Spacewar”.

## Dziennik sesji (playtesty)

Host zapisuje przebieg każdej misji do `user://sessions/<data>_<godzina>.jsonl` (Windows: `%APPDATA%\Godot\app_userdata\Dead Air '87 Prototype\sessions\`), jeden wiersz JSON na zdarzenie: start misji (wersja buildu, zestaw dźwięku, mapa, trudność, skład), zmiany fazy, **upadki ze źródłem ciosu, Uwagą i bronią w ręku**, podniesienia i wykrwawienia, przebudzenia i zamachy Stalkera (trafione / chybione, w człowieka czy bota), użycia Q, **co 3 s pozycje graczy** (ludzie i boty: miejsce, życie, kucanie, leżenie, do tego faza i Uwaga), **zaliczone cele** (nieśmiertelnik, skrytka, generator, gniazdo, boss: który z ilu, gdzie i kto) oraz wynik: czas, upadki, szczyt Uwagi, **strzały / Uwaga / obrażenia / zabójstwa wg broni**, złom (ile wypadło z wrogów, ile drużyna zebrała, premia za misję) i Uwaga wg źródła (strzały, bieg, ból, krzyk, Q, świat). **Progresja (od 1.7.391, `PROGRESSION_PLAN.md` P0):** start misji zapisuje też XP, poziom, perki i wygląd każdego człowieka (replikowane `player.prof_xp`), koniec — zabójstwa ludzi wg rodzaju wroga i XP za nie (`players[id].kinds`, `xp_kills`), a po udanej misji wiersz `xp` od właściciela profilu (XP za wynik, etykiety bonusów, łączne XP i poziom); każda rozstrzygnięta operacja warsztatu to wiersz `hub_buy` (broń, część, zaopatrzenie, prasa, badanie, tokarka, serwis: koszt, wynik, powód odmowy, bank po operacji). **Raport progresji:** `python tools/session_progress.py [--since 2026-10-27] [--min-humans 2] [--json PLIK]` — tempo kampanii, złom i XP na misję i minutę wg mapy, poziomy i perki, zakupy i odmowy w kryjówce, próbki, udział broni, Nocny Dyżur i sygnały ostrzegawcze z progami planu. Plik zostaje na dysku hosta i nigdzie nie jest wysyłany; klient go nie pisze. Opis pól: `scripts/session_log.gd`. Tryb headless nie pisze, chyba że podasz `--sessionlog=KATALOG` (tak robi CI). **Mapy cieplne i czasy odcinków:** `python tools/session_heatmap.py [--map z1_m1] [--build 1.7.27] [--difficulty NORMAL]` czyta te pliki i dla każdej mapy rysuje `build/heatmap/<mapa>_heat.png` (rzut siatki, poświata = gdzie drużyna spędza czas, linie tras, krzyżyki upadków w kolorze sprawcy) oraz wypisuje raport: wyniki, czas udanej misji, mediana czasu do kolejnych celów i udział czasu w pasach po 20 kolumn (`--json PLIK` zapisuje go do pliku, `--bots` dolicza boty).

**Przerwane misje i friendly fire (od 1.7.397):** wyjście z gry albo LEAVE SESSION hosta w trakcie misji zamyka ją w dzienniku wierszem
`mission_end` z `"result": "quit"`, `how` (`exit` / `leave`) i fazą — `tools/session_progress.py` liczy je w kolumnie „przerw” (także po wipe'ie).
Każde friendly fire to zdarzenie `ff` ze strzelcem i ofiarą (`shooter`, `shooter_bot`, `victim`, `victim_bot`; najwyżej raz na 0,6 s na ofiarę).

**Wydajność (od 1.7.389):** każdy uruchomiony egzemplarz gry — host i klient — dopisuje do swojego pliku wiersz `system` (karta graficzna, procesor, RAM, ekran, okno, jakość, V-Sync, limit klatek) i co 10 s wiersz `perf` (`fps`, średnia, p50, p95 i maksimum czasu klatki w ms, `spikes` — klatki powyżej 50 ms, `gpu` — ms GPU świata i warstwy graczy, `map`), także w kryjówce. Klient pisze plik z samymi tymi wierszami: po playteście trzeba zebrać katalog `sessions` z każdego komputera, nie tylko od hosta. Od 1.7.390 czas przestoju jest liczony zegarem: `delta` silnik przycina do 8 kroków fizyki (ok. 133 ms przy 60 Hz), więc dawne wiersze `perf` zapisywały każdy dłuższy przestój jako ok. 133–150 ms. Dev: z `--verbose` (opcja silnika, przed `--`) każdy przestój drukuje `[SPIKE-MARK]` tuż pod wczytanymi w tej klatce zasobami i shaderami, a wolna klatka widoku 3D (> 20 ms) — `[V3D-SLOW]` z najdroższymi częściami.

**Wersja buildu** (`config/version` w `project.godot` + skrót commita) jest w stopce menu głównego i w każdym `mission_start`. Eksport dla graczy rób przez `tools/export_build.sh [Windows|Linux]`: zapisuje skrót commita do builda i odmawia eksportu bez dźwięku z nagrań (`audio_licensed/`; `--allow-synth` wymusza).

## Uruchomienie

```bash
# okno 1 — host
godot --path . -- --host

# okno 2 — klient
godot --path . -- --join=127.0.0.1
```

Bez parametrów: lobby z przyciskami **HOST GAME** / **JOIN** (Enter w polu IP = dołącz). Interfejs po angielsku albo po polsku (ustawienie języka).

**Wczytywanie mapy (od 1.7.397, krokami od 1.7.399):** najpierw rysuje się czarna plansza „LOADING…” (`view3d._show_curtain`), potem
świat 3D buduje się krokami po jednym na klatkę (`_build_steps`: teren, kratownice, ciecze, dekale, runo, dekoracje, mgła, las, tło), a po nim
w kolejnych klatkach wchodzą grupy modeli (`_warm_stage`: wrogowie → przedmioty → rekwizyty kryjówki → stanowiska → bronie). Najdłuższa
klatka spadła z 4–8 s do ok. 1–2 s (i9 + RTX 3080, z `--verbose`), więc okno nie „zawiesza się” dla systemu. Bez planszy i krokami nie
przy zrzutach (`--shot*`, `--view3dsave*`, `-s tools/…`), pomiarach `--perf*` i nagraniach `--write-movie` — tam wszystko w jednej klatce,
jak dawniej. Dev: `--verbose` → `[LOAD-CURTAIN] on/off`, `[V3D-BUILD] krok ms`; `--loadshot=PLIK` — zrzut 1 s po zejściu planszy i koniec.

## Sterowanie

| Akcja | Klawisz | Pad |
|---|---|---|
| Ruch | WASD lub strzałki | lewy drążek |
| Celowanie | 8 kierunków wg ruchu / mysz (gdy celujesz myszą, WASD tylko porusza; spust z klawiatury wraca do 8 kierunków) | prawy drążek (swobodnie 360°) |
| Skok | SPACJA | A |
| Strzał | J lub LPM | RT |
| Skradanie (cisza) | SHIFT | L3 |
| **Przesterowanie** | **Q** | LB |
| Podnieś kolegę (przytrzymaj) / podnieś broń | E | B |
| Broń (2 główne + sidearm) | 1 / 2 / 3, kółko myszy | Y (następna) |
| Przeładowanie (krótko — szybkie, magazynek spada; przytrzymane — taktyczne; przy zacięciu — przeładowanie rączką) | R | R3 |
| Cios (maczeta / kilof) | V lub PPM | X |
| Użycie przedmiotu / zmiana przedmiotu | lewy Alt (macOS: lewy Cmd) / X | RB / D-pad ↑ |
| Tryb ognia | B | D-pad ↓ |
| Rodzaj amunicji (następny magazynek; od 1.7.317) | Z | — (do przypisania) |
| Latarka | L | D-pad ← |
| Flara (rzut łukiem w stronę celowania) | F | D-pad → |
| Oględziny broni przy łupie / gablocie (nie blokują klawisza flary) | H | — (do przypisania) |
| **Krzyk** (także mikrofon, jeśli włączony w lobby) | G | LT |
| Zeskok z kładki | dół + SPACJA | lewy drążek ↓ + A |
| Pokaż / ukryj sterowanie | F1 | – |
| Czat drużyny | T | – |
| Zaproszenie przez Steam (host) | F2 | – |
| Nowa misja (host, po ekstrakcji) / gotowość w kryjówce | Enter | Back |
| Menu pauzy / ustawienia | Esc lub P | Start |
| Pełny ekran | F11 | – |

Podpowiedzi w grze i ściąga sterowania pokazują klawisze albo przyciski pada — zależnie od tego, czego gracz użył ostatnio. W menu pauzy: D-pad / drążek i A nawigują, B zamyka, LB / RB przełączają zakładki. Wszystkie akcje i ich wiązania są w `scripts/actions.gd`.

Tabela powyżej opisuje profil **Classic**. Opcjonalny **Modern** zmienia latarkę na C (L pozostaje drugim klawiszem),
przedmiot na M4 (lewy Alt/Cmd pozostaje), dodaje M5 i Share/Create do oględzin H oraz zamienia na padzie przeładowanie
na X i cios na R3. Bieżące własne przypisania pozostają przy starcie gry. HUD, sloty broni i ściągi korzystają z aktualnej
mapy; brak przypisania na padzie pokazują jako —. Oznaczenia Xbox / PlayStation / Nintendo wynikają z nazwy zgłaszanej
przez sterownik (Steam Input może zgłaszać wirtualny Xbox). Na strzelnicy osobne **Range brace key: HOLD / TOGGLE**
steruje podparciem broni; zmiana stanowiska lub otwarcie nakładki wyłącza przełączone podparcie.

Regresje: `godot --headless --path prototype -s tools/test_input_bindings.gd` oraz
`xvfb-run godot --path prototype --rendering-driver opengl3 -s tools/test_controls_render.gd`.
Szczegóły zakresu i ograniczeń: [`CONTROLS.md`](CONTROLS.md).

## Testy broni

```bash
# wszystko naraz (jednostkowe ~2,5 min + sieć host/klient ~20 s; kod wyjścia 0 = OK)
tools/test_weapons.sh

# osobno — jednostkowe: prawdziwy gracz, pociski i poziom, manekiny zamiast wrogów
godot --headless --path . -- --host --weapontest --autoquit=220

# osobno — sieć: host + klient (predykcja, walidacja serwera, limiter tempa)
godot --headless --path . -- --host --weaptestnet --autoquit=60 &
sleep 3
godot --headless --path . -- --join=127.0.0.1 --weaptestclient --autoquit=40

# wizualna kontrola: zrzuty efektów (rozbłysk, promień, płomień, szyna, wybuch…) — wymaga renderowania
xvfb-run -a godot --rendering-driver opengl3 --path . -- --host --weaponshots=/tmp/shots
```

## Testy headless

```bash
# sam host
godot --headless --path . -- --host --autoquit=3

# sieć: host + klient
godot --headless --path . -- --host --autoquit=12 &
sleep 3
godot --headless --path . -- --join=127.0.0.1 --autoquit=6

# test pętli cichości: budzi stalkera, używa Q, potem cisza → zasypia
# (zwykli wrogowie są w tym teście usuwani; PASS = zasnął, 0 HP straty, ~20,5 s)
godot --headless --path . -- --host --stealthtest=25 --autoquit=27

# test Stalkera: ostrzał, prędkość na gruncie / w wodzie / w błocie, zachowanie po ciosie
# (mapa 1.3 bez zwykłych wrogów; linie [STALKER-TEST], kod wyjścia 0 = OK, ~45 s)
godot --headless --path . -- --host --stalkertest --autoquit=70

# test wrogów i hałasu (ENEMY_PLAN.md F0): walidacja zgłoszeń hałasu, rozbieg Wołka, ściany przy ciosie, XP przywołanych
# (linie [ENEMY-TEST], kod wyjścia 0 = OK, ~10 s)
godot --headless --path . -- --host --enemytest --autoquit=150

# strzelnica FPP (RANGE_FPS_PLAN.md): drzwi w kryjówce i parkowanie postaci, blachy przez kontroler broni, podrzut, amunicja ćwiczebna,
# oparcie przy ławie, wynik na tablicy drużyny przez serwer (odrzuca niewiarygodne), przyrządy z modelu w osi kamery, ćwiczenie z przeładowaniem,
# rekordy osobiste, porównanie grup na papierze, szafa z bronią, wyjście (linie [RANGE-TEST], kod wyjścia 0 = OK, ~30 s)
godot --headless --path . -- --host --rangetest --autoquit=60

# test wipe: wszyscy padają → restart misji po 3 s (działa też z klientem)
godot --headless --path . -- --host --wipetest --autoquit=8

# test pętli misji: gniazda → Żyła → ekstrakcja → sukces → nowa misja
godot --headless --path . -- --host --missiontest --autoquit=9
```

Flagi: `--mission=ID` (mapa startowa), `--maptest`, `--gentest`, `--ridetest`, `--ridehost`, `--rideclient`, `--host`, `--steam-host`, `--steam-join=ID`, `--difficulty=easy|normal|hard`, `--nightshift` (tryb Nocny Dyżur), `--shifttest`, `--stalkertest`, `--enemytest`, `--rangetest`, `--range3d` (strzelnica FPP: gracz od razu w tunelu, jakby wszedł drzwiami kryjówki; `--rangeslot=N` broń ze slotu, `--rangereload=S[,empty]` przeładowanie po S s, `--rangeads` przyrządy bez PPM, `--rangeads=T` stały postęp przyrządów 0..1, `--rangelook=YAW,PITCH` kierunek patrzenia w °, `--rangefire=S` spust przez S s od 1 s, `--rangeleave=S` wyjście do kryjówki po S s, `--rangeweapon=KLUCZ` broń w slocie 1 z pełnym magazynkiem, `--rangeex=reload` ćwiczenie z przeładowaniem na starcie, `--rangelocker` otwarta szafa z bronią, `--rangeparts` szafa w gniazdach M-83 (próba części), `--shotrangeboard` przykładowa tablica rekordów bez zapisu i przykładowe serie na papierze — do zrzutów i nagrań przejścia), `--elite=RODZAJ` (dev: elita obok pierwszego Trzoska mapy, np. `--elite=kaplan`), `--sessionlog=KATALOG`, `--noclips` (postacie bez klipów animacji, same pozy z kodu), `--charset=tripo` (stare stylizowane modele postaci z Tripo zamiast realistycznych), `--shotrun` (gracz 1 biegnie w prawo podczas `--shot`), `--nohud` (dev: bez HUD-u, celownika i plakietek graczy — czyste ujęcia do zrzutów i nagrań traileru), `--join=IP`, `--port=N` (domyślnie 8910; np. testy przy otwartym oknie gry), `--autoquit=N`, `--shot=PLIK.png [--shotat=KOLUMNA]` (zapis obrazu z gry), `--stealthtest[=N]`, `--wipetest[=OPÓŹNIENIE]`, `--missiontest`, `--weapontest`, `--weaptestnet`, `--weaptestclient`.

**Renderer:** Forward+ (`project.godot`); bez Vulkana / D3D12 silnik wraca do OpenGL, a `--rendering-driver opengl3` wymusza tryb zgodności (zrzuty pod xvfb). W trybie zgodności widok 3D działa bez SSAO, SSIL i mgły wolumetrycznej.

**Widok 3D (`view3d.gd`):** jedyny obraz gry (widok 2D i przełącznik „View” usunięte w 1.7.194); w trybie headless jest wyłączony. Ta sama symulacja 2D renderowana w 3D: geometria z mapy ASCII (`level3d.gd`), perspektywa, księżyc (od 1.7.389 bez cienia) i światła z cieniami, mgła głębi, mgła przy ziemi (`Level3D.build_ground_fog`), cienie świateł omni, las w głębi; wrogowie i bossowie jako modele 3D (`enemy3d.gd`, `art/enemy3d/`; rigi: Wołek, Ślepiec, Podsłuchacz, Stalker, Skoczek, Trzosek, Mimik; deformacja wierzchołków w shaderze: Ćma, gniazdo, Żyła, Pijawka); billboardy z arkuszy HD tylko przy braku modelu, gracze jako modele `char3d.gd`; warstwy: tło 3D → rekwizyty i efekty 2D → gracze 3D → HUD. Celowanie, fizyka i sieć bez zmian (kamera 3D odwzorowuje Camera2D: płaszczyzna gry pokrywa się z kadrem 2D, a punkt zbiegu leży 2,2 m nad środkiem kadru — `EYE_UP_M`). Skala renderu wg „Effects quality” (LOW 50 %, MEDIUM 75 % rozdzielczości okna dla świata i graczy, skalowanie dwuliniowe), a od 1.7.389 niezależnie od niej ustawienie „Render scale” (menu pauzy, DISPLAY: 100 / 85 / 75 / 67 / 50 %, `Settings.RENDER_SCALE_LIST`) — świat 3D renderowany wewnątrz w tej skali i skalowany przez AMD FSR 1 (`View3D._apply_render_scale`); mnoży się ze skalą z jakości, a warstwa graczy zostaje w pełnej rozdzielczości. SSIL (odbite światło) od 1.7.389 tylko we wnętrzach (kryjówka; HIGH). Dev: `--view3dtoggle` (po 3 s wyłącza widok — test przywracania 2D). Materiały świata: zestaw PBR hybrydowy (`art/world3d/`: skany CC0 + proceduralne, `tools/world_pbr_import.py` / `world_pbr_gen.py`), warstwa brudu i dekale zniszczeń (`tools/world_decals_gen.py`, `Level3D.build_decals`); źródła: `art/world3d/CREDITS.md`. Dev: `--noworldpbr`, `--nograime`, `--nodecals`, `--noforestfloor`, `--view3dsavebg=PLIK`, `--view3dlit` (pełne światło: podgląd geometrii i materiałów). Noc jest czarna jak w 2D (widoczność dają aura gracza, latarka, flary, ogniska); mgła głębi zaczyna się za płaszczyzną gry. Tło i runo: bór sosnowy ze świerkami, brzozami i martwymi pniami, trawa i paprocie z `tools/world_forest_gen.py` (`art/world3d/forest/`, `Level3D.build_forest` / `build_undergrowth`); las, dno lasu za bryłą gruntu (`build_forest_floor`) i wstęgi mgły przy ziemi stoją na wspólnym profilu terenu (`Level3D.forest_terrain`: pomija dachy, kładki i nawisy, wycina szyby, wygładza tym mocniej, im dalej w głąb). Niebo nocy z księżycem, gwiazdami i chmurami wg pogody (`Level3D.SKY_SHADER`, `MOON_DIR`), zamglenie koron między pasami lasu (`build_canopy_haze`: od kilku metrów nad dnem lasu w górę, tło za postaciami zostaje czarne) i poświata księżyca tylko na lesie (`MoonRim`, warstwa `LAYER_FOREST`). Punkty orientacyjne na horyzoncie z `BACKDROP` w danych mapy (`backdrop3d.gd`: maszt radiowy z czerwonymi lampami, linia energetyczna, wieża obserwacyjna z tlącym się oknem). Las ma polany, kępy i płaty różnego wieku (`Level3D.forest_stand`, `forest_age`), a korony i runo kołyszą się na wietrze zależnym od pogody (`WIND_SHADER`, `Level3D.set_wind`). W bliskim i środkowym pasie stoją modele 3D: sosny i brzozy (`prep_items3d.py: build_pine / build_birch`, kora i kępy igliwia z `world_forest_gen.py`), świerki i martwe pnie; daleki pas to karty sosen, świerków i brzóz. Każde drzewo ma lekko inny odcień, a las jest dzielony na odcinki po 96 m (`FOREST_CHUNK`), więc silnik rysuje tylko te w kadrze. Martwe drzewa to pień z Tripo i trzy odmiany proceduralne (`prep_items3d.py: build_snag`: martwa sosna ze złamanym wierzchołkiem, szkielet świerka z piętrami suchych gałęzi, złamana brzoza z hubami; drewno `dead_wood` z `world_forest_gen.py`). Wnętrza bryły gruntu zamyka od frontu przekrój ziemi (`Level3D._build_caps`), a jego krawędź łamią przewieszona trawa, korzenie i niskie kępy (`build_front_edge`). **Słupy i kładki (od 1.7.297):** słup z kafli `w` (`Level3D.post_runs`) przechodzi przez kładkę i przez znacznik wroga u swojej podstawy (ta sama reguła co tło 2D w `level._marker_back_char`), więc nie ma dziur pod pomostami ani słupów wiszących nad ziemią. Słup przy kładce stoi tuż za tylną krawędzią jej pokładu (`deck_half` + promień modelu), a kładka dochodząca z boku leży na belce pod pokładem; pozostałe słupy (stemple tunelu, pnie) zostają w głębi na `POST_Z`. Ciąg `w` z gołym niebem nad sobą, o który nie opiera się żadna kładka, to pień drzewa (w 2D tak wyglądał): od 1.7.298 stoi tam martwe drzewo z modeli lasu (`Level3D.TRUNK_MODELS`), a nie słup. **Dachy i budynki (od 1.7.299):** dach z blachy to cienki arkusz z okapem na płatwiach i wiązarach (`Level3D._build_roofs`; stalowe w budynkach ze ścianami `C`, drewniana wiata na słupach co ≤ 5 kafli w szopie), a ściana `C` kończąca się nad otwartym parterem stoi na betonowym filarze w głębi (`wall_feet`). Kolizja bez zmian. Maszt z kolumn `w` od góry mapy i nogi strażnicy pod skrzyniami `M` rysuje `Backdrop3D.build_frames` (od 1.7.300: kratownica z lampami przeszkodowymi, drewniane nogi z przodu i z tyłu ze stężeniami). Pomost bez słupa, ściany i bryły obok stoi od 1.7.301 na nogach z rusztowania (`Level3D.deck_supports`: do gruntu albo pomostu niżej, wspornik i zastrzał pod pokładem; bez oparcia pod spodem — pręty do stropu). Dach i podłoga strażnicy (skrzynie `M` nad nogami wieży, `Level3D.tower_slabs`) to od 1.7.302 blacha i deski na drewnianych wiązarach, a nie pudła kafla; pozostałe skrzynie `M` to skrzynie z modelu `crate` (`crate_blocks`), głębokie jak szerokie. Słup kładki na zewnątrz (otwarte powietrze nad jego górą) ma od 1.7.303 połowę przekroju (`POST_THIN`) — żerdź rusztowania, pal mostu; stemple we wnętrzach mają przekrój pośredni (`POST_PROP`, ok. 0,56 m). Długie hale pod betonowym stropem (kryjówka) mają od 1.7.304 żebra co 8 kafli: pilaster, belka pod stropem i skosy (`interior_ribs`). Pilnuje tego `tools/test_structures.gd`. **Ciecze (od 1.7.294):** woda, błoto i olej (`Level3D.build_liquids`) nie mają własnej poświaty — nocą widać je tylko w świetle sceny (aura, latarka, flara, ogień); woda jest mętna i torfowa (brązowo-oliwkowa, bez kaustyk), błoto ciemne i mokre. Postacie i wrogowie brodzą: fizyka zostaje na krawędzi kafla, a model schodzi pod taflę (`Level3D.WADE`: błoto do kostek, woda do kolan; przy brzegu stopy idą po dnie niecki, `wade_at`). Graczy (osobna kamera nad światem) zakrywa zasłona `build_wade_veils` na ich warstwie, a smuga strzału brodzącego wychodzi z widocznej lufy i na pierwszych 3 m wraca na tor symulacji. Kule w błocie i oleju nie krzeszą iskier (grudy / ciemne krople, chlupnięcie), w wodzie dają plusk. Skrzynie i beczki są bryłami 3D (`view3d.gd: _sync_props`), a przedmioty HD (meble, skrytki, pickupy, generator, drezyna, skrzynie, beczki) i dekoracje mapy (kamienie, kłody, płoty, kości) modelami 3D z `art/items3d/` — buduje je `python prototype/tools/prep_items3d.py [--only=nazwa,...]` (Blender: wypiek brył proceduralnych do PBR i przygotowanie modeli z Tripo); przedmiot bez modelu zostaje kartą z mapą normalnych (`_sync_items`). Dev: `--noitems3d`. Modele można też generować lokalnie i za darmo przez ComfyUI: `python prototype/tools/comfy_gen.py both "opis" --out art_src/gibs/nazwa` (SDXL → TRELLIS 2; wymaga uruchomionego Comfy Desktop z modelami `sd_xl_base_1.0`, `trellis_2`, `pixal3d`).

**Spike 3D (Bramka B):** `godot --path prototype res://scenes/spike_mission3d.tscn` — misja 1.1 jako scena 3D (geometria z mapy ASCII, perspektywa, światła i cienie 3D, postać z `char3d.gd`), bez wrogów, celu i sieci; opis, sterowanie, wyniki i szacunek portu w `MISSION_3D_SPIKE.md`.

## Zrzuty ekranu bez GPU (xvfb)

Silnik z renderem programowym (Mesa llvmpipe) pozwala sprawdzić wygląd w CI / na serwerze bez ekranu — w ten sposób znaleziono
białe prostokąty zamiast broni (tekstura wczytana po raz pierwszy w `_draw()`). Wymaga `xvfb` i `godot`:

```bash
godot --headless --path . --import                       # raz po zmianie grafik
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
    --script tools/shot_menu.gd -- --tab=2 --out=/tmp/weapons.png     # menu pauzy: 0 ustawienia, 1 bestiariusz, 2 bronie, 3 sterowanie
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
    --script tools/shot_game.gd -- --wait=200 --out=/tmp/game.png      # gra: host + HUD; `--menu` dodatkowo otwiera menu pauzy
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
    --script tools/shot_enemies.gd -- --dir=/tmp/shots                 # po jednym zrzucie przy każdym rodzaju wroga / gnieździe / bossie (--elite=KIND, --reveal: ujawniony Żerca)
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3     --script tools/shot_taken.gd -- --dir=/tmp/shots                   # porwany bot: smuga krwi i strzałka na krawędzi ekranu
```

## Grafika — generowanie i podmiana

```bash
python3 tools/bake_sprites.py      # (postacie wymagają numpy + Pillow: pip install -r tools/requirements.txt) art/sprites/*.png (broń: tools/gun_art.py), art/tiles.png, art/props.png, art/sprites.json
godot --headless --path . --import
```

**Potwory w wyższej jakości (1.7.16)** — `tools/char_monsters_hd.py`: Trzosek 24×22, Wołek 44×44, Skoczek 26×26, Ślepiec 26×32, Podsłuchacz 26×40, Cma 26×20, Stalker 32×60, gniazdo 40×34 (ok. 1,5× większe klatki, więcej brył i detali, ten sam silnik co boss). Hitboxy zostały bez zmian — sprite jest większy od hitboxu (od 1.7.217 strefy trafień wrogów mają wysokość modeli 3D — `scripts/hurtbox.gd` — a ciało gracza 22 px). **Arkusze mają 2× gęstość pikseli** (np. Wołek 88×88 rysowany w skali 0,5 = 44×44 w świecie; manifest `scale`, filtr liniowy, `filter_clip`). **Gracz, bot i Mimik też mają 2× gęstość** (`tools/char_player.py`: klatka 32×48 rysowana w skali 0,5 = 16×24 w świecie; hitbox i oś broni (9, 12) bez zmian) — Mimik rysuje się z tego samego rigu, więc dalej pasuje do sylwetki gracza. Bake wymaga numpy/Pillow (`tools/requirements.txt`); bez nich `bake_sprites.py` wraca do starej grafiki 1×.

**Boss The Vein** (`art/sprites/vein.png` + `vein_glow.png`, klatka 256×160 = 2× gęstość pikseli, rysowana w skali 0,5 → 128×80 w świecie, 5 animacji: dormant / idle / open / windup / spit) powstaje w `tools/char_boss.py` tym samym silnikiem co potwory (render 4×, rampy, obrys). `boss.gd` wybiera animację wg stanu, nakładka dorysowuje żar żył i paszczy; bez arkusza wraca do rysunku z kółek. Po `bake_sprites.py` uruchom import (`--import`), żeby Godot wygenerował pliki `.import` nowych PNG.

**Postacie 3D (dev, bramka P0, `CHARACTERS_PLAN.md`)** — `tools/concept/char_mpfb_outfit.py --bake` (Blender 5.2 + wtyczka MPFB/MakeHuman) renderuje animacje stylizowanej postaci Scavenger '87 (M/F), a `tools/pack_chars3d.py` składa je w arkusze `art/sprites/playerhd_{male,female}.png` (klatka 64×96 przy skali 0,25, te same animacje co `player_N`, dłoń wypada w punkcie obrotu broni) i dopisuje do `sprites.json` (pełny `bake_sprites.py` je zachowuje). Drugi zestaw (`playerhd3_*`) powstaje z modeli Tripo: `tools/tripo_gen.py` (API v3, klucz w `~/.config/dead-air/tripo.env`) generuje i rigguje postać z tekstu, `tools/concept/char_tripo_bake.py` renderuje te same animacje z dłonią w punkcie obrotu broni, a `tools/pack_chars3d.py --prefix=playerhd3_ --genders=male` składa arkusz. **Etap 2 — świat HD (dev, `--newworld`):** `tools/world_hd_tiles.py` (numpy + Pillow + scipy) maluje okresowy teren HD (glina z kamykami i korzeniami, darń z trawą, przewis trawy 4 piksele świata) jako `art/world/terrain_hd.png` + `_n.png`; `Level.enable_world_hd()` rysuje go nad kaflami `#` (kafle zostają dla kolizji, okluderów i logiki), a kępy trawy z `props.png` zastępuje trawą terenu. Rekwizyty HD z Tripo (`tools/concept/prop_tripo_bake.py` + `pack_gun_hd.py --out=world/prop_NAZWA`): płot, kłody, kamień podmieniają dekoracje 6, 7, 3. Rozdzielczość bazowa projektu (640×360, `canvas_items`) **nie wymaga zmiany** — sprite'y HD są rysowane w natywnej rozdzielczości okna; pikselowy jest tylko świat starego stylu (kafle `w`, `C`, `m`, tła, nowe rekwizyty, UI).

**Postacie 3D:** widok 3D zawsze używa modeli; w widoku 2D decyduje ustawienie **Characters in 2D view: SPRITES / 3D** (menu pauzy → Settings → System, domyślnie 3D, zmiana po restarcie; wymaga grafiki HD) albo flaga `--char3d` — gracze i bot jako modele 3D renderowane w czasie rzeczywistym, ręce z IK trzymają broń 3D (12 broni, 6 wyglądów). Postój, bieg, kucanie, upadek, wstawanie i reanimacja grają z klipów animacji (`char_clips.gd`, biblioteka CC0 w `art_src/animations/ual1/`); skok, trafienie, rzut, cios i przeładowanie to pozy z kodu. Wrogowie dwunożni (`enemy3d.gd`): Ślepiec, Podsłuchacz i Stalker chodzą klipem zombie, Mimik klipem ludzkim, a Ślepiec i Stalker mają też zapowiedź i cios z klipu (`art_src/animations/ual2/`); Wołek i pozostałe stany wrogów to pozy z kodu. Modele postaci (od 1.7.220) są realistyczne: ciało i stroje z MPFB2 / MakeHuman (CC0 i CC-BY, autorzy w `art/char3d/mpfb/CREDITS.md`) składa `tools/char_mpfb.py`, a ekwipunek (plecak, śpiwór, aparat oddechowy, plecak medyczny, ładownice, manierka) to modele z lokalnej generacji FLUX.1 [schnell] + TRELLIS 2 w `art_src/gear/` (pochodzenie w `SOURCE.md`). Opis, pomiary i ograniczenia w `CHAR3D_SPIKE.md`.

**Grafika HD:** zasoby HD (postacie, bronie, wrogowie, świat, UI) są używane zawsze — ustawienie „Graphics: HD / CLASSIC”, opcja „Characters in 2D view” i flaga `--classic` zostały usunięte w 1.7.194. Flagi dev `--newchar/--newgun/--newmon/--newworld/--newui` nadal działają osobno. Tryb headless (testy) nie ładuje tekstur HD (`Settings.hd_active()`), więc `--weapontest`/`--maptest` liczą wariant bez grafiki.

**Wygląd gracza: płeć i strój (`--newchar=tripo-hd-look`):** `look.gd` — kod wyglądu = płeć × 8 + strój (męski/żeński × Scavenger '87 / Hazmat tech / Field medic), arkusze `playerhd3h_<płeć>[_<strój>]`. Cztery nowe postacie z Tripo (`art_src/characters/tripo/{male,female}_{hazmat,medic}_01_rig.glb`) wypieka `char_tripo_bake.py` (z normalizacją skali modelu: `normalize_scale`) i `pack_chars3d.py --hd --genders=…`. `Profile.look` (zapis w `profile.cfg`, `set_look` sprawdza odblokowanie: Hazmat od poziomu 3, Medic od 5), `player.look` replikowane (kosmetyka — serwer niczego z niego nie liczy), `Player._refresh_look_sprites` wymienia sprite'y przy zmianie. Wybór przy szafkach osobistych (od 1.7.349; wcześniej w warsztacie), zakładka **LOOK** (siatka 2×3 z animowanymi podglądami, szczegóły, Equip). Dev: `--look=KOD` (bez odblokowania, bez zapisu), `--shotlook`. Boty zostają kobietą Scavenger '87.

**Bronie HD (`--newgun`):** wszystkie 12 broni (plus M-83 z etapu 1) ma model z Tripo (`art_src/weapons/tripo/<klucz>_01.glb`, po 30 kredytów) wypieczony do `art/sprites/gunhd_<klucz>.png` + `_n.png` (+ `_glow.png` dla LR-7, SPECTER-1, HKM-9). `tools/concept/weapons_hd_bake.py OUT [--preview] [--cams=klucz:CAM]` liczy długość i punkt chwytu każdej broni ze starego sprite'a `guns.png` (HD pasuje do dotychczasowego celowania i wylotu lufy; kilof ma zmniejszoną szerokość, bo jego głowica jest wysoka), renderuje przez `gun_tripo_bake.py` i pakuje `pack_gun_hd.py [--glow=cyan|red]`. `WeaponView` podmienia sprite i warstwę świecenia, miniatury (`gun_icon.gd` `HD_KEYS`) w HUD/warsztacie/kodeksie używają modeli HD przy `--newui --newgun`. Dev: `--shotgunid=N` (broń 0–11 w ręku gracza 1 do zrzutu).

**Bronie 3D (`tools/gun_proc.py`, od 1.7.213):** modele w `art/char3d/gun_<klucz>.glb` nie pochodzą już z Tripo — buduje je skrypt Blendera z brył z fazami i wypieka materiały proceduralne do PBR (`blender -b --factory-startup -P prototype/tools/gun_proc.py -- KLUCZ WYJŚCIE.glb`; wszystkie naraz `prototype/tools/gun_proc_all.sh`, potem `godot --headless --path prototype --import`). Arkusze `gunhd_*.png` (miniatury HUD, warsztatu i kodeksu, rozmiar broni na stojaku i jako łup) wypieka z tych samych modeli `tools/concept/weapons_hd_bake.py OUT` (od 1.7.214; stare modele Tripo: `--src=tripo`).

**HUD i UI HD (`--newui`):** `UiTheme.hd_on()` (czytane leniwie z argumentów, bo HUD i menu budują się przed `Main._ready`) przełącza styl: panele i przyciski z miękkimi rogami (2–3 px) i cieniem, nagłówki czystym, pogrubionym i rozstrzelonym krojem motywu zamiast pikselowej Silkscreen (także cyfry amunicji), gładkie serca (krzywa parametryczna z obrysem i połyskiem), romby, kropki gotowości i moneta jako koła, paski `Bar` jako zaokrąglone belki z połyskiem i delikatnymi rowkami segmentów. Miniatura broni M-83 w HUD, warsztacie i kodeksie używa modelu HD (`HD_KEYS` w `gun_icon.gd`, wymaga `--newgun`); pozostałe bronie i przedmioty mają jeszcze pikselowe ikony. Pomiar: z `--newui` ~350 fps wobec ~414 (więcej wywołań rysowania: cienie i zaokrąglone ramki).

**Tła i teren HD w 2D — usunięte (1.7.205):** niebo, las, teren i rekwizyty rysowane w 2D (`art/backdrop/`, `art/world/`) oraz ich generatory (`tools/world_hd_backdrop.py`, `world_hd_materials.py`, `world_hd_tiles.py`) zniknęły z repo; obraz świata buduje scena 3D (`level3d.gd`, tekstury w `art/world3d/`, generator `tools/world_forest_gen.py`).

**Przedmioty i otoczenie HD (`--newitem`, domyślnie z grafiką HD):** `tools/build_items.sh [nazwa…]` odtwarza `art/items/` (albedo z obrysem `<nazwa>.png`, `_n.png`, `_glow.png`, `items.json`). Modele proceduralne buduje `tools/concept/items_proc_bake.py` w Blenderze (jednostka = piksel świata, materiały z węzłów, pasy: albedo, normalne, emisja, AO), warstwę końcową składa `tools/pack_items_hd.py`; warsztat i kupka złomu to modele Tripo (`art_src/world/tripo/{workshop,scrap_pile}.glb`, `prop_tripo_bake.py` z 7. argumentem = px na piksel świata). `ItemsHd` (`scripts/items_hd.gd`) wczytuje je jako `CanvasTexture`, `ItemsHd.make` stawia sprite ze stopami w (0, 0), `draw_fit` rysuje w UI. Użycie: `pickup.gd` (apteczka, amunicja, złom, skrzynie, flary, skrytka, nieśmiertelnik; broń HD na stojaku), `prop.gd` (skrzynia, beczka), `rack.gd`, `workshop.gd`, `lamp.gd`, `flare.gd`, `grenade.gd`, `placed.gd`, `mission.gd` (flara ewakuacji), `item_icon.gd` i `codex_portrait.gd` (GEAR, WEAPONS, miniatury), `level.gd` (kości i trzciny przez `_prop_hd`). Szczątki po zabitych stworach (`Vfx._gibs_hd`: mięso, kości, wnętrzności), cząsteczki i plamy krwi mają wariant HD przy `Sprites.newitem` (`--shotgibs`). Kryjówka HD: tablica z odprawą i ściana wyników z modeli `board`, `results_board` (strzelnica usunięta w 1.7.196). Dev: `--shotitems [--shotitems2 --shotnothrow]`, `--shotweapons[=N]`, `--shotgear`, `--shotextract`, `--shotfinale` (finał kopalni: pył ze stropu; z `--shotat`/`--shotrow`), `--shotinspect[=N]` (oględziny N-tej broni zbrojowni od lewej), `--shotboss --shotspit` (Żyła pluje w gracza), `--shotacid` (seria kul kwasu przed graczem), `--shotloot[=ammo|cache]` (zrzuty zaopatrzenia z każdą zawartością / skrzynki amunicji różnych broni / skrzynie z mapy jako sterty wokół gracza), `--shotzoom=N`.

**Przejście po mapie:** `--host --mission=ID --perf=SEK --perfsweep=KROK [--perfwake]` teleportuje gracza co KROK kolumn na każde piętro mapy i mierzy SEK s klatek w każdym miejscu; wypisuje [SWEEP] z średnią, p95, max, wywołaniami rysowania i liczbą wrogów w 400 px dla najgorszych miejsc (`--perfwake` budzi całą mapę). **Test obciążenia wrogami:** `--perf=N --perfmobs=K [--perfflares=F]` (okno/GPU, mapa np. `--mission=z1_m2`) po rozgrzewce dostawia K obudzonych wrogów wokół gracza i F flar, a raport `[PERF]` dopisuje czasy: `proc_max` i `phys_max` (najdłuższa klatka bez fizyki i najdłuższy krok fizyki z ostatniej sekundy — tak liczy je silnik, to nie średnie; do 2026-10-23 opisane jako `idle` / `phys`), `A*` (wywołania i czas nav.gd), `enemy_phys` i `slide` (czas skryptu wrogów i `move_and_slide`), `view3d` (czas `_process` widoku 3D — od 2026-10-23; liczniki zerowane na starcie pomiaru), pary kolizji. Pomiar 2026-10-08 (RTX 3080, HD, z1_m2): skrypt wrogów 0,3 ms przy 20, 0,9 ms przy 80, 2,5 ms przy 150, 11 ms przy 250 wrogach (rośnie kwadratowo; przy 250 p95 klatki 82 ms), A* pomijalny (0,02 ms), klasyczna grafika ~1,7 ms szybsza niż HD przy 80 wrogach.

**Przestoje w trakcie gry (1.7.390, 2026-10-26):** każdy wróg dostawał własny `Shader` z tym samym kodem, więc Godot kompilował go przy każdym nowym wrogu (8 wariantów `SceneForwardClustered`, ok. 60 ms na Trzoska, 140 ms na Wołka; finał 1.1 wypuszcza 6 wrogów w jednej klatce — ok. 0,3 s). Teraz `Enemy3D` trzyma wspólne shadery i scenę modelu na rodzaj (`_shader_cache`, `_scene_cache`; 13–18 ms na egzemplarz), a nowe modele w trakcie gry powstają po jednym na klatkę (`ENEMY_MODELS_PER_FRAME`; bez limitu przez 1,5 s po budowie mapy). Zamontowane części broni z ekwipunku wczytują się w tle jak broń (`GunModel.warm`, start misji z lufą RPK i bębnem M-83: 143 ms), pył kopalni na mapie z finałem powstaje przy budowie mapy, a `GunModel.drain` odbiera wczytywanie w tle przed wyjściem z gry. Zostały: otwarcie stanowiska konserwacji w kryjówce (ok. 1 s: arkusze postaci kompresowane w locie i model MPFB), części M-83 do podglądów tuż po wejściu do kryjówki (ok. 0,6 s), pierwsze modele rekwizytów zawału (ok. 0,13 s) i przebudowa geometrii przy restarcie po zawale (ok. 2,3 s).

**Skrypt widoku 3D i pozy wrogów (`[PERF-V3D]`, 2026-10-26):** `--perf` drukuje też czas części `View3D._tick` na klatkę (ms, wg nazwy `_sync_*`, najdroższe pierwsze). Pomiar 1.7.388 w walce (z1_m2 kol. 120, `--perfmobs=12 --perfflares=3 --perffx=…`, 4K): 21 kl./s, skrypt widoku 20 ms, z czego `enemies` 17,4 ms — szkielety pozowało 46 wrogów na klatkę (próg „blisko kamery” 90 m), w kadrze było kilkunastu, a jeden Trzosek kosztował ok. 0,5 ms (podparcie łap: do ~90 punktów skóry na łapę, do trzech razy na klatkę). Od 1.7.389 wróg poza bryłą widzenia kamery świata (sfera `ENEMY_CULL_R`, bossowie ×3) jest ukryty i `Enemy3D.skip_skeleton` pomija szkielet, materiały i sondy gruntu (biegną tylko zegary klipów, faza kroku i prędkości), a `_sole_penetration` liczy na spłaszczonych tablicach (`_sole_flat`) — ten sam wynik z dokładnością 2·10⁻⁶ m. Po zmianie (razem z przywróconymi poprawkami GPU i przestojów z 1.7.389): 38 kl./s, p95 39 ms (było 73), skrypt widoku 8,7 ms, `enemies` 5,7 ms (Trzosek ok. 0,27 ms, Wołek ok. 0,3 ms), GPU 8,9 ms (było 14).

**Rozbicie kosztu (`--perfreport`, 2026-10-23):** dopisane do `--perf` drukuje po pomiarze `[PERF-VP]` (czas GPU każdego viewportu), `[PERF-MESH]` (najcięższe siatki w kadrze kamery świata i kamery graczy wg nazwy węzła: trójkąty bez LOD, ile z nich rzuca cień), `[PERF-LIGHT]` (światła w kadrze i z cieniem), `[PERF-TEX]` (największe tekstury materiałów sceny, szacunek pamięci z wymiarów i formatu importu, RGBA = bez kompresji VRAM), `[PERF-EXP]` (jedna zmiana naraz na 60 klatek: cień księżyca, 2 kaskady, las bez cienia, MSAA, SSIL, SSAO, mgła wolumetryczna, glow, skala 0,75 z FSR — czas GPU przed i po) i `[PERF-PHYS]` (średni czas klatki przy kolejno wyłączanych grupach węzłów z `_physics_process`; miarodajne z `--headless`, w oknie klatkę wyznacza GPU). `--perfshots=KATALOG` zapisuje zrzut przy każdej zmianie i zaraz po jej cofnięciu (`<mapa>_NN.png` / `<mapa>_NN_ref.png`) — do porównania wyglądu z kosztem. Pomiar 2026-10-23 (RTX 3080, i9-11900KF, pełny ekran 3840×2160, HIGH): GPU 10,4–11,6 ms na mapach i w kryjówce, z czego 9,6 ms to viewport świata; skala 0,75 z FSR −3 ms, SSIL −1,2…−1,6 ms (na mapach nocnych bez widocznej różnicy, w kryjówce lekki ciepły odblask), cień księżyca −0,7…−1,2 ms, MSAA −0,9 ms, glow −0,5…−0,8 ms. W walce (`--perfmobs=12 --perfflares=3 --perffx=casing,blood,gibs,smoke`) CPU w trybie headless ok. 7 ms na klatkę, a przestoje 46–110 ms to synchroniczne wczytanie dźwięków przy pierwszym odtworzeniu i modeli broni przy odrodzeniu.

**Czas GPU, elity i przestoje (2026-10-17):** sterownik może wymuszać vsync mimo ustawień gry (na RTX 3080 nawet pusta scena chodzi równo 60 kl./s), więc czas klatki z `[PERF]` bywa przycięty do 16,6 ms. Dlatego `--perf` drukuje też `[PERF-GPU]` — czas GPU i CPU renderu z liczników silnika dla okna i SubViewportów widoku 3D (`viewport_set_measure_render_time`, niezależny od vsync) — oraz `[PERF-SPIKES]`: klatki > 40 ms z chwilą wystąpienia (pierwsza, ok. 0,07 s, to artefakt przełączenia vsync); z `--verbose` w logu stoi `[SPIKE-MARK]` tuż pod wczytanymi wtedy zasobami. `--perfkinds=a,b,c` wybiera rodzaje do `--perfmobs` (ukryty Żerca jest w teście ujawniony), `--perfdrag` dokłada co klatkę smugę ciągnięcia (Żerca). Pomiar z1_m2 kol. 120, 1920×1080, RTX 3080: GPU 6,85 ms bez wrogów, 6,96 ms z 12 zwykłymi, 6,99 ms z trzema elitami, 7,22 ms z 12 elitami (1,5 mln prymitywów), smugi krwi +0,1 ms; skrypt wrogów 1,8 → 3,7 ms przy 12 obudzonych, A* ok. 1 ms. Przy pierwszej śmierci wroga w sesji był przestój 0,3–0,43 s (synchroniczne wczytanie modeli szczątków) — `view3d.setup` wczytuje je teraz z góry.

**Wydajność HD (pomiar i culling):** `tools/perf_bench.sh [SEKUNDY]` (wymaga okna/GPU) uruchamia `--perf=N [--shotat=KOL]` na kilku konfiguracjach, mapach i pozycjach i drukuje czas klatki bez vsync (średnia/p50/p95/max), wywołania rysowania, prymitywy, węzły i pamięć wideo; wyniki w `concepts/perf_stage3.txt`. Teren i rekwizyty HD są podzielone na fragmenty 16×16 kafli (`Level.HdChunk`, `HD_CHUNK`), które silnik odrzuca poza kadrem, a wpisy w fragmencie są posortowane wg materiału (mniej wywołań). Tekstury HD wczytywane przez `Sprites.hd_texture` (dziś: ikony broni i przedmiotów oraz arkusze portretów w interfejsie) dostają mipmapy i są kompresowane w locie do S3TC (~4× mniej pamięci, kilka ms na arkusz; `--nocompress` wyłącza do porównań) — **tylko przy uruchomieniu z edytora Godota**. Szablony eksportu nie mają kompresora BC, więc w wyeksportowanym buildzie te tekstury zostają w RGBA8 z mipmapami (na starcie misji 47 tekstur: 32,5 MB zamiast 8,2 MB — `--perf` na z1_m1 pokazuje 1934 MB pamięci tekstur w buildzie wobec 1908 MB z edytora, RTX 3080, 2026-10-13; arkusze portretów kodeksu i warsztatu, wczytywane dopiero po otwarciu, to łącznie do ok. 350 MB zamiast ok. 90 MB — wyliczone z rozmiarów arkuszy), a pomiary pamięci z tego akapitu dotyczą uruchomienia z edytora. Pomiar na RTX 3080 (z1_m2/z1_m3): świat HD przed cullingiem ~255–320 fps, 660 wywołań rysowania, 24 tys. prymitywów; po cullingu ~415 fps, ~140 wywołań, ~4,2 tys. prymitywów (jak klasyczna gra); pamięć wideo przy wszystkich flagach HD 382 → 247 MB (m3) i 288 → 192 MB (m2) po kompresji, klasyczna gra ~80 MB. Stan na 2026-10-09 po usunięciu pustych warstw glow, leniwym wczytywaniu portretów kodeksu i kompresji grzbietów tła: z1_m2 259 MB, z1_m3 263 MB (HD, wszystkie flagi), klasyczna gra (`--classic`, z1_m2) 129 MB (wcześniej 149 MB).

**Etap 3 — kodeks i pozostałe tereny HD:** kodeks (bestiariusz) rysuje arkusze HD (`Sprites.enemy_sheet` w `codex_portrait.gd`, klatki z mipmapami `Sprites.mip_texture`, płynne dopasowanie do karty; `--codexentry=N` wybiera wpis do zrzutu). `tools/world_hd_materials.py` maluje materiały HD (beton, metal, woda, kratownica, deski, ściana tła, słup, błoto, olej) jako `art/world/mat_<nazwa>.png` + `_n.png`; `Level.MATERIALS` mapuje znak mapy → materiał, kafle tła (`b`, `w` i znaczniki dziedziczące tło) rysuje węzeł nad `_back`, bryły i platformy — nad `_solid`; kolumny HD w atlasie pikselowych kafli są w `--newworld` przezroczyste (`_hide_pixel_tiles`), kolizje i okludery bez zmian. Nie ma jeszcze materiałów dla lodu i śniegu (`i`, `s` — nieużywane na mapach).

**Etap 3 — komplet wrogów i bossów HD (`--newmon`):** poza Wołkiem, Trzoskiem i Ślepcem są też Skoczek (czworonożny; sen = ta sama poza do góry nogami pod sufitem klatki), Podsłuchacz, Stalker (albedo przyciemnione `--gain=0.5` jak cień), Mimik (to ten sam model co gracz z osobnym przebiegiem tylko świecących oczu: `char_tripo_bake.py --eyes`), Ćma, gniazdo oraz bossowie Żyła i Pijawka. Modele bez rigu (Ćma, gniazdo, Żyła, Pijawka) animuje deformacja wierzchołków: `tools/concept/static_tripo_bake.py` (machanie skrzydłami, pulsowanie, oddech, wychylenie, wynurzanie), a gęstość to 8 px na piksel świata dla wrogów i 5–6 dla bossów; skala arkusza wynika z rozmiaru starej klatki (`pack_monsters_hd.py`). `Sprites.enemy_sheet` jest używane w `enemy.gd`, `stalker.gd`, `nest.gd`, `boss.gd` i `leech.gd`. Podgląd: `--shotmon[=b|e]` (bez bota; `e` — Ślepiec obok elit), z `--shotdmg` wrogowie po 0,8 s tracą życie do 80 / 55 / 30 / 12% (paski życia i ślad obrażeń; z `--shotdelay=` także stan po wygaśnięciu); `--shotchip` — gracz 1 z pół punktem zabranym głazem Wołka (pół kreski życia).

**Pijawka HD (animacje):** wypiek `blender -b --factory-startup -P prototype/tools/concept/static_tripo_bake.py -- leech art_src/enemies/tripo/leech_01.glb OUT 0 [-Y] [ANIM,…]` (45 klatek; opcjonalna lista animacji do podglądu), pakowanie `python prototype/tools/pack_monsters_hd.py OUT leech -Y --anims=idle:8:8:1,peek:4:8:1,strike:6:18:0,grab:6:10:1,spit:6:12:0,hurt:2:14:0,dive:5:14:0,death:8:8:0`. Pozy klatek to tabela `leech_pose()` w `static_tripo_bake.py`.

**Etap 3 — wrogowie HD (dev, `--newmon`):** `tools/concept/monster_tripo_bake.py KIND GLB OUT CAM` renderuje klatki wrogów (albedo + normalne, 8 px na piksel świata): Wołek i Ślepiec (szkielet Mixamo z własnymi pozami: chód, zamach rękami nad głową, zgarbiony sen) oraz Trzosek (animacja `preset:quadruped:walk` z Tripo + pozy pochodne); `tools/pack_monsters_hd.py FRAMES KIND CAM` składa `<rodzaj>_hd.png`, `_hd_n.png` i `_hd_glow.png` (świecące oczy z nasyconych żółtych pikseli; warstwa glow powstaje tylko przy co najmniej 100 świecących pikselach, inaczej plik jest pomijany, a manifest ma `glow:false` — pusta warstwa to kilkanaście MB pamięci wideo) i dopisuje do manifestu (te same nazwy i liczby klatek animacji co stary arkusz). `Sprites.enemy_sheet(kind)` wybiera arkusz HD; podgląd w grze: `--newmon --shotmon`. Tripo: dla postaci biped retarget animacji z presetów zwracał błąd 1004 (rig v1.0, spec mixamo), dlatego pozy są własne; dla czworonogów preset chodu działa.

**Etap 3 — postacie HD:** drugi wygląd gracza to kobieta Scavenger '87 (`art_src/characters/tripo/female_scav_01_rig.glb`, arkusz `playerhd3h_female`); wspólna skala obu płci (`REF_H` = 1,8 m w `char_tripo_bake.py`), więc jest odrobinę niższa. `--newchar=tripo-hd-female` / `tripo-hd-mix` (nieparzyste `display_id` = mężczyzna, parzyste = kobieta). Modele GLB z Tripo (postacie, broń, rekwizyty) leżą w `art_src/` (≈ 560 MB) i są w Git LFS (`.gitattributes`: `*.glb`); lekkie wersje do gry w `prototype/art/char3d/` też.

**Etap 1 HD (bez pikselowania):** `char_tripo_bake.py --normals --albedo` renderuje klatki 256×384 jako kolor bez oświetlenia plus mapę normalnych, `pack_chars3d.py --hd --prefix=playerhd3h_` składa arkusze `playerhd3h_<płeć>.png` + `_n.png` (skala 0,0625, manifest `hd`/`normal`), a `Sprites` buduje z nich klatki `CanvasTexture` (diffuse + normal, mipmapy) — światła 2D (`Lights.LIGHT_HEIGHT` = 80 px) dają reliefowe oświetlenie latarką i flarą. Broń HD: `tools/concept/gun_tripo_bake.py` + `tools/pack_gun_hd.py` → `art/sprites/gunhd_<klucz>.png` (+`_n`), ramka 576×224, dłoń (104, 112), włączana flagą `--newgun` (na razie m83). Flagi dev: `--newchar=tripo-hd`, `--newgun`, `--shotlight` (flara przed graczem do zrzutu). Włącz w grze flagą `--newchar[=male|female|mix|tripo|tripo-hd]`; bez niej gra używa dotychczasowych `player_N`. Boty mają stary sprite, a przy `--newchar=tripo-hd…` są kobietą Scavenger '87 (`Sprites.bot_sheet()`).

Artysta może podmienić PNG w `art/` zachowując układ z `art/sprites.json` (rozmiar klatki, wiersz = animacja) — bez zmian w kodzie. Tło: pliki `art/backdrop/{sky,ridge_far,ridge_near,fog}.png` mają pierwszeństwo przed generowanymi.

## Struktura

```
scripts/
  input_setup.gd    # autoload: rejestruje akcje wejściowe (woła Actions.register)
  main_menu.gd      # ekran startowy: GRAJ / USTAWIENIA / WYJŚCIE (tło: maszt radiowy)
  colorblind_fx.gd  # filtr widzenia barw nad całym obrazem; captions.gd — napisy dźwięków
  actions.gd        # rejestr akcji: id → klawisze/mysz, które akcje wycina menu pauzy, ściąga sterowania i `{id}` w podpowiedziach — nazwy klawiszy nie wpisujemy ręcznie
  noise_manager.gd  # autoload: autorytatywny hałas + ładunek Przesterowania
  feel.gd           # autoload: screen shake + hitstop
  audio_director.gd # autoload: odtwarzanie, busy, muzyka warstwowa
  sound_grid.gd     # siatka propagacji dźwięku po mapie (własność poziomu, czyta ją audio_director)
  audio_manifest.gd # lista ścieżek audio
  weapon_def.gd     # typowana definicja broni (dane)
  weapons.gd        # rejestr 12 broni, walidacja, symulacja rozgrzania
  weapon_controller.gd  # węzeł „Weapons” gracza/bota: magazynek, przeładowanie, rytm, ogień, melee, sieć
  weapon_view.gd    # sprite i animacje broni, rozbłysk, promień/płomień, celownik, hitmarkery
  combat.gd         # warstwa obrażeń: krytyk, backstab, podpalenie, wybuch, ślad promienia
  projectile.gd     # pocisk z przeciąganiem promienia (przebicie, naprowadzanie, łuk, bełt)
  arsenal.gd        # autoload: wspólny zapas amunicji + zdarzenia walki przez sieć
  weapon_test.gd    # testy headless broni
  main.gd           # lobby, host/join, spawn (spawn_function), boty, wipe, testy
  mission.gd        # pętla misji: cel → ekstrakcja → wynik (serwer + sync)
  level.gd          # mapa: siatka ASCII → TileSet/TileMapLayer, znaczniki postaci
  lights.gd         # światło: tekstury, materiał unshaded, „kogo oświetla latarka"
  nest.gd           # gniazdo — cel misji (odnóże Żyły)
  boss.gd           # Żyła — matka gniazd (boss misji)
  nav.gd            # A* platformówki: węzły = kafle do stania, skok/spadek/zeskok
  player.gd         # ruch, broń, HP, down/revive, synchronizer, AI (is_bot)
  enemy.gd          # Trzosek / Wołek (symulacja na serwerze)
  stalker.gd        # AI stalkera (symulacja na serwerze)
  hud.gd            # HUD (EN, skala 0,7): hałas z progami, serca, ładunki Q, broń, latarka, cel, boss, podpowiedzi, winieta, wynik
  lobby.gd          # lobby (EN): host / join, sterowanie
  settings.gd       # autoload Settings: głośność, wstrząsy, rozmiar HUD, podpowiedzi, pełny ekran (user://settings.cfg), flaga DEMO
  pause_menu.gd     # menu pauzy (Esc/P): ustawienia + ściąga sterowania; solo zatrzymuje grę, w koopie świat idzie dalej
  codex.gd          # kodeks w menu pauzy: opisy i wskazówki wrogów/broni + statystyki z kodu
  codex_page.gd     # widok kodeksu: lista + portret + statystyki (bestiariusz i bronie)
  gun_icon.gd       # miniatura broni z gun_icons.png 64×24 (HUD), rysowana ostro
  # broń: tools/gun_icons_hd.py → guns.png (świat 72×28 w skali 0,5) + gun_icons.png (UI 64×24)
  codex_portrait.gd # portret / miniatura wpisu kodeksu (tło, poświata, podłoga, cień, ostry pixel-art)
  pixel_art.gd      # skala pixel-artu w UI: całkowita liczba pikseli ekranu na piksel rysunku (bez rozmycia)
  hints.gd          # jednorazowe podpowiedzi dla nowego gracza (ruch, hałas, wabik, podnoszenie…)
  ui_theme.gd       # wspólny motyw UI: obrys tekstu, panele, przyciski
  vfx.gd            # kurz, iskry, krew, szczątki i łuski (RigidBody2D), plamy
  prop.gd           # skrzynie i beczki (fizyka na serwerze, sync, wybuch)
  pickup.gd         # apteczka, amunicja, skrzynia z mapy, broń na ziemi
  sprites.gd        # SpriteFrames z arkusza + manifestu (warstwy ciało / glow)
  # misje i kryjówka:
  generator.gd      # generator radiostacji (misja 1.2), handcar.gd — drezyna ucieczki po generatorach
  brick_wall.gd     # zamurowane przejście (marker q) ze skrytką; board.gd, results_wall.gd, run_log.gd — tablica odprawy i ściana wyników w kryjówce
  workshop_ui.gd    # panel warsztatu (złom), parts.gd — części broni w gniazdach (zakup drużyny, montaż gracza)
  profile.gd        # autoload Profile: lokalny profil (XP, poziom, perki), perk_icon.gd — miniatury perków
  throwables.gd     # granaty, miny, ładunki; smoke_cloud.gd — dym, fire_patch.gd — ogień HKM-9
  # Pijawka (boss B1): leech.gd (symulacja i animacje), acid_spit.gd — kwas, tide_water.gd — fala przypływu
  # grafika i postacie: char3d.gd (postać 3D w czasie rzeczywistym, patrz CHAR3D_SPIKE.md), gib_art.gd — szczątki HD, horror_fx.gd — gradacja, winieta, ziarno
  maps/             # dane map (siatka ASCII): z1_hub (kryjówka), z1_m1 „Zaginiony Patrol”, z1_m2 „Przerwa w Nadawaniu”, z1_m3 „Gniazdo”, z1_b1 „Pijawka”
scenes/
  main.tscn  player.tscn  bot_companion.tscn  stalker.tscn  enemy.tscn  nest.tscn  boss.tscn
tools/
  bake_audio.py  audio_dsp.py   # generowanie ścieżek audio
  bake_hybrid.py audio_lib_fetch.py audio_ab.py   # dźwięk ze źródeł nagranych i wygenerowanych, odsłuch A/B (AUDIO.md §4)
```

## Znane ograniczenia (świadome, prototyp)

- serwer nie sprawdza pełnego wyposażenia i magazynka przy strzale (`_fire_request` waliduje nadawcę, tempo i wylot). Zamiana broni ma osobny serwerowy rejestr zestawu; `_drop_rpc` nie tworzy przedmiotów, a starą broń odkłada wyłącznie serwer po przyjętym podniesieniu
- wydajność mierzona wyłącznie na RTX 3080 (HD: ok. 260 MB pamięci wideo na misję); brak pomiaru na słabszym GPU, a grzbiety i mgła tła HD są importowane jako S3TC (PC, Steam Deck; bez S3TC trzeba je przełączyć z powrotem na bezstratne)
- hitbox wynurzonej Pijawki nie podąża za wychyleniem głowy w ataku; arkusze HD potworów mają warstwę glow tylko u Mimika i Trzoska
- pozycje zdalnych graczy ufane (OK dla kooperacji, blokuje host migration)
- relay tylko przez Steam (wymaga wtyczki GodotSteam, patrz wyżej); bez niej tylko ENet P2P/LAN

## Warsztat 1.7.367 — weryfikacja i zasady

Odblokowania są wspólne, a montaż prywatny i jawny. Zakup części montuje ją kupującemu; kolegom nie zmienia zestawu. Starszy profil jednorazowo utrwala poprzedni automatyczny montaż. Serwer sprawdza nadawcę, życie, kryjówkę i rzeczywisty zasięg odpowiedniego stanowiska; samo otwarcie panelu nie daje prawa do operacji. Powtórzenia zakupów mają limit 350 ms, a wymiana konkretnej części eksploatacyjnej jest możliwa raz podczas jednego pobytu w kryjówce.

Nieprzyjęta reszta opłaconych nabojów pozostaje w zapisanej dostawie: odbiór przy prasie, a dla 40 mm przy pirotechnice. Zmiana magazynka nie usuwa ani nie dodaje nabojów. Panel filtruje bronie, pamięta wybór, pokazuje kolejki i rzeczywiste porównanie zestawu; długie treści można przewijać.

```bash
godot --headless --path prototype --import
godot --headless --path prototype -- --host --port=8952 --workshoptest --autoquit=60
bash prototype/tools/test_weapons.sh
godot --headless --path prototype -- --host --rangetest --autoquit=75
```

Test warsztatu obejmuje autoryzację, duplikaty, amunicję podczas zmiany części i zestawu, opóźnione przeładowanie, cofanie tymczasowego zwrotu amunicji po wipe, migrację profilu, badania/tokarkę, częściowe dostawy, zapis, snapshot dołączającego oraz UI. Poza podsumowaniem PASS log nie może zawierać `SCRIPT ERROR` ani `Parse Error`. W dzienniku sesji `mission_start` ma `hub_seconds` (czas przygotowań), `equipment` (broń, kody części, masa każdego człowieka) i `workshop` (stan ekonomii/kolejek na wyjściu). Dane zostają w lokalnym dzienniku hosta; pozwalają zestawić przygotowania z obrażeniami, zabójstwami i hałasem w `mission_end`.

## Sylwetki wrogów 1.7.377

Wołek i Rzeźnik korzystają z przebudowanych siatek. `tools/enemy_mesh_repair.py`
scala punkty geometryczne przed Decimate, zachowując UV na narożnikach.
Rzeźnik ma wagi liczone wzdłuż powierzchni, a jego tasak ma sztywny wpływ
prawej dłoni. Pełny rig wejściowy jest w `art_src/enemies_f4/rzeznik_rig.glb`
(Git LFS); wypiek nie wymaga generowania nowej postaci.

```bash
python prototype/tools/prep_enemy3d.py --only=wolek,rzeznik
godot --headless --path prototype --import
python prototype/tools/tex_vram.py
godot --headless --path prototype --import
godot --headless --path prototype -s tools/test_enemy_surface.gd
godot --headless --path prototype -s tools/audit_enemy_assets.gd
godot --headless --path prototype -s tools/test_enemy_motion.gd
```

Zrealizowane: naprawa siatek i wag, zachowanie cullingu materiału, MSAA 2×
w podglądzie animacji oraz regresje skinningu. Pozostałe lokalne brzegi i
krawędzie niemanifold pochodzą z generowanych źródeł; te modele nie są
pełną ręczną retopologią. Test topologii ma jawne budżety, a ocenę detali
stroju wykonuje się również w renderze gry.

## Gabloty 1.7.379 — wymiana i weryfikacja

Cała gablota ma wspólny zasięg interakcji, niezależny od wybranego rzędu. H otwiera/zamyka, góra/dół wybiera broń, 1/2 wskazuje zastępowany slot, E pobiera. Panel ma też przyciski myszy; pad używa zarejestrowanych akcji menu. Odmowa pobrania zablokowanej broni zachowuje podgląd. Szczegóły przewijają się, a akcja pobrania pozostaje widoczna.

Egzemplarze są wspólne dla drużyny. Panel pokazuje dostępne, zablokowane i wydane miejsca, z etykietą odbiorcy; dołączający otrzymuje snapshot. Znana już broń daje tylko naboje do wspólnej puli, w granicach jej pojemności. Zamiana zwraca stary magazynek z jego typem amunicji i odkłada starą broń bez nowego przydziału. Serwer ustala ją na podstawie zatwierdzonego zestawu, a nie replikowanej deklaracji klienta. Zestaw przechodzi z carry, resetuje się po wipe i karze porwania. Ekspozycja pozostaje fabryczna; statystyki dotyczą montażu gracza, a porównanie uwzględnia aktualny nabój i zastępowany slot. Pistolet i magazynki na dolnej półce nadal są dekoracją.

```bash
godot --headless --path prototype --import
godot --headless --path prototype -- --host --port=8953 --cabinettest --autoquit=40
bash prototype/tools/test_cabinets.sh
```

Testy obejmują rzeczywiste gabloty, odległość, blokady, klawiaturę/akcje pada/przyciski, amunicję, porównanie i lifecycle. Dwa procesy ENet sprawdzają późne dołączenie, duplikaty, fałszywe porzucenie i sfałszowany replikowany zestaw. Host i klienci muszą używać tej samej wersji gry (zmienione RPC zamiany). Regresje dodano do CI; nie zastępują próby WAN/Steam i nie oznaczają pełnego systemu przeciw oszustwom.

### Immersyjna ława ARMS od 1.7.385

Duży model broni leży na macie 3D; wybrana część ma osobny podgląd na stalowej tacy. Boczny stojak przełącza noszoną broń i pełną zbrojownię. Kliknięcie powierzchni części, numeru gniazda lub przycisku pod modelem wybiera to samo gniazdo. Przeciągnięcie obraca broń; nieruchome oględziny i ograniczenie ruchu ułatwiają pracę.

Oględziny pokazują faktyczny montaż. Wybór wariantu tworzy jawny podgląd bez zmiany profilu, nabojów i portfela. Papierowa karta pokazuje cztery główne zmiany z podpisami „Korzyść” / „Kompromis”, a wszystkie parametry są dostępne osobno. Porównanie korzysta z pełnej konfiguracji i aktualnie załadowanej amunicji; zużycie, temperatura, wprawa i sytuacja podczas strzelania nadal należą do kontrolera broni.

Góra / dół wybiera broń, lewo / prawo gniazdo, 1 / 2 wariant; Enter zatwierdza, C przywraca oględziny, R wybiera miejsce zapisu / zapisuje aktualny zestaw. V przełącza pełne parametry, PageUp / PageDown przewijają kartę. Pad: D-pad, X / Y, A, R3 / L3, Back do parametrów, oś pionowa prawego drążka do przewijania oraz barki do zakładek. Etykiety korzystają z rejestru `actions.gd`. Koszt i główna akcja pozostają poza przewijaną treścią. EN i PL.

Zakup nadal rozstrzyga `Scrap`, montaż posiadanej części `Profile`. Animacja ze zrzutu konfiguracji sprzed operacji rusza po powodzeniu, nigdy nie zatwierdza ponownie ani nie dodaje kosztu. W toku żądania drugie działanie jest blokowane. Zmiana wyboru lub zamknięcie panelu nie cofa zatwierdzonego zakupu, ale usuwa jego spóźnioną prezentację. Ukryte viewporty nie renderują. Pozostałe sześć stanowisk zachowuje dotychczasowy układ i zasady.

Kod: `scripts/gunsmith_panel.gd`, `workshop_ui.gd`, `gun_stage.gd`. Test: `--host --workshoptest --autoquit=60`; pełne regresje `tools/test_weapons.sh` sprawdzają też prawdziwy zakup klienta ENet. Render wymaga uruchomienia bez `--headless`.

**Rendery przedmiotów na kartach stanowisk (od 1.7.414, `STATION_CARDS_PLAN.md` E0):** kafle i karta zaopatrzenia (ława, prasa, stół pirotechniczny) pokazują render modelu 3D przedmiotu z `art/items3d/` zamiast rysunku 2D — te same modele co w świecie gry, pod ciepłą lampą stanowiska. Mapowanie rodzaj → model: `ItemIcon.RENDERS` (amunicja specjalna ma jedno pudełko, rodzaj odróżnia pasek płytki; amunicja 40 mm nie ma modelu i zostaje przy ikonie). Wypalanie: `godot --path prototype --rendering-driver opengl3 --script tools/bake_items.gd [-- --only=frag,mine]` → `art/item_renders/<model>.png`, potem import (pliki `.import` mają mipmapy — miniatury są kilka razy mniejsze od renderu). `--workshoptest` sprawdza, że każdy rodzaj z modelem ma render.

`tools/workbench_qa.gd` uruchamia rzeczywistą kryjówkę z testowym montażem i wyłączonym zapisem Profile / Scrap. Najpierw import. Dla pełnej izolacji ustawień i dziennika uruchamiać na kopii projektu z inną nazwą aplikacji; raport 25.10 opisuje użyte katalogi. Polecenie renderu (Forward+ zgodnie z obecnym `project.godot`):

```powershell
godot_console --path prototype --rendering-method forward_plus --resolution 1280x720 --script res://tools/workbench_qa.gd -- --host --port=18964 --mission=z1_hub --qa-locale=pl --qa-part=m83_drum75 --qa-out=C:/Temp/workbench.png
```

Opcje: `--qa-weapon=0..11`, `--qa-fit=id,id`, `--qa-mount`, `--qa-large-ui`, `--qa-pad`, `--qa-details`, `--qa-perf=4`. Narzędzie zapisuje PNG i JSON z granicami panelu oraz wynikiem `layout_ok`; katalog wyjściowy musi istnieć. Test renderu nie zastępuje playtestu, a test ENet nie potwierdza transportu Steam / WAN.

### Zamykanie gry od 1.7.385

Wyjście z menu, przez okno i z testów sceny korzysta z `Audio.quit_game(exit_code)`. Audio jest zatrzymywane przed niszczeniem drzewa, symulacja zamrożona, a zegar monotoniczny i kolejne klatki silnika dają wątkowi miksu co najmniej 100 ms rzeczywistego czasu na zwolnienie playback. To działa także podczas pauzy, przy time_scale=0 i przyspieszonym headless; na czas wyjścia FPS jest ograniczany do 60. Kolejne żądanie nie nadpisuje kodu wyjścia. `Audio.shutdown()` można wywołać wielokrotnie; przed ponownym użyciem audio trzeba wywołać `Audio.set_enabled(true)`.

Pomocniczy Node2D oczu w `dread.gd` jest tworzony po sprawdzeniu headless, więc instancja bez obrazu lub bez wejścia do drzewa nie zostawia osieroconego węzła. Diagnostyka: `docs/audits/2026-10-25-shutdown-leaks.md`. Nie wyciszamy komunikatów silnika ani nie wyłączamy audio dla całego testu.

```powershell
godot_console --headless --path prototype --script res://tools/test_shutdown.gd
godot_console --headless --path prototype --script res://tools/test_shutdown.gd -- --shutdown-window
godot_console --headless --path prototype --script res://tools/test_shutdown.gd -- --shutdown-exit=7
```

Ostatnie polecenie ma zakończyć się kodem **7**; to kontrola zachowania kodu, a nie błąd asercji. `test_shutdown.gd` sprawdza faktycznie uruchomione ambienty / stemy / SFX, zwolnienie strumieni, ponowny start i własność węzłów. Obok podsumowania PASS log nie może zawierać SCRIPT ERROR, Parse Error ani komunikatów o pozostawionych zasobach. Samo `SceneTree.quit()` w zewnętrznym narzędziu z aktywnym audio pomija wspólną ścieżkę zamknięcia; takie narzędzia powinny wywoływać `root.get_node("Audio").quit_game(code)`.

`--shutdown-paused --shutdown-exit=7` sprawdza zamknięcie przy pauzie i time_scale=0. `--shutdowntrace` wypisuje stan audio i faktyczny czas sprzątania z zegara monotonicznego.

Od 1.7.388: komunikaty RenderingDevice przy wyjściu („Attempted to free invalid ID”, „RIDs of type Texture were leaked”) widać tylko z prawdziwym rendererem, nie w headless. Podgląd postaci w szafce (`Char3D`, tryb preview) zostawiał je za każdym razem — `char3d.gd` przy `NOTIFICATION_PREDELETE` odpina teraz tekstury viewportów od sprite'a i `CanvasTexture`, zanim Godot usunie SubViewporty. Kontrola w oknie (ustawienia gracza izolować, np. nieśledzonym `prototype/override.cfg` z `application/config/custom_user_dir_name`):

```powershell
godot_console --path prototype --resolution 1280x720 --script res://tools/shutdown_render_qa.gd -- --host --mission=z1_hub [--qa-modes=locker]
```
