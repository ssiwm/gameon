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

**Nowa broń = jeden wpis w `weapons.gd` + rysunek w `tools/gun_icons_hd.py` (wiersz w `guns.png` i `gun_icons.png`; `gun_len` w `weapons.gd` musi równać się `gun_icons_hd.gun_len(nazwa)` — `bake_sprites.py` to sprawdza) + klucze audio.**
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
| 4 | **PELLET-8** | ciężka strzelba 8×10, pompka | 80 na strzał z bliska (zabija Mimika i Skoczka jednym), odrzut, ogłuszenie 0,5 s; ładowanie po 1 naboju (przerywane strzałem); śrucina 10 mało traci na pancerzu Wołka |
| 5 | **LR-7** | promień ciągły, przebija 2 | 60 DPS na 2 cele, zasięg 11 m i wiązka słabnie z dystansem (do 55%); **hałas rośnie z rozgrzaniem** (0,25 → 0,8 na tyk), bateria 60 kończy się w 6 s; promień **świeci** i **przyciąga ćmy** oraz Stalkera |
| 6 | **HKM-9** | miotacz ognia | 4 m, podpala (8 HP/s), **Trzoski uciekają w panice** |
| 7 | **WRATH-4** | granatnik po łuku | AoE 3 m, 80 dmg; niszczy gniazda; wybuch = +15 Uwagi; rani drużynę |
| 8 | **FALCON-6** | mikrorakiety naprowadzane (10 dmg) | Same dochodzą do celu poza osią i **wolą cele trudne do trafienia**: ćmę, skoczka, podsłuchacza |
| 9 | **SPECTER-1** | szyna, ładowanie 1,2 s | 150 dmg przez wszystkich; **najgłośniejsza** (14 Uwagi); puszczenie przed końcem anuluje |
| 10 | **SINEW-6** | kusza, bełt do odzysku | **Cicha** (0,08); bełt zostaje w świecie jako skrzynka z 1 nabojem |
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
| PELLET-8 | 75 | 100.0 | 8 | 3.60s | 7.2 | 0.30s | 1.40s |
| LR-7 | 600 | 60.0 | 60 | 2.60s | 6.4 | 0.50s | 2.33s |
| HKM-9 | 600 | 30.0 | 80 | 2.60s | 3.0 | 1.00s | 4.67s |
| WRATH-4 | 50 | 66.7 | 6 | 4.20s | 2.8 | 0.45s | 2.10s |
| FALCON-6 | 300 | 50.0 | 40 | 2.70s | 10.5 | 0.60s | 2.80s |
| SPECTER-1 | 67 | 71.4 | 5 | 3.30s | 6.7 | 0.42s | 1.96s |
| SINEW-6 | 75 | 56.2 | 1 | 1.50s | 0.1 | 0.53s | 2.49s |
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

*(Stary opis, 1.6 — dziś bronie rysuje `tools/gun_icons_hd.py`, patrz niżej; `gun_art.py` zostaje jako zapas bez numpy.)* Każdy model to siatka 24×9 w `tools/gun_art.py`, składana pociągnięciami `h/v/r` (pozycje jawne, `check()` w
`bake_sprites.py` pilnuje: dłoń 2×2 na (3..4, 3..4), wylot lufy = `3 + gun_len`, wolne pierwszy i ostatni
wiersz na obrys). Materiały mają rampy 5 tonów (połysk · światło · ton · cień · głęboki cień; światła cieplejsze,
cienie chłodniejsze), obrys 1 px dokłada `sheet()` tak samo jak postaciom — dlatego broń leży w tej samej
estetyce i gęstości pikseli co gracz (16×24) i wrogowie. Znaki z drugim kolorem trafiają także do
`guns_glow.png` — warstwy unshaded rysowanej w `weapon_view.gd`, która świeci w ciemności (LR-7, SPECTER-1,
HKM-9, FALCON-6). Podgląd: `python3 tools/bake_sprites.py`, potem zrzuty `--weaponshots` (patrz §6).

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
- **Kilof** nie otwiera zamurowanych przejść, a PELLET-8 nie wyważa drzwi — mapa nie ma takich kafli.
- **Dołączający w trakcie misji** widzi przedmioty z mapy, które inni już zabrali (stałe nazwy
  z mapy, serwer zignoruje próbę podniesienia). Jak ze znanym potomstwem Żyły (GDD §19).
- **Brzmienia nie oceniano uchem** (jak w AUDIO.md) — wymagany odsłuch i strojenie głośności
  względem reszty miksu; wartości `sfx_vol` w `weapons.gd` to punkt wyjścia.
- **Grafika broni (1.7.17)**: jeden projekt na broń w `tools/gun_icons_hd.py` (silnik postaci: render 4×, rampy, obrys, warstwa świecąca), dwa arkusze: `art/sprites/guns.png` (+ `guns_glow.png`) — broń w świecie, klatka **72×28 = 2× gęstość pikseli** (manifest: `scale` 0,5, więc na ekranie zajmuje tyle co 36×14), dłoń (pivot obrotu) w (13; 14) pikseli arkusza, wylot lufy = dłoń + `gun_len` (w pikselach świata); gra rysuje ją z filtrem liniowym i `filter_clip`, żeby obrót pod dowolnym kątem był gładki; oraz `gun_icons.png` (+ glow) — ikony 64×24 do HUD i kodeksu. Wiersz = `gun_row`. Artysta może podmienić PNG (układ z `art/sprites.json`) bez zmian w kodzie. Lufa nie wychodzi za ścianę (`weapon_controller.muzzle_pos` skraca wylot do przeszkody).

## 6. Faza 1 przeglądu broni (1.7.57)

Wnioski z analizy (hałas na jednostkę obrażeń różnił się ~100×, dwie bronie były nieosiągalne, PELLET-8 i FALCON-6 zdominowane,
krytyk i pancerz prawie martwe) i zmiany tylko w danych:

| Obszar | Zmiana |
|---|---|
| Dostępność | **WRATH-4** w warsztacie (300), **SPECTER-1** w warsztacie (400) po pokonaniu Pijawki (trofeum `Scrap.trophies`, zapis u hosta); hub ma 8 stojaków |
| LR-7 | bazowe przebicie 2 → 1 (trafia 2 cele; poziom 3 dokłada +1); ćmy lecą na wiązkę jak na latarkę — światło ma cenę |
| PELLET-8 | 7 → 10 na śrucinę (80 na strzał), ogłuszenie 0,2 → 0,5 s |
| FALCON-6 | 7 → 10 na rakietę; naprowadzanie premiuje ćmę, skoczka i podsłuchacza (`EVASIVE_KINDS`) |
| Strefy głowy | Ślepiec, Podsłuchacz i Mimik (28% sylwetki) obok Wołka — krytyk P-64 / SINEW / M-83 ma sens |
| Pancerz Wołka | −3 na trafienie kulą i wiązką (min. 40% obrażeń); ogień, wybuchy, szyna i broń biała bez zmian; trafienie osłabione ≥ 30% ma znacznik ARMOR |

`--weapontest` pilnuje teraz: pancerza, stref głowy, naprowadzania na cele trudne, ćmy a wiązki, źródeł SPECTER-1 / WRATH-4 oraz
widełek hałas/DPS ≤ 0,25 dla broni palnych (najgorszy dziś FALCON-6 0,21).

## 7. Faza 2 przeglądu broni (1.7.58): ulepszenia

Dane w `scripts/upgrades.gd` (`TIERS`, `COST_MULT`, `cost()`); `Upgrades.validate()` sprawdza tabelę w `--weapontest`.
Poziom 1 to zwykle pojemność, poziom 2 statystyka, **poziom 3 to zmiana zachowania**:

| Broń | Poziom 1 | Poziom 2 | Poziom 3 (zmiana zachowania) |
|---|---|---|---|
| M-83 | +10 magazynek | +15% obrażeń, szybszy reload | Tłumik (cichszy) |
| P-64 | +4 magazynek | +20% obrażeń | Tłumik |
| SPREAD-12 | +6 magazynek | ciaśniejszy rozrzut, +15% | **Podpalająca amunicja** (2 s) |
| PELLET-8 | +4 magazynek | +15%, szybszy cykl | **Pociski ogłuszające** (do 1,5 s) |
| LR-7 | +20 ładunku | +20% | Soczewka: przebija +1 cel |
| HKM-9 | +20 paliwa | +25%, dłuższe palenie | Dłuższa dysza (+30% zasięgu) |
| WRATH-4 | +2 granaty | +25% wybuch, +12% promień | **Granaty kasetowe** (2 bomby) |
| FALCON-6 | +20 rakiet | ostrzejszy czujnik, +15% | **Salwa 3 rakiet** za 2 naboje |
| SPECTER-1 | +2 magazynek | ładowanie −30% | **Przebija jedną warstwę ściany** |
| SINEW-6 | 2 bełty | większy kołczan, szybszy reload | **Bełt z hakami** (przebija cel, ogłuszenie, +20%) |
| Maczeta | +20% obrażeń | +50% łuku, +6 px zasięgu | **Executioner**: dobija wroga < 35% HP |
| Kilof | +15%, szybszy zamach | ogłuszenie +0,6 s, odrzut | **Szeroki łuk** (+60%) i ogłuszenie +0,8 s |

Cena poziomu = bazowa (60 / 120 / 220) × klasa broni, zaokrąglona do 5: P-64 i broń biała ×0,8, PELLET-8 / LR-7 / HKM-9 ×1,2,
FALCON-6 ×1,3, WRATH-4 i SINEW-6 ×1,5, SPECTER-1 ×1,7 (M-83 i SPREAD-12 bez zmian).

## 8. Faza 3 przeglądu broni (1.7.59): nowe mechaniki

| Mechanika | Jak działa | Kod |
|---|---|---|
| **Tryb serii M-83** (B) | seria 3 strzałów (0,07 s) + 0,28 s przerwy; przytrzymanie powtarza serie. Hałas strzału ×0,8, rozgrzanie ×0,6, rozrzut ×0,5. Symulacja 12 s: **6,3 hałasu/s przy 58 DPS** (ogień ciągły 12,8 przy 73) — hałas na DPS 0,11 zamiast 0,18 | `WeaponDef.burst_*`, `weapon_controller.gd` (`toggle_fire_mode`, `is_burst`) |
| **Ogień na podłodze HKM-9** | co 0,5 s ciągłego płomienia plama ognia na 4 s w miejscu lądowania; podpala wrogów i skrzynie (nie drużynę), scala się z sąsiednią, maks. 10; ćmy lecą i spalają się | `fire_patch.gd`, `level.gd` (`spawn_fire_patch`) |
| **Błysk lufy** | strzał o `flash_light` ≥ 1,6 budzi i przyciąga ćmy do strzelca przez 0,6 s | `lights.gd` (`add_flash`), `enemy.gd` (`_nearest_light`) |
| **Światło broni → Stalker** | wiązka LR-7 i płomień HKM-9 w zasięgu 10 m i linii wzroku ściągają przebudzonego Stalkera jak latarka | `lights.gd` (`light_weapon_on`), `stalker.gd` |

Broń z trybem serii dostaje `burst_size > 0` w tabeli (dziś tylko M-83); bot zawsze strzela ogniem ciągłym.

## 9. Brakujące elementy (1.7.60)

| Element | Jak działa | Kod |
|---|---|---|
| **Linka SINEW-6** (T3) | trafiony wróg dostaje prędkość ku strzelcowi (`pull` 260 px/s × `knock_mult`) zamiast odrzutu; kreska od strzelca do celu przez 0,45 s u wszystkich peerów | `WeaponDef.pull`, `combat.gd` (`_tether_fx`), `enemy.gd` (`take_hit`), `arsenal.gd` |
| **Zamurowane przejście** (marker `q`) | ściana 16 px × do 6 kafli: bryła dla fizyki i nawigacji; HP 120; niszczą ją tylko kilof (`breaks_walls`) i wybuch; rozbicie = hałas 6, gruz, odblokowanie nawigacji, synchronizacja z dołączającymi | `brick_wall.gd`, `level.gd` (`_register_walls`, `break_wall`), `combat.gd` (`in_cone`, `explode`) |
| **Ogień jako mur** | ciało statyczne na warstwie 64 (bit 7), 40 px wysokości; maska tylko u wrogów `fire_shy` (Trzosek, Ślepiec, Skoczek) | `fire_patch.gd`, `enemy.gd` (`FIRE_BIT`) |

Przejście z kilofem jest w misji 1.2 (hala pod wieżą widokową). Nowa ściana = marker `q` w dolnym wierszu przejścia (3 kafle wysokości
i bryła nad nimi); `--maptest` otwiera wszystkie ściany przed sprawdzeniem osiągalności.

## 10. Osłabienie LR-7 (1.7.61)

Po rozgrywkach LR-7 była zbyt mocna: hitscan, zasięg 14 m, 70 DPS na dwa cele, prawie bezgłośna (hałas/DPS 0,026) i 30 s ognia z jednego zapasu.

| Parametr | Było | Jest |
|---|---|---|
| Obrażenia na tyk / DPS | 7 / 70 | 6 / 60 |
| Zasięg | 14 m, bez spadku | 11 m, spadek od 5 m do 55% obrażeń na końcu |
| Hałas na tyk | 0,18 stały | 0,25 → 0,8, rośnie z rozgrzaniem (+0,04 na tyk, chłodzenie 0,25/s) |
| Hałas / DPS (seria 12 s) | 0,026 | 0,106 (M-83 0,175, P-64 0,07) |
| Bateria / zapas / max | 100 / 200 / 400 | 60 / 120 / 240 (skrzynka 50, przeładowanie 2,6 s) |
| Pancerz Wołka | — | 6 → 3 na tyk (połowa DPS), tak jak kule |

Ulepszenie „Extended cell” daje teraz +20 ładunku i +40 zapasu max. `--weapontest` pilnuje DPS ≤ 65, zasięgu ≤ 12 m, hałasu/DPS ≥ 0,05,
spadku wiązki z dystansem i grzania się lufy (119/119). Hałas ciągłej broni liczy się teraz z rozgrzaniem (`weapon_controller.gd`,
HKM-9 bez zmian — jego `heat_gain` = 0).

## 11. Ekwipunek zużywalny, faza A1 (1.7.62): granaty

Plan całości (A1–A3): szkielet rzutu → pozostałe przedmioty (dymna, mina, ładunek wyburzeniowy, apteczka, defibrylator, skaner) → zakup, boty i balans.

| | Odłamkowy (`frag`) | Fosforowy (`phos`) |
|---|---|---|
| Zapas start / maks. | 2 / 4 | 1 / 3 |
| Zapalnik | 1,8 s | 1,3 s |
| Efekt | wybuch 4 m, 90 w środku (50% na brzegu), rani drużynę, rozbija zamurowane przejścia | pole ognia 15 s z 3 plam (72 px), podpala, mur dla `fire_shy`, nie rani drużyny |
| Hałas | wybuch (`N_GRENADE` 15) | 3 |

- Klawisze: **lewy Alt** (macOS: lewy Cmd) rzut / użycie, **X** zmiana rodzaju (wybór lokalny, zapas wspólny). Rzut: łuk 230 px/s, odbija się od podłogi, zapalnik liczy się od rzutu.
- Zapas trzyma `Arsenal` (`stock`, `request_throw`, `add_throwable`, `reset_throwables`), dane `throwables.gd`; nowy rodzaj = wpis w `KINDS`/`ORDER` + gałąź w `grenade.gd` (`_detonate`).
- Sieć: klient prosi serwer o rzut (korekta wylotu, jak przy strzale), serwer zdejmuje sztukę i rozsyła `spawn_grenade`; lot deterministyczny, wybuch tylko na serwerze.

## 12. Ekwipunek zużywalny, faza A2 (1.7.63): pozostałe przedmioty

Karuzela (lewy Alt / X), dane w `throwables.gd` (`ORDER`, `KINDS`, `mode`):

| Przedmiot | Tryb | Efekt | Start / maks. |
|---|---|---|---|
| FRAG | rzut | 4 m, 90, zapalnik 1,8 s, rani drużynę | 2 / 4 |
| PHOS | rzut | pole ognia 15 s (3 plamy), mur dla `fire_shy` | 1 / 3 |
| **SMOKE** | rzut | chmura 3,5 m na 12 s; wróg nie widzi celu przez dym, dalej słyszy; hałas 2 | 1 / 3 |
| **MINE** | postaw | po 1 s uzbrojona; przebudzony wróg w stożku ±38° / 84 px → 120 obrażeń każdemu w stożku; nie rani drużyny; hałas 10 | 1 / 3 |
| **CHARGE** | postaw | zapalnik 4 s, 5 m, 150, rozbija zamurowane przejścia, rani drużynę, hałas 20 | 1 / 2 |
| **MEDKIT** | użyj (przytrzymaj klawisz) | 5 s przy rannym koledze (do 36 px) albo sobie: +1 serce; obrażenia przerywają | 1 / 3 |
| **DEFIB** | użyj (przytrzymaj klawisz) | 1,5 s: podnosi leżącego do 10 m w linii wzroku; 1 na misję | 1 / 1 |
| **OWL** | użyj | 10 s: sylwetki wrogów przez ściany do 15 m (czerwone = zagrożenie), hałas 1/s | 2 / 3 |

Start „po 1–2 sztuki” to tymczasowy zestaw do prób — faza A3 przeniesie go do zakupu w warsztacie.
Kod: `grenade.gd` (rzucane), `placed.gd` (mina, ładunek), `smoke_cloud.gd`, `scanner_view.gd`, `player._gear_tick`, `Arsenal.request_use`.

## 13. Ekwipunek zużywalny, faza A3 (1.7.65): zakup, zapas, boty

**Źródła przedmiotów:** (1) darmowy zestaw przed każdą misją, (2) zakup w warsztacie (zakładka SUPPLIES), (3) skrzynki zaopatrzenia z wrogów.

| Przedmiot | Cena | Zestaw darmowy | Maks. |
|---|---|---|---|
| FRAG | 100 | 1 | 4 |
| PHOS | 150 | — | 3 |
| SMOKE | 80 | — | 3 |
| MINE | 140 | — | 3 |
| CHARGE | 250 | — | 2 |
| MEDKIT | 70 | 1 | 3 |
| DEFIB | nie na sprzedaż | 1 | 1 |
| OWL | 120 | — | 3 |

- **Zapas przechodzi** między misjami (kryjówka → misja → kryjówka) i sesjami (zapis hosta, `progress.cfg` → `gear/stock`), przed misją dopełniany do zestawu. **Wipe** wraca do stanu z początku misji (`Arsenal.begin_mission(false)`); Nocny Dyżur (bez złomu) dostaje sam zestaw.
- **Skrzynki:** Wołek 35%, Mimik 40%, Podsłuchacz 15%, Ślepiec 10%, Skoczek 8% (× mnożnik trudności „drops"); rodzaj losowany z wag frag 3 / apteczka 3 / dym 2 / fosfor 1 / mina 1 / skaner 1; bez ładunku. Skrzynka zostaje na ziemi, gdy zapas tego rodzaju jest pełny.
- **Boty:** defibrylator na leżącym człowieku (≤ 10 m, linia wzroku, 1,5 s), apteczka na rannym człowieku (≤ 36 px, 5 s, bez wroga w 150 px), na końcu na sobie. Granatów i min nie używają (ryzyko friendly fire).
- **Menu pauzy → GEAR:** karta każdego przedmiotu (typ, zapas, cena, parametry, hałas, opis, wskazówka).
- Kod: `throwables.gd` (`issue`, `price`, `DROP_WEIGHTS`), `Arsenal.begin_mission` / `load_gear` / `use_as`, `scrap.gd` (`request_buy_supply`), `workshop_ui.gd` (strona SUPPLIES), `pickup.gd` (`supply`), `codex.gd` (`gear`).
