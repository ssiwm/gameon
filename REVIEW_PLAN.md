# Plan: zmiany po przeglądzie designu (droga do pierwszego playtestu)

Status: **plan z 2026-10-12, sprawdzony ponownie 2026-10-13 względem `origin/main` (621cf2a, PR #266); R1 i R2 wdrożone, wyniki w §6.**
Podstawa: przegląd designu spisany przy 1.7.150, sprawdzony względem kodu, oraz log jednej sesji (EASY, człowiek + bot, misje 1.1–1.3,
jeszcze na starym dźwięku). Liczby w §2 pochodzą z kodu; zachowania oznaczone „z lektury kodu” nie były jeszcze uruchomione w grze
i potwierdza je dopiero etap R1.

Co zmieniło się między 1.7.205 a 621cf2a: 23 PR-y, wszystkie dźwiękowe (`AUDIO_PLAN.md` F0–F6 i F8). Reguły gry, balans, postęp i sieć
są bez zmian, więc ustalenia z §2 stoją. Nowe są cztery rzeczy, które plan musi uwzględnić: Stalker brzmi inaczej, nagrania żyją poza
repo, numer wersji przestał opisywać build i dryf zakresu przeniósł się z grafiki na dźwięk.

## 1. Cel

Doprowadzić do pierwszej sesji z drugim człowiekiem (GDD §16.0 pkt 2, `prototype/PLAYTEST.md`), która **mierzy design, a nie błędy**,
i mieć z niej dane zamiast wrażeń. Plan nie dodaje zawartości i nie zmienia liczb balansu przed sesją — poza miejscami, w których kod
łamie regułę zapisaną w GDD.

## 2. Stan obecny (z kodu)

| Obszar | Fakt | Gdzie |
|---|---|---|
| Playtest | tabela wyników pusta; z 56 wpisów 1.7.150–205 zasady ruszają 3, a 23 kolejne PR-y to sam dźwięk | `GDD.md` §23.3, §22 |
| Stalker: trafienia | każde trafienie ustawia `_hesitate = 0.7`; z aktywnym `_hesitate` nie idzie i nie zaczyna zamachu (zmierzone w R1) | `stalker.gd:403`, `:184` |
| Stalker: teren | zawsze 88 px/s; gracz w wodzie 68, w błocie 55 — reguła „wolniejszy od gracza” nie działa (1.3: 136 kafli wody) | `stalker.gd:201`, `surfaces.gd` |
| Stalker: cofnięcie | 6 px + 0,8 s pauzy; GDD mówi „6 m” | `stalker.gd:25`, `:302`, GDD §8.5 |
| Stalker: zasięg | tylko misje 1.2 i 1.3; w sesji 7 zamachów, 6 pudeł, 1 trafienie w bota, 0 w człowieka | `level.gd:607`, log sesji |
| Stalker: dźwięk (nowe) | „szept” to teraz niski oddech, warkot z nagrań, nowy sygnał `stalker_appear`, gdy wychodzi z mroku; wrogowie mają własne głosy | `stalker.gd`, `enemy.gd` (`VOICES`), PR #251, #259 |
| Dźwięk w buildzie (nowe) | 139 plików z nagrań leży poza repo w `prototype/audio_licensed/`; gra bierze je, gdy są, inaczej gra syntezę. Jest tylko w drzewie `gameon-audio`; eksport pakuje to, co jest w drzewie | `audio_director.gd` (`_path`), `export_presets.cfg` |
| Wersja buildu (nowe) | changelog kończy się na 1.7.205, a PR-y #245–#266 nie mają wpisów; w kodzie nie ma stałej z wersją | `GDD.md` §22, `project.godot` |
| Dane z gry | brak zapisu przyczyny upadku; zdarzenia idą tylko na konsolę (`godot.log`, 5 ostatnich plików) | `player.gd:1640`, `mission.gd:346` |
| Broń | M-83 ogniem ciągłym 5,7 DPS na 1 hałasu/s, serią (B) 9,2; P-64 14,1; kusza tylko z map, 6 bełtów | `weapons.gd`, `WEAPONS.md` §3, §8 |
| Perki | Quiet steps: krok 0,125 < próg Ślepca 0,25 — Ślepiec przestaje słyszeć bieg; opis perka o tym milczy | `player.gd:723`, `enemy.gd:44`, `perks.gd:10` |
| Postęp klienta | złom, bronie, ulepszenia, trofea tylko w zapisie hosta | `scrap.gd:301` |
| Trudność | start NORMAL, wybór nie jest zapamiętywany; `PLAYTEST.md` zakłada domyślne EASY i start kampanii od 1.2 | `difficulty.gd:46`, `PLAYTEST.md:12`, `:35` |
| CI | headless nie wykonuje `view3d.gd`, `level3d.gd`, `enemy3d.gd`, `char3d.gd` (ok. 7,7 tys. linii); pomiar tylko RTX 3080 | `.github/workflows/tests.yml`, `settings.gd:197` |
| Dokumenty | nagłówek GDD 1.6.0; changelog 205 z 265 KB; §5, §6.7, §19 i wiersz 7 nieaktualne | `GDD.md` |

## 3. Etapy

Każdy etap to osobny PR. R1–R4 idą po kolei; R5 i R7 można robić równolegle, bo nie dotykają rozgrywki.

### R0. Zamrożenie zakresu grafiki i dźwięku (decyzja, bez kodu)

Do wypełnienia GDD §23.3: w grafice i dźwięku tylko poprawki błędów, które blokują sesję. Bez nowych modeli, efektów, materiałów
i rodzin dźwięków. Z `AUDIO_PLAN.md` zostaje eksperyment F7 (HRTF) i strojenie F6 w grze: F7 czeka na wynik sesji, strojenie F6 można
zrobić przy przejściu kontrolnym w R4, bo i tak trzeba wtedy grać w słuchawkach.

### R1. Test Stalkera (`--stalkertest`, headless)

Nowy test w `main.gd` obok `--stealthtest`, dopisany do CI jako osobny krok z własną linią PASS (tak jak dodane ostatnio
`test_sound_grid.gd` i `test_audio_loops.gd`). Trzy pomiary, każdy z wynikiem liczbowym w logu:

1. **Ostrzał.** Obudzony Stalker 200 px od gracza, trafienie co 0,6 s przez 10 s. Mierzymy przebytą drogę i liczbę rozpoczętych zamachów.
2. **Pościg po wodzie i błocie.** Gracz ucieka prosto po kaflach wody (potem błota), Stalker 60 px za nim. Mierzymy, czy dystans rośnie.
3. **Po ciosie.** Odległość Stalkera od gracza zaraz po trafieniu i czas do następnego zamachu.

Na tym etapie test tylko raportuje; progi PASS/FAIL dochodzą w R2. Rozmiar: mały. **Zrobione** — `scripts/stalker_test.gd`, wyniki w §6.

### R2. Stalker zgodny z własnymi regułami (tylko to, co potwierdzi R1)

| Problem | Zmiana | Uwagi |
|---|---|---|
| Zatrzymywanie strzałami | `take_bullet` nadal spowalnia (`_slow`), ale `_hesitate` odnawia się najwyżej raz na 3 s | wartość do strojenia; test: przy ostrzale Stalker dochodzi do gracza |
| Woda i błoto | prędkość Stalkera × mnożnik powierzchni, po której idzie (ten sam co gracza) | zachowuje „88 < 95” na każdym terenie; test: dystans nie maleje |
| „6 m” w GDD | poprawić GDD §8.5 na stan faktyczny (0,4 m, pauza 0,8 s, cooldown 1,5 s) | zmiana kodu na 6 m to teleport o 96 px, także przez ściany — decyzja D2 |

Bez zmian do playtestu: zasięg 14 px, zapowiedź 0,55 s, 1 obrażenie, prędkości 88 / 55. To są pytania do sesji (R6), nie błędy.
Po zmianach: `--stealthtest=25` musi nadal przechodzić. Rozmiar: mały. **Zrobione** — wyniki w §6; „6 m” poprawione w GDD (decyzja D2).

### R3. Dziennik sesji (`session_log.gd`)

Plik `user://sessions/<data>_<godzina>.jsonl`, jeden wiersz JSON na zdarzenie, pisany tylko na serwerze (host widzi całą symulację).
Zostaje na dysku hosta, nic nie wysyła. Bez limitu 5 plików, który ma `godot.log`. Wyłączony w headless, jak profil.

| Zdarzenie | Pola |
|---|---|
| `mission_start` | wersja buildu, zestaw dźwięku (nagrania / synteza), mapa, trudność, tryb, liczba ludzi i botów, pogoda |
| `down` | gracz (bot?), **źródło** (rodzaj wroga / stalker / boss / wybuch), Uwaga, broń w ręku, pozycja, faza misji, czas |
| `bleed_out`, `revive` | gracz, kto podniósł, czas leżenia |
| `stalker` | `awake` / `asleep` / `swing_hit` / `swing_miss`, Uwaga, cel (człowiek / bot), czas |
| `overcharge` | pozycja, Uwaga, czy „zwietrzały” |
| `phase` | nowa faza, czas od startu |
| `mission_end` | wynik, czas, upadki, próby, szczyt Uwagi, cel poboczny, na gracza: zabójstwa, strzały i obrażenia wg broni |

Zmiany w kodzie: `deliver_hit(amount, from_pos, source := "")` i uzupełnienie wywołań (`enemy.gd`, `stalker.gd`, `boss.gd`, `leech.gd`,
`combat.gd`, `acid_spit.gd`); liczniki strzałów i obrażeń wg broni w `mission.player_stats`. Istniejące `print("[STALKER] …")` zostają.
Wersja buildu (decyzja D6): dziś nie ma jej skąd wziąć, więc dochodzi `config/version` w `project.godot` i skrót commita zapisywany
do pliku przy eksporcie; ta sama wartość trafia na ekran menu, żeby dało się ją odczytać z nagrania.
Opcja R3b (decyzja D5): `add_noise(amount, pos, tag := "")` i suma Uwagi wg źródła (strzały, bieg, krzyk, ból, Q) w `mission_end` —
bez tego nie da się odpowiedzieć liczbą na pytanie „M-83 czy P-64”.
Test: `--missiontest` z włączonym zapisem do katalogu tymczasowego sprawdza, że plik ma `mission_start` i `mission_end`. Rozmiar: średni.

### R4. Sesja

1. Poprawić `PLAYTEST.md`: trudność ustawia prowadzący (decyzja D3), kampania zaczyna od 1.1, dodać krok „skopiuj `user://sessions/`”.
2. **Dźwięk w buildzie.** Eksport z drzewa, w którym jest komplet `audio_licensed/` (`tools/audio_lib_fetch.py sync`, potem
   `bake_audio.py` i `--import`); kontrola `tools/audio_audit.py --licensed`. Build z samej syntezy brzmi inaczej, a pytanie
   „czy Stalker straszy” opiera się na dźwięku, więc wszyscy uczestnicy muszą dostać ten sam zestaw. Zgodne z decyzją 3 z
   `AUDIO_PLAN.md` §6 (nagrania tylko lokalnie i w buildach).
3. Eksport, przejście kontrolne w słuchawkach na komputerze bez Godota; przy okazji strojenie F6 (droga dźwięku, wersje dalekie).
4. Sesja 3–5 osób: solo z botem i koop, bez tłumaczenia gry, nagranie z dźwiękiem.
5. Wypełnić GDD §23.3 i dołączyć liczby z dziennika (trafienia Stalkera w ludzi na misję, źródła upadków, czas faz, użycia Q).

Sesja z 2026-10-12 (0 trafień Stalkera w człowieka) szła na starym dźwięku i bez nagrań, więc jest punktem odniesienia dla mechaniki,
nie dla grozy.

### R5. Dokumenty (równolegle)

- Changelog §22 do osobnego `CHANGELOG.md`; w GDD zostaje odnośnik. Przy okazji zdublowane numery 1.7.100 i 1.7.101.
- Changelog nie jest prowadzony od PR #245 (23 PR-y dźwiękowe opisuje tylko `AUDIO_PLAN.md` §7). Przy wydzielaniu zdecydować, czy dalej
  pisać go ręcznie, czy składać z tytułów PR-ów; rekomendacja: z tytułów PR-ów, bo ręczny już raz się rozjechał.
- GDD §13 „Audio” i §7.3: opis brzmienia Stalkera (oddech zamiast szeptu, sygnał pojawienia się) i własnych głosów wrogów.
- Nagłówek GDD: wersja i wiersz „Grafika” (widoku 2D i grafiki klasycznej już nie ma).
- §5 sterowanie zgodnie z `actions.gd` (G = krzyk, F = flara, V = cios, R = przeładowanie, lewy Alt = przedmiot).
- §6.7 i §19: usunąć z „poza zakresem” ulepszenia, granaty, flary, zakup w kryjówce i „łup misji nie istnieje”.
- `tools/perf_bench.sh`: etykieta `classic` opisuje tryb, którego nie ma.

### R6. Decyzje po sesji (nie wdrażać wcześniej)

| Pytanie | Miara z dziennika i nagrania | Możliwe ruchy |
|---|---|---|
| Czy run-and-gun jest strategią podrzędną? | udział obrażeń i Uwagi wg broni; czy gracze sami odkrywają tryb serii (B) | podpowiedź o B, seria jako tryb domyślny M-83, korekta P-64 |
| Czy Stalker straszy? | trafienia w ludzi na misję, czas od przebudzenia do pierwszego zamachu, momenty „strach” z nagrania; osobno: czy strach budzi sam dźwięk (oddech, `stalker_appear`), zanim cokolwiek zaatakuje | eskalacja z czasem przebudzenia, zagrożenie dla leżących, częstsza obecność; F7 (HRTF) tylko jeśli gracze nie umieją wskazać, skąd nadchodzi |
| Czy klient ma po co wracać? | pytanie po sesji koop | osobisty złom albo trofea i odblokowania w profilu |
| Czy perki są wyborem? | które perki gracze zakładają po odblokowaniu | opis Quiet steps (D4), wzmocnienie Wide arm, Cold blood także dla G |
| Czy drużyna ma role? | kto używa defibrylatora, skanera, Q | gadżet startowy przypisany do slotu gracza |
| Ile powtórek mapy bez nudy? | „po której próbie zaczęło nudzić” | losowe rozmieszczenie przedmiotów w 3–4 miejscach (GDD §4), dopiero potem Strefa II |
| Czy gracz rozumie hałas? | czy potrafi powiedzieć, czemu Stalker się obudził | promień słyszalności na skanerze albo w kodeksie (strzelnicy już nie ma) |

### R7. Obraz w CI i słabszy sprzęt (równolegle)

- Krok CI pod `xvfb` z `--rendering-driver opengl3`: zrzut z każdej mapy istniejącymi flagami zrzutów; warunek: brak `SCRIPT ERROR`
  i obraz nie jest jednolity. To pierwszy test, który w ogóle wykona kod widoku 3D.
- Pomiar `--perf` na zintegrowanej grafice albo Steam Decku przed sesją — wymaga sprzętu, którego tu nie ma.

## 4. Decyzje do podjęcia

| # | Decyzja | Rekomendacja |
|---|---|---|
| D1 | Zamrozić grafikę i dźwięk do wypełnienia §23.3? | tak; F7 po sesji |
| D2 | Cofnięcie Stalkera: poprawić GDD czy kod? | GDD; kod dopiero po sesji |
| D3 | Trudność na sesję | zapamiętywać wybór w `settings.cfg`, domyślnie NORMAL, prowadzący ustawia EASY |
| D4 | Ślepiec nie słyszy biegu z Quiet steps: zamierzone? | tak i dopisać to do opisu perka; inaczej próg jest przypadkiem |
| D5 | Uwaga wg źródła w dzienniku (R3b)? | tak |
| D6 | Skąd wersja buildu? | `config/version` podbijane w PR-ach zmieniających grę + skrót commita przy eksporcie |

## 5. Poza zakresem

Strefa II, losowość map, nowe bronie, wrogowie i perki, zmiany cen i XP, strona Steam (`STORE_URL`, własny App ID) — wracają po R6.

## 6. Wyniki

### R1 (2026-10-13, `--stalkertest`, mapa 1.3, NORMAL)

| Pomiar | Wynik |
|---|---|
| Bez trafień | Stalker przechodzi 174 px w 2 s (88 px/s) |
| Trafienie co 0,6 s przez 10 s | **1 px z 200**, zero zamachów, gracz bez strat; Uwaga spada z 95 do 88, choć każdy strzał dokłada 0,5 |
| Zwykły grunt | gracz 95 px/s, Stalker 88 |
| Woda | gracz 68 px/s, **Stalker 88** |
| Błoto | gracz 55 px/s, **Stalker 88** |
| Po ciosie | cofnięcie 6 px, odstęp od gracza 16 px; **kolejnego zamachu nie ma przez ponad 7 s** |

Wszystkie trzy zachowania z §2 są potwierdzone. Ostatni wiersz to nowe ustalenie: po ciosie gracz ląduje 16 px od Stalkera, czyli
2 px poza zasięgiem 14 px, a krzyk bólu pada w miejscu, do którego Stalker już doszedł — więc ten stoi i nasłuchuje, dopóki gracz
nie zrobi nowego hałasu albo sam nie podejdzie. To zgodne z regułą „reaguje tylko na hałas” i zostaje bez zmian do sesji (pytanie
„czy Stalker straszy?” w R6), ale tłumaczy, czemu w zwykłej grze drugi cios prawie nie pada.

### R2 (2026-10-13)

| Pomiar | Przed | Po |
|---|---|---|
| Trafienie co 0,6 s przez 12 s | 1 px z 200, zero zamachów | 194 px z 200, 3 zamachy, gracz traci 2 HP |
| Woda | gracz 68, Stalker 88 | gracz 68, Stalker 63 |
| Błoto | gracz 55, Stalker 88 | gracz 55, Stalker 51 |

Zmiany w `stalker.gd`: zatrzymanie po trafieniu najwyżej raz na 3 s (`STAGGER_COOLDOWN`), spowolnienie zostaje; prędkość mnożona
przez mnożnik powierzchni pod nogami. Test ma teraz progi: przy ostrzale Stalker musi dojść do strzelca i się zamachnąć, a na każdym
terenie biegnący gracz musi być szybszy. `--stealthtest=25` bez zmian (zasypia po 20,5 s, 0 HP straty), `--maptest` PASS.
Wartości 3 s i 40% są punktem wyjścia do strojenia po sesji.
