# Baterie i ładowarki latarki — plan

Status: **plan z 2026-10-31 (main 1.7.448, cc6064d); B0 + B1 wdrożone w 1.7.450** (#547), **B2 w 1.7.451** (gałąź `feat/battery-readability`).
Decyzje D1–D4 (§4): przyjęte warianty zalecane (2026-10-31). Zostają B3, B4.

## 1. Skąd to

Pierwszy tester zewnętrzny (2026-10-29, build 1.7.423): latarka „nie ładuje się w kryjówce ani przy śmierci” i „nie znalazłem
baterii”, więc „ciężko jej w ogóle używać” — szczególnie przy kolejnych próbach bossa i na Pijawce, której cień ujawnia dopiero
światło. Część zgłoszenia naprawił 1.7.424 (#519): wipe, punkt kontrolny, nowa misja i kryjówka dają pełną baterię, a
odrodzenie po wykrwawieniu co najmniej połowę. **W grze dalej nie ma żadnej baterii do znalezienia ani ładowarki** — jedyne
źródło w misji to wolne ładowanie przy zgaszonej latarce.

GDD przewiduje ładowarki dopiero w Strefie III (§9, mapa 3.2 „Ciemność”: „Zarządzanie baterią: ładowarki co 90 s”, strefa:
„Zarządzanie światłem i bateriami”). Ten plan daje Strefie I prosty, czytelny zapas (znajdźka) i przygotowuje ładowarkę tak,
żeby w Strefie III była już gotowym klockiem mapy.

## 2. Stan obecny (z kodu)

| Obszar | Fakt | Gdzie |
|---|---|---|
| Bateria | 180 s świecenia (`BATTERY_MAX`), zużycie 1 s/s, rój ćm na szkle do +300% | `player.gd: _update_flashlight`, `MOTH_DRAIN` |
| Ładowanie | 0,25 s/s przy zgaszonej latarce — pełna bateria od zera po 12 min, czyli dłużej niż misja | `BATTERY_RECHARGE` |
| Reset | `full_reset` → 100% (wipe, punkt kontrolny, nowa misja, kryjówka); `_respawn` → co najmniej 50% | `player.gd`, `BATTERY_RESPAWN` |
| Autorytet | bateria jest stanem **właściciela** postaci (liczy ją tylko on); serwer nie ma metody, żeby ją dodać | `player.gd` (por. `deliver_heal` → `apply_heal` RPC) |
| Bot | ma własną baterię, świeci, gdy świeci dowódca, nie kuca i ma > 1 s | `player.gd:1597` |
| HUD | pasek i procent baterii pod latarką (L), czerwony poniżej 20% | `hud.gd:1493` |
| Znajdźki | `pickup.gd`: health, ammo, cache, scrap, tag, stash, flares, supply, power, part, mag, weapon; rozstrzyga serwer, spawn i zabranie przez RPC `level.gd` | `pickup.gd`, `level.spawn_item` |
| Znaczniki map | wolne litery w legendzie `level.gd`: **`y`, `I`, `Q`** | `level.gd:614` |
| Zrzuty z wrogów | apteczka, amunicja, zaopatrzenie, amunicja specjalna elit — `EnemyDefs` × `Difficulty.m("drops")` | `enemy.gd: _die` |
| Klocek „stanowiska” | generator 1.2: trzymaj E, serwer liczy postęp, buczenie = hałas | `generator.gd` |
| Dziennik sesji | próbka `pos` co 3 s ma `lamp` i `moths`, **nie ma stanu baterii**; brak zdarzeń „pusta bateria” | `session_log.gd` |

**Dane z dzienników (107 misji z próbkami ludzi, 559 plików, bateria odtworzona z `lamp`/`moths` wg reguł 1.7.448):** latarka
świeci średnio **3,2% czasu na 1.1, 0% na 1.2, 1.3 i B1**; bateria spadła do zera w 1 misji na 107. To nasze (deweloperskie)
przejścia, nie testera — jego dzienników nie mamy. Wniosek: nie umiemy dziś zmierzyć głodu baterii, więc etap B0 (telemetria)
idzie pierwszy, a liczby z §3 są startowe do strojenia.

## 3. Plan

### B0 — telemetria (mała, pierwsza)
- `pos`: pole `bat` (procent) obok `lamp`; zdarzenia `battery_empty` (who, bot, phase, pos) i `battery` (who, bot, src = pickup,
  w B3 także charger; amount, before). Reset baterii nie ma osobnego zdarzenia — wynika z wipe'a / punktu kontrolnego w dzienniku.
- `mission_end.battery`: {dropped, picked, empty}. Właściciel zgłasza pustą latarkę serwerowi RPC (`player._report_battery_empty`),
  a poziom baterii innych peerów serwer zna z replikowanego `player.bat_pct`.
- `tools/fun_report.py`: wiersz „latarka” — % czasu z latarką, % czasu < 20%, mediana najniższej baterii, puste na próbę, baterie
  zebrane / wypadłe.
- Test: `--batterytest` sprawdza, że pole i zdarzenia się piszą.

### B1 — znajdźka „Bateria 4,5 V” (rdzeń)
- Nowy `kind = "battery"` w `pickup.gd`: płaska bateria 3R12 4,5 V (typowa w PRL-u, pasuje do '87). **+90 s (50%)**, bez
  przekroczenia `BATTERY_MAX`.
- Zasady podniesienia (jak apteczka, nic się nie marnuje): bierze żywy gracz z baterią < 90%; człowiek ma pierwszeństwo przed
  botem w promieniu 80 px; przy kilku chętnych — ten z najmniejszą baterią.
- Sieć: `player.deliver_battery(amount)` → RPC `apply_battery` do właściciela (wzór: `deliver_heal` / `apply_heal`, przyjmuje
  tylko od serwera); toast u biorącego „+50% BATERII”, dźwięk `item_pickup` (później własny klik).
- Źródła w Strefie I:
  - **znacznik `y`** na mapach: 1.1 — 2, 1.2 — 3, 1.3 — 3 (jedna przy punkcie kontrolnym Żyły), B1 — 3 (dwie przed areną
    Pijawki, przy skrzynce z flarami). Konkretne kafle wybrać z map cieplnych (`map_analysis/tools`) — tam, gdzie drużyna
    i tak przechodzi, poza głównym korytarzem (mała nagroda za zboczenie ze ścieżki);
  - **zrzut z wrogów**: `EnemyDefs` pole `battery` (domyślnie 0,08, Ślepiec 0,2) × `Difficulty.m("drops")`; nie z
    przywołanych, wędrowców Dyrektora ani w Nocnym Dyżurze (jak zaopatrzenie);
  - **rozbite gniazdo ćm**: zawsze 1 bateria — ćmy drenują baterię, więc rozbicie gniazda ją oddaje (czytelna nagroda
    za ryzyko);
  - **sejf** (`strongbox.gd`): +1 bateria obok złomu.
- Wygląd: model 3D baterii (dwie mosiężne blaszki, papierowa etykieta) — prosty skrypt Blendera w potoku `tools/build_items.sh`
  albo Meshy (~30–40 kredytów); `ITEM_SCALE` w `view3d.gd` jak apteczka; poświata ciepła biel (`GLOW["battery"]`). Wdrożone:
  `m_battery` w `tools/concept/items_proc_bake.py` → `art/items/battery.png` i `art/items3d/battery.glb` (`prep_items3d.py --only=battery`),
  ok. 25 cm w świecie. Mini-mapa nie pokazuje znajdziek (flar też nie) — bez ikony.
- Testy: nowy `--batterytest` (podnosi tylko < 90%, +90 s z obcięciem, bot ustępuje człowiekowi, sejf daje baterię, Ćma bez
  losowego zrzutu) + krok `--batterynet` w `test_net_session.sh` (klient dostaje baterię przez RPC). Gniazdo ćm — tylko przegląd kodu
  (`enemy_moth._nest_cleared`), bez osobnego testu.
- Wdrożone wartości: Trzosek 0,04, Skoczek 0,08, Podsłuchacz 0,1, Wołek 0,12, Mimik 0,15, Ślepiec 0,2, elity 0,3; znaczniki: 1.1 (126,17)
  i (258,42); 1.2 (238,21), (152,39), (125,50); 1.3 (177,25) tuż przed Żyłą, (62,39), (108,39); B1 (38,26), (64,26), (90,26) — kładki
  nad basenem Pijawki, przy skrzynkach z flarami.

### B2 — czytelność
- Poniżej 20%: snop migocze co kilka sekund, a przy przejściu progu krótki klik i podpowiedź raz na profil („Bateria się
  kończy — płaskie baterie 4,5 V leżą na mapie, wypadają z wrogów i z gniazd ćm”, `hints.gd`).
- Kodeks: wpis „Bateria 4,5 V” (a po B3 „Ładowarka”); przy latarce w kodeksie zdanie o źródłach baterii.
- Raport po akcji (`result_screen.gd`): wiersz „baterie zebrane”, jeśli były.
- `ui.csv`: nowe klucze PL/EN, `--uifittest`.
- Wdrożone: `player.low_battery_dim` (poniżej `BATTERY_LOW` 0,2 dwa przygaśnięcia do 30% na początku każdych 3,5 s, przesunięte o
  `display_id`), klik przy przejściu progu, `hints.gd` „battery_low”, `codex.flashlight_entry` (ikona `art/hud/battery.png` z
  `bake_hud_icons.gd`), `mission.batteries` → `finds.batteries` → wiersz raportu. Kodeks ma liczby wpisane ręcznie (opis przy funkcji).

### B3 — ładowarka (klocek na mapę, w Strefie I jedna)
- Nowy węzeł `charger.gd` na znaczniku **`Q`**, na wzór `generator.gd` (autorytet serwera, gracz zgłasza tylko „stoję / zszedłem”):
  stojąc w zasięgu ze zgaszoną latarką, bateria rośnie **6 s/s** (od zera do pełna w 30 s). Ładowarka **buczy** (hałas jak
  `HUM_NOISE` generatora co 4,5 s) — bezpieczeństwo światła za cenę hałasu.
- Strefa I: jedna ładowarka na B1 przed areną Pijawki (tam latarka jest wymagana do walki). Reszta — w Strefie III wg GDD
  („co 90 s” na 3.2), już gotowym klockiem.
- Model: stary prostownik / ładowarka akumulatorów z kablami (Meshy albo Poly Haven, jeśli coś pasuje); lampka kontrolna jako
  światło sceny (zielona przy ładowaniu).
- Testy: `--batterytest` — ładuje tylko przy zgaszonej latarce, w zasięgu, hałas co `HUM_INTERVAL`, dwóch graczy ładuje się
  naraz.

### B4 — strojenie po playteście
Na danych z B0: wartość baterii, liczba znaczników, szanse zrzutu, tempo ładowania pasywnego (D3). Zmiany liczbowe, bez
nowego kodu.

## 4. Decyzje

| | Pytanie | Warianty | Zalecane |
|---|---|---|---|
| D1 | Ile daje bateria | a) 50% (90 s) · b) 100% (pełna) | **a** — kilka znajdziek na mapę zamiast jednej „pełnej”; pełną daje i tak reset przy wipe'ie |
| D2 | Ładowarki w Strefie I | a) jedna na B1 przed Pijawką · b) żadnej (dopiero Strefa III) · c) po jednej na każdej mapie | **a** — tam latarka jest wymagana; więcej rozmyłoby pomysł z GDD 3.2 |
| D3 | Pasywne ładowanie 0,25 s/s | a) zostaje do playtestu · b) obniżyć do 0,1 razem z B1 · c) usunąć | **a** — zmieniamy jedną rzecz naraz; decyzja w B4 na danych z B0 |
| D4 | Bot i baterie | a) bot bierze, ale ustępuje człowiekowi · b) bot nie bierze wcale | **a** — bot świeci razem z dowódcą, pusta bateria bota psuje mu pomoc w ciemności |

## 5. Kolejność i zakres PR

1. **B0 + B1** razem (jeden PR) — telemetria musi być w buildzie, który dostanie tester, inaczej B4 nie ma z czego stroić.
2. **B2** (osobny PR, mały).
3. **B3** (osobny PR) — po D2.
4. Nowy build dla testera po 1–2, potem B4.

Poza zakresem: perk na większą baterię (np. „Zapasowe ogniwo”), ulepszenie latarki w warsztacie, baterie jako towar w
zaopatrzeniu — wrócić po B4, jeśli dane pokażą, że baterii nadal brakuje.
