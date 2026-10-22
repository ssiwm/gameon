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
| 2 | **SPREAD-12** | rozrzut 5×7, półautomat na komorze AK z bębnem na 25 naboi (od 1.7.313; wcześniej model pompki przy mechanice półautomatu) | Klasyk Contry; dobra z bliska, spadek obrażeń z dystansem |
| 3 | **P-83** (od 1.7.313; klucz techniczny `p64`) | sidearm, ∞ amunicji, magazynek 8 jak w prawdziwym P-83 Wanad (dawny P-64 miał tu 12, prawdziwy 6) | Cichsza od M-83, celna, **krytyk ×2** — ratunek i broń „na cicho”; od 1.7.316 kula **poddźwiękowa** (9×18 mm ≈ 315 m/s → 1070 px/s) i 8+1 z nabojem w komorze |
| 4 | **PELLET-8** | ciężka strzelba 8×10, pompka | 80 na strzał z bliska (zabija Mimika i Skoczka jednym), odrzut, ogłuszenie 0,5 s; ładowanie po 1 naboju (przerywane strzałem); śrucina 10 mało traci na pancerzu Wołka |
| 5 | **LR-7** | promień ciągły, przebija 2 | 60 DPS na 2 cele, zasięg 11 m i wiązka słabnie z dystansem (do 55%); **hałas rośnie z rozgrzaniem** (0,25 → 0,8 na tyk), bateria 60 kończy się w 6 s; promień **świeci** i **przyciąga ćmy** oraz Stalkera |
| 6 | **HKM-9** | miotacz ognia | 4 m, podpala (8 HP/s), **Trzoski uciekają w panice** |
| 7 | **WRATH-4** | granatnik po łuku (od 1.7.312 grawitacja 520 jak granat ręczny i flara, prędkość 368 — ten sam kształt toru co dawniej 280 / 300) | AoE 3 m, 80 dmg; niszczy gniazda; wybuch = +15 Uwagi; rani drużynę; **ściana zasłania** przed wybuchem (od 1.7.310, `Combat.blast_reaches`); od 1.7.316 zapalnik **uzbraja się po 80 px lotu** — bliżej granat tylko uderza (25 + ogłuszenie), bez wybuchu |
| 8 | **FALCON-6** | mikrorakiety naprowadzane (10 dmg) | Same dochodzą do celu poza osią i **wolą cele trudne do trafienia**: ćmę, skoczka, podsłuchacza; od 1.7.316 jak Gyrojet **rozpędzają się** (60 → 300 px/s w 0,25 s), więc z bliska są słabe (30% obrażeń przy wylocie) |
| 9 | **SPECTER-1** | szyna, ładowanie 1,2 s | 150 dmg przez wszystkich; **najgłośniejsza** (14 Uwagi); puszczenie przed końcem anuluje |
| 10 | **SINEW-6** | kusza, bełt do odzysku; od 1.7.313 zasięg 200 px (krótszy niż M-83) i bełt opada z prawdziwym g (120 px/s² ≈ 9,8 m/s²) | **Cicha** (0,08); bełt zostaje w świecie jako skrzynka z 1 nabojem |
| 11 | **Maczeta** | melee | 30 dmg, cisza; **zabija śpiącego lub odwróconego plecami natychmiast** i bez hałasu |
| 12 | **Kilof** | melee | 55 dmg, ogłusza (1,2 s), odrzut, hałas 0,8 |

### Profil liczbowy (wygenerowany przez `--weapontest`)

DPS przy pełnym trafieniu (granatnik: wybuch; szyna: z ładowaniem). „Hałas/s” — Uwaga na sekundę przy
ciągłym ogniu przez 12 s z modelem rozgrzania (szyna i granatnik: na cykl strzału). Wróg stoi w miejscu,
bez spadku obrażeń z dystansu.

| Broń | RPM | DPS | Magazynek | Pełne przeładowanie | Hałas/s (seria 12 s) | TTK Trzosek (30) | TTK Wołek (140) |
|---|---|---|---|---|---|---|---|
| M-83 | 545 | 72.7 | 30 | 1.80s | 12.8 | 0.41s | 1.92s |
| SPREAD-12 | 231 | 134.6 | 25 | 2.50s | 17.4 | 0.22s | 1.04s |
| P-83 | 300 | 55.0 | 8 | 1.40s | 3.9 | 0.55s | 2.55s |
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
| Smuga pocisku | **od 1.7.311 broń palna strzela szybkimi kulami** (M-83 2400 px/s ≈ 200 m/s w skali świata 3D, P-83 1500, SPREAD-12 1400, PELLET-8 1300; dawniej 280–360 px/s, wolniej niż 4× bieg postaci): kula w locie to addytywna smuga 3D od ogona do jasnego czoła o długości prędkość × 0,022 s (M-83 ok. 4,3 m), nigdy dalej niż do lufy (`Projectile.is_fast` / `tracer_len_at`, `view3d.gd: _sync_projectiles`); po trafieniu, w ścianie i na końcu zasięgu ostatni odcinek dogasa 0,08 s (`Vfx.trace` → `mirror_trace`), więc kula trafiająca z bliska w pierwszej klatce też zostawia ślad. Śrucina ma cieńszą i ciemniejszą smugę. Wolne zostają rakieta FALCON-6 (z żarem), granat WRATH-4 (z zapalnikiem) i bełt SINEW-6 (z grotem) |
| Szyna / promień | halo + rdzeń + biały środek, iskry w ścianie, światło na końcu promienia |
| Odrzut | sprite broni cofa się wzdłuż lufy (`recoil`), kamera dostaje **kierunkowe szarpnięcie** (`Feel.kick`) przeciwnie do lufy, od 1.7.313 **żadna broń nie przesuwa strzelca** (dawniej strzelby, granatnik i szyna popychały postać — prawdziwy odrzut nie przestawia stojącego człowieka); zostają szarpnięcie kamery, wznos lufy i cofnięcie ciała w pozie |
| Rozrzut | bazowy + **bloom** rosnący z serią (M-83 do 4°; od 1.7.324 przy myszy zamiast niego podrzut — §20), +0,8° w biegu, +1,5° w locie (skok, spadanie; od 1.7.316, `air_spread`), ×0,5–0,6 w kucaniu; śrut (od 1.7.312): każda śrucina w losowym miejscu własnego wycinka stożka ±`spread_deg` — pokrycie i kąt skrajny jak w dawnym równym wachlarzu, bez „grzebienia” |
| Uderzenie | wg materiału: krew (krytyk = złoty błysk), iskry + rykoszet (blacha/pancerz), drzazgi (skrzynia), pył/odłamki/rozbryzg (ściana wg kafla); od 1.7.312 **ślad po kuli** (decal 3D 9 cm na gruncie i murze, bez cieczy; najstarsze ponad 160 znikają) i **osmalenie** gruntu pod wybuchem (ok. 2 m dla WRATH-4, do 24 naraz) — `view3d.gd: mark_hit / mark_scorch` |
| Świst kul | od 1.7.312: cudza kula (kolega, bot) przelatująca do ok. 1,5 m od głowy lokalnego gracza gra `whizz` w punkcie przelotu (raz na kulę; strzelec go nie słyszy) — `projectile.gd: _near_miss` |
| Łuski | wylatują z okna wyrzutowego: punkt na osi broni między chwytem a wylotem (`eject_frac`: karabin i strzelba 0,2, P-83 0,45), u pompki w chwili przeładowania; wcześniej zawsze 0,5 m za wylotem |
| Hitmarker | biały / złoty (krytyk) / czerwony większy (zabójstwo) / szary (pancerz) + dźwięk potwierdzenia w UI |
| Celownik | kursor systemowy ukryty; **30% mniejszy niż w 1.6** (`CROSS_SCALE` = 0,7 skaluje wszystko razem); 4 ramiona rozchodzą się z rozrzutem — **od 1.7.310 to prawdziwy stożek strzału w odległości celownika od wylotu** (`WeaponDef.cone_radius`: rozrzut + bloom + bieg, u śrutu też rozstaw śrucin; nie dalej niż zasięg lotu), wiązka i szyna mają najmniejsze kółko, **łuk ciepła lufy** (biały → czerwony), pierścień przeładowania/ładowania, czerwony X przy pustym magazynku, miganie przy niskim stanie |
| Animacje broni | dobycie (broń „wchodzi” z dołu), przeładowanie (opadanie i powrót), ładowanie szyny (drżenie), cios (zamach przez łuk z pchnięciem) |
| Przeładowanie | tryb taktyczny: z nabojem w komorze szybciej niż pusty (+0,4–0,5 s), a broń z zamkiem zamkniętym (`chamber`: M-83, P-83, SPREAD-12, PELLET-8) mieści wtedy jeszcze nabój w komorze (30+1, 8+1; od 1.7.316); automatycznie po „kliku” na pustym i po wzięciu pustej broni. Od 1.7.326 (M-83, SPREAD-12): krótkie [R] — szybkie, magazynek spada z resztkami, przytrzymane [R] — taktyczne (§22) |
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
| Strefy głowy | Ślepiec, Podsłuchacz i Mimik (28% sylwetki) obok Wołka — krytyk P-83 / SINEW / M-83 ma sens |
| Pancerz Wołka | −3 na trafienie kulą i wiązką (min. 40% obrażeń); ogień, wybuchy, szyna i broń biała bez zmian; trafienie osłabione ≥ 30% ma znacznik ARMOR |

`--weapontest` pilnuje teraz: pancerza, stref głowy, naprowadzania na cele trudne, ćmy a wiązki, źródeł SPECTER-1 / WRATH-4 oraz
widełek hałas/DPS ≤ 0,25 dla broni palnych (najgorszy dziś FALCON-6 0,21).

## 7. Faza 2 przeglądu broni (1.7.58): ulepszenia

Dane w `scripts/upgrades.gd` (`TIERS`, `COST_MULT`, `cost()`); `Upgrades.validate()` sprawdza tabelę w `--weapontest`.
Poziom 1 to zwykle pojemność, poziom 2 statystyka, **poziom 3 to zmiana zachowania**:

| Broń | Poziom 1 | Poziom 2 | Poziom 3 (zmiana zachowania) |
|---|---|---|---|
| M-83 | magazynek RPK 40 | lufa RPK: rozrzut −30%, bloom −20%, pełne obrażenia 30 px dalej, +0,05 s dobycia (do 1.7.315: +15% obrażeń) | Tłumik (cichszy) |
| P-83 | przedłużka +2 (do 1.7.315: +4) | lufa wyborowa: rozrzut −40%, bloom −25% (do 1.7.315: +20% obrażeń) | Tłumik |
| SPREAD-12 | +5 w bębnie | dławik: snop −20%, pełne obrażenia 15 px dalej (do 1.7.315: +15% obrażeń) | **Podpalająca amunicja** (2 s) |
| PELLET-8 | przedłużka rury +2 (do 1.7.315: +4) | gładka pompka i stopka: cykl −12%, szarpnięcie kamery −25% (do 1.7.315: +15% obrażeń) | **Pociski ogłuszające** (do 1,5 s) |
| LR-7 | +20 ładunku | +20% | Soczewka: przebija +1 cel |
| HKM-9 | +20 paliwa | +25%, dłuższe palenie | Dłuższa dysza (+30% zasięgu) |
| WRATH-4 | +2 granaty | +25% wybuch, +12% promień | **Granaty kasetowe** (2 bomby) |
| FALCON-6 | +20 rakiet | ostrzejszy czujnik, +15% | **Salwa 3 rakiet** za 2 naboje |
| SPECTER-1 | +2 magazynek | ładowanie −30% | **Przebija jedną warstwę ściany** |
| SINEW-6 | 2 bełty | większy kołczan, szybszy reload | **Bełt z hakami** (przebija cel, ogłuszenie, +20%) |
| Maczeta | +20% obrażeń | +50% łuku, +6 px zasięgu | **Executioner**: dobija wroga < 35% HP |
| Kilof | +15%, szybszy zamach | ogłuszenie +0,6 s, odrzut | **Szeroki łuk** (+60%) i ogłuszenie +0,8 s |

Cena poziomu = bazowa (60 / 120 / 220) × klasa broni, zaokrąglona do 5: P-83 i broń biała ×0,8, PELLET-8 / LR-7 / HKM-9 ×1,2,
FALCON-6 ×1,3, WRATH-4 i SINEW-6 ×1,5, SPECTER-1 ×1,7 (M-83 i SPREAD-12 bez zmian).

## 8. Faza 3 przeglądu broni (1.7.59): nowe mechaniki

| Mechanika | Jak działa | Kod |
|---|---|---|
| **Tryb serii M-83** (B) | seria 3 strzałów (0,07 s) + 0,28 s przerwy; przytrzymanie powtarza serie. Hałas strzału ×0,8, rozgrzanie ×0,6, rozrzut ×0,5. Symulacja 12 s: **6,3 hałasu/s przy 58 DPS** (ogień ciągły 12,8 przy 73) — hałas na DPS 0,11 zamiast 0,18 | `WeaponDef.burst_*`, `weapon_controller.gd` (`toggle_fire_mode`, `is_burst`) |
| **Ogień na podłodze HKM-9** | co 0,5 s ciągłego płomienia plama ognia na 4 s w miejscu lądowania; podpala wrogów i skrzynie (nie drużynę), scala się z sąsiednią, maks. 10; ćmy lecą i spalają się. Podłoże (1.7.295): **woda** gasi płomień (para, syk, bez żaru), w **błocie** żar trwa 45% czasu, **olej** się zapala — żar 11 s i ogień biegnie po plamie co 24 px (0,22 s), zapłon plamy daje +3 Uwagi; flara, która spadnie na olej, też go zapala | `fire_patch.gd`, `level.gd` (`spawn_fire_patch`), `flare.gd` |
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

## 14. Realia, etap 0 (1.7.316)

Pierwszy etap planu `GUNSMITH_PLAN.md` (analiza systemu broni i ulepszeń, propozycja rozbudowy). Tylko poprawki zgodności z prawdziwą bronią,
bez nowych systemów:

| Zmiana | Jak działa | Kod |
|---|---|---|
| **Ulepszenia bez „+obrażeń” z lufy i spustu** | lufa daje skupienie (rozrzut, bloom, dalszy start spadku obrażeń), dławik — węższy snop, pompka — szybszy cykl; obrażenia daje amunicja. Magazynki o prawdziwych pojemnościach: RPK 40, przedłużka P-83 +2, przedłużka rury PELLET-8 +2. Test pilnuje, że żaden poziom „barrel / choke / trigger / pump / action” nie zmienia `damage` | `upgrades.gd`, `weapon_test.gd` (`_t_realia_e0`) |
| **P-83 poddźwiękowy** | 1500 → 1070 px/s (9×18 mm ≈ 315 m/s; przelicznik px/s ≈ m/s × 3,4); `Weapons.SOUND_PX` = 1165 to prędkość dźwięku w tej skali. Kula nadal leci jako smuga (próg `FAST_PX` 900), zasięg przelatuje w 0,19 s | `weapons.gd` |
| **Nabój w komorze** | `chamber`: broń z zamkiem zamkniętym po przeładowaniu z nabojem w komorze mieści `mag + 1` (`WeaponDef.capacity`); z pustej — tylko `mag`. M-83, P-83, SPREAD-12, PELLET-8 | `weapon_def.gd`, `weapon_controller.gd` (`_rl_cap`), `arsenal.gd` |
| **Uzbrojenie zapalnika WRATH-4** | `arm_dist` 80 px (ok. 6,5 m w skali świata 3D; prawdziwy 40 mm uzbraja się po 14–27 m — skrócone do skali ekranu): trafienie bliżej = tępe uderzenie (obrażenia i ogłuszenie samego pocisku, dźwięk `impact_hard`), bez wybuchu i bez +15 Uwagi; strzał pod nogi nie rani strzelca. Samolikwidacja (`fuse`) i koniec zasięgu wybuchają tylko po uzbrojeniu | `projectile.gd` (`is_armed`, `_dud`, `dud_count`) |
| **FALCON-6 jak Gyrojet** | rakieta wychodzi z lufy z 60 px/s i rozpędza się do 300 w 0,25 s (`speed_start`, `accel_time`, `WeaponDef.speed_at`); obrażenia rosną z prędkością od 30% (`boost_damage`) — z bliska słaba, z daleka pełne 10. Naprowadzanie bez zmian | `weapon_def.gd`, `projectile.gd` (`_boost`) |
| **Strzał w locie** | +1,5° rozrzutu, gdy strzelec nie stoi na ziemi (`air_spread`) | `weapon_controller.gd` (`spread_extra`) |

Kule nadal lecą bez opadania: realnie 7,62×39 opada o kilka centymetrów na 30 m, czego w grze nie widać. Kolejne etapy (amunicja według kalibru,
części z kompromisami widoczne na modelu, obsługa broni, stan techniczny) — patrz `GUNSMITH_PLAN.md` §10.

## 15. Amunicja według kalibru, etap 1 (1.7.317)

Drugi etap `GUNSMITH_PLAN.md`. Dane i reguły w `scripts/ammo.gd`, zapas w `arsenal.gd`, wybór w `weapon_controller.gd`.

| Element | Jak działa | Kod |
|---|---|---|
| **Kalibry** | `WeaponDef.caliber`: M-83 `762`, P-83 `918`, SPREAD-12 i PELLET-8 `12g`; reszta broni bez kalibru (zapas tylko dla siebie). Pula naboi zwykłych ma klucz `Ammo.pool_key` (100 + indeks kalibru; broń bez kalibru — własne id), sufit = największy `reserve_max` broni tego kalibru (`Arsenal.pool_max`). **12/70 jest wspólne dla obu strzelb** | `ammo.gd`, `Arsenal.pool` |
| **Typy naboi** | indeks 0 = zwykły; specjalne: **7,62 US** (poddźwiękowy: prędkość ×0,42 ≈ 1000 px/s, obrażenia ×0,75, hałas ×0,85, a z tłumikiem ×0,5), **7,62 BZ** (`armor_pen` 0,7, od 1.7.327 podwójna energia przebicia — §23, podpalenie 1 s), **12/70 breneka** (śrut → jeden pocisk: 85% snopa, bez rozrzutu, zasięg ×2, energia przebicia 1,3, `armor_pen` 0,3), **12/70 zapalające** (podpalenie 2 s, ×0,7), **12/70 gumowe** (×0,25, ogłuszenie +1 s, odrzut ×1,3, bez krytyka). Typ nakłada się na definicję jak ulepszenie: `Weapons.def_ammo(id, t)` (pamięć podręczna po broni, poziomie i typie) | `Ammo.apply`, `weapons.gd` |
| **Pancerz** | `Combat.make_info` niesie `ap` z definicji naboju; `enemy.take_hit` mnoży pancerz przez (1 − ap): Wołek traci od PS 3 na trafienie, od BZ 0,9 | `combat.gd`, `enemy.gd` |
| **Wybór [Z]** | akcja `ammo_type` (pad: do przypisania): następny typ kalibru, który drużyna ma w zapasie (zwykły zawsze). Typ wchodzi z następnym magazynkiem — gotowa broń od razu się przeładowuje, stary magazynek (z nabojem w komorze) wraca do zapasu swojego typu; nowy ładuje się bez komory. HUD: `30 / 150 PS`, przy wybranym innym typie `PS→US` (zapas pokazuje następny typ) | `cycle_ammo`, `loaded` / `want_ammo`, `hud.gd` |
| **Sieć** | typ leci z żądaniem strzału (`_fire_request`, `_server_fire`, `_fire_remote`) i z prośbą o naboje (`_req_rounds`, `_deposit_rpc`); serwer sprawdza `Ammo.valid`, nieznany typ = zwykły. Magazynek i typ w nim należą do gracza jak dotąd, zapas — do serwera | `weapon_controller.gd`, `arsenal.gd` |
| **Skąd amunicja specjalna** | warsztat, zakładka SUPPLIES: pudełka (`ammo_*` w `throwables.gd`, `mode` = "ammo"; US 30 szt. / 60 złomu, BZ 30 / 120, breneka 10 / 50, zapalające 10 / 60, gumowe 10 / 40). Zapas leży w `Arsenal.stock` w nabojach, więc przechodzi między misjami, wraca po wipe i zapisuje się u hosta jak granaty; reset misji go nie zeruje. Nie ma jej w wyborze przedmiotu [X]. Nocny Dyżur: bez amunicji specjalnej | `throwables.gd`, `scrap.gd`, `workshop_ui.gd`, `item_icon.gd` |
| **Ulepszenia** | dawne poziomy 3 strzelb to dziś typy naboi; w ich miejsce: SPREAD-12 T3 **lufa z portami gazowymi** (szarpnięcie kamery −35%, drżenie −30%, hałas +10%), PELLET-8 T3 **ładownica na komorze** (ładowanie łuski −25%). Tłumik M-83 i P-83 ustawia `suppressor`, z którego korzysta nabój poddźwiękowy | `upgrades.gd` |

Poza tym etapem (patrz `GUNSMITH_PLAN.md` §10): naboje 40 mm (kartacz, oświetlający, dymny, kasetowy), wspólne ogniwa NiCd LR-7 / SPECTER-1,
smugacze T-45 i amunicja specjalna w łupie z elit.

## 16. Naboje 40 mm i łup z elit (1.7.318)

Ciąg dalszy etapu 1 `GUNSMITH_PLAN.md`. WRATH-4 dostał kaliber `40mm` (pula 103) i trzy typy amunicji specjalnej:

| Typ | Wzór | Jak działa | Kod |
|---|---|---|---|
| **Kartaczowy** (`ammo_40buck`, 6 szt. / 90 złomu) | M576 | 10 śrucin po 8, rozrzut ±10°, 950 px/s bez opadania, zasięg 140 px; **bez wybuchu i bez uzbrajania** — działa z bliska, gdzie granat odłamkowy tylko uderza | `ammo.gd` (modyfikatory `set`) |
| **Oświetlający** (`ammo_40illum`, 4 / 80) | M583 | w szczycie toru (prędkość pionowa ≥ 0 po 0,15 s), przy trafieniu albo na końcu zasięgu wyrzuca **flarę na spadochronie**: opada 24 px/s, świeci jaśniej (zasięg 13 zamiast 8) i 40 s, przyciąga wrogów jak zwykła flara | `WeaponDef.payload`, `projectile._release`, `flare.gd` (`chute`), `level.spawn_flare(…, chute)` |
| **Dymny** (`ammo_40smoke`, 4 / 60) | — | w miejscu upadku chmura dymu jak granat dymny (`cloud_life`), bez wybuchu | `projectile._release`, `level.spawn_smoke` |

Kasetowy zostaje ulepszeniem WRATH-4 (poziom 3), a smugacze T-45 nie wchodzą — w grze każda kula broni palnej ma smugę od 1.7.311.

**Łup z elit:** zabita elita (Kapłan, Rzeźnik, Żerca) z szansą 60% × mnożnik trudności „drops” upuszcza pudełko amunicji specjalnej do kalibru,
z którego strzela broń noszona przez żywego człowieka, o ile ten zapas nie jest pełny (`Arsenal.pick_special_drop`, `enemy._die`, poza Nocnym
Dyżurem). Pudełko to zrzut zaopatrzenia (`pickup` „supply”), którego indeks liczy się teraz w `Throwables.SHOP_ORDER` (przedmioty mają
te same indeksy co dawniej); podniesienie dokłada całe pudełko naboi, a w świecie wygląda jak skrzynka amunicji.

## 17. Części w gniazdach, etap 2a (1.7.319)

Trzy liniowe poziomy ulepszeń (dawne `upgrades.gd`) zastąpił katalog części `scripts/parts.gd` (`GUNSMITH_PLAN.md` §4).

| Element | Jak działa | Kod |
|---|---|---|
| **Gniazda i części** | każda broń ma 2–4 gniazda (`feed`, `barrel`, `muzzle`, `action`, `stock`, `optic`, `edge`, `head`, `special`), w gnieździe element fabryczny i 1–3 części; części jednego gniazda się wykluczają (np. bęben 75 albo magazynek RPK, ciężka albo kasetowa głowica WRATH-4, ciężka albo sejsmiczna głowa kilofa). **Każda część ma koszt** — co najmniej jeden modyfikator na minus (`Parts.validate`, `is_cost`), np. magazynek RPK +0,15 s przeładowania, PBS-1 +0,05 s dobycia, lufa RPK +0,05 s dobycia | `parts.gd` (`PARTS`, `SLOT_ORDER`) |
| **Nowe alternatywy** | M-83: bęben RPK 75 (+45, przeładowanie +1,2 s), krótka lufa (dobycie ×0,7, rozrzut ×1,3, zasięg ×0,85, głośniej, od 1.7.325 grzeje się o 25% szybciej), płomieniotłumik (błysk ×0,35, szarpnięcie +15%), kolba składana AKMS (dobycie ×0,8, podrzut +15%, szarpnięcie +25%); SPREAD-12: magazynek pudełkowy na 8 (przeładowanie ×0,6). Dawne poziomy zostały częściami z tymi samymi cenami (WRATH-4 „Bandolier” → szybkoładowacz, SINEW-6 „Waxed quiver” → podwójne gumy, bo zapas drużyny nie zależy już od części) | `parts.gd` |
| **Zakup dla drużyny** | warsztat, zakładka ARMS: klawisze 1 / 2 (pad X / Y) albo kliknięcie przesuwają kursor po częściach broni, akcja kupuje część (cena z perkiem Kowal), montuje ją albo wraca do elementu fabrycznego. Serwer sprawdza broń i portfel (`Scrap.request_part` → `_part_server`), części trafiają do `Scrap.parts` (zapis u hosta, synchronizacja) | `scrap.gd`, `workshop_ui.gd` |
| **Montaż gracza** | `Profile.fits` (profil gracza): gniazdo → id części albo "" (fabryczny); gniazdo bez wyboru montuje pierwszą odblokowaną część z listy, kupiona część montuje się kupującemu. `Profile.fit_code(w)` = kod `fit` (2 bity na gniazdo) | `profile.gd` |
| **Sieć** | lokalny gracz publikuje `player.fits` (replikowane jak perki); kontroler buduje broń `Weapons.def_build(w, build)`, gdzie `build` = typ naboju \| fit << 4. Kod leci ze strzałem (`_fire_request` / `_server_fire` / `_fire_remote`), pocisk i `Combat.make_info` liczą z niego obrażenia; serwer wycina części, których drużyna nie ma (`Parts.sanitize`), a prośby o naboje ogranicza największym magazynkiem z części (`Parts.max_capacity`). `Weapons.def(w)` to od teraz broń fabryczna (zapas drużyny, łup, boty) | `weapons.gd`, `weapon_controller.gd`, `player.gd`, `arsenal.gd` |
| **Migracja zapisów** | zapis sprzed 1.7.319 z poziomami (`workshop/levels`) odblokowuje części tych poziomów (`Scrap.migrate_levels`), a samomontaż daje tę samą broń co wcześniej (z kosztami części) | `scrap.gd` |
| **Kodeks** | karta broni pokazuje części (zamontowana / odblokowana / cena) i statystyki broni tego gracza | `codex.gd`, `codex_page.gd` |

Poza etapem 2a: części widoczne na modelu 3D (2b), ława rusznikarska w 3D (2c) i więcej alternatyw dla pozostałych broni.

## 18. Części widoczne na modelu, etap 2b (1.7.320)

| Element | Jak działa | Kod |
|---|---|---|
| **Podzespoły broni bazowej** | generator buduje bryły w `with comp("mag"):` itd.; ściany niosą atrybut podzespołu, a po wypieku (jeden wypiek, ta sama tekstura) trafiają do osobnych węzłów GLB `gun_<klucz>__<podzespół>`. M-83: `mag`, `stock`, `front` (lufa, łoże, komora gazowa, muszka), `muzzle` (kompensator); SPREAD-12: `mag` (bęben z wieżyczką), `muzzle` (dławik). Przód i wylot M-83 to funkcje z parametrami (`m83_front`, `m83_muzzle`) — dla wartości domyślnych dają fabryczny AKM | `tools/gun_proc.py` (`comp`, `split_comps`) |
| **Modele części** | `gun_proc.py <broń> gunpart_<id>.glb --part=<id>` buduje część z tych samych materiałów w układzie broni i w tej samej skali; `.json` = mocowanie (`frame` — magazynek, kolba, przód z lufą; `muzzle` — tłumik, płomieniotłumik, lufa z portami siedzą na wylocie założonej lufy), `hides` (zastępowane podzespoły), `muzzle` (nowy wylot lufy) i `muzzle_add` (wydłużenie za wylotem). Wszystkie: `tools/gun_parts_all.sh` (ok. 1,5 min na RTX 3080) | `gun_proc.py` (`PART_BUILDERS`) |
| **Zestaw w tym etapie** | M-83: magazynek RPK 40, bęben RPK 75, lufa RPK (wylot +120 mm), krótka lufa (−120 mm, łoże krótsze, bez osady bagnetu), PBS-1 (+166 mm), płomieniotłumik szczelinowy, kolba składana AKMS; P-83: tłumik na gwintowanej lufie; SPREAD-12: bęben 30, magazynek pudełkowy na 8, dławik z portami. Części bez modelu (np. dławik, mechanizm) nie zmieniają wyglądu | `art/char3d/gunpart_*.glb` |
| **Składanie w grze** | `GunModel.build(klucz, części, wylot fabryczny)`: zastąpione podzespoły znikają, części „muzzle” stają na wylocie założonej lufy, fabryczny kompensator jedzie razem z wylotem. Postać trzyma broń z częściami swojego gracza (`char3d.set_gun(klucz, fit)` z `player.fits` — widzą to wszyscy), oględziny pokazują broń i statystyki z częściami tego gracza | `gun_model.gd`, `char3d.gd`, `weapon_view.gd`, `weapon_inspect.gd` |
| **Wylot pocisku** | `Char3D.aim_points(…, fit)` i błysk liczą wylot z założonej lufy i tłumika (`info_with` → `GunModel.muzzle`): PBS-1 przesuwa wylot o ok. 2 px świata, lufa RPK z PBS-1 o 3,5 px, krótka lufa cofa go o 1,5 px. `tools/test_aim_points.gd` sprawdza, że wylot rozgrywki zgadza się z modelem z częściami | `char3d.gd`, `weapon_controller.gd`, `player.gd` |

Stojaki, gabloty i łup pokazują broń fabryczną. Dev: `--shotfit=id,id…` (drużyna ma części, gracz je montuje) z `--shotgunid=N` / `--shotzoom=N` / `--shotinspect=N`.

**Pozostałe bronie (1.7.321):** podzespoły i 18 modeli części — PELLET-8: dłuższa rura magazynka (`tube`), ładownica na 6 nabojów (`saddle`);
LR-7: większy zasobnik ogniw z przewodem (`mag`), obiektyw z osłoną (mocowanie na wylocie, +36 mm); HKM-9: większy zbiornik (`tank`), dłuższa
dysza z lufą i osłoną (`front`, wylot +120 mm); WRATH-4: szybkoładowacz z dwoma granatami pod lufą; FALCON-6: większy bęben taśmy (`mag`), większy
obiektyw i reflektor IR (`optic`); SPECTER-1: większe kondensatory (`mag`), żeberka chłodzące na cewkach; SINEW-6: zapasowy harpun na boku belki,
trzecia para gum, grot z dwoma zadziorami i obejmą linki (`tip`); maczeta: długi chwyt (`grip`), cięższa i szersza głownia (`blade`); kilof:
ciężka głowa i głowa sejsmiczna z obuchem (`head`). Bez modelu zostają części bez widocznej zmiany (mechanizm, mieszanka, głowice granatów,
dławik, szlif). Test `--weapontest` sprawdza, że każdy zastępowany podzespół istnieje w modelu bazowym.

## 19. Ława rusznikarska w 3D, etap 2c (1.7.323)

Szczegóły broni w zakładce ARMS warsztatu pokazują zamiast płaskiej ikony broń w małej scenie 3D (`gun_stage.gd`): ciepła lampa nad ławą,
chłodna kontra, broń leży bokiem i lekko się kołysze, przeciągnięcie myszą obraca ją (po 2 s wraca bokiem). Na ławie leży broń z częścią spod
kursora listy — ta sama, której statystyki panel porównuje z obecnymi — złożona przez `GunModel.build`, czyli dokładnie tak, jak wygląda potem
w dłoniach postaci. Część pod kursorem świeci (poświata krawędzi) i wysuwa się ze swojego gniazda w stronę, w którą się ją zdejmuje: magazynek
w dół, lufa i tłumik do przodu, kolba do tyłu, celownik do góry. Na elemencie fabrycznym świecą fabryczne podzespoły, które części tego gniazda
zastępują. Kadr liczy się z broni fabrycznej i każdej jej części z modelem (nic nie wychodzi poza ławę, kadr nie skacze przy zmianie części), scena
renderuje się w pikselach ekranu.
Broń zablokowana leży w półmroku z czerwoną kontrą. Dev: `--shotws --shotwssel=N --shotwsopt=N` (kafel broni i opcja części).

## 20. Podrzut i oparcie, etap 3a (1.7.324)

Ustawienie **Weapon handling** (Ustawienia → Rozgrywka): **REALISTIC** (domyślnie) albo **CLASSIC** — dawne zachowanie, do porównania na playteście.

| Element | Jak działa | Kod |
|---|---|---|
| **Podrzut** (mysz) | każdy strzał unosi lufę o `bloom_per_shot × 2,2`° (±25%), najwyżej `bloom_max × 2`, lufa wraca `bloom_decay × 0,6`°/s. Rozrzut serii (bloom) przy myszy nie rośnie — strzał leci tam, gdzie lufa, a gracz ściąga mysz w dół. M-83: ok. 1° na strzał, do 8°, powrót 5,4°/s — seria z biodra wędruje w górę, krótkie serie trzymają się celu. Części, które zmniejszają bloom (lufa RPK, lufa wyborowa P-83), zmniejszają też podrzut | `weapon_controller.gd` (`climb`, `apply_climb`, `climb_mode`), `player.gd` |
| **Klawiatura, pad, boty** | bez podrzutu — 8 kierunków nie da się ściągać, więc zostaje rozrzut serii jak dotąd (GUNSMITH_PLAN §11, decyzja 3) | |
| **Kucanie** | podrzut ×0,6 (rozrzut jak dotąd ×`crouch_accuracy`) | |
| **Oparcie** | broń leży na górnej krawędzi przeszkody: pod łożem albo wylotem (0,45–1,4 długości broni od chwytu) jest krawędź bryły, kładki, skrzyni albo beczki 1,5–6 px pod linią broni, a sama linia nad nią jest wolna; na ziemi, bez biegu, lufa najwyżej lekko w dół, krawędź wyżej niż stopy. Podrzut (i narastanie rozrzutu) ×0,4, rozrzut ×0,6. Lufa stojącej postaci jest na 17–18 px, skrzynia ma 14 px, stopień z kafla 16 px: **na stojąco** opierasz broń o skrzynię i murek, **kucając** chowasz się za nimi (przeszkoda zasłania lufę) | `check_brace` |
| **Celownik** | przy podrzucie celownik stoi na torze uniesionej lufy (tam poleci kula), a kursor zostaje jako blada kropka — widać, ile ściągnąć; oparcie = zielona podpórka pod celownikiem | `weapon_view.gd` |
| **Sieć** | kierunek z podrzutem i rozrzut liczy strzelec, serwer przycina rozrzut (0–12°) jak dotąd; `aim_dir` z podrzutem jest replikowany, więc inni widzą unoszącą się broń | |

Postać nie kładzie jeszcze broni na krawędzi (poza bez zmian — karabin wisi ok. 3 px nad skrzynią). Dev: `--shotbrace` (skrzynia przed
graczem 1).

## 21. Gorąca lufa, etap 3b (1.7.325)

Temperatura lufy (0..1) jest osobna dla każdej broni i różni się od „ciepła” hałasu: tamto mierzy ciągłość ognia i opada w kilka sekund,
lufa grzeje się długim ogniem i stygnie powoli. Działa w obsłudze REALISTIC (ustawienie z §20); w CLASSIC temperatura liczy się, ale nie
zmienia rozrzutu ani hałasu.

| Element | Jak działa | Kod |
|---|---|---|
| **Nagrzewanie** | `WeaponDef.barrel_heat` na strzał: M-83 1/60 (dwa magazynki ciągłym ogniem), P-83 1/35 (cienka lufa pistoletu), SPREAD-12 i PELLET-8 1/24. Wiązka, płomień, szyna, granatnik, rakiety, łuk i broń biała się nie grzeją. Lufa RPK grzeje się o 30% wolniej (cięższa), krótka o 25% szybciej | `weapons.gd`, `parts.gd` |
| **Stygnięcie** | z pełnej do zimnej w 45 s (`BARREL_COOL`), także schowana broń | `weapon_controller.gd` (`_barrel`, `barrel_of`) |
| **Rozrzut** | cały stożek (bazowy + seria + bieg…) × (1 + 0,4·t²) — przy połowie temperatury tylko +10%, przy pełnej +40% | `spread_extra` |
| **Tłumik** | hałas × (1 + 0,5·t) — rozgrzana puszka głośnieje | `hot_can_mult` |
| **Widać** | od t > 0,5 z przodu lufy unoszą się smużki dymu (spalany smar), od t > 0,6 nad lufą faluje powietrze (pas zniekształcający obraz za sobą, `HAZE_SHADER`); przy jakości efektów LOW bez nich. Temperaturę trzymanej broni niesie gracz (`w_hot`, replikowane), więc widzą to wszyscy | `view3d.gd` (`_sync_weapon_fx`), `player.gd` |

Zostaje na etap 4 (§6): szybsze zużycie przy pełnej temperaturze i ogniu ciągłym. Dev: `--shothot` (rozgrzana lufa gracza 1).

## 22. Dwa przeładowania, etap 3c (1.7.326)

Broń z wymiennym magazynkiem (`WeaponDef.mag_drop`: M-83, SPREAD-12) w obsłudze REALISTIC. 0,25 s po rozpoczęciu przeładowania magazynek wychodzi
z gniazda i wtedy rozstrzyga się, czy [R] jest wciąż wciśnięte.

| Element | Jak działa | Kod |
|---|---|---|
| **Szybkie** ([R] krótko) | magazynek leci na ziemię z nabojami, które w nim zostały; w broni zostaje tylko nabój w komorze, z zapasu przychodzi pełny magazynek (M-83: 1 + 30). Czas jak dotąd | `weapon_controller.gd` (`_mag_out`, `_spawn_mag`) |
| **Taktyczne** ([R] przytrzymane) | resztki zostają (dawne dopełnianie), przeładowanie trwa o 0,4 s dłużej (`TAC_EXTRA`) | |
| **Magazynek na ziemi** | znajdźka `mag` (arg = broń \| typ naboju << 8, rounds = naboje): model to podzespół `__mag` broni (bęben leży płasko, magazynek pudełkowy na boku, ×1,6), stuk o ziemię (dźwięk i mały hałas 0,15). Resztki wracają do wspólnego zapasu, gdy człowiek **kucnie** nad magazynkiem — samo przejście nie wystarczy. Pusty magazynek nie świeci i znika po 30 s; na mapie leży najwyżej 16 magazynków (najstarsze znikają bez dźwięku) | `pickup.gd` (`_try_mag`), `view3d.gd` (`_sync_guns`), `level.gd` |
| **Sieć** | klient zgłasza upuszczenie (`_drop_mag_rpc`), serwer sprawdza nadawcę, broń, typ naboju i liczbę (najwyżej pełny magazynek z komorą) i stawia znajdźkę pod ręką gracza | |
| **Podpowiedź** | po pierwszym magazynku z nabojami: krótkie [R] wyrzuca magazynek, kucnij nad nim; przytrzymane [R] zachowuje naboje | `hints.gd` (`magdrop`) |

CLASSIC: dawne dopełnianie bez upuszczania. Nie zrobione: zatrzymanie zamka P-83 po ostatnim naboju (model pistoletu nie ma osobnego zamka).
Dev: `--shotmag` (magazynek M-83 z 17 nabojami i pusty bęben SPREAD-12 przy graczu 1).

## 23. Przebijalność i rykoszet, etap 3d (1.7.327)

Kula ma **energię przebicia** (`WeaponDef.pen`, typ naboju ją zmienia); każda przeszkoda zabiera swoją część, a obrażenia za nią maleją
w proporcji do energii, która została. Zastępuje dawne `pierce` (liczbę ciał) dla kul; promień LR-7, szyna i bełt SINEW-6 liczą ciała jak dotąd.

| Przeszkoda (koszt) | 9×18 PM (0,5) | 7,62 PS (1,2) | 7,62 US (0,72) | 7,62 BZ (2,4) | breneka (1,3) | śrucina (0,3) |
|---|---|---|---|---|---|---|
| skrzynia, drewno (0,6) | zostaje | przechodzi (50%) | przechodzi (17%) | przechodzi (75%) | przechodzi (54%) | zostaje |
| beczka, stal (1,5) | zostaje | zostaje | zostaje | przechodzi (38%) | zostaje | zostaje |
| ciało (1,0) | zostaje | 1 ciało, drugi cel 17% | zostaje | 2 ciała (58%, 17%) | 1 ciało, drugi cel 23% | zostaje |
| ściana z kafli | zostaje | zostaje | zostaje | zostaje | zostaje | zostaje (szyna z ulepszeniem przebija cienką warstwę) |

Liczby w nawiasach — obrażenia za przeszkodą względem pełnych. Kopia kosmetyczna kuli u klienta przechodzi tam, gdzie kula serwera.

**Rykoszet:** kula (bez wybuchu, ładunku, wbijania i naprowadzania) uderzająca w kafel blachy pod kątem ostrzejszym niż 20° odbija się raz:
połowa obrażeń i energii przebicia, prędkość ×0,6, odchylenie do ±6° liczone z punktu odbicia (ten sam wynik u serwera i klientów), iskry
i dźwięk rykoszetu. Beton i ziemia nie odbijają. Kolega trafiony rykoszetem krzyczy (hałas), nie traci zdrowia — jak przy każdym trafieniu kolegi.
Kod: `projectile.gd` (`PEN_*`, `_pass_through`, `pen_cost`, `_ricochet`), `weapons.gd`, `ammo.gd`.

## 24. Stan techniczny i zacięcia, etap 4a (1.7.328)

Ustawienie **Weapon reliability** (Ustawienia → Rozgrywka): OFF (bez zużycia i zacięć), **STANDARD** (domyślnie), VETERAN (zużycie i szansa
zacięcia ×2). Stan każdej broni gracza (0–100 %) siedzi w jego profilu (`Profile.cond`, zapis co 30 s i przy wyjściu).

| Element | Jak działa | Kod |
|---|---|---|
| **Zużycie** | 0,06 % na strzał (od 1.7.347; wcześniej 0,02) × `WeaponDef.wear` (M-83 i P-83 0,7, LR-7, FALCON-6, SPECTER-1 2,0, reszta 1) × 3 przy lufie gorętszej niż 0,8 × 1,5 z tłumikiem × ustawienie. M-83 traci ok. 1 % na 24 strzały, ok. 15 % na misję | `weapon_controller.gd` (`_wear_shot`), `profile.gd` |
| **Szansa zacięcia** | broń palna (7,62, 9×18, 12/70; `can_jam`): 0 powyżej 70 % stanu, 1 na 150 strzałów przy 30 %, ok. 1 na 86 przy 0 %. Nigdy w pierwszych 3 strzałach magazynka i nigdy dwa razy w 10 s | `jam_chance`, `_roll_jam` |
| **Niewypał** (50 %) | kurek uderza, strzału nie ma (klik). [R] — przeładowanie rączką 0,6 s, nabój wylatuje. **P-83** (podwójne działanie): drugie pociągnięcie spustu strzela | `_handle_shot`, `_start_clear` |
| **Zacięcie łuski** (40 %) | strzał wychodzi, następny — klik. [R] — przeładowanie rączką 0,6 s, bez straty naboju | |
| **Podwójne podanie** (10 %) | strzał wychodzi, następny — klik. [R] — wyjęcie magazynka i przeładowanie rączką 1,6 s, jeden nabój stracony | |
| **Widać** | HUD pod licznikiem: „JAMMED — [R] CLEAR” (P-83: „MISFIRE — PULL AGAIN”), w trakcie „CLEARING”, poniżej 40 % stanu „DIRTY”; celownik — czerwony X; oględziny [F] — „CONDITION”; podpowiedź po pierwszym zacięciu | `hud.gd`, `weapon_view.gd`, `weapon_inspect.gd`, `hints.gd` |
| **Czyszczenie** | warsztat, zakładka ARMS: wiersz „SERVICE · Clean” pod częściami — od 1.7.347 bez złomu: 1,5 s przy ławie za każde rozpoczęte 10 % zużycia (`Profile.CLEAN_STEP`), broń wraca do 100 %; odejście od ławy, zmiana broni albo ponowne [E] przerywa. Stan siedzi w profilu gracza, więc serwer nie bierze udziału | `workshop_ui.gd` (`_start_clean`, `tick_clean`), `profile.gd` (`clean_time`) |

Boty się nie zacinają. Zacięcie dotyczy broni, nie gracza — zostaje po zmianie broni i wraca z nią. Dev: `--shotjam` (broń gracza 1 brudna
i zacięta, profil bez zapisu).

## 25. Stan techniczny, etap 4b (1.7.329)

| Element | Jak działa | Kod |
|---|---|---|
| **Zestaw do czyszczenia** | nowy przedmiot „use” (CLEAN KIT, `cleankit`): 1 sztuka w zestawie na misję, w sklepie 50 złomu, najwyżej 2. Trzymany klawisz przedmiotu przez 6 s czyści broń w rękach: +40 % stanu, zacięcie usunięte; cicho, w trakcie bez ruchu i strzału, obrażenia przerywają (jak apteczka). Zapas zdejmuje serwer, efekt nakłada klient właściciela (`cleankit_done`) | `throwables.gd`, `player.gd` (`_tick_cleankit`), `arsenal.gd`, `weapon_controller.gd` |
| **Woda i błoto** | wejście na kafel wody: −5 % całej noszonej broni, błota: −10 %; ta sama powierzchnia najwyżej raz na 20 s (brnięcie tam i z powrotem to jedno zamoczenie) | `wade`, `wear_carried` |
| **Upadek** | gracz leży: broń w rękach −3 % | `on_down` |
| **LR-7: przegrzanie ogniwa** | zużyte LR-7 (ta sama krzywa co zacięcia, ×0,1 na tik wiązki): wiązka gaśnie na 1 s, HUD „CELL OVERHEATED”; mija samo, [R] nic nie robi | `fault_chance`, `_start_fault` |
| **SPECTER-1: przebicie kondensatora** | zużyty SPECTER-1 (krzywa zacięć ×5 na strzał): po naładowaniu zamiast strzału iskra — ładunek przepada, ładowanie od nowa, HUD „CAPACITOR ARCED” | `_handle_rail` |

`WeaponDef.fault`: "overheat" (LR-7), "arc" (SPECTER-1). Zostaje: brud i łuska w oknie widoczne na modelu broni.

## 26. Wprawa, etap 5a (1.7.330)

Wprawa jest osobna dla gracza i broni (`Profile.mastery`: klucz broni → punkty, zapis razem ze stanem broni). Punkty daje każde trafienie żywego
celu z tej broni: trafienie i trafienie w pancerz 1, krytyk 2, zabójstwo 5; skrzynie i beczki nic. Serwer dołącza numer broni do potwierdzenia
trafienia (`Arsenal.confirm` → sygnał `weapon_hit` tylko u strzelca).

| Stopień | Punkty | Efekt (narasta co stopień) |
|---|---|---|
| I | 60 | −2 % czasu przeładowania i dobycia, −2 % podrzutu i narastania rozrzutu, −4 % usuwania zacięcia |
| II | 200 | −4 % / −8 % |
| III | 450 | −6 % / −12 % |
| IV | 850 | −8 % / −16 % |
| V | 1500 | −10 % / −20 % |

Małe liczby — wyszkolenie, nie supermoc; boty bez wprawy. Awans — komunikat (toast) „M-83 · MASTERY II”; stopień i punkty do następnego
pokazuje warsztat (szczegóły broni), stopień — oględziny [F]. Kod: `weapon_controller.gd` (`mastery_of`, `mastery_mult`, `_on_weapon_hit`),
`profile.gd` (`MASTERY_XP`, `add_mastery`), `combat.gd`, `arsenal.gd`.

## 27. Historia broni, etap 5b (1.7.331)

| Element | Jak działa | Kod |
|---|---|---|
| **Zabójstwa** | każde zabójstwo żywego celu z danej broni trafia do historii gracza (`Profile.history`: klucz broni → zabójstwa, elity, bossowie); oględziny [F] i warsztat pokazują „KILLS” | `profile.gd` (`add_kill`, `kills`) |
| **Nacięcia** | za każdą elitę (Kapłan, Rzeźnik, Żerca) i bossa — rysa nożem na kolbie (pistolet: z tyłu zamka), najwyżej 12; za bossa głęboka (×1,6). Serwer rozpoznaje rangę zabitego (`Combat.apply`: `rank` 1 elita, 2 boss) i dokleja ją do potwierdzenia trafienia — przy randze przez sieć niezawodnie. Toast „A notch on the M-83” | `combat.gd`, `arsenal.gd` (`weapon_hit(kind, weapon, rank)`), `weapon_controller.gd` |
| **Na modelu** | `GunModel.build(…, notches, deep)`: rysy po obu bokach od tyłu broni, każda na prawdziwej powierzchni — promienie z boku w siatkę trójkątów modelu (górna krawędź kolby, potem bok na wysokości środka rysy). Widać je w dłoniach postaci (u wszystkich graczy — `player.notches`, replikowane), na ławie w warsztacie i w oględzinach | `gun_model.gd` (`add_notches`), `char3d.gd`, `gun_stage.gd`, `weapon_inspect.gd` |

Dev: `--shotnotch=N` (każda broń z N nacięciami, w tym jednym głębokim, i 120 zabójstwami; profil bez zapisu). Nie zrobione z §7.4: zużycie
widoczne na broni (przetarta oksyda) i własna nazwa broni.

## 28. Części jako znaleziska, etap 5c (1.7.333)

Części można dalej kupować w warsztacie za złom, ale można je też **znaleźć** — wtedy są za darmo.

| Element | Jak działa | Kod |
|---|---|---|
| **Skrytki** | ukryta skrytka misji (cel poboczny 1.1) poza złomem zawiera część: losową część z modelem dla broni, którą drużyna ma, jeszcze nieodblokowaną | `pickup.gd` (`_try_stash`), `scrap.gd` (`pick_find`) |
| **Elity** | Kapłan, Rzeźnik i Żerca w 30 % zostawiają część na ziemi — jej własny model (`gunpart_<id>.glb`) z poświatą; bierze ją człowiek, który do niej podejdzie | `enemy.gd` (`_die`), `pickup.gd` (`_try_part`), `view3d.gd` (`_sync_guns`) |
| **Do ekstrakcji** | znaleziona część czeka w `Scrap.found` (replikowane) jak łup złomu: po udanej ekstrakcji jest odblokowana dla drużyny (toast „… unlocked for the squad”), wipe ją zabiera. Toast przy znalezieniu, w warsztacie wiersz części ma dopisek „found — extract” | `scrap.gd` (`find_part`, `bank_loot`, `reset_loot`), `workshop_ui.gd` |

Dev: `--shotpart` (PBS-1 i bęben RPK przy graczu 1).

## 29. Zużycie i czyszczenie po przeglądzie warsztatu (1.7.347)

`WORKSHOP_PLAN.md` etap W0. Przed zmianą M-83 tracił ok. 5 % stanu na misję, a zacięcia zaczynają się poniżej 70 % — pierwsze pojawiało się po
mniej więcej sześciu misjach, a czyszczenie kosztowało najwyżej 10 złomu. Teraz:

| Co | Jak | Gdzie |
|---|---|---|
| **Zużycie ×3** | `WEAR_SHOT` 0,06 % na strzał (× `wear`, gorąca lufa, tłumik, ustawienie jak dotąd): M-83 ok. 15 % na misję; zaniedbany po dwóch misjach zaczyna się zacinać, a woda, błoto i długi ogień potrafią zejść poniżej 70 % w jednej misji — zestaw do czyszczenia ma znaczenie | `weapon_controller.gd` |
| **Czyszczenie za czas** | przy ławie bez złomu: `Profile.CLEAN_STEP` 1,5 s za każde rozpoczęte 10 % zużycia (od 55 % — 7,5 s); przycisk pokazuje postęp, ponowne [E], zmiana broni albo odejście przerywa i trzeba zacząć od nowa. Stan siedzi w profilu gracza, więc RPC czyszczenia (`Scrap.request_clean`) usunięte | `workshop_ui.gd` (`_start_clean`, `tick_clean`), `profile.gd` (`clean_time`) |
| **Złom w dzienniku sesji** | `mission_end.scrap` = {dropped — złom, który wypadł z wrogów i bossa, loot — zebrany łup, bonus — premia}; do strojenia cen (ceny części bez zmian: szacunek z map w `WORKSHOP_PLAN.md` §1.1 daje 1–1,5 misji na część) | `session_log.gd`, `level.spawn_item`, `mission.scrap_bonus` |

Test: `_t_condition_jams` (czyszczenie: przerwane bez zmian, pełne do 100 %, bank nietknięty); CI sprawdza pole `scrap` w `mission_end` testu misji.
