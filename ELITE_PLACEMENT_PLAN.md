# ELITE_PLACEMENT_PLAN.md — elity w zwykłej kampanii

Kontynuacja `ENEMY_PLAN.md` F4. Elity są w kodzie od 1.7.253–1.7.261, ale gracze ich nie spotykają. Plan stawia Kapłana i Rzeźnika na mapach stałymi znacznikami i dodaje pomiar potrzebny do strojenia (F4f).

## Diagnoza (dzienniki sesji autora, 567 plików, 713 startów misji, 2026-10-13 – 2026-11-01)

| | Wystawiony przez Dyrektora | Znaczniki na mapach | Wpisy w dziennikach |
|---|---|---|---|
| Kapłan | 0 | 0 | 0 |
| Rzeźnik | 0 | 0 | 1 upadek (1.7.255, 32. s misji, najpewniej `--elite`) |

- Dyrektor wypuścił 3 grupy na 713 misji, za każdym razem po 92–110 s ciszy i przy napięciu 0, a elity wymagają napięcia co najmniej 0,1.
- Odliczanie idzie tylko po 35 s bez aktywnego wroga w promieniu 520 px, przy niskim stresie.
- Elita wchodzi do losowania po 480–780 s fazy celu, a mediana tej fazy na NORMAL to 217–369 s.

### Wyniki od 1.7.400 (małe próbki)
| Mapa, NORMAL | Sukcesy | Upadki na misję | Wniosek |
|---|---|---|---|
| 1.1 | 13/18 | 0,2 | Jest zapas trudności |
| 1.2 | 2/8 | 1,1 | Tylko zamiana wroga, bez dokładania |
| 1.3 | 0/5 | 2,0 | Bez zmian (decyzja: 1.3 nietykalna) |

## Decyzje
- Stałe znaczniki zamiast naprawy Dyrektora. Naprawa warunku ciszy dosypałaby wędrowców na wszystkich mapach.
- Bez zmian na 1.3 i B1.
- Żerca poza planem: jego porwanie wymaga osobnego przemyślenia.
- Rzeźnik: 400 HP zamiast 600. Na 1.2 działa `ENEMY_HP` 1,25, więc przy 600 HP miał 750 HP, czyli 188 trafień z M-83 przy 180 nabojach startowych. Przy 400 HP: 500 HP na NORMAL, 125 trafień z M-83, 17 strzałów ze SPREAD-12, 7 z PELLET-8.

## Etapy

### E0 — pomiar
- Zdarzenie `elite`: `what` = `spawn` / `wake` / `kill`, `kind`, `src` (`map`, `director`, `finale`, `dev`), `pos`, `hp`, `max_hp`. Przy `kill` także `by`, `weapon`, `after` (s od przebudzenia) i `dmg` (źródło → obrażenia).
- `mission_start.elites` i `mission_end.elites`: stan elit na mapie (także przeżyłych, z HP).
- `mission_end.director`: sekundy fazy celu, w których odliczanie blokował każdy warunek (`relax`, `breath`, `stress`, `groups`; warunki mogą się nakładać), `open` (odliczanie szło), `no_spot`, `spawns`.

### E1 — Kapłan na 1.1
- Znacznik `A`, kolumna 112, rząd 22: obóz patrolu, leczenie sięga 3 z 5 Trzosków watahy.
- Nie zadaje obrażeń, więc wprowadza pierwszą elitę bez kary. Cicha droga konarami ma zostać.

### E2 — Rzeźnik na 1.2
- Znacznik `U`, kolumna 228, rząd 25: zastępuje Wołka na parterze pompowni, więc liczba wrogów się nie zmienia.
- Parter ma prawie 30 kafli rozbiegu, a platforma i piętro z generatorem dają półkę bezpieczną przed szarżą.
- 2 beczki `o`: kolumny 224 i 233 (wybuch 70 obrażeń bez pancerza, promień 64 px).
- Daleko od domu Stalkera i zamurowanej skrytki w hali.

### E3 — po playteście
- Strojenie F4f według zdarzeń `elite` i decyzja o Dyrektorze według `mission_end.director`.
- Jeśli stałe miejsca się opatrzą: wystawianie po postępie celu, wzorem `FINALE_SPAWNS` z 1.1.

## Przebudowa Kapłana (K1–K4, po pierwszym playteście)
Playtest autora: Kapłan wlókł nogi, był bierny, uciekał i ginął bez trudu (20,5 s od przebudzenia). Pomiar: prawa stopa przez 52% cyklu sunęła po ziemi (1,27 m), cofał się na 110 px, czyli poza zasięg krzyku, a seria M-83 blokowała krzyk.

- **K1, chód:** klip `human`, cykl 0,75 s.
- **K2, postawa:** nie cofa się (`hold` 190 px), `stun_resist`, cios łapą za 1 w przerwie krzyku, HP 350, XP 40.
- **K3, wzywanie:** pierwsze po 6 s, potem co 14 s × `enemy_cd`, gest 1,2 s, 2 Trzoski (od trzeciego wezwania 3) poza kadrem, limit żywych 4 × `boss_adds`. 60 obrażeń przerywa gest. Wezwani bez XP i łupu, padają razem z Kapłanem. Dziennik: `elite` scream, summon, summon_break.
- **K4, gesty:** klipy `summon` i `bless`, oczy i obwódka widoczne w ciemności.

Po drugim playteście: fala krzyku ma zasięg progu zapowiedzi (110 px, wcześniej 96 px i tylko 1 z 5 krzyków ogłuszył), a wezwanie bez żywego gracza nie zaczyna gestu i nie podbija licznika fal.

Rzeźnik: w trzech grach ginął w tym samym punkcie, na kratownicy w szybie na zachód od pompowni (kol. 207–212), bo nie skacze i nie rzuca. Teraz po 0,4 s wyskakuje, gdy z miejsca, w którym stoi, nie dojdzie pieszo do domu; HP oceniamy dopiero po tej zmianie.

Do sprawdzenia w playteście: czy 1.1 nie jest teraz za trudna (najpierw zwiększyć odstęp, potem zmniejszyć limit).

## Kapłan w jaskini (1.7.467, przegląd 2026-11-01)
W obozie (kol. 112) Kapłan budził się w 46–57. s misji w 6 z 7 prób, a 3 z 6 upadków z tego dnia na 1.1 przypadły na 56–72. s, wszystkie od Trzosków. To pierwsza mapa gry, więc elita spotykała gracza przed drugim nieśmiertelnikiem.

- Znacznik `A`: kolumna 170, rząd 18, środkowa półka jaskini, przed trzecim nieśmiertelnikiem (mediana zebrania 109. s).
- Półka jest 64 px nad ścieżką: na kucaka gracz przechodzi (budzi z 40 px), wyprostowany budzi z 80 px. Cicha droga zostaje.
- Leczeniem sięga tylko Trzoska z tej półki, zamiast 3 z 5 z watahy. Resztę wzywa. Wataha w obozie zostaje bez zmian.
- Do sprawdzenia w playteście: kiedy się budzi (`elite` wake), czy upadki na 1.1 się przesunęły i czy Kapłan schodzi z półki do gracza.

## Progresja
Elita daje 1 próbkę, 15–25 złomu, 60% szans na amunicję specjalną i 30% na część broni. Przy jednej zabitej elicie na misję próbek będzie ok. 1,8 zamiast 0,8, czyli 20 próbek na strefę w ok. 11 misji zamiast 25. Złom na tę strefę zbiera się przez ok. 14 misji.

## Do sprawdzenia w playteście
- Czy krzyk Kapłana (hałas 8) częściej ściąga przechodzącego Stalkera na 1.1.
- Odsetek zabitych elit i broń zabójcy, a także wpływ na wyniki 1.1 i 1.2.
- Czy 1.1 nie staje się najszybszym źródłem próbek.
- Czy szarża Rzeźnika rozbija beczki, zanim gracz ich użyje.

Powiązany szkic poza zakresem tego planu: Tunel Elite (`map_analysis/elite_tunnel/ELITE_TUNNEL_PLAN.md`).
