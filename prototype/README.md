# Dead Air '87 — prototyp

Co-op horror run-and-gun (retro Contra) w Godot 4.7. Zakres:

- ruch 8-kierunkowy (WASD/strzałki) + strzelanie (J/LPM) + przeładowanie (R) + cios (V/PPM) + skok (SPACJA) + skradanie (SHIFT)
- czucie gry (GDD §23): coyote time, jump buffer, jump cut, hitstop, screen shake
- **mapa wielopoziomowa** (TileMapLayer z siatki ASCII w `scripts/level.gd`, 192 × 44 kafli): las + posterunek, arena z kładkami, **Skład** (hala z antresolą, dach, schody z rusztowań), tartak z bossem, a pod całością **podziemia** — sale i niskie tunele połączone trzema szybami ze schodami z kładek; kładki jednokierunkowe — wskok od spodu, zeskok **dół + skok**. Broni do znalezienia są tylko **4** (las, półka w podziemnej sali, antresola hali, rusztowanie tartaku), reszta arsenału to start + skrzynki z amunicją
- **ciemność i latarka** (GDD §8.3): aura 6 m, latarka **L** (stożek 8 m, bateria, +1 Uwagi co 10 s, budzi oświetlonych wrogów, ściąga Stalkera), flara ekstrakcji 12 m, cienie od kafli
- **12 broni** (overhaul 1.6, `WEAPONS.md`): M-83, SPREAD-12, P-64, SRUT-8, LR-7 (promień), HKM-9 (miotacz), GNIEW-4 (granatnik), SOKOL-6 (naprowadzane), WIDMO-1 (szyna), CIEGNO-6 (cicha kusza), maczeta (cichy backstab), kilof. Model rozgrzania lufy per broń — krótka seria cicha, ciągły ogień głośny; **magazynki, przeładowanie, wspólny zapas drużyny**, skrzynki z mapy i drop z wrogów, podnoszenie i wymiana broni (**E**), krytyk w głowę, spadek obrażeń z dystansem, przebicie, podpalenie, wybuchy; predykcja strzału po stronie strzelca i walidacja serwera
- wrogowie: Trzosek (wataha — **atakuje po kolei**: max 2 naraz, reszta krąży; **morale**: śmierć kolegów, zwłaszcza przewodnika, rozbija watahę; **ucieka przed Stalkerem**), Wołek (tank — **szarża** z zapowiedzią rozbija skrzynie i detonuje beczki, o ścianę ogłusza; **rzuca skrzyniami**), **Mimik** (udaje kolegę z drużyny i woła o pomoc; zdradzają go brak serduszek nad głową, świecące oczy i dziwny numer; demaskuje go latarka, strzał albo podejście), **Ślepiec** (nie widzi, tylko słyszy: idzie do źródła hałasu — kroki wyczuwa z bliska, strzały z daleka; kucanie i cisza go mijają, latarka go nie budzi, dotyk już tak) i **Podsłuchacz** (stoi i nasłuchuje; zobaczy albo usłyszy — krzyczy po zapowiedzi 0,9 s: +14 Uwagi i cała okolica 420 px idzie do źródła; zabij go po cichu maczetą w plecy) — śpią, budzi ich strzał w pobliżu albo bliskość gracza. **Percepcja (1.6.8)**: goni tylko to, co widzi (zasięg wzroku + linia bez ściany; kucającego z bliższa), inaczej idzie na ostatni ślad (źródło hałasu, ostatnia pozycja), rozgląda się 3,5 s, a po ~9 s bez kontaktu wraca do domu i zasypia. **Pamięć wrogów**: wabik Q użyty ponownie w tym samym miejscu (140 px, 120 s) „już nie działa” — kosztuje ładunek, nikogo nie przekierowuje; wracający do domu wróg raz sprawdza „gorące miejsce”, gdzie drużyna ostatnio strzelała. **Skoczek** wisi pod sufitem i spada na tego, kto pod nim przejdzie (2 obrażenia), a **Ćma** (światłolubna, wisi pod sufitem) leci na latarkę (gryzie) i flary (spala się). **Dyrektor grozy** (`director.gd`) mierzy napięcie drużyny i po szczycie daje 45 s oddechu, a po ≥35 s ciszy wypuszcza z ciemności grupę wędrowców; napięcie skaluje też straszaki. **Słuch po trasie**: dźwięk liczy się długością ścieżki po grafie A*, nie linią prostą — strzał nad sufitem podziemi nie budzi sal poniżej. Chodzi po grafie A* (skoki Trzosków, zeskoki przez kładki; Wołek nie przeskoczy — czeka i rezygnuje), wataha się rozsuwa, a Trzosek po ciosie odskakuje
- **Krzyk (G albo mikrofon)**: GDD §8.2 — krzyk = Uwaga +20 i przyciągnięcie wrogów w promieniu 25 m (budzi śpiących, Podsłuchacz alarmuje, Ślepiec słyszy); cooldown 2,5 s, efekt (fala, dźwięk) widzą wszyscy. **Mikrofon (VAD)** to opt-in z lobby (przycisk MIC: OFF → LOW → MED → HIGH): wykrywa głośny, utrzymany krzyk, ignoruje szept i mowę, adaptuje się do szumu tła; dźwięk przetwarzany tylko lokalnie, nigdy nie nagrywany ani wysyłany. Bez mikrofonu to samo robi klawisz **G** (dostępność: nic nie wymaga mikrofonu)
- **Flara (F)**: światło-przynęta bez hałasu (pula drużyny 3, max 5; +1 ze skrzyni z mapy i za każdy cel). Płonie 25 s, budzi ciekawość Trzosków (idą sprawdzić, jeśli blisko po trasie) i **odciąga ćmy** — ćma, która doleci do flary, spala się
- **Przesterowanie (Q)** — zasób: celowo podnosisz HAŁAS, żeby odciągnąć stalkera (GDD §8.4)
- **Poziom Uwagi**: bieganie/strzały dodają, cisza odejmuje; dwie prędkości decayu
- **Stalker „ON"**: budzi się przy 60%, poluje szybciej niż czatuje, wolniejszy od gracza (88 vs 95 px/s), atak nie podnosi hałasu, po ciosie się cofa
- **groza** (`scripts/dread.gd`, lokalna i kosmetyczna): fałszywe odgłosy (kroki zza pleców, skrzypienie, drzwi, szkło, pomruk), migotanie świateł po uderzeniu, **oczy w mroku** (znikają, gdy podejdziesz lub poświecisz), a w podziemiach ciemniej i częściej; tempo rośnie z Uwagą
- **AI towarzysz (BOT)** (unika ciosów: odskakuje przed zapowiedzią i cofa się od wroga w zasięgu ręki, ranny idzie po apteczkę, nie stoi w jednym punkcie z innymi botami) wypełnia puste sloty — 1 bot gdy jesteś sam, znika przy 3+ graczach; podnosi leżących, kuca gdy kucasz, po Q wstrzymuje ogień 8 s (broni się z ≤70 px)
- 1–4 graczy online (ENet, port **8910**), synchronizacja przez `MultiplayerSynchronizer`
- **serwerowe pociski** — spawn i kolizje rozstrzyga serwer, klienci tylko rysują. **Kompensacja opóźnienia** (`lag_comp.gd`, do 150 ms): serwer sam mierzy RTT strzelca (ping/pong), a pocisk i szyna klienta trafiają wrogów w pozycjach sprzed RTT + opóźnienie interpolacji (historia pozycji 0,5 s w `enemy.gd`), więc to, co klient trafił na ekranie, jest trafione
- **friendly fire = hałas**: pocisk kolegi przelatuje (zero HP), trafiony krzyczy (+4 Uwagi, max raz na 0,6 s) i dostaje odrzut; żadna broń nie rani kolegi (ranić może tylko wybuch beczki). Bot nie strzela, gdy kolega jest na linii — podskakuje; **przeskakuje skrzynie i beczki** na drodze
- **apteczki** (+1 HP): wypadają z Wołków (75%) i z Żyły (2 sztuki); podnosi ranny przez dotknięcie, bot ustępuje rannemu człowiekowi. **Serca się kumulują**: apteczka przy pełnym HP dodaje złote serce ponad 3 (sufit 6), o ile w promieniu 120 px nikt nie jest ranny; nadmiar znika po śmierci, wipe'ie i nowej misji
- 3 HP, **down/revive** (GDD §4): leżysz 10 s, kolega trzyma E 4 s → wstajesz z 2 HP; wykrwawienie = powrót na start z 1 HP; **wipe** (wszyscy leżą) = restart misji po 3 s
- audio (overhaul v2, patrz `AUDIO.md`; broń 1.6: +36 assetów): 152 ścieżki, muzyka stemowa wg Uwagi (kwantyzacja do beatu), okluzja z dyfrakcją, pogłos środowiskowy, ogłuszenie po wybuchu, pozycyjny szept stalkera
- **powierzchnie (1.7.8, `surfaces.gd`)**: podłoże zmienia ruch, kroki i hałas biegu. **Bagno/płycizna** (wolniej ×0,72, ospały rozruch, niższy skok, głośny chlupot), **błoto** (×0,58, jeszcze ciężej, tłumi hałas), **plama oleju** (ślizg: prawie bez przyczepności, hamowanie i zawracanie wydłużone ~10×) — kafle `m` i `O` na mapie; lód i śnieg przygotowane pod biom zimowy. Kroki: głośniejsze (+6 dB) i różne — miękka ziemia, twardy beton, dzwoniący metal, chlupiące bagno, mlaszczące błoto; potwory też zwalniają na bagnie. Oddech cichszy (−8 dB)
- **fizyka (1.5)**: bezwładność ruchu, szybsze opadanie, przysiad/rozciąganie; łuski, szczątki, krew i plamy, iskry, rozbryzgi; **skrzynie** (pchaj, stań, zepchnij z kładki = hałas-wabik) i **beczki** (wybuchają, reakcja łańcuchowa)
- **grafika (1.5)**: pixel-art ze sprite'ami (`tools/bake_sprites.py` → `art/`), kafle z wariantami, dekoracje, tło parallax; **(1.6.1)** broń przerysowana (`tools/gun_art.py`, warstwa świecąca `guns_glow.png`), HUD i celownik o 30% mniejsze (`UI_SCALE`, `CROSS_SCALE`); **(1.6.6)** postacie przerysowane od zera (`tools/char_*.py`): rig ze stawami, render w 4× z cieniowaniem rampami i obrysem selektywnym, 8-klatkowy bieg, oddech w idle, bot z wizjerem (glow)
- **HUD (1.7.6)**: lewy górny róg — miernik hałasu ze stanem; **lewy dolny — karta drużyny** (zdrowie własne i kolegów/botów w kolorach slotów, DOWN / REVIVING, paski wykrwawiania); **środek dołu — płaski pasek broni i zasobów** (jeden rząd: nazwa + koszt hałasu, miniatura aktualnej broni na płytce z paskiem w kolorze smugi pocisku, duży magazynek + zapas drużyny, przeładowanie i ciepło lufy, sloty z miniaturami broni, wabik, flary, latarka; nie zasłania bossa)
- **pętla misji** (GDD §4): zniszcz **4 gniazda** — dwa na powierzchni (posterunek, szczyt tartaku) i dwa **w podziemiach** (trzeba zejść szybem) — są głośne i budzą okolicę → budzi się **Żyła, matka gniazd** (boss w tartaku: paszcza otwiera się tylko na chwilę po ataku — wtedy strzelaj; ataki z zapowiedzią: macka, fala ogona po podłodze — przeskocz, plucie zarodnikami; latarka w paszczę podczas zapowiedzi ją ogłusza, Q w pobliżu ją odciąga; przy 33% HP krzyk budzi Stalkera; +1 ładunek Q) → po jej śmierci wyjście otwiera się w punkcie najdalszym od drużyny → cała stojąca drużyna 3 s przy flarze → ekran wyniku, host [Enter] = nowa misja
- **nawigacja A*** (`nav.gd`): bot chodzi za drużyną po całej mapie (skoki, zeskoki przez kładki), Stalker chodzi po powierzchniach zamiast przez ściany

## Menu pauzy, ustawienia, podpowiedzi (demo)

- **Esc / P** — menu pauzy: głośność (ogólna, muzyka + ambient, efekty), wstrząsy kamery (FULL / HALF / OFF), rozmiar HUD
  (SMALL / NORMAL / LARGE), podpowiedzi, mikrofon (krzyk), pełny ekran (też F11) i ściąga sterowania. Ustawienia zapisują się
  w `user://settings.cfg`. W trybie solo gra jest zatrzymana; w kooperacji świat idzie dalej (menu to mówi) i klawisze gry są
  wyłączone na czas menu.
- **Zakładki menu:** SETTINGS · **BESTIARY** (Trzosek, Wołek, Skoczek, Ślepiec, Podsłuchacz, Mimik, Cma, Stalker „ON", gniazdo,
  boss Żyła — animowany portret z arkusza, statystyki liczone z `Enemy.KINDS`, opis i wskazówka) · **WEAPONS** (wszystkie 12 pozycji:
  miniatura, obrażenia, tempo, zasięg, magazynek/zapas, przeładowanie, hałas, opis i wskazówka — statystyki liczone z `WeaponDef`,
  więc nie rozjeżdżają się z grą) · CONTROLS. Dane i teksty: `codex.gd`, widok: `codex_page.gd`.
- **Podpowiedzi** (`hints.gd`): krótkie, jednorazowe wskazówki w chwili, gdy mechanika się przydaje (pierwszy ruch, pierwszy
  hałas, „SOMETHING IS LISTENING", leżący kolega, latarka, flara). Zapamiętane — weteran ich nie zobaczy; wyłącznik w menu.
- **Wersja demo**: `Settings.DEMO` (domyślnie `true`) dodaje na ekranie końcowym misji zachętę do listy życzeń; po wpisaniu
  `Settings.STORE_URL` pojawia się klawisz [O] otwierający stronę sklepu. Lista kontrolna playtestu i publikacji: `PLAYTEST.md`.

## Poziomy trudności

Host wybiera w lobby przyciskiem **DIFFICULTY** albo flagą `--difficulty=easy|normal|hard` (domyślnie **NORMAL** = dotychczasowa gra). Wartość trafia do klientów przy dołączeniu, widać ją w HUD (prawy górny róg). Mnożniki: `scripts/difficulty.gd` (autoload `Difficulty`).

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

## Steam (opcjonalnie): lobby, zaproszenia, relay

Gra łączy się przez ENet (IP) jak dotąd, a **Steam** jest dodatkowym transportem — bez konfiguracji routera, z zaproszeniami od znajomych i relayem Valve (graczom z różnych krajów nie trzeba otwierać portów). Kod: `scripts/steam_net.gd`. Wtyczka **GodotSteam 4.23 (GDExtension, Godot 4.4+)** leży w `addons/godotsteam/` (tylko Linux x64 + Windows x64) i zawiera już `SteamMultiplayerPeer` — **nie dodawaj** osobnego addonu steam-multiplayer-peer, bo klasy się dublują. Bez Steama przyciski w lobby są wyszarzone, a reszta gry działa normalnie.

Instalacja (raz):
1. Wtyczka jest już w repo. Aktualizacja: gałąź `gdextension-plugin` na codeberg.org/godotsteam/godotsteam (GitHub jest zarchiwizowany), skopiuj `addons/godotsteam/`.
2. Zainstaluj i uruchom klienta Steam, zaloguj się. W katalogu projektu leży `steam_appid.txt` z `480` (**Spacewar** — publiczny App ID testowy, darmowy; w bibliotece gra pokazuje się jako „Spacewar"). Testerzy muszą mieć Steama i być znajomymi hosta.
3. W lobby: **STEAM HOST** tworzy lobby (ID ląduje w schowku i w statusie), **F2** w grze otwiera okno zaproszeń Steam, znajomi klikają „Dołącz do gry" albo wklejają ID i dają **STEAM JOIN**. Flagi: `--steam-host`, `--steam-join=ID`; start z zaproszenia (`+connect_lobby ID`) też działa.
4. Pod wydanie: własny App ID (Steam Direct, 100 USD zwrotne po 1000 USD przychodu) — zmień `APP_ID` w `steam_net.gd` i `steam_appid.txt`, a plik usuń z paczki sklepowej.

API GodotSteam różni się między wersjami, więc wrapper dobiera argumenty po nazwach i obsługuje dwa warianty peera (wbudowane lobby `create_lobby`/`connect_lobby` oraz surowe `create_host`/`create_client`). Wtyczka ładuje się, a sygnatury API zgadzają się z wrapperem (sprawdzone sondą w Godot 4.7.2); w grze działa wariant surowego P2P. Nie testowano z działającym klientem Steam — pierwszy test: dwa konta Steam będące znajomymi.

### Playtesty przez Steam (App ID 480)

```bash
godot --headless --path prototype --export-release "Linux"     # -> build/linux/
godot --headless --path prototype --export-release "Windows"   # -> build/windows/
cp prototype/steam_appid.txt build/linux/ ; cp prototype/steam_appid.txt build/windows/
```

Presety są w `export_presets.cfg` (szablony eksportu 4.7.2 muszą być zainstalowane). Testerom wyślij zipem cały folder (`.pck`, biblioteki i `steam_appid.txt`). Każdy tester: Steam uruchomiony i zalogowany, wszyscy muszą być **znajomymi na Steamie** z hostem. Host: STEAM HOST, potem F2 albo wysłanie ID lobby; reszta: „Dołącz do gry” albo ID + STEAM JOIN. W Steamie tester widnieje jako grający w „Spacewar”.

## Uruchomienie

```bash
# okno 1 — host
godot --path . -- --host

# okno 2 — klient
godot --path . -- --join=127.0.0.1
```

Bez parametrów: lobby z przyciskami **HOST GAME** / **JOIN** (Enter w polu IP = dołącz). Interfejs gry jest po angielsku (1.4.0).

## Sterowanie

| Akcja | Klawisz |
|---|---|
| Ruch / celowanie 8 kier. | WASD lub strzałki |
| Skok | SPACJA |
| Strzał | J lub LPM |
| Skradanie (cisza) | SHIFT |
| **Przesterowanie** | **Q** |
| Podnieś kolegę (przytrzymaj) | E |
| Broń (2 główne + sidearm) | 1 / 2 / 3, kółko myszy |
| Przeładowanie | R |
| Cios (maczeta / kilof) | V lub PPM |
| Podnieś broń z ziemi | E |
| Latarka | L |
| Pokaż / ukryj sterowanie | F1 |
| Zaproszenie przez Steam (host) | F2 |
| Flara (rzut łukiem w stronę celowania) | F |
| **Krzyk** (także mikrofon, jeśli włączony w lobby) | G |
| Zeskok z kładki | dół + SPACJA |
| Nowa misja (host, po ekstrakcji) | Enter |
| Menu pauzy / ustawienia | Esc lub P |
| Pełny ekran | F11 |

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

# test wipe: wszyscy padają → restart misji po 3 s (działa też z klientem)
godot --headless --path . -- --host --wipetest --autoquit=8

# test pętli misji: gniazda → Żyła → ekstrakcja → sukces → nowa misja
godot --headless --path . -- --host --missiontest --autoquit=9
```

Flagi: `--host`, `--steam-host`, `--steam-join=ID`, `--difficulty=easy|normal|hard`, `--join=IP`, `--port=N` (domyślnie 8910; np. testy przy otwartym oknie gry), `--autoquit=N`, `--stealthtest[=N]`, `--wipetest[=OPÓŹNIENIE]`, `--missiontest`, `--weapontest`, `--weaptestnet`, `--weaptestclient`.

## Grafika — generowanie i podmiana

```bash
python3 tools/bake_sprites.py      # (postacie wymagają numpy + Pillow: pip install -r tools/requirements.txt) art/sprites/*.png (broń: tools/gun_art.py), art/tiles.png, art/props.png, art/sprites.json
godot --headless --path . --import
```

**Potwory w wyższej jakości (1.7.16)** — `tools/char_monsters_hd.py`: Trzosek 24×22, Wołek 44×44, Skoczek 26×26, Ślepiec 26×32, Podsłuchacz 26×40, Cma 26×20, Stalker 32×60, gniazdo 40×34 (ok. 1,5× większe klatki, więcej brył i detali, ten sam silnik co boss). Hitboxy zostały bez zmian — sprite jest większy od hitboxu. Mimik zostaje 16×24, bo musi pasować do sylwetki gracza.

**Boss The Vein** (`art/sprites/vein.png` + `vein_glow.png`, klatka 128×80, 5 animacji: dormant / idle / open / windup / spit) powstaje w `tools/char_boss.py` tym samym silnikiem co potwory (render 4×, rampy, obrys). `boss.gd` wybiera animację wg stanu, nakładka dorysowuje żar żył i paszczy; bez arkusza wraca do rysunku z kółek. Po `bake_sprites.py` uruchom import (`--import`), żeby Godot wygenerował pliki `.import` nowych PNG.

Artysta może podmienić PNG w `art/` zachowując układ z `art/sprites.json` (rozmiar klatki, wiersz = animacja) — bez zmian w kodzie. Tło: pliki `art/backdrop/{sky,ridge_far,ridge_near,fog}.png` mają pierwszeństwo przed generowanymi.

## Struktura

```
scripts/
  input_setup.gd    # akcje wejściowe w kodzie
  noise_manager.gd  # autoload: autorytatywny hałas + ładunek Przesterowania
  feel.gd           # autoload: screen shake + hitstop
  audio_director.gd # autoload: odtwarzanie, busy, muzyka warstwowa
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
  # broń: tools/gun_icons_hd.py → guns.png (świat 36×14) + gun_icons.png (UI 64×24)
  codex_portrait.gd # portret / miniatura wpisu kodeksu (tło, poświata, podłoga, cień, ostry pixel-art)
  pixel_art.gd      # skala pixel-artu w UI: całkowita liczba pikseli ekranu na piksel rysunku (bez rozmycia)
  hints.gd          # jednorazowe podpowiedzi dla nowego gracza (ruch, hałas, wabik, podnoszenie…)
  ui_theme.gd       # wspólny motyw UI: obrys tekstu, panele, przyciski
  vfx.gd            # kurz, iskry, krew, szczątki i łuski (RigidBody2D), plamy
  prop.gd           # skrzynie i beczki (fizyka na serwerze, sync, wybuch)
  pickup.gd         # apteczka, amunicja, skrzynia z mapy, broń na ziemi
  sprites.gd        # SpriteFrames z arkusza + manifestu (warstwy ciało / glow)
  backdrop.gd       # tło parallax
scenes/
  main.tscn  player.tscn  bot_companion.tscn  stalker.tscn  enemy.tscn  nest.tscn  boss.tscn
tools/
  bake_audio.py  audio_dsp.py   # generowanie ścieżek audio
```

## Znane ograniczenia (świadome, prototyp)

- zwykli wrogowie (Trzosek, Wołek) bez A* — gonią prosto i doskakują
- jedna mapa (choć duża); wrogowie podziemi budzą się od hałasu tylko w promieniu słyszenia, a goniąc „prosto” mogą utknąć pod sufitem, gdy gracz jest na powierzchni; grafika kafli i postaci to placeholder rysowany w kodzie
- pozycje zdalnych graczy ufane (OK dla kooperacji, blokuje host migration)
- relay tylko przez Steam (wymaga wtyczki GodotSteam, patrz wyżej); bez niej tylko ENet P2P/LAN
