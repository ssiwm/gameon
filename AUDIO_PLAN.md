# Plan: refaktor dźwięku — źródła hybrydowe i propagacja po mapie

Status: **plan z 2026-10-12; F0–F5 zrobione, F6 (droga dźwięku po mapie, wersje bliska / daleka) i F8 (format wydania) wdrożone, zostaje eksperyment F7; 129 plików z nagrań żyje poza repo (`audio_licensed/`) — stan w §7.** Oparty na przeglądzie kodu (`tools/bake_*.py`, `scripts/audio_director.gd`,
`default_bus_layout.tres`, `AUDIO.md`), nie na próbnej implementacji — rozmiary faz są szacunkowe. Kontynuacja `prototype/AUDIO.md`
(overhaul v2), który sam stwierdza w §5: „to nie jest jeszcze AAA w sensie brzmienia” i „brzmienia nie oceniałem uchem”.

Cel: dźwięk, który brzmi jak nagranie, a nie jak syntezator, i z którego da się odczytać, **skąd** coś nadchodzi — bez wymiany
runtime'u i bez zmian w sieci.

## 1. Stan obecny (z kodu)

- **Assety:** 157 plików WAV (stan z dnia planu; po F5 — 180) (48 kHz / 16 bit, 139 mono, 18 stereo, 330 s, 46 MB) w `prototype/audio/`, commitowane zwykłym gitem (nie LFS).
  Wszystkie powstają z czystej syntezy numpy (`bake_weapons.py`, `bake_sfx.py`, `bake_amb.py`, `bake_music.py`); `audio_dsp.py` nie ma
  funkcji wczytującej plik dźwiękowy.
- **Finalizacja:** `bake_common.finalize()` — jedyne miejsce zapisu: normalizacja (peak albo LUFS), true-peak ≤ −1,5 dBTP, fade'y, dither.
  Bake jest deterministyczny bit w bit; `audio_audit.py` mierzy LUFS, szczyty, szwy pętli, zgodność z mono, różnorodność wariantów.
- **Runtime:** cała gra woła tylko `Audio.play*()` z kluczem; węzły odtwarzające są wyłącznie w `audio_director.gd` (i w `voice.gd`).
  Dźwięk pozycyjny = `AudioStreamPlayer2D` (panorama lewo–prawo, zasięg 1600 px); okluzja = 3 promienie → 3 szyny z filtrem;
  pogłos = 12 promieni wokół słuchacza steruje jednym efektem Reverb; słuchacz jest dzieckiem `Camera2D` lokalnego gracza.
- **Luki znalezione przy przeglądzie:**
  - Wrogowie nie mają własnych głosów: Trzosek, Wołek, Pijawka i bossowie grają `stalker_shriek` / `stalker_growl` z inną wysokością.
    Stalker nie ma przez to własnej tożsamości dźwiękowej, choć GDD §13 na niej opiera grozę.
  - Brak warstw zależnych od odległości: strzał z 5 m i z 80 m to ta sama próbka, tylko ciszej.
  - Dźwięk zza ściany jest stłumiony, ale dochodzi „na wprost”, a nie z otworu, którym naprawdę by dotarł.
  - Położenie góra–dół jest niesłyszalne (panorama 2D działa tylko w poziomie).
  - Cztery rodziny są w manifeście, ale żaden skrypt ich nie gra: `amb_air`, `amb_drips`, `mine_beep_loop`, `radio_static_loop`, `stalker_appear`.
  - Dokumentacja się rozjechała: `README.md` podaje 152 ścieżki, `AUDIO.md` 116, w repo jest 157.

## 2. Zasady wspólne

1. **Klucze i API się nie zmieniają.** `Audio.play*()`, klucze manifestu i liczby wariantów zostają; nowe dźwięki dostają nowe klucze.
   Symulacja, sieć i testy headless nie są dotykane w fazach F1–F5.
2. **Każdy dźwięk ma przepis.** Przepis = lista źródeł (nagranie, plik wygenerowany, warstwa syntetyczna) + obróbka w `bake_*.py`.
   Zasada z `CLAUDE.md` („edytuj generatory, nie wynikowe pliki”) obowiązuje dalej.
3. **Trzy rodzaje źródeł, każde do czego innego:**

   | Źródło | Do czego | Gdzie leży |
   |---|---|---|
   | Nagrania z bibliotek royalty-free (archiwum Sonniss GDC; pojedyncze pliki pobiera `tools/audio_lib_fetch.py`) | strzały, eksplozje, trafienia, kroki, szkło, drzwi, przeładowania, głosy stworów | `art_src/audio_lib/`, `audio_lib/` obok repo albo katalog z `DA87_AUDIO_LIB` — poza repo, jak `art_src/world_pbr_cc0/` |
   | Pliki wygenerowane lokalnie (Stable Audio 3 Medium w ComfyUI) | głosy Stalkera i wrogów, ambienty, tekstury bez odpowiednika w bibliotekach | `art_src/audio_gen/` — w repo (LFS), z opisem i ziarnem |
   | Synteza (obecna) | UI, radio, pisk w uszach, sub-bas i ogony pod nagraniami, muzyka | kod w `tools/` |

4. **Determinizm względem źródeł.** `tools/audio_sources.json` (w repo) trzyma dla każdego źródła: plik, paczkę, licencję i SHA-256.
   Ten sam zestaw źródeł = ten sam bajt wyniku; `audio_lib_fetch.py sync` pobiera komplet z rejestru i sprawdza sumy.
   Brak źródła na dysku: wersja z nagrań jest pomijana z ostrzeżeniem (`--strict` zamienia je w błąd).
7. **Dwie wersje jednego klucza (decyzja 2026-10-12, §6 pkt 3).** Repo jest publiczne, a licencja bibliotek zabrania udostępniania
   dźwięków dalej. Dlatego: w `prototype/audio/` (repo) leży wersja **publiczna** każdego klucza — synteza albo plik wygenerowany;
   wersja **z nagrań** powstaje lokalnie w `prototype/audio_licensed/` (poza repo, ta sama ścieżka) przez `bc.hybrid()`.
   Gra bierze plik z `audio_licensed/`, jeśli tam jest (`audio_director.gd: _path()`), więc trafia też do buildów robionych na maszynie
   z nagraniami. Obie wersje mają tę samą głośność docelową — miks nie zależy od tego, która gra. Każdy nowy klucz musi mieć wersję publiczną.
5. **Akceptacja uchem, nie tylko pomiarem.** Każda faza z assetami kończy się odsłuchem A/B na słuchawkach (strona z F0) i raportem
   `audio_audit.py --compare`. Pomiar pilnuje techniki, o brzmieniu decyduje odsłuch.
6. **Mały rebake.** Pieczemy tylko zmieniane grupy (`--only`), żeby niezmienione pliki zostały bit w bit takie same — każdy podmieniony
   WAV zostaje w historii gita na zawsze (repo ma już 256 MB).

## 3. Fazy (każda osobny PR)

| Faza | Zakres | Pliki | Kryterium akceptacji | Szac. |
|---|---|---|---|---|
| **F0 Punkt odniesienia** | Raport audytu „przed” do `tools/baseline/`; `tools/audio_ab.py` — strona HTML z parami odtwarzaczy (wersja z `main` obok bieżącej), pogrupowana rodzinami, z trybem „na ślepo”; potwierdzenie licencji u źródła (tekst licencji paczki Sonniss, karta modelu Stable Audio 3) | `tools/audio_ab.py` (nowy), `tools/baseline/` | strona otwiera się lokalnie i gra obie wersje; licencje zapisane w `prototype/audio/CREDITS.md` | 0,5–1 d |
| **F1 Warstwa źródeł w bake'u** | `audio_dsp.py`: wczytanie pliku przez ffmpeg (dowolny format → 48 kHz, float), wycinek, zmiana wysokości i długości; `bake_common.py`: `src(id)` ze sprawdzeniem SHA-256 i polityką braku źródła; `tools/audio_sources.json`; generowanie `CREDITS.md`; tryb `audio` w `comfy_gen.py` (szablon `audio_stable_audio_3_medium.json`); testy w `test_audio_dsp.py` | `tools/audio_dsp.py`, `bake_common.py`, `bake_audio.py`, `comfy_gen.py`, `.gitignore`, `.gitattributes` | pełny bake nie zmienia ani jednego pliku w `audio/` (`git status` czysty); testy DSP przechodzą | 1–1,5 d |
| **F2 Pilotaż — bramka A** | Trzy rodziny w nowej technice: `m83_shot` (6 wariantów), `step_concrete` (5), `stalker_growl` (2). Dla Stalkera dwie wersje do wyboru: z biblioteki i wygenerowana | `bake_weapons.py`, `bake_sfx.py` | **odsłuch A/B przez Ciebie**; decyzja: idziemy dalej, i które źródło wygrywa w której kategorii | 1–2 d |
| **F3 Bronie** | 75 plików: strzały 10 broni, pompka, przeładowania, trafienia, rykoszety, świst, łuski, wybuchy. Przepis strzału: nagrany atak i korpus + syntetyczny sub + mechanika. Nowe klucze `<broń>_far_N` i `explosion_far_N` (daleka wersja: ogon, bez ataku) — na razie nieużywane, gra je F6. Dwa PR-y: strzały / reszta | `bake_weapons.py`, `WEAPONS.md` | A/B; `tools/test_weapons.sh` przechodzi; audyt bez uwag; różnorodność wariantów nie spada poniżej obecnej (0,71) | 3–5 d |
| **F4 Gracz i świat** | Kroki (4 powierzchnie × 5), lądowanie, wysiłek i ból, drzwi, szkło, skrzypienia, grzmot, flara, generator, deszcz, wiatr. Pętle domykane przez `seam_xfade` | `bake_sfx.py`, `bake_amb.py` | A/B; szwy pętli w normie audytu; kucanie nadal wyraźnie cichsze (GDD §8.1) | 2–3 d |
| **F5 Stalker i głosy wrogów** | Stalker: 11 plików od nowa, z własnym charakterem. **Nowe rodziny** dla Trzoska, Wołka, Pijawki, Ślepca, Podsłuchacza i bossów (zapowiedź ataku, ból, śmierć — po 2–3 warianty); skrypty wrogów przestają pożyczać `stalker_*`; napisy dźwięków dla nowych kluczy | `bake_sfx.py`, `bake_audio.py` (CAPTIONS), `enemy.gd`, `leech.gd`, `boss.gd`, `translations/ui.csv` | Stalkera da się rozpoznać na ślepo wśród wrogów; `--maptest` i test broni przechodzą | 3–4 d |
| **F6 Odległość i droga dźwięku** | (a) `play_at` miesza wersję bliską i daleką wg odległości dla rodzin z `_far`. (b) Propagacja po mapie: zalewanie wolnych kafli od słuchacza (odświeżane, gdy zmieni kafel, rozłożone na klatki) daje długość drogi i kierunek ostatniego otworu; źródło zasłonięte gra z tego kierunku, z głośnością wg długości drogi; wygrywa głośniejsza z dróg „przez ścianę” (obecne filtry) i „dookoła”. Zawalenia i rozbite ściany unieważniają wynik. Tylko lokalnie, bez serwera | `audio_director.gd`, `level.gd` (publiczny odczyt siatki), `README.md`, `AUDIO.md` | strzał za rogiem słychać od strony przejścia; koszt ≤ 0,3 ms na klatkę (`perf_bench.sh`); napisy dźwięków dalej pokazują prawdziwy kierunek | 3–4 d |
| **F7 Eksperyment HRTF — bramka B** | Tylko Stalker, tylko na gałęzi: słuchacz na pozycji gracza, źródło w 3D, wtyczka Nexus Resonance (Steam Audio). Test na ślepo: czy da się wskazać kierunek, w tym górę i dół | gałąź eksperymentalna | decyzja: wdrażamy jako opcję „Słuchawki” albo porzucamy; bez scalania przed decyzją | 1–2 d (limit) |
| **F8 Format wydania** | Import: kompresja QOA dla efektów, Ogg Vorbis dla muzyki i ambientu; sprzątnięcie nieużywanych rodzin albo podpięcie ich w grze; wyrównanie liczb w `README.md` i `AUDIO.md` | `*.wav.import`, dokumentacja | rozmiar eksportu audio mniejszy o ponad połowę, bez słyszalnej różnicy w A/B | 0,5–1 d |

Razem ok. 15–23 dni roboczych. Muzyka (stemy) jest poza tym planem — osobna decyzja po F5.

## 4. Kolejność i zależności

- F0 → F1 → F2 są sekwencyjne; **F2 jest bramką** — jeśli odsłuch nie pokaże wyraźnej poprawy, plan wraca do stołu przed wydaniem dni na F3–F5.
- F3, F4, F5 są od siebie niezależne i mogą iść w dowolnej kolejności; rekomendowana: bronie → Stalker i wrogowie → gracz i świat
  (wg tego, co gracz słyszy najczęściej i co niesie grozę).
- F6 nie zależy od assetów poza punktem (a), który potrzebuje kluczy `_far` z F3. Punkt (b) można robić równolegle od razu.
- F7 po F5 (potrzebny dobry głos Stalkera, żeby test miał sens).
- Względem trwającego refaktoru grafiki („stan zamiast węzłów 2D”): brak wspólnych plików w F1–F5. F6 czyta siatkę z `level.gd` i zakłada, że
  `Camera2D` gracza zostaje — do potwierdzenia przy etapie 5 tamtego planu. Kroki gracza liczone są z przebytej drogi, nie z klatek animacji,
  więc etap 4 (pozy) ich nie dotyka.

## 5. Ryzyka

| Ryzyko | Skutek | Ograniczenie |
|---|---|---|
| Pliki wygenerowane rozmywają ostre ataki | „miękkie” strzały i trafienia | broń i trafienia tylko z nagrań; generowanie do głosów i tekstur; bramka A |
| Licencje | materiał, którego nie wolno wydać | F0 czyta licencje u źródła; `audio_sources.json` + `CREDITS.md` dla każdego pliku; surowe nagrania z bibliotek nie trafiają do repo |
| Stable Audio 3 nie mieści się w 10 GB VRAM albo brzmi słabo | brak darmowego źródła głosów | sprawdzane w F2; rezerwa płatna: ElevenLabs SFX v2 |
| Niespójność brzmienia między źródłami | bronie z różnych paczek „nie z jednej gry” | wspólny tor w `finalize()` i wspólne ogony; odsłuch całych rodzin, nie pojedynczych plików |
| Propagacja po mapie myli gracza | dźwięk „z drzwi” zamiast zza ściany odbierany jako błąd | mieszanie obu dróg, nie przełączanie; próg i wagi strojone na jednej mapie przed włączeniem wszędzie; flaga dev do wyłączenia |
| Koszt zalewania siatki w GDScript | spadek klatek na dużych mapach | promień ograniczony do zasięgu słyszalności, praca rozłożona na klatki, pomiar w kryterium F6 |
| Wtyczka HRTF | wersja 1.0.1 oznaczona przez autora jako niestabilna; gotowe pliki dla Linuksa (CI) niepotwierdzone | tylko eksperyment na gałęzi z limitem czasu |
| Rozrost repo | każdy podmieniony WAV zostaje w historii | zasada 6; ewentualne przejście `prototype/audio/` na LFS dopiero po sprawdzeniu limitu transferu w CI |

## 6. Decyzje do podjęcia

1. ~~Pobrania do pilotażu~~ — zgoda z 2026-10-12; co faktycznie pobrano: §7.
2. ~~Bramka A~~ — odsłuch 2026-10-12: `m83_shot`, `step_concrete` i `stalker_growl` w wersji z nagrań. Plan idzie dalej (F3–F5),
   a nagrania są źródłem pierwszego wyboru także dla głosów; generowanie zostaje dla tego, czego w bibliotekach nie ma.
3. ~~Assety z nagrań a publiczne repo~~ — decyzja 2026-10-12: **repo zostaje publiczne, assety z nagrań tylko lokalnie i w buildach**
   (zasada 7). Tło: licencja Sonniss 2.0 zabrania udostępniania dźwięków innym „jako efektów dźwiękowych”, także przerobionych, a zmiksowany
   WAV w publicznym repo każdy może pobrać. Rozważane i odrzucone: repo prywatne, pisemna zgoda Sonniss. Osobne prywatne repo na
   `audio_licensed/` jest możliwe później (to zwykły katalog), ale niepotrzebne: komplet odtwarza się z rejestru (`sync` + bake, ok. 1 min).
4. **Rejestracja w Stability AI** przed komercyjnym użyciem plików wygenerowanych (wymóg licencji; robi to właściciel projektu).
5. **Głosy wrogów w F5:** osobne dla każdego gatunku (plan zakłada tak) czy na początek tylko odróżnienie Stalkera od reszty.

## 7. Stan po F0–F2 (2026-10-12)

**Jak mieć wersje z nagrań u siebie** (każda kopia repo osobno, bo `audio_licensed/` leży w projekcie Godota):

```bash
python prototype/tools/audio_lib_fetch.py sync      # nagrania z rejestru → katalog nagrań (sprawdza sumy)
cd prototype && python tools/bake_audio.py          # synteza → audio/ (bez zmian), wersje z nagrań → audio_licensed/
godot --headless --path . --import                  # log gry: „[AUDIO] manifest OK: 157 ścieżek, z nagrań: N”
```

Porównanie w grze: flaga `--synthaudio` wymusza samą syntezę. Odsłuch obok siebie: `python tools/audio_ab.py --licensed`.

**F0 — zrobione.** `tools/baseline/audit_refactor_before.json` (157 plików), `tools/audio_ab.py` (strona A/B „na ślepo”, WAV-y zaszyte w jednym
pliku HTML; tryby `--alts` i `--ref`), licencje przeczytane u źródła i zapisane w `tools/audio_sources.json` → `audio/CREDITS.md`.

**F1 — zrobione.** `audio_dsp.py`: `read_audio`, `resample`, `cut`, `onset`, `from_onset`, `repitch`. `bake_common.py`: `src()` ze sprawdzaniem
SHA-256, `hybrid()` (wersja z nagrań → `audio_licensed/`; brak źródła = pominięcie), `alt()` (wersja alternatywna do odsłuchu), `--strict`, `--alts`.
`tools/audio_lib_fetch.py`: spis, pobieranie pojedynczych plików z archiwów Sonniss i `sync` z rejestru. `comfy_gen.py audio`: Stable Audio 3.
Kryterium spełnione: pełny bake bez źródeł i ze źródłami nie zmienia żadnego pliku w `audio/`; testy DSP i testy źródeł przechodzą.

**F2 — zrobione, wybrane wersje z nagrań (bramka A).** Po odsłuchu trzy rodziny są wersjami z nagrań w `audio_licensed/` (13 plików,
zgodnych co do bajta z odsłuchanymi); przepisy w `tools/bake_hybrid.py` wołane z builderów zaraz po syntezie tego samego klucza.
Przegrana wersja wygenerowana warkotu usunięta razem ze źródłami. Do poprawy w F3: różnorodność wariantów `m83_shot` z nagrań to 0,25
wobec 0,45 w syntezie (próg audytu „prawie identyczne” to 0,25) — sześć wariantów powstaje z pięciu strzałów jednej broni.
Wersje w odsłuchu:

| Rodzina | Wersje | Źródła |
|---|---|---|
| `m83_shot` ×6 | obecna / z nagrań | AKM z 1 m (trzask) + AK-47 w otwartym terenie (korpus, ogon) + syntetyczny sub |
| `step_concrete` ×5 | obecna / z nagrań | pięć kroków z nagranego marszu w butach po betonie |
| `stalker_growl` ×2 | obecna / z nagrań / wygenerowana | „Monster Growls 4” (dwa najniższe warknięcia) albo Stable Audio 3 Medium; obie obniżone, z oktawą w dół i halą |

Pomiar (nie odsłuch): strzał z nagrań ma środek ciężkości widma ok. 1,4 kHz zamiast 250 Hz (obecny to głównie sub-bas), ogon do −40 dB
ok. 380 ms zamiast 255 ms, głośność zrównana z obecnym do 0,5 LU. Kroki z nagrań są ciemniejsze powyżej 4 kHz niż syntetyczne. Alternatywy
pieką się deterministycznie (dwa przebiegi = te same sumy).

**F3–F5 — odsłuchy 2026-10-12, wybrane rodziny grają z `audio_licensed/` (razem z bramką A 119 plików z nagrań, do tego 10 wyprowadzonych z nich dalekich wersji z F6):**

| Rodzina | Werdykt | Źródła wersji z nagrań |
|---|---|---|
| `spread12_shot` ×3 | z nagrań | Saiga-12 z 1 m (pojedyncze strzały), zaciśnięty ogon, syntetyczny sub |
| `srut8_shot` ×3, `srut8_pump` ×2 | z nagrań | ta sama Saiga 3 półtony niżej + front USAS-12 + większy sub; pompka z nagrania 12 Gauge |
| `gniew4_shot` ×2 | z nagrań | odpalenie granatnika dymnego + niski korpus + hala |
| `explosion` ×2 (stereo) | z nagrań | dwa nagrania dużych eksplozji + syntetyczny sub i ostry front |
| `ciegno6_shot` ×2 | z nagrań, **wersja 2** | wersja 1 (samo zwolnienie cięciwy + brzęk) była „zbyt krótka i jednostajna”; wybrana wersja 2: zamek → strzał cięciwy z trzaskiem bicza → uderzenie ramion → gasnące drganie → świst bełtu (ok. 0,5 s) |
| `impact_hard` ×3 | z nagrań | trafienia pocisku w cegłę/beton, skałę i ścianę, zaciśnięte do ok. 0,3 s |
| `impact_flesh` ×3 | z nagrań | uderzenie pocisku w ciało, mokre trafienie, tępy cios |
| `shell` ×3 | z nagrań | mosiężna łuska na drewnie, pocisk na drewnie, łuska strzelby na betonie; ścięty czubek, żeby dzwonienie było słyszalne |
| `p64_shot` ×4 | **synteza** | odrzucone: SIG P229 9 mm z 1 m (jasny i krótki wobec syntezy) |
| `sokol6_shot` ×3 | **synteza** | odrzucone: start fajerwerku z bliska |
| `whizz` ×3 | **synteza** | odrzucone: nagrane przeloty pocisków |
| `foley_gear` ×3 | z nagrań | ruchy oporządzenia z nagrania biegu, obniżone i przyciemnione („wojskowo”). Pierwsza próba z nagrań przegrała z syntezą na stronie A/B, ale syntetyczny brzęk okazał się w grze wysoki i męczący; synteza w repo też jest teraz bez metalicznych stuknięć |
| `dry_fire` | **synteza** | odrzucone: kurek M1911 z dołożonym niskim stukiem |
| `ricochet` ×2 | synteza (bez kandydata) | w archiwach nie ma czystego, pojedynczego rykoszetu |
| `reload` ×3 | z nagrań | magazynek G36C i zamek Saigi na osi czasu syntezy + jej niskie stuki |
| `reload_shell` ×3 | z nagrań | wsunięcie naboju i wyrzut łuski strzelby + niski stuk |
| `maczeta` ×2 | z nagrań | zamach długą klingą + krótki świst noża |
| `hkm9_flame_loop` | z nagrań | ryk ognia + syk palnika gazowego, pętla 2 s ze szwem przenikanym |
| `hkm9_ignite` | **synteza** | odrzucone: początek nagrania dużego zapłonu |
| `kilof_swing` ×2 | **synteza** | odrzucone: zamach długim trzonkiem, obniżony o 3 półtony |
| `reload_bolt`, `reload_launcher`, `reload_cell` ×2, `reload_rail` | synteza (bez kandydata) | brak nagrań mechanizmu naciągu kuszy i granatnika; ogniwa i działo szynowe nie mają odpowiednika |
| `stalker_shriek` ×2 | z nagrań | skrzek + ryk + pisk suchego lodu + sub, hala; ten sam autor nagrań co warkot |
| `amb_far_cry` ×2 | z nagrań | ten sam krzyk przefiltrowany, w długim pogłosie |
| `stalker_step` ×3 | z nagrań | ciężkie, mokre kroki stwora + sub-uderzenie |
| `stalker_whisper_loop` | z nagrań | niski, powolny oddech: nagrany wydech obniżony o oktawę, wdech to ten sam wydech odwrócony, pod spodem falujący niski ton; cykl 7 s. Wcześniej: nagrany ludzki szept odrzucony na rzecz syntezy, a jasny syk syntezy okazał się w grze za mało mroczny. Synteza w repo też jest teraz o oktawę niżej, z dronem |
| `step_metal` ×5, `step_dirt` ×5, `step_water` ×5 | z nagrań | pojedyncze kroki z nagranych marszów (blacha, ziemia, kałuża), jak beton z bramki A |
| `land_hard` | z nagrań | lądowanie w butach na obie stopy, obniżone, z uderzeniem w dole pasma (pierwsza wersja — nagrany upadek ciała — w grze brzmiała jak przewrócenie się po każdym podskoku) |
| `amb_forest`, `amb_rain`, `amb_rain_roof` | z nagrań | pętle stereo 16 s z najrówniejszego fragmentu nagrania (zimowy las nocą, ulewa, deszcz o daszek), szew przenikany 1,5 s |
| `amb_wind` | z nagrań | górski wiatr, ta sama technika pętli; przy pierwszym odsłuchu odrzucony, przy drugim wybrany |
| `door` ×2 | z nagrań | skrzyp metalowego zawiasu + uderzenie skrzydła, pogłos blaszanego korytarza |
| `glass_break` ×2 | z nagrań | wybite okno z odłamkami; uderzenie w szkło + rozsypanie odłamków |
| `thunder` ×3 | z nagrań | trzy nagrane uderzenia pioruna, przycięte do ok. 6 s |
| `amb_creak` ×3, `amb_gust` ×3, `amb_thud` ×2 | z nagrań | skrzypienie metalu i zablokowanych drzwi; porywy (świst i wycie w szczelinie); głębokie uderzenia w pogłosie jaskini |
| `player_hurt` ×2, `player_down` | z nagrań | okrzyki bólu z jednego zestawu nagrań; jęk + to samo uderzenie ciała co w syntezie |
| `effort` ×2 | **usunięte** | dźwięk podskoku: stęknięcie męczyło, odbicie butów też było zbędne — po odsłuchu w grze skok jest niemy, słychać dopiero lądowanie |
| `trzosek_attack` ×3, `trzosek_death` ×2 | z nagrań | duży pies obniżony o 6 półtonów z warkotem ogara („wilkołak”); śmierć: szczeknięcie przechodzące w skowyt. Pierwsza wersja (owadzi terkot) była w grze za wysoka |
| `wolek_attack` ×2, `wolek_death` ×2 | z nagrań | ryk bestii + sub-uderzenie; jęk trolla / yeti + upadek cielska |
| `slepiec_death` ×2 | z nagrań | trzepoczący, urywany wydech + syntetyczne klikanie |
| `slepiec_attack` ×2 | **synteza** | odrzucone: syntetyczne klikanie na nagranym wdechu / syku |
| `podsluchacz_scream` ×2 | z nagrań | wrzask banshee + przestrojony jęk, drżenie alarmu jak w syntezie |
| `leech_growl` ×2, `leech_shriek` ×2 | z nagrań | bulgot wodnego stwora + niska faktura; skrzek morskiej bestii |
| `zyla_roar` ×2 | z nagrań | kilka ryków naraz (smok, wielka bestia, behemot) + sub-uderzenie |
| `zyla_growl` ×2 | **synteza** | odrzucone: niski pomruk obcej bestii z nałożonym tętnem |

Głośność każdej rodziny zrównana ze ZMIERZONĄ głośnością syntezy (nominalne cele z `bake_weapons.py` synteza osiąga tylko częściowo, bo
ogranicza ją szczyt). Zostają syntetyczne także: `widmo1` (działo szynowe), `lr7` (promień), znaczniki trafień — to dźwięki bez odpowiednika w
nagraniach. F3, F4 i F5 są zamknięte: każda rodzina, dla której był kandydat, ma werdykt; lista kandydatów jest pusta.

**F5, część 2 — własne głosy wrogów (2026-10-12).** Wrogowie przestali pożyczać głos Stalkera. 11 nowych rodzin, 23 pliki
(`audio/sfx/enemies/`, builder `bake_sfx.build_enemies()`; razem 180 assetów), każda z wersją syntetyczną w repo:

| Rodzina | Kto i kiedy | Gest wersji syntetycznej |
|---|---|---|
| `trzosek_attack` ×3, `trzosek_death` ×2 | Trzosek (i Skoczek, niżej): zapowiedź ciosu, śmierć | niskie, psie warknięcie-szczeknięcie; opadający skowyt |
| `wolek_attack` ×2, `wolek_death` ×2 | Wołek: zapowiedź ciosu / szarży / rzutu, śmierć | parsknięcie i niski ryk; długi jęk + upadek cielska |
| `slepiec_attack` ×2, `slepiec_death` ×2 | Ślepiec (i zdemaskowany Mimik, wyżej): zapowiedź, śmierć; śmierć Podsłuchacza | przyspieszające klikanie + świst wdechu; wydech z gasnącym klikaniem |
| `podsluchacz_scream` ×2 | krzyk alarmu Podsłuchacza, demaskacja Mimika | dwa głosy o pół tonu od siebie, szybkie drżenie |
| `leech_growl` ×2, `leech_shriek` ×2 | Pijawka (boss): te same zdarzenia co dotąd | mokry, bulgoczący warkot; syczący skrzek |
| `zyla_growl` ×2, `zyla_roar` ×2 | Żyła (boss): te same zdarzenia co dotąd | pomruk tętniący jak serce; ryk z trzech głosów naraz |

Zwykli wrogowie odzywają się przy zboczu `winding` (zapowiedź ciosu — to informacja dla gracza, nie ozdoba) i przy śmierci; głos gra
lokalnie na każdym peerze z replikowanego stanu, bez nowych RPC. Ćma jest niema. „Ból” przy każdym trafieniu pominięty celowo: trafienie
ma już `impact_flesh`, a wataha pod ostrzałem robiłaby ścianę dźwięku. U bossów wysokości odtwarzania zbliżone do 1,0 (wcześniej 0,42–1,35,
bo jeden krzyk Stalkera udawał wszystko). Limity jednoczesnych głosów: `audio_director.gd: VOICE`. Napisy: `bake_audio.py: CAPTIONS`
+ `translations/ui.csv`. Werdykt odsłuchu: 9 z 11 rodzin z nagrań, zapowiedź ciosu Ślepca i pomruk Żyły syntetyczne (tabela wyżej).

Wzór z werdyktów (52 rodziny z nagrań, 8 odrzuconych): nagrania wygrywają tam, gdzie liczy się masa i faktura (strzelby, wybuchy,
trafienia, łuski, kroki, głos stwora, ogień), a przegrywały dla dźwięków krótkich, jasnych i „bliskich gracza” z samego nagrania (pistolet,
przelot, szelest, kurek) — synteza jest tam pełniejsza w dole pasma. Po dołożeniu pod nagranie niskich stuków syntezy mechanika broni
(przeładowania) wygrała. Szept Stalkera pokazuje granicę: rozpoznawalnie ludzkie nagranie przegrało z abstrakcyjną syntezą.

Uwagi z pomiaru:
- **Różnorodność wariantów** z nagrań jest niska w mierze audytu (`m83_shot` 0,25, `p64_shot` 0,22, `spread12_shot` 0,11 wobec 0,45–0,47
  w syntezie). Miara porównuje rozkład energii w pasmach, a kolejne strzały z jednej broni mają go niemal ten sam — to różne ujęcia, nie ta sama
  próbka. Próba zwiększenia rozrzutu obróbką (wysokość, korekcja, balans warstw) podniosła `m83_shot` tylko do 0,27, więc została porzucona.
  Rozstrzyga przycisk „seria” na stronie A/B; jeśli seria brzmi powtarzalnie, następny krok to domieszanie ujęć drugiej broni.
- **Warkot Stalkera z nagrań jest o ok. 3,5 LU głośniejszy** od syntetycznego (−14,8 wobec −18,3 LUFS): synteza to prawie sam sub-bas, który
  miara głośności (i ucho) tłumi. Wersja została wybrana w odsłuchu, więc zostaje; jeśli w grze dominuje, ściszyć w `stalker.gd`.
- `get` / `sync` z archiwów działają dla wszystkich roczników (wcześniejsze błędy zakresów były przejściowe).

**F6 (b) droga dźwięku po mapie — wdrożona, czeka na strojenie w grze.** `scripts/sound_grid.gd` (natywny `AStarGrid2D` na kaflach mapy,
własność poziomu) + `audio_director.gd: _placement()`: źródło mocno zasłonięte gra z kierunku ostatniego rogu drogi i z odległości równej
jej długości, jeśli tak wychodzi głośniej niż przez ścianę; pętle pozycyjne dojeżdżają do pozornego położenia płynnie. Zamiast zalewania
siatki z planu jest wyszukiwanie drogi na żądanie z pamięcią podręczną — prościej i bez pracy co klatkę. Testy: `tools/test_sound_grid.gd`
(w CI), `--maptest` sprawdza drogę dźwięku do każdego punktu mapy. Wagi (`ROUTE_LOSS_DB`, `WALL_LOSS_DB`) dobrane z rachunku, nie z odsłuchu;
do porównania w grze służy `--nosoundpath`.

**F6 (a) wersja bliska i daleka — wdrożona, czeka na strojenie w grze.** 8 rodzin dalekich po 2 warianty (`m83_far`, `p64_far`,
`spread12_far`, `srut8_far`, `gniew4_far`, `sokol6_far`, `widmo1_far`, `explosion_far`; razem 196 assetów). Daleka wersja powstaje
z gotowej bliskiej jedną funkcją (`bake_weapons.far_version()`: stłumiony atak, pochłonięta góra pasma, dwa echa, pogłos dużej
przestrzeni) — osobno z syntezy (do repo) i z wersji z nagrań (do `audio_licensed/`, tylko dla rodzin, których bliska wersja jest
z nagrań), więc daleka zawsze pochodzi od tej bliskiej, którą gra gra. `audio_director.gd: play_at()` przenika obie wg odległości
(`FAR_START` 300 px → `FAR_FULL` 900 px, stała moc); rodziny dalekie rozpoznaje po nazwie w manifeście, bez tabeli. Dotyczy strzałów
innych graczy i botów oraz wybuchów; własny strzał jest niepozycyjny i zostaje bliski. Dev: `--nofar`. Progi i charakter ogona
dobrane z rachunku — do oceny w grze. Inaczej niż w planie F3, dalekie wersje nie są osobnymi przepisami z nagrań z dystansu:
wyprowadzenie z bliskiej gwarantuje, że to „ten sam strzał”, i nie wymaga osobnego odsłuchu każdej broni.

**F8 — rozpoznanie (2026-10-12).** Pięć rodzin jest w banku, ale gra ich nigdzie nie odtwarza: `amb_air`, `amb_drips`,
`mine_beep_loop`, `radio_static_loop`, `stalker_appear`. Do decyzji: podpiąć (np. `stalker_appear` przy wyjściu Stalkera z ukrycia,
`mine_beep_loop` przy uzbrojonej minie) albo usunąć z bake'a. Liczby w `README.md` i `AUDIO.md` wyrównane do 196.

Stan importu: 73 z 196 plików w repo (i wszystkie wersje z nagrań) są już importowane z kompresją QOA — Godot 4.7 ustawia ją
domyślnie nowym plikom; reszta to PCM. Przy okazji wyszedł błąd: `audio_director.gd: _enable_loop()` liczył koniec pętli z rozmiaru
danych, więc pętle w QOA (`amb_rain`, `amb_rain_roof`, `hkm9_flame_loop`, `lr7_beam_loop`, pętle ambientu z nagrań) urywały się po
ok. 1/5 długości. Naprawione, pilnuje tego `tools/test_audio_loops.gd` (w CI). Pomiar QOA na całym banku (zrzut danych z Godota,
dekodowanie ffmpeg): 53,1 MB → 10,7 MB, długości co do próbki; szum kodeka 14–20 dB pod sygnałem dla strzałów i szkła (szum na szumie),
40–65 dB dla dźwięków niskich i tonalnych, ale dla stemów muzyki tylko ok. 22 dB w paśmie 2–8 kHz — to potwierdza podział z planu:
QOA dla efektów, Ogg Vorbis dla muzyki i długich pętli ambientu.

**F8 — format wydania wdrożony (2026-10-12).** Odsłuch kontrolny PCM / QOA dla dziesięciu rodzin efektów (w tym najgorsze w pomiarze:
szkło, strzały, szept): „bez różnicy” we wszystkich. Stan:

- **Efekty** (`audio/sfx/**`, 183 pliki): WAV importowany z kompresją QOA (`compress/mode=2` w `*.wav.import`; nowe pliki dostają ją
  w Godocie 4.7 domyślnie).
- **Muzyka i ambient** (`audio/music/`, `audio/amb/`, 13 plików): gra ładuje bliźniaczy plik Ogg Vorbis (jakość 6, ok. 190 kb/s),
  który `bake_audio.py` koduje z WAV-u przez ffmpeg — deterministycznie, tylko gdy WAV się zmienił (`audio/_ogg.json`). WAV zostaje
  plikiem wzorcowym (audyt, odsłuch), ale ma import „skip”, więc Godot go nie importuje i nie eksportuje. To samo dzieje się lokalnie
  dla pętli ambientu z nagrań w `audio_licensed/`. Pętla Ogg w Godocie jest ciągła co do próbki (zrzut dekodera przez szew: błąd na
  szwie taki sam jak w środku pliku), długości stemów równe 960 000 klatek.
- **Rozmiar** zaimportowanego audio: 53 MB → ok. 8 MB (efekty 4,6 MB, muzyka i ambient 3,5 MB).

Pięć rodzin, których gra dotąd nie odtwarzała, jest podpiętych (decyzja: podpiąć, nie usuwać):

| Rodzina | Gdzie gra |
|---|---|
| `stalker_appear` | chwila, gdy przebudzony Stalker wychodzi z mroku dla lokalnego gracza (z bliska albo w snopie latarki); nie częściej niż co 20 s (`stalker.gd`) |
| `mine_beep_loop` | cichy sygnał uzbrojonej miny kierunkowej, pozycyjny; wrogów nie budzi (`placed.gd`) |
| `radio_static_loop` | szum eteru z radiostacji w kryjówce, pozycyjny (`radio_set.gd`) |
| `amb_air` | tło pod dachem — „powietrze” budynku; razem z tym las z powierzchni cichnie pod dachem o 6 dB (`weather_fx.gd: _beds()`) |
| `amb_drips` | kapanie w podziemiach (`weather_fx.gd: _beds()`) |

Głośności dobrane z rachunku — do oceny w grze. F8 jest zamknięte.

**Poprawki po pierwszym odsłuchu w grze (2026-10-12).** Trzy rzeczy brzmiały źle dopiero w grze, mimo wygranej na stronie A/B:
Trzosek (za wysoki — owad zamiast drapieżnika), skok (stęknięcie przy każdym odbiciu) i lądowanie (upadek ciała po każdym
podskoku). Wniosek na przyszłość: strona A/B porównuje pojedynczy dźwięk, a nie to, jak często i w jakim kontekście gra —
dźwięki powtarzane co sekundę (skok, lądowanie, głos najliczniejszego wroga) trzeba sprawdzać w grze, zanim uzna się je za zamknięte.
Drugi odsłuch w grze: Trzosek i lądowanie zostają, a dźwięk podskoku został usunięty całkowicie (bank ma teraz 194 assety).
Trzeci: chodzenie — szelest ekwipunku z nagrań zamiast syntetycznego brzęku, a krok po metalu stracił syntetyczną warstwę
(obniżony `ricochet`), bo nagrany krok po blasze sam niesie charakter podłoża.
Czwarty: podnoszenie — `ammo_pickup` (naboje w dłoni + chwyt torby) i `weapon_pickup` (chwyt karabinu, niżej i ciężej) z nagrań
zamiast syntetycznych sygnałów; synteza `ammo_pickup` w repo straciła wysoki dzwonek. Do tego cztery nowe klucze, żeby
każdy rodzaj przedmiotu brzmiał jak to, czym jest (`level.gd: PICKUP_SOUND`; bank ma 198 assetów), wszystkie z nagrań:
`tag_pickup` (nieśmiertelnik — brzęk blaszek na łańcuszku), `scrap_pickup` (złom i skrytki — garść żelastwa),
`medkit_pickup` (apteczka — chwyt i suwak; wcześniej pożyczała dźwięk podnoszenia rannego), `item_pickup` (flary,
zaopatrzenie — miękki chwyt torby). Zaopatrzenie nie gra już dźwięku podwójnie.

**Ustalenia, które zmieniają plan:**

- **Paczka Sonniss 2026 nie zawiera strzałów, kroków ani przeładowań** (347 plików; są głosy stworów, gore, drzwi, wiatr). Broń i kroki są
  w rocznikach 2016–2019. Serwer Sonniss obsługuje żądania zakresu, więc zamiast całych archiwów (2016–2019 i 2026 to razem ok. 103 GB)
  pobieramy pojedyncze pliki: pilotaż potrzebował 52 MB. Serwer bywa kapryśny przy wielu żądaniach z rzędu (odpowiedź bez zakresu) —
  `audio_lib_fetch.py` ponawia; spisy są dla wszystkich roczników 2016–2020, 2023, 2024 i 2026 (razem ok. 230 GB archiwów).
- **Repo jest publiczne** — patrz zasada 7 i decyzja 3.
- **Stable Audio 3 działa lokalnie** na RTX 3080 10 GB: model Medium i mały model SFX, cztery pięciosekundowe próbki w kilka sekund.
  Medium daje więcej szczegółu w środku pasma, mały SFX ciemny, ciągły pomruk. Wynik to FLAC 44,1 kHz (bake przepróbkowuje do 48 kHz).
- Brzmienia nie oceniałem uchem — wybór wycinków i próbek opiera się na pomiarach (poziom, widmo, okresowość); od tego jest bramka A.
