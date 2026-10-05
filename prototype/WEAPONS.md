# Bronie — analiza i overhaul (1.6)

Dokument opisuje, co było nie tak z bronią w prototypie, co zostało przebudowane i jak to
sprawdzać. Liczby w tabelach pochodzą z `--weapontest` (patrz §6) — nie z zgadywania.

## 1. Wniosek z analizy

Broń była 48-liniową tabelą trzech wpisów i trzema gałęziami `if` rozsianymi po `player.gd`.
Fundament pod filar „hałas jako zasób” był dobry, ale:

| Usterka | Skutek |
|---|---|
| Wspólny `HEAT_DECAY = 1,2/s` większy niż przyrost ciepła na strzał × tempo (M-83 `0,10 × 8,3 = 0,83`, P-64 `0,08 × 5 = 0,4`) | **Rozgrzewała się tylko strzelba.** Hałas M-83 i P-64 był stały (0,6 i 1,0), `n_max` nieosiągalne — wbrew README i GDD („ciągły ogień drogi”) |
| Rozgrzania nie było widać w UI | Filar-mechanika, o której gracz nie wiedział |
| P-64 gorsza od M-83 pod każdym względem (50 vs 66 DPS, głośniejszy zimny strzał), bez amunicji i bez roli | Sidearm bez sensu |
| Brak magazynków, przeładowania, zapasu, wymiany broni, 6 z 9 broni GDD, broni białej | `reload_*`, `foley_gear`, `maczeta_*` leżały w audio bez użycia |
| Strzelec-klient widział własny pocisk po RTT, własny dźwięk lokalnie | Smuga spóźniona względem huku o 50–150 ms |
| `whizz` (świst pocisku koło ucha) grał strzelającemu | Dźwięk przeznaczony dla postronnych |
| Pocisk = `Area2D` przesuwany `position +=` | Szybka broń (szyna, bełt) tunelowałaby przez wąskich wrogów i cienkie ściany |
| Serwer ufał żądaniu strzału bez sprawdzania tempa i wylotu | Zmodyfikowany klient mógł strzelać bez limitu |
| Każda nowa broń = zmiany w 6 miejscach (`GUN_ROWS`, `_gun_len`, `_shot_fx`, bot, HUD…) | Brak skalowalności |
| Efekty trafień tylko u serwera (krew, dźwięk) | Klienci widzieli, jak pocisk znika w wrogu bez śladu |

## 2. Architektura

```
weapon_def.gd         typowana definicja (≈55 pól: rytm, obrażenia, celność, pocisk, hałas,
                      amunicja, czucie, audio) + wielkości pochodne (dps, spadek obrażeń)
weapons.gd            rejestr 12 broni (tabele) + walidacja + symulacja rozgrzania + pellet_dirs
combat.gd             JEDYNE miejsce, w którym broń „robi krzywdę”: info → apply → report;
                      ślad promienia z przebiciem, stożek (cios/płomień), wybuch
projectile.gd         pocisk: przeciąganie promienia, przebicie, spadek, naprowadzanie, łuk, bełt
weapon_controller.gd  węzeł „Weapons” gracza/bota: zestaw, magazynek, przeładowanie, rytm,
                      rozgrzanie, rozrzut, ładowanie szyny, promień/płomień, cios, sieć
weapon_view.gd        sprite + animacje, rozbłysk i światło, promień, płomień, pętle, celownik
arsenal.gd            autoload: wspólny zapas drużyny + zdarzenia walki przez sieć
pickup.gd             apteczka / amunicja / skrzynia z mapy / broń na ziemi
weapon_test.gd        testy headless (jednostkowe i sieciowe)
```

**Nowa broń = jeden wpis w `weapons.gd` + rysunek w `tools/gun_art.py` (wiersz w `guns.png`) + klucze audio.**
Kontroler, HUD, boty i testy nie wymagają zmian.

### Obrażenia

Wszystko, co rani, buduje `info` (broń, ilość, punkt, kierunek, strzelec, typ, odrzut,
ogłuszenie, podpalenie, krytyk, backstab) i woła `Combat.apply(cel, info)`. Cel implementuje
`take_hit(info) -> {hit, dealt, killed, mat}` (wróg, boss, gniazdo, obiekt, Stalker); cele bez
niego dostają dawne `take_bullet*`. Wynik niesie materiał (`FLESH/ARMOR/WOOD/METAL`), z którego
`Arsenal` rozsyła efekt trafienia (krew, iskry, drzazgi + dźwięk) do wszystkich peerów i
hitmarker do strzelca.

### Sieć (GDD §19)

1. Strzelec **natychmiast** gra dźwięk, rozbłysk, odrzut kamery i leci jego **kosmetyczna** kula
   (predykcja — zero opóźnienia o RTT).
2. Do serwera idzie `{wylot, kierunek, broń, seed, rozrzut}` (reliable — trafienia się liczą).
3. Serwer waliduje: **tempo** (token bucket, zapas 2,5 strzału na lag), **wylot** (> 40 px od
   dłoni → korekta), nadawcę, rodzaj broni. Dopiero potem spawnuje kulę **autorytatywną**
   i wysyła pozostałym peerom kosmetyczne kopie.
4. Rozrzut śrutu wyznacza **seed** → serwer i każdy klient dostają identyczne kierunki bez
   przesyłania wektorów każdej śruciny.
5. Promień i płomień nie mają RPC na tyknięcie: serwer czyta zreplikowane `w_firing`, `aim_dir`
   i pozycję (50 ms) i sam liczy obrażenia.
6. Amunicja: magazynek należy do gracza, **zapas jest wspólny i autorytatywny na serwerze**.
   Gracz prosi o naboje przy *końcu* przeładowania, serwer zdejmuje je z zapasu i odsyła
   przyznaną liczbę — dwóch graczy z tą samą bronią nie wyda tych samych naboi, a anulowane
   przeładowanie nic nie kosztuje.

## 3. Roster (12 broni)

Wartości domyślne z `weapons.gd`; DPS = pełne trafienie, bez krytyków i spadku. TTK z `--weapontest`.

| # | Broń | Rodzaj | Rola / pytanie, które zadaje graczowi |
|---|------|--------|----------------------------------------|
| 1 | **M-83** | SMG, auto | Wszechstronna. Krótka seria cicha, ciągły ogień głośny (0,6 → 1,5 Uwagi/strzał) |
| 2 | **SPREAD-12** | rozrzut 5×7, półauto | Klasyk Contry; dobra z bliska, spadek obrażeń z dystansem |
| 3 | **P-64** | sidearm, ∞ amunicji | Cichsza od M-83, celna, **krytyk ×2** — ratunek i broń „na cicho” |
| 4 | **SRUT-8** | ciężka strzelba 8×7, pompka | Odrzut, ogłuszenie; ładowanie po 1 naboju (przerywane strzałem) |
| 5 | **LR-7** | promień ciągły, przebija 3 | Prawie bezgłośny (0,18/tyk), 70 DPS na 3 cele; promień **świeci** (światło na końcu i przy lufie), a bateria (100) kończy się w 10 s |
| 6 | **HKM-9** | miotacz ognia | 4 m, podpala (8 HP/s), **Trzoski uciekają w panice** |
| 7 | **GNIEW-4** | granatnik po łuku | AoE 3 m, 80 dmg; niszczy gniazda; wybuch = +15 Uwagi; rani drużynę |
| 8 | **SOKÓŁ-6** | mikrorakiety naprowadzane | Słabe, ale same dochodzą do celu poza osią |
| 9 | **WIDMO-1** | szyna, ładowanie 1,2 s | 150 dmg przez wszystkich; **najgłośniejsza** (14 Uwagi); puszczenie przed końcem anuluje |
| 10 | **CIĘGNO-6** | kusza, bełt do odzysku | **Cicha** (0,08); bełt zostaje w świecie jako skrzynka z 1 nabojem |
| 11 | **Maczeta** | melee | 30 dmg, cisza; **zabija śpiącego lub odwróconego plecami natychmiast** i bez hałasu |
| 12 | **Kilof** | melee | 55 dmg, ogłusza (1,2 s), odrzut, hałas 0,8 |

### Profil liczbowy (wygenerowany przez `--weapontest`)

DPS przy pełnym trafieniu (granatnik: wybuch; szyna: z ładowaniem). „Hałas/s” — Uwaga na sekundę przy
ciągłym ogniu przez 12 s z modelem rozgrzania (szyna i granatnik: na cykl strzału). Wróg stoi w miejscu,
bez spadku obrażeń z dystansu.

| Broń | RPM | DPS | Magazynek | Pełne przeładowanie | Hałas/s (seria 12 s) | TTK Trzosek (30) | TTK Wołek (140) |
|---|---|---|---|---|---|---|---|
| M-83 | 545 | 72.7 | 30 | 1.80s | 12.8 | 0.41s | 1.92s |
| SPREAD-12 | 231 | 134.6 | 24 | 2.50s | 17.4 | 0.22s | 1.04s |
| P-64 | 300 | 55.0 | 12 | 1.40s | 3.9 | 0.55s | 2.55s |
| SRUT-8 | 75 | 70.0 | 8 | 3.60s | 7.2 | 0.43s | 2.00s |
| LR-7 | 600 | 70.0 | 100 | 2.00s | 1.8 | 0.43s | 2.00s |
| HKM-9 | 600 | 30.0 | 80 | 2.60s | 3.0 | 1.00s | 4.67s |
| GNIEW-4 | 50 | 66.7 | 6 | 4.20s | 2.8 | 0.45s | 2.10s |
| SOKOL-6 | 300 | 35.0 | 40 | 2.70s | 10.5 | 0.86s | 4.00s |
| WIDMO-1 | 67 | 71.4 | 5 | 3.30s | 6.7 | 0.42s | 1.96s |
| CIEGNO-6 | 75 | 56.2 | 1 | 1.50s | 0.1 | 0.53s | 2.49s |
| MACHETE | 143 | 71.4 | — | — | 0.0 | 0.42s | 1.96s |
| PICKAXE | 67 | 61.1 | — | — | 0.9 | 0.49s | 2.29s |

Nazwy w HUD są ASCII (interfejs EN); GDD zostaje przy nazwach z diakrytykami.

## 4. Czucie strzału (feel)

| Element | Realizacja |
|---|---|
| Rozbłysk | wielokąt-gwiazda + język ognia + jądro (bez cieniowania), światło o energii z definicji, zanikające w 55–100 ms |
| Smuga pocisku | głowa + zanikający ogon wzdłuż toru; rakieta z żarem; granat z zapalnikiem; bełt z grotem |
| Szyna / promień | halo + rdzeń + biały środek, iskry w ścianie, światło na końcu promienia |
| Odrzut | sprite broni cofa się wzdłuż lufy (`recoil`), kamera dostaje **kierunkowe szarpnięcie** (`Feel.kick`) przeciwnie do lufy, strzelba/granatnik/szyna popychają postać |
| Rozrzut | bazowy + **bloom** rosnący z serią (M-83 do 4°), +0,8° w biegu, ×0,5–0,6 w kucaniu |
| Uderzenie | wg materiału: krew (krytyk = złoty błysk), iskry + rykoszet (blacha/pancerz), drzazgi (skrzynia), pył/odłamki/rozbryzg (ściana wg kafla) |
| Hitmarker | biały / złoty (krytyk) / czerwony większy (zabójstwo) / szary (pancerz) + dźwięk potwierdzenia w UI |
| Celownik | kursor systemowy ukryty; **30% mniejszy niż w 1.6** (`CROSS_SCALE` = 0,7 skaluje wszystko razem); 4 ramiona rozchodzą się z rozrzutem, **łuk ciepła lufy** (biały → czerwony), pierścień przeładowania/ładowania, czerwony X przy pustym magazynku, miganie przy niskim stanie |
| Animacje broni | dobycie (broń „wchodzi” z dołu), przeładowanie (opadanie i powrót), ładowanie szyny (drżenie), cios (zamach przez łuk z pchnięciem) |
| Przeładowanie | tryb taktyczny: z nabojem w komorze szybciej niż pusty (+0,4–0,5 s); automatycznie po „kliku” na pustym i po wzięciu pustej broni |
| HUD | (cały HUD 70% — `UI_SCALE` w `hud.gd`) nazwa, `magazynek / zapas drużyny`, status (RELOADING %, CHARGING %, NO AMMO), **pasek lufy z kosztem następnego strzału** (`SHOT 0,8 → 1,5`) |

### Grafika broni (1.6.1)

Każdy model to siatka 24×9 w `tools/gun_art.py`, składana pociągnięciami `h/v/r` (pozycje jawne, `check()` w
`bake_sprites.py` pilnuje: dłoń 2×2 na (3..4, 3..4), wylot lufy = `3 + gun_len`, wolne pierwszy i ostatni
wiersz na obrys). Materiały mają rampy 5 tonów (połysk · światło · ton · cień · głęboki cień; światła cieplejsze,
cienie chłodniejsze), obrys 1 px dokłada `sheet()` tak samo jak postaciom — dlatego broń leży w tej samej
estetyce i gęstości pikseli co gracz (16×24) i wrogowie. Znaki z drugim kolorem trafiają także do
`guns_glow.png` — warstwy unshaded rysowanej w `weapon_view.gd`, która świeci w ciemności (LR-7, WIDMO-1,
HKM-9, SOKÓŁ-6). Podgląd: `python3 tools/bake_sprites.py`, potem zrzuty `--weaponshots` (patrz §6).

## 5. Zasada projektowa: jedna waluta ryzyka

Hałas, światło i amunicja nie są trzema osobnymi statystykami:

- **Hałas** — każda broń ma `n_min → n_max` i własne `heat_gain/heat_decay` (naprawa błędu z §1);
  wybuch granatu = +15; przeładowanie +0,25; „klik” na pustym +0,12.
- **Światło** — rozbłysk, promień LR-7 i płomień HKM-9 oświetlają scenę (gracz widzi w ciemności,
  gdzie strzela — i gdzie jest widoczny dla *graczy*). Wrogowie reagują na **hałas** i trafienia;
  „światło przyciąga wzrok wrogów” działa tylko dla latarki (GDD §8.3) — rozszerzenie na broń to krok następny.
- **Amunicja** — wspólna; wrogowie upuszczają ją tylko do broni, którą ktoś **nosi** i której
  zapas jest < 80% (nic nie wypada „na zapas”); skrzynie z mapy dzielą ją na wszystkie noszone
  bronie główne; sidearm ma ∞, więc zawsze jest wyjście awaryjne.

## 6. Testy

```bash
tools/test_weapons.sh        # jednostkowe (~2,5 min) + sieć host/klient (~20 s); kod wyjścia 0 = OK

# osobno:
godot --headless --path . -- --host --weapontest --autoquit=220
godot --headless --path . -- --host --weaptestnet --autoquit=60 &
sleep 3
godot --headless --path . -- --join=127.0.0.1 --weaptestclient --autoquit=40

# wizualna kontrola (rozbłysk, promień, płomień, szyna, wybuch, cios, celownik, HUD):
xvfb-run -a godot --rendering-driver opengl3 --path . -- --host --weaponshots=/tmp/shots
```

Wynik: linie `[WTEST] PASS|FAIL …`, tabela profilu broni i kod wyjścia (0 = OK). Test jednostkowy
sprawdza m.in.: spójność tabel, osiąganie `n_max` przez każdą broń z rozstrzałem hałasu,
obrażenia i magazynek, spadek obrażeń śrutu, krytyk w głowę, brak tunelowania pocisku 9000 px/s,
przebicie promienia/szyny, ładowanie i anulowanie szyny, płomień (zasięg, podpalenie, panika),
granat (trafienie + AoE + hałas), naprowadzanie, bełt do odzysku, backstab maczetą (cisza),
przeładowanie (pełne, częściowe, brak zapasu, anulowanie, strzelba po 1 naboju, sidearm ∞),
rozgrzanie i hałas w serii, skrzynki, podnoszenie i wymianę broni.

Regresje starych testów (`--stealthtest`, `--missiontest`, `--wipetest`) nadal przechodzą.

## 7. Znane ograniczenia i dalsze kroki

- **Ulepszenia** (GDD §6.4, 3 poziomy) — struktura gotowa (`tier_notes`, pola definicji
  są modyfikowalne), ale bez Kryjówki nie ma gdzie ich kupować.
- **Granaty, flary, miny, wabik** (GDD §6.5) — poza zakresem; `Combat.explode` jest gotowy.
- **Kilof** nie otwiera zamurowanych przejść, a SRUT-8 nie wyważa drzwi — mapa nie ma takich kafli.
- **Dołączający w trakcie misji** widzi przedmioty z mapy, które inni już zabrali (stałe nazwy
  z mapy, serwer zignoruje próbę podniesienia). Jak ze znanym potomstwem Żyły (GDD §19).
- **Brzmienia nie oceniano uchem** (jak w AUDIO.md) — wymagany odsłuch i strojenie głośności
  względem reszty miksu; wartości `sfx_vol` w `weapons.gd` to punkt wyjścia.
- **Grafika broni** jest „ręcznym” pixel-artem w kodzie (`tools/gun_art.py` → `bake_sprites.py`);
  artysta może podmienić `art/sprites/guns.png` (+ `guns_glow.png`; 24×9 na broń, dłoń w (4,4)) bez zmian w kodzie.
