# Plan: mapy misji Strefy I

Status: plan z 2026-10-17. **M1a–M1d (misja 1.1) w main**: obóz patrolu 1.7.278 (#350), przechodzący Stalker 1.7.279 (#351), gęstsza kopalnia i porządki 1.7.280 (#352).
**P1–P3 (pomiar)** w main (#348, #349). **Playtest 1.1 (2026-10-18, 9 podejść)** → poprawki 1.7.281 (§1.3), drugi playtest potwierdził cichą drogę.
**Wydłużenie 1.1 (§1.4):** W2 strażnica (1.7.282), W1 powrót przez obudzony las (1.7.283) i W3 bród (1.7.284) w grze; playtest 1.7.283 w §1.5.
**Do decyzji:** B1 (§3); wejście do kopalni na HARD (§1.5).
Podstawa: analiza map (lokalnie, poza repo: rzuty map z upadkami, `stats.json`) i logi sesji 1.7.211–1.7.277 (63 podejścia, 1 człowiek + bot).

**Decyzje użytkownika:**
- **1.3 The Nest zostaje bez zmian** („najlepsza mapa”). Nie ruszamy areny Żyły, kolejności gniazd ani domu Stalkera.
- B1: na razie tylko diagnoza HP (§3), bez zmian.
- Do zrobienia: **1.1** (wielkość, konsekwencja hałasu, zadanie skradania) i **pomiar tras** (§2).

## 1. Misja 1.1 Missing Patrol: dłuższa i z konsekwencją hałasu

### 1.1 Diagnoza wielkości

Odcinki trasy na grafie `nav.gd` (marsz 95 px/s, bez walki):

| Odcinek | Kolumny | Długość | Marsz | Różnica wysokości | Wrogów przy trasie |
|---|---|---|---|---|---|
| start → nieśmiertelnik 1 (polana) | 6 → 62 | 896 px | 9,4 s | 0 | 2 |
| → nieśmiertelnik 2 (jaskinia) | 62 → 125 | 1008 px | 10,6 s | 0 | 2 |
| → nieśmiertelnik 3 (sala kopalni) | 125 → 148 | 1199 px | 12,6 s | 320 px | 3 |
| → nieśmiertelnik 4 (dolna galeria) | 148 → 185 | 671 px | 7,1 s | 144 px | 3 |
| → wyjście `e` (szyb) | 185 → 189 | 334 px | 3,5 s | 176 px | 1 |
| **razem** | | **4109 px** | **43 s** | | **11 z 23** |

Dla porównania 1.3 ma 4376 px i 46 s marszu, czyli prawie tyle samo, a gra się ją 6–8 min. 1.2 ma 5039 px i 53 s marszu do ostatniego generatora (plus drezyna), a gra się ją 5–11 min.
**1.1 nie jest więc krótka przez długość trasy, tylko przez gęstość.** Za odstęp między długością marszu a czasem gry odpowiadają walka, skradanie i pion. Tymczasem:
- pierwsze dwa odcinki (połowa trasy, 20 s marszu) są płaskie (0 px w pionie) i mają razem 4 wrogów na trasie;
- 12 z 23 wrogów nie stoi przy trasie (Skoczki i Ćmy pod sufitem, boczne końce galerii);
- w mapie nie ma Stalkera, więc hałas nie kosztuje czasu: 6 z 19 podejść doszło do Uwagi 100 bez skutku;
- rzędy 0–17 (18 z 56) to puste niebo nad mapą.

Mnożnik „czas gry / czas marszu” wynosi: 1.1 ≈ 3,4 (145 s / 43 s), 1.2 ≈ 8 (bez drezyny), 1.3 ≈ 8.
Cel 5–6 min (300–360 s) wymaga obu rzeczy naraz: **dłuższej trasy (+25–35 s marszu, ok. 2500–3300 px)** i **gęstszej trasy (mnożnik z 3,4 do ok. 5)**.
Samo dosztukowanie kolumn przy obecnej gęstości dałoby ok. 290 dodatkowych kolumn, a to nierealne.

### 1.2 Zmiany (etapy, każdy osobny PR, `--maptest` + `--tagtest` + `--sneaktest` + `--finaletest`)

**M1a: nowy odcinek powierzchni z zadaniem skradania (+60–80 kolumn).**
Wstawić go między polaną (nieśmiertelnik 1, kol. 62) a jaskinią (kol. 84). Mapa urośnie z 200 do ok. 270 kolumn, a wszystko na wschód od wstawki przesunie się w prawo.
Trzeba więc przesunąć `COLLAPSE`, `ACCENTS` i wpisy sprawdzane w testach (`sneaktest` używa półki z Trzoskiem).
- Teren z pionem: zbocze, powalone pnie, 2–3 poziomy podestów (jak schodki do skrytki A). Dziś pierwsze 125 kolumn ma 0 px różnicy wysokości.
- **Zadanie skradania: obóz posterunku patrolu.** Nowy nieśmiertelnik albo przeniesiony nr 2 leży w środku śpiącej watahy (4–5 Trzosków, w tym przewodnik) na otwartej polanie bez półek.
  Przejście kucając (45 px/s) ok. 30 kolumn to ok. 11 s zamiast 5 s. Wataha ma łatwe obejście górą po podestach albo szybkie, ale głośne przejście dołem.
  Obudzona wataha to walka z 4–5 Trzoskami, która kosztuje 20–40 s i hałas, a więc konsekwencję z M1b.
- Latarka: odcinek w głębokim lesie (`AMBIENT` lokalnie ciemniejszy nie istnieje, więc ciemność daje sama noc). Do sprawdzenia, czy wystarcza bez latarki.
- Szacunek: +1100–1300 px trasy (+12–14 s marszu), przy mnożniku 5–6 daje to ok. +60–80 s gry.

**M1b: konsekwencja hałasu (scenariuszowy Stalker).**
1.1 dalej nie ma pełnego Stalkera (samouczek), ale Uwaga 100 musi coś kosztować. Warianty do wyboru:
1. **„Przechodzący” Stalker** (zalecany): gdy Uwaga pierwszy raz przekroczy próg (np. 80), Stalker wychodzi z ciemności poza kadrem po stronie, z której drużyna przyszła.
   Idzie na źródło hałasu przez 25–30 s i znika. Jeśli kogoś dopadnie, kładzie go (down, nie śmierć).
   Gracz uczy się, że hałas ściąga Istotę i że ucieczka albo cisza działają. W kodzie to `X` dodane dynamicznie albo tryb „patrol” Stalkera z czasem życia.
2. **Pościg w kopalni**: po trzecim nieśmiertelniku (zawał) Stalker rusza za drużyną rampą przez salę do szybu.
   Jest to scenariusz niezależny od hałasu: daje napięcie, ale nie uczy kosztu hałasu.
3. Oba: 1 jako lekcja, 2 jako finał.
- Czas: wariant 1 dodaje 20–40 s tylko graczom, którzy hałasują; wariant 2 dodaje 15–25 s wszystkim.

**M1c: gęstość trasy w kopalni.**
Przesunąć 2–3 wrogów z bocznych końców galerii na trasę (np. Wołek przy rampie, Trzoski na dojściu do szybu).
Skoczki i Ćmy zostają pod sufitem, ale co najmniej jeden Skoczek ma wisieć nad trasą przed nieśmiertelnikiem 3.

**M1d: porządki.**
- Wyjście `E` (kol. 14) nie działa jako wyjście, bo finał zawsze przestawia ekstrakcję na `e`. Sprawdzić, czy pasek kierunku HUD pokazuje je przed finałem; jeśli tak, wyjście usunąć albo ukryć do finału.
- Rozważyć obcięcie 10–12 z 18 pustych rzędów nieba (kamera i `bounds`), o ile widok 3D nie potrzebuje ich na tło.

**Oczekiwany wynik:** ok. 5000–5400 px trasy (55–58 s marszu) przy mnożniku ok. 5–6 daje 280–350 s. Do sprawdzenia playtestem (pomiar z §2).

### 1.3 Playtest 2026-10-18 (1.7.280, 9 podejść: 4 sukcesy na EASY/NORMAL, 5 wipe'ów na HARD)

- Czas udanej misji 147–208 s (mediana 161 s), wcześniej ok. 145 s. Wydłużenie o ok. 15 s, do celu 5–6 min wciąż daleko.
- Odcinki (mediana od poprzedniego celu): nieśmiertelnik 1 po 23 s, obóz (nr 2) +34 s, jaskinia (nr 3) +30 s, sala (nr 4) +46 s, galeria (nr 5) +28 s.
- Obóz: próbki pozycji prawie wyłącznie na dnie niecki i na moście, na konarach najwyżej jedna próbka na podejście, kucanie prawie wcale. Cichej drogi nikt nie znalazł.
- Przechodzący Stalker wyszedł w każdym podejściu (Uwaga 100 w 8 z 9). Na HARD już po 12–27 s, przy polanie, zanim gracz zebrał pierwszy nieśmiertelnik.
- **Zmiany 1.7.281:** latarnia patrolu i wstążki na konarach, porada `camp` na podejściu, Stalker dopiero po pierwszym nieśmiertelniku, na HARD od Uwagi 95.

### 1.3b Playtest 2 (1.7.281, 4 podejścia)

- Cicha droga działa: trasy idą łukiem po konarach, w niecce jest najwyżej jedna próbka na podejście, obóz zajmuje 15–24 s (wcześniej 24–63 s).
- Stalker wychodzi dopiero po pierwszym nieśmiertelniku, zwykle przy obozie (na zachodnim płaskowyżu, za plecami gracza na konarach).
- **Misja zrobiła się krótsza:** EASY 168 s, NORMAL 140 s (wcześniej mediana 161 s). Cichy obóz jest szybszy od walki w niecce.
- Odcinki między nieśmiertelnikami (EASY / NORMAL): start → 1: 29 / 16 s, obóz → 2: 35 / 20 s, jaskinia → 3: 34 / 34 s, sala → 4: 46 / 42 s, galeria → 5: 20 / 20 s, potem wyjście 4–8 s.
- HARD: 1 wipe i 1 sukces po 374 s z 6 upadkami, z tego 208 s na ostatnim odcinku (Skoczki i Ćma w kopalni).

### 1.4 Wydłużenie 1.1 do 5–6 min (propozycja, do decyzji, bez kodu)

**Ile brakuje:** udana misja trwa 140–170 s, cel to 300–360 s, więc brakuje 130–200 s.
Czas gry na sekundę marszu w 1.1 wynosi ok. 3 (EASY / NORMAL; HARD dużo więcej), więc samo wydłużenie trasy musiałoby dać +45–65 s marszu (+4300–6200 px).
Tak dużo nie da się dodać jednym odcinkiem bez rozwlekania samouczka. Stąd propozycja dwóch zmian: nowego odcinka z nową lekcją i innego zakończenia.

**W1. Powrót przez obudzony las (zakończenie, zalecane).** Najwięcej czasu za najmniej nowej treści.
- Po ostatnim nieśmiertelniku zawał zostaje, ale wyjściem jest `E` przy starcie, a nie „e” za szybem: szybem na powierzchnię i powierzchnią na zachód, przez jaskinię, obóz i polanę.
  Tak brzmiał pierwotny opis misji („ekstrakcja na początku mapy”) i tak działa `_open_extraction` (najdalsze wyjście = powrót przez obudzony teren, GDD §4).
  Martwe dziś `E` (M1d) znów ma sens.
- Żeby powrót nie był nudny, las się zmienia. Finał budzi grupy oznaczone nowym znacznikiem „śpi do finału”: 2–3 Trzoski na polanie, Wołek przy wylocie jaskini, wataha przechodzi z niecki na płaskowyż.
  Przechodzący Stalker w 1.1 działa też w fazie EXTRACT (dziś tylko w fazie celu).
- Obóz od wschodu: dziś cicha droga działa tylko na wschód (zeskok z konaru D). Na powrót trzeba dołożyć wejście na konary od wschodu (podesty z płaskowyżu co 2 kafle) albo pogodzić się z tym, że powrót przez obóz jest głośny.
- Szacunek: ok. 240 kolumn, ok. 3900 px, ok. 41 s marszu; z walką i Stalkerem **+80–120 s**.
- Koszt: dane mapy (zamiana „e” → `E`, nowy znacznik i rekwizyty, podesty w obozie), `mission._start_finale` (wybór wyjścia), `level.gd` (wrogowie budzeni finałem), `stalker.gd` (faza EXTRACT dla trybu przechodzącego), testy `--finaletest` i `--tagtest` (wyjście po zachodniej stronie).
- Ryzyko: powrót tą samą drogą bywa nudny. Ograniczają to nowe grupy, Stalker i inna kolejność przejścia obozu.

**W2. Strażnica nad wylotem jaskini (nowy odcinek, lekcja flary).** ok. 40–50 kolumn wstawionych między jaskinię (nieśmiertelnik 3, kol. 189) a rampę kopalni (kol. ok. 200).
- Drewniana wieża obserwacyjna na 4–5 kondygnacji (podesty co 2 kafle jak szyby kryjówki). Szósty nieśmiertelnik leży na szczycie, w ciemności.
- Wokół szczytu krążą 2–3 Ćmy, które ciągnie światło. Latarka ściąga je na gracza, a rzucona w bok flara (F) je odciąga. To pierwsza lekcja flary: dziś porada „flare” pojawia się dopiero po 150 s gry, bez kontekstu.
- Pod daszkiem półpiętra wisi Skoczek: wejście po ciemku jest groźne, ale da się je przeczytać.
- Szacunek: ok. 700 px trasy, w tym dużo w pionie, ok. 10 s marszu; ze wspinaczką i ćmami **+40–60 s**.
- Koszt: wstawka w siatce jak przy obozie (przesunięcie kopalni, zawału i testów o ok. 45 kolumn), 6 nieśmiertelników (teksty, odprawa, testy), porada flary w strefie strażnicy (`HINT_ZONES`).

**W3. Bród na rzece przed polaną (nowy odcinek, lekcja powierzchni).** ok. 30 kolumn płycizny i błota między startem a polaną (dziś 44 puste kolumny na rozbieg).
- Woda spowalnia (×0,72) i chlapie (hałas biegu ×1,3), błoto tłumi kroki (×0,6), ale bardzo spowalnia. Na drugim brzegu śpi Wołek.
- Szacunek: **+20–35 s**. Koszt: mały (sama siatka, bez nowej logiki).

**W4. Radio patrolu (dodatkowy cel w obozie).** Za drugim nieśmiertelnikiem trzeba przytrzymać [E] przy radiu patrolu przez ok. 6 s, a to podnosi Uwagę. To zapowiedź generatorów z 1.2.
- Szacunek: **+15–25 s**. Sam nie wystarczy, ale dobrze łączy się z W1, bo wezwanie przez radio może być pretekstem, czemu las się budzi.

**Zestawy:**

| Zestaw | Szacowany czas udanej misji (EASY / NORMAL) | Nowe lekcje | Koszt |
|---|---|---|---|
| W1 + W2 (zalecany) | ok. 260–350 s | powrót przez obudzony teren, flara i ćmy | średni |
| W1 + W2 + W3 | ok. 280–385 s | jw. + powierzchnie | średni+ |
| W2 + W3 + W4 (bez powrotu) | ok. 215–290 s | flara, powierzchnie, przytrzymanie [E] | średni, ale wciąż poniżej 5 min |
| tylko W1 | ok. 220–290 s | powrót | najmniejszy |

**Kolejność (jeśli zestaw zalecany):** najpierw W2 (sama treść mapy, mierzalna w heatmapie), potem W1 (logika finału).
Po każdym etapie playtest i `tools/session_heatmap.py --map z1_m1 --build <wersja>`.
Wątek poboczny: HARD w kopalni (6 upadków, 208 s na ostatnim odcinku) warto stroić osobno, po W1/W2.

### 1.5 Playtest 3 (1.7.283, 5 podejść: 2 sukcesy EASY/NORMAL, 2 wipe'y HARD, 1 przerwane)

- Udana misja: **268–270 s** (było 140–168 s). Do celu 300–360 s brakuje 30–90 s; bród (W3, 1.7.284) ma dołożyć 20–35 s.
- Powrót (EXTRACT): 69–111 s, najdłużej przy polanie i wyjściu (EASY 42 s). Obóz na powrocie przechodzony dnem niecki (konar E dla drogi na zachód doszedł w tym samym wydaniu, niesprawdzony w grze).
- Strażnica: tylko ok. 15 s między nieśmiertelnikami 3 i 4 (szacunek był 40–60 s) — wspinaczka jest szybka, ćmy nie zatrzymują.
- **Błąd:** w ewakuacji przechodzący Stalker wychodził „za plecami” liczonymi z zachodu, czyli przed drużyną, przy wyjściu (x = 120). Poprawione w 1.7.284 (`stalker.behind_side`).
- HARD: oba wipe'y przy wejściu do sali kopalni (Wołek pod rampą z M1c, Skoczek nad wejściem, Trzoski w sali). Do strojenia osobno, np. Wołek pod rampą tylko na EASY/NORMAL albo dalej w sali.

## 2. Pomiar tras: pozycje graczy w logu sesji

Dziś `SessionLog` zapisuje upadki (`down` z `pos`), ale nie wiadomo, gdzie drużyna spędza czas ani którędy idzie.

**P1: zdarzenie `pos` (zrobione).**
Host co 3 s (`SessionLog.POS_EVERY`) zapisuje jeden wiersz: `phase`, `noise` i listę `p` z każdym graczem (ludzie i boty): `who`, `bot`, `pos`, `hp`, `crouch`, `dead`.
Pierwsza próbka idzie zaraz po starcie próby. Rozmiar: ok. 120 B na gracza, 2 graczy przez 10 min daje ok. 50 KB na misję.
- Tylko w fazach misji (kryjówka i ekran wyniku nie piszą); headless pisze tylko z `--sessionlog=` (jak dotąd).

**P2: zdarzenia celów (zrobione).**
`objective`: `what` (`tag` / `stash` / `generator` / `nest` / `boss`), `n` z `of`, `pos`, a przy nieśmiertelniku i skrytce `who` i `bot`. Pozwolą mierzyć czas każdego odcinka trasy z §1.1.
CI (`--missiontest --sessionlog`) sprawdza, że w pliku są `pos` i `objective` gniazd oraz bossa.

**P3: narzędzie `tools/session_heatmap.py` (zrobione).**
Czyta `sessions/*.jsonl` i renderuje rzut mapy z danych `scripts/maps/<id>.gd` z trzema warstwami: mapą cieplną czasu (`pos`), trasami (linie) i upadkami (krzyżyki wg sprawcy).
Liczy też czas odcinków między celami (mediana od startu i od poprzedniego celu) i udział czasu w pasach po 20 kolumn; filtry: `--map`, `--build`, `--difficulty`, `--mode`, `--bots`.
Działa też na starych logach (same upadki i wyniki). Wymaga Pillow tylko do obrazów, raport tekstowy działa bez niego.

**Kolejność:** P1 + P2 w jednym PR (bez zmiany gry, bez numeru wersji), potem P3, a na końcu zmiany 1.1 (M1a–M1d),
żeby czas odcinków „przed” był zmierzony na obecnej mapie.

## 3. B1 The Leech: stan HP (do decyzji, bez zmian)

- `leech.gd`: `BASE_HP` 5000, +1500 za każdego dodatkowego człowieka (boty się nie liczą), razy `boss_hp` z trudności: EASY ×0,7, NORMAL ×1,0, HARD ×1,4.
  Solo + bot: EASY **3500**, NORMAL **5000**, HARD **7000**. Dwóch ludzi na NORMAL: 6500. Dla porównania Żyła ma 750 (+250 za człowieka).
- Mnożniki obrażeń: zanurzona 5%, zanurzona w świetle flary lub latarki 40%, wynurzona 100%; w ciemności regeneruje 0,5% maks. HP/s (EASY ×0,5).
- Komentarz przy stałej zakłada dla duetu ok. 77 efektywnych DPS, czyli ok. 130 s walki. W logach (11 podejść, wszystkie EASY) drużyna zadała łącznie 700–2600 obrażeń w 42–120 s,
  czyli ok. 15–25 DPS. Liczby obejmują też Trzoski z brzegów i nie mówią, ile z tego dostała sama Pijawka. Nikt nie zbił 3500 HP z EASY.
- Do decyzji: czy skalować HP pod rzeczywisty DPS (ok. 20), czy zmienić okna obrażeń (dłużej wynurzona, 40% → 60% w świetle). Najpierw pomiar z §2.
