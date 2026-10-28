# DEAD AIR '87 — Game Design Document

**Wersja:** 1.7.388 — numer gry z `prototype/project.godot` (`config/version`); historia zmian: [`CHANGELOG.md`](CHANGELOG.md). Zręby dokumentu pochodzą z 1.6.0 (analiza „wciągająca, przyjemna gra”: game feel, Stalker, down/revive, zakres; patrz §23)
**Gatunek:** Co-op survival horror / retro run-and-gun (side-scroll)
**Gracze:** 1–4 online (2–3 to projektowany default; **AI towarzysz od premiery EA**)
**Silnik:** Godot 4.7 (renderer Forward+) + GodotSteam
**Grafika:** 2.5D — symulacja 2D, obraz wyłącznie w 3D (widok 2D i grafika klasyczna usunięte w 1.7.194) — patrz §13
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
**Stan w prototypie (1.7.392):** złom i próbki → warsztat i stanowiska Kryjówki; XP → poziom profilu → perki i stroje; kolejne misje kampanii są
trudniejsze z założenia mapy, a nie ze skalowania z postępem (skaluje tylko Nocny Dyżur). Analiza i plan: `PROGRESSION_PLAN.md`.

### Zasady śmierci
- HP: 3 serca (Weteran), 1 trafienie (Koszmar).
- **Down** — gracz pada, **wykrwawia się 10 s** (licznik widoczny na HUD i nad postacią). Kolega staje obok i **trzyma E przez 4 s** (perk Krwioobieg: 2,5 s) — gracz wstaje z 2 serc. Bot też podnosi (z tym samym czasem — nie jest szybszy od człowieka).
- **Wykrwawienie** (10 s bez pomocy) = powrót w punkcie startu misji z 1 sercem. To kara dystansem i czasem, nie ekranem „game over".
- **Sam bez bota** (od 1.7.400, host wyłączył AI towarzysza — §16.3, `NOBOT_PLAN.md`): nikt nie podniesie, więc pierwszy upadek w próbie to
  wykrwawienie i powrót na start z 1 sercem (łup zostaje), a **drugi upadek w tej samej próbie = wipe**. Z botem albo drugim człowiekiem
  wipe jak zawsze: wszyscy leżą jednocześnie.
- **Wipe** (wszyscy down jednocześnie) = **nieudana ekstrakcja**: po 3 s restart misji (Uwaga, wrogowie, ładunki Q), tracicie łup misji, ale nie postęp fabularny.
- **Punkt kontrolny bossa** (od 1.7.401, `FUN_PLAN.md` P0.3): w misji z gniazdami i bossem (1.3) przebudzenie bossa zapisuje pozycje drużyny. Wipe w walce z bossem wraca do jej początku (gniazda zostają zniszczone, reszta jak przy wipe'ie, boss budzi się po 2,5 s), a wykrwawienie w walce odradza przy arenie — połowa wipe'ów 1.3 była w fazie BOSS, a powtórka całej mapy karała czasem, nie decyzją.
- **Dlaczego bez auto-respawnu:** darmowy respawn po 3 s zabija napięcie i sens Przesterowania. Down + revive tworzy momenty, o których drużyna opowiada po sesji.
- Uratowani NPC mogą zginąć na stałe (wpływ na zakończenie i sklep).

---

## 5. Sterowanie i ruch

| Akcja | Klawiatura | Pad |
|-------|------------|-----|
| Ruch / celowanie 8 kier. | WASD / strzałki (mysz: celowanie swobodne, wtedy WASD tylko porusza) | Lewy drążek (ruch) / prawy (aim) |
| Strzał | LPM / J | RT |
| Skok | Spacja | A |
| Kucanie (cisza) | Shift | L3 |
| **Przesterowanie** (§8.4) | Q | LB |
| Zmiana broni | 1 / 2 / 3, kółko myszy | Y (następna) |
| Przeładowanie | R | R3 |
| Tryb ognia (seria M-83) | B | D-pad ↓ |
| Rodzaj amunicji (następny magazynek) | Z | — (do przypisania) |
| Cios (maczeta / kilof) | V / PPM | X |
| Przedmiot (granat, mina, apteczka…) / zmiana przedmiotu | lewy Alt / X | RB / D-pad ↑ |
| Flara | F | D-pad → |
| Latarka | L | D-pad ← |
| Interakcja / dźwiganie | E | B |
| **Krzyk** (także mikrofon, jeśli włączony) | G | LT |

Tabela opisuje stan gry; źródłem prawdy jest rejestr `prototype/scripts/actions.gd`, a gracz może zmienić przypisania w ustawieniach.
Ping drużyny i radio z pierwotnego projektu nie są zaimplementowane.

**Ruch:** bieg, sprint, kucanie (hałas 0), wspinaczka po drabinach, chwyt krawędzi, unik w bok (i-frames 0.2 s), spadanie z platform.

**Kluczowe:** gra jest single-plane (klasyczna Contra), ale z warstwami tła (przeciwnicy strzelający z drugiego planu) i sekcjami wewnętrznymi (budynki, sztolnie).

---

## 6. SYSTEM BRONI — pełna lista

### Zasady ogólne
- Gracz nosi **2 bronie główne** + **sidearm** (P-83 Wanad, nieskończona amunicja) + **broń białą**.
- Bronie główne wypadają z pickupów w misji i są odblokowywane na stałe przez zakup w Kryjówce.
- Amunicja jest **współdzielona w drużynie** — ekonomia zespołowa. Od 1.7.317 zapas liczy się **po kalibrze** (SPREAD-12 i PELLET-8 biorą
  12/70 z jednej puli), a kaliber ma **typy naboi**: zwykłe (zapas misji, łup) i specjalne kupowane w warsztacie (7,62 US poddźwiękowe,
  7,62 BZ przeciwpancerno-zapalające, 12/70 breneka, zapalające, gumowe; od 1.7.318 granaty 40 mm: kartaczowy, oświetlający z flarą na
  spadochronie, dymny). Typ wybiera się klawiszem Z na następny magazynek. Elity upuszczają pudełka amunicji specjalnej do noszonej broni.
- Każda broń ma **części w gniazdach** (od 1.7.319, zamiast 3 poziomów ulepszeń): zasilanie, lufa, wylot, mechanizm, kolba… — każda część
  ma zysk i koszt. Drużyna odblokowuje części za złom, a każdy gracz montuje je we własnej broni (`prototype/WEAPONS.md` §17).
- **Hałas** = promień w metrach, który wrzuca punkty do Poziomu Uwagi. Jest to pełnoprawny statystyk.

### 6.1 Bronie główne

| # | Broń | Typ | Dmg | RPM | Mag. | Zasięg | Hałas | Cechy |
|---|------|-----|-----|-----|------|--------|-------|-------|
| 1 | **M-83 „Krótki"** | SMG (start) | 8 | 600 | 30 | 12 m | 3 / 6 m | Wszechstronny, szybki reload |
| 2 | **SPREAD-12 „Rozrzut"** | Strzelba samopowtarzalna (komora AK, bęben) | 4×5 | 240 | 25 | 8 m | 3 / 7 m | Klasyk Contry, szeroki stożek, silne szarpnięcie kamery |
| 3 | **LR-7 „Promień"** | Laser ciągły | 12/tyk | — | Bateria 100 | 14 m | 2 / 4 m | Przebija 3 wrogów; cichy, ale świeci w ciemności (przyciąga wzrok wrogów) |
| 4 | **HKM-9 „Miotacz"** | Miotacz ognia | 15/s DoT | — | Paliwo 80 | 4 m | 1 / 3 m | Podpala teren; **UV +3 Uwagi** (światło); strach wśród Trzosków |
| 5 | **WRATH-4** | Granatnik | 80 AoE 3 m | 40 | 6 | 10 m | 4 / 18 m | Niszczy Gniazda i Żyły; friendly fire 100% |
| 6 | **FALCON-6** | Naprowadzane mikro-rakietki | 6 | 300 | 40 | 10 m | 3 / 7 m | Auto-namierzanie, słabe, dobre na Skoczków |
| 7 | **PELLET-8** | Strzelba | 7×8 | 75 | 8 | 6 m | 4 / 12 m | Odrzut wrogów, door-breacher |
| 8 | **SPECTER-1** | Railgun | 150 przebicie | 12 (charge 1,2 s) | 5 | 30 m | 5 / 25 m | Najgłośniejsza broń w grze — używasz jej, budzisz wszystko |
| 9 | **SINEW-6** | Harpun (kusza) | 45 | 60 | 1 (bełt do odzysku) | 12 m, bełt opada | **1 / 1 m** | **Jedyna cicha broń główna**; przybija Trzoski do ścian; bełty można odzyskać |

### 6.2 Sidearm
| Broń | Dmg | RPM | Ammo | Hałas | Uwagi |
|------|-----|-----|------|-------|-------|
| **P-83 „Wanad"** | 10 | 300 | ∞ (rezerwa, magazynek 8) | 2 / 4 m | Nigdy się nie kończy; ratunek w sytuacjach awaryjnych |

### 6.3 Broń biała
| Broń | Dmg | Szybkość | Hałas | Uwagi |
|------|-----|----------|-------|-------|
| **Maczeta** | 30 | szybka | 0 | Ciche zabójstwo od tyłu (instant), niszczy cienkie drzwi |
| **Kilof** | 55 | wolna | 1 / 2 m | Otwiera zamurowane przejścia, ogłusza elitki |

### 6.4 Ulepszenia broni (przykłady)

> Od 1.7.319 ulepszenia to części w gniazdach z kompromisami (`scripts/parts.gd`, `prototype/WEAPONS.md` §17); tabela poniżej to pierwotny
> zamysł projektu.

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

**Skrzynie mocy (od 1.7.402, `FUN_PLAN.md` P1.3):** power-up w stylu Contry — skrzynia na mapie (1.1: WRATH-4 × 8, 1.2: FALCON-6 × 60) daje temu, kto jej dotknie, broń poza slotami z ograniczoną amunicją: bez przeładowania i zacięć, zmiana broni zablokowana, po ostatnim naboju albo upadku wraca broń ze slotu. Po co: w dziennikach M-83 dawało 81% zabójstw — broń mocy to chwila „Contry”, która zmusza do innej broni bez nauki warsztatu.

Pełna analiza i architektura: `prototype/WEAPONS.md`. W prototypie działa **12 pozycji**: M-83, SPREAD-12,
P-83, PELLET-8, LR-7, HKM-9, WRATH-4, FALCON-6, SPECTER-1, SINEW-6, maczeta, kilof (w HUD nazwy ASCII). Różnice
względem tabel powyżej — **wartości z kodu są nadrzędne** (`scripts/weapons.gd`, testy `--weapontest`):

- **Amunicja:** magazynki i przeładowanie (tryb taktyczny: z nabojem w komorze szybciej), **wspólny zapas drużyny**. Od 1.7.326 (M-83, SPREAD-12):
  krótkie [R] to szybkie przeładowanie — magazynek z resztkami spada na ziemię i trzeba po niego kucnąć; przytrzymane [R] — wolniejsze, resztki zostają
- **Przebijalność (od 1.7.327):** kula 7,62 przechodzi przez skrzynię albo jedno ciało (słabsza za nim), BZ przez dwa ciała albo stalową beczkę,
  9×18 i śrut zostają w pierwszym celu; kula od blachy pod ostrym kątem odbija się (rykoszet z połową siły)
- **Stan broni (od 1.7.328, ustawienie „Weapon reliability”):** każdy strzał trochę zużywa broń; poniżej 70 % stanu broń palna czasem się zacina
  (niewypał, zacięta łuska, podwójne podanie) — krótkie [R] przeładowuje rączką, P-83 strzela przy drugim pociągnięciu spustu. Brudną broń
  czyści się przy stole konserwacji w kryjówce (od 1.7.347 bez złomu, za to kilka sekund: 1,5 s na każde 10 % zużycia; od 1.7.350 zmęczone sprężyny ograniczają stan po czyszczeniu, a zużyta lufa rozrzuca — obie części wymienia się za złom) albo w misji zestawem do czyszczenia (od 1.7.329: 6 s, +40 %). Brodzenie w wodzie
  i błocie oraz upadek też zużywają broń; zużyte LR-7 przegrzewa ogniwo, a SPECTER-1 przebija kondensator
- **Wprawa (od 1.7.330):** trafienia i zabójstwa z danej broni podnoszą wprawę gracza z nią (5 stopni): do −10 % czasu przeładowania, dobycia
  i podrzutu, szybsze usuwanie zacięć
- **Historia broni (od 1.7.331):** broń liczy zabójstwa, a za każdą elitę i bossa ma rysę na kolbie (za bossa głęboką) — widać je na modelu
  w rękach, na ławie i w oględzinach
- **Części jako znaleziska (od 1.7.333):** skrytki misji zawierają części broni, a elity czasem je zostawiają; znaleziona część jest odblokowana
  dla drużyny po udanej ewakuacji (wipe ją zabiera), za darmo — kupowanie za złom zostaje
  autorytatywny na serwerze; sidearm ∞. Wrogowie upuszczają amunicję tylko do broni, którą ktoś nosi; skrzynie
  z mapy zasilają wszystkie noszone bronie główne.
- **Hałas:** każda broń ma własny `heat_gain`/`heat_decay` (wcześniej wspólny decay sprawiał, że rozgrzewała się
  tylko strzelba). P-83 jest **cichszy** od M-83 (0,5→0,9 vs 0,6→1,5), zgodnie z tabelą §6.2.
- **Krytyk w głowę:** tylko cele wysokie (Wołek: górne 28% sylwetki; Trzosek nie ma słabego punktu). P-83 i SINEW ×2, M-83 ×1,5.
- **Maczeta** zabija natychmiast i po cichu wroga śpiącego **albo odwróconego plecami**.
- **HKM-9** podpala (8 HP/s), płonące Trzoski uciekają w panice. **WRATH-4** liczy się jako wabik (+15 Uwagi) i rani drużynę.
- Zasięgi to zasięg *lotu* pocisku; efektywny (bez spadku obrażeń) jest krótszy (M-83 12 m, SPREAD-12 2,5 m).
- **Realia (1.7.316):** nabój w komorze (M-83 30+1, P-83 8+1, strzelby), P-83 strzela poddźwiękowo (9×18 mm), granat WRATH-4 uzbraja się
  dopiero po ok. 5 m lotu (bliżej tylko uderza — strzał pod nogi nie rani), rakiety FALCON-6 rozpędzają się jak Gyrojet (z bliska słabe),
  strzał w locie ma większy rozrzut, a ulepszenia lufy i spustu dają celność zamiast obrażeń. Od 1.7.324 (ustawienie „Weapon handling”,
  dla nowego gracza od 1.7.398 domyślnie CLASSIC, a zacięcia OFF — §16.0a): przy myszy seria unosi lufę (podrzut do ściągania), a broń oparta o krawędź skrzyni czy murku mniej podskakuje
  i mniej rozrzuca. Od 1.7.325 długi ogień grzeje lufę: gorąca lufa rozrzuca szerzej, rozgrzany tłumik głośnieje, a z lufy idzie dym
  i nad nią faluje powietrze; lufa stygnie ok. 45 s. Dalsza rozbudowa: `GUNSMITH_PLAN.md`.
- Doszły później (patrz `prototype/WEAPONS.md` §7–§9 i `scripts/throwables.gd`): ulepszenia 3-poziomowe, granaty, miny, ładunki, flary
  i zakup w kryjówce. Poza zakresem prototypu zostaje wyważanie drzwi.

---

## 7. WROGOWIE

### 7.1 Standardowe

| Wróg | HP | Szybkość | Zachowanie | Kontra |
|------|----|----------|------------|--------|
| **Trzosek** | 30 | szybka | Wataha 3–6, biegnie wprost; po zauważeniu gracza staje na ok. 0,4 s (odwraca się, oczy żarzą się, cichy warkot) — czytelny sygnał „zauważył cię"; kto pierwszy zauważy gracza, daje znać kolegom z watahy w ok. 14 m, więc schodzą się razem | Ogień ciągły, maczeta; mocne ogłuszenie (strzelba, szyna, harpun) przerywa jego cios w zapowiedzi |
| **Wołek** | 140 | wolna | Tankuje (pancerz 3 na trafienie; od 1.7.402 śrut traci go raz na cały strzał, nie na każdą śrucinę), potężny cios; szarża po poziomie, rzut skrzynią także w górę i w dół (do ok. 10 kafli różnicy poziomów); bez skrzyni w pobliżu rzuca **głazem** (0,5 HP — dwa trafienia = jedno serce, przerwa 8 / 5 / 3,2 s wg trudności) | Unik, strzelba w plecy |
| **Skoczek** | 40 | skok | Spada z sufitu/wysokości | Ciągły ogień w górę, FALCON |
| **Pijawka** | 15 | pełznie | Dopada, wysysa HP, QTE (30 s) | Maczeta, strzał w twarz kolegi? (friendly fire) |
| **Ślepiec** | 100 | węszy | **Nie widzi — słyszy.** Idzie w okolice ostatniego hałasu (z błędem lokalizacji — z daleka i przy cichych dźwiękach mniej dokładnie), po dojściu **przeszukuje okolicę** (±4 m, 6 s), a na **głośny dźwięk w 19 m** (rozgrzana M-83 i głośniejsze: strzelba, granat, krzyk) po krótkiej zapowiedzi **szarżuje** w jego stronę (do 1,4 s, 2,4× szybciej, z błędem celu; 2 obrażenia za cios; skacze przez przeszkody) — kroki w błocie i oleju go nie budzą | Kucnij i przejdź; harpun |
| **Podsłuchacz** | 35 | stoi | Nieruchomy „słuchacz" — widzi (240 px) albo słyszy (kroki z bliska, strzały z dalej); po zapowiedzi 0,9 s (dłuższej o 30%, gdy tylko usłyszał) **krzyczy**: przez 1,4 s stoi w **polu ochronnym (−90% obrażeń)**, a horda w 26 m budzi się **falą** (dalsi później) i idzie na krzyk. Kolejne krzyki sięgają bliżej, po trzecim milknie do uspokojenia (12 s) | Priorytet: zabić cicho (harpun) albo w zapowiedzi; w polu przeczekać albo dobić w zwarciu — cios przechodzi przez pole w całości (od 1.7.402) |
| **Mimik** | 70 | udaje | Udaje sylwetkę/radio kolegi z drużyny | Sprawdź pingiem/kodem drużyny |
| **Żyła** | 200 | rośnie | Splot 5–10 m, rodzi Trzoski | Ogień, WRATH-4, ładunek |

### 7.2 Elity

| Wróg | HP | Cechy |
|------|----|-------|
| **Kapłan** | 250 | Elita wsparcia (pancerz 2, wolny, **nie bije w zwarciu**): trzyma dystans za Trzoskami i co sekundę **leczy** je o 10% maks. HP (7 m, z czystą linią); gdy gracz podejdzie bliżej niż 7 m, po zapowiedzi 0,7 s z pierścieniem **krzyczy** — wszyscy gracze w 6 m dostają **ogłuszenie 0,8 s** (bez strzału, skoku i bicia, chodzić można; potem 3 s niewrażliwości), przerwa 8 s. Zabity przestaje leczyć, a Trzoski w pobliżu tracą morale. Najwyżej jedna elita naraz (znacznik `A` w mapie, późne grupy Dyrektora) | Zabij pierwszego: cofnij się z pierścienia, wejdź w zasięg tuż po krzyku, strzelba i ogień |
| **Rzeźnik** | 600 | Miniboss stref (pancerz 4, odporny na ogłuszenie i prawie na odrzut; prędkość 60): po zapowiedzi 1,0 s **szarżuje** 1,4 s ×3,2 szybciej (przerwa 9 s, 2 obrażenia) — **przebija zamurowane przejścia i barykady**, rozbija skrzynie i beczki, a o ścianę z kafli ogłusza się na 1,6 s (okno na strzał w plecy). Nie rzuca. Wymaga czystego rozbiegu 100–320 px na jednym poziomie (gracz na półce jest bezpieczny). Znacznik `U` w mapie, późne grupy Dyrektora (od ok. 11–13 min); najwyżej jedna elita naraz. Nie niszczy kafli mapy (tylko barykady) | Uskok z toru szarży, półka, beczki, strzelba i ogień (pancerz 4 osłabia M-83) |
| **Żerca** | 300 | Elita-porywacz (skacze, prędkość 95, **odporny na zatrzymywanie** — trafienia go nie chwieją i prawie nie odrzucają), **zamaskowany do porwania**: dopóki nikt nie leży, jest niewidoczny i nietrafialny (nie bije i nie reaguje na żywych). Wyczuwa **krew** — leżących graczy w ok. 33 m po trasie — skrada się do nich i w chwili **porwania ujawnia się** (krzyk, pierścień), po czym ciągnie ofiarę do legowiska daleko od drużyny (×0,6 prędkości); wykrwawianie porwanego stoi, podnieść go nie można. Po **20 s** od porwania „zjada”: gracz wraca na start misji tylko z wyposażeniem początkowym (nie ginie na stałe, GDD §4), a Żerca znów się chowa. **Zabity w tym czasie puszcza ofiarę** (min. 3 s do wykrwawienia, normalne podniesienie). Pojawia się dopiero po pierwszym upadku w misji i po ok. 6 min (Dyrektor, znacznik `V` w mapie); najwyżej jedna elita naraz. HUD drużyny: „TAKEN 17s”; gdy ofiara jest poza kadrem, przy krawędzi ekranu pulsuje czerwona strzałka „P2 TAKEN · 14 s · 23 m”, a za ciągniętym ciałem zostaje ciągła smuga krwi prowadząca do legowiska | Nie padaj; gdy ktoś padnie — po ujawnieniu zabij Żercę natychmiast, zanim zaciągnie ofiarę z zasięgu |

### 7.3 Stalker — „ON" (On/To)

- **Nie da się go zabić.** HP ∞. Trafienie spowalnia go na 1,2 s (do 40% prędkości) i zatrzymuje na 0,7 s, ale zatrzymanie działa najwyżej raz na 3 s — ostrzałem kupuje się czas, nie unieruchamia go.
- Aktywuje się, gdy Poziom Uwagi misji przekroczy próg (start: 60/100).
- Porusza się poza kadrem (dźwięk z głośników 3D), atakuje znienacka.
- **Mechanika tropu:** idzie do ostatniego głośnego punktu. Wabik odciąga go na 20–30 s: udane Q (§8.4) **przytrzymuje** go przy wabiku przez 15 s (`NoiseMgr.LURE_LOCK`, od 1.7.401) — nowy hałas w tym czasie go nie zawraca, przerywa to tylko snop latarki na nim albo kolejne Q; potem nasłuchuje przy wabiku do następnego hałasu.
- **Światło go przyciąga** (latarka na wrogu = śmierć). Ciemność i kucanie = szansa ucieczki.
- Można go „uspokoić": obniżyć Uwagę poniżej progu przez 60 s (żadnych strzałów, wabik gdzieś daleko).
- Pojawia się w 3 formach zależnie od strefy (sylwetka, dźwięk, cień).
- **Brzmienie (PR #251–#259):** niski, powolny oddech zamiast szeptu, warkot z nagrań i osobny sygnał, gdy wychodzi z mroku dla danego gracza (`stalker_appear`, najwyżej raz na 20 s). Zwykli wrogowie mają własne głosy i nie pożyczają głosu Stalkera.

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
| Strzał z P-83 | +1,0 → +1,6 (rozgrzanie) |
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

**Hałas wrogów i szczyt (od 1.7.402, `FUN_PLAN.md` P1.1–P1.2):** hałas samych wrogów (szarże, rzuty, krzyki elit) podnosi Uwagę najwyżej o 6 naraz, z odnową 2 na s — słyszą go wrogowie i Stalker jak dotąd, ale licznik ma mówić o decyzjach drużyny. Krzyk Podsłuchacza (kara za wykrycie) i skryptowe skoki są poza limitem. Uwaga trzymana na 100 przez 15 s sama opada do 70 i zaczyna się **oddech**: przez 8 s każdy hałas liczy się w połowie (HUD „THE NOISE FADES”) — rytm szczyt → oddech zamiast stałego maksimum.

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
- **Trzcina kryje kucającego** (od 1.7.306): przy brzegach wody, błota i oleju (kafel brzegu i pierwszy kafel cieczy) kucający jest widoczny z 0,3 zasięgu wzroku wroga zamiast 0,6. Stojącego nie kryje; słuchu (hałas, Ślepiec) ani budzenia z bliska nie zmienia. Stalker, który zauważa z bliska i idzie na hałas, działa bez zmian.
- Tilesety mają „dark zones” — pokoje, gdzie bez światła nie widzisz podłogowych pułapek.
- CRT/scanline filter opcjonalny; głębia tła sterowana warstwami parallax.
- **W prototypie (1.3.5):** zasięgi świateł, wzroku, słuchu i wybuchów są w **metrach projektowych: 16 px = 1 m** (`Lights.PX_PER_M`, kodeks). Świat 3D ma inną, prawdziwą skalę: **1 px = 0,082 m** (`Level3D.PX`; postać 1,8 m = 22 px, kafel 16 px = 1,31 m), więc metr projektowy to w obrazie ok. 1,31 m — aura „6 m” sięga w 3D na ok. 7,9 m. `CanvasModulate` przyciemnia świat (`Lights.AMBIENT`, strojone pomiarem luminancji ekranu: bez latarki przy graczu ~0,056, 6–9 m dalej ~0,007 — wcześniej tło było prawie tak jasne jak krąg gracza); każdy gracz ma aurę 6 m, latarka (L) to stożek 8 m (±24°) z baterią 180 s, kosztem +1 Uwagi co 10 s świecenia i budzeniem wrogów, na których padnie snop (z linią widzenia). Snop na Stalkerze ściąga go na świecącego (§7.3) i odsłania sylwetkę. Flara ekstrakcji = zielone światło 12 m, gniazda słabo się żarzą, strzał daje rozbłysk 4 m. Kafle rzucają cienie (okluder cofnięty o 4 px na odsłoniętych bokach — wierzch i lica łapią światło). Oczy wrogów, etykiety i paski są „unshaded" — widać je w ciemności. **Do playtestu:** bateria odnawia się 0,25 s/s przy zgaszonej latarce (GDD nie przewiduje ładowania — bez tego misja po 3 min byłaby czarna).

### 8.4 PRZESTEROWANIE — hałas jako zasób (nie zakaz)

Sedno poprawki. Problem: pierwotna wersja traktowała hałas jako coś, czego się unika, co oznacza **permanentne zakazanie run-and-gunu** — gatunku, dla którego gracz kupił grę. Rozwiązanie: hałas staje się **walutą do wydawania**, a nie zakazem.

**Mechanika:** przycisk **Q** (przesterowanie). Daje **+12 Uwagi celowo** i jednorazowo „przesterowuje" **ostatnie źródło hałasu** — Stalker rusza w stronę miejsca, gdzie użyto Q, zamiast miejsca ostatniego strzału. Koszt: zużycie ładunku.

- **Ładunek przesterowania:** misja startuje z 2. Regeneracja: +1 co 45 s (albo natychmiast przy wykonaniu celu głównego). Max 3.
- **Efekt taktyczny:** jeśli Stalker właśnie poluje na kolegę, gracz używa Q *daleko od niego* i Stalker przekierowuje się na gracza-innego-człowieka (albo na podstawiony Wabik). Drużyna zyskuje 20 s.
- **Widać, że zadziałało (od 1.7.401, `FUN_PLAN.md` P0.2):** w dziennikach Q użyto 8 razy na 129 misji — skutku nie było widać, a następny strzał kolegi i tak zawracał Stalkera. Teraz udane Q przytrzymuje go 15 s (§7.3), HUD pokazuje „HE TAKES THE BAIT” i odliczanie zamiast „He hears you…”, słychać jego zawracający warkot, a gdy Stalker poluje tuż przy koledze, a gracz ma ładunek, HUD podpowiada „He's on P2! [Q] lures him away from them”. Udane wabiki gracza liczy wyróżnienie BAIT na karcie wyniku.
- **Dlaczego to jest hook, a nie nerf:** aktywne „przesterowanie" brzmi jak coś, co *ty* robisz celowo — sygnał dla streamera „spróbujcie tego", zamiast statystyki, której się unika.

**Napięcie gatunków rozstrzygnięte w ten sposób:** w trybie **szumu** (walka) hałas jest nieunikniony i Stalker ciśnie — tu grasz jak w Contra. W trybie **napięcia** (cele, skradanie) cisza jest możliwa i oszczędzasz ładunek Q. Misje przełączają te tryby jawnie, żeby gracz wiedział, w którym jest. Bez tego GDD opisywał dwa różne produkty.

### 8.5 Stalker — pozycje i celowość (reguła dla AI, nie tylko opis)
- **Stalker NIE biega szybciej od gracza.** 88 px/s vs gracz 95 px/s — gracze da się wyprzedzić, ale trzeba biec w linii prostej, co rzadko możliwe w labiryncie. To zostawia szansę na ucieczkę. **Teren hamuje go tak samo jak gracza** (woda ×0,72, błoto ×0,58), więc reguła obowiązuje na każdej powierzchni: w wodzie 63 vs 68, w błocie 51 vs 55. Pilnuje tego `--stalkertest`.
- **Stalker kieruje się źródłem hałasu, nie pozycją gracza.** Nie ma „trybu szukania"; idzie tam, gdzie ostatnio było głośno.
- **W fazie napięcia (niski hałas) jest powolny (55 px/s)** i omija graczy — groźba bez ataku. W fazie szumu jest szybki i agresywny.
- **Nasłuchiwanie (v2):** po dotarciu do źródła hałasu Stalker **zatrzymuje się i nasłuchuje 4 s**. Idzie dalej tylko do *nowego* hałasu. Nigdy nie przełącza się na pozycję gracza — to oddaje ciszy realną wartość (wcześniej kod po dotarciu do punktu celował w najbliższego gracza, co robiło z niego zwykłego goniącego wroga).
- **Kucający gracz jest niemal niewidoczny:** Stalker zauważa go dopiero z **8 px** (stojącego z 14 px). Kucanie obok przechodzącego Stalkera to świadoma, nagradzana decyzja.
- **Widoczność — „słyszysz, nigdy nie widzisz":** ciało pojawia się dopiero w promieniu ~60 px od lokalnego gracza (płynnie do 160 px), poza tym widać tylko słabo błyszczące oczy. Gdy dojdzie oświetlenie 2D, widoczny jest w świetle latarki/flary.
- **Atak z zapowiedzią (v2):** zamach 1 HP, cooldown 1,5 s, **bez generowania hałasu**. Przed ciosem jest **0,55 s zapowiedzi** (szept milknie, oczy rozbłyskują, ryk) — gracz może uciec; jeśli odejdzie poza zasięg, cios chybia. Po ciosie Stalker odsuwa się o 6 px (ok. 0,5 m), stoi 0,8 s i może zamachnąć się ponownie najwcześniej po 1,5 s — okno na decyzję, nie natychmiastowy kolejny cios. Po **pudle** przerwa jest taka sama (do 1.7.400 była krótsza, 0,8 s, więc unik sypał serią szybszych zamachów bez skutku). Pudło w człowieka tuż obok to **ucieczka o włos** (od 1.7.401, `FUN_PLAN.md` P0.1): u tego gracza kadr na chwilę się zwęża, świat i muzyka cichną, HUD mówi „CLOSE CALL” — najwyżej raz na 5 s; licznik trafia na kartę wyniku (CLOSE SHAVE). W praktyce trafiony gracz ląduje tuż poza zasięgiem 14 px i Stalker nasłuchuje, dopóki nie padnie nowy hałas albo gracz sam nie podejdzie (pomiar: `--stalkertest`). Zasada: **śmierć od Stalkera jest zawsze „fair" i zapowiedziana.**
- **Poruszanie się:** idzie po powierzchniach poziomu ścieżką A* (`nav.gd`, 1.3.7) — chodzi, wspina się na wyższe poziomy i zeskakuje, nie przenika przez ściany. Ten sam graf prowadzi bota.

---

## 9. KAMPANIA — pełna lista misji

### STREFA I: BÓR CIEMNY (Dark Pinery) — „Zaginiony patrol"
Las, posterunek, tartak. Kolory: mgła, brąz, zieleń. Wprowadza: strzelanie, skok, latarkę.

| # | Misja | Cel główny | Cel poboczny | Nowa mechanika | Wrogowie | Czas |
|---|-------|------------|--------------|----------------|----------|------|
| 1.1 | **Zaginiony Patrol** | Znajdź 6 nieśmiertelników | 2 skrytki ze złomem | Ruch, strzał, latarka. **Tutorial ciszy:** kucz i chodź — pasek Uwagi spada; bród przed polaną (woda chlapie, błoto tłumi kroki, Wołek na skarpie); obóz patrolu: wataha śpi pod zerwanym mostem, cicho tylko górą po konarach. Strażnica: ćmy pod dachem lecą do światła, flara rzucona w bok je spala (lekcja flary). **Finał:** zawał w kopalni, szybem na powierzchnię i z powrotem przez obudzony las do wyjścia przy starcie. **Lekcja hałasu:** po pierwszym nieśmiertelniku Uwaga ≥ 80 (HARD: 95) wywołuje „przechodzącego” Stalkera — wychodzi z ciemności za plecami drużyny, poluje 28 s i znika | Trzoski, Wołki | 8 min |
| 1.2 | **Przerwa w Nadawaniu** | Uruchom 3 generatory radiostacji | Nie przekrocz 40 Uwagi | Poziom Uwagi, Podsłuchacze. **Tutorial Przesterowania:** użyj Q, żeby odciągnąć stalkera od koledów | Trzoski, Podsłuchacze, Stalker (skrypt) | 10 min |
| 1.3 | **Gniazdo** | Spal 3 gniazda | Uratuj zwiadowcę (NPC) + **zabij stalkera w ciszy**: obniż Uwagę <30, gdy celuje w NPC | **Pierwsze pejne starcie ze stalkerem** (bez skryptu). AI towarzysz ćwiczy dźwiganie | Trzoski, Żyła, Stalker | 12 min |
| **B1** | **PIJAWKA** | Zabij bossa | — | Flary ujawniają cień pod wodą | Pijawka, Trzoski | 6 min |

**Stan w prototypie (1.7.24):** zaimplementowane są **1.2 „Przerwa w Nadawaniu"** (w v2 — 1.7.25 — **4 generatory** na mapie 288×44, skok Uwagi po ostatnim, lekcja Q na Stalkerze, cel poboczny „Uwaga < 40") i **1.3 „Gniazdo"** (gniazda + Żyła zamiast Pijawki). Kampania gra je po kolei (1.2 → kryjówka → 1.3 → kryjówka → od początku); w 1.2 powrót to **ucieczka drezyną** (1.7.26); brakuje 1.1 „Zaginiony Patrol" i bossa Pijawki. **(Aktualizacja od 1.7.54:** kampania `z1_m1 → z1_m2 → z1_m3 → z1_b1` ma wszystkie trzy misje i bossa Pijawkę, więc Strefa I jest kompletna; ten akapit opisuje stan z 1.7.24.)

**Nagroda strefy:** odblokowanie sklepu broni (SPREAD-12, PELLET-8), postać Igła. **(Stan 1.7.392:** SPREAD-12 jest od startu, PELLET-8 i pozostałe bronie kupuje się w warsztacie od początku, Pijawka daje SPECTER-1 jako trofeum; postaci grywalnych z imionami w EA nie ma — wygląd wybiera się w szafkach.)

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
| **Złom** | Trupy wrogów, skrytki, sejfy (od 1.7.403: wyważane trzymanym [E], głośno — 40 złomu), premia za misję (ukończenie, cel poboczny, bez upadków, od 1.7.403 cichy cel: Uwaga < 60 przez cały cel, +30) | Bronie, części broni, zaopatrzenie, prasa, serwis, połowa badań, tokarka |
| **XP — poziom profilu** | Zabójstwa, wynik misji (cel poboczny, bez upadków, boss, pierwsze ukończenie), podniesienie kolegi | Poziomy gracza → sloty perków, perki, stroje i palety (do L6) |
| **Próbki** | Cele poboczne, elity, bossowie | Badania części broni specjalnych w pracowni |

Stan 1.7.392: perków się nie kupuje (odblokowuje je poziom), próbek się nie sprzedaje, strefy nie wymagają próbek. „Wroga wiedza” jako waluta
fabularna (np. wiedza o rodzajach wrogów) zostaje celem 1.0; w EA XP to tylko poziom profilu (§16.0a).
| **Taśmy** | Ukryte znajdźki | Fabuła, zakończenia, tapety koncept-artów |

### 10.2 Perki (2 sloty na postać; zaimplementowane — 1.7.73)
| Perk | Efekt |
|------|-------|
| Ciche kroki | Bieg generuje hałas 0,25/s zamiast 0,5/s; krok spada poniżej progu słuchu Ślepca (0,25), więc Ślepiec przestaje słyszeć bieg |
| Szerokie ramię | Rzut granatem +30% zasięgu |
| Druga szansa | Raz na misję wstajesz sam z down po 8 s (na 1 sercu; przy krótkim wykrwawianiu — po 80% jego czasu) |
| Krwioobieg | Szybsze dźwiganie rannego (4 s → 2,5 s) |
| Zimna krew | Twój krzyk do mikrofonu = tylko +10 Uwagi |
| Kowal | −20% kosztu ulepszeń broni |
| Skaut | Skaner pokazuje Stalkera (także uśpionego) w promieniu 10 m |
| Weteran | +1 serce (i +1 do sufitu kumulacji apteczek) |

### 10.3 Kryjówka (hub)
- **Warsztat** — bronie i części broni (zakup dla drużyny, montaż we własnej broni), trzy zapisane zestawy części na broń (każdy gracz osobno) i narzędzia (apteczka, skaner, zestaw do czyszczenia; granaty i miny — na stole pirotechnicznym, amunicja — w prasie); wybrana broń leży na ławie 3D z częścią spod kursora.
- **Pracownia elektroniki i próbek** (góra, pod radiostacją, od 1.7.357) — części broni specjalnych (LR-7, HKM-9, WRATH-4, SPECTER-1, FALCON-6, SINEW-6) bada się za próbki z elit (1), bossów (2) i celów pobocznych (1) oraz połowę ceny w złomie; jedno badanie na misję, po udanej misji gotowy schemat.
- **Tokarka i szlifierka** (maszynownia na dole, od 1.7.358) — ze schematu część za ćwierć ceny, jedno zlecenie na misję, gotowa po udanej misji; szlifierka ostrzy maczetę i kilof (każdy zamach tępi o 1 %, tępe ostrze rani do 70 %).
- **Stół pirotechniczny** (magazyn na dole, od 1.7.355) — granaty, miny, ładunki i naboje 40 mm; wybór długości zapalnika dla drużyny (odłamkowy 1,0–3,0 s, fosforowy 0,8–2,5 s, ładunek 4–15 s).
- **Masa ekwipunku** (od 1.7.356, obsługa REALISTIC) — każda broń i część ma masę; ekwipunek cięższy niż startowy (10,3 kg) biegnie głośniej (+5 % na kg) i wolniej (−1,2 % na kg), lżejszy — ciszej i szybciej. Ława pokazuje masę broni i całego ekwipunku.
- **Prasa elaboracyjna** (magazyn na dole, od 1.7.354) — amunicję specjalną się zamawia (taniej niż dawny sklep, najwyżej 3 partie), partia jest gotowa po następnej udanej misji; tylko tu powstają ładunki gorące (7.62 HOT, 12/70 MAG: mocniej, ale broń zużywa się dwa razy szybciej).
- **Stół konserwacji** (od 1.7.350) — czyszczenie broni (bez złomu, za czas; broń rozłożona na ławie 3D) i wymiana części eksploatacyjnych: lufa (zużyta rozrzuca) i sprężyny (zmęczone nie pozwalają doczyścić broni do 100 %) za złom drużyny — od 40 % zużycia (od 1.7.412).
- **Szafki osobiste** (świetlica, od 1.7.349) — perki i wygląd postaci (wcześniej zakładki warsztatu). Kolejne stanowiska warsztatu: `WORKSHOP_PLAN.md`.
- **Zbrojownia** — dwie gabloty po cztery bronie: [H] otwiera, ↑ / ↓ wybiera rząd, 1 / 2 wskazuje zastępowany slot, [E] bierze. Panel obsługuje też mysz i akcje pada; pokazuje blokadę oraz odbiorcę wspólnego egzemplarza. Serwer odblokowuje pobranie po zakupie w warsztacie, rozlicza zamianę i odkłada starą broń bez świeżych nabojów. Cała gablota ma wspólny zasięg; dołączający gracz widzi wcześniej pobrane egzemplarze jako wydane (1.7.379).
- **Szpital** — stan uratowanych NPC, bonusy fabularne (np. uratowany naukowiec daje schemat EMP).
- **Układ (od 1.7.265, „Stacja Dead Air”)** — bunkier pod nieczynną stacją radiową, trzy poziomy połączone szybami: środek (śluza → ściana pamięci → warsztat → świetlica z izbą chorych → zbrojownia → odprawa i wyjście), góra (radiostacja nad tablicą odpraw), dół (maszynownia i magazyn ze skrytkami). Wyjście na misję: strefa startu przed drzwiami z lampą ON AIR (gotowość przez stanie w strefie albo [Enter]), odliczanie 3 s (cyfra w HUD) ze świecącym padem, poświatą przy podłodze i polami graczy. Klimat: generator buczy i mruga w burzy, zza zamkniętych drzwi D-7 co jakiś czas ktoś puka, okno radiostacji pokazuje prognozowaną pogodę.
- **Radiostacja** — wywiad: prognoza pogody (modyfikatory misji), tygodniowe wyzwania.
- **Ściana pamięci** — statystyki drużyny, osiągnięcia.
- **Tablica misji** — tablica odpraw w strefie startu (od 1.7.392): kampania zaczyna się od misji po najdalszej ukończonej przez drużynę (zapis hosta), a [Interakcja] przy tablicy przełącza cel wyjścia na każdą ukończoną misję Strefy I albo następną; zmiana odnawia odliczanie wyjścia. Tryby dodatkowe (Nocny Dyżur) wybiera się w lobby.

---

## 11. Tryby gry

| Tryb | Opis | Uwięzienie |
|------|------|------------|
| **Kampania** | 18 misji + 6 bossów, 15–20 h | Postęp fabularny |
| **Nocny Dyżur** (endless) | 5 losowych misji pod rząd, wipe kończy serię. **W prototypie od 1.7.23** (HP +12%/misję, modyfikatory), ranking tylko lokalny | Cotygodniowy ranking |
| **Koszmar Tygodnia** | Misja + 3 losowe modyfikatory (np. blackout, podwójne hordy, alway-on Stalker) | Skiny, złom ×3 |
| **Strzelnica** | Test broni, tutorial. **W prototypie od 1.7.338:** drzwi na dolnym poziomie kryjówki prowadzą do tunelu FPP (5 blach na czas i ćwiczenie z przeładowaniem, papierowa tarcza z miarą grupy, ruchomy cel, amunicja ćwiczebna, ta sama obsługa broni co na misji, celowanie przez przyrządy z modelu broni); wynik sprawdza serwer, tablica rekordów drużyny wisi obok drzwi, rekordy osobiste per broń zapisuje profil (od 1.7.343); szafa z bronią daje na strzelnicy każdą broń palną bez kosztów, a przy wyjściu wraca zestaw z wejścia (od 1.7.346) | — |

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
- **2.5D:** rozgrywka jest symulacją 2D (fizyka kafli, AI, sieć, celowanie), a obraz domyślnie powstaje w 3D — kamera perspektywiczna patrzy z boku na płaszczyznę gry (`view3d.gd`, `level3d.gd`). Geometria świata powstaje z tej samej mapy ASCII co kolizje.
- **Renderer:** Godot Forward+ (Vulkan / D3D12): światła i cienie 3D, SSAO, SSIL (tylko kryjówka), mgła wolumetryczna, mgła głębi, glow, tonemapping filmic. Bez Vulkana silnik wraca do OpenGL (tryb zgodności, bez SSAO / SSIL / mgły wolumetrycznej).
- **Ciemność jest mechaniką, nie tylko nastrojem** (§8.3): noc jest czarna, a widoczność dają światła sceny — aura gracza, latarka, flary, ogniska, lampy, błysk lufy. Tło i mgła nie mogą rozjaśniać poziomu, na którym stoją postacie; daleki wróg ma być tak samo słabo widoczny w 3D i w 2D.
- **Materiały i zasoby:** świat w PBR (skany CC0 + proceduralne, `art/world3d/`), dekale zniszczeń, ciecze z przekrojem, bór sosnowy ze świerkami, brzozami i martwymi pniami, runo; kamienie, pnie i rekwizyty tła ze skanów Poly Haven (CC0, `art/items3d/CREDITS.md`) stawiane przez akcenty map (`ACCENTS`); postacie graczy i wrogowie jako modele 3D (rig + IK, `char3d.gd`, `enemy3d.gd`); przedmioty HD jako karty z mapą normalnych oświetlane światłem 3D. Grafikę generują skrypty w `prototype/tools/`.
- **Palety stref:** kolor niosą materiały i światła, nie filtr na całym kadrze (Bór: brąz ściółki i zieleń runa w ciepłym świetle ognia; Obiekt 86: stal i cyjan; Martwa Cisza: czerń i magenta).
- **Tylko 3D** (decyzja 2026-10-11): wszystko, co widać w świecie gry — modele, światła, cząsteczki, ogień, dym, krew, pociski, efekty — ma być w 3D. Elementy nadal rysowane w 2D na scenie 3D (m.in. płomień i poświata flar, iskry, plamy krwi, część cząsteczek i efektów pogody) są długiem do zastąpienia; wyjątkiem jest interfejs.
- **Widok 2D nie jest dalej rozwijany** (decyzja 2026-10-11): zostaje w grze jako tryb zastępczy dla słabszego sprzętu i do testów headless, ale nowe rzeczy — oświetlenie, modele, efekty, strojenie widoczności — powstają tylko dla widoku 3D i nie muszą mieć odpowiednika w 2D.
- **Opcje:** brak przełącznika widoku — obraz jest wyłącznie w 3D (widok 2D i grafika klasyczna usunięte w 1.7.194).
- Animacje z wyraźnymi reakcjami trafień (hitstop 50–90 ms przy zabójstwie, wartości w §23), duży, stylizowany gore.

### Audio (filar!)
- Muzyka adaptacyjna: warstwy (cisza / napięcie / walka / pościg) przełączane płynnie.
- Brzmienie: analogowe syntezatory lat 80. (DX7, taśma, szum) + industrialne uderzenia w muzyce; efekty, kroki, bronie i głosy wrogów z nagrań (`AUDIO_PLAN.md`; nagrania żyją poza repo w `prototype/audio_licensed/` i trafiają tylko do buildów).
- **Propagacja dźwięku przez ściany** — kroki i strzały są filtrowane (muffled) zależnie od geometrii; kluczowe dla horroru.
- Dźwięk 3D dla Stalkera (zawsze słyszysz, nigdy nie widzisz).
- Lektor: tylko radio (nadające głosy), brak pełnego dubbingu.

---

## 14. UI/UX i dostępność

- HUD minimalny: serca, amunicja (liczba), wskaźnik Uwagi (ikona oka/heartbeat), status drużyny (ikony), licznik baterii.
- Brak minimapy — tylko kompas ekstrakcji po wykonaniu celu.
- Ping system (jak w Apex): oznaczaj wroga/przedmiot/drogę.
- **Paski nad postaciami (1.7.393):** pasek życia wroga i plakietka gracza są w warstwie ekranu (nad obrazem 3D i efektami obrazu, pod HUD-em), przypięte do czubka modelu w bieżącej pozie — ostre w każdej rozdzielczości. Pasek wroga ma kolor kości na ciemnym torze (poniżej 25% rdzawy), po trafieniu jasny ślad obrażeń spływa po 0,35 s, a pasek gaśnie 4 s po ostatnim trafieniu (elita pokazuje go też przy pierwszym wejściu w kadr). Od 1.7.394 elita ma grubszy pasek w bursztynowym obrysie, romb, nazwę z kodeksu przez 3 s od pierwszego wejścia w kadr i tarcze pancerza (liczba = pancerz na trafienie); plakietka gracza to imię i te same kreski życia co na karcie drużyny (bez ramki, przy 1 życiu pulsująca czerwona linia). `world_bars.gd`.
- **Karta drużyny i boss (1.7.394):** własne kreski życia grubsze; pół punktu zabrane głazem Wołka to pół kreski z nacięciem; utracona kreska błyska i rozpada się na odpryski (bez nich przy „Reduce effects”); EKG bije co 1,2 s przy pełnym życiu, 0,9 s przy ubytku, 0,55 s przy ostatnim punkcie, a po powaleniu jest płaską szarą linią. Pasek bossa to ciągła belka z nacięciami progów faz (miniony próg gaśnie), śladem obrażeń i pulsem w furii.
- **Ustawienia dostępności:** VAD ON/OFF, „Krzyk" na przycisk, napisy z opisem dźwięków ([kroki za tobą]), mono audio, redukcja screen shake, tryb dla daltonistów (3 presety + kształty), skalowanie czcionek, pełne remapowanie klawiszy, tryb streamera (cenzura, brak muzyki licencjonowanej).
- **Stan prototypu (2026-10):** zrobione — pełne remapowanie klawiszy i przycisków pada, pad w grze (celowanie prawym drążkiem), „Reduce effects”, napisy dźwięków z kierunkiem, filtr widzenia barw (3 tryby), skradanie przełączane, rozmiar HUD, język EN/PL, jasność z ekranem kalibracji (±1 EV, od 1.7.383 — wąski zakres, żeby ustawienie nie rozjaśniało nocy z §8.3). Zrobione też: mono audio i czat tekstowy drużyny (T). Brak jeszcze: kształty zamiast samych kolorów, tryb streamera, ping drużyny. Plan i weryfikacja z kodem: `UI_PLAN.md`.

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
- Wymagania: karta z Vulkanem albo D3D12 dla pełnego obrazu 3D; na słabszym sprzęcie „Render scale” 75 % lub mniej (FSR 1, od 1.7.389) albo „Effects quality: LOW” (widoku 2D już nie ma). Minimalna konfiguracja nie jest jeszcze zmierzona (pomiar tylko na RTX 3080).

---

## 16. Zakres MVP, budżet, roadmapa

### 16.0 Strategia zakresu — demo najpierw (v1.3)
Budżet z §16.4 (10–16 mies. do EA) jest ryzykiem, dopóki nie wiemy, że rdzeń bawi. Dlatego kolejność jest odwrócona:
1. **Pionowy wycinek = jedna misja w całości** (ręcznie zbudowana mapa, cel, ekstrakcja, 1 boss), 2 bronie, 2 wrogowie + Stalker. To jest **demo na Steam** i materiał do pierwszych playtestów ze znajomymi.
2. **Playtest „kiedy się nudziłeś, a kiedy się bałeś"** (3–5 osób, nagrany gameplay) — przed jakąkolwiek nową zawartością. Wyniki decydują o priorytetach (§23). **Stan (1.7.366):** sesje z osobami z zewnątrz w toku, wpisy trafią do §23.3; dotychczasowe pomiary map (`MAPS_PLAN.md`) to sesje autora z botem.
3. **Dopiero potem** pozostałe misje Strefy I, losowe pokoje i EA. Losowość pokoi odkładamy, dopóki pętla na jednej mapie nie jest przyjemna po 20 powtórkach.
4. ~~**Progresja w EA — wersja minimalna:** jedna waluta (złom), 3 bronie do kupienia, 2–3 perki, bez Kryjówki-huba i bez Taśm/Próbek.~~ Zastąpione korektą zakresu z §16.0a.
5. **Nawigacja:** pełne A* dla Stalkera i botów po zbudowaniu poziomu na tilemapie (do tego czasu: ruch po powierzchniach, patrz §8.5).

### 16.0a Korekta zakresu (1.7.366, 2026-10-22)
Pkt 4 z §16.0 przestał opisywać grę: między 1.7.316 a 1.7.365 (ok. 50 wydań, `GUNSMITH_PLAN.md`, `RANGE_FPS_PLAN.md`, `WORKSHOP_PLAN.md`)
powstały pełne rusznikarstwo, Kryjówka-hub ze stanowiskami i strzelnica FPP — przed playtestem z pkt 2. Nie cofamy tego; zakres EA to teraz:
- **Bronie:** wszystkie 9 głównych z §6.1, P-83, maczeta i kilof (zamiast 3 do kupienia), z częściami w gniazdach zamiast poziomów ulepszeń.
- **Waluty:** złom (wszystko) i próbki (tylko badania części broni specjalnych w pracowni). XP zostaje jako poziom profilu (perki, stroje — od 1.7.73);
  „Wroga wiedza” jako waluta fabularna i Taśmy zostają celem 1.0.
- **Kryjówka:** hub z §10.3 — ława, szafki osobiste, stół konserwacji, prasa elaboracyjna, stół pirotechniczny, pracownia, tokarka, zbrojownia,
  strzelnica FPP. Szpital, wyzwania tygodniowe i osiągnięcia na ścianie pamięci zostają poza EA.
- **Głębia obsługi broni jest opcjonalna:** zużycie i zacięcia wyłącza ustawienie „Weapon reliability” (OFF / STANDARD / VETERAN), podrzut,
  oparcie, gorącą lufę, dwa przeładowania i masę ekwipunku — „Weapon handling” = CLASSIC. Nowy gracz ma grać rdzeń (Uwaga, Stalker, co-op)
  bez nauki warsztatu.

Zasady na czas do Gate 0 (§16.5):
1. Systemy warsztatu weryfikuje playtest (§23.3): jeśli gracze z zewnątrz ich nie używają albo gubią się w Kryjówce, upraszczamy i chowamy,
   a nie rozbudowujemy.
2. Bez nowych stanowisk, walut i warstw zużycia, dopóki §23.3 nie ma wpisów z co najmniej 3 sesji z osobami z zewnątrz.
3. Czas idzie najpierw w brakujące punkty §16.1: AI towarzysz pełnej drużyny, stabilność sesji 4-osobowej, demo.

### 16.1 MVP — co musi działać w premierze EA
- [ ] Online 1–4 (Steam P2P) + **AI towarzysz wypełniający puste sloty** (nie opcjonalne — patrz 16.3)
- [x] Strefa I kompletna (3 misje + boss) jako „vertical slice" nośny — **w prototypie: 1.1, 1.2, 1.3 i boss B1 Pijawka (od 1.7.54)**
- [x] 3 bronie główne, sidearm, maczeta, Wabik (funkcjonalny od EA — to infrastruktura Przesterowania) — **w prototypie więcej: 9 głównych, części w gniazdach, warsztat (§16.0a)**
- [x] 4 typy wrogów + Stalker w wersji z §8.1/§8.5 (mniej, ale poprawnie zbalansowanych)
- [x] System Uwagi, Przesterowanie (Q), ładunek i regeneracja, system światła
- [x] Serwerowe pociski z lag compensation (nie per-peer symulacja — patrz 18.2)
- [x] Tryb Nocny Dyżur v1 (1.7.23; bez rankingu online)
- [ ] Demo

### 16.2 Czego świadomie NIE ma w EA
Strefy II–VI, Bliźniak/Kolekcjoner, Wyzwania tygodniowe, Szpital, Wroga wiedza jako waluta fabularna (poziom profilu z XP jest w EA) i Taśmy, mod support, konsola. To świadome odcięcie — patrz 16.5.
(Do 1.7.365 lista obejmowała też „większość broni” — weszły do EA, patrz §16.0a.)

### 16.3 AI towarzysz — dlaczego nie może być „opcjonalne w 1.0"
Multiplayer jest najsilniejszym czynnikiem sukcesu w tej niszy (10x hit rate vs singleplayer), ale zakłada, że **gracz ma kogo zaprosić**. Realnie to połowa dostępnej publiczności: nie każdy ma znajomego w grze, a multiplayer o 3 w nocy jest pusty. Hot-join do botów musi działać bez gadżetu sieciowego (Peer-to-peer LAN feel) — inaczej „gra co-op" staje się „gra, w której potrzebujesz znajomego".

AI towarzysz w EA: podąża, strzela, dźwiga, reaguje na stalkera. To 2–4 mies. pracy i ratuje całą bazę graczy solo.

**Wyłączanie (od 1.7.400, `NOBOT_PLAN.md`):** towarzysz jest domyślny, ale host może go wyłączyć (lobby: „AI companion” ON / OFF; zmiana
także w kryjówce, nie w misji) — dla graczy, którzy chcą grać sami albo we dwóch bez bota. Sam bez bota: reguła upadku z §4, drezyna
(1.2) pompowana z mocą jak z botem (1,5). Dziennik sesji zapisuje `ai_companion`, a raport rozdziela wyniki „z botem / bez bota”.

### 16.4 Realny budżet i czas (liczby z researchu zestawione z kosztem)
Dane rynkowe: mediana przychodu gry na Steam ~$250–300; mediana kosztu developmentu indie ~$30–60k. To znaczy, że **mediana projektu nie zwraca kosztu** — potrzebujemy albo lepszej realizacji, albo akceptujemy, że to portfolio +uczenie. Budżetujemy to świadomie.

| Pozycja | Godziny (solo+1 pomocnik) | Uwagi |
|---|---|---|
| Netcode + synchronizacja serwerowa (16.1) | 200–300 | Największe ryzyko techniczne; zrobić w pierwszej kolejności |
| AI towarzysz (16.3) | 150–250 | Zależne od istniejącego AI stalkera |
| Strefa I (3 misje + boss) + tilesety | 250–400 | Audio jako filar grozy — nie zaniedbywać |
| Broń + pociski + pociski serwerowe | 120–200 | Zakładało 3 bronie; w grze jest 9 (§16.0a) |
| System Uwagi + Przesterowanie | 60–100 | Prototyp już ma serwerowy rdzeń |
| UI/HUD, Kryjówka, Endless | 120–180 | Zakładało Kryjówkę minimalną |
| Rusznikarstwo, stanowiska Kryjówki, strzelnica FPP | poza pierwotnym budżetem | Zrobione w 1.7.316–1.7.365 (§16.0a); utrzymanie i strojenie dalej kosztują |
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
| **EA launch** | Gate 0 | Strefa I, Endless, AI towarzysz, Kryjówka z warsztatem (§16.0a) |
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
| **Głębia warsztatu przytłacza nowych graczy, rozmywa pitch „hałas i Stalker”** | średnia | wysoki | Ustawienia CLASSIC / reliability OFF (§16.0a); playtest (§23.3) rozstrzyga, co chowamy; bez nowych systemów warsztatu do Gate 0 |

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

**Pozostałe znane ograniczenia:** zwykli wrogowie (Trzosek, Wołek) jeszcze bez A* — gonią prosto i doskakują; dołączający w trakcie walki nie widzi już istniejącego potomstwa Żyły; brak WebSocket/relay fallback; wipe odbiera łup misji (złom zebrany w tej próbie) i postęp próby.

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
| P-83 „Wanad" | start | — | Sidearm, ∞ ammo |
| Maczeta | start | — | Cicha, backstab |
| SPREAD-12 | Strefa I | 400 zł | Szeroki ostrzał |
| PELLET-8 | Strefa I | 500 zł | Bliski zasięg, odrzut |
| SINEW-6 | Strefa II | 600 zł | **Cicha** (harpun) |
| FALCON-6 | Strefa II | 700 zł | Auto-namierzanie |
| HKM-9 | Strefa III | 800 zł | DoT, kontrola tłumu |
| WRATH-4 | Strefa III | 900 zł | AoE, niszczenie gniazd |
| SPECTER-1 | Strefa IV | 1200 zł | Przebicie, elitki |

## 22. Aneks C — Historia wersji

Historia zmian jest w [`CHANGELOG.md`](CHANGELOG.md) — 244 wpisy od 1.0 do bieżącej wersji. Wydzielona w 1.7.208, żeby ten dokument
opisywał stan gry, a nie drogę do niego. Zasady prowadzenia są w nagłówku tamtego pliku.

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
| SPREAD-12 | 0,26 s, 5 śrucin ±14° | 5×7, spadek do 35% | 3,5 → 5,0 | shake 2,4, szarpnięcie kamery 2,6 (od 1.7.313 broń nie przesuwa strzelca) |
| P-83 | 0,20 s | 11 (×2 w głowę) | 0,5 → 0,9 | shake 0,5 |
| PELLET-8 | 0,8 s, 8 śrucin ±17° | 8×7, spadek do 25% | 4,5 → 6,0 | shake 4,0, odrzut 130, ogłuszenie 0,2 s |

- Lufa grzeje się z każdym strzałem i stygnie z **własną prędkością broni** (M-83 0,30/s, SPREAD-12 1,2/s, P-83 0,6/s…): krótka seria jest tania, ciągły ogień drogi (§8.1). Pełny roster i liczby: §6.7 i `prototype/WEAPONS.md`.
- Trafienie wroga: biały błysk 0,1 s, ogłuszenie 0,12 s, odrzut (Trzosek 70, Wołek 14).
- **Hitstop:** zabójstwo Trzoska 50 ms, Wołka 90 ms, własne trafienie 70 ms; cooldown 250 ms (przy 8 strz./s hitstop na każde trafienie zamroziłby grę). **Na hoście z podłączonymi klientami hitstop jest wyłączony** — `Engine.time_scale` spowalniałby symulację wszystkim; zostaje shake.
- Shake jest lokalny (kamera każdego peera), wygaszany czasem rzeczywistym.

### 23.3 Priorytety po playteście

Wypełniane po playteście „kiedy się nudziłeś, a kiedy się bałeś" (§16.0 pkt 2). Do tego czasu kolejność prac wyznacza §19.

| Data | Osoby | Nuda (moment) | Strach (moment) | Wniosek → zmiana |
|---|---|---|---|---|
| — | — | — | — | — |

Pytania o progresję do każdej sesji (`PROGRESSION_PLAN.md` P0.7, od 1.7.391; liczby z tej samej sesji daje `tools/session_progress.py`):
1. Na co wydałeś złom i czy wiedziałeś, na co zbierasz?
2. Czy zauważyłeś perki i szafki osobiste? Czy założyłeś perk po awansie?
3. Czy wiesz, do czego służą próbki?
4. Czy chciałeś zacząć od innej misji niż ta, którą dała gra?
5. Czy powtórka misji była nudna, a jeśli tak — która i za którym razem?

## Doprecyzowanie istniejącego warsztatu — 1.7.367

Odblokowane części są własnością drużyny, a montaż należy do konkretnego gracza. Nowe odblokowanie nie zmienia samoczynnie jego broni; stare zapisane konfiguracje zachowuje jednorazowa migracja profilu. Operacje ekonomiczne i zapalniki wymagają żywego gracza przy właściwym stanowisku w kryjówce i są sprawdzane na serwerze. Zmiana magazynka zachowuje naboje, opłacona nieprzyjęta dostawa czeka na odbiór, a części w kolejce badań lub produkcji nie zajmują także puli znalezisk.

Do oceny w trzech zewnętrznych sesjach: czas przygotowań drużyny (`mission_start.hub_seconds`), wybory zestawów (`equipment`), zużycie złomu i kolejki (`workshop`) oraz późniejsze użycie broni, hałas i wynik misji (`mission_end`). Zmiana nie dodaje stanowisk, walut ani nowych poziomów ulepszeń. Szczegóły: `prototype/WEAPONS.md`, regresje: `prototype/scripts/workshop_test.gd`.
