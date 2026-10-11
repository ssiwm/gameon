# Plan: refaktor dźwięku — źródła hybrydowe i propagacja po mapie

Status: **plan z 2026-10-12; F0–F2 zrobione, bramka A przeszła (wszystkie trzy rodziny: wersja z nagrań) — stan w §7.** Oparty na przeglądzie kodu (`tools/bake_*.py`, `scripts/audio_director.gd`,
`default_bus_layout.tres`, `AUDIO.md`), nie na próbnej implementacji — rozmiary faz są szacunkowe. Kontynuacja `prototype/AUDIO.md`
(overhaul v2), który sam stwierdza w §5: „to nie jest jeszcze AAA w sensie brzmienia” i „brzmienia nie oceniałem uchem”.

Cel: dźwięk, który brzmi jak nagranie, a nie jak syntezator, i z którego da się odczytać, **skąd** coś nadchodzi — bez wymiany
runtime'u i bez zmian w sieci.

## 1. Stan obecny (z kodu)

- **Assety:** 157 plików WAV (48 kHz / 16 bit, 139 mono, 18 stereo, 330 s, 46 MB) w `prototype/audio/`, commitowane zwykłym gitem (nie LFS).
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
   | Nagrania z bibliotek royalty-free (archiwum Sonniss GDC; pojedyncze pliki pobiera `tools/audio_lib_fetch.py`) | strzały, eksplozje, trafienia, kroki, szkło, drzwi, przeładowania | `art_src/audio_lib/` albo katalog z `DA87_AUDIO_LIB` — poza repo (`.gitignore`), jak `art_src/world_pbr_cc0/` |
   | Pliki wygenerowane lokalnie (Stable Audio 3 Medium w ComfyUI) | głosy Stalkera i wrogów, ambienty, tekstury bez odpowiednika w bibliotekach | `art_src/audio_gen/` — w repo (LFS), z opisem i ziarnem |
   | Synteza (obecna) | UI, radio, pisk w uszach, sub-bas i ogony pod nagraniami, muzyka | kod w `tools/` |

4. **Determinizm względem źródeł.** `tools/audio_sources.json` (w repo) trzyma dla każdego źródła: plik, paczkę, licencję, SHA-256 i wycinek.
   Ten sam zestaw źródeł = ten sam bajt wyniku. Brak źródła na dysku: asset jest pomijany z ostrzeżeniem i zostaje poprzedni WAV
   (CI nie piecze dźwięku, więc go to nie dotyczy); `--strict` zamienia ostrzeżenie w błąd.
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
3. **Assety z nagrań a publiczne repo** — decyzja 2026-10-12: **repo ma być prywatne.** Dopóki jest publiczne, WAV-y z nagrań nie są
   wypychane (zostają na lokalnej gałęzi). Tło decyzji: repo `ssiwm/gameon` jest publiczne,
   a licencja Sonniss 2.0 zabrania udostępniania dźwięków innym „jako efektów dźwiękowych”, także przerobionych. Zmiksowany WAV w publicznym
   repo jest plikiem, który każdy może pobrać. Licencja nie mówi wprost o repozytoriach kodu, więc to ryzyko, a nie pewne naruszenie.
   Możliwości: (a) repo prywatne; (b) assety z nagrań w osobnym, prywatnym repo albo tylko w buildach, a publiczne repo zostaje z syntezą
   (bake już to obsługuje: bez źródeł zostawia WAV-y z repo); (c) pisemna zgoda Sonniss. Do decyzji nagrania żyją tylko jako wersje alternatywne.
4. **Rejestracja w Stability AI** przed komercyjnym użyciem plików wygenerowanych (wymóg licencji; robi to właściciel projektu).
5. **Głosy wrogów w F5:** osobne dla każdego gatunku (plan zakłada tak) czy na początek tylko odróżnienie Stalkera od reszty.

## 7. Stan po F0–F2 (2026-10-12)

**F0 — zrobione.** `tools/baseline/audit_refactor_before.json` (157 plików), `tools/audio_ab.py` (strona A/B „na ślepo”, WAV-y zaszyte w jednym
pliku HTML; tryby `--alts` i `--ref`), licencje przeczytane u źródła i zapisane w `tools/audio_sources.json` → `audio/CREDITS.md`.

**F1 — zrobione.** `audio_dsp.py`: `read_audio`, `resample`, `cut`, `onset`, `from_onset`, `repitch`. `bake_common.py`: `src()` ze sprawdzaniem
SHA-256, `hybrid()` (asset gry ze źródeł; brak źródła = pominięcie), `alt()` (wersja alternatywna do odsłuchu), `--strict`, `--alts`.
`tools/audio_lib_fetch.py`: spis i pobieranie pojedynczych plików z archiwów Sonniss. `comfy_gen.py audio`: Stable Audio 3.
Kryterium spełnione: pełny bake bez źródeł i ze źródłami nie zmienia żadnego pliku w `audio/`; testy DSP + 16 nowych testów źródeł przechodzą.

**F2 — zrobione, wybrane wersje z nagrań (bramka A).** `tools/bake_hybrid.py` → `build/audio_alt/` → `build/audio_ab.html`:

| Rodzina | Wersje | Źródła |
|---|---|---|
| `m83_shot` ×6 | obecna / z nagrań | AKM z 1 m (trzask) + AK-47 w otwartym terenie (korpus, ogon) + syntetyczny sub |
| `step_concrete` ×5 | obecna / z nagrań | pięć kroków z nagranego marszu w butach po betonie |
| `stalker_growl` ×2 | obecna / z nagrań / wygenerowana | „Monster Growls 4” (dwa najniższe warknięcia) albo Stable Audio 3 Medium; obie obniżone, z oktawą w dół i halą |

Pomiar (nie odsłuch): strzał z nagrań ma środek ciężkości widma ok. 1,4 kHz zamiast 250 Hz (obecny to głównie sub-bas), ogon do −40 dB
ok. 380 ms zamiast 255 ms, głośność zrównana z obecnym do 0,5 LU. Kroki z nagrań są ciemniejsze powyżej 4 kHz niż syntetyczne. Alternatywy
pieką się deterministycznie (dwa przebiegi = te same sumy).

**Ustalenia, które zmieniają plan:**

- **Paczka Sonniss 2026 nie zawiera strzałów, kroków ani przeładowań** (347 plików; są głosy stworów, gore, drzwi, wiatr). Broń i kroki są
  w rocznikach 2016–2019. Serwer Sonniss obsługuje żądania zakresu, więc zamiast całych archiwów (2016–2019 i 2026 to razem ok. 103 GB)
  pobieramy pojedyncze pliki: pilotaż potrzebował 52 MB. Części roczników 2020, 2023 i 2024 nie obsługują zakresów — z nich trzeba by
  pobrać całe archiwa.
- **Repo jest publiczne** — patrz decyzja 3.
- **Stable Audio 3 działa lokalnie** na RTX 3080 10 GB: model Medium i mały model SFX, cztery pięciosekundowe próbki w kilka sekund.
  Medium daje więcej szczegółu w środku pasma, mały SFX ciemny, ciągły pomruk. Wynik to FLAC 44,1 kHz (bake przepróbkowuje do 48 kHz).
- Brzmienia nie oceniałem uchem — wybór wycinków i próbek opiera się na pomiarach (poziom, widmo, okresowość); od tego jest bramka A.
