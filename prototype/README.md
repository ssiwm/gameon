# Dead Air '87 — prototyp

Co-op horror run-and-gun (retro Contra) w Godot 4.7. Zakres:

- ruch 8-kierunkowy (WASD/strzałki) + strzelanie (J/LPM) + skok (SPACJA) + skradanie (SHIFT)
- czucie gry (GDD §23): coyote time, jump buffer, jump cut, hitstop, screen shake
- **mapa wielopoziomowa** (TileMapLayer z siatki ASCII w `scripts/level.gd`): las + posterunek, arena z kładkami, tartak; kładki jednokierunkowe — wskok od spodu, zeskok **dół + skok**
- **ciemność i latarka** (GDD §8.3): aura 6 m, latarka **L** (stożek 8 m, bateria, +1 Uwagi co 10 s, budzi oświetlonych wrogów, ściąga Stalkera), flara ekstrakcji 12 m, cienie od kafli
- 3 bronie (M-83, SPREAD-12, P-64) z modelem rozgrzania lufy — krótka seria cicha, ciągły ogień głośny
- wrogowie: Trzosek (wataha) i Wołek (tank) — śpią, budzi ich strzał w pobliżu albo bliskość gracza
- **Przesterowanie (Q)** — zasób: celowo podnosisz HAŁAS, żeby odciągnąć stalkera (GDD §8.4)
- **Poziom Uwagi**: bieganie/strzały dodają, cisza odejmuje; dwie prędkości decayu
- **Stalker „ON"**: budzi się przy 60%, poluje szybciej niż czatuje, wolniejszy od gracza (88 vs 95 px/s), atak nie podnosi hałasu, po ciosie się cofa
- **AI towarzysz (BOT)** wypełnia puste sloty — 1 bot gdy jesteś sam, znika przy 3+ graczach; podnosi leżących, kuca gdy kucasz, po Q wstrzymuje ogień 8 s (broni się z ≤70 px)
- 1–4 graczy online (ENet, port **8910**), synchronizacja przez `MultiplayerSynchronizer`
- **serwerowe pociski** — spawn i kolizje rozstrzyga serwer, klienci tylko rysują
- **friendly fire = hałas**: pocisk kolegi przelatuje (zero HP), trafiony krzyczy (+4 Uwagi, max raz na 0,6 s) i dostaje odrzut; żadna broń nie rani kolegi (ranić może tylko wybuch beczki). Bot nie strzela, gdy kolega jest na linii — podskakuje
- 3 HP, **down/revive** (GDD §4): leżysz 25 s, kolega trzyma E 4 s → wstajesz z 2 HP; wykrwawienie = powrót na start z 1 HP; **wipe** (wszyscy leżą) = restart misji po 3 s
- audio: 88 ścieżek, muzyka warstwowa wg Uwagi, szept stalkera
- **fizyka (1.5)**: bezwładność ruchu, szybsze opadanie, przysiad/rozciąganie; łuski, szczątki, krew i plamy, iskry, rozbryzgi; **skrzynie** (pchaj, stań, zepchnij z kładki = hałas-wabik) i **beczki** (wybuchają, reakcja łańcuchowa)
- **grafika (1.5)**: pixel-art ze sprite'ami (`tools/bake_sprites.py` → `art/`), kafle z wariantami, dekoracje, tło parallax
- **pętla misji** (GDD §4): zniszcz 3 gniazda (głośne — budzą okolicę) → budzi się **Żyła, matka gniazd** (boss w tartaku: paszcza otwiera się tylko na chwilę po ataku — wtedy strzelaj; ataki z zapowiedzią: macka, fala ogona po podłodze — przeskocz, plucie zarodnikami; latarka w paszczę podczas zapowiedzi ją ogłusza, Q w pobliżu ją odciąga; przy 33% HP krzyk budzi Stalkera; +1 ładunek Q) → po jej śmierci wyjście otwiera się w punkcie najdalszym od drużyny → cała stojąca drużyna 3 s przy flarze → ekran wyniku, host [Enter] = nowa misja
- **nawigacja A*** (`nav.gd`): bot chodzi za drużyną po całej mapie (skoki, zeskoki przez kładki), Stalker chodzi po powierzchniach zamiast przez ściany

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
| Broń | 1 / 2 / 3, kółko myszy |
| Latarka | L |
| Pokaż / ukryj sterowanie | F1 |
| Zeskok z kładki | dół + SPACJA |
| Nowa misja (host, po ekstrakcji) | Enter |

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

Flagi: `--host`, `--join=IP`, `--port=N` (domyślnie 8910; np. testy przy otwartym oknie gry), `--autoquit=N`, `--stealthtest[=N]`, `--wipetest[=OPÓŹNIENIE]`, `--missiontest`.

## Grafika — generowanie i podmiana

```bash
python3 tools/bake_sprites.py      # art/sprites/*.png, art/tiles.png, art/props.png, art/sprites.json
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
  weapons.gd        # tabela broni (rytm, obrażenia, hałas)
  main.gd           # lobby, host/join, spawn (spawn_function), boty, wipe, testy
  mission.gd        # pętla misji: cel → ekstrakcja → wynik (serwer + sync)
  level.gd          # mapa: siatka ASCII → TileSet/TileMapLayer, znaczniki postaci
  lights.gd         # światło: tekstury, materiał unshaded, „kogo oświetla latarka"
  nest.gd           # gniazdo — cel misji (odnóże Żyły)
  boss.gd           # Żyła — matka gniazd (boss misji)
  nav.gd            # A* platformówki: węzły = kafle do stania, skok/spadek/zeskok
  player.gd         # ruch, broń, HP, down/revive, synchronizer, AI (is_bot)
  enemy.gd          # Trzosek / Wołek (symulacja na serwerze)
  bullet.gd         # pociski serwerowe
  stalker.gd        # AI stalkera (symulacja na serwerze)
  hud.gd            # HUD (EN): hałas z progami, serca, ładunki Q, broń, latarka, cel, boss, podpowiedzi, winieta, wynik
  lobby.gd          # lobby (EN): host / join, sterowanie
  ui_theme.gd       # wspólny motyw UI: obrys tekstu, panele, przyciski
  vfx.gd            # kurz, iskry, krew, szczątki i łuski (RigidBody2D), plamy
  prop.gd           # skrzynie i beczki (fizyka na serwerze, sync, wybuch)
  sprites.gd        # SpriteFrames z arkusza + manifestu (warstwy ciało / glow)
  backdrop.gd       # tło parallax
scenes/
  main.tscn  player.tscn  bot_companion.tscn  bullet.tscn  stalker.tscn  enemy.tscn  nest.tscn  boss.tscn
tools/
  bake_audio.py  audio_dsp.py   # generowanie ścieżek audio
```

## Znane ograniczenia (świadome, prototyp)

- zwykli wrogowie (Trzosek, Wołek) bez A* — gonią prosto i doskakują
- jedna mapa; grafika kafli i postaci to placeholder rysowany w kodzie
- pozycje zdalnych graczy ufane (OK dla kooperacji, blokuje host migration)
- brak WebSocket/relay fallback (tylko ENet P2P/LAN)
