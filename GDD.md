# DEAD AIR '87 — Game Design Document

**Wersja:** 1.6.0 (po analizie "wciągająca, przyjemna gra" — game feel, Stalker, down/revive, zakres; patrz §22–§23)
**Gatunek:** Co-op survival horror / retro run-and-gun (side-scroll)
**Gracze:** 1–4 online (2–3 to projektowany default; **AI towarzysz od premiery EA**)
**Silnik:** Godot 4.x + GodotSteam
**Platformy:** Steam (PC) → GOG → Epic (decyzja odroczona do ≥25k sprzedaży, patrz §15)
**Model:** premium, bez MTX
**Cena:** **$9.99** (EA i 1.0) — patrz §17.3, dlaczego nisko
**Zespół:** 1–3 osoby
**Czas do EA:** 18–30 mies. pracy własnej (nie 9–14 — patrz §16.4)
**Kill criteria:** patrz §16.5

---

## 1. High concept

Rok 1987. Oddział specjalny „Cicha Godzina" wkracza do zamkniętego kompleksu **Obiekt 86** na Syberii, gdzie radziecki program biologiczny obudził coś, co poluje dźwiękiem. Strzelasz jak w *Contrze*, ale **każdy strzał, krzyk i bieg przywołują Istotę, której nie da się zabić**.

> **Pitch sprzedażowy (jedno zdanie):** „Contra spotyka Lethal Company — run-and-gun, w którym twoja własna krzycząca ekipa jest najgroźniejszym wrogiem."

---

## 2. Filary projektowe

| # | Filar | Znaczenie |
|---|-------|-----------|
| 1 | **Strzelanina z klasą** | Responsywna, 8-kierunkowa, czytelna — czysta przyjemność run-and-gun |
| 2 | **Hałas to waluta, którą się wydaje** | Poziom Uwagi rośnie od strzałów, biegu i mikrofonu. **Przesterowanie (Q)** pozwala go celowo podnieść, żeby ściągnąć Stalkera z drużyny. Hałas to decyzja, nie zakaz — patrz §8.4 |
| 3 | **Co-op albo śmierć** | Down = dźwigasz kolegę. **Friendly fire = hałas**: pocisk kolegi przelatuje bez obrażeń, ale trafiony krzyczy (+4 Uwagi, odrzut) — żadna broń nie rani kolegi; obrażenia drużynie zadają tylko wybuchy (beczki). Szeptanie do mikrofonu to mechanika |
| 4 | **Groza przez dźwięk i światło** | Zero jump scare'ów-tanich. Grozę budują: ciemność, audio, stalker i cisza |
| 5 | **Krótkie misje, długi progres** | 8–15 min misje, meta-progresja na 20 h+, powtarzalne modyfikatory |
| 6 | **Gracze albo AI, nigdy pusto** | AI towarzysz od EA. Hot-join do botów w trakcie misji. Pusta drużyna = zepsuta sesja |
| 7 | **Czucie gry przed zawartością** | Skok, strzał i trafienie muszą być przyjemne *zanim* dodamy kolejną broń, wroga czy strefę. Standard: §23 (coyote time, jump buffer, hitstop, shake, rytm broni). Jedna dopracowana strefa > sześć bladych |

---

## 3. Setting i fabuła

**Miejsce:** ZSRR, okolice jeziora Bajkał, jesień 1987. Kompleks **Obiekt 86** — połączenie kopalni, wioski górniczej, laboratoriów biologicznych i reaktora. Oficjalnie: kopalnia uranu. W rzeczywistości: program badawczy nad organizmem z rdzenia meteorytu tunguskiego — **„Pierwszym Głosem"**.

**Incydent:** 14 dni przed akcją cała obsada Obiektu 86 przestała nadawać. Ostatnia transmisja to 40 sekund oddechu i czyjś głos mówiący do mikrofonu: *„Nie strzelajcie. On nie widzi. On słyszy."*

**Cel fabularny:** drużyna ma potwierdzić likwidację kompleksu (ładunki atomowe), ale odkrywa, że Pierwszy Głos nie jest organizmem — jest **anteną**, a cała okolica jego uchem.

**Struktura narracji:** 6 stref, narracja przez radio (nadająca wciąż obsada? ich głosy?), znajdźki (taśmy, listy robotników), dialogi NPC-ów uratowanych w misjach.

### Postacie grywalne (4)

| Postać | Rola | Unikalny gadżet | Charakter |
|--------|------|-----------------|-----------|
| **Borsuk** | Dowódca / wszechstronny | Radio taktyczne: 1× ping ujawniający wrogów | Weteran Afganistanu |
| **Igła** | Sanitariuszka / szybka | Strzykawka adrenaliny: revive na dystans | Cyniczna, opanowana |
| **Wulkan** | Granadier / tank | Tarcza balistyczna (stawiana, 8 s) | Głośny, dosłownie i w przenośni |
| **Sowa** | Snajperka / skradanie | Skaner ciszy: pokazuje promień słuchu wrogów | Mówi szeptem, także w intrukcji |

---

## 4. Pętla rozgrywki

### Pętla misji (8–15 min)
```
WEJŚCIE → ROZPOZNANIE → WYKONANIE CELU → ALARM/STALKER → EKSTRAKCJA
```
1. **Wejście** — ekwipunek, loadout (max 2 bronie + sidearm).
2. **Rozpoznanie** — semi-losowe pomieszczenia z tilesetów; przedmioty w 3–4 możliwych miejscach.
3. **Cel** — znajdź / uruchom / zniszcz / eskortuj / przetrzymaj.
4. **Napięcie** — hałas kumuluje się w Poziom Uwagi; po progu budzi się Stalker i następuje pętla pościgu.
5. **Ekstrakcja** — po wykonaniu celu pozycja wyjścia się zmienia; opcjonalne skrytki z łupem po drodze (ryzyko/nagroda).

### Pętla meta
```
Misja → złom + wroga wiedza + próbki → Ulepszenia broni / Perki / Bezpieczna Kryjówka → trudniejsze misje
```

### Zasady śmierci
- HP: 3 serca (Weteran), 1 trafienie (Koszmar).
- **Down** — gracz pada, **wykrwawia się 10 s** (licznik widoczny na HUD i nad postacią). Kolega staje obok i **trzyma E przez 4 s** (perk Krwioobieg: 2,5 s) — gracz wstaje z 2 serc. Bot też podnosi (z tym samym czasem — nie jest szybszy od człowieka).
- **Wykrwawienie** (10 s bez pomocy) = powrót w punkcie startu misji z 1 sercem. To kara dystansem i czasem, nie ekranem „game over".
- **Wipe** (wszyscy down jednocześnie) = **nieudana ekstrakcja**: po 3 s restart misji (Uwaga, wrogowie, ładunki Q), tracicie łup misji, ale nie postęp fabularny.
- **Dlaczego bez auto-respawnu:** darmowy respawn po 3 s zabija napięcie i sens Przesterowania. Down + revive tworzy momenty, o których drużyna opowiada po sesji.
- Uratowani NPC mogą zginąć na stałe (wpływ na zakończenie i sklep).

---

## 5. Sterowanie i ruch

| Akcja | Klawiatura | Pad |
|-------|------------|-----|
| Ruch / celowanie 8 kier. | WASD / strzałki | Lewy drążek (ruch) / prawy (aim) |
| Strzał | LPM / J | RT |
| Skok | Spacja | A |
| Kucanie (cisza) | Shift | L3 |
| **Przesterowanie** (§8.4) | Q | LB |
| Zmiana broni | 1 / 2 / 3, kółko myszy | D-pad ← / → |
| Granat | G | RB |
| Miecz/maczeta | F | X |
| Latarka | L | Y |
| Interakcja / dźwiganie | E | B |
| Ping (drużyna) | V | D-pad ↑ |
| Radio | R | D-pad ↓ |
| Mikrofon | push-to-talk / open | push-to-talk / open |

**Ruch:** bieg, sprint, kucanie (hałas 0), wspinaczka po drabinach, chwyt krawędzi, unik w bok (i-frames 0.2 s), spadanie z platform.

**Kluczowe:** gra jest single-plane (klasyczna Contra), ale z warstwami tła (przeciwnicy strzelający z drugiego planu) i sekcjami wewnętrznymi (budynki, sztolnie).

---

## 6. SYSTEM BRONI — pełna lista

### Zasady ogólne
- Gracz nosi **2 bronie główne** + **sidearm** (P-64, nieskończona amunicja) + **broń białą**.
- Bronie główne wypadają z pickupów w misji i są odblokowywane na stałe przez zakup w Kryjówce.
- Amunicja jest **współdzielona w drużynie** (jeden typ na broń) — ekonomia zespołowa.
- Każda broń ma 3 poziomy ulepszeń kupowane za złom.
- **Hałas** = promień w metrach, który wrzuca punkty do Poziomu Uwagi. Jest to pełnoprawny statystyk.

### 6.1 Bronie główne

| # | Broń | Typ | Dmg | RPM | Mag. | Zasięg | Hałas | Cechy |
|---|------|-----|-----|-----|------|--------|-------|-------|
| 1 | **M-83 „Krótki"** | SMG (start) | 8 | 600 | 30 | 12 m | 3 / 6 m | Wszechstronny, szybki reload |
| 2 | **SPREAD-12 „Rozrzut"** | Karabin rozrzutowy | 4×5 | 240 | 24 | 8 m | 3 / 7 m | Klasyk Contry, szeroki stożek, cięższy odrzut |
| 3 | **LR-7 „Promień"** | Laser ciągły | 12/tyk | — | Bateria 100 | 14 m | 2 / 4 m | Przebija 3 wrogów; cichy, ale świeci w ciemności (przyciąga wzrok wrogów) |
| 4 | **HKM-9 „Miotacz"** | Miotacz ognia | 15/s DoT | — | Paliwo 80 | 4 m | 1 / 3 m | Podpala teren; **UV +3 Uwagi** (światło); strach wśród Trzosków |
| 5 | **WRATH-4** | Granatnik | 80 AoE 3 m | 40 | 6 | 10 m | 4 / 18 m | Niszczy Gniazda i Żyły; friendly fire 100% |
| 6 | **FALCON-6** | Naprowadzane mikro-rakietki | 6 | 300 | 40 | 10 m | 3 / 7 m | Auto-namierzanie, słabe, dobre na Skoczków |
| 7 | **PELLET-8** | Strzelba | 7×8 | 75 | 8 | 6 m | 4 / 12 m | Odrzut wrogów, door-breacher |
| 8 | **SPECTER-1** | Railgun | 150 przebicie | 12 (charge 1,2 s) | 5 | 30 m | 5 / 25 m | Najgłośniejsza broń w grze — używasz jej, budzisz wszystko |
| 9 | **SINEW-6** | Harpun (kusza) | 45 | 60 | 1 (bełt do odzysku) | 15 m | **1 / 1 m** | **Jedyna cicha broń główna**; przybija Trzoski do ścian; bełty można odzyskać |

### 6.2 Sidearm
| Broń | Dmg | RPM | Ammo | Hałas | Uwagi |
|------|-----|-----|------|-------|-------|
| **P-64 „Igła"** | 10 | 300 | ∞ (rezerwa) | 2 / 4 m | Nigdy się nie kończy; ratunek w sytuacjach awaryjnych |

### 6.3 Broń biała
| Broń | Dmg | Szybkość | Hałas | Uwagi |
|------|-----|----------|-------|-------|
| **Maczeta** | 30 | szybka | 0 | Ciche zabójstwo od tyłu (instant), niszczy cienkie drzwi |
| **Kilof** | 55 | wolna | 1 / 2 m | Otwiera zamurowane przejścia, ogłusza elitki |

### 6.4 Ulepszenia broni (przykłady)

| Broń | Poziom II | Poziom III |
|------|-----------|------------|
| M-83 | +10 mag, szybszy reload | Tryb burst 3× (mniejszy hałas) |
| SPREAD-12 | +2 pestki | Podpala trafionych |
| LR-7 | Bateria 150 | Przebicie 6 wrogów |
| HKM-9 | Paliwo 120, wolniejsze zużycie | Ściany ognia (blokada przejścia) |
| WRATH-4 | Zapas 10 | Granaty kasetowe (3× AoE) |
| FALCON-6 | 60 rakiet | Rakiety rozdzielają się na 3 cele |
| PELLET-8 | Auto-ładowanie 2 pestek | Pociski ogłuszające (stun 1,5 s) |
| SPECTER-1 | Szybsze ładowanie | Przebija ściany (1 warstwa) |
| SINEW-6 | 2 bełty w magazynku | Bełty zatrute (DoT), linka do przyciągania |

### 6.5 Granaty i przedmioty zużywalne

| Przedmiot | Efekt | Hałas | Cena |
|-----------|-------|-------|------|
| **Granat odłamkowy** | 90 AoE 4 m | 4 | 100 zł |
| **Dymna** | Wizja 0 dla wrogów i graczy w chmurze | 2 | 80 zł |
| **Flara** | Światło 20 m / 60 s; Ślepce ją ignorują, Stalker na moment traci trop | 1 | 60 zł |
| **Fosforowa** | Obszar ognia 15 s, blokada przejścia | 3 | 150 zł |
| **Wabik (kostka dźwiękowa)** | Rzut: generuje hałas 4 w punkcie przez 5 s — **odciąga Stalkera i hordy** | 4 (w punkcie rzutu) | 120 zł |
| **Mina kierunkowa** | 120 dmg w stożku | 3 | 140 zł |
| **Ładunek wyburzeniowy** | Otwiera nowe przejście, zabija bossa-pomocniczo | 5 | 250 zł |

### 6.6 Narzędzia drużynowe

| Narzędzie | Efekt | Uwagi |
|-----------|-------|-------|
| **Latarka** | Stożek 8 m; bateria 3 min | Światło = +1 Uwagi co 10 s |
| **Skaner ruchu (Sowa)** | Ujawnia sylwetki przez ściany, 15 m | Emituje hałas 1/s — używaj krótko |
| **Apteczka** | +1 serce sojusznikowi | Czas użycia 5 s (ryzyko) |
| **Defibrylator** | Revive na dystans 10 m | 1 użycie na misję |
| **Klucz francuski** | Otwiera zamki, naprawia generatory | Postęp celu |
| **Taśma klejąca** | Podnosi prowizoryczne barykady | Gameplay obronny |


### 6.7 Stan implementacji w prototypie (1.6)

Pełna analiza i architektura: `prototype/WEAPONS.md`. W prototypie działa **12 pozycji**: M-83, SPREAD-12,
P-64, PELLET-8, LR-7, HKM-9, WRATH-4, FALCON-6, SPECTER-1, SINEW-6, maczeta, kilof (w HUD nazwy ASCII). Różnice
względem tabel powyżej — **wartości z kodu są nadrzędne** (`scripts/weapons.gd`, testy `--weapontest`):

- **Amunicja:** magazynki i przeładowanie (tryb taktyczny: z nabojem w komorze szybciej), **wspólny zapas drużyny**
  autorytatywny na serwerze; sidearm ∞. Wrogowie upuszczają amunicję tylko do broni, którą ktoś nosi; skrzynie
  z mapy zasilają wszystkie noszone bronie główne.
- **Hałas:** każda broń ma własny `heat_gain`/`heat_decay` (wcześniej wspólny decay sprawiał, że rozgrzewała się
  tylko strzelba). P-64 jest **cichsza** od M-83 (0,5→0,9 vs 0,6→1,5), zgodnie z tabelą §6.2.
- **Krytyk w głowę:** tylko cele wysokie (Wołek: górne 28% sylwetki; Trzosek nie ma słabego punktu). P-64 i SINEW ×2, M-83 ×1,5.
- **Maczeta** zabija natychmiast i po cichu wroga śpiącego **albo odwróconego plecami**.
- **HKM-9** podpala (8 HP/s), płonące Trzoski uciekają w panice. **WRATH-4** liczy się jako wabik (+15 Uwagi) i rani drużynę.
- Zasięgi to zasięg *lotu* pocisku; efektywny (bez spadku obrażeń) jest krótszy (M-83 12 m, SPREAD-12 2,5 m).
- Poza zakresem prototypu: ulepszenia 3-poziomowe, granaty/flary/miny (§6.5), zakup w Kryjówce, wyważanie drzwi.

---

## 7. WROGOWIE

### 7.1 Standardowe

| Wróg | HP | Szybkość | Zachowanie | Kontra |
|------|----|----------|------------|--------|
| **Trzosek** | 30 | szybka | Wataha 3–6, biegnie wprost | Ogień ciągły, maczeta |
| **Wołek** | 140 | wolna | Tankuje, potężny cios | Unik, strzelba w plecy |
| **Skoczek** | 40 | skok | Spada z sufitu/wysokości | Ciągły ogień w górę, FALCON |
| **Pijawka** | 15 | pełznie | Dopada, wysysa HP, QTE (30 s) | Maczeta, strzał w twarz kolegi? (friendly fire) |
| **Ślepiec** | 60 | węszy | **Nie widzi — słyszy.** Idzie do ostatniego hałasu | Kucnij i przejdź; harpun |
| **Podsłuchacz** | 35 | stoi | Nieruchomy „słuchacz" — krzyczy i ściąga hordę | Priorytet: zabić cicho (harpun) |
| **Mimik** | 70 | udaje | Udaje sylwetkę/radio kolegi z drużyny | Sprawdź pingiem/kodem drużyny |
| **Żyła** | 200 | rośnie | Splot 5–10 m, rodzi Trzoski | Ogień, WRATH-4, ładunek |

### 7.2 Elity

| Wróg | HP | Cechy |
|------|----|-------|
| **Kapłan** | 250 | Emituje falę krzyku (AoE 6 m, stun), leczy Trzosków. Zabij pierwszego |
| **Rzeźnik** | 600 | Miniboss stref; ładuje się przez ściany, niszczy barykady |
| **Żerca** | 300 | Zjada downed graczy — jeśli nie uratujesz w 20 s, postać ginie do końca misji |

### 7.3 Stalker — „ON" (On/To)

- **Nie da się go zabić.** HP ∞.
- Aktywuje się, gdy Poziom Uwagi misji przekroczy próg (start: 60/100).
- Porusza się poza kadrem (dźwięk z głośników 3D), atakuje znienacka.
- **Mechanika tropu:** idzie do ostatniego głośnego punktu. Wabik odciąga go na 20–30 s.
- **Światło go przyciąga** (latarka na wrogu = śmierć). Ciemność i kucanie = szansa ucieczki.
- Można go „uspokoić": obniżyć Uwagę poniżej progu przez 60 s (żadnych strzałów, wabik gdzieś daleko).
- Pojawia się w 3 formach zależnie od strefy (sylwetka, dźwięk, cień).

### 7.4 Bossowie

| # | Boss | Strefa | Mechanika |
|---|------|--------|-----------|
| 1 | **PIJAWKA** | I | Arena zalana wodą; pod wodą niewidoczna — flary ujawniają cień; 3 fazy, wciąga graczy pod wodę (QTE drużyny) |
| 2 | **KAPŁAN** | II | Fale krzyku niszczące światło; 4 totemy do zniszczenia; fazy ciszy, gdy boss „nasłuchuje" — nie wolno strzelać |
| 3 | **MATKA ŻYŁ** | III | Gigantyczny robak w grocie; segmenty z pancerzem, słabe punkty od spodu; sekwencja ucieczki kolejką górniczą |
| 4 | **BLIŹNIAK** | IV | Mimikuje losowego gracza (broń, sylwetka, linie głosowe); trzeba go zdemaskować (tells: brak cienia, brak oddechu), potem pokonać jego loadoutem |
| 5 | **KOLEKCJONER** | V | Wrzuca downed graczy do klatek na arenie; drużyna walczy i odbija ich mid-fight; kradnie broń i używa jej |
| 6 | **PIERWSZY GŁOS** | VI | Żywa antena. Faza 1: mówi głosami drużyny, gracze muszą zachować ciszę (mikrofon!). Faza 2: tarcza reaguje na dźwięk — trzeba **krzyczeć** do mikrofonu, żeby ją przeciążyć. Finał: cisza vs. krzyk |

---

## 8. SYSTEM GROZY — Hałas, Mikrofon, Ciemność

### 8.1 Poziom Uwagi (globalny licznik misji 0–100)
| Źródło | Punkty |
|--------|--------|
| Krok (bieg) | +0,5/s na gracza |
| Krok (chód / kucanie) | +0 (kucanie = 0) |
| Strzał z broni cichej (harpun, maczeta) | +1 |
| Strzał z P-64 | +1,0 → +1,6 (rozgrzanie) |
| Strzał z broni głównej | **zależny od rozgrzania lufy** — patrz „Model rozgrzania" niżej (SMG: +0,6 → +2,6 / strzał; strzelba: +3,5 → +5) |
| Granat/ładunek | +15 |
| Krzyk do mikrofonu (VAD > progu) | +20 (jednorazowo) |
| Głośnik alarmowy / dzwon | +30 |
| **Przesterowanie (Q, czynne)** | **+12 celowo** |
| Cisza (kucanie + chód, brak strzałów) | −4/s |
| Założony Wabik / Flara (odległy punkt) | −8 jednorazowo |

**Balans (obowiązujący numer, wszystko pochodzi z niego):**
- Świeża misja startuje na **20**. Średnia misja ma dawać 3–5 serii i ~6 s biegu → w środku misji jesteś w okolicach **45–55** (to nie jest wartość startowa).
- **60+:** Stalker budzi się i idzie do ostatniego hałasu. 80+: hordy podwójne, Ślepce agresywniejsze.
- Dekrement ciszy **−4/s** (nie −1) — bo w praktyce gracz spędza dużo czasu poza walką, i przy −1/s nigdy nie schodził z 60. Prototyp pokazał dokładnie ten błąd (§19 poz. 3).
- **Stalker NIE podnosi hałasu przy ataku.** Zamach z targetu jest za cichy, żeby go zasygnalizować — ostrzeżeniem jest sam ruch i audio. W przeciwnym razie śmierć jest samopodtrzymująca się: atak rodził hałas, który trzymał stalkera obudzonego, a gracz nie mógł uciec, bo stalker był szybszy od biegu (105 vs 95 px/s). Prototyp: 3 ataki pod rząd, bez możliwości wyjścia.
- Poziom nie resetuje się między misjami w obrębie strefy — kolejne misje startują z 25% poprzedniego.

**Model rozgrzania lufy (obowiązujący, zastępuje stałe +4/strzał):**
- Każda broń ma `n_min`, `n_max`, `heat_gain`. Rozgrzanie `h` (0–1) rośnie o `heat_gain` na strzał i spada o 1,2/s. Hałas strzału = `lerp(n_min, n_max, h)`.
- Efekt: **krótka seria (3–5 strzałów) jest tania** (~6 pkt), **ciągły ogień drogi** (~21 pkt/s → próg 60 po ok. 3 s). To zostawia Contrę — strzelanie seriami i wyjście z cienia — bez zamieniania każdego strzału w alarm.
- Wartości startowe (prototyp): M-83 `0,6 → 2,6`, gain `0,10`; P-64 `1,0 → 1,6`, gain `0,08`; SPREAD-12 `3,5 → 5,0`, gain `0,40`.
- Wszystkie wartości hałasu pochodzą z jednej tabeli (`weapons.gd` / `noise_manager.gd`) i są identyczne w trybie solo i sieciowym. Stare „połowienie w sieci" usunięte (to było obejście, nie balans).
- Bieg: **0,5 pkt/s** (dokładnie jak w tabeli). Trafienie gracza: +6 (krzyk bólu), niezależnie od trybu.

**Faza niepokoju (40–60): ostrzeżenie zanim zacznie się kara.**
- Poniżej 40: cisza. **40–59:** Stalker jeszcze śpi, ale słychać szept i HUD pokazuje „COŚ SŁUCHA". To okno na decyzję: przestań strzelać, użyj Wabika, kucnij.
- **60+:** Stalker się budzi (§8.5). Gracz zawsze dostaje ostrzeżenie, nigdy zaskoczenie.

**Start misji — jedna liczba:** misja zaczyna się od **20**. „45–55" to *typowy poziom w środku misji* (po kilku seriach i biegu), nie wartość startowa. Zasypianie: ≤30.

### 8.2 Mikrofon (Voice Activity Detection)
- Opcjonalny w menu (domyślnie ON w trybie co-op, z push-to-talk).
- **Krzyk** = Uwaga +20 i przyciągnięcie wrogów w promieniu 25 m. Wideo-reakcje = marketing.
- **Szept** (niski wolumen) — działa jak interkom, nie generuje hałasu.
- **Ślepcy** w misji 4.2 reagują na mikrofon gracza, nie tylko postać.
- **PIERWSZY GŁOS** używa mikrofonu jako mechaniki finałowej.
- Dostępność: **finał nie może zależeć od mikrofonu.** Krzyk w bossie 6 działa też przyciskiem „Krzyk" (V) bez VAD — patrz §14, bo wymaganie mikrofonu blokuje streamerów bez mikrofonu i dzieci.
- Ochrona strumieniowców: automatyczna cenzura wulgaryzmów w VAD (opcja), brak zapisu audio (przetwarzane lokalnie, nie wysyłane).

### 8.3 Ciemność
- Widoczność bazowa: 6 m. Latarka: 8 m. Flara: 12 m.
- Światło przyciąga wzrok Trzosków i Stalkera.
- Tilesety mają „dark zones” — pokoje, gdzie bez światła nie widzisz podłogowych pułapek.
- CRT/scanline filter opcjonalny; głębia tła sterowana warstwami parallax.
- **W prototypie (1.3.5):** skala 16 px = 1 m. `CanvasModulate` przyciemnia świat (`Lights.AMBIENT`, strojone pomiarem luminancji ekranu: bez latarki przy graczu ~0,056, 6–9 m dalej ~0,007 — wcześniej tło było prawie tak jasne jak krąg gracza); każdy gracz ma aurę 6 m, latarka (L) to stożek 8 m (±24°) z baterią 180 s, kosztem +1 Uwagi co 10 s świecenia i budzeniem wrogów, na których padnie snop (z linią widzenia). Snop na Stalkerze ściąga go na świecącego (§7.3) i odsłania sylwetkę. Flara ekstrakcji = zielone światło 12 m, gniazda słabo się żarzą, strzał daje rozbłysk 4 m. Kafle rzucają cienie (okluder cofnięty o 4 px na odsłoniętych bokach — wierzch i lica łapią światło). Oczy wrogów, etykiety i paski są „unshaded" — widać je w ciemności. **Do playtestu:** bateria odnawia się 0,25 s/s przy zgaszonej latarce (GDD nie przewiduje ładowania — bez tego misja po 3 min byłaby czarna).

### 8.4 PRZESTEROWANIE — hałas jako zasób (nie zakaz)

Sedno poprawki. Problem: pierwotna wersja traktowała hałas jako coś, czego się unika, co oznacza **permanentne zakazanie run-and-gunu** — gatunku, dla którego gracz kupił grę. Rozwiązanie: hałas staje się **walutą do wydawania**, a nie zakazem.

**Mechanika:** przycisk **Q** (przesterowanie). Daje **+12 Uwagi celowo** i jednorazowo „przesterowuje" **ostatnie źródło hałasu** — Stalker rusza w stronę miejsca, gdzie użyto Q, zamiast miejsca ostatniego strzału. Koszt: zużycie ładunku.

- **Ładunek przesterowania:** misja startuje z 2. Regeneracja: +1 co 45 s (albo natychmiast przy wykonaniu celu głównego). Max 3.
- **Efekt taktyczny:** jeśli Stalker właśnie poluje na kolegę, gracz używa Q *daleko od niego* i Stalker przekierowuje się na gracza-innego-człowieka (albo na podstawiony Wabik). Drużyna zyskuje 20 s.
- **Dlaczego to jest hook, a nie nerf:** aktywne „przesterowanie" brzmi jak coś, co *ty* robisz celowo — sygnał dla streamera „spróbujcie tego", zamiast statystyki, której się unika.

**Napięcie gatunków rozstrzygnięte w ten sposób:** w trybie **szumu** (walka) hałas jest nieunikniony i Stalker ciśnie — tu grasz jak w Contra. W trybie **napięcia** (cele, skradanie) cisza jest możliwa i oszczędzasz ładunek Q. Misje przełączają te tryby jawnie, żeby gracz wiedział, w którym jest. Bez tego GDD opisywał dwa różne produkty.

### 8.5 Stalker — pozycje i celowość (reguła dla AI, nie tylko opis)
- **Stalker NIE biega szybciej od gracza.** 88 px/s vs gracz 95 px/s — gracze da się wyprzedzić, ale trzeba biec w linii prostej, co rzadko możliwe w labiryncie. To zostawia szansę na ucieczkę.
- **Stalker kieruje się źródłem hałasu, nie pozycją gracza.** Nie ma „trybu szukania"; idzie tam, gdzie ostatnio było głośno.
- **W fazie napięcia (niski hałas) jest powolny (55 px/s)** i omija graczy — groźba bez ataku. W fazie szumu jest szybki i agresywny.
- **Nasłuchiwanie (v2):** po dotarciu do źródła hałasu Stalker **zatrzymuje się i nasłuchuje 4 s**. Idzie dalej tylko do *nowego* hałasu. Nigdy nie przełącza się na pozycję gracza — to oddaje ciszy realną wartość (wcześniej kod po dotarciu do punktu celował w najbliższego gracza, co robiło z niego zwykłego goniącego wroga).
- **Kucający gracz jest niemal niewidoczny:** Stalker zauważa go dopiero z **8 px** (stojącego z 14 px). Kucanie obok przechodzącego Stalkera to świadoma, nagradzana decyzja.
- **Widoczność — „słyszysz, nigdy nie widzisz":** ciało pojawia się dopiero w promieniu ~60 px od lokalnego gracza (płynnie do 160 px), poza tym widać tylko słabo błyszczące oczy. Gdy dojdzie oświetlenie 2D, widoczny jest w świetle latarki/flary.
- **Atak z zapowiedzią (v2):** zamach 1 HP, cooldown 1,5 s, **bez generowania hałasu**. Przed ciosem jest **0,55 s zapowiedzi** (szept milknie, oczy rozbłyskują, ryk) — gracz może uciec; jeśli odejdzie poza zasięg, cios chybia. Po ciosie Stalker cofa się 6 m — okno na decyzję, nie natychmiastowy kolejny cios. Zasada: **śmierć od Stalkera jest zawsze „fair" i zapowiedziana.**
- **Poruszanie się:** idzie po powierzchniach poziomu ścieżką A* (`nav.gd`, 1.3.7) — chodzi, wspina się na wyższe poziomy i zeskakuje, nie przenika przez ściany. Ten sam graf prowadzi bota.

---

## 9. KAMPANIA — pełna lista misji

### STREFA I: BÓR CIEMNY (Dark Pinery) — „Zaginiony patrol"
Las, posterunek, tartak. Kolory: mgła, brąz, zieleń. Wprowadza: strzelanie, skok, latarkę.

| # | Misja | Cel główny | Cel poboczny | Nowa mechanika | Wrogowie | Czas |
|---|-------|------------|--------------|----------------|----------|------|
| 1.1 | **Zaginiony Patrol** | Znajdź 3 nieśmiertelniki | 2 skrytki ze złomem | Ruch, strzał, latarka. **Tutorial ciszy:** kucz i chodź — pasek Uwagi spada | Trzoski, Wołki | 8 min |
| 1.2 | **Przerwa w Nadawaniu** | Uruchom 3 generatory radiostacji | Nie przekrocz 40 Uwagi | Poziom Uwagi, Podsłuchacze. **Tutorial Przesterowania:** użyj Q, żeby odciągnąć stalkera od koledów | Trzoski, Podsłuchacze, Stalker (skrypt) | 10 min |
| 1.3 | **Gniazdo** | Spal 3 gniazda | Uratuj zwiadowcę (NPC) + **zabij stalkera w ciszy**: obniż Uwagę <30, gdy celuje w NPC | **Pierwsze pejne starcie ze stalkerem** (bez skryptu). AI towarzysz ćwiczy dźwiganie | Trzoski, Żyła, Stalker | 12 min |
| **B1** | **PIJAWKA** | Zabij bossa | — | Flary ujawniają cień pod wodą | Pijawka, Trzoski | 6 min |

**Stan w prototypie (1.7.24):** zaimplementowane są **1.2 „Przerwa w Nadawaniu"** (w v2 — 1.7.25 — **4 generatory** na mapie 288×44, skok Uwagi po ostatnim, lekcja Q na Stalkerze, cel poboczny „Uwaga < 40") i **1.3 „Gniazdo"** (gniazda + Żyła zamiast Pijawki). Kampania gra je po kolei (1.2 → kryjówka → 1.3 → kryjówka → od początku); w 1.2 powrót to **ucieczka drezyną** (1.7.26); brakuje 1.1 „Zaginiony Patrol" i bossa Pijawki.

**Nagroda strefy:** odblokowanie sklepu broni (SPREAD-12, PELLET-8), postać Igła.

---

### STREFA II: MARTWA WIEŚ (Dead Village) — „Nie budź wioski"
Niszczejąca wioska górnicza, cerkiew, piwnice. Nowy wróg: Ślepcy (słuch), Mimiki.

| # | Misja | Cel główny | Cel poboczny | Nowa mechanika | Wrogowie | Czas |
|---|-------|------------|--------------|----------------|----------|------|
| 2.1 | **Cisza** | Przeprowadź drużynę przez wioskę bez alarmu | „Duch" — zero wykrycia | Szept, przejście obok Ślepców | Ślepcy, Trzoski | 10 min |
| 2.2 | **Piwnice** | Uratuj 4 ocalałych z piwnic | Znajdź pamiętnik górnika | Dźwiganie rannych NPC; pierwszy Mimik udaje ocalałego | Mimiki, Pijawki, Wołki | 12 min |
| 2.3 | **Dzwon** | Ochroniaj dzwonnicy, potem uciekaj | Zniszcz 2 gniazda | Dzwon budzi hordę; obrona 3 fali | Horda, Kapłan (elita), Stalker | 12 min |
| **B2** | **KAPŁAN** | Zniszcz 4 totemy i zabij bossa | — | Fazy ciszy: nie wolno strzelać | Kapłan, Trzoski | 7 min |

**Nagroda strefy:** SINEW-6 (harpun), FALCON-6, postać Wulkan.

---

### STREFA III: KOPALNIA KOŚCI (Bone Mine) — „Zjazd w ciemność"
Sztolnie, windy, podziemne jezioro. Zarządzanie światłem i bateriami.

| # | Misja | Cel główny | Cel poboczny | Nowa mechanika | Wrogowie | Czas |
|---|-------|------------|--------------|----------------|----------|------|
| 3.1 | **Zjazd** | Przetrwaj 3 fale na opadającej windzie | Bez utraty apteczki zespołowej | Arena obronna w ruchu | Trzoski, Skoczkowie, Rzeźnik | 10 min |
| 3.2 | **Ciemność** | Znajdź 3 bezpieczniki | Odnajdź zaginionych górników | Zarządzanie baterią: ładowarki co 90 s | Ślepcy, Skoczkowie | 12 min |
| 3.3 | **Żyły** | Zniszcz sieć żył (5 węzłów) | Przejedź kolejką bez śmierci | Sekcja kolejki: strzelanie w ruchu | Żyły, Trzoski, Wołki | 12 min |
| **B3** | **MATKA ŻYŁ** | Przetrwaj pościg i zabij bossa | — | Fazy z pancerzem segmentów; ucieczka kolejką | Matka Żył | 8 min |

**Nagroda strefy:** HKM-9 (miotacz), WRATH-4 (granatnik), postać Sowa.

---

### STREFA IV: OBIEKT 86 (Facility 86) — „Kwarantanna"
Laboratoria, kwatery, serwerownia. Automatyczne turret-y z czasów ZSRR. Mimiki w pełnej krasie.

| # | Misja | Cel główny | Cel poboczny | Nowa mechanika | Wrogowie | Czas |
|---|-------|------------|--------------|----------------|----------|------|
| 4.1 | **Kwarantanna** | Uratuj naukowca z bloku B | Wyłącz 3 turret-y | Turret-y: skradanie lub EMP (ładunek) | Turret-y, Trzoski, Wołki | 12 min |
| 4.2 | **Eksperyment 9** | Pobierz 3 próbki z kwarantanny | Nie zabij ani jednego Ślepca | Jeden gracz **zarażony** — musi dotrzeć do medbay w 5 min (efekt: miga na radarze) | Ślepcy, Mimiki | 13 min |
| 4.3 | **Wyciek** | Uciekaj w 6 min, zanim strefa zostanie odcięta | Uratuj 2 techników | Zamknięte drzwi, mapy ucieczki, Bliźniak za plecami | Bliźniak (skrypt), Trzoski | 8 min |
| **B4** | **BLIŹNIAK** | Zdemaskuj i zabij bossa | — | Boss kopiuje loadout gracza | Bliźniak | 7 min |

**Nagroda strefy:** SPECTER-1 (railgun), ulepszenia pancerza, finałowa zbroja dla drużyny.

---

### STREFA V: SARKOFAG (Reactor Sarcophagus) — „Rdzeń słyszy"
Reaktor, strefy radiacji, rdzeń. Sekcje zero-hałasu — broń palna = śmierć.

| # | Misja | Cel główny | Cel poboczny | Nowa mechanika | Wrogowie | Czas |
|---|-------|------------|--------------|----------------|----------|------|
| 5.1 | **Sarkofag** | Włóż 3 pręty paliwowe w wyznaczone miejsca | Zbierz 5 taśm audio | Strefy radiacji: licznik Geigera, skafandry (HP spada w skażeniu) | Wołki, Żyły, Pijawki | 12 min |
| 5.2 | **Rdzeń** | Wyłącz reaktor (3 panele) | Zero strzałów (osiągnięcie) | **Sekcja ciszy:** każdy strzał = natychmiastowa horda; tylko harpun/maczeta/wabik | Ślepcy, Rzeźnik | 10 min |
| 5.3 | **Zejście** | Zejdź do gardzieli (platformy) | Bez śmierci | Platforming, spadające fragmenty | Skoczkowie, Trzoski | 10 min |
| **B5** | **KOLEKCJONER** | Zabij bossa i odbij pojmanych | Uwolnij wszystkich w 1. próbie | Boss porywa downed graczy do klatek | Kolekcjoner, Trzoski | 8 min |

**Nagroda strefy:** wszystkie ulepszenia poziomu III, finałowa scena fabularna.

---

### STREFA VI: MARTWA CISZA (Dead Air) — „Pierwszy Głos"
Inny wymiar: organiczne korytarze, grawitacja się zmienia, radio mówi głosami drużyny. Finał.

| # | Misja | Cel główny | Cel poboczny | Nowa mechanika | Wrogowie | Czas |
|---|-------|------------|--------------|----------------|----------|------|
| 6.1 | **Membrana** | Przejdź przez membranę (3 sekcje) | Znajdź 3 wspomnienia (taśmy) | Grawitacja: chodzenie po sufitach; organiczne ściany | Mimiki, Trzoski | 12 min |
| 6.2 | **Głosy** | Odnajdź prawdziwe wyjście | Nie daj się zwieść ani raz | Radio podaje **fałszywe cele**; kod drużyny (hasło z 4 słów) odróżnia prawdę | Mimiki, Kapłan | 12 min |
| 6.3 | **Martwa Cisza** | Dotrzyj do Pierwszego Głosu | Przetrwaj z 3 nabojami zapasu | Finałowy gauntlet: wszyscy wrogowie, mało amunicji | Wszyscy | 15 min |
| **B6** | **PIERWSZY GŁOS** | Zniszcz antenę | — | Faza ciszy (mikrofon!) i faza krzyku (przeciążenie) | Pierwszy Głos | 10 min |

**Nagroda:** zakończenie zależne od uratowanych NPC i zebranych taśm (3 warianty: „Likwidacja", „Powrót", „Dead Air").

---

## 10. Progresja

### 10.1 Waluty
| Waluta | Źródło | Wydatki |
|--------|--------|---------|
| **Złom** | Skrytki, sprzedaż próbek | Bronie, ulepszenia, granaty, perki |
| **Wroga wiedza** (XP) | Zabójstwa, cele, pierwsze ukończenie | Poziomy gracza → sloty perków |
| **Próbki** | Cele poboczne, elitki | Odblokowanie stref, badania w Kryjówce |
| **Taśmy** | Ukryte znajdźki | Fabuła, zakończenia, tapety koncept-artów |

### 10.2 Perki (przykłady, 2 sloty na postać)
| Perk | Efekt |
|------|-------|
| Ciche kroki | Bieg generuje hałas 0,25/s zamiast 0,5/s |
| Szerokie ramię | Rzut granatem +30% zasięgu |
| Druga szansa | Raz na misję wstajesz sam z down (30 s cooldown ekstra na misję) |
| Krwioobieg | Szybsze dźwiganie rannego (4 s → 2,5 s) |
| Zimna krew | Twój krzyk do mikrofonu = tylko +10 Uwagi |
| Kowal | −20% kosztu ulepszeń broni |
| Skaut | Skaner pokazuje Stalkera w promieniu 10 m |
| Weteran | +1 serce |

### 10.3 Kryjówka (hub)
- **Warsztat** — bronie i ulepszenia.
- **Szpital** — stan uratowanych NPC, bonusy fabularne (np. uratowany naukowiec daje schemat EMP).
- **Radiostacja** — wywiad: prognoza pogody (modyfikatory misji), tygodniowe wyzwania.
- **Ściana pamięci** — statystyki drużyny, osiągnięcia.
- **Tablica misji** — kampania + tryby dodatkowe.

---

## 11. Tryby gry

| Tryb | Opis | Uwięzienie |
|------|------|------------|
| **Kampania** | 18 misji + 6 bossów, 15–20 h | Postęp fabularny |
| **Nocny Dyżur** (endless) | 5 losowych misji pod rząd, wipe kończy serię. **W prototypie od 1.7.23** (HP +12%/misję, modyfikatory), ranking tylko lokalny | Cotygodniowy ranking |
| **Koszmar Tygodnia** | Misja + 3 losowe modyfikatory (np. blackout, podwójne hordy, alway-on Stalker) | Skiny, złom ×3 |
| **Strzelnica** | Test broni, tutorial | — |

### Modyfikatory (losowane / tygodniowe)
Cisza radiowa (brak minimapy), Przeciążenie (Uwaga 50 start), Głód amunicji (−50% amunicji), Oczy w ciemności (wrogowie widzą w ciemności), Wyciek (Stalker zawsze aktywny), Podwójna horda, Delikatni (1 HP), Bunt maszyn (turret-y w każdej strefie).

---

## 12. Multiplayer i architektura

- **Host-authoritative**, 1–4 graczy, Steam P2P + relay (fallback).
- Tickrate 20 Hz; predykcja ruchu po stronie klienta; server-authoritative hit detection z lag compensation 150 ms.
- **Reconnect:** okno 2 min, postać czeka jako „down" w miejscu rozłączenia.
- **Voice:** Steam Voice API (proximity + push-to-talk), VAD lokalnie (bez wysyłania audio na serwer gry).
- **Drop-in/drop-out** między misjami; lobby hosta z ustawieniami (modyfikatory, trudność, VAD).
- Late-join: tylko między misjami (spójność fabularna).
- **AI towarzysz wypełnia puste sloty od EA** (§16.3) — nie dopiero w 1.0. Bez tego „tryb solo" nie istnieje.

---

## 13. Kierunek artystyczny i audio

### Grafika
- Pixel art 16-bit, render 320×180 skalowany ×4–6 (opcja pixel-perfect).
- Paleta: 48 kolorów bazowych + warstwa świateł (Godot 2D Lights), CRT/scanline opcjonalnie.
- Animacje 12 fps feel, reakcje trafień (hitstop 50–90 ms przy zabójstwie, wartości w §23), duży gore (pixel, stylizowany, bez foto-realizmu).
- Tła: 3 warstwy parallax; strefy mają własne palety (Bór: brąz/zieleń; Obiekt 86: stal/cyjan; Marwa Cisza: czerń/magenta).

### Audio (filar!)
- Muzyka adaptacyjna: warstwy (cisza / napięcie / walka / pościg) przełączane płynnie.
- Brzmienie: analogowe syntezatory lat 80. (DX7, taśma, szum) + industrialne uderzenia.
- **Propagacja dźwięku przez ściany** — kroki i strzały są filtrowane (muffled) zależnie od geometrii; kluczowe dla horroru.
- Dźwięk 3D dla Stalkera (zawsze słyszysz, nigdy nie widzisz).
- Lektor: tylko radio (nadające głosy), brak pełnego dubbingu.

---

## 14. UI/UX i dostępność

- HUD minimalny: serca, amunicja (liczba), wskaźnik Uwagi (ikona oka/heartbeat), status drużyny (ikony), licznik baterii.
- Brak minimapy — tylko kompas ekstrakcji po wykonaniu celu.
- Ping system (jak w Apex): oznaczaj wroga/przedmiot/drogę.
- **Ustawienia dostępności:** VAD ON/OFF, „Krzyk" na przycisk, napisy z opisem dźwięków ([kroki za tobą]), mono audio, redukcja screen shake, tryb dla daltonistów (3 presety + kształty), skalowanie czcionek, pełne remapowanie klawiszy, tryb streamera (cenzura, brak muzyki licencjonowanej).

---

## 15. Monetyzacja i platformy

| Platforma | Kiedy | Uwagi |
|-----------|-------|-------|
| **Steam (EA)** | Premiera EA | **Jedyna premiera.** Wszystkie decyzje o iteracji i szybkim feedbackzie są ważniejsze niż 12% prowizji |
| **GOG** | Po 1.0 | Retro + DRM-free = naturalna publiczność; soundtrack i PDF artbook. Realistycznie: dodatkowe 2–5% sprzedaży, nie główny kanał |
| **Epic** | **Odroczone do ≥25k sprzedanych** | Nie bierzemy First Run (6 mies. ekskluzywności) — zamraża naszą ścieżkę iteracji w Early Access, gdzie potrzebujemy szybkiego feedbacku. Jeśli kiedyś: wariant bez ekskluzywności, tylko 100% z 1. mln $ rocznie |
| **Konsole** | Nieplanowane | Tylko po 1.0 i sprzedaży >100k. To zadanie na 6+ mies. pracy — nie na tę fazę |

- Model: premium, **zero MTX**.
- DLC po 1.0: kosmetyki (skiny oddziału, retro filtry), soundtrack, artbook. Nigdy nie dzielimy map ani broni.
- Demo: Strefa I (bez zapisu postępu) — konwersja na wishlistę.

---

## 16. Zakres MVP, budżet, roadmapa

### 16.0 Strategia zakresu — demo najpierw (v1.3)
Budżet z §16.4 (10–16 mies. do EA) jest ryzykiem, dopóki nie wiemy, że rdzeń bawi. Dlatego kolejność jest odwrócona:
1. **Pionowy wycinek = jedna misja w całości** (ręcznie zbudowana mapa, cel, ekstrakcja, 1 boss), 2 bronie, 2 wrogowie + Stalker. To jest **demo na Steam** i materiał do pierwszych playtestów ze znajomymi.
2. **Playtest „kiedy się nudziłeś, a kiedy się bałeś"** (3–5 osób, nagrany gameplay) — przed jakąkolwiek nową zawartością. Wyniki decydują o priorytetach (§23).
3. **Dopiero potem** pozostałe misje Strefy I, losowe pokoje i EA. Losowość pokoi odkładamy, dopóki pętla na jednej mapie nie jest przyjemna po 20 powtórkach.
4. **Progresja w EA — wersja minimalna:** jedna waluta (złom), 3 bronie do kupienia, 2–3 perki, bez Kryjówki-huba i bez Taśm/Próbek. Pełna tabela §10 to cel 1.0, nie EA.
5. **Nawigacja:** pełne A* dla Stalkera i botów po zbudowaniu poziomu na tilemapie (do tego czasu: ruch po powierzchniach, patrz §8.5).

### 16.1 MVP — co musi działać w premierze EA
- [ ] Online 1–4 (Steam P2P) + **AI towarzysz wypełniający puste sloty** (nie opcjonalne — patrz 16.3)
- [ ] Strefa I kompletna (3 misje + boss) jako „vertical slice" nośny — **2 z 3 misji w prototypie (1.2, 1.3; 1.7.24)**, brak 1.1 i bossa Pijawki
- [ ] 3 bronie główne, sidearm, maczeta, Wabik (funkcjonalny od EA — to infrastruktura Przesterowania)
- [ ] 4 typy wrogów + Stalker w wersji z §8.1/§8.5 (mniej, ale poprawnie zbalansowanych)
- [ ] System Uwagi, Przesterowanie (Q), ładunek i regeneracja, system światła
- [ ] Serwerowe pociski z lag compensation (nie per-peer symulacja — patrz 18.2)
- [x] Tryb Nocny Dyżur v1 (1.7.23; bez rankingu online)
- [ ] Demo

### 16.2 Czego świadomie NIE ma w EA
Strefy II–VI, większość broni, Bliźniak/Kolekcjoner, Wyzwania tygodniowe, mod support, konsola. To świadome odcięcie — patrz 16.5.

### 16.3 AI towarzysz — dlaczego nie może być „opcjonalne w 1.0"
Multiplayer jest najsilniejszym czynnikiem sukcesu w tej niszy (10x hit rate vs singleplayer), ale zakłada, że **gracz ma kogo zaprosić**. Realnie to połowa dostępnej publiczności: nie każdy ma znajomego w grze, a multiplayer o 3 w nocy jest pusty. Hot-join do botów musi działać bez gadżetu sieciowego (Peer-to-peer LAN feel) — inaczej „gra co-op" staje się „gra, w której potrzebujesz znajomego".

AI towarzysz w EA: podąża, strzela, dźwiga, reaguje na stalkera. To 2–4 mies. pracy i ratuje całą bazę graczy solo.

### 16.4 Realny budżet i czas (liczby z researchu zestawione z kosztem)
Dane rynkowe: mediana przychodu gry na Steam ~$250–300; mediana kosztu developmentu indie ~$30–60k. To znaczy, że **mediana projektu nie zwraca kosztu** — potrzebujemy albo lepszej realizacji, albo akceptujemy, że to portfolio +uczenie. Budżetujemy to świadomie.

| Pozycja | Godziny (solo+1 pomocnik) | Uwagi |
|---|---|---|
| Netcode + synchronizacja serwerowa (16.1) | 200–300 | Największe ryzyko techniczne; zrobić w pierwszej kolejności |
| AI towarzysz (16.3) | 150–250 | Zależne od istniejącego AI stalkera |
| Strefa I (3 misje + boss) + tilesety | 250–400 | Audio jako filar grozy — nie zaniedbywać |
| Broń + pociski + pociski serwerowe | 120–200 | 3 bronie, nie 9 |
| System Uwagi + Przesterowanie | 60–100 | Prototyp już ma serwerowy rdzeń |
| UI/HUD, Kryjówka, Endless | 120–180 | |
| Marketing / wishlisty / demo / VOD | 80–150 | Równolegle, nie na końcu |
| **RAZEM do EA (Strefa I)** | **~1000–1600 h** | Przy ~25 h/tydz. na osobę: **~10–16 mies. pracy własnej**; przy 2 osobach ~6–10 mies. |
| Pełna kampania (Strefy II–VI) | +2500–4000 h | Dopiero po przejściu gate'u w 16.5 |

To jest realistyczne. Przy pracy **jednej osoby** ~25 h/tydz. daje to **~10–16 mies. do EA (Strefa I)** i **18–30 mies. do 1.0**; przy dwóch osobach dzielących sie realnie ~35 h/tydz. łącznie miesiące kalendarzowe skracają się, ale nie liniowo (netcode i audio nie dzielą się czysto). Pierwotna wersja GDD mówiła „9–14 miesięcy do EA z 3 strefami i 4-osobowym netcodem" — to było zaniżone i pomijało AI towarzysza, serwerowe pociski i audio.

### 16.5 Kill criteria (bramki „kontynuujemy / kasujemy")
- **Gate 0 (przed EA):** 20 zamkniętych playtestów, ≥60% graczy dociera do Stalkera bez pomocy, średni czas do bossa 6–12 min, zero crashów sesji 4-osobowej przez 10 kolejnych sesji. Jeśli nie → popraw, nie wydawaj na Strefę II.
- **Gate 1 (po premierze EA, 90 dni):** ≥8k sprzedanych, ≥75% pozytywnych recenzji, konwersja wishlist→kupno ≥25%. Poniżej → nie idziemy do Strefy II–VI; albo mała poprawka i próba 2, albo zamknięcie.
- **Gate 2 (przed 1.0):** 25k sprzedanych łącznie. Poniżej → 1.0 jako „ Early Access forever", porty konsolowe odpadają.
Twarde progi, żeby nie palić miesięcy pracy na „a może się uda".

### 16.6 Roadmapa (post gate)
| Etap | Warunek | Zawartość |
|------|------|-----------|
| **EA launch** | Gate 0 | Strefa I, Endless, AI towarzysz |
| Update 1 | Gate 1 ✓ | Strefa II + Przesterowanie loadouty + Koszmar Tygodnia |
| Update 2 | sprzedaż ≥12k | Strefa III + drugi typ stalkera |
| Update 3 | sprzedaż ≥20k | Strefy IV–VI + finał + 3 zakończenia |
| **1.0** | Gate 2 ✓ | Balans, mod support (rozważ), GOG |

Roadmapa jest warunkowa, nie kalendarzowa. Nie ma sensu planować Strefy IV przed Gate 1.

---

## 17. KPI i marketing

| Metryka | Cel |
|---------|-----|
| Wishlisty przed EA | 10 000–15 000 |
| Konwersja wishlist → zakup (1. mies.) | ≥25% |
| Oceny Steam | ≥75% pozytywnych (próg danych rynkowych; cel operacyjny ≥80%) |
| Sprzedaż EA (3 mies.) | 8 000–15 000 kopii (Gate 1) |
| Refundy | <8% |
| CCU szczyt (1. mies.) | 1 500–2 500 |

### 17.3 Cena $9.99 — dlaczego nisko (korekta wobec pierwotnej wersji)
Pierwotny GDD ustawiał $12.99 na podstawie „$10–20 daje 1,9x lift". To było **sprzeczne z danymi o mechanice sukcesu w tej niszy**. Hity, do których się odwołujemy (*Lethal Company*, *R.E.P.O.*), kosztują $9.99. W grze, którą kupuje cała ekipa (4 kopie = 4x ruch), **niska cena jest mechaniką wiralową, nie ustawieniem marży**: obniża koszt wejścia do „wyślij znajomym". $12.99 pomija główny czynnik, który wyjaśnia sukces tych tytułów. Utrzymujemy $9.99 do 1.0; DLC kosmetyczne, nigdy mapa/warunki.

### Plan marketingowy
1. **Steam page od dnia 1** (devlogi, GIFy) — cel: 3k wishlist przed gameplay reveal.
2. **Klipy „scream moments"** — TikTok/Shorts/Reels; hasło: „gra, która słyszy twój krzyk".
3. **Klucze dla streamerów horror co-op** (największa dźwignia) — dzień premiery EA.
4. **Demo na Steam Next Fest** — 2 festiwale przed EA.
5. **Discord + playtesty** — zamknięte bety co 2 miesiące (zbieranie feedbacku o VAD).
6. **Press kit** — polski i angielski; festiwale (Pixel Heaven, Game Arena).

---

## 18. Ryzyka i mitygacje

| Ryzyko | Prawd. | Wpływ | Mitygacja |
|--------|--------|-------|-----------|
| Netcode 4 graczy opóźnia produkcję | wysoka | wysoki | Pion z 2 graczami w 1. mies.; serwerowe pociski + lag compensation przed wszystkim (18.2); AI towarzysz jako bufor |
| **Cisza nie da się utrzymać → pętla horror nie do przejścia** | **wystąpiła w prototypie** | **wysoki** | **Naprawione w GDD §8.1/§8.5: spadek −4/s, Stalker wolniejszy (88/55 vs 95), atak nie generuje hałasu, cofnięcie po ciosie. Weryfikacja w playteście: gracz musi umieć „uśpić" stalkera w <20 s** |
| VAD działa źle na tanich mikrofonach | średnia | wysoki | Progi kalibracyjne + tryb bez VAD + finał na przycisku (8.2) + testy na 20 konfiguracjach |
| Finał wymaga mikrofonu → blokuje streamery i dzieci | średnia | średni | Krzyk = przycisk V równolegle z VAD (8.2) |
| Multiplayer bez znajomych = pusta baza | wysoka | wysoki | AI towarzysz od EA, hot-join do botów (16.3) |
| Groza nie działa w 2D | średnia | wysoki | Inwestycja w audio + dźwięk przestrzenny; testy „na słuchawkach" co sprint |
| Klon po sukcesie | średnia | średni | Szybkie wejście w EA, społeczność, Przesterowanie jako rozróżnialna mechanika |
| Przesycenie co-op horroru | średnia | średni | Hook: retro side-scroll + mikrofon + aktywne Przesterowanie; cena $9.99 |
| Stalker irytuje zamiast straszyć | średnia | średni | Reguły z 8.5 (dwie prędkości, cofnięcie po ciosie), okna oddechu, playtesty |
| Zasięg EA zbyt duży, Gate 1 nieosiągalny | średnia | wysoki | Warunkowa roadmapa (16.6); Strefa I jako jedyny nośnik EA |

---

## 19. Znane ograniczenia prototypu (do naprawy przed playtestem z drugą osobą)

Prototyp w `dead-air-87/prototype/` jest vertical slice'em, nie grą. Poniższe ograniczenia są **udokumentowanymi błędami**, nie opcjonalnymi upgrade'ami — każdy z nich psuje rdzeń doświadczenia i musi zniknąć przed pierwszym zewnętrznym playtestem:

| # | Problem | Gdzie | Skutek | Priorytet |
|---|---------|-------|--------|-----------|
| 1 | Pociski symulowane per-peer; obrażenia tylko od kopii strzelca | `bullet.gd` | Pocisk przechodzi przez wroga na jednym ekranie, trafia na drugim — widał desync | **P0 — naprawione**: serwerowe pociski |
| 2 | Ręczne RPC 20 Hz, bez bufora interpolacji/predykcji | `player.gd` `_sync_state` | Zdalny gracz szarpie się przy jitterze | **P0 — naprawione**: `MultiplayerSynchronizer` |
| 3 | Stalker szybszy od gracza + atak generuje hałas + za słaby decay | `stalker.gd`, `noise_manager.gd` | Pętla ciszy nie do przejścia (potwierdzone testem: 3 ataki pod rząd) | **P0 — naprawione**: 88/55 vs 95 px/s, atak bez hałasu, decay 4.0/1.5. Test: obudził się przy 89, zasnął przy 30, zero ataków |
| 4 | Brak Przesterowania / Wabiku | — | Filar 2 GDD nie istnieje w kodzie | **P0 — naprawione**: Q + ładunek 2/regen 45s/max 3, HUD |
| 5 | Brak limitów kamery | `player.tscn` | Widać pustkę poza poziomem | **P1 — naprawione**: limit_left/top/right/bottom |
| 6 | `display_id` z kolejności spawnu | `player.gd` `_ready` | Kolizja indeksów po rozłączeniu/dołączeniu | **P1 — naprawione**: licznik `_display_counter` w main.gd |
| 7 | Pozycje zdalnych graczy ufane (brak anticheat) | `player.gd` | OK dla kooperacji, blokuje host migration | P2 (1.0) — świadomie |
| 8 | Brak AI towarzysza | — | Nie da się grać solo (16.3) | **P1 — naprawione**: `bot_companion.tscn`, reconcile 1 bot przy 1–2 graczach |
| 9 | preload-cykl main→bot→player | `main.gd` | `bot_companion.tscn` nie parsował się („Parse Error: Busy") | **P1 — naprawione**: `load()` w runtime zamiast `preload` |
| 10 | Bot bez nawigacji | `player.gd` `_bot_brain` | Bot gubi się przy przeszkodach, nie skacze celowo | P2 — A* lub navmesh |
| 11 | `MultiplayerSynchronizer` postaci klienta miał autorytet 1 (tworzony w `_ready` po `set_multiplayer_authority`) | `player.gd` | Serwer nadpisywał stan klienta: **klient nie mógł się ruszyć**, jego obrażenia/down znikały. Poz. 2 de facto nie działała dla 2. człowieka | **P0 — naprawione (1.3.1)**: synchronizator w `_init`, autorytet w `_enter_tree`, spawn przez `spawn_function` (dane startowe dla każdego peera). Test: ruch klienta 32→127 px widoczny u hosta |
| 12 | Wipe nie był podłączony (`full_reset`/`reset_enemy` bez wywołań) | `main.gd` | Brak restartu misji z §4 — każdy wykrwawiał się osobno, zabici wrogowie zostawali martwi | **P0 — naprawione (1.3.1)**: wykrywanie na serwerze, 3 s, reset Uwagi/Q/wrogów/graczy przez autorytet. Test `--wipetest` host+klient |
| 13 | Bot strzelał do każdego aktywnego wroga w zasięgu 260 px | `player.gd` `_bot_brain` | Strzały bota w ~1 s kasowały Przesterowanie drużyny i nie dawały Uwadze opaść — AI łamało filar 2 | **P1 — naprawione (1.3.1)**: po Q wstrzymuje ogień 8 s, kuca i milczy, gdy dowódca kuca, strzela tylko z linią strzału; ≤70 px broni się zawsze |
| 14 | `display_id` bota liczony z liczby graczy | `main.gd` `_reconcile_bots` | Bot i dołączający klient dostawali ten sam numer (P2) — regresja poz. 6 | **P1 — naprawione (1.3.1)**: wspólny licznik |
| 15 | Hitstop (`Engine.time_scale`) na hoście | `feel.gd` | Spowalniał symulację serwera — szarpanie u wszystkich klientów przy każdym zabójstwie | **P1 — naprawione (1.3.1)**: na hoście z klientami tylko shake |
| 16 | Próg budzenia wrogów 1,0 > hałas strzału zimnego M-83 (0,6) | `enemy.gd` | Pojedyncze strzały M-83 były dla wrogów nieme | **P2 — naprawione (1.3.1)**: próg 0,5 (kroki 0,25 nadal nie budzą) |
| 17 | Postęp podnoszenia widoczny tylko u podnoszącego | `player.gd` | Leżący nie wiedział, że ktoś go ratuje | **P2 — naprawione (1.3.1)**: synchronizacja 10 Hz, HUD „Podnoszą cię… N%" |
| 18 | Wspólny `HEAT_DECAY` 1,2/s większy niż przyrost ciepła × tempo (M-83: 0,10 × 8,3; P-64: 0,08 × 5) | `weapons.gd` | Rozgrzewała się tylko strzelba; hałas M-83/P-64 stały, `n_max` nieosiągalne — wbrew §8.1 i README | **P1 — naprawione (1.6)**: `heat_decay` per broń, walidacja i test pilnują `peak heat ≥ 0,99` |
| 19 | Własny pocisk strzelca-klienta pojawiał się po RTT; `whizz` grał strzelającemu | `player.gd` | Smuga spóźniona o 50–150 ms względem huku | **P1 — naprawione (1.6)**: predykcja kosmetyczna po stronie strzelca, serwer autorytatywny |
| 20 | Pocisk = `Area2D` przesuwany dyskretnie | `bullet.gd` | Szybka broń tunelowałaby przez wąskich wrogów i cienkie ściany | **P1 — naprawione (1.6)**: przeciąganie promienia; test: 9000 px/s trafia wroga 10 px |
| 21 | Serwer ufał żądaniu strzału (tempo, wylot) | `player.gd` | Zmodyfikowany klient: strzał bez limitu | **P1 — naprawione (1.6)**: token bucket, korekta wylotu, walidacja nadawcy; test sieciowy |
| 22 | Efekty trafień (krew, dźwięk uderzenia) tylko u serwera | `bullet.gd`, `enemy.gd` | Klient widział pocisk znikający w wrogu bez śladu | **P2 — naprawione (1.6)**: `Arsenal` rozsyła efekt trafienia do wszystkich peerów |
| 23 | Przedmioty z mapy (broń, skrzynie) mają stałe nazwy tworzone lokalnie | `level.gd` | Dołączający w trakcie misji widzi przedmioty, które inni już zabrali | P2 — znane, jak potomstwo Żyły |

**Pozostałe znane ograniczenia:** zwykli wrogowie (Trzosek, Wołek) jeszcze bez A* — gonią prosto i doskakują; brak flar jako przedmiotu (tylko znacznik ekstrakcji); dołączający w trakcie walki nie widzi już istniejącego potomstwa Żyły; brak WebSocket/relay fallback; łup misji nie istnieje, więc wipe odbiera tylko postęp próby.

**Testy regresji (headless):** `--stealthtest=25` (sama pętla ciszy ze stalkerem — zwykli wrogowie są w tym teście usuwani; PASS = zasnął, 0 HP straty; wynik 1.3.1: zasnął po 20,5 s), `--wipetest` (wipe + restart, także z klientem), `--missiontest` (gniazda → ekstrakcja → sukces → nowa misja). `--port=N` pozwala je puścić przy otwartym oknie gry.

---

## 20. Aneks A — Tabela misji (skrót)

| # | Strefa | Misja | Typ celu | Boss |
|---|--------|-------|----------|------|
| 1.1 | Bór | Zaginiony Patrol | Zbieranie | — |
| 1.2 | Bór | Przerwa w Nadawaniu | Aktywacja | — |
| 1.3 | Bór | Gniazdo | Zniszczenie | — |
| B1 | Bór | — | Walka | Pijawka |
| 2.1 | Wieś | Cisza | Przejście | — |
| 2.2 | Wieś | Piwnice | Ratunek | — |
| 2.3 | Wieś | Dzwon | Obrona | — |
| B2 | Wieś | — | Walka | Kapłan |
| 3.1 | Kopalnia | Zjazd | Obrona w ruchu | — |
| 3.2 | Kopalnia | Ciemność | Zbieranie | — |
| 3.3 | Kopalnia | Żyły | Zniszczenie + przejazd | — |
| B3 | Kopalnia | — | Pościg + walka | Matka Żył |
| 4.1 | Obiekt 86 | Kwarantanna | Ratunek | — |
| 4.2 | Obiekt 86 | Eksperyment 9 | Zbieranie + status | — |
| 4.3 | Obiekt 86 | Wyciek | Ucieczka (timed) | — |
| B4 | Obiekt 86 | — | Walka | Bliźniak |
| 5.1 | Sarkofag | Sarkofag | Dostarczanie | — |
| 5.2 | Sarkofag | Rdzeń | Wyłączenie (cisza) | — |
| 5.3 | Sarkofag | Zejście | Platforming | — |
| B5 | Sarkofag | — | Walka + odbicie | Kolekcjoner |
| 6.1 | Martwa Cisza | Membrana | Przejście | — |
| 6.2 | Martwa Cisza | Głosy | Nawigacja | — |
| 6.3 | Martwa Cisza | Martwa Cisza | Gauntlet | — |
| B6 | Martwa Cisza | — | Walka finałowa | Pierwszy Głos |

**Razem:** 18 misji + 6 bossów. Szacowany czas kampanii: 4–5 h przejścia, 15–20 h z replayem i wyzwaniami.

## 21. Aneks B — Bronie (ściąga)

| Broń | Odblokowanie | Cena | Rola |
|------|--------------|------|------|
| M-83 „Krótki" | start | — | Domyślna, wszechstronna |
| P-64 „Igła" | start | — | Sidearm, ∞ ammo |
| Maczeta | start | — | Cicha, backstab |
| SPREAD-12 | Strefa I | 400 zł | Szeroki ostrzał |
| PELLET-8 | Strefa I | 500 zł | Bliski zasięg, odrzut |
| SINEW-6 | Strefa II | 600 zł | **Cicha** (harpun) |
| FALCON-6 | Strefa II | 700 zł | Auto-namierzanie |
| HKM-9 | Strefa III | 800 zł | DoT, kontrola tłumu |
| WRATH-4 | Strefa III | 900 zł | AoE, niszczenie gniazd |
| SPECTER-1 | Strefa IV | 1200 zł | Przebicie, elitki |

## 22. Aneks C — Historia wersji

| Wersja | Data | Zmiany |
|--------|------|--------|
| 1.0 | — | Pierwszy pełny koncept produkcyjny |
| 1.1 | 2026-10-05 | Korekta po analizie krytycznej: (a) hałas → zasób (Przesterowanie Q, §8.4/8.5) rozstrzyga napięcie Contra/horror, (b) realny balans Uwagi z wartościami z testów prototypu, (c) AI towarzysz w EA nie w 1.0 (§16.3), (d) budżet 1000–1600 h + kill criteria (§16.4/16.5), (e) cena $9.99 z uzasadnieniem mechaniki wiralowej (§17.3), (f) Epic odroczone — nie bierzemy First Run (§15), (g) rejestr znanych błędów prototypu (§19), (h) misje Strefy I przestawione pod Przesterowanie + AI |
| 1.2 | 2026-10-05 | Wdrożenie priorytetów 1–3 w prototypie: pętla cichości naprawiona (test: stalker obudził się przy 89, zasnął przy 30, zero ataków), Przesterowanie Q działa (charges 2→1, przekierowanie celu), serwerowe pociski, synchronizacja przez MultiplayerSynchronizer, AI towarzysz + reconcile, limity kamery, stabilny display_id. Błędy P0/P1 z §19 zamknięte; zostały P2 (anticheat/host migration, nawigacja bota) i brak audio |
| 1.3 | 2026-10-05 | Analiza „wciągająca, przyjemna gra": filar 7 „czucie gry przed zawartością" (§2, §23), down/revive zamiast respawnu po 3 s (§4), Stalker v2 — nasłuchiwanie, zapowiedź ataku, widoczność (§8.5), strategia „demo najpierw" (§16.0). W prototypie: coyote/buffer/jump cut, hitstop i shake, 3 bronie z modelem rozgrzania lufy, Trzosek i Wołek, down/revive, audio (85 ścieżek) |
| 1.3.1 | 2026-10-05 | Audyt prototypu po 1.3 + poprawki (§19 poz. 11–17): synchronizacja postaci klienta (klient nie mógł się ruszyć), wipe podłączony, dyscyplina ognia bota (nie kasuje Q), `display_id` bota, hitstop wyłączony na hoście z klientami, próg budzenia wrogów, postęp podnoszenia u leżącego. Test ciszy izolowany od zwykłych wrogów (wynik z 1.2 przestał być miarodajny po ich dodaniu); dodano `--wipetest`. Dodano §23 |
| 1.3.2 | 2026-10-05 | Audio: (a) pętle bez trzasków — filtr HP przed szwem zamiast po nim (amb_air, szept, oddech, muzyka klikały co obieg); (b) muzyka = dokładnie 16 taktów (11,43 s), serce = dokładnie 4 uderzenia — wcześniej rytm przeskakiwał przy każdym zapętleniu; (c) `tape()` czytał 0,35% za szybko (dryf taktu, zawijanie one-shotów); (d) słuchawka przypięta do kamery człowieka (skakała gracz↔bot co klatkę i stała w złym miejscu dla okluzji); (e) serce startuje po wejściu z lobby; (f) wygaszone warstwy muzyki się zatrzymują, nowa wchodzi w tym samym miejscu taktu; (g) słychać kroki kolegi i bota; (h) limiter na Masterze; (i) cisza po rozłączeniu |
| 1.3.3 | 2026-10-05 | Prototyp: pętla misji z §4 / §16.0 pkt 1 — cel „zniszcz 3 gniazda" (misja 1.3; zniszczenie = hałas 8, budzi okolicę), ekstrakcja w punkcie najdalszym od drużyny (+1 ładunek Q wg §8.4), wymóg: cała stojąca drużyna 3 s w strefie, ekran wyniku (czas, upadki, próba), wipe = kolejna próba. Bot idzie za najbliższym stojącym człowiekiem (nie za hostem) |
| 1.3.4 | 2026-10-05 | Friendly fire = hałas (filar 3): na jednej płaszczyźnie drużyna stoi w kolejce i seria M-83 w plecy kładła kolegę — kara za samo ustawienie. Pocisk kolegi przelatuje, trafiony krzyczy (`N_FF` = 4, cooldown 0,6 s ≈ 6,7 Uwagi/s przy ciągłej serii) i dostaje odrzut; obrażenie tylko od strzelby z bliska. Bot: linia strzału uwzględnia ludzi (wcześniej strzelał przez plecy), przy zasłonięciu podskakuje. Następny krok: mapa wielopoziomowa na TileMapLayer (drużyna w pionie, A*) |
| 1.3.5 | 2026-10-05 | Prototyp: (a) **mapa na TileMapLayer** z siatki ASCII (`level.gd`) — 3 sekcje: las + posterunek (wataha w korytarzu, obejście dachem), arena z 3 poziomami kładek (wrogowie z obu stron), tartak z rusztowaniami nad wodą; kładki jednokierunkowe (wskok od spodu, zeskok dół+skok) rozkładają drużynę w pionie; kroki czytają powierzchnię z kafla; wyjścia na obu końcach mapy. (b) **Ciemność i latarka** wg §8.3 (szczegóły tamże). Testy: stealth/mission/wipe PASS, w sieci latarka klienta budzi watahę na serwerze |
| 1.3.6 | 2026-10-05 | Po pierwszej sesji: (a) **ciemniej bez latarki** — światło otoczenia i niebo strojone pomiarem luminancji (§8.3); (b) **warstwa muzyki „cisza"** (Uwaga < 20%) grała statyczny, nieprzyjemny dźwięk: wszystkie 4 akordy naraz (dysonansowy klaster 24 pił), 4 suby dudniące 6–21 Hz, wąskopasmowy szum (56% dudnienia obwiedni) i filtr przesuwany przez całą pętlę. Teraz jeden akord na takt z przenikaniem 0,6 s, sub-pedał D z pełną liczbą okresów w pętli, bez szumu i saturacji |
| 1.3.7 | 2026-10-05 | Prototyp: (a) **nawigacja A*** (§16.0 pkt 5) — graf platformówki z mapy (264 węzły; chodzenie, skok do 2 kafli, spadek z krawędzi, zeskok przez kładkę); bot idzie ścieżką (start → szczyt tartaku 13 s), Stalker chodzi po powierzchniach zamiast przez ściany (0 próbek w bryle). (b) **Boss misji: Żyła — matka gniazd** (§7.1): śpi i jest nietykalna, dopóki żyją gniazda (jej odnóża); ostatnie gniazdo ją budzi (krzyk +15 hałasu, +1 ładunek Q); 200 HP + 100 za każdego dodatkowego człowieka; co ~7 s rodzi Trzoska (limit 3 + gracze); smagnięcie macką z 0,75 s zapowiedzią — z zasięgu da się uciec; przy 50% HP furia; śmierć = potomstwo usycha, otwiera się ekstrakcja. Misja: gniazda → Żyła → ekstrakcja → wynik |
| 1.3.8 | 2026-10-05 | Żyła: koniec bezkarnego ostrzału z rusztowań (półki 160–190 px nad nią, poza zasięgiem macki i potomstwa). (a) **Pancerny grzbiet** — pocisk z góry pod stromym kątem: 20% obrażeń + rykoszet; słaby punkt = paszcza z poziomu ziemi (test: 2 s ognia z półki 19 obrażeń, z ziemi 109). (b) **Plucie zarodnikami** na graczy poza zasięgiem macki do 300 px: 0,8 s nabrzmiewania (paszcza świeci na zielono, bulgot), potem wolny pocisk po łuku w miejsce z początku zapowiedzi — stojący obrywa, ruszający się unika (test potwierdza oba) |
| 1.3.9 | 2026-10-05 | Żyła przeprojektowana — wcześniej padała w ~4 s z ziemi i nie używała filarów gry. (a) **Rytm:** paszcza zamknięta (5% obrażeń), otwiera się na 1 s po każdym ataku; ataki z harmonogramu, jeden naraz, każdy z zapowiedzią. (b) **Zamach ogonem:** fala po podłodze do 170 px w obie strony — przeskocz albo stań na kładce. (c) **Latarka** (filar 4): snop w paszczę w trakcie zapowiedzi oślepia ją — atak przerwany, paszcza otwarta 2 s (co 10 s). (d) **Q** (filar 2): Przesterowanie w pobliżu odciąga ją na 5 s — pluje w miejsce Q, nie smaga, nie zamiata. (e) **Fazy:** 66% furia, 33% krzyk — Uwaga 100%, światła migoczą, budzi się Stalker. (f) HP 750 + 250 za dodatkowego człowieka. Symulacja idealnego gracza z botem: 42 s bez latarki, 48 s z latarką, 3–4 upadki drużyny (cel dla realnej gry: 60–90 s) |
| 1.4.0 | 2026-10-05 | **UI/UX i język angielski.** Interfejs gry w całości po angielsku (lobby, HUD, cele, podpowiedzi, wynik); GDD i komentarze w kodzie zostają po polsku. Wspólny motyw (`ui_theme.gd`): obrys tekstu (czytelność w ciemności), spójne panele, przyciski i pola. Lobby od nowa: tytuł, IP + HOST GAME / JOIN (Enter = join), czytelna siatka sterowania; HUD nie prześwituje już spod lobby. HUD od nowa: karta stanu (pasek hałasu z progami 30/40/60, serca, ładunki Q, sloty broni, bateria), karta celu z podpowiedzią i paskiem bossa (progi faz), sesja + zegar misji, ostrzeżenie z wyjaśnieniem, pasek kontekstowy z postępem (podnoszenie, wykrwawianie, ewakuacja), ekran SQUAD DOWN, karta wyniku, czerwona winieta przy trafieniu/1 HP, sterowanie przez 20 s potem F1. Etykiety nad postaciami wyśrodkowane, z cieniem |
| 1.5.0 | 2026-10-05 | **Fizyka i grafika.** (1) Ruch z bezwładnością (rozpęd 0,1 s, hamowanie ~2 px), opadanie 1,35× szybsze, skok bez zmian (44 px); przysiad/rozciąganie; łuski, szczątki, krew i plamy, iskry, rozbryzgi w wodzie. (2) Tło parallax (niebo, księżyc, dwie linie sosen, mgła), pył widoczny w snopie latarki, żar gniazd. (3) Pixel-art generowany w kodzie (`tools/bake_sprites.py`): animowane postacie z warstwą świecącą (oczy), broń, kafle z wariantami, dekoracje; podmiana PNG przez artystę bez zmian w kodzie. (4) **Obiekty fizyczne**: skrzynie (pchanie, stawanie, zepchnięta z wysokości = hałas w miejscu upadku → wabik bez ładunku Q) i beczki (wybuch: obrażenia w promieniu 4 m, odrzut, reakcja łańcuchowa, hałas +15); symulacja na serwerze, sync do klientów |
| 1.5.1 | 2026-10-05 | Usunięty filtr VHS (ziarno, linie, aberracja) — decyzja po obejrzeniu w grze |
| 1.5.2 | 2026-10-05 | Friendly fire: usunięty wyjątek strzelby SPREAD-12 z bliska (<40 px zabierała koledze 1 HP). Żadna broń nie rani już kolegi — tylko hałas i odrzut; drużynę ranią jedynie wybuchy |
| 1.5.3 | 2026-10-05 | **Apteczki** (+1 HP, maks. 3): wypadają z Wołków (75%) i z Żyły (2 sztuki — na drogę do ekstrakcji); Trzoski nic nie dają. Podnosi ranny przez dotknięcie, przy pełnym HP apteczka zostaje, leżący nie podnosi; bot ustępuje rannemu człowiekowi w promieniu 80 px. Zielona poświata — widać je w ciemności. Restart misji czyści apteczki |
| 1.5.4 | 2026-10-05 | **Overhaul audio (szczegóły: `prototype/AUDIO.md`).** Audyt (`tools/audio_audit.py`) wykrył, że rdzeń syntezy był zepsuty: `osc()` bez dzielenia fazy przez SR (sinus = cisza, reszta = aliasowany szum → bas, kick, akordy, serce i UI nie miały wysokości), `fm2()`/`svf()`/`stereoize()` błędne, 74/85 plików z true-peakiem > −1 dBTP, 19 tracących >3 dB w mono. Nowy rdzeń DSP (numpy/scipy, testy), 116 assetów (było 85): broń warstwowa + własna strzelba + łuski, głosy z formantami, kroki ×5 na powierzchnię, ambient stereo bez Haas, muzyka jako 4 **stemy addytywne** (96 BPM, 8 taktów). Runtime: okluzja progowa z dyfrakcją, pogłos środowiskowy z promieni, muzyka kwantyzowana do beatu, sidechain, ogłuszenie + szum w uszach, voice management, emitery ambientu, szept stalkera pozycyjny, sygnał napisów. Audyt: 76 → 0 assetów z uwagami. Brzmienia nie oceniano uchem, zmian w silniku nie uruchomiono — wymagany odsłuch i test w Godocie |
| 1.6.0 | 2026-10-05 | **Overhaul broni (szczegóły: `prototype/WEAPONS.md`).** Analiza wykryła, że model rozgrzania działał tylko dla strzelby (wspólny decay > przyrost ciepła × tempo), ciepła nie było w UI, P-64 była zdominowana przez M-83, nie było magazynków/przeładowania/zapasu, a strzał klienta miał lag o RTT. Przebudowa: typowany `WeaponDef` + rejestr **12 broni** (dane → zero zmian w kodzie przy nowej broni), warstwa obrażeń `Combat` (krytyk, backstab, podpalenie, wybuch, przebicie), pociski z przeciąganiem promienia (bez tunelowania, spadek obrażeń, naprowadzanie, łuk, bełt do odzysku), promień/płomień/szyna/granat/cios, **amunicja ze wspólnym zapasem drużyny** + skrzynki, drop wrogów, podnoszenie i wymiana broni (E), predykcja po stronie strzelca + walidacja serwera (token bucket) + seed rozrzutu, efekty trafień do wszystkich peerów. Feel: rozbłysk ze światłem, smugi, odrzut kierunkowy kamery, bloom, celownik z łukiem ciepła i pierścieniem przeładowania, hitmarkery z dźwiękiem, animacje broni, impact wg powierzchni. HUD: magazynek/zapas, pasek lufy z kosztem strzału. Audio: +36 assetów (152 ścieżki). Testy: `--weapontest` (≈60 asercji), test sieciowy host+klient |
| 1.6.1 | 2026-10-05 | **Grafika broni i skala interfejsu.** (1) 12 sprite'ów broni narysowanych od nowa (`tools/gun_art.py`): rampy 5 tonów na materiał ze światłem z lewej-góry i chłodnymi cieniami, detale (szyny, wentylacje, pompki, żebra, lotki), te same rozmiary i wyloty lufy co wcześniej (zero zmian w balansie); **warstwa świecąca** `guns_glow.png` — taśma LR-7, cewki SPECTER-1, pilot HKM-9, diody i czubki rakiet FALCON-6 widać w ciemności jak oczy wrogów (żar SPECTER-1 narasta z ładowaniem). (2) **HUD o 30% mniejszy** (`UI_SCALE` 0,7 w `hud.gd`; układ liczony względem rozmiaru ekranu — koniec z nakładaniem się karty stanu na kartę celu). (3) **Celownik o 30% mniejszy** (`CROSS_SCALE` 0,7 w `weapon_view.gd`: ramiona, łuki ciepła i przeładowania, hitmarker, X) |
| 1.6.2 | 2026-10-05 | **Mapa rozbudowana, mniej broni w terenie.** (1) Mapa 128×30 → **192×44**: nowa strefa **Skład** między areną a tartakiem (dwupoziomowa hala z antresolą i dachem, schody z rusztowań po obu stronach, skrzynie i beczki) oraz **podziemia** pod całą mapą — trzy sale (pod posterunkiem, areną/Składem, tartakiem) połączone niskimi tunelami i trzema szybami (S1 przy posterunku, S2 i S3 w Składzie) z zygzakiem kładek; zawartość: wataha, Wołek, skrzynki. Liczba gniazd bez zmian (3, boss jest zbudowany na 3). (2) Loot: broni na ziemi **8 → 4** (PELLET-8, SINEW-6, HKM-9, WRATH-4; kilof, LR-7 i SPECTER-1 nie leżą już na mapie), każda w miejscu wymagającym eksploracji; skrzynek z amunicją 5 → 10 (mapa jest ponad 1,5× większa). Wrogowie 8+2 → 18+4. Weryfikacja: port grafu `nav.gd` do Pythona potwierdził, że każdy znacznik jest osiągalny ze startu i da się z niego wrócić (768 węzłów). Nie uruchamiano w Godocie — wymagany test ręczny i `tools/test_weapons.sh` |
| 1.6.3 | 2026-10-05 | (1) Bot **przeskakuje skrzynie i beczki** (graf A* ich nie zna: test ruchu w bok, a gdy koliduje rekwizyt — skok 42 px). (2) Etykiety graczy/botów **−30%** (`NAME_SIZE` 6 → 4). (3) Wykrwawianie **25 s → 10 s** (×1,5 / ×0,7 wg trudności: 15 / 10 / 7 s); czas podnoszenia kolegi bez zmian (4 s). (4) **Więcej grozy** — `dread.gd`: fałszywe odgłosy (kroki zza pleców urywają się, skrzypienie, trzask drzwi, szkło, odległy pomruk), migotanie świateł po uderzeniu, blade **oczy w mroku** (znikają przy podejściu/poświeceniu, nie atakują), podziemia ciemniejsze (×0,6 ambientu) i z częstszymi straszakami; tempo skaluje Uwaga i trudność (`dread` w `difficulty.gd`). Wszystko lokalne i kosmetyczne (zero wpływu na symulację/sieć), wyłączone w headless. Nie uruchamiano w Godocie — wymaga strojenia na ucho/oko |
| 1.6.4 | 2026-10-05 | **Gniazda w podziemiach.** Gniazd 3 → **4**: posterunek (powierzchnia), sala pod areną i sala pod Składem (podziemia, na górnych kładkach), szczyt tartaku. Gniazdo z areny przeniesione do podziemi — nie da się już ukończyć misji bez zejścia szybem. Żyła liczy gniazda z grupy `nests` (wcześniej na sztywno 3); jej trzy żyły na sylwetce gasną proporcjonalnie. Graf A*: wszystkie znaczniki nadal osiągalne ze startu i z powrotem. Nie uruchamiano w Godocie |
| 1.6.5 | 2026-10-05 | **Kumulowanie serc.** Apteczka przy pełnym zdrowiu dodaje serce ponad `MAX_HP` (3) — sufit `STACK_HP` = 6, serca ponad podstawowe złote (HUD i etykieta nad postacią). Ranny w promieniu 120 px od apteczki ma pierwszeństwo (pełny nie zabiera jej sprzed nosa), bot nadal ustępuje rannemu człowiekowi. Odrodzenie, wykrwawienie i restart misji wracają do 3 serc. Nie uruchamiano w Godocie |
| 1.6.6 | 2026-10-06 | **Postacie od zera (grafika).** Dotychczasowe sprite'y (prostokąty w kodzie, 4 klatki biegu, bez objętości) zastąpiono generatorem `tools/char_art.py` + `char_player.py` + `char_monsters.py`: każda klatka powstaje z **pozy szkieletu** (kąty stawów, kinematyka prosta, uziemienie najniższej stopy), ciało to kapsuły/elipsy z normalnymi renderowane w 4× i oświetlone jednym światłem z lewej-góry, kwantyzowane do ramp 4 tonów z przesunięciem barwy (cień chłodny, światło ciepłe), potem pikseloza, wygładzanie pasm, obrys selektywny (ciemny odcień sąsiedniego materiału) i detale na siatce gry. Gracz: kurtka w kolorze slotu, czapka, plecak z anteną, pas, kieszenie, twarz; **bieg 8 klatek** z cyklem nóg i wymachem ręki, oddech w idle (6), skok/spadek/przysiad/leżenie w nowych pozach. Bot: hełm z **wizjerem w warstwie glow**. Trzosek (ogar z kolcami, kły, otwarta paszcza w zapowiedzi), Wołek (garbaty osiłek z rogami i kolcami, ciężki chód), Stalker (wychudzony, żebra, strzępy płaszcza, oczy w glow). Rozmiary klatek i punkt dłoni broni (9, 12) bez zmian — kod gry nie wymaga zmian; manifest ma tylko więcej klatek. Bez numpy/Pillow bake wraca do starego rysunku. Nie uruchamiano w Godocie — wymaga oceny w grze |
| 1.6.7 | 2026-10-06 | Miks i światło: **oddech cichszy o połowę** (−6 dB: start −24 dB, zakres −30…−18 dB) oraz **jasność bez latarki −30%** — ambient (`Lights.AMBIENT`) i energia aury gracza (`AURA_ENERGY` 0,75 → 0,525) ×0,7; latarka, flara i światła postaci bez zmian, więc kontrast latarki rośnie. Nie uruchamiano w Godocie |
| 1.6.8 | 2026-10-06 | **Zachowanie wrogów i bota.** Wrogowie (`enemy.gd`): (1) **percepcja** — obudzony wróg znał położenie gracza na całej mapie; teraz widzi w promieniu `sight` (260 / 200 px, ×0,6 dla kucającego, ×`enemy_hear`) z czystą linią (promień po bryłach), a bez widocznego celu idzie na **ostatni ślad** (źródło hałasu, ostatnia pozycja), rozgląda się 3,5 s, po 9 s bez kontaktu **wraca do domu i zasypia** (skradanie ma sens także po obudzeniu watahy); potomstwo Żyły jest `omniscient`. (2) **Nawigacja A\*** z `nav.gd` (graf mapy): skoki po krawędziach JUMP (Trzosek, 42 px jak gracz), zeskok przez kładkę (DROP), Wołek nie przeskoczy, więc czeka pod przeszkodą i rezygnuje; zmiana piętra z histerezą 0,35 s (skok gracza nie przełącza trybu). (3) **Wataha**: rozsuwanie w poziomie (nie stoją w jednym punkcie), Trzosek po ciosie odskakuje 0,32 s (uderz i uciekaj). Bot (`player.gd`): unik przed zapowiedzią ciosu i cofanie się od wroga bliżej niż 30 px (strzela w biegu), ranny idzie po apteczkę w 180 px (ludzie mają pierwszeństwo), kilku botów trzyma różny odstęp od dowódcy. Składnia wszystkich skryptów sprawdzona `gdparse`; **nie uruchamiano w Godocie** — nawigację i strojenie trzeba obejrzeć w grze |
| 1.6.9 | 2026-10-06 | **Steam jako transport co-op** (opcjonalny). `steam_net.gd` + przyciski w lobby (STEAM HOST / lobby ID / STEAM JOIN), F2 = zaproszenia, start z „Dołącz do gry" (`+connect_lobby`). Wrapper woła GodotSteam dynamicznie (singleton `Steam`, klasa `SteamMultiplayerPeer`), dobiera argumenty po nazwach i obsługuje dwa warianty peera; gra zachowuje ENet i działa bez wtyczki (przyciski wyszarzone). Test/rozwój na App ID 480 (Spacewar, bez opłat), wydanie wymaga własnego App ID (Steam Direct 100 USD). Host startuje sesję dopiero przy `CONNECTION_CONNECTED`. Wtyczki GodotSteam nie ma w repo; składnia sprawdzona `gdparse`, **integracja ze Steamem nie była testowana** — wymaga dwóch kont Steam |
| 1.7.0 | 2026-10-06 | **Cztery typy wrogów + Stalker (GDD §16.1).** Dołożono dwa z §7.1 pasujące do filaru ciszy: **Ślepiec** (60 HP, „nie widzi — słyszy": brak wzroku poza dotykiem 26 px, `keen` — próg hałasu 0,25 i zasięg słyszenia rosnący z głośnością (kroki z ~105 px, strzały z 300+ px), latarka go nie budzi, idzie na ślad hałasu i rozgląda się) oraz **Podsłuchacz** (35 HP, stoi, czuwa; wzrok 240 px, słuch 170 px; po zobaczeniu/usłyszeniu krzyk z zapowiedzią 0,9 s: hałas +14, wrogowie w 420 px dostają ślad do krzyku i się budzą, fala + dźwięk; kolejny krzyk po 6 s; trafiony pociskiem krzyczy, maczeta w plecy zabija po cichu; bot widzi go jako zagrożenie dopiero po krzyku). Nowa grafika (`char_monsters.py`: ślepiec, podsluchacz), znaczniki mapy `L` i `P`: 3 Ślepce (arena, sale pod areną i pod Składem) i 3 Podsłuchacze (przedpole tartaku, dach hali, półka w podziemnej sali). Graf A*: wszystkie znaczniki nadal osiągalne. Składnia `gdparse`; **nie uruchamiano w Godocie** — wymaga strojenia (zasięgi, hałas krzyku) |
| 1.7.1 | 2026-10-06 | **Krzyk z mikrofonu (VAD) + odpowiednik na przycisk (GDD §8.2, §14).** Autoload `Voice` (`voice.gd`): wyciszona szyna „Mic" z `AudioEffectCapture`, poziom RMS z bufora, **VAD**: próg = max(bezwzględny dBFS wg czułości LOW/MED/HIGH, szum tła + margines), krzyk musi trwać ≥ 0,18 s (kliknięcia i kaszel odpadają), histereza, adaptacyjny szum tła; **szept i zwykła mowa nie generują hałasu**. Krzyk (mikrofon albo klawisz **G**, ten sam kod): Uwaga +20 (mikrofon 12–26 wg głośności), `NoiseMgr.add_scream` → wrogowie w 25 m dostają ślad do krzyku i się budzą (`enemy.hear_scream`), fala + dźwięk u wszystkich peerów, cooldown 2,5 s. **Opt-in** (domyślnie wyłączony, przycisk MIC w lobby, stan zapisany w `user://settings.cfg`), wskaźnik poziomu z progiem w rogu ekranu. Prywatność: audio tylko lokalnie, bez nagrywania i wysyłania. Dostępność: nic nie wymaga mikrofonu (G). Wymaga `audio/driver/enable_input=true` (system może zapytać o zgodę na mikrofon; pod macOS eksport potrzebuje `NSMicrophoneUsageDescription`). Odroczone: cenzura wulgaryzmów, push-to-talk/proximity chat, finał z mikrofonem (boss 6). Składnia `gdparse`; **nie uruchamiano w Godocie ani z prawdziwym mikrofonem** — progi dBFS do strojenia na kilku mikrofonach (GDD §18) |
| 1.7.2 | 2026-10-06 | **Kompensacja opóźnienia dla pocisków serwerowych (GDD §12, §16.1).** Autoload `LagComp`: serwer co 0,5 s pinguje klientów i liczy RTT (EMA) — klient niczego nie deklaruje, więc nie da się go zawyżyć; `rewind_for(peer)` = RTT + 50 ms interpolacji, **maks. 150 ms** (GDD). Wrogowie (`enemy.gd`) zapisują historię pozycji (0,5 s, co klatkę fizyki), `lag_rect(t)` zwraca prostokąt trafień z chwili `t` (interpolacja). Strzał klienta: pocisk (`projectile.gd`) „dogania" czas strzału — leci `lag` s krokami po 1/60 s, wrogów testuje w pozycjach z historii (odcinek vs prostokąt), ściany i kolegów zwykłym promieniem, potem leci dalej w czasie rzeczywistym; szyna (`Combat.trace`) robi jeden test w przeszłość. Kompensowani są wrogowie z historią (Trzosek, Wołek, Ślepiec, Podsłuchacz); gniazda, boss, Stalker i obiekty fizyczne liczone na bieżąco. Poza zakresem: ciągłe bronie (promień, płomień), cios wręcz, wybuchy (liczone w chwili detonacji), strzały hosta i botów (0 ms). Test jednostkowy `_t_lag` (historia, interpolacja, odcinek vs prostokąt). Składnia `gdparse`; **nie uruchamiano w Godocie ani przy realnym opóźnieniu** — warto sprawdzić z sztucznym lagiem (np. `tc netem delay 100ms`) |
| 1.7.3 | 2026-10-06 | **Design i jakość UI (po zrzutach z gry).** (1) **Lobby przepisane**: lista sterowania była ucinana przy dolnej krawędzi (brakowało F1/F2/G) — teraz karta jest wyśrodkowana i mieści się z zapasem: wiersze LAN i Steam mają te same kolumny (przycisk | pole | przycisk), sekcje MULTIPLAYER / OPTIONS / CONTROLS z podpisami, sterowanie w dwóch kolumnach z klawiszami jako „keycapy" (14 pozycji, w tym R, V, G), status o stałej wysokości (układ nie skacze), tytuł delikatnie migocze. (2) **Motyw** (`ui_theme.gd`): stan *disabled* przycisków (wyszarzone Steam bez wtyczki wyglądały jak aktywne) i pól tekstowych, cień i ciepła ramka paneli. (3) **HUD**: cienkie separatory grup w karcie statusu (stan | broń | światło) i pod nagłówkiem celu; cień wyłączony na małych slotach broni. Układ HUD w grze (kolejność, skala 0,7) bez zmian. Składnia `gdparse`; **nie uruchamiano w Godocie** — wymaga oceny wizualnej na zrzucie |
| 1.7.4 | 2026-10-06 | **Logika wrogów: słuch po trasie, wataha z morale, Mimik, Wołek-bruiser.** (1) **Słyszalność po ścieżce**: hałas, krzyk gracza i alarm Podsłuchacza liczą się długością trasy po grafie A* (`_sound_distance`), nie linią prostą (prefiltr: poniżej limitu liczymy A*, brak trasy = tłumienie ×3) — strzał na powierzchni nie budzi sal pod ziemią, a ściany i piętra mają znaczenie. (2) **Wataha (Trzosek)**: max 2 atakujących naraz (`MAX_ATTACKERS`), reszta krąży w pasmie 26–44 px i czeka na wolne miejsce; **morale** — śmierć kolegi w 220 px podnosi strach (+0,34, przewodnik = najstarszy w watasze +0,7, zanik 0,12/s), przy 1,0 wataha się rozbiega na 2,4 s; **strach przed Stalkerem** — aktywny ON w 260 px zmusza Trzoski do ucieczki od niego. Panika uogólniona (źródło ucieczki: gracz, pozycja zgonu albo Stalker). (3) **Mimik** (nowy typ, §7.1): zamaskowany stoi jak kolega (sprite gracza, etykieta „P2–P4" bez serduszek), woła o pomoc próbką bólu gracza co 6–10 s, gdy ktoś jest w 70–340 px; demaskuje go latarka, strzał albo podejście na 46 px (krzyk + 0,35 s przemiany, potem pościg, 70 HP, 2 obrażenia); tell-e: brak serduszek, brak kroków, oczy świecące w ciemności, dziwny numer. (4) **Wołek-bruiser**: **szarża** (zapowiedź 0,7 s, 0,9 s biegu ×3,4, cooldown 7 s) rozbija skrzynie, detonuje beczki (wybuch rani też jego), uderza gracza za 2 HP, o ścianę — ogłuszenie 1,3 s i hałas; **rzut skrzynią** (zapowiedź 0,8 s, łuk balistyczny, skrzynia rani 1 HP przy trafieniu, cooldown 6 s) — przy każdym Wołku postawiono skrzynię. Mapa: 2 Mimiki (`Y`: wejście do hali, podziemny tunel), 4 nowe skrzynie; graf A* nadal spójny. Składnia `gdparse`; **nie uruchamiano w Godocie** — wszystkie liczby (zasięgi, cooldowny, morale) do strojenia na żywo |
| 1.7.5 | 2026-10-06 | **Światło, pamięć, zasadzki i reżyser tempa (propozycje 5–8).** (5) **Flara (F) i Ćma**: flara to światło-przynęta bez hałasu — wspólna pula drużyny (start 3, max 5, +1 ze skrzyni z mapy i za cel; `NoiseMgr.flares`, serwer rozstrzyga), leci łukiem (deterministycznie, bez sieciowej synchronizacji), płonie 25 s, daje światłolubnym Trzoskom ślad (jeśli ≤ 360 px po trasie) i odciąga ćmy. **Ćma** (18 HP, lata, wisi pod sufitem aż zobaczy światło w 420 px): leci falistym lotem na flarę (spala się, 6 DPS) albo na włączoną latarkę (gryzie za 1 HP) — latarka ma teraz kolejną cenę; flara rzucona daleko ratuje. (6) **Pamięć wrogów**: wabik Q użyty ponownie w promieniu 140 px w ciągu 120 s jest „zwietrzały" — kosztuje ładunek i 3 Uwagi, ale nie przekierowuje Stalkera ani wrogów (komunikat w HUD); wróg wracający do domu raz sprawdza „gorące miejsce" (gdzie w ostatnich 90 s strzelano, ≤ 600 px; do 6 miejsc w `NoiseMgr.hot_spots`). (7) **Skoczek** (40 HP): wisi pod sufitem nad przejściami (3 tunele i hala), spada, gdy ktoś stoi pod nim w 36 px poziomo i 10–220 px w dół (z linią wzroku) albo go coś obudzi — lądowanie rani 2 HP i robi hałas; potem biega i skacze po grafie A*; nie wraca na sufit. (8) **Dyrektor grozy** (`director.gd`, autoload, serwer): napięcie = max(stres, Uwaga·0,7); stres rośnie od utraty HP (0,22/HP) i walki, opada w ciszy; po szczycie (>0,75) 45 s okna oddechu bez dosypywania; po ≥35 s bez starcia, przy stresie <0,3, w fazie OBJECTIVE i ≤3 wędrowcach wypuszcza co 55–90 s (×`dread` trudności) grupę (2–3 Trzoski albo Ślepiec) w ciemności poza kadrem i bez linii wzroku, która rusza na pozycję drużyny; uśpieni, odlegli wędrowcy znikają; napięcie idzie do klientów i skaluje `dread.gd`. Mapa: 4 Skoczki (`J`) i 7 Ćm (`Z`), nowe sprite'y `cma`, `skoczek`. Składnia `gdparse`; **nie uruchamiano w Godocie** — wszystkie stałe do strojenia na żywo, szczególnie tempo dyrektora i zasięgi ćmy |
| 1.7.6 | 2026-10-06 | **Przebudowa HUD wg wzorców gatunku (Left 4 Dead, Deep Rock Galactic, Helldivers, Dead Space).** Dotąd jedna gęsta karta w lewym górnym rogu (hałas, zdrowie, zasoby, broń, światło) i zdrowie tylko własne. Teraz: **lewy dolny róg — karta drużyny**: wiersz każdego gracza i bota, własna karta największa na dole (najbliżej rogu), koledzy nad nią; plakietka w kolorze slotu (jak kurtka sprite'a: P1 bursztyn, P2 cyjan, P3 czerwień, P4 zieleń, AI szary), serca (złote ponad bazę), stan (DOWN Ns / REVIVING / CRITICAL migoczące / YOU / AI), pasek pod spodem, gdy ktoś leży (czerwony = wykrwawianie, zielony = podnoszenie), błysk wiersza po utracie HP. **Prawy dolny róg — karta broni i zasobów**: nazwa i stan (RELOADING / NO AMMO), **duży magazynek + zapas drużyny**, pasek przeładowania / ładowania szyny, koszt hałasu strzału (BARREL), 4 sloty, a niżej wabik Q, flary F i bateria latarki L. **Lewy górny róg — tylko miernik hałasu** z etykietą stanu (CALM / UNEASY / HUNTED) — jedyny wskaźnik do ciągłej obserwacji (filar ciszy). Wskaźnik mikrofonu pod miernikiem hałasu; podpowiedź F1 pod zegarem. Wiersze drużyny powstają dynamicznie (dołączanie, rozłączanie, boty). Składnia `gdparse`; **nie uruchamiano w Godocie** — wymaga zrzutu z gry i strojenia odstępów |
| 1.7.7 | 2026-10-06 | **Karta broni o połowę mniejsza** (po zrzucie z gry: zajmowała zbyt dużo ekranu). Szerokość 184 → 130, wysokość ok. −35%, powierzchnia ≈ −50%: nazwa i stan w nagłówku, magazynek 22 → 18 pt, pasek ciepła lufy w jednym wierszu z kosztem strzału (bez podpisu BARREL), sloty broni jako same klawisze 1/2/3/V (aktywny podświetlony; nazwa jest w nagłówku), wabik Q i flary F w jednym wierszu, latarka jako cienki pasek z procentem. Treść bez zmian — tylko układ. Składnia `gdparse`; **nie uruchamiano w Godocie** |
| 1.7.8 | 2026-10-06 | **Powierzchnie: ruch, kroki, hałas; plamy oleju i bagno.** Nowy `surfaces.gd` — jedna tabela własności powierzchni (prędkość, przyspieszanie, hamowanie, zawracanie, skok, mnożnik hałasu biegu, próbka/głośność/wysokość/warstwa kroku): dirt, concrete, metal, **water** (płycizna/bagno: ×0,72, accel ×0,55, skok ×0,85, hałas ×1,3), **mud** (×0,58, accel ×0,42, skok ×0,8, hałas ×0,6), **oil** (×0,9, accel ×0,14, hamowanie ×0,06, zawracanie ×0,12 = ślizg), oraz zapas pod biom zimowy: **ice** (ślizg jak olej, ×1,05) i **snow** (×0,82, cichy). Gracz: maks. prędkość, przyspieszenie, hamowanie, zawracanie i wybicie z `surfaces.gd` (zastąpiło stały `WATER_SPEED`), hałas biegu × `noise`; bot i potwory: mnożnik prędkości (da się ich zwabić w błoto). Mapa: nowe kafle-podłoża `m` (błoto), `O` (olej), `i` (lód), `s` (śnieg) z grafiką w atlasie 12×4; rozmieszczone: bagno przy starcie (6) i w sali zachodniej (6), olej w arenie (5), hali Składu (7) i dwóch salach podziemnych (7+7); lód i śnieg tylko w atlasie. **Kroki**: bazowo +6 dB (własne −14 → −8, cudze −19 → −13) i wyraźnie różne: ziemia cicha i miękka, beton twardszy, metal najgłośniejszy z metalicznym dzwonieniem, woda z drugą warstwą chlupotu, błoto z mlaśnięciem; kucanie −7 dB. **Oddech** cichszy o kolejne 8 dB (start −32, zakres −38…−26 dB). Graf A* bez zmian (kafle nadal bryły). Składnia `gdparse`; **nie uruchamiano w Godocie** — strojenie ślizgu i grząskości na żywo |
| 1.7.9 | 2026-10-06 | **Karta broni: płaski pasek na środku dołu** (po zrzucie z gry: karta w prawym dolnym rogu zasłaniała bossa). Układ pionowy (130 px szerokości, ok. 6 wierszy) zastąpiony jednym rzędem: nazwa broni nad kosztem hałasu strzału, duży magazynek + zapas, stan (RELOADING / NO AMMO) nad paskami przeładowania i ciepła lufy, sloty 1–3 + V, wabik (Q), flary (F) i latarka (L). Pasek jest wyśrodkowany i niski (ok. 30 px wysokości zamiast ok. 90), a pasek kontekstowy (revive, ewakuacja) podniesiony z 81% na 76% wysokości, by nie nakładał się na pasek broni. Zmiana wyłącznie w `hud.gd`. |
| 1.7.10 | 2026-10-06 | **Miniatury broni w HUD.** Pasek broni dostał sylwetki z arkusza `guns.png` (te same, co w świecie i na podnośnikach): duża miniatura aktualnej broni (skala 2×) na ciemnej płytce z miękką poświatą i paskiem w kolorze smugi pocisku danej broni, oraz miniatury w czterech slotach (1–3 + V) — aktywny jasny w złotej ramce, pozostałe przygaszone, numer klawisza w rogu. Sylwetki mają obrys i cień dla czytelności, warstwa `guns_glow.png` świeci (taśma LR-7, płomień HKM-9). Nowa klasa `GunIcon` w `hud.gd`, bez nowych assetów — nowa broń dostaje miniaturę automatycznie przez `gun_row`. |
| 1.7.11 | 2026-10-06 | **Przygotowanie dema.** (1) **Menu pauzy** (Esc / P, `pause_menu.gd`): głośność ogólna / muzyka+ambient / efekty, wstrząsy kamery FULL-HALF-OFF, rozmiar HUD (0,85× / 1× / 1,25× bazowej skali), podpowiedzi, mikrofon, pełny ekran (F11), ściąga sterowania. Solo zatrzymuje grę, kooperacja nie (host jest autorytetem); na czas menu akcje gry są wycięte z InputMap, żeby klik nie strzelał. Nowy autoload `Settings` (zapis w `user://settings.cfg`, współdzielony z `voice.gd`). (2) **Podpowiedzi dla nowego gracza** (`hints.gd`): 7 jednorazowych wskazówek wyzwalanych sytuacją (ruch/skradanie, pierwszy hałas, niepokój, leżący kolega, własny down, latarka, flara) zamiast ściany tekstu; zapamiętywane. (3) **Ekran końcowy dema**: zachęta do listy życzeń (`Settings.DEMO`, `STORE_URL`). (4) `PLAYTEST.md`: lista kontrolna eksportu, playtestu (§23.3), testu sieci i strony Steam. Zmiany bez testu w silniku — do sprawdzenia w grze. |
| 1.7.12 | 2026-10-06 | **Menu pauzy mniejsze** (po zrzucie z gry: karta nie mieściła się na ekranie). Menu jest teraz rysowane w skali HUD (70% × ustawienie HUD SIZE, logiczny rozmiar = viewport / skala), karta 300 zamiast 330 jednostek, przyciski ustawień niższe (mniejsze marginesy pionowe, czcionka 9), mniejsze odstępy. |
| 1.7.13 | 2026-10-06 | **Bestiariusz i opisy broni w menu pauzy.** Menu dostało zakładki SETTINGS / BESTIARY / WEAPONS / CONTROLS. Bestiariusz (10 pozycji: 7 zwykłych wrogów, Stalker „ON", gniazdo, boss Żyła): animowany portret z arkusza sprite'ów (boss rysowany w kodzie), statystyki liczone z `Enemy.KINDS` (HP, prędkość w m/s, obrażenia, słuch, wzrok), opis zachowania i wskazówka jak sobie radzić. Bronie (12 pozycji): miniatura z paskiem w kolorze smugi, obrażenia, tempo, zasięg, magazynek + zapas, przeładowanie, hałas (zimny → rozgrzany), opis i wskazówka — liczby z `WeaponDef`, więc nowa broń pojawia się w kodeksie sama (opis do dopisania w `codex.gd`). Wszystkie wpisy widoczne od początku (bez odblokowywania po spotkaniu). `GunIcon` wyodrębniony z `hud.gd` do `gun_icon.gd`. |
| 1.7.14 | 2026-10-06 | **Ostrzejsze miniatury w bestiariuszu, katalogu broni i HUD.** Przyczyna rozmycia: kontrolki rysowały sprite'y z domyślnym filtrem liniowym (reszta gry używa NEAREST), a skala HUD 0,7 razem z rozciągnięciem okna dawała nieliczbową liczbę pikseli ekranu na piksel rysunku. Nowy `pixel_art.gd` liczy skalę tak, by piksel rysunku = całkowita liczba pikseli ekranu (przy braku miejsca schodzi do 1/2, 1/3…), przyciąga pozycje do siatki ekranu i rysuje obrys o grubości 1 piksela ekranu. Portrety (`codex_portrait.gd`): gradient tła, poświata w kolorze wpisu (kolor stwora / smugi pocisku), podłoga z cieniem, nawiasy w rogach, animowana klatka z warstwą świecącą. Nowość: **miniatury w wierszach listy** (bestiariusz i bronie). `GunIcon` w HUD używa tej samej skali; tekst numerów slotów zostaje gładki. |
| 1.7.15 | 2026-10-06 | **Nowy wygląd bossa The Vein (Żyła).** Zamiast kilku kółek w `_draw()` — sprite 128×80 z `tools/char_boss.py` (silnik jak u potworów: render 4×, rampy cieni, obrys, warstwa świecąca). Bryła: ciemnoczerwona masa mięsa, pancerny grzbiet z pięciu płyt kostnych z kolcami, sześć macek-odnóży ze stawami, dwa czułki korony, rząd oczu, wypukłe żyły i paszcza na dole — zamknięta (dwie płyty ze szwem, żebra, kły w szwie) albo otwarta (ciemna jama z kręgiem 12 zębów). Pięć animacji: `dormant` (zapadnięta, ospała), `idle`, `open` (paszcza otwarta — okno obrażeń/ogłuszenie), `windup` (macki uniesione przed smagnięciem/zamachem), `spit` (nabrzmiały worek zarodników). Furia (faza 2) przyspiesza animację ×1,45, faza 3 mocniej rozżarza oczy; biały błysk po trafieniu w paszczę, drżenie po utracie gniazda. Nakładka (`_draw_overlay`) rysuje żar wzdłuż żył korpusu (gasną z liczbą gniazd) i blask paszczy w nowym punkcie (0, −14); fale i zapowiedzi bez zmian. Kolizja 64×44 → 70×46 pod większą bryłę. Kodeks (bestiariusz) pokazuje nowy sprite. Bez arkusza gra wraca do rysunku z kółek. |
| 1.7.16 | 2026-10-06 | **Nowy wygląd pozostałych wrogów (za akceptacją porównania PNG).** `tools/char_monsters_hd.py` (silnik jak boss: render 4×, rampy, obrys, warstwa świecąca) zastępuje arkusze: Trzosek 24×22 (kolce grzbietu, żebra, kły, trójpalczaste łapy), Wołek 44×44 (rogi, płyty kostne, kolce na pięściach, szwy), Skoczek 26×26 (segmentowany odwłok, żuwaczki, kolce na stawach), Ślepiec 26×32 (zaszyte oczodoły, sterczące ucho, zębata szczelina), Podsłuchacz 26×40 (uszy w „V", szczelina ust, w krzyku uszy odchylone), Cma 26×20 (puszyste ciało, pierzaste czułki, skrzydła z „oczami"), Stalker 32×60 (płaszcz z kapturem, czarna pustka z czerwonymi oczami, długie palce), gniazdo 40×34 (kępa worków z żyłami, korzenie, kolce). Nazwy i liczba klatek animacji bez zmian. **Hitboxy i kolizje bez zmian** (sprite większy od hitboxu); pasek HP gniazda przesunięty na −38. Mimik zostaje 16×24 (musi pasować do gracza — poprawa razem z graczem to osobne zadanie). Podgląd w kodeksie (bestiariusz) bierze nowe arkusze automatycznie. |
| 1.7.17 | 2026-10-06 | **Nowy wygląd broni — w świecie i w UI** (za akceptacją porównania PNG). `tools/gun_icons_hd.py` (silnik jak boss i potwory) rysuje 12 broni jako jeden projekt w dwóch arkuszach: **`guns.png` 36×14** — broń w rękach graczy i na podłodze (wcześniej 24×9), dłoń w (6,5; 7), kolba za dłonią ucięta jak dawniej; oraz **`gun_icons.png` 64×24** — ikony HUD i kodeksu (miniatury ostro skalowane do 1/2, 1/3… gdy trzeba). Nowe `gun_len` (px dłoń → wylot): M-83 18, SPREAD-12 18, P-64 14, PELLET-8 18, LR-7 18, HKM-9 15, WRATH-4 14, FALCON-6 16, SPECTER-1 17, SINEW-6 17, maczeta 22, kilof 20 (wcześniej 9–16); `bake_sprites.py` sprawdza zgodność z `weapons.gd`. Wylot lufy skracany do ściany (`muzzle_pos`), żeby dłuższa broń nie strzelała przez cienką przegrodę. Ciężkie bronie (WRATH-4, FALCON-6, SPECTER-1) osadzone niżej względem dłoni, by nie zasłaniać twarzy. Tolerancja wylotu u serwera (40 px) bez zmian. |
| 1.7.18 | 2026-10-06 | **Broń w świecie: 2× więcej pikseli przy tym samym rozmiarze.** Arkusz `guns.png` ma klatkę 72×28 (było 36×14), a manifest niesie `scale` 0,5 (nowe `Sprites.scale_of`), więc broń zajmuje na ekranie dokładnie tyle co wcześniej, ale z 4× większą liczbą pikseli na powierzchnię — drobniejsze żebra, szyny, słoje, cewki. Rysunki powstają tym samym projektem co ikony (`tools/gun_icons_hd.py`, `WORLD_DENSITY = 2`), obrys 2 px arkusza = 1 px świata. W `weapon_view.gd` broń i jej warstwa świecąca mają skalę 0,5, filtr liniowy (obrót pod dowolnym kątem bez „schodków” nearest) i `filter_clip` na atlasie (brak przeciekania sąsiedniej klatki); pivot dłoni (13; 14). `gun_len`, rozbłysk i pozycja wylotu bez zmian (liczone w pikselach świata). Broń na podłodze (`pickup.gd`) rysowana w tej samej skali. Kompromis: broń jest gładsza i bardziej szczegółowa niż reszta świata (krawędzie sprite'ów o gęstości 1×) — do oceny w grze. |
| 1.7.19 | 2026-10-06 | **Boss The Vein w 2× gęstości pikseli.** Arkusz `vein.png` ma klatkę 256×160 (było 128×80), manifest niesie `scale` 0,5, więc boss zajmuje na ekranie tyle co wcześniej (128×80 px świata), ale z 4× większą liczbą pikseli. `char_boss.py` renderuje projekt z `DENSITY = 2` (obrys 2 px arkusza = 1 px świata) i dodaje drobne detale możliwe dopiero przy gęstszej siatce: pory i guzki skóry, żebra na płytach grzbietu. Ogólna obsługa arkuszy o innej gęstości w `Sprites` (`scale_of`, skala węzła, filtr liniowy, `filter_clip` w atlasie) — ten sam mechanizm co dla broni. Boss.gd bez zmian: współrzędne świata (maw, żyły, kolizja 70×46) te same. Kodeks pokazuje bossa w pełnej gęstości. |
| 1.7.20 | 2026-10-06 | **Pozostali wrogowie w 2× gęstości pikseli.** Trzosek, Wołek, Skoczek, Ślepiec, Podsłuchacz, Cma, Stalker i gniazdo mają arkusze o dwukrotnie większej liczbie pikseli (np. Trzosek 48×44, Wołek 88×88, Stalker 64×120, gniazdo 80×68), rysowane w grze w skali 0,5 (manifest `scale`), więc ich rozmiar na ekranie się nie zmienia. `char_monsters_hd.py` renderuje z `DENSITY = 2` (helpery `_sc`, `_finish2` z obrysem 2 px arkusza = 1 px świata, `_eye` dla świecących punktów, `_speckle` dla drobnych detali: pory skóry Wołka, kępki sierści Trzoska, ziarnistość gniazda). Ten sam mechanizm w `Sprites` co dla broni i bossa (skala węzła, filtr liniowy, `filter_clip` w atlasie). Mimik zostaje w 1× (16×24), bo musi pasować do sylwetki gracza. Zmiany bez wpływu na hitboxy, animacje i logikę. |
| 1.7.21 | 2026-10-06 | **Naprawa: białe prostokąty zamiast broni w HUD i kodeksie.** Przyczyna (odtworzona w silniku 4.7 pod xvfb): tekstura wczytana po raz pierwszy W TRAKCIE `_draw()` rysuje się jako biały prostokąt i taką zostaje, dopóki kontrolka się nie przerysuje (kontrolki broni przerysowują się tylko przy zmianie). `GunIcon` ładuje teraz arkusz w konstruktorze, portret kodeksu w `show_spec`, a podnośnik broni w `_ready`. Dodane brakujące pliki `.import` (gun_icons, vein) i `.uid` skryptów — wygenerowane przez `godot --headless --import`. |
| 1.7.22 | 2026-10-06 | **Gracz, bot i Mimik w 2× gęstości pikseli + angielskie nazwy.** `tools/char_player.py`: klatka 32×48 rysowana w skali 0,5 (16×24 w świecie; hitbox i oś broni (9, 12) bez zmian), manifest `scale`. Mimik rysuje się z tego samego rigu, więc ma tę samą gęstość i sylwetkę. Naprawa: `player.gd` co klatkę nadpisywał skalę sprite'a (`body.scale = squash`), więc postacie były 2× za duże — teraz `squash * skala z manifestu`. Wyświetlane nazwy: WRATH-4, FALCON-6, SPECTER-1, SINEW-6, PELLET-8 oraz Cutpurse, Bullock, Leaper, Blind One, Eavesdropper, Mimic, Moth, Stalker (identyfikatory i nazwy plików bez zmian). |
| 1.7.23 | 2026-10-06 | **Nocny Dyżur v1 (§11, §16.1).** Tryb wybierany przez hosta w lobby (`MODE: CAMPAIGN / NIGHT SHIFT`) albo `--nightshift`: seria **5 misji pod rząd** na tej samej mapie, **wipe kończy serię** (zamiast powtórki misji), [Enter] na ekranie wyniku = następna misja, po serii albo porażce = nowa seria. Każda kolejna misja jest twardsza: **HP wrogów i bossa +12% na misję** oraz losowe modyfikatory (misje 2–3: jeden, 4–5: dwa): **OVERLOAD** (Uwaga startuje od 50), **AMMO FAMINE** (połowa amunicji w skrzyniach i z wrogów), **LEAK** (Stalker budzi się przy 45, zasypia przy 15), **THIN WALLS** (każdy hałas +50%). Stan (`night_shift.gd`, statyczny) replikuje `mission._sync`; HUD pokazuje „NIGHT SHIFT n/5", zasady misji w pierwszych 9 s i karty wyniku (misja ukończona / SHIFT OVER / SHIFT COMPLETE) z rekordem lokalnym (`Settings.shift_best_*`, `user://settings.cfg`). **Poza zakresem v1:** cotygodniowy ranking online (brak backendu), losowe układy map (jedna mapa — §16.0 pkt 3), modyfikatory z §11 wymagające nowych systemów (Delikatni, Podwójna horda, Bunt maszyn). Test: `--nightshift --host --shifttest` (seria, modyfikatory, porażka, nowa seria). |
| 1.7.24 | 2026-10-06 | **Druga misja Strefy I: 1.2 „Przerwa w Nadawaniu" + wiele misji w grze.** (1) **Mapy jako dane**: `scripts/maps/z1_m2.gd` i `z1_m3.gd` (dotychczasowa mapa „Gniazdo" = 1.3); `level.load_map(id)` przebudowuje poziom na każdym peerze (host rozsyła `_load_map_rpc`, dołączający dostaje mapę przed postacią), gracze dostają nowy start i granice kamery, `mission.rebind()` podpina cel. (2) **Cel „generators"**: `generator.gd` (znacznik `G`) — przytrzymaj [E] 4 s (2 osoby = 2× szybciej), praca robi hałas, uruchomiony generator buczy i co 6 s zgłasza cichy hałas (przyciąga nasłuchujących). Po ostatnim **nadajnik rozbrzmiewa na cały las**: `NoiseMgr.script_spike(70)`, Stalker budzi się i idzie na źródło, podpowiedź uczy Q; ekstrakcja na początek mapy. (3) **Cel poboczny** „Uwaga < 40": szczyt Uwagi liczony do ostatniego generatora, wynik na karcie (kept/lost). (4) **Mapa 1.2** 168×44: skraj lasu z pagórkiem → dziedziniec z watahą → chata radiowa (antresola z kuszą, rusztowanie na dach) → wieża widokowa → podziemna hala (generator 2, dom Stalkera, dwa szyby) → maszt z pomostem (generator 3). Wrogowie: Trzoski, Podsłuchacze, Ślepiec, Stalker. (5) **Kampania** gra 1.2 → 1.3 → od nowa ([Enter] na ekranie wyniku); **Nocny Dyżur losuje mapę** każdej misji serii. (6) HUD: tytuł misji w pierwszych sekundach, podpowiedź „Hold [E]" przy generatorze, karta wyniku 1.2; stopka dema tylko na końcu kampanii/serii. (7) Testy: `--maptest` (kształt siatki + osiągalność wszystkich punktów z grafu nawigacji, w obie strony), `--host --mission=z1_m2 --gentest` (cała misja + przejście do 1.3 i z powrotem), `--mission=ID` wybiera mapę startową; testy 1.3 same wymuszają `z1_m3`. Naprawa testów: licznik błędów w lambdach (`--shifttest`, `--gentest`) był kopiowany i zawsze pokazywał 0 — teraz tablica. |
| 1.7.25 | 2026-10-06 | **Misja 1.2 v2: dłuższa i trudniejsza (po uwadze „zbyt krótka i zbyt łatwa").** (1) **Mapa 168 → 288 × 44**: dziedziniec z Wołkiem → chata radiowa (2 Ślepce) → **bagno z szopą** (błoto, staw, 2 Skoczki i Ćma pod dachem, Mimik na rozstaju, Wołek) → wieża widokowa i podziemna hala (Wołek, Ślepiec, 2 Podsłuchacze, dom Stalkera) → **pompownia o dwóch kondygnacjach** (generator na piętrze, Wołek na parterze, Skoczek, Podsłuchacz) → maszt. (2) **4 generatory zamiast 3**, rozrzucone na całej długości; trasa samego marszu ≈ 99 s (było ≈ 57 s), do tego 4 × 5,5 s pracy, walki i czekanie na opadnięcie Uwagi. (3) **Trudność**: wrogów ≈ 30 (było ≈ 12: m.in. 4 Wołki, 4 Ślepce → 3, 6 Podsłuchaczy, Skoczki, Ćma, Mimik; wataha 4 zamiast 3), **HP wrogów ×1,25** na tej mapie (`ENEMY_HP` w danych mapy → `level.hp_mult`), mniej amunicji (5 skrzynek na 288 kolumn), generator **pracuje 5,5 s** (było 4), robi więcej hałasu przy pracy (1,6/s) i przy starcie (+5), a **buczy głośniej i częściej** (0,9 co 4,5 s). (4) `--maptest` liczy teraz szacunek długości trasy start → cele → wyjście. |
| 1.7.26 | 2026-10-06 | **Ucieczka drezyną i kryjówka między misjami (po uwadze „powrót przez całą mapę do flary jest monotonny").** (1) **Drezyna** (`handcar.gd`, znacznik `D`): po nadawaniu w misji 1.2 szyb przy maszcie (kol. 272-277) prowadzi do **głębokiego tunelu** (wiersze 44-51, mapa 288×52), gdzie stoi drezyna; jedzie torem **na zachód do wyjścia** (`E` na końcu tunelu). Napęd: ludzie NA POKŁADZIE **trzymają [E] i pompują** (1 osoba ≈ 95 px/s, 2 ≈ 130; boty na pokładzie dokładają połowę), puszczone E = hamowanie. **Pompujący nie strzela ani nie chodzi** (`player.pumping`) — trzeba wybierać: jechać czy się bronić. Stalker idzie 88 px/s, więc stanie w miejscu oznacza, że ON dogoni. Jazda hałasuje (0,8 co 1,2 s) i budzi śpiących przy torze: 23 wrogów w tunelu (Trzoski, Wołki, Ślepce, 4 Skoczki z sufitu komór, 3 Ćmy, 2 Podsłuchacze). Pozycja liczona na serwerze, klienci całkują ją z replikowanej prędkości (`AnimatableBody2D`, `sync_to_physics`), więc gracz na pokładzie jedzie razem z platformą. Na torze nie ma skrzyń ani beczek (gracz zahaczał o nie i spadał z pokładu — wykrył to `--ridetest`). Cel poboczny i skok Uwagi bez zmian. (2) **Kryjówka** (`z1_hub`, „SAFE ROOM"): po sukcesie kampania prowadzi najpierw do kryjówki (bez wrogów, 3 skrzynki z amunicją, 3 bronie do wymiany, radio z fabułą), a [Enter] hosta rusza do następnej misji; **ekwipunek i amunicja przechodzą** przez kryjówkę (`_restart_mission(..., carry)`, `Player.full_reset(keep_loadout)`); wipe i Nocny Dyżur resetują jak dotąd. (3) Testy: `--ridetest` (zasilenie, wejście, pompowanie, jazda z graczem, dojazd, SUCCESS), `--ridehost` + `--rideclient` (klient pompuje przez sieć), `--gentest` obejmuje kryjówkę i carry. Poza zakresem: dalsza rozbudowa powierzchni mapy, bramy sterowane generatorami, fala posiłków. |
| 1.7.27 | 2026-10-06 | **Kryjówka, etap 1: zbrojownia, tablica z odprawą, światło — i brak wrogów.** (1) **Błąd: wrogowie pojawiali się w kryjówce.** Przyczyna: Dyrektor grozy dosypuje „wędrowców" w każdej fazie OBJECTIVE, a kryjówka jest w niej cały czas. Naprawa w trzech warstwach: `NoiseMgr.safe_zone` (ustawia `level.gd` z celu mapy `hub`, więc u wszystkich peerów) wyłącza spawn Dyrektora, straszaki (`dread.gd`) i liczenie hałasu; test `--gentest` wymusza warunki spawnu i sprawdza, że nikt się nie pojawia (padał przed poprawką). (2) **Zbrojownia**: 6 stojaków (`rack.gd` za każdym „g" przy `RACKS := true`): SPREAD-12, PELLET-8, LR-7, HKM-9, FALCON-6, SINEW-6; **karta statystyk** (obrażenia, tempo, zasięg, magazynek, przeładowanie, hałas + opis z kodeksu) pokazuje się przy broni w zasięgu [E] **tylko w kryjówce** (w misjach zasłaniała grę; tam zostaje pasek „[E] Take…"). Karta wisi **nad stojakiem** (pozycja liczona z kamery, nie zasłania gracza ani broni), broń na stojaku **stoi w miejscu** (`static_display`: bez podskoku przy spawnie i bez bujania), a stojak ma **jedną kołyskę** pod jedną bronią. (3) **Tablica z odprawą** (`board.gd`, znacznik `n`): po podejściu HUD pokazuje cel następnej misji i **zagrożenia policzone ze znaczników jej mapy** (`level.briefing(id)`; nazwy i podpisy z bestiariusza `codex.gd`), np. dla 1.3: Cutpurse ×16, Moth ×7, Leaper ×4, Bullock ×4, … Stalker, 4 gniazda, boss. (4) **Światło**: mapa może mieć własny `AMBIENT` (kryjówka: ciepły i jaśniejszy; `level.ambient`, `dread.gd` używa go jako bazy) oraz lampy (`lamp.gd`, znacznik `l`: wiszą pod sufitem, ciepłe, migoczące). Kryjówka ma 84×44, skrzynki z amunicją i wszystkie nowe elementy są osiągalne (`--maptest`). Baner z radiem chowa się, gdy widać kartę. Poza zakresem etapu 1: gotowość graczy, ściana wyników, strzelnica, taśmy, waluta i warsztat (etapy 2–5). |
| 1.7.28 | 2026-10-07 | **Kryjówka, etap 2: gotowość graczy.** Wyjście na misję nie zależy już od hosta: każdy człowiek przełącza gotowość [Enter]em (boty się nie liczą), a gdy wszyscy są gotowi, po 2 s odliczania drużyna rusza (odznaczenie przez kogokolwiek przerywa; ktoś, kto wyjdzie, przestaje się liczyć). Serwer trzyma stan (`main.gd`: `hub_ready`, RPC `_hub_ready_rpc` / `_hub_state`), HUD pokazuje „n / m ready” i odliczanie. `--gentest` sprawdza: bez gotowości nie ruszamy, gotowość → odliczanie, odznaczenie je przerywa, potem start. Poprawka drezyny: `sync_to_physics = false`, bo bez tego nikt nie był wożony. |
| 1.7.29 | 2026-10-07 | **Kryjówka, etap 3: ściana wyników.** Tablica z kredowymi kreskami (znacznik `v`, `results_wall.gd`): jedna kreska na ukończoną misję kampanii. Podejdź — HUD pokazuje listę (6 ostatnich: misja, czas, upadki, próby, cel poboczny kept/lost) i sumy. Dane w `run_log.gd` (statyczny dziennik, max 8 wpisów); każdy peer zapisuje wynik sam przy zobaczeniu SUCCESS (serwer w `_success`, klient przy zmianie fazy w `_sync`), Nocny Dyżur nie trafia do dziennika. `--gentest` sprawdza, że po 1.2 w kryjówce stoi ściana i ma wpis. |
| 1.7.30 | 2026-10-07 | **Kryjówka, etap 4: strzelnica.** Kryjówka poszerzona do 128 kolumn; na prawym końcu linia strzału „RANGE” (znacznik `r`, `range_line.gd`) i jeden manekin 10 m od niej (bot w strzelnicy staje za strzelającym, nie w linii ognia) (znacznik `t`, `range_target.gd`). Tarcza przyjmuje trafienia jak wróg (grupa `enemies`, `Combat.apply` → `take_hit`), ale pociski i promienie lecą przez nią dalej (`pass`; wybuchowe detonują na niej), nie ginie, nie hałasuje i nie blokuje graczy; głowa liczy się jako crit. Pokazuje unoszące się liczby obrażeń (czerwone: głowa) i podsumowanie serii: suma obrażeń, trafienia, DPS (seria zeruje się po 3 s bez strzału), plus tabliczkę z odległością. Do testowania broni z kryjówki; amunicję trzeba brać ze skrzynek (strzelnica jej nie ogranicza dodatkowo). `--gentest` sprawdza strzelnicę (tarcza, trafienie, nieśmiertelność, crit z głowy). Przy okazji: start w kryjówce z lobby ustawia następną misję (odprawa), a lobby zrefaktoryzowane (tryb SAFE ROOM). |
| 1.7.31 | 2026-10-07 | **Złom, faza A (§10.1).** Autoload `Scrap` (`scrap.gd`): portfel WSPÓLNY dla drużyny (serwer = autorytet, klienci przez sync), dwa stany — `loot` (złom z bieżącej misji, niebezpieczny) i `bank` (portfel). Udana ekstrakcja przenosi łup do banku + bonusy (+30 za misję, +15 cel poboczny, +10 bez upadków); **wipe i restart kasują łup**, bank zostaje (GDD §4). Źródła: wrogowie (35% szansy; Trzosek 2, Wołek 6, Ślepiec 5, Podsłuchacz 4, Mimik 10, Skoczek 5, Ćma 4), skrytki na mapach (znacznik `u`, po 6: 6 szt. w 1.2, 8 w 1.3), Żyła +30. Pierwsze stawki (50%, skrytki po 10, bonus 40) dawały 274 złomu za jedną misję przy pełnym wyczyszczeniu — za dużo, obniżone do ok. 130–160. Pickup `scrap` zbiera każdy żywy gracz (też bot). Zapis banku u hosta w `user://progress.cfg` (testy headless nie czytają ani nie piszą zapisu). Nocny Dyżur nie daje złomu. HUD: „SCRAP bank +łup” pod zegarem; karta wyniku „Scrap banked”; ściana wyników ma kolumnę SCRAP i sumę. Stałe balansu w jednym miejscu (`scrap.gd`). `--gentest`: pickup, kasowanie łupu, skrytki na mapie, bankowanie po misji, wpis w dzienniku. Faza B (warsztat, odblokowanie broni) i C (ulepszenia) — w planie. |
| 1.7.32 | 2026-10-07 | **Złom, faza B: warsztat i zablokowane stojaki.** W kryjówce (prawa strona, przed strzelnicą) stoi ława (`workshop.gd`, znacznik `h`): [E] otwiera panel zakupów (`workshop_ui.gd`) — lista 6 broni ze stojaków, ceny, podgląd statystyk wybranej, portfel; sterowanie ↑/↓ (W/S), Enter kupuje, Esc/E/Backspace zamyka (na czas panelu akcje gry są wycięte, świat idzie dalej; panel zamyka się po odejściu od ławy). Odblokowane od początku: M-83, P-64, maczeta. **Do kupienia:** SPREAD-12 150, LR-7 200, HKM-9 250 scrap (stałe `Scrap.PRICES`). PELLET-8, FALCON-6 i SINEW-6 zostają zablokowane („later zone”). Zablokowany stojak: broń przyciemniona z kłódką i ceną na tabliczce, karta statystyk z dopiskiem LOCKED, pasek „LOCKED · N scrap at the workshop”, [E] nie bierze broni; serwer odrzuca podniesienie (`level.is_locked_item`). Zakup przez serwer (`Scrap.request_buy` → `_buy_server`: poor / owned / later / ok), portfel i odblokowania replikowane do klientów, zapis w `user://progress.cfg` (sekcja `workshop`). Broń znaleziona w misji (nie ze stojaka) nie podlega blokadzie. `--gentest`: ława i panel, 6 zablokowanych stojaków, scenariusz zakupu (za mało / późniejsza strefa / ok / już kupione), odblokowanie stojaka. Poprawka testu złomu (pickup bez losowego podskoku). Faza C (ulepszenia broni) w planie. |
| 1.7.33 | 2026-10-07 | **Złom, faza C: ulepszenia broni (§6.4).** Trzy poziomy na broń (M-83, P-64, SPREAD-12, PELLET-8, LR-7, HKM-9), ceny 60 / 120 / 220 scrap za kolejny poziom (`Upgrades.COSTS`), kupowane w tym samym panelu warsztatu: Enter na odblokowanej broni kupuje następny poziom, na zablokowanej — samą broń. Panel pokazuje poziom (TIER n / 3, MAX), statystyki aktualnej wersji i opis następnego poziomu z ceną. Tabela w `upgrades.gd` (modyfikatory `[pole, mul|add, wartość]`, poziomy się kumulują): m.in. M-83 — magazynek +10 / +15% obrażeń i szybsze przeładowanie / tłumik (hałas −30…40%); SPREAD-12 — mniejszy rozrzut / dłuższa lufa; LR-7 — +20% obrażeń / +1 przebicie; HKM-9 — +25% obrażeń i dłuższe podpalenie / +30% zasięgu. Poziomy wspólne dla drużyny, replikowane (`Scrap._sync`) i zapisywane u hosta (`progress.cfg`, `workshop/levels`). **`Weapons.def(id)` zwraca teraz definicję z ulepszeniami** (cache id × poziom; `Weapons.base_def` = bez ulepszeń), więc kontroler, pociski, HUD i karty stojaków czytają nowe statystyki bez zmian po swojej stronie. **Korekta cen broni (faza B):** SPREAD-12 jest bronią startową gracza, więc przestaje być do kupienia — odblokowany od początku; do kupienia LR-7 150, HKM-9 200, PELLET-8 250; FALCON-6 i SINEW-6 zostają „later zone”. `--gentest`: poor/locked/invalid/ok/max, statystyki M-83 po T3, baza nietknięta; `--weapontest` 70/70. |
| 1.7.34 | 2026-10-07 | **Katalog broni (menu pauzy → WEAPONS) pokazuje tiery.** Wpis broni liczy się świeżo przy każdym wyborze i po otwarciu zakładki (`Codex.weapon_entry`): statystyki z ulepszeniami drużyny, w tagu „TIER n / 3”, sekcja UPGRADES z trzema poziomami (nazwa, efekt, koszt; zielony = zainstalowany, złoty = następny, szary = dalszy) oraz czerwona linia dostępu dla zablokowanej broni („Locked — 150 scrap at the workshop” / „later zone”). Panel szczegółów jest przewijany. |
| 1.7.35 | 2026-10-07 | **Misja 1.1 „Zaginiony Patrol”, faza A (rdzeń celu, mapa „na szaro”).** Nowy rodzaj celu `tags` (`OBJECTIVE := "tags"` w danych mapy): znajdź 3 nieśmiertelniki → od razu EXTRACT (bez bossa), wyjście `E` na początku mapy. Przedmiot `tag` (pickup.gd, znacznik `F` na mapie): dotknięcie przez dowolnego żywego gracza (też bota) woła `mission.on_tag_taken()` (serwer; licznik idzie istniejącym `goal_left/goal_total` przez `_sync`, więc bez nowego RPC), wraca po wipe razem z przedmiotami z mapy. Mapa `maps/z1_m1.gd` (200 × 44): start i wyjście → polana z ogniskiem (nieśmiertelnik 1, 3 Trzoski) → przesmyk pod skalnym sufitem (nr 2, uśpiona wataha + Wołek) → kopalnia: rampa w dół i sala w ciemności (nr 3, Wołek + Trzoski); 9 Trzosków, 2 Wołki, 3 skrytki złomu (`u`), trasa samego marszu ≈ 60 s (`--maptest` liczy nieśmiertelniki jako cele). HUD: tekst celu i podpowiedź dla `tags`, karta wyniku (czas, nieśmiertelniki, upadki, próba, złom), „DOG TAG ×3” w odprawie przy tablicy (`briefing()["tags"]`). Test `--host --mission=z1_m1 --tagtest`: zbieranie, wipe (nieśmiertelniki wracają), EXTRACT, SUCCESS, złom z bonusu, dziennik. Do zrobienia: B (rozstawienie i samouczek ciszy/latarki), C (cel poboczny: 2 ukryte skrytki), D (kolejność kampanii, pula Nocnego Dyżuru). |
| 1.7.36 | 2026-10-07 | **Misja 1.1, faza B: samouczek ciszy i latarki.** Mechanika (z kodu wrogów): uśpiony wróg budzi się od hałasu ≥ 0,5 w promieniu słyszenia, od snopa latarki i gdy gracz podejdzie bliżej niż `wake_near` (Trzosek 90 px, Wołek 70 px — **kucający tylko połowę**, a odległość jest euklidesowa, więc różnica poziomów się liczy); kroki (0,25) nie budzą, ale kucanie ich nie robi wcale, a Uwaga opada 4/s po 1,5 s ciszy (chodzenie wyprostowane: 1,5/s). Układ: **polana** (4 Trzoski wokół pierwszego nieśmiertelnika — strzelasz, słyszysz hałas) → **jaskinia** pod skalnym sufitem, w której Trzoski i Wołek **śpią na półkach 4 kafle (64 px) nad ścieżką** (jednokierunkowe platformy z podestem 2 kafle wyżej, osiągalne dla grafu nawigacji): wyprostowany pod półką budzisz je, kucający (45 px < 64) nie — lekcja ciszy bez żadnego skryptu; **kopalnia** (rampa w dół, ciemna sala: Wołek i 3 Trzoski na podłodze, latarka widzi, ale budzi). Podpowiedzi (`hints.gd`): `sneak` (śpiący wróg < 130 px, a gracz stoi wyprostowany), `quiet` (Uwaga 22–60 %, nic aktywnego w 420 px), `light` także po zejściu do podziemi bez latarki. Radio patrolu w pierwszych sekundach (`RADIO` mapy). Test `--host --mission=z1_m1 --sneaktest`: Trzosek na półce śpi przy kucającym graczu pod nim, budzi się od wyprostowanego; podpowiedzi quiet i light łapią swoje warunki. Zauważone: bot kopiuje kucanie lidera, więc skrada się razem z graczem; wyprostowany bot obok śpiących je budzi. |
| 1.7.37 | 2026-10-07 | **Flara ekstrakcji — nowy rysunek (`mission._draw`).** Wbita w ziemię czerwona tuba z jasnym paskiem i kamykami u podstawy, płomień w trzech warstwach (zielony zewnętrzny, jasny środek, biały rdzeń) z niezależnym migotaniem, halo wokół płomienia, iskry i dym unoszące się ze stałymi fazami (bez losowania co klatkę), słup światła jako gradient (podstawa → przezroczysty czubek) z jaśniejszym rdzeniem, eliptyczna poświata na ziemi w trzech warstwach i pulsujący pierścień, strefa ewakuacji jako animowana przerywana linia z wspornikami na krawędziach, pasek postępu w ramce z podziałką. Same światło i jego energia bez zmian. |
| 1.7.38 | 2026-10-07 | **Finał misji 1.1, etap E1: zawał w trakcie misji (mechanizm).** Po trzecim nieśmiertelniku, gdy mapa ma dane finału, kopalnia „budzi się": `mission._start_finale` — wstrząs (`rumble`: Feel.shake + dźwięk), skok Uwagi (`FINALE_NOISE` 14) i wyjście przenosi się na znacznik **`e`** (`level.exits_alt`), a po `FINALE_DELAY` 2,5 s następuje **zawał** (`collapse`: wstrząs mocniejszy, hitstop). Zawał nie rani — zamienia wskazane obszary mapy (`const COLLAPSE := [[c0, r0, c1, r1]]` w danych mapy) w skałę. **Zmiana kafli w trakcie gry** (`level.gd`): `collapse()` (serwer) → RPC `_collapse_rpc` u wszystkich peerów (`_map` jest teraz kopią danych, `_orig_map` zostaje), `_place_cell` wydzielone z `_build_map`, `_refresh_region` odświeża kafle z ramką (okluzja ścian) i **przebudowuje graf nawigacji** (boty i wrogowie nie szukają drogi przez skałę), gracze (własni na danym peerze) uwięzieni w obszarze trafiają tuż za skałę (`_push_players_out`, jak przy drezynie), dołączający w trakcie dostają zastosowane zawały (`send_collapse_to`), a restart misji cofa mapę (`reset_collapse`). Stan `finale` replikuje `mission._sync`; podpowiedź „The mine is coming down — find another way out!”. **Mapa 1.1 nie ma jeszcze danych finału** (COLLAPSE ani `e`), więc misja gra się jak dotąd; szyb ucieczki i wschodnia flara to etap E2. Test `--host --mission=z1_m1 --finaletest` wstrzykuje dane w locie: rampa wolna → 3 nieśmiertelniki → finał → zawał (skała, graf bez drogi, uwięziony gracz za skałą) → sukces przy nowym wyjściu → restart cofa zawał. |
| 1.7.39 | 2026-10-07 | **Finał misji 1.1, etap E2: szyb wentylacyjny i druga flara.** Mapa `z1_m1` dostaje dane finału (`COLLAPSE := [[150, 33, 157, 41]]`: dolna część rampy) i znacznik `e` — flarę na powierzchni przy wschodnim końcu sali. Sala kopalni sięga teraz do kol. 191, a za nią biegnie **szyb** (kol. 192-196, rzędy 31-41): pionowa wspinaczka po pięciu jednokierunkowych podestach, naprzemiennie przy lewej i prawej ścianie, co 2 kafle w górę (zakres skoku grafu), ostatni podest o 1 kafel pod powierzchnią. Pod sufitem sali **2 Skoczki i 2 Ćmy** (budzi je wstrząs finału i światło latarki — Ćmy to lekcja „światło przyciąga”). Po trzecim nieśmiertelniku: wstrząs → zawał rampy po 2,5 s → drużyna wspina się szybem przez obudzoną salę do flary `e`; startowa flara (`E`) zostaje tylko jako zapas dla wyboru wyjścia. Szacunek `--maptest` trasy: ≈ 34 s samego marszu (poprzednio 60 s z powrotem na start) — w praktyce dłużej przez walkę i skradanie. `--maptest` liczy wyjście po zawale jako cel (osiągalne ze startu i z powrotem). `--finaletest` używa już danych z mapy (bez wstrzykiwania): zawał nie zmienia drogi z sali do flary (ścieżka szybem, 33 węzły), a trasa na rampę po zawale nie przechodzi przez zablokowane kafle. `--tagtest` oczekuje wyjścia przy szybie. Do zrobienia: E3 (końcowe radio patrolu, mała fala przy ewakuacji, strojenie). |
| 1.7.40 | 2026-10-07 | **Misja 1.1, faza D: integracja z kampanią.** `Level.CAMPAIGN = [z1_m1, z1_m2, z1_m3]`: nowa kampania zaczyna się od 1.1 (także start w kryjówce z lobby: odprawa i „Depart” prowadzą do 1.1), a po 1.3 kampania wraca przez kryjówkę do 1.1. Nocny Dyżur losuje mapy z osobnej puli `Level.SHIFT_POOL = [z1_m2, z1_m3]` — samouczek bez bossa i Stalkera zaniżałby trudność serii. Stopka dema nadal pojawia się po ostatniej misji kampanii (1.3). Testy: `--gentest` (po 1.3 hub → 1.1, kolejność kampanii, pula Nocnego Dyżuru), `--tagtest` (po 1.1 [Enter] → kryjówka → 1.2). Test Nocnego Dyżuru wymaga flagi `--nightshift --host --shifttest`. |
| 1.7.41 | 2026-10-07 | **Finał misji 1.1, etap E3: radio patrolu.** **Ostatnia transmisja** (`mission.FINALE_RADIO`): przez 12,5 s od startu finału HUD pokazuje zamiast tytułu „PATROL SEVEN — RADIO” i kolejne linie (0 s: „you found our tags”; 3 s: „it was never the woods listening — it's the mine”; 6 s: „don't go back up the ramp, there's an old shaft on the east side”; 9 s: „keep the light off, stay quiet, the flare is at the top… run”) — zegar `finale_clock` liczy każdy peer lokalnie od zreplikowanej flagi `finale`, linię daje czysta funkcja `radio_line_at(t)`. Podpowiedź finału: „Climb the shaft to the flare!”. (Pierwotnie E3 miało też falę wrogów przy flarze — **usunięta** po uwadze, że jest zbędna: `Director.spawn_wave` i jej test wyleciały.) |
| 1.7.42 | 2026-10-07 | **Misja 1.1: rozbudowane podziemia.** Mapa `z1_m1` urosła z 44 do 56 wierszy: pod salą kopalni jest **dolna galeria** (kol. 140–187, rzędy 46–50), dostępna **szybem serwisowym** w podłodze sali (kol. 168–171; wspinaczka po czterech jednokierunkowych podestach co 2 kafle, jak szyb ucieczki). Galerię dzielą stalaktyty, w ślepych końcach leżą skrytki złomu i skrzynka z amunicją, a pilnują jej 3 Trzoski, Wołek, 2 Ćmy (budzi je światło) i 2 Skoczki — opcjonalna eksploracja w ciemności, osobna od głównej trasy (trzeci nieśmiertelnik i finał bez zmian; Trzosek z sali przesunięty, bo stał nad otworem). Skrytek złomu na mapie: 5. `--maptest` potwierdza osiągalność wszystkiego i powrót, `--tagtest` sprawdza galerię (wrogowie, skrytki, droga szybem). Miejsce na przyszły cel poboczny (faza C: dwie ukryte skrytki). |
| 1.7.43 | 2026-10-07 | **Kryjówka przebudowana + naprawa czarnych kwadratów.** (1) **Czarne kwadraty** to kafle tła bez tekstury pod znacznikami stojącymi obok innych znaczników: tło dziedziczył tylko znacznik z sąsiadem-tłem po lewej, a przy `kk` / `ak` / `Sbb` drugi znacznik zostawał dziurą. `level._place_cell` szuka teraz tła w lewo ponad sąsiednimi znacznikami (do 8 kafli) — poprawia też inne mapy. (2) **Układ strefami** od lewej, w kolejności „co robi drużyna po powrocie”: wejście (2 punkty startu) → ściana wyników → warsztat → zbrojownia (6 stojaków co 7 kafli, od startowych po zablokowane; skrzynki z amunicją na obu końcach) → tablica z odprawą → strzelnica (linia i tarcza 10 m); lampy równomiernie co 12 kafli. **Pudła (`k`) usunięte** — pusta podłoga to droga. (3) **Narzędzie deweloperskie** `--shot=ścieżka.png [--shotat=kolumna]`: po 2,5 s zapisuje obraz z widoku gry (tylko okno gry, bez pulpitu) i kończy; `--shotat` przenosi gracza na podłogę w danej kolumnie — do oglądania stref bez zrzutów ekranu. |
| 1.7.44 | 2026-10-07 | **UI w stylu gry, faza 1 (szkielet).** Nowy język wizualny całego interfejsu: panele (HUD, lobby, menu pauzy, warsztat) to ciepłe, ciemne „deski” z mosiężną krawędzią i grubszą dolną krawędzią, **bez zaokrągleń i cieni** (`UiTheme.panel_box`, przyciski i pola też o ostrych rogach); nagłówki w **pikselowej czcionce Silkscreen** (SIL OFL, `art/fonts/`, import bez antyaliasingu i hintingu; `UiTheme.heading()`, rozmiary wielokrotności 8) — tytuł lobby, NOISE / SQUAD / OBJECTIVE, nazwa bossa, TIP, ostrzeżenia, banery, karta wyniku, warsztat; tekst opisowy zostaje w czytelnej czcionce motywu. **Karty obiektów świata** (broń na stojaku, odprawa) to papier z tekstem tuszem i **ogonkiem** wskazującym obiekt (`TailPanel`, `UiTheme.paper_box`). **Tryb kryjówki HUD-a:** miernik hałasu (zawsze 0%) zastąpiony znacznikiem SAFE; karta celu to pasek „Next: <misja>” z kwadracikami gotowości (jeden na człowieka, `Pips` kształt `ready`) i podpowiedzią „Ready up · n / m ready”; portfel złomu jako moneta z liczbą. Dalsze fazy: 2 (ściana wyników kredą na obiekcie świata, odprawa), 3 (warsztat: siatka broni z ikonami, statystyki przed/po, mysz), 4 (dopracowanie pozostałych elementów HUD-a). |
| 1.7.45 | 2026-10-07 | **Błąd: po wyjściu z kryjówki do misji świat był prawie czarny, a postacie wyglądały jak ciemne kwadraty.** Przyczyna: wyjście wołano z kroku fizyki (`_hub_server_tick` w `_physics_process`), a przebudowa mapy w locie (`level.load_map`: usunięcie i utworzenie węzłów, świateł i warstw kafli) w ticku fizyki psuje rysowanie — to samo wywołane z klatki zwykłej (coroutine testów) działało. Naprawa: wyjście z kryjówki (`_depart_hub`, z flagą `_departing`, żeby nie wołać co tick) i przejście po ekranie wyniku (`_continue_after_result`) są odroczone (`call_deferred`) poza krok fizyki. Narzędzie `--shot` dostało `--shotdepart` (gotowość jak [Enter] w kryjówce → odliczanie → wyjście), `--shotdelay=S` i `--shotflicker` do odtwarzania takich przypadków. |
| 1.7.46 | 2026-10-07 | **UI w stylu gry, faza 2: ściana wyników kredą i odprawa.** (1) **Ściana wyników** nie ma już karty w HUD-zie — treść jest rysowana kredą na tablicy w świecie (`results_wall.gd`, powiększona do 116×66): nagłówek „RESULTS” z liczbą misji, cztery ostatnie wiersze (numer misji, czas, upadki — czerwone, gdy > 0 — i złoty złom), kreski za wszystkie misje w grupach po pięć i łączny czas; pusta tablica pokazuje „NO MISSIONS YET”; kreda jaśnieje, gdy gracz stoi przy tablicy; pikselowa czcionka nagłówków. (2) **Odprawa** (przypięta kartka): czerwona pinezka na górnej krawędzi (`TailPanel.pin`), kolorowe znaczniki wrogów w kolejnej kolumnie (kolor rodzaju z `Enemy.KINDS`, `Swatch`), cztery kolumny zamiast trzech. Narzędzie `--shotdemo` (przykładowe wpisy dziennika do podglądu tablicy). |
| 1.7.47 | 2026-10-07 | **UI w stylu gry, faza 3: warsztat jako szkic techniczny.** Panel (`workshop_ui.gd`) przebudowany: ciemny błękitno-zielony arkusz z jasnymi liniami (`UiTheme.blueprint_box`, `tile_box`), po lewej **siatka 2×4 kafli broni** (miniatura `GunIcon`, nazwa, trzy kwadraciki poziomu ulepszeń albo moneta z ceną; „LATER ZONE” dla zablokowanych do późniejszych stref; wybrany kafel w bursztynowej ramce), po prawej **szczegóły**: duża miniatura, nazwa, statystyki **„teraz » po zakupie”** (zmieniona wartość zielona; podgląd z `Weapons.def_at(id, poziom + 1)`), lista trzech poziomów (zainstalowany / następny / dalszy) i przycisk akcji (kup / ulepsz / maks.). **Mysz**: kafel wybiera, przycisk kupuje (kursor widoczny na czas panelu, potem przywracany); klawiatura: strzałki / WASD po siatce, Enter lub Spacja akcja, Esc / E / Backspace zamyka. Zasada typografii: **pikselowej czcionki nie używamy do liczb i drobnych nazw** (przy małym rozmiarze mylą się 8 i 3) — tylko nagłówki i słowa; wallet, ceny i nazwy broni w kaflach zwykłą czcionką (to samo w liczniku złomu w HUD-zie). Test `--gentest`: otwarcie panelu przy ławie, 8 kafli, kliknięcie kafla, mysz i zamknięcie. Narzędzie `--shotws` (podgląd panelu z przykładowym portfelem i ulepszeniami, bez zapisu). |
| 1.7.48 | 2026-10-07 | **UI w stylu gry, faza 4: reszta HUD-a.** (1) **Serca w pixel arcie** (`Pips`, 9×8 px z ciemnym obrysem i pikselem odblasku) zamiast gładkich kół i trójkąta; (2) **paski „diodowe”** (`Bar.seg`): miernik hałasu (bloki 3 px z 1-pikselową przerwą, progi 30/40/60 jak dotąd) i pasek bossa (4 px) zamiast jednolitych belek; (3) **magazynek** pikselową czcionką w rozmiarze 24 (cyfry w tej czcionce są czytelne od 16 w górę; drobne liczby zostają zwykłą czcionką), pasek broni lekko zagęszczony (odstępy 7, miniatura 50 px), żeby nie zachodził na kartę drużyny; (4) karta wyniku, drużyny, celu, podpowiedzi i ostrzeżenia dziedziczą nowy panel i nagłówki z faz 1–2. Narzędzie `--shotresult` (podgląd karty wyniku). Cały plan UI (fazy 1–4): ostre panele i pikselowe nagłówki, papier z ogonkiem przy obiektach, kreda na tablicy wyników, warsztat jako szkic, pixel-artowe serca i paski. |
| 1.7.49 | 2026-10-07 | **Błąd: przedmioty (apteczki, amunicja, broń) wpadały w ścianę i były nie do podniesienia.** Pickup (`pickup.gd`) nie miał ciała fizycznego, tylko ruch po paraboli z losowym dryfem ±40 px/s, więc podskok przy ścianie przenosił go w skałę. Poprawki: (1) w locie promień poziomy przed każdym krokiem — ściana zatrzymuje dryf; (2) podłoga szukana pod nowym punktem w każdej klatce, a nie raz pod punktem startu; (3) przedmiot zaczęty w bryle (wróg zginął przy ścianie) jest wypychany w bok na najbliższe wolne miejsce (`_unstick`); (4) dryf liczony deterministycznie z nazwy węzła, więc ląduje w tym samym miejscu u wszystkich peerów (wcześniej `randf` na każdym peerze osobno). Test w `--tagtest`: podskok w skałę zatrzymany, przedmiot zaczęty w skale wypchnięty. Przedmioty już leżące w bryle po starej wersji znikają przy restarcie misji (`clear_pickups`). |
| 1.7.50 | 2026-10-07 | **Misja 1.1, faza C: cel poboczny — dwie ukryte skrytki.** Znacznik mapy `H` → pickup `stash` (zakopany worek ze złotym połyskiem, słabe światło — trzeba na niego trafić): zbiera go każdy żywy gracz; wartość `Scrap.STASH_VALUE` 20 trafia do łupu, a `mission.on_stash_found()` zalicza licznik (`stashes_found / stash_total`, replikowane przez `_sync`). **Komplet skrytek = cel poboczny** (`mission.side_done()`; dla 1.2 nadal „cicho”, dla innych misji brak): +`BONUS_SIDE` 15 złomu przy ekstrakcji i wpis `side=1` w dzienniku. Rozmieszczenie: **A** — półka nad polaną, schodki z jednokierunkowych podestów co 2 kafle (wejście w kadr startu, ale poza główną trasą); **B** — wnęka w stropie jaskini nad półką ze śpiącym Wołkiem (do niej trzeba się skradać obok niego; strop podniesiony o 3 rzędy, żeby graf nawigacji dopuścił skok). Podpowiedź celu: „side goal: 2 hidden stashes (n / 2)”, karta wyniku: „Hidden stashes n / 2 — bonus”, odprawa: „STASH x2 — side goal, hidden”. `--maptest` liczy skrytki jako cele (osiągalne ze startu i z powrotem), `--tagtest` zbiera obie i sprawdza łup, licznik, bonus i dziennik. Misja 1.1 ma teraz komplet celów z GDD §9 (3 nieśmiertelniki + 2 skrytki). |
| 1.7.51 | 2026-10-07 | **Boss B1 „Pijawka”, faza A (rdzeń walki).** Nowa misja `z1_b1` (140 × 44, `maps/z1_b1.gd`, `OBJECTIVE := "boss"`): zalana hala z płytkim basenem (kafle `~`, kolumny `POOL`), trzy kładki nad wodą (rząd 27) i kładki pośrednie, suche brzegi ze startem i ewakuacją, skrzynki z flarami (`f`: pickup `flares`, +2 flary do puli, o ile nie pełna) na brzegach i kładkach B/C, skrzynki z amunicją i skrytki złomu. **Pijawka** (`leech.gd`, marker `K`): zanurzona i niewidoczna; jej cień ujawnia flara w promieniu 150 px albo snop latarki; **zanurzona w ciemności dostaje 5% obrażeń, odsłonięta (w świetle albo wynurzona) 100%**. Płynie pod najbliższym graczem stojącym w wodzie (tempo 105/140/175 px/s w fazach), pod nim robi zapowiedź (kręgi, 0,85 s → 0,55 s), wynurza się, rani 1 HP i zostaje odsłonięta (1,7 s → 1,3 s); gracz na kładce nad wodą jest poza zasięgiem. HP 600 (+200 za każdego dodatkowego człowieka), fazy przy 66% i 33% (tempo i cooldowny), śmierć: apteczki, złom, ekstrakcja. Interfejs jak u Żyły (`hp`/`max_hp`/`phase`/`died`, `boss_name`/`boss_hint`), więc pasek bossa i misja działają; do tego pola „udawanego wroga” (`kind`, `winding`, `alive`, `active`) — bez nich boty rzucały błąd co klatkę przy unikach. **Misja `boss`** (`mission.gd`): walka zaczyna się, gdy człowiek podejdzie do basenu (160 px od jego początku) albo po 40 s; teksty celu i podpowiedzi, odprawa „THE LEECH”. Rysowanie proceduralne (kręgi na wodzie, cień z oczami, segmentowy tułów z paszczą). Test `--host --mission=z1_b1 --leechtest`: 5% / 100%, zasadzka, bezpieczna kładka, fazy, skrzynka z flarami, śmierć → ekstrakcja → sukces; `--maptest` obejmuje arenę. Narzędzie `--shotboss`. Do zrobienia: B (chwyt i QTE), C (Trzoski i faza 3), D (kampania, odprawa, szlif). |
| 1.7.52 | 2026-10-07 | **Boss B1 „Pijawka”, faza B: chwyt i QTE drużyny.** Zasadzka kończy się teraz **chwytem**: gryzie wszystkich w zasięgu (1 HP), a najbliższego gracza (człowiek przed botem przy remisie) łapie — tryb `GRAB`: ofiara jest **przypięta** przy pysku (`Player.grabbed`, `deliver_grab` → właściciel postaci; nie chodzi i nie skacze, ale może strzelać i bić), Pijawka jest odsłonięta i wciąga ją przez `GRAB_TIME` 4 s. **Uwolnienie przez obrażenia:** drużyna musi zadać `GRAB_FRAC` 12% maks. HP Pijawki w tym oknie (liczą się trafienia wszystkich, **cios chwyconego w zwarciu — podwójnie**); wtedy Pijawka puszcza, cofa się o 60 px i zanurza z przerwą `GRAB_CD` (3,0 / 2,4 / 1,8 s). Gdy okno minie bez uwolnienia, ofiara jest **wciągnięta pod wodę** — trafia do stanu „down” (można ją podnieść jak zwykle). Śmierć Pijawki, reset misji albo śmierć ofiary z innej przyczyny puszczają chwyt. HUD (ofiara i koledzy widzą to samo): pasek „GRABBED — shoot the leech to break free · Ns” / „Teammate grabbed — shoot the leech! · Ns” z postępem uwolnienia; stan chwytu (`grab_victim_id`, `grab_progress`, `grab_time_left`) replikuje `_sync`. Boty strzelają do wynurzonej Pijawki jak do zwykłego wroga. Dźwięki i wstrząsy: chwyt / uwolnienie / wciągnięcie. `--leechtest` (12 sprawdzeń): chwyt z przypięciem, QTE udane (13% HP), QTE nieudane (down), cios chwyconego liczony podwójnie. Do zrobienia: C (Trzoski z brzegów, podwójna zasadzka i krzyk w fazie 3), D (kampania, odprawa, szlif). |
| 1.7.53 | 2026-10-07 | **Boss B1 „Pijawka”, faza C: Trzoski z brzegów, krzyk i podwójna zasadzka.** **Faza 2** (< 66% HP): po przejściu progu para Trzosków wychodzi na brzegach basenu (zachodni i wschodni naprzemiennie), potem dosyłanie co 16 s do limitu 3 żywych (+1 za dodatkowego człowieka); to wsparcie bossa, więc `omniscient` — wiedzą, gdzie są gracze (nazwy `LeechSpawn*`, RPC `_spawn_minion`, sprzątane przy resecie i śmierci Pijawki). **Faza 3** (< 33%): **krzyk** — Uwaga na maksimum (`NoiseMgr.MAX_LEVEL`), światła graczy migoczą (`Lights.flicker_until_ms`), trzy kolejne Trzoski, dosyłanie co 10 s do limitu 4; **podwójna zasadzka**: podczas zapowiedzi Pijawka wyznacza **drugi punkt** (inny gracz w wodzie co najmniej 40 px dalej, a gdy go nie ma — punkt 70–130 px od pierwszego), na którym też rysują się kręgi (`second_x`, replikowane); przy wynurzeniu gryzie także tam (1 HP, bez chwytu — chwyta tylko pierwszy punkt). Śmierć bossa kończy walkę także z Trzoskami (padają razem z nim). `--leechtest` (14 sprawdzeń): Trzoski w fazie 2, krzyk i Trzoski w fazie 3, drugi punkt zasadzki, sprzątanie po śmierci. Do zrobienia: D (B1 jako czwarta misja kampanii, odprawa w kryjówce, szlif dźwięków i efektów, ewentualnie sprite). |
| 1.7.54 | 2026-10-07 | **Boss B1 „Pijawka”, faza D: integracja z kampanią.** `Level.CAMPAIGN = [z1_m1, z1_m2, z1_m3, z1_b1]`: boss zamyka Strefę I, po nim kampania wraca przez kryjówkę do 1.1; Nocny Dyżur nadal losuje tylko z 1.2 i 1.3 (bez samouczka i bez areny bossa). Odprawa przy tablicy w kryjówce pokazuje „B1 THE LEECH” z wierszem bossa i opisem „hides under water”; karta wyniku bossa „THE LEECH IS DEAD” (czas, boss pokonany, upadki, próba, złom) i stopka dema po ostatniej misji kampanii (teraz B1). Szlif: **plusk wody** (`Vfx.splash`) przy wynurzeniu, zanurzeniu, drugim punkcie zasadzki i wciągnięciu pod wodę. Rysowanie bossa zostaje proceduralne (sprite pixel-artowy w `tools/` — do zrobienia osobno). `--gentest`: po 1.3 kryjówka z B1, odprawa B1, wejście w arenę, po B1 kryjówka → 1.1. Zadanie z GDD „Strefa I kompletna (3 misje + boss)” jest wykonane. |
| 1.7.55 | 2026-10-07 | **Bestiariusz: wpis „THE LEECH”.** Menu pauzy → BESTIARY ma nowy wpis bossa (po Żyle): „Boss — hides under water”, statystyki liczone z kodu (`leech.gd`: HP 600 +200 za dodatkowego gracza, 5% pod wodą w ciemności, pełne obrażenia w świetle i wynurzona, chwyt 4 s i uwolnienie 12% HP, fazy 2 i 3), opis zachowania i wskazówka (flara / latarka, strzelać do wynurzonej, drużyna przy chwycie, cios chwyconego liczy się podwójnie). Nowy typ portretu `leech` (`codex_portrait.gd`): animowany cykl 6 s — kręgi i cień pod wodą, wynurzenie, otwarta paszcza, zanurzenie; ta sama animacja w miniaturze listy. Narzędzie `--shotcodex` (podgląd bestiariusza z ostatnim wpisem). |
| 1.7.56 | 2026-10-07 | **Sprite Pijawki.** Nowy arkusz `art/sprites/leech.png` (+ `_glow`, 192×160 px, gęstość 2×, skala 0,5) z `tools/char_leech.py` na silniku postaci (`char_art`): segmentowy tułów z jaśniejszym brzuchem i śluzem, głowa minogi z okrągłą przyssawką i dwoma kręgami zębów, piana przy linii wody; warstwa glow = blade oczy i żar w gardle. Animacje: `rise` (wynurzenie, 4 kl.), `idle` (kołysanie, 6), `grab` (głowa nisko, paszcza szeroko, 3), `dead` (1). `leech.gd` rysuje wynurzoną Pijawkę z arkusza (obrót twarzą do najbliższego gracza albo chwyconej ofiary, biały błysk po trafieniu, mocniejszy blask oczu w fazach 2–3, hitbox wyższy o 14 px); kręgi i cień pod wodą nadal proceduralne, a gdy brak arkusza działa dawny rysunek zastępczy. `bake_sprites.py --only=leech` przepieka wyłącznie wskazane arkusze (reszta PNG nietknięta). Portret w bestiariuszu (`codex_portrait.gd`) też korzysta z arkusza: ten sam 6-sekundowy cykl (kręgi, cień, wynurzenie od góry, szeroka paszcza), a bez arkusza wraca rysunek z kodu. Statystyki wpisu THE LEECH skrócone (długie etykiety rozpychały siatkę i portret z tekstem wystawały poza kartę menu). Menu pauzy ma teraz nieprzezroczysty panel (napisy świata — tablice, ściana wyników — przebijały przez opisy bestiariusza). Dev: `--shotboss --shotup` = zrzut z od razu wynurzoną Pijawką. |
| 1.7.57 | 2026-10-07 | **Przegląd broni, faza 1 (dane).** Analiza: hałas na jednostkę DPS różnił się ~100× (LR-7 0,03 wobec M-83 0,18 i FALCON-6 0,30), SPECTER-1 i WRATH-4 były nieosiągalne, PELLET-8 i FALCON-6 zdominowane, strefa głowy tylko u Wołka. Zmiany: **WRATH-4** (300) i **SPECTER-1** (400, trofeum po Pijawce — `Scrap.REWARDS`, `trophies` zapisane i zsynchronizowane) w warsztacie, hub ma 8 stojaków (mapa z1_hub), panel warsztatu 10 kafli (etykiety „BOSS REWARD” / „LATER ZONE”). **LR-7**: bazowe przebicie 1 (2 cele), ćmy lecą na wiązkę. **PELLET-8**: 10 na śrucinę, ogłuszenie 0,5 s. **FALCON-6**: 10 na rakietę, naprowadzanie woli ćmę, skoczka i podsłuchacza. **Strefy głowy**: Ślepiec, Podsłuchacz, Mimik. **Pancerz Wołka** −3 na kulę/wiązkę (min. 40%, znacznik ARMOR; ogień i wybuchy bez zmian). Bestiariusz: statystyki „Armor” i „Weak spot”, opisy LR-7 / FALCON-6 / Wołka. `--weapontest` +12 sprawdzeń (82/82), szczegóły w `WEAPONS.md` §6. |
| 1.7.58 | 2026-10-07 | **Przegląd broni, faza 2 (ulepszenia).** Wszystkie 12 pozycji ma teraz po 3 poziomy (wcześniej 6): dojechały WRATH-4, FALCON-6, SPECTER-1, SINEW-6, maczeta i kilof; warsztat ma 12 kafli. **Poziom 3 zmienia zachowanie broni** (jak w GDD §6.4): SPREAD-12 podpalająca amunicja (2 s), PELLET-8 pociski ogłuszające (do 1,5 s), WRATH-4 granaty kasetowe (dwie bomby po wybuchu, połowa obrażeń, bez dodatkowego hałasu — `WeaponDef.cluster`), FALCON-6 salwa trzech rakiet za dwa naboje (wolniejsza), SPECTER-1 przebija jedną warstwę ściany (`wall_pierce`), SINEW-6 bełt z hakami (przebija cel, dłuższe ogłuszenie), maczeta „Executioner” (dobija wroga poniżej 35% HP — `WeaponDef.execute_frac`), kilof szeroki łuk i ogłuszenie ≈2,6 s. **Ceny skalowane klasą broni** (`Upgrades.COST_MULT`, bazowo 60/120/220): P-64 i broń biała ×0,8, PELLET-8/LR-7/HKM-9 ×1,2, FALCON-6 ×1,3, WRATH-4/SINEW-6 ×1,5, SPECTER-1 ×1,7. `--weapontest` 96/96 (walidacja tabeli ulepszeń, bomby kasetowe, salwa, szyna przez prawdziwą ścianę, dobicie maczetą); szczegóły w `WEAPONS.md` §7. |
| 1.7.59 | 2026-10-07 | **Przegląd broni, faza 3 (nowe mechaniki).** **Tryb serii M-83** (klawisz **B**, `WeaponDef.burst_*`): jedno naciśnięcie = seria 3 strzałów co 0,07 s i 0,28 s przerwy (przytrzymany spust powtarza serie); strzał o 20% cichszy, lufa grzeje się o 40% wolniej, mniejszy rozrzut — ok. 6,3 hałasu/s wobec 12,8 przy ogniu ciągłym za cenę ok. 20% DPS; HUD pokazuje „M-83 · AUTO / BURST”, podpowiedź w grze, wiersz w liście sterowania. **Ogień na podłodze HKM-9** (`fire_patch.gd`): ciągły płomień co 0,5 s zostawia na podłodze (koniec płomienia / mur, rzut w dół) plamę ognia na 4 s; kto w niej stoi, płonie (Trzoski panikują i uciekają), nie rani drużyny, scala się z sąsiednią, maks. 10 naraz, powstaje u wszystkich peerów (`level.spawn_fire_patch`); ćmy lecą na ogień jak na flarę i się w nim spalają. **Światło broni jako sygnał** (`lights.gd`): strzał o błysku ≥ 1,6 (SPREAD-12, PELLET-8, WRATH-4, SPECTER-1) przez 0,6 s budzi i przyciąga ćmy do strzelca; wiązka LR-7 i płomień HKM-9 (ciche, ale jasne) w zasięgu 10 m i linii wzroku ściągają przebudzonego Stalkera jak latarka. `--weapontest` 108/108 (+12), dev `--shotfire`; szczegóły w `WEAPONS.md` §8. |
| 1.7.60 | 2026-10-07 | **Brakujące elementy przeglądu broni.** **Linka SINEW-6** (poziom 3 „Barbed tether”, `WeaponDef.pull`): trafiony wróg leci ku strzelcowi (260 px/s × `knock_mult`, więc Wołek ledwo drgnie), a od trafienia do strzelca rysuje się linka (`Arsenal.broadcast_tether`); dalej przebija cel i ogłusza. **Zamurowane przejścia i kilof** (`brick_wall.gd`, marker „q”, `WeaponDef.breaks_walls`): ściana z cegieł zajmuje przejście od podłogi do sufitu (do 6 kafli), jest bryłą dla fizyki i nawigacji (nikt nie planuje drogi do skrytki za nią), rozbija ją tylko kilof (~3 uderzenia, 120 HP) albo wybuch WRATH-4; kule i maczeta odbijają się; uderzenie +1,5 hałasu, rozbicie +6 (słychać w całej hali); rozbite ściany synchronizują się z dołączającymi. W misji 1.2 kilof leży przy wieży nad podziemną halą, a skrytka (2 × złom, amunicja) za cegłami w lewej ścianie hali; podpowiedź w grze przy ścianie. **Ogień jako mur**: plama ognia HKM-9 ma ciało na osobnej warstwie fizyki (`FIRE_LAYER`, 40 px — wyżej niż skok wroga), które blokuje wrogów z flagą `fire_shy` (Trzosek, Ślepiec, Skoczek); Wołek, Mimik i gracze przechodzą (przeciwnik pali się, gracza ogień nie rani). `--maptest` otwiera ściany przed sprawdzeniem osiągalności; `--weapontest` 117/117 (+9), `--gentest` sprawdza szczelność i otwarcie skrytki; dev `--shotwall`. |
| 1.7.61 | 2026-10-07 | **Osłabienie LR-7** (zbyt mocna w rozgrywce). Obrażenia 7 → 6 (60 DPS), zasięg 14 → 11 m ze spadkiem wiązki z dystansem (od 5 m do 55%), bateria 100 → 60 (zapas 120 / max 240, skrzynka 50, przeładowanie 2,6 s), **hałas rośnie z rozgrzaniem wiązki** (0,25 → 0,8 na tyk; hałas/DPS 0,026 → 0,106). Ciągła broń liczy hałas z rozgrzaniem (HKM-9 bez zmian). `--weapontest` 119/119, szczegóły w `WEAPONS.md` §10. |
| 1.7.62 | 2026-10-07 | **Ekwipunek zużywalny, faza A1: szkielet rzucanych przedmiotów.** Nowy rodzaj ekwipunku obok flar i wabika (GDD §6.5): **granat odłamkowy** (4 m, 90 obrażeń z spadkiem do 50%, zapalnik 1,8 s, rani też drużynę, rozbija zamurowane przejścia, hałas wybuchu) i **granat fosforowy** (zapalnik 1,3 s, pole ognia z 3 plam na 15 s — podpala, fizycznie zatrzymuje Trzoski, Ślepce i Skoczki, nie rani drużyny, hałas 3). Rzut **T**, zmiana rodzaju **X**; HUD pokazuje rodzaj i zapas. Zapas jest **wspólny dla drużyny** (jak flary i Q; zmiana względem planu „per gracz”, bo to spójny model w całej grze), start: 2 odłamkowe i 1 fosforowy, maks. 4 / 3, wraca do startu co misję i próbę (też z kryjówki); zakup w warsztacie i skrzynki — faza A3. Serwer rozstrzyga zapas i wybuch, granat leci deterministycznie u wszystkich peerów (`grenade.gd`, `throwables.gd`, `Arsenal.request_throw`, `level.spawn_grenade`); `spawn_fire_patch` przyjmuje czas życia (pole fosforowe 15 s, pula 16 plam). Podpowiedź w grze, wiersz w sterowaniu, dev `--shotnade`. `--weapontest` 130/130 (+11). Szczegóły w `WEAPONS.md` §11. |
| 1.7.63 | 2026-10-07 | **Ekwipunek zużywalny, faza A2: pozostałe przedmioty.** Karuzela ekwipunku ma 8 pozycji (**T** użyj, **X** następny — puste rodzaje są pomijane): rzucane — odłamkowy, fosforowy i **dymny** (chmura 3,5 m na 12 s; wrogowie słyszą, ale nie widzą celu przez dym — `smoke_cloud.gd`, `enemy._clear_line`); stawiane — **mina kierunkowa** (uzbraja się po 1 s, odpala ją pierwszy przebudzony wróg w stożku ±38° / 84 px: 120 obrażeń każdemu w stożku, nie rani drużyny, hałas 10) i **ładunek wyburzeniowy** (zapalnik 4 s, wybuch 5 m, 150 obrażeń, rozbija zamurowane przejścia, rani drużynę, hałas 20 — `placed.gd`); narzędzia — **apteczka** (trzymaj T 5 s przy rannym koledze lub sobie: +1 serce, obrażenia przerywają), **defibrylator** (trzymaj T 1,5 s: podnosi leżącego do 10 m w linii wzroku, 1 na misję) i **skaner „Sowa”** (10 s, sylwetki wrogów przez ściany do 15 m, hałas 1/s — `scanner_view.gd`). Narzędzia i stawianie obsługuje `player._gear_tick` (apteczka i defibrylator wymagają stania w miejscu), zapas i skutki serwer (`Arsenal.request_use`, `request_throw` wg trybu `throw` / `place` / `use`). Start misji: po 1–2 sztuki każdego (zakup i skrzynki — A3). HUD: środkowy pasek dla apteczki/defibrylatora, dev `--shotscan`. `--weapontest` 143/143 (+13). Szczegóły w `WEAPONS.md` §12. |
| 1.7.64 | 2026-10-07 | **Klawisz użycia przedmiotu: lewy Alt (macOS: lewy Cmd) zamiast T.** Dotyczy rzutu, stawiania i narzędzi (karuzela ekwipunku z 1.7.62–1.7.63); X dalej zmienia pozycję. Wiązanie tylko lewego klawisza (`InputEventKey.location`), prawy Alt / Cmd pozostają wolne. Podpowiedzi, HUD („ALT” / „CMD”), lista sterowania i stopka pokazują nowy klawisz (`Throwables.key_name`). Test wiązania w `--weapontest` (144/144). |
| 1.7.65 | 2026-10-07 | **Ekwipunek zużywalny, faza A3: zakup, zapas, boty, kodeks i ekonomia.** **Warsztat ma zakładkę SUPPLIES** (Tab / przyciski ARMS–SUPPLIES): granat odłamkowy 100, fosforowy 150, dymny 80, mina 140, ładunek wyburzeniowy 250, apteczka 70, skaner Sowa 120 złomu za sztukę (`Scrap.request_buy_supply`, serwer rozstrzyga; sufit zapasu `max`; defibrylator nie jest na sprzedaż). **Zapas przechodzi między misjami** i sesjami (zapis `gear/stock` u hosta), przed każdą misją dopełniany do **darmowego zestawu**: 1 odłamkowy, 1 apteczka, 1 defibrylator (zamiast tymczasowych 1–2 sztuk z A2); **wipe wraca do stanu z początku misji** (`Arsenal.begin_mission`), Nocny Dyżur dostaje sam zestaw. **Skrzynki zaopatrzenia** wypadają z wrogów (Wołek 35%, Mimik 40%, Podsłuchacz 15%, Ślepiec 10%, Skoczek 8%; losowy rodzaj z wagami, `Throwables.DROP_WEIGHTS`) i zasilają wspólny zapas, jeśli nie jest pełny. **Boty używają zapasu** (`player._bot_gear`): defibrylator na leżącym człowieku w zasięgu 10 m i linii wzroku (1,5 s), apteczka na rannym człowieku obok (5 s, gdy w pobliżu nie ma wroga), na końcu na sobie; granatów i min nie rzucają. **Menu pauzy ma kartę GEAR** (8 pozycji z cenami, statystykami, opisem i wskazówką, portret rysowany w kodzie). Testy w `--weapontest` (153/153, +9): tabela cen (50–300, każdy przedmiot do zdobycia, ładunek > mina > granat), zakup, zapas między misjami / wipe, zapis, skrzynki, bot; dev `--shotsup`, `--shotgear`. Szczegóły w `WEAPONS.md` §13. |
| 1.7.66 | 2026-10-07 | **Zakładka SUPPLIES i karta GEAR w stylu gry.** Poprzednia zakładka zaopatrzenia (lista tekstowych wierszy z domyślnymi przyciskami) odstawała od ARMS — teraz ma **ten sam układ**: siatka kafli 150 × 46 po lewej (miniatura przedmiotu na „płytce” z poświatą i paskiem w kolorze przedmiotu, nazwa, moneta i cena, kwadraciki zapasu drużyny jak poziomy ulepszeń), po prawej panel szczegółów (duża miniatura, tytuł pikselową czcionką, typ, statystyki, opis, przycisk „Buy +1 · N scrap”), nawigacja strzałkami jak w ARMS, Enter kupuje. Nowe **miniatury przedmiotów** (`item_icon.gd`): sylwetka z obrysem i cieniem 1 px ekranu rysowana ostro (jak `gun_icon.gd`), ta sama bryła w karcie GEAR (`codex_portrait.gd`, miniatury na liście mieszczą się w 20 px). Bez zmian w logice; `--weapontest` 153/153, `--gentest` bez błędów. |
| 1.7.67 | 2026-10-07 | **Proporcje broni względem postaci.** Pomiar pikseli pokazał, że broń w świecie była za duża: karabin 26 px przy postaci 23,5 px (długość 1,1 wzrostu), pistolet P-64 21 px (0,9), maczeta 27 px, a grubość 11,5 px większa niż głowa; wszystkie bronie miały podobną długość. Arkusz `guns.png` przebudowany ze skalą świata `WORLD_FIT` (`tools/gun_icons_hd.py`): karabiny i strzelby ×0,65, WRATH-4 i SPECTER-1 ×0,72, **pistolet ×0,5** (wylot 7 px), maczeta ×0,6, kilof ×0,65. `gun_len` w `weapons.gd` dopasowane (M-83 12, SPREAD-12 12, P-64 7, PELLET-8 12, LR-7 11, HKM-9 10, WRATH-4 10, FALCON-6 10, SPECTER-1 12, SINEW-6 11, maczeta 13, kilof 13) — od niego zależą wylot lufy, błysk i start pocisku. Ikony HUD / kodeksu (`gun_icons.png`) bez zmian; zasięgi broni białej i statystyki bez zmian (zasięg cięcia maczety 22 px jest teraz większy niż widoczne ostrze 13 px — do oceny w grze). `bake_sprites.py --only=guns` przepieka same arkusze broni. `--weapontest` 153/153. |
| 1.7.68 | 2026-10-07 | **Pijawka trudniejsza (pakiet A + B + C).** Przyczyny: boss atakował tylko graczy w wodzie (kładka i brzeg były bezpiecznym stanowiskiem), 600 HP przy ~60–70 DPS to ok. 15 s ognia, chwyt łatwy do przerwania, Trzoski dopiero od fazy 2. **A — koniec bezpiecznych miejsc:** zasięg zasadzki obejmuje niską kładkę (32 px nad wodą, `STRIKE_Y` 20 → 44) i brzeg do 44 px od basenu (Pijawka wyskakuje z wody o 22 px dalej, `SHORE_REACH` / `SHORE_LUNGE`); wysokie kładki (64 px) bronią przed ugryzieniem, ale **od fazy 2 Pijawka pluje kwasem** (`acid_spit.gd`): podpływa pod gracza w zasięgu 340 px, zapowiedź 0,9 / 0,7 s (kręgi), wynurza się odsłonięta na 1,1 s i pluje łukiem z wyprzedzeniem (1 serce); boty robią unik przed kwasem. **B — wytrzymałość:** HP 600 → **900** (+300 na dodatkowego człowieka); **regeneracja** 1,5% maks. HP/s zanurzona i nieoświetlona (do progu bieżącej fazy, faza nie cofa się); **flary w wodzie gasną po 8 s** (`flare.gd`, na brzegu 25 s). **C — presja:** Trzoski z brzegów od fazy 1 (co 22 / 12 / 8 s, maks. 2 / 4 / 5, pierwsze po 10 s); chwyt: uwolnienie za **18%** maks. HP w **3,5 s** (było 12% w 4 s), przerwy po chwycie 3,0 / 2,2 / 1,2 s; **furia** w fazie 3 poniżej 15% HP (ruch ×1,4, zapowiedzi i przerwy ×0,7, krzyk i migotanie świateł). `--leechtest` 19 sprawdzeń (+5: Trzoski w fazie 1, zasięg niskiej kładki i brzegu, regeneracja, flara w wodzie, plucie, furia), bestiariusz zaktualizowany. Uwaga: flary gasną szybciej na każdym kaflu wody, nie tylko w arenie. |
| 1.7.69 | 2026-10-08 | **Pijawka, pakiet D: fala przypływu i skalowanie przez poziom trudności.** **Fala przypływu** (fazy 2–3, `leech.gd` `_tick_surge`, `tide_water.gd`): co 25 s w fazie 2 (pierwsza po 14 s) i 20 s w fazie 3 — zapowiedź 2,2 s (woda faluje, dudnienie, pasek „THE TIDE IS RISING”), potem fala zalewa basen i 56 px brzegu do 48 px nad dnem: każdy żywy gracz niżej (niska kładka 32 px, brzeg, woda) traci serce, zalane flary gasną, a przez 4,5 s wysokiej wody zasięg zasadzki Pijawki sięga całej zalanej strefy; potem woda opada (0,9 s). Bezpieczne są wysokie kładki (64 px), na które nie dosięga ugryzienie ani fala, ale dosięga kwas. Mapa B1: wschodnia wysoka kładka (rząd 27) przedłużona do kolumny 110, żeby z niskiej kładki wschodniej była droga w górę. Wizualnie: półprzezroczysta tafla z gradientem, falującą krawędzią i pianą; zdarzenia `surge_warn / surge_on / surge_off` synchronizują klientów. **Skalowanie `Difficulty`:** HP dalej przez `boss_hp` (EASY ×0,7 / NORMAL ×1 / HARD ×1,4 → 630 / 900 / 1260, z 2 ludźmi 840 / 1200 / 1680; `Leech.hp_for`), a poziom trudności zmienia teraz też zachowanie Pijawki: `boss_cd` skraca / wydłuża zapowiedzi i przerwy (HARD ×0,8), nowe `boss_regen` (×0,5 / 1 / 1,5 regeneracji), `boss_adds` (×0,6 / 1 / 1,3 liczby i tempa Trzosków, maks. w fazie 3: 3 / 5 / 7), `boss_tide` (×1,35 / 1 / 0,75 odstępów i zapowiedzi fali). Dev `--shottide`. `--leechtest` 22 sprawdzenia (+3: brak fali w fazie 1, fala niska/wysoka kładka, skalowanie trudności), `--maptest` bez błędów. |
| 1.7.70 | 2026-10-08 | **Pijawka wciąż za łatwa (ukończona w 1:33) — zmiana modelu obrażeń i dłuższa walka.** Diagnoza: cień w świetle flary dostawał 100% obrażeń, więc wystarczyło go oświetlić i strzelać; 900 HP padało w ~35 s. Teraz: **pełne obrażenia tylko wynurzona** (zasadzka, chwyt, plucie), **cień w świetle 40%** (`LIT_MULT`), w ciemności 5% — światło pomaga przewidzieć zasadzkę i podcinać, ale prawdziwe okno trzeba wywołać przynętą i wykorzystać. **HP 900 → 5000** (+1500 na dodatkowego człowieka; HARD ×1,4 = 7000), próg uwolnienia z chwytu 6% maks. HP (300 HP w 3,5 s), regeneracja w ciemności 0,5%/s. Teksty celu, wskazówka bossa, opis mapy i bestiariusz mówią o nowej zasadzie. **Symulacja `--leechsim=CELNOŚĆ,DPS`** (`main._leech_sim`): nieśmiertelny gracz-przynęta w wodzie zadaje DPS × celność tylko w oknach wynurzenia i w świetle flary (40%), czas ×4 — sufit szybkości walki: 1 strzelec 73 DPS / celność 60% = 3,7 min, duet 128 DPS = 1,9 min, duet i 100% celności = 1,3 min (przy 900 HP i 100% w świetle ten sam model dawał kilkanaście–20 s wobec ok. 35 s w prawdziwej grze, więc realny czas to ok. 2× wynik symulacji). Uwaga: HP 1.7.69 (EASY/NORMAL/HARD 630 / 900 / 1260) zastąpione liczbami ×5,6: 3500 / 5000 / 7000. `--leechtest` 22 sprawdzenia. |
| 1.7.71 | 2026-10-08 | **Perki i XP, faza B1: profil gracza i XP.** Nowy autoload `Profile` (`profile.gd`) — **lokalny profil każdego człowieka** (`user://profile.cfg`: XP, ukończone misje, założone perki; nie w zapisie hosta). **Poziomy:** próg następnego rośnie o 150, 250, 350… (L2 150 XP, L3 400, L4 750, L5 1200); **sloty perków:** 1 od L2, 2 od L4. **XP** liczy serwer i wysyła właścicielowi profilu: zabójstwa (Trzosek 2, Ćma 3, Podsłuchacz 4, Skoczek 5, Ślepiec 6, Mimik 10, Wołek 12; ostatni trafiający, także od podpalenia; Trzoski Pijawki, wędrowcy Dyrektora i boty nie liczą się), ukończenie misji 100 (+50 cel poboczny, +25 bez upadków, +300 boss, +100 pierwsze ukończenie danej misji — bonus liczy lokalny profil), podniesienie kolegi 15; Nocny Dyżur: połowa. **Katalog perków** (`perks.gd`, GDD §10.2): Quiet steps, Bloodflow, Wide arm, Smith (L2), Cold blood, Scout, Second chance (L4), Veteran (L6); API `equip` / `unequip` (sloty i progi) i zapis — **skutki perków (hooki) w fazie B3, ekran wyboru w kryjówce w B2**. HUD: „LV n · x / y XP” pod złomem, „+12 XP” sumujące się i blaknące, komunikat awansu (nowy slot, nowe perki), wiersz XP na karcie wyniku. Zrzuty dev (`--shot*`) nie zapisują profilu. `--weapontest` 161/161 (+8: krzywa i sloty, katalog, zakładanie, XP za misję i zabójstwa, zapis). |
| 1.7.72 | 2026-10-08 | **Perki i XP, faza B2: ekran perków w kryjówce i w menu pauzy.** Warsztat ma trzecią zakładkę **PERKS** (Tab: ARMS → SUPPLIES → PERKS), w tym samym układzie co pozostałe: po lewej poziom, pasek XP, siatka 8 kafli z ikonami (`perk_icon.gd`, pikselowe glify z płytką i obrysem) oraz dwa **sloty** (kliknięcie lub klawisze 1 / 2 wybierają slot; zablokowany pokazuje poziom otwarcia), po prawej panel szczegółów z opisem i przyciskiem **Equip / Remove**. Kafel pokazuje stan: „EQUIPPED · SLOT n”, „AVAILABLE” lub „LV n”; próba założenia zablokowanego perka albo do zablokowanego slotu daje komunikat zamiast cichego niepowodzenia. Każdy perk ma kolor (`Perks.color_of`). **Menu pauzy** ma nową kartę **PERKS** (6 kart: SETTINGS, BESTIARY, WEAPONS, GEAR, PERKS, CONTROLS) z listą i portretem z `Codex.perks()`. Perki jeszcze nie działają w grze — skutki w fazie B3. Dev: `--shotperks`, `--shotperkcard`; gentest sprawdza zakładkę (zakładanie, zdejmowanie, blokada L6 przy L4, zawijanie Tab, 6 kart pauzy). |

---

## 23. Czucie gry — standard i priorytety z playtestów

Filar 7 (§2): nowa zawartość dopiero, gdy podstawy są przyjemne. Poniższe wartości są **wdrożone w prototypie** (`player.gd`, `feel.gd`, `weapons.gd`, `enemy.gd`) i są punktem odniesienia — zmiana wymaga uzasadnienia z playtestu.

### 23.1 Ruch i skok

| Parametr | Wartość | Po co |
|---|---|---|
| Prędkość / kucanie | 95 / 45 px/s | Gracz szybszy od Stalkera (88), kucanie wyraźnie wolniejsze — koszt ciszy |
| Coyote time | 0,10 s | Skok jeszcze chwilę po zejściu z krawędzi — brak „zjadanych" skoków |
| Jump buffer | 0,10 s | Skok wciśnięty tuż przed lądowaniem się liczy |
| Jump cut | ×0,45 | Puszczenie skoku skraca lot — kontrola wysokości |
| Nietykalność po trafieniu | 0,6 s (1,2 s po podniesieniu, 1,5 s po respawnie) | Brak „serii" trafień od kilku wrogów naraz |
| Twarde lądowanie | dźwięk + shake rosnące z czasem lotu (> 0,25 s) | Lądowanie jest aktywnością w sensie §8.1 |

### 23.2 Strzał i trafienie

| Broń | Rytm | Obrażenia | Hałas (zimna → gorąca lufa) | Feel |
|---|---|---|---|---|
| M-83 (auto) | 0,11 s | 8 (×1,5 w głowę) | 0,6 → 1,5 | shake 0,7, kick kamery 0,5, bloom do 4° |
| SPREAD-12 | 0,26 s, 5 śrucin ±14° | 5×7, spadek do 35% | 3,5 → 5,0 | shake 2,4, odrzut gracza 55 |
| P-64 | 0,20 s | 11 (×2 w głowę) | 0,5 → 0,9 | shake 0,5 |
| PELLET-8 | 0,8 s, 8 śrucin ±17° | 8×7, spadek do 25% | 4,5 → 6,0 | shake 4,0, odrzut 130, ogłuszenie 0,2 s |

- Lufa grzeje się z każdym strzałem i stygnie z **własną prędkością broni** (M-83 0,30/s, SPREAD-12 1,2/s, P-64 0,6/s…): krótka seria jest tania, ciągły ogień drogi (§8.1). Pełny roster i liczby: §6.7 i `prototype/WEAPONS.md`.
- Trafienie wroga: biały błysk 0,1 s, ogłuszenie 0,12 s, odrzut (Trzosek 70, Wołek 14).
- **Hitstop:** zabójstwo Trzoska 50 ms, Wołka 90 ms, własne trafienie 70 ms; cooldown 250 ms (przy 8 strz./s hitstop na każde trafienie zamroziłby grę). **Na hoście z podłączonymi klientami hitstop jest wyłączony** — `Engine.time_scale` spowalniałby symulację wszystkim; zostaje shake.
- Shake jest lokalny (kamera każdego peera), wygaszany czasem rzeczywistym.

### 23.3 Priorytety po playteście

Wypełniane po playteście „kiedy się nudziłeś, a kiedy się bałeś" (§16.0 pkt 2). Do tego czasu kolejność prac wyznacza §19.

| Data | Osoby | Nuda (moment) | Strach (moment) | Wniosek → zmiana |
|---|---|---|---|---|
| — | — | — | — | — |
