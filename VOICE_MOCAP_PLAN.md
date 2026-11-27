# Q8: głosy wg płci i mocap ruchu — plan

**Stan (2026-11-27):** plan, nic nie wdrożone. Przygotowane lokalnie (poza repo): kandydaci na głos kobiecy pobrani z Sonniss i pocięci na
ujęcia, strona odsłuchu `C:\deadair87\odsluch\q8_glosy\index.html`; siedem stylów ruchu z 100STYLE (BVH) w `C:\deadair87\char_src\mocap\100STYLE\`.
Kontynuacja `CHARACTER_QUALITY_PLAN.md` (Q8 „Później”) i etapu E3 z `CHARACTER_PLAN.md`. Dwie niezależne części: **A — głos**, **B — mocap**.

## 1. Stan dziś

### 1.1 Głos

Każda postać, także kobieta, ma ten sam męski głos. Wersja z nagrań (`audio_licensed/`, poza repo) i publiczna (synteza w `audio/`):

| Klucz | Źródło nagrania (`bake_hybrid.py`) | Gdzie gra |
|---|---|---|
| `player_hurt_1/2` | SoundBits „Screams & Shouts 2” `Male_Shout-of-Pain_132`, `Male_Grunt-Shout_317` | trafienie (`player.gd` 2447, 2467, 2500, 2573); krzyk [G] o 20% niżej (`_scream_fx`, 1520); wołanie i echo Mimika (`enemy.gd` 723, 731) |
| `player_down` | Gamemaster „Human Vocalizations” `voice_male_b_death_low_09` + uderzenie ciała | powalenie (`player.gd` 1588, tylko u siebie) |
| `breath_loop` | Pole Position „The Grunts Library” `Male 1 - Breathing - Gasping` | zadyszka przy zmęczeniu (`player.gd` 1880) |
| `revive` | to samo nagranie oddechu | podniesienie (`player.gd` 1712) |

Płeć jest w kodzie wyglądu (`Look.gender_of(look)`: 0 mężczyzna, 1 kobieta), a `player.look` jest replikowany, więc każdy klient wie,
jaki głos zagrać. Priorytety (`audio_director.gd` `VOICE`) i napisy (`CAPTIONS`) dopasowują klucz po najdłuższym prefiksie, więc
`player_hurt_f_1` dziedziczy priorytet i napis „[Cry of pain]” bez zmian w tabelach.

### 1.2 Ruch

Klipy z Universal Animation Library 1 i 2 (Quaternius, CC0; `art_src/animations/ual1|ual2/`) — animacja ręczna, nie nagranie ruchu.
Bieg tyłem to klip truchtu z wyprostowanym tułowiem (Q2, 1.7.705). E3 (mocap) nigdy nie wystartował: Rokoko wymaga formularza z danymi
osobowymi, a CMU nie zostało pobrane.

## 2. Część A — głos kobiecy

### 2.1 Kandydaci (pobrani 2026-11-27, `audio_lib_fetch.py get`)

Spis Sonniss GDC ma po kilka plików z każdej paczki, więc wybór jest skromny, ale wystarcza na trafienie, powalenie i oddech.
F0 to mediana wysokości z autokorelacji (męskie w grze: ok. 220–330 Hz).

| Rola | Kandydaci (ujęć) | Uwagi |
|---|---|---|
| trafienie (2) | Pole Position „The Grunts Library” `Female 1 - Grunt - Getting Hit - Medium` (10 ujęć, 0,35–0,44 s, F0 350–520), `Female 3 - Grunt - Jumping and Landing` (6), AudioDesire „Emma” `Female_Pain_20`, Articulated Sounds „Ashley” `Anger Fight Grunt Big 02` (2018 i 2019), Gamemaster `voice_female_a_attack_02`, Bottle Rocket `Gasp_Quick_Female` | Pole Position: ten sam wykonawca i studio co obecny męski oddech, 10 ujęć do wyboru — rekomendacja |
| powalenie (1) | 344 Audio `Female Scream in Pain, Agony, Wounded 2` (1,0 s), Epic Stock Media `British Detective Pain … Dying High Grunt Breath` (2 ujęcia), Gamemaster `voice_female_a_cough_03` | |
| krzyk [G] (opcja) | 344 Audio `Female Warrior 3 Scream`, SoundBits `Female_Scream_005` (2,9 s), Emma `Female_Scream_High_03` (3,4 s, F0 ≈ 600) | dziś [G] = trafienie o 20% niżej; własny krzyk to osobna decyzja (§6) |
| oddech (1) | UberDuo „Tanja” `Female, Panting, Nose, Loop` i `Breathe, Growing Panic`, ESM `British Detective Breathing … Annoyed` (1 s — za krótki na pętlę) | `revive` bierze ten sam oddech, jak dziś u mężczyzny |

Strona `C:\deadair87\odsluch\q8_glosy\index.html` pokazuje każde ujęcie osobno (wyrównane do szczytu) obok obecnych męskich plików z gry
i składa werdykt do skopiowania. Strona i ujęcia zostają na dysku: licencja Sonniss zabrania udostępniania nagrań.

### 2.2 Etapy

**A0 — odsłuch (użytkownik).** Wybór 2 ujęć trafienia, 1 powalenia, 1 oddechu; opcjonalnie krzyk [G].

**A1 — wypiek (`bake_hybrid.py`, `bake_audio.py`).**
- Nowe klucze: `player_hurt_f_1/2`, `player_down_f`, `breath_loop_f` (pętla — w `LOOPS`), `revive_f`.
- Ten sam łańcuch co wersja męska (filtr 90 Hz, nasycenie, limiter, krótki pogłos), głośność równa zmierzonej głośności klucza męskiego.
- Źródła wpisane do `tools/audio_sources.json` (`audio_lib_fetch.py add`, z sumą SHA-256).
- Wersja publiczna (`audio/`): synteza męska przesunięta o ok. +5 półtonów z przesunięciem formantów. Bez niej gra bez `audio_licensed/`
  zagrałaby u kobiety głos męski.

**A2 — gra.**
- `player.gd`: `_voice(base) -> String` zwraca `base + "_f"`, gdy `Look.gender_of(look) == 1` i klucz istnieje w manifeście (inaczej `base`);
  pięć wywołań `player_hurt`, `player_down`, `breath_loop`, `revive` przez `_voice`. Bot dostaje głos ze swojego wyglądu.
- Krzyk [G] (`_scream_fx`): głos krzyczącego, nadal o 20% niżej — chyba że A0 wybierze osobny krzyk.
- Mimik (`enemy.gd` 723, 731): wołanie przebranego Mimika i echo krzyku biorą płeć gracza, którego udaje (`enemy_mimic.gd` zna jego
  etykietę; dopisać zapamiętanie `look` przy przebraniu). Echo kobiety o `ECHO_PITCH` niżej jak dziś.
- `stop_loop("breath_loop")` przy powaleniu i odrodzeniu musi zatrzymać właściwy klucz (zapamiętać klucz w `_breath_key`).

**A3 — testy.** Test headless: dla każdego klucza `_f` istnieje plik publiczny i wpis w manifeście; `_voice` daje `_f` dla `look=8`
(kobieta scav) i klucz męski dla `look=0`; bez wersji `_f` wraca do męskiej. `bake_audio.py --check` w CI pilnuje manifestu.

Koszt: A1–A3 ok. 1–1,5 dnia, jeden PR (podbicie wersji, `CHANGELOG.md`, nowe WAV-y z nagraniami tylko lokalnie — skopiować do
`gameon/prototype/audio_licensed`).

## 3. Część B — mocap

### 3.1 Źródła (licencje sprawdzone 2026-11-27)

| Źródło | Licencja | Co ma | Stan |
|---|---|---|---|
| **100STYLE** (Ian Mason, Edinburgh; Zenodo 8127870) | CC BY 4.0 — wolno komercyjnie, wymagany dopisek w napisach: „The 100STYLE Dataset – Ian Mason” | Xsens, 60 kl./s, jeden wykonawca, 100 stylów × przód / tył / bok, chód / bieg, postój; `Frame_Cuts.csv` z granicami ujęć | pobrane 7 stylów (146 MB, przez HTTP Range bez całego archiwum 1,5 GB): `Neutral`, `Swat`, `Crouched`, `OnToesCrouched`, `InTheDark`, `Rushed`, `LimpLeft` |
| **CMU Motion Capture Database** (BVH Bruce'a Hahne'a, cgspeed) | wolno używać i sprzedawać w produktach; nie wolno sprzedawać samych danych | ok. 2500 ujęć: skoki, lądowania, upadki, przysiad i wstawanie | do pobrania (wybrane ujęcia) |
| Rokoko — darmowe paczki | „w każdej grze, także komercyjnie” | chód, bieg, postój | formularz z danymi osobowymi — tylko jeśli 100STYLE i CMU nie wystarczą |
| ~~Bandai Namco Research Motion Dataset~~, ~~Ubisoft LaFAN1~~ | CC BY-NC / CC BY-NC-ND | — | odpadają: zakaz użycia komercyjnego |

Szkielet 100STYLE: `Hips`, `Chest`–`Chest4`, `Neck`, `Head`, `*Collar`, `*Shoulder`, `*Elbow`, `*Wrist`, `*Hip`, `*Knee`, `*Ankle`, `*Toe`
(23 kości, jak nasz bez palców). Surowe BVH zostają poza repo (rozmiar); do repo idą tylko klipy przeniesione na nasz szkielet
(`art/char3d/anim/*.glb`) i wpis w `art_src/animations/SOURCE.md`.

### 3.2 Co zamieniamy

| Stan w grze (`char_clips.gd`) | Dziś (UAL) | Kandydat mocap | Po co |
|---|---|---|---|
| `run` | `Sprint_Loop` | `Neutral_FR`, `Swat_FR` | naturalny krok i tułów; Swat = bieg z bronią przy ciele |
| `run_back` | trucht `jog` z wyprostowanym tułowiem | `Neutral_BR`, `Swat_BR` | prawdziwy bieg tyłem zamiast przeróbki truchtu |
| `walk` | `walk` | `Neutral_FW`, `InTheDark_FW` (ostrożny) | |
| `crouch_walk` | `crouch_walk` | `Crouched_FW`, `OnToesCrouched_FW` (skradanie) | |
| `idle` | `idle` + oddech z kodu (Q2) | `Neutral_ID`, `Swat_ID` | żywy postój bez pętli z kodu |
| nowy: utykanie przy 1 HP | — | `LimpLeft_FW`, `LimpLeft_FR` | czytelny stan „ranny” bez paska życia — decyzja w §6 |

Ręce z bronią dalej prowadzi IK (`upper` w tabeli `CLIPS` miesza klip z pozą z kodu), więc z klipu bierzemy głównie nogi, biodra i tułów.
Skok, spadanie, lądowanie, trafienie i upadek zostają z kodu / UAL (sprawdzone w 1.7.209); CMU dopiero, jeśli B1 pokaże, że warto.

### 3.3 Etapy

**B0 — narzędzie (`prep_anim3d.py`).**
- Import BVH (`bpy.ops.import_anim.bvh`, 60 → 30 kl./s) obok GLB.
- `ALIASES` dla nazw Xsens: `Chest`→`Spine`, `Chest2`/`Chest3`→`Spine1`/`Spine2`, `Collar`→`Shoulder`, `Shoulder`→`Arm`,
  `Elbow`→`ForeArm`, `Wrist`→`Hand`, `Hip`→`UpLeg`, `Knee`→`Leg`, `Ankle`→`Foot`, `Toe`→`ToeBase`.
- Wycięcie jednego cyklu kroku ze stałą prędkością: `--range=a:b` z `Frame_Cuts.csv` i wybór szwu o najmniejszym błędzie pozy
  (dwa kolejne lądowania prawej stopy), potem `--step-sync` jak dziś.

**B1 — porównanie.** `shot_anim3d.gd --set=run|stand|crouch` i film: UAL obok mocap, mężczyzna i kobieta, w skali gry i w zbliżeniu.
Wybór użytkownika per stan.

**B2 — podmiana.** Tabela `CLIPS` (`upper`, `bounce`, `drop` dostrojone od nowa), `SOURCE.md`, dopisek 100STYLE w napisach
(`CREDITS.md` + ekran napisów w grze), wersja, `CHANGELOG.md`.

**B3 — testy.** `test_proportions.gd`, `test_aim_points.gd` (błąd ≤ 1 px), poślizg stóp (pozycja stopy na gruncie w fazie podparcia),
`bench_char3d.gd` (klipy z 60 kl./s nie mogą podnieść kosztu), CI.

Koszt: B0 ok. 1 dzień, B1 0,5 dnia, B2–B3 ok. 1 dzień. Jeden PR po B1 (z wybranymi klipami).

## 4. Kolejność

| Kolejność | Etap | Czas | Zależy od |
|---|---|---|---|
| 1 | A0 odsłuch | — (użytkownik) | strona gotowa |
| 2 | B0 narzędzie BVH | 1 d | — (równolegle z A0) |
| 3 | A1–A3 głos kobiecy | 1–1,5 d | A0 |
| 4 | B1 porównanie klipów | 0,5 d | B0 |
| 5 | B2–B3 podmiana i testy | 1 d | B1 (wybór) |

Razem ok. 3,5–4 dni pracy.

## 5. Ryzyka

- **Mało ujęć kobiecych:** spis Sonniss ma po kilka plików z paczki. Dwa warianty trafienia z jednej sesji Pole Position mogą brzmieć
  zbyt podobnie — wtedy drugi wariant z innej paczki (Emma, Ashley).
- **Krzyk [G] o 20% niżej** u kobiety może brzmieć jak męski albo „zwolniony” — sprawdzić przy A1; w razie czego osobny krzyk.
- **Mimik:** echo krzyku musi brzmieć jak ofiara, inaczej gracze rozpoznają przebranie po płci głosu (albo odwrotnie: zdradzi go męski
  głos przy kobiecym wyglądzie).
- **Jeden wykonawca 100STYLE:** kobieta i mężczyzna dostaną ten sam ruch (jak dziś z UAL). Różnicę płci w chodzie można dodać z kodu
  (kołysanie bioder) — decyzja w §6.
- **Xsens:** dryf i poślizg stóp w długich ujęciach, zmiany tempa w środku ujęcia — stąd wycinanie cyklu ze stałą prędkością i pomiar
  poślizgu w B3.
- **Prędkość:** wykonawca biegnie inaczej niż postać w grze; `--step-sync` dopasowuje fazę, a długość kroku trzeba sprawdzić na filmie.
- **Bieg tyłem z mocap** pochyla tułów inaczej niż dzisiejsza przeróbka — może wrócić efekt „moonwalka”; B1 porównuje oba.

## 6. Decyzje

1. **Głos kobiecy:** wybór ujęć na stronie odsłuchu (trafienie ×2, powalenie, oddech).
2. **Krzyk [G]:** zostaje trafieniem o 20% niżej czy dostaje własny krzyk (dla obu płci)?
3. **Mimik:** głos udawanej ofiary (rekomendacja) czy zawsze męski?
4. **Mocap:** 100STYLE jako główne źródło z dopiskiem w napisach (rekomendacja); CMU tylko gdy B1 pokaże braki; Rokoko pominąć.
5. **Utykanie przy 1 HP:** nowy stan ruchu (zmienia czytelność rozgrywki — inni widzą, kto jest ranny) — tak / nie / po playteście.
6. **Chód kobiety:** ten sam klip co mężczyzna czy lekkie kołysanie bioder z kodu?

## 7. Pliki

- Głos: `prototype/tools/bake_hybrid.py`, `bake_audio.py`, `audio_sources.json`, `scripts/audio_manifest.gd` (generowany),
  `scripts/player.gd`, `scripts/enemy.gd`, `scripts/enemy_mimic.gd`, nowy test w `prototype/tests/`.
- Mocap: `prototype/tools/prep_anim3d.py`, `scripts/char_clips.gd`, `art/char3d/anim/`, `art_src/animations/SOURCE.md`,
  `art/char3d/mpfb/CREDITS.md`, ekran napisów.
- Lokalnie, poza repo: `C:\deadair87\audio_lib\sonniss\…` (nagrania), `C:\deadair87\odsluch\q8_glosy\` (odsłuch),
  `C:\deadair87\char_src\mocap\100STYLE\` (BVH, `Frame_Cuts.csv`, `Dataset_List.csv`).
