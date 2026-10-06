# Dead Air '87 — prototyp

Co-op horror run-and-gun (retro Contra) w Godot 4.7. Zakres:

- ruch 8-kierunkowy (WASD/strzałki) + strzelanie (J/LPM) + przeładowanie (R) + cios (V/PPM) + skok (SPACJA) + skradanie (SHIFT)
- czucie gry (GDD §23): coyote time, jump buffer, jump cut, hitstop, screen shake
- **mapa wielopoziomowa** (TileMapLayer z siatki ASCII w `scripts/level.gd`, 192 × 44 kafli): las + posterunek, arena z kładkami, **Skład** (hala z antresolą, dach, schody z rusztowań), tartak z bossem, a pod całością **podziemia** — sale i niskie tunele połączone trzema szybami ze schodami z kładek; kładki jednokierunkowe — wskok od spodu, zeskok **dół + skok**. Broni do znalezienia są tylko **4** (las, półka w podziemnej sali, antresola hali, rusztowanie tartaku), reszta arsenału to start + skrzynki z amunicją
- **ciemność i latarka** (GDD §8.3): aura 6 m, latarka **L** (stożek 8 m, bateria, +1 Uwagi co 10 s, budzi oświetlonych wrogów, ściąga Stalkera), flara ekstrakcji 12 m, cienie od kafli
- **12 broni** (overhaul 1.6, `WEAPONS.md`): M-83, SPREAD-12, P-64, SRUT-8, LR-7 (promień), HKM-9 (miotacz), GNIEW-4 (granatnik), SOKOL-6 (naprowadzane), WIDMO-1 (szyna), CIEGNO-6 (cicha kusza), maczeta (cichy backstab), kilof. Model rozgrzania lufy per broń — krótka seria cicha, ciągły ogień głośny; **magazynki, przeładowanie, wspólny zapas drużyny**, skrzynki z mapy i drop z wrogów, podnoszenie i wymiana broni (**E**), krytyk w głowę, spadek obrażeń z dystansem, przebicie, podpalenie, wybuchy; predykcja strzału po stronie strzelca i walidacja serwera
- wrogowie: Trzosek (wataha), Wołek (tank), **Ślepiec** (nie widzi, tylko słyszy: idzie do źródła hałasu — kroki wyczuwa z bliska, strzały z daleka; kucanie i cisza go mijają, latarka go nie budzi, dotyk już tak) i **Podsłuchacz** (stoi i nasłuchuje; zobaczy albo usłyszy — krzyczy po zapowiedzi 0,9 s: +14 Uwagi i cała okolica 420 px idzie do źródła; zabij go po cichu maczetą w plecy) — śpią, budzi ich strzał w pobliżu albo bliskość gracza. **Percepcja (1.6.8)**: goni tylko to, co widzi (zasięg wzroku + linia bez ściany; kucającego z bliższa), inaczej idzie na ostatni ślad (źródło hałasu, ostatnia pozycja), rozgląda się 3,5 s, a po ~9 s bez kontaktu wraca do domu i zasypia. Chodzi po grafie A* (skoki Trzosków, zeskoki przez kładki; Wołek nie przeskoczy — czeka i rezygnuje), wataha się rozsuwa, a Trzosek po ciosie odskakuje
- **Przesterowanie (Q)** — zasób: celowo podnosisz HAŁAS, żeby odciągnąć stalkera (GDD §8.4)
- **Poziom Uwagi**: bieganie/strzały dodają, cisza odejmuje; dwie prędkości decayu
- **Stalker „ON"**: budzi się przy 60%, poluje szybciej niż czatuje, wolniejszy od gracza (88 vs 95 px/s), atak nie podnosi hałasu, po ciosie się cofa
- **groza** (`scripts/dread.gd`, lokalna i kosmetyczna): fałszywe odgłosy (kroki zza pleców, skrzypienie, drzwi, szkło, pomruk), migotanie świateł po uderzeniu, **oczy w mroku** (znikają, gdy podejdziesz lub poświecisz), a w podziemiach ciemniej i częściej; tempo rośnie z Uwagą
- **AI towarzysz (BOT)** (unika ciosów: odskakuje przed zapowiedzią i cofa się od wroga w zasięgu ręki, ranny idzie po apteczkę, nie stoi w jednym punkcie z innymi botami) wypełnia puste sloty — 1 bot gdy jesteś sam, znika przy 3+ graczach; podnosi leżących, kuca gdy kucasz, po Q wstrzymuje ogień 8 s (broni się z ≤70 px)
- 1–4 graczy online (ENet, port **8910**), synchronizacja przez `MultiplayerSynchronizer`
- **serwerowe pociski** — spawn i kolizje rozstrzyga serwer, klienci tylko rysują
- **friendly fire = hałas**: pocisk kolegi przelatuje (zero HP), trafiony krzyczy (+4 Uwagi, max raz na 0,6 s) i dostaje odrzut; żadna broń nie rani kolegi (ranić może tylko wybuch beczki). Bot nie strzela, gdy kolega jest na linii — podskakuje; **przeskakuje skrzynie i beczki** na drodze
- **apteczki** (+1 HP): wypadają z Wołków (75%) i z Żyły (2 sztuki); podnosi ranny przez dotknięcie, bot ustępuje rannemu człowiekowi. **Serca się kumulują**: apteczka przy pełnym HP dodaje złote serce ponad 3 (sufit 6), o ile w promieniu 120 px nikt nie jest ranny; nadmiar znika po śmierci, wipe'ie i nowej misji
- 3 HP, **down/revive** (GDD §4): leżysz 10 s, kolega trzyma E 4 s → wstajesz z 2 HP; wykrwawienie = powrót na start z 1 HP; **wipe** (wszyscy leżą) = restart misji po 3 s
- audio (overhaul v2, patrz `AUDIO.md`; broń 1.6: +36 assetów): 152 ścieżki, muzyka stemowa wg Uwagi (kwantyzacja do beatu), okluzja z dyfrakcją, pogłos środowiskowy, ogłuszenie po wybuchu, pozycyjny szept stalkera
- **fizyka (1.5)**: bezwładność ruchu, szybsze opadanie, przysiad/rozciąganie; łuski, szczątki, krew i plamy, iskry, rozbryzgi; **skrzynie** (pchaj, stań, zepchnij z kładki = hałas-wabik) i **beczki** (wybuchają, reakcja łańcuchowa)
- **grafika (1.5)**: pixel-art ze sprite'ami (`tools/bake_sprites.py` → `art/`), kafle z wariantami, dekoracje, tło parallax; **(1.6.1)** broń przerysowana (`tools/gun_art.py`, warstwa świecąca `guns_glow.png`), HUD i celownik o 30% mniejsze (`UI_SCALE`, `CROSS_SCALE`); **(1.6.6)** postacie przerysowane od zera (`tools/char_*.py`): rig ze stawami, render w 4× z cieniowaniem rampami i obrysem selektywnym, 8-klatkowy bieg, oddech w idle, bot z wizjerem (glow)
- **pętla misji** (GDD §4): zniszcz **4 gniazda** — dwa na powierzchni (posterunek, szczyt tartaku) i dwa **w podziemiach** (trzeba zejść szybem) — są głośne i budzą okolicę → budzi się **Żyła, matka gniazd** (boss w tartaku: paszcza otwiera się tylko na chwilę po ataku — wtedy strzelaj; ataki z zapowiedzią: macka, fala ogona po podłodze — przeskocz, plucie zarodnikami; latarka w paszczę podczas zapowiedzi ją ogłusza, Q w pobliżu ją odciąga; przy 33% HP krzyk budzi Stalkera; +1 ładunek Q) → po jej śmierci wyjście otwiera się w punkcie najdalszym od drużyny → cała stojąca drużyna 3 s przy flarze → ekran wyniku, host [Enter] = nowa misja
- **nawigacja A*** (`nav.gd`): bot chodzi za drużyną po całej mapie (skoki, zeskoki przez kładki), Stalker chodzi po powierzchniach zamiast przez ściany

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
| Zeskok z kładki | dół + SPACJA |
| Nowa misja (host, po ekstrakcji) | Enter |

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
