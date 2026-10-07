# Plan: Strefa II „Martwa Wieś" (faza C)

Status: **plan, nic jeszcze nie zaimplementowano** (stan z 2026-10-08, po zamknięciu perków B1–B4, PR #75–#78).
Źródło wymagań: GDD §9 (Strefa II), §7.2 (Kapłan jako elita), §7.4 (boss Kapłan), §20 (tabela misji).

Proponowane 7 faz, każda jako osobny PR z testem w `--gentest` / `--weapontest` i wpisem w GDD.

## Co już jest
- **Wrogowie ze Strefy II:** Ślepiec, Mimik, Pijawka, Wołek i Skoczek są w `enemy.gd`.
- **Bronie:** FALCON-6 i SINEW-6 istnieją w kodzie jako `SOKOL6` i `CIEGNO6`; w warsztacie czekają w `Scrap.LATER`. Jest mechanizm trofeów (`trophies` / `REWARDS`), który odblokowuje broń po bossie.
- **Typy celów:** `generators`, `nests`, `tags`, `boss`, faza `BOSS` w `mission.gd`.
- **Wzór na bossa:** `leech.gd` i `maps/z1_b1.gd` (fale, fazy).
- **Reszta infrastruktury:** kryjówka, XP za misje (`Profile`), Nocny Dyżur, `--maptest`.

## Czego brakuje
- **Kapłan** — nie ma go w kodzie (potrzebny jako elita i boss).
- **Ocaleni** — nie ma żadnego NPC; „uratuj 4 ocalałych" wymaga nowego systemu.
- **Dzwon i fale** — nie ma obrony ani fal wrogów (Dyrektor tylko dosypuje wędrowców).
- **Totemy i fazy ciszy** — nie ma ich.
- **Cel „przejście bez alarmu"** — nie ma takiego typu celu.
- **Oprawa wsi** — brak kafli, palety i tła.
- **Strefy** — `CAMPAIGN` to jedna płaska lista, a testy w `main.gd` mają na sztywno Strefę I.
- **Postać „Wulkan"** — w kodzie nie ma systemu postaci (ani „Igły" ze Strefy I); pomijamy.

## Fazy

**C0. Fundament stref (mały).**
- Pojęcie strefy w `level.gd`: `ZONES` z listą misji i bramką.
- Wybór strefy w lobby i na odprawie; Strefa II zablokowana, dopóki host nie ma trofeum Pijawki.
- Kryjówka zostaje ta sama (inne radio i odprawa z danych mapy).
- Poprawka sztywnych testów kolejności kampanii.
- Paleta wsi (`AMBIENT`) i nowe kafle: deski, dach, kamień cerkwi.

**C1. Kapłan jako elita (średni).**
- Nowy rodzaj wroga `kaplan`: 250 HP, krzyk w promieniu 6 m ogłuszający graczy, leczenie pobliskich Trzosków.
- Nowy status ogłuszenia gracza (RPC jak `_scream_fx`, serwer rozstrzyga).
- Sprite przez `tools/char_kaplan.py` (wzór: `char_leech.py`), wpis w bestiariuszu, dźwięki krzyku.
- Test: krzyk ogłusza tylko w zasięgu, leczenie nie przekracza maksymalnego HP, zabicie Kapłana zatrzymuje leczenie.

**C2. Misja 2.1 „Cisza" (średni).**
- Nowy cel `pass`: dojdź do wyjścia, mijając Ślepców (słuch, kucanie ratuje).
- Alarm = Uwaga ≥ 60 (budzi Stalkera). Cel poboczny „Duch" = zero wykryć (rozszerzenie licznika `peak_noise`).
- Mapa ręczna ~220×44 z generatorem w `tools/`, `--maptest`, dane `maps/z2_m1.gd`.

**C3. Misja 2.2 „Piwnice" (największe ryzyko mechaniczne).**
- Nowy `survivor.gd`: leżący NPC podnoszony przytrzymaniem [E] (ten sam wzór postępu i RPC co podnoszenie gracza).
- Po podniesieniu biegnie do wyjścia i znika.
- Jeden z ocalałych to Mimik, demaskowany jak dziś (latarka, strzał, podejście).
- Cel poboczny: pamiętnik górnika (pickup). Cel `rescue` (4 osoby).

**C4. Misja 2.3 „Dzwon" (duży).**
- Nowe `bell.gd` i `wave.gd`: trzy fale hordy ze spawnerów, dzwon budzi hordę.
- Kapłan w drugiej i trzeciej fali.
- Potem ucieczka (istniejąca faza `EXTRACT`).
- Cel poboczny: zniszcz 2 gniazda (`nest.gd` istnieje).

**C5. Boss B2 „Kapłan" (duży, wzór z Pijawki).**
- Arena z 4 totemami (cele niszczalne).
- Krzyk bossa gasi światło (flary i lampy).
- Fazy ciszy: boss „nasłuchuje" i w tym czasie każdy strzał podnosi Uwagę i wywołuje krzyk (wykrycie strzału z hałasu w `NoiseMgr`).
- Skalowanie HP przez `Difficulty` od razu (lekcja z „zbyt łatwej" Pijawki).
- Test headless w stylu `--leechtest`, strojenie symulacją w stylu `--leechsim`.

**C6. Integracja (średni).**
- Odblokowanie FALCON-6 i SINEW-6 w warsztacie (ceny z GDD 700 / 600, przeskalowane do złomu gry).
- Trofeum Kapłana, pula Nocnego Dyżuru ze Strefy II.
- XP i bonusy pierwszego ukończenia (działają już przez `Profile`).
- Wpisy kodeksu, README, tabela misji w GDD; playtest ogólny.

## Decyzje do potwierdzenia (rekomendacje)
1. **Wybór strefy** w lobby i kryjówce, Strefa II odblokowana trofeum Pijawki (alternatywa: jedna długa kampania). Rekomendacja: wybór strefy — nie psuje testów i pętli Strefy I.
2. **Kiedy odblokować SINEW-6 i FALCON-6.** GDD mówi „nagroda strefy", ale cicha broń pasuje do faz ciszy bossa. Rekomendacja: SINEW-6 po 2.2, FALCON-6 po bossie.
3. **Alarm w 2.1 miękki:** przekroczenie progu budzi hordę i kosztuje cel poboczny, ale nie kończy misji.
4. **Ocaleni w 2.2** znikają przy wyjściu i nie towarzyszą drużynie (znacznie prostsze).
5. **Kolejność:** C0, C1, C2, C3, C4, C5, C6 (Kapłan jako zwykły wróg przed misją 2.3 i bossem).

## Ryzyka
- **Mapy ręczne, bez playtestu.** Mitygacja: generator w `tools/`, `--maptest` na osiągalność, krótkie iteracje po zrzutach.
- **Skala:** największy obszar z roadmapy, mniej więcej 7 razy więcej niż faz B1–B4 razem. Pierwszy grywalny kawałek to C0–C2.
- **Brak zewnętrznego playtestu.** `prototype/PLAYTEST.md` (§16.0 GDD) ma decydować o treści; sensownie zrobić go po C2, przed ocalałymi i dzwonem.
- **Trudność bossa ciszy** wymaga strojenia symulacją, nie na oko.
