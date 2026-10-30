# RESULTS_PLAN — raport po akcji zamiast karty wyniku

Projekt 2026-10-30 na 1.7.435. Cel: ekran po udanej ekstrakcji ma **nagradzać** — odsłaniać wynik po kolei, liczyć łup na oczach gracza,
pokazać awans i wyróżnienia drużyny — a nie wyświetlać naraz jedenaście równie ważnych wierszy. Ton zostaje ponury (1987, raport
z akcji, pieczątki, taśma), bez cukierkowych gwiazdek i fajerwerków. Mockup do oceny (odtwarzana sekwencja, przełączniki solo / drużyna,
awans, cichy cel, „Ogranicz efekty”): https://claude.ai/artifact/T5HGFeYtam9e5o4nCCuFLt (prywatny — udostępnia autor).

**Stan (2026-10-30):** P0, P1 i P2 wdrożone razem w 1.7.436 (gałąź `feat/results-report`) z decyzjami z §12 według rekomendacji.
Różnice wobec projektu i to, czego nie zrobiono — §14.

Zakres zgodny z GDD §16.0a: zmienia się prezentacja istniejących danych (misja, złom, XP, wyróżnienia). Nowe dane są dwie: rekord czasu mapy
w profilu postaci (P1) i przebieg misji (P2). Nie ma nowej waluty, stanowiska ani warstwy warsztatu.

## 1. Co jest dziś

### 1.1 Kod
- Karta: `hud.gd` — `_build_result()` (budowa), `_fill_result()` (wiersze wg `m.kind` / Nocny Dyżur), `_drive_xp()` (licznik XP i pasek
  poziomu 1,6 s, „LEVEL UP — LV n” po końcu), `_fill_players()` (tabela KILLS / DOWNS / REVIVED), `_fill_awards()` (wyróżnienia),
  `_shift_result()` (Nocny Dyżur). Pokazuje ją `_process`, gdy `mission.phase` to `SUCCESS` albo `FAILED`; wejście `UiTheme.fade_in`.
- Klawisze: `main.gd` w fazie wyniku — `restart` (Enter / pad BACK) → `_continue_after_result` (kryjówka), `interact` (E / pad B) →
  `_continue_without_hub` (od razu następna misja, FUN_PLAN.md P0.4). Tylko host; klient widzi „Waiting for the host to continue…”.
- Dźwięk: `mission._event("success")` — `ui_confirm` + `tape_stop` na każdym peerze. Nic więcej.
- Karta ma 240 jednostek logicznych szerokości w HUD-zie skalowanym do 70 %, tekst 8–9 pt: na 1920×1080 to ok. 12 px. HUD rozgrywki
  (broń, Uwaga, przedmioty, karta misji) zostaje pod spodem w pełnej jasności.

### 1.2 Dane, które już są (każdy peer ma je lokalnie)
| Dane | Źródło | Uwagi |
|---|---|---|
| czas, upadki, próba | `mission.elapsed`, `downs`, `attempts` | replikowane w `_sync` |
| cel główny / poboczny | `goal_total`, `stashes_found/stash_total`, `side_done()`, `nests_total` | |
| Uwaga (cichy cel, ukrycie) | `peak_noise`, `silent_counts()`, `silent_ok()`, `stealth_ok()` | `peak_noise` replikowane |
| statystyki graczy | `player_stats[id]` = name, call, kills, downs, revived, revives, escapes, lures, noise | liczy serwer, `_recv_stats` raz przy sukcesie |
| wyróżnienia | `Mission.awards(player_stats, stalker_woke)` | statyczne, deterministyczne na każdym peerze |
| złom drużyny | `Scrap.last_gain` (łup + premie), premie: `BONUS_CLEAR/SIDE/NO_DOWNS/SILENT` | rozbicie: `mission.scrap_bonus()`, łup = `last_gain − bonus` |
| XP gracza | `Profile.last_mission_xp`, `last_mission_rows` ([etykieta, XP]), `last_run_xp` (zabójstwa, podniesienia) | przychodzi do klienta RPC-em chwilę **po** zmianie fazy |
| poziom i odblokowania | `Profile.level_of()`, `SLOT_LEVELS` (2, 4), `Perks.unlocked_at(lv)`, `Look.UNLOCK_LEVEL`, palety | wystarczy do linii „Odblokowano: …” |
| pierwsze przejście | wiersz „First clear” w `last_mission_rows` (`Profile.completed`) | |
| znalezione części, próbki, trofeum | `Scrap.found` → `parts` w `bank_loot`, `samples_loot`, `add_trophy` | trzeba zapamiętać listę przed `bank_loot` (czyści `found`) |
| wprawa broni | `Profile.mastery`, `mastery_level(key)`, `MASTERY_XP` | brak migawki „przed misją” |
| Nocny Dyżur | `shift_cleared`, `shift_time`, `shift_downs`, `shift_record`, `Settings.shift_best_*` | |

### 1.3 Czego brakuje
- **Rekordu mapy.** `RunLog` żyje tylko w sesji (8 wpisów). Brak najlepszego czasu na mapę w profilu postaci.
- **Rozbicia złomu dla klienta w jednej paczce.** Klient może je policzyć sam (`scrap_bonus()` z replikowanych danych), ale `last_gain`
  i premie dochodzą różnymi drogami — lepiej wysłać `{loot, bonus_rows}` w `_recv_stats`.
- **Listy znalezisk misji** po `bank_loot` (części, próbki, schematy) — zapamiętać w `Scrap.last_finds`.
- **Gotowości graczy** (klient nie może nic zrobić poza czekaniem; host nie wie, kto jeszcze czyta).
- **Przebiegu misji** (kiedy cel, kiedy upadki, ucieczki o włos) — jest tylko w dzienniku sesji serwera.
- **Migawki wprawy i bestiariusza** z początku misji (żeby pokazać „M-83: wprawa 3 → 4”, „Nowy wpis: Rzeźnik”).

### 1.4 Diagnoza
1. Brak bohatera ekranu: tytuł, cel, czas, złom, XP i „Towarzysz AI wył.” mają ten sam rozmiar i kolor.
2. Nie widać **dlaczego** dostałem nagrodę: premie złomu i XP za cel poboczny / bez upadków / po cichu są rozrzucone w trzech wierszach.
3. Nic się nie dzieje: jedyna animacja to pasek XP, a „LEVEL UP” pojawia się jako mały napis po fakcie.
4. Drużyna to tabela liczb; wyróżnienia to linia tekstu, a nie coś, co gracz „dostaje”.
5. Ryzyko: E wciśnięte w ostatniej sekundzie ekstrakcji (podnoszenie, interakcja) od razu uruchamia następną misję.
6. Za mało miejsca: 12 px tekstu na 4K i padzie z kanapy jest nieczytelne; HUD rozgrywki konkuruje z kartą.

## 2. Wzorce z branży — co bierzemy, co odrzucamy

| Gra | Co robi dobrze | Bierzemy | Odrzucamy |
|---|---|---|---|
| **Helldivers 2** | Podsumowanie misji drużyny: kolumny graczy obok siebie, potem nagrody spływają po kolei (XP, waluta, próbki), każdy licznik z dźwiękiem; da się pominąć | karty graczy obok siebie, nagrody liczone po kolei, pomijanie | militarny patos, medale za wszystko |
| **Deep Rock Galactic** | Nagrody rozbite na cel główny i poboczny, wyraźna lista „za co”, pasek XP klasy z awansem jako osobny moment | **„za co” obok nagrody** (pieczątki celów), awans jako osobna scena | wesołe kolory, humor kontroli misji |
| **Hunt: Showdown** | Po meczu dziennik łowcy: przebieg zdarzeń na osi czasu, ponura estetyka papieru i tuszu | oś czasu misji (P2), papier, tusz i pieczątki jako język wizualny | ściana zakładek z drobnymi statystykami |
| **Escape from Tarkov** | Surowy status rajdu („Survived”), rozbicie doświadczenia na kategorie, potem łup | jednoznaczny status jako tytuł, rozbicie XP na kategorie | wiele ekranów z rzędu, żadnej przyjemności |
| **Left 4 Dead** | Krótkie wyróżnienia drużynowe przy końcu rozdziału (kto najbardziej chronił, kto oberwał) | wyróżnienia przypięte do karty gracza jako pieczątki | — |
| **Destiny / Call of Duty** | Pasek XP z wyraźnym awansem i odblokowaniem, postęp broni, rekordy osobiste, szybki „gotowy” do następnej gry | awans + „Odblokowano: …”, rekord osobisty, wprawa broni (P2), gotowość graczy | jeden MVP drużyny, głosowanie, przerywniki |

### Zasady „juice” dla nagród (wspólne dla tych gier)
1. **Sekwencja, nie ściana**: wynik → dlaczego → nagroda → drużyna → co dalej. Jedna rzecz naraz przyciąga oko.
2. **Antycypacja i spłata**: licznik rośnie od zera z cykaniem, pasek się zapełnia, przy przelaniu przychodzi osobny akcent (awans).
3. **Każda nagroda ma przyczynę obok**: „PO CICHU ✓ +30 złomu” uczy grać lepiej i podpowiada, co było do wzięcia (pieczątka przekreślona).
4. **Dźwięk niesie rytm**: krótki klik na tick, głuche uderzenie na pieczątkę, niski akord na awans. Bez dzwoneczków.
5. **Szacunek dla czasu**: cała sekwencja ≤ 5,5 s, pierwsze naciśnięcie pomija do końca, drugie wykonuje akcję. Nic nie blokuje.
6. **Drużyna, nie ranking**: każdy może dostać wyróżnienie, nie ma jednego „MVP” ani miejsca ostatniego.
7. **Rekord i „pierwszy raz”** to najmocniejsze bodźce do kolejnej próby — muszą być widoczne, ale rzadkie.

### Ton Dead Air '87
Raport z akcji jednostki z 1987: ciemny panel („deck” z `UiTheme`), stencil Big Shoulders na tytule, IBM Plex Mono w liczbach, Special Elite
(maszyna do pisania) w podpisie, **pieczątki** w kolorze lampy (`ACCENT`) i krwi (`DANGER`) lekko przekrzywione, cykanie przekaźnika
i dźwięk taśmy. Zielone światło ekstrakcji zostaje w tle. Żadnych gwiazdek, konfetti, tęczowych pasków ani pulsowania.

## 3. Docelowy ekran

Proporcje dla 1920×1080 (HUD skaluje się jak dziś). Świat pod spodem przyciemniony do ok. 35 % jasności z winietą; HUD rozgrywki (broń,
Uwaga, przedmioty, karta misji, minimapa) **znika** na czas raportu. Panel raportu ok. 1180×760 px, wyśrodkowany.

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ RAPORT PO AKCJI · 1.1 ZAGINIONY PATROL · ŁATWY                    PRÓBA #1 · 5:12      │  A nagłówek (mono, przygaszony)
│                                                                                        │
│                         EKSTRAKCJA UDANA                                               │  B tytuł — bohater 1 (stencil 64 px)
│              „Nieśmiertelniki patrolu są u drużyny — czas wracać.”                     │    podpis maszynopisem
│                                                                                        │
│  ┌ CEL GŁÓWNY ─┐ ┌ CEL POBOCZNY ┐ ┌ BEZ UPADKÓW ┐ ┌ PO CICHU ───┐                       │  C pieczątki celów — „za co”
│  │ ✓ 6/6       │ │ ✓ skrytki 2/2│ │ ✓ 0         │ │ ✓ szczyt 41 │                       │    nagroda pod każdą
│  │ +100 XP +30 │ │ +50 XP  +15  │ │ +25 XP  +10 │ │      +30    │                       │
│  └─────────────┘ └──────────────┘ └─────────────┘ └─────────────┘                       │
│                                                                                        │
│  DRUŻYNA              ZAB. · UPADKI · PODN.  │  ŁUP                                     │
│  ▌macvv (ty)  HOST              40 · 0 · 0   │  ZŁOM DRUŻYNY                    +243    │  D nagrody — bohater 2
│    [RZEŹNIK zabójstwa: 40] [PRZYNĘTA …]      │   łup 158 · premie 85                    │    (mono 56 px, licznik)
│  ▌Wilk        GOTOWY ✓          22 · 1 · 0   │  TWOJE XP                        +330    │
│    [DUCH najciszej]                          │  LV 5 ███████████████▒▒▒ LV 6            │    pasek z przelaniem
│  ▌Kos         czyta…             9 · 1 · 0   │  ▣ AWANS · POZIOM 6                      │    pieczątka awansu
│    [O WŁOS pudła Stalkera: 3]                │  Odblokowano: perk Weteran               │
│  ▌Sowa        GOTOWY ✓          14 · 0 · 2   │  ◆ NOWA CZĘŚĆ: Tłumik PBS-1  ◆ +1 próbka │  E znaleziska / rekord
│    [SANITARIUSZ podniesienia: 2]             │  ▣ NOWY REKORD 5:12 (było 5:40)          │
│ ───────────────────────────────────────────────────────────────────────────────────── │
│  Towarzysz AI: wył.                 [ENTER] Kryjówka     [E] Od razu następna misja      │  F stopka + akcje
└───────────────────────────────────────────────────────────────────────────────────────┘
```

### Hierarchia informacji
1. **Wynik** (B) — pierwsze 0,6 s ekranu należy tylko do tytułu.
2. **Nagrody** (D) — największe liczby na ekranie: złom drużyny i twoje XP, pasek poziomu, awans.
3. **Za co** (C) — pieczątki celów; nieosiągnięte są przekreślone i szare, z tym, ile można było zyskać („PO CICHU — szczyt 78 · +30”).
4. **Drużyna** (karty-wiersze) — kryptonim w kolorze slotu, trzy liczby, wyróżnienia jako pieczątki na karcie, stan gotowości.
   Trzecia kolumna zmienia znaczenie: zamiast „REVIVED” (ile razy wstał) — **podniesienia kolegów** (`revives`), bo na nich stoi
   SANITARIUSZ, a „ile razy wstał” wynika już z upadków.
5. **Szczegóły** (A, F) — czas, próba, trudność, towarzysz AI: małe, przygaszone, zawsze na tym samym miejscu (zrzuty z playtestu).

### Warianty
| Wariant | Tytuł / kolor | Pieczątki C |
|---|---|---|
| 1.1 nieśmiertelniki | EKSTRAKCJA UDANA / mech | cel główny (N/N), skrytki, bez upadków, po cichu |
| 1.2 generatory | EKSTRAKCJA UDANA / mech | generatory, ukrycie (Uwaga < 60 — cel poboczny), bez upadków, po cichu (gdy `silent_counts`) |
| 1.3 gniazda | EKSTRAKCJA UDANA / mech | gniazda, Żyła, bez upadków |
| B1 boss | PIJAWKA NIE ŻYJE / mech | Pijawka, bez upadków, pierwsze przejście |
| Nocny Dyżur — misja | MISJA n ZALICZONA / mech | zamiast pieczątek: drabinka serii (n z `MISSIONS` kratek), czas serii |
| Nocny Dyżur — koniec | DYŻUR ZAKOŃCZONY / mech, SERIA PRZERWANA / krew | drabinka + rekord serii (`shift_record`) |
| Solo | jedna szeroka karta gracza zamiast czterech | bez zmian |

Wipe w kampanii nadal nie pokazuje raportu (odliczanie do powtórki) — bez zmian.

## 4. Sekwencja i czasy (pełna: 5,2 s)

| t [s] | Co | Ruch | Dźwięk |
|---|---|---|---|
| 0,00 | faza SUCCESS: świat przygasa, HUD rozgrywki znika | ściemnienie 0 → 0,65 w 0,4 s; HUD alfa → 0 w 0,3 s | `tape_stop` (jest), muzyka i ambient −8 dB |
| 0,25 | nagłówek A + tytuł B | tytuł „przybity”: skala 1,18 → 1,0 i alfa 0 → 1 w 0,16 s (ease-out), panel drgnie o 2 px | `ui_stamp` (nowy) |
| 0,55 | podpis | maszynopis: litera po literze 0,45 s | ciche stuknięcia co 3 litery (`ui_type`, nowy, −18 dB) |
| 0,90 | pieczątki C, co 0,22 s | ✓: pieczątka skala 1,3 → 1,0, obrót −3°; ✗: wjazd szary bez akcentu | ✓ `ui_stamp` (wysokość +1 półton za każdą); ✗ suchy klik |
| 1,90 | ZŁOM DRUŻYNY | licznik 0 → wartość w 0,9 s (ease-out cubic), wiersze rozbicia pojawiają się, gdy licznik minie ich sumę | `ui_tick` max 20/s, wysokość rośnie z postępem |
| 2,80 | TWOJE XP + pasek | licznik i pasek 1,6 s (logika `_drive_xp`); wiersze XP jak przy złomie | `ui_tick` niżej o kwintę |
| przy przelaniu | **AWANS** | pasek dobiega do końca, krótko rozjaśnia się (0,12 s, bez stroboskopu), zeruje i dolicza; pieczątka „AWANS · POZIOM n” + „Odblokowano: …” | `ui_levelup` (nowy: niski akord z „wow” taśmy, 1,2 s); muzyka −12 dB na 1,5 s |
| 4,40 | karty drużyny | wjazd z dołu 12 px + alfa, co 0,10 s | ciche szuranie papieru |
| 4,70 | wyróżnienia na kartach | pieczątka na karcie co 0,15 s | `ui_stamp` −8 dB, niżej |
| 5,00 | znaleziska, rekord, pierwsze przejście | pieczątki | rekord: `ui_stamp` + `radio_beep` |
| 5,20 | stopka F aktywna | podpowiedzi rozjaśniają się | — |

- **Pominięcie**: pierwsze naciśnięcie dowolnej akcji raportu (albo klik) w trakcie sekwencji → stan końcowy od razu (liczniki na wartościach
  końcowych, wszystkie pieczątki, jeden `ui_confirm`). Drugie naciśnięcie wykonuje akcję.
- **Blokada przypadkowego wyjścia**: przez pierwsze 0,6 s raport ignoruje wejście (E z podnoszenia, Enter z czatu). Akcje hosta działają
  dopiero po końcu sekwencji albo po pominięciu.
- **„Ogranicz efekty”** (`Settings.fx_mult() == 0`): stan końcowy od razu, bez skali, drgania, rozjaśnienia i maszynopisu; dźwięk tylko
  `tape_stop` + jeden `ui_stamp`. To samo zachowanie co dzisiejszy `_drive_xp`.
- **Dane spóźnione**: etap XP (i złomu u klienta) czeka na dane do 1,5 s; licznik pokazuje „…”. Jeśli nie przyjdą — etap się pomija,
  a wartość dolicza się bez animacji, gdy dojdzie. Sekwencja nigdy nie stoi.
- Wszystkie czasy w jednej tablicy stałych (`STAGES`) — strojenie bez szukania po kodzie.

## 5. Co-op (do 4 graczy, host rozstrzyga)
- Każdy peer odtwarza sekwencję lokalnie i niezależnie. Wspólne dane (cele, złom, `player_stats`, wyróżnienia) są takie same u wszystkich;
  XP, awans, odblokowania, rekord i wprawa są **własne** (sekcja „TWOJE XP”).
- `_recv_stats` (serwer → wszyscy, raz przy sukcesie) dostaje rozbicie złomu `{loot, rows}` i listę znalezisk, żeby klient nie składał
  ich z kilku źródeł.
- **Gotowość (P1)**: klient naciska akcję raportu → `mission.server_result_ready(peer)` (RPC do serwera, walidacja: faza SUCCESS/FAILED,
  peer w sesji) → serwer rozsyła zbiór gotowych. Karta gracza pokazuje „GOTOWY ✓” albo „czyta…”. Host widzi „2 / 3 gotowych”, ale **dalej
  decyduje sam** (jak dziś) — gotowość to informacja, nie blokada. Klient, który się rozłączył: karta przygaszona „rozłączony”.
- **Awans kolegi (P2)**: po zakończeniu własnego etapu XP klient wysyła serwerowi swój nowy poziom (tylko liczba, serwer sprawdza zakres),
  serwer rozsyła; karta kolegi dostaje pieczątkę „AWANS → 6”.
- Boty nie mają kart (nie są w `player_stats`); stopka mówi „Towarzysz AI: wył./wł.” jak dziś.

## 6. Wejście: klawiatura i pad (rejestr `actions.gd`)
Nowe akcje w kontekście raportu (`"menu": true`, poza listą przypisywanych):

| id | Klawiatura | Pad | Host | Klient |
|---|---|---|---|---|
| `result_continue` | Enter, Enter numeryczny, Spacja | A | pomiń → Kryjówka (kampania) / Dalej (Nocny Dyżur) | pomiń → Gotowy |
| `result_next` | E | Y | pomiń → Od razu następna misja | pomiń → Gotowy |

- `main.gd` w fazie wyniku czyta te akcje zamiast `restart` / `interact`; `restart` (Enter / BACK) zostaje jako drugi sposób na kryjówkę,
  żeby nie łamać nawyków. Klik myszą w podpowiedź = ta akcja.
- Teksty przez `Actions.key("result_continue")` / `Actions.fmt(...)`, nigdy literał. Pad pokazuje ikony przycisków jak reszta UI.
- „Następna misja” na Y, a nie na B: B w menu znaczy „wstecz”, a tu to akcja nieodwracalna.

## 7. Tłumaczenia (`ui.csv`, kolumna `pl`)
Nowe klucze (angielski w kodzie): `AFTER-ACTION REPORT` → RAPORT PO AKCJI, `MAIN OBJECTIVE` → CEL GŁÓWNY, `SIDE OBJECTIVE` → CEL POBOCZNY,
`NO DOWNS` → BEZ UPADKÓW, `SILENT RUN` → PO CICHU, `STEALTH` → UKRYCIE, `peak %d` → szczyt %d, `SQUAD SCRAP` → ZŁOM DRUŻYNY,
`loot %d · bonuses %d` → łup %d · premie %d, `YOUR XP` → TWOJE XP, `LEVEL UP · LEVEL %d` → AWANS · POZIOM %d, `Unlocked: %s` → Odblokowano: %s,
`second perk slot` → drugi slot perka, `NEW PART: %s` → NOWA CZĘŚĆ: %s, `+%d sample` → +%d próbka, `NEW RECORD %s (was %s)` → NOWY REKORD %s (było %s),
`FIRST CLEAR` → PIERWSZE PRZEJŚCIE, `SQUAD` → DRUŻYNA, `LOOT` → ŁUP, `READY` → GOTOWY, `reading…` → czyta…, `disconnected` → rozłączony,
`%d / %d ready` → %d / %d gotowych, `Skip` → Pomiń, `Ready` → Gotowy, `Continue` → Dalej, `MISSION %d CLEARED` (jest), `SERIES BROKEN` → SERIA PRZERWANA.
Istniejące zostają: `EXTRACTION COMPLETE`, podpisy misji, `Safe room`, `Next mission now`, tytuły i opisy wyróżnień (`Mission.AWARD_*`).
Polski jest dłuższy o ok. 20–30 % — pieczątki C i karty mają stałą szerokość i test mieszczenia (§9).

## 8. Dźwięk
Nowe krótkie efekty z generatora UI (`tools/bake_sfx.py`, tam gdzie `ui_click` / `ui_confirm`; na szynę `Audio.BUS_UI`, wpis w `audio_manifest.gd`):
- `ui_stamp` — głuche uderzenie gumowej pieczątki w papier na blacie (0,15 s, nisko, bez pogłosu).
- `ui_tick` — klik przekaźnika / licznika mechanicznego (20 ms); wysokość zmienia kod (`pitch_scale`), limit 20/s.
- `ui_type` — pojedyncze stuknięcie maszyny do pisania (cicho, rzadko).
- `ui_levelup` — niski akord (smyczki/organy syntezatora z lat 80.) z lekkim „wow” taśmy, 1,2 s. Nie dzwonek, nie fanfara.
Muzyka: `tape_stop` zostaje sygnałem końca; ambient (deszcz, las) trwa przyciszony — cisza po akcji jest częścią tonu. Odsłuch A/B
przed scaleniem (jak w AUDIO_PLAN.md).

## 9. Dostępność
- Pominięcie jednym naciśnięciem; „Ogranicz efekty” = stan końcowy od razu; żadnego błysku częstszego niż 3 Hz.
- Stan celu kodowany kształtem i tekstem (✓ / ✗ przekreślenie + słowo), nie tylko kolorem (mech / krew).
- Minimalny tekst 15 px na 1080p (dziś ok. 12 px); liczby nagród 48–64 px. Skala HUD-u z ustawień działa jak wszędzie.
- Pad w pełni; mysz klika podpowiedzi.
- Raport nie znika sam — nikt nie traci nagrody, bo czytał wolniej.

## 10. Architektura
- Nowy `scripts/result_screen.gd` (Control, dziecko HUD-u) zamiast `_build_result` / `_fill_*` / `_drive_xp` w `hud.gd` (2636 linii).
- `static func build_model(m, profile, scrap) -> Dictionary` — **czyste dane**: tytuł, podpis, kolor, pieczątki `[{id, ok, value, xp, scrap}]`,
  złom `{total, loot, rows}`, XP `{start, end, rows, unlocks}`, drużyna `[{id, call, slot, kills, downs, revives, awards, ready}]`,
  znaleziska, rekordy, stopka. Testowalne headless bez rysowania.
- `Sequence`: `t`, `advance(delta)`, `skip()`, `stage_visible(id)`, `counter_value(id)` — odtwarzanie i stan końcowy z tych samych stałych.
- HUD tylko pokazuje / chowa `ResultScreen` i ukrywa karty rozgrywki, gdy raport jest widoczny.
- Nocny Dyżur i boss to warianty modelu, nie osobne ekrany.

## 11. Etapy wdrożenia (zamiast trzech PR-ów — jeden, 1.7.436, na prośbę o wdrożenie całości)

### P0 — raport z sekwencją (dane, które już są)
- `result_screen.gd` z modelem, sekwencją i układem A–F; pieczątki celów z nagrodami; liczniki złomu i XP; awans z linią „Odblokowano”;
  wyróżnienia jako pieczątki na kartach; ukrycie HUD-u rozgrywki; akcje `result_continue` / `result_next`; blokada 0,6 s; pominięcie;
  „Ogranicz efekty”; teksty w `ui.csv`. Dźwięk na istniejących efektach (`ui_confirm` jako tymczasowa pieczątka, `ui_click` jako tick).
- Test `--resulttest` (`scripts/result_test.gd`, w CI):
  1. model 1.1 ze wszystkimi premiami: 4 pieczątki ✓; suma wierszy złomu = `Scrap.last_gain`; suma wierszy XP = `last_mission_xp + last_run_xp`;
  2. model z utraconym cichym celem: pieczątka ✗ z „szczyt N”, bez +30 w złomie;
  3. warianty: generatory, gniazda, B1, Nocny Dyżur (misja, koniec, porażka) — tytuł i pieczątki zgodne z tabelą §3;
  4. sekwencja: przy t = 0,5 widać tylko A–B; przy t = 6 wszystko; `skip()` → liczniki na wartościach końcowych; `fx_mult == 0` → stan końcowy przy t = 0;
  5. wejście: `result_next` w pierwszych 0,6 s nie woła `_continue_without_hub`; pierwsze naciśnięcie w trakcie pomija, drugie (host) zmienia mapę;
  6. XP spóźnione o 1,0 s: etap czeka i animuje; spóźnione o 3 s: sekwencja idzie dalej, wartość dolicza się bez animacji;
  7. awans przez dwa poziomy naraz (np. 1 → 3): dwie pieczątki, odblokowania z obu poziomów;
  8. mieszczenie: 1 i 4 graczy, 1920×1080 i 1280×720, angielski i polski — żaden Label nie wychodzi poza swój kontener (jak `--uifittest`).
- Flaga `--shotresult[=wariant]` do zrzutu w oknie (zgodnie z zasadą izolacji zapisu: `override.cfg` z `custom_user_dir`, usunąć po teście).

### P1 — gotowość, rekordy, dźwięk
- Gotowość graczy (RPC z walidacją serwera, §5); w `tools/test_net_session.sh`: klient zgłasza gotowość → host widzi „1 / 1 gotowych”,
  rozłączenie klienta → karta „rozłączony”, host dalej może przejść.
- `Profile.map_best` (per postać: id mapy → {czas, upadki}); pieczątki NOWY REKORD i PIERWSZE PRZEJŚCIE; stopka „Rekord mapy 4:58”.
  Test w `tools/test_characters.gd` (osobny katalog): zapis, odczyt, rekord tylko przy lepszym czasie, nowa kampania nie kasuje rekordów (do decyzji).
- `Scrap.last_finds` (części, próbki, schematy, trofeum) → wiersz E.
- Nowe efekty `ui_stamp`, `ui_tick`, `ui_type`, `ui_levelup` w generatorze + `tools/test_audio_loops.gd` / manifest; odsłuch A/B.

### P2 — przebieg i postęp broni
- `mission.timeline` (serwer, najwyżej 64 zdarzeń: cel, skrytka, Stalker obudzony, upadek, ucieczka o włos, wabik, start ekstrakcji;
  wysyłany w `_recv_stats`) → pasek „PRZEBIEG” jak taśma pod raportem (wzór: dziennik Hunt: Showdown). Test: limit 64, kolejność czasu, replikacja.
- Migawka `Profile.mastery` i bestiariusza na starcie misji → „M-83: wprawa 3 → 4”, „Nowy wpis w kodeksie: Rzeźnik” (link do kodeksu w kryjówce).
- Awans kolegów na ich kartach (§5).
- Opcjonalnie: powolne oddalenie kamery 3D nad miejscem ekstrakcji w czasie raportu (`view3d.gd`, wyłączone przy „Ogranicz efekty”).

## 12. Decyzje (rozstrzygnięte 2026-10-30: według rekomendacji)
1. **Pad**: A = kryjówka / gotowy, Y = od razu następna misja. Stare `restart` (Enter / pad BACK) działa dalej jako „dalej”.
2. **Gotowość**: tylko informacja dla hosta — host decyduje sam, widzi „N / M gotowych”.
3. **Rekordy**: per postać (`Profile.map_best` w `profile.cfg` postaci); nowa kampania ich nie kasuje (kasuje je tylko reset postaci).
4. **Materiał panelu**: ciemny panel z pieczątkami (jak w mockupie).
5. **HUD rozgrywki** gaśnie na czas raportu w całości (także komunikaty); wraca po zmianie mapy.

## 13. Ryzyka
- Za długa sekwencja męczy przy szybkim „od razu następna misja” — dlatego pominięcie jednym naciśnięciem i ≤ 5,5 s; po playteście
  zmierzyć w dzienniku czas od SUCCESS do akcji hosta (`mission_end` → `mission_start`).
- Dane od serwera dochodzą w różnych chwilach — sekwencja nie może zależeć od kolejności RPC (bramki z limitem czasu, test 6).
- Polski tekst w pieczątkach — stała szerokość + test mieszczenia, skróty uzgodnione w `ui.csv`.
- Dźwięki pieczątek łatwo przesadzić — głośność i wysokość w jednej tablicy, odsłuch przed scaleniem.

## 14. Wdrożenie 1.7.436 — co inaczej niż w projekcie
- **Każdy człowiek ma kartę.** Serwer zakłada wpis `player_stats` każdemu człowiekowi przy sukcesie — wcześniej gracz bez zabójstw i hałasu
  nie trafiał do tabeli, a serwer odrzucałby jego gotowość i poziom.
- **Bez znaku ✓ w liczbach.** IBM Plex Mono nie ma tego znaku (rysował „√”), więc stan celu niosą pieczątka (ZALICZONE / STRACONE),
  kolor ramki i szary kolor wartości; „GOTOWY” też bez ptaszka.
- **Rozmiary.** HUD rysuje w ok. 0,48 (UI_SCALE × NORMAL), więc raport ma własny mnożnik krojów (`FS` = 1,4) i panel 880 jednostek —
  ok. 2/3 szerokości ekranu; przy skali UI LARGE panel się pomniejsza, żeby zmieścić się w pionie.
- **Mieszczenie** sprawdza `--resulttest` dla trzech skal UI (SMALL / NORMAL / LARGE) zamiast rozdzielczości — logiczny ekran gry ma zawsze
  640×360 (stretch `canvas_items`), więc rozdzielczość okna nie zmienia układu.
- **Dźwięki** `ui_stamp`, `ui_tick`, `ui_type`, `ui_levelup` z `tools/bake_sfx.py` (synteza; wersji z nagrań brak). Odsłuch A/B — do zrobienia.
- **Przebieg misji**: serwer zapisuje cel, skrytkę, przebudzenie Stalkera, start walki z bossem, upadki i podniesienia ludzi, ucieczki
  o włos, wabiki i otwarcie ewakuacji (najwyżej 64 zdarzenia na próbę); taśma rozwija się razem z kartami drużyny.
- **Awans kolegów**: każdy peer po własnym wyniku XP zgłasza serwerowi poziom przed i po (`mission.report_level`, walidacja zakresu),
  serwer rozsyła — karta kolegi dostaje pieczątkę „AWANS → n”.
- **Nie zrobione:** oddalenie kamery 3D w czasie raportu (opcja z P2) i pomiar w dzienniku czasu od SUCCESS do akcji hosta (§13).
- Testy: `--resulttest` (62 sprawdzenia), `tools/test_net_session.sh` sekcja „raport po akcji” (`--resultnet=N`), zrzuty
  `--shotresult`, `--shotresult4`, `--shotresultt=S`.
