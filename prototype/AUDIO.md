# Audio — analiza i overhaul (v2)

Dokument opisuje, co było nie tak z dźwiękiem w prototypie, co zostało przebudowane i jak to
sprawdzać. Wszystkie liczby pochodzą z `tools/audio_audit.py` (raporty: `tools/baseline/`).

## 1. Wniosek z analizy

Biblioteka wyglądała na kompletną (85 assetów, muzyka adaptacyjna, okluzja), ale **generator
dźwięku miał błędy fundamentalne**, których nie było widać bez pomiaru ani spektrogramu:

| Usterka | Skutek |
|---|---|
| `osc()` zwiększał fazę o `f` próbek na krok zamiast `f·len(tabela)/SR` | „Sinus" przy całkowitych Hz = **cisza**, pozostałe oscylatory = **aliasowany szum**. Wysokość dźwięku nie istniała: bas, kick, pady, akordy Dm–B♭–Gm–A, serce, brzęczyki UI. Centroid widma „serca" 62→44 Hz: **17,7 kHz** |
| `fm2()` podawał fazę w cyklach do `sin()` jak w radianach | Piła z DC, nie FM; „metaliczne" dzwony i krzyki brzmiały jak buczek |
| `svf()`: punkt −3 dB ~3× za nisko, +5 dB w paśmie przepustowym | Każdy filtr stroił się inaczej niż kod deklarował |
| `stereoize()` = opóźnienie Haas 9–30 ms na każdym dźwięku | Filtr grzebieniowy: **19 plików traciło >3 dB po zsumowaniu do mono** (do −10,8 dB) |
| Normalizacja każdego pliku do −0,4 dBFS po *sample peaku* | **74 z 85** plików z true-peakiem > −1 dBTP (max +1,4), brak headroomu |
| Szwy pętli (`amb_drips`, `amb_machine`, `generator`, `mine_beep`) | Skok na styku ×57…×949 890 mediany → klik co obieg |
| `tape()`, `schroeder()`, wszystkie ogony zapieczone w próbce | Ten sam „pokój" w lesie, korytarzu i jaskini; pogłos podwójny z szyną Reverb |
| Warstwy muzyki = pełne, samodzielne utwory, a runtime je *przenikał* | Podwójny bas/perkusja w trakcie przejścia, crossfade liniowy **w dB** |
| Okluzja binarna (jeden promień → jeden LP 620 Hz), szept stalkera niepozycyjny | Brak dyfrakcji; „stalker zawsze słyszysz, nigdy nie widzisz" bez kierunku |
| `m83_shot` ×4 warianty, SPREAD-12 = M-83 pitchowany ×0,62 | Powtarzalność przy 10 strz./s; strzelba nie brzmi jak strzelba |

## 2. Wynik (pomiar przed → po)

| Metryka | Przed | Po |
|---|---|---|
| Assety z uwagami audytu | 76 / 85 | **0 / 118** |
| True peak > −1 dBTP | 74 | **0** (max −1,5 dBTP) |
| Pliki tracące >3 dB w mono | 19 (do −10,8 dB) | **0** (najgorszy −2,6 dB) |
| Szwy pętli poza normą | 6 | **0** (szew w typowym zakresie skoków, `seam_pct` ≤ 95) |
| Warianty w rodzinach | 52 | **84** (kroki ×5, M-83 ×6, P-64 ×4, strzelba ×3) |
| Średnia różnorodność wariantów (odl. widmowa) | 0,41 | **0,74**; rodziny „prawie identyczne" 4 → 0 |
| Centroid „serca" / „revive" / „ui_confirm" | 17,7 kHz / 12,1 kHz / 11,0 kHz | **54 Hz / 277 Hz / 1,6 kHz** — wreszcie mają ton |
| Pliki stereo | 35 (z Haas) | 16 (tylko to, co ma szerokość: ambient, muzyka, wybuchy, whizz) |
| Czas pełnego bake'u | — | 41 s, **bit w bit deterministyczny** |

Testy rdzenia (`tools/test_audio_dsp.py`) dowodzą m.in.: dokładność wysokości ≤ 0,5 Hz dla 4 kształtów
fali, filtry −3 dB w fc (±1,2 dB), aliasowanie piły 3 kHz poniżej −35 dB, szum filtrowany kołowo
ma szew 1,5× mediany, RT60 syntetycznych IR w granicach 0,55–1,6× zadanego, LUFS zgodny z ffmpeg `ebur128` (±0,3 LU).

## 3. Co zostało zrobione

### 3.1 Rdzeń DSP (`tools/audio_dsp.py`, numpy + scipy)
Oscylatory PolyBLEP, filtry RBJ (+ Butterworth, sweep blokowy), FM i **synteza modalna** (metal, szkło,
dzwon), saturacja z 4× oversamplingiem, kompresor/limiter/transient shaper, **pogłos splotowy z
syntetycznych IR** (`make_ir`: wczesne odbicia + ogon z zanikiem zależnym od pasma), decorrelator
allpass i niezależne realizacje L/R zamiast Haas, loudness BS.1770, true-peak, dither TPDF.
**Pętle kołowe** (`circ_filter`, `fold_loop`): sygnał okresowy → 3× kafel → środek; szew idealny z konstrukcji,
bez crossfade'u i bez dziury w energii.

> Zmiana zależności: bake wymaga teraz `numpy` + `scipy` (`pip install -r tools/requirements.txt`).
> Poprzedni komentarz „stdlib, brak numpy w środowisku" przestał być prawdą; `matplotlib` jest tylko do podglądu.
> Gra (Godot) nie potrzebuje Pythona — pliki WAV są w repozytorium.

### 3.2 Assety (118, `tools/bake_*.py`)
* **Broń** — strzał warstwowy: crack (1,5 ms) / blast (swept LP) / body (sinus z opadającą wysokością) /
  punch / mechanika modalna / krótki ogon źródła. Własna **strzelba** (5 cracków śrutu + sub), przeładowanie
  w 5 zdarzeniach, **łuski** (mosiądz/plastik z odbiciami), **foley ekwipunku**, **szum w uszach**.
* **Stalker i głosy** — źródło głosowe (jitter/shimmer) → formanty: growl z „vocal fry" i AM-szorstkością,
  krzyk z konturem wysokości, szept z płynnie wędrującymi formantami (pętla okresowa, 7 sylab), odległy zew.
  Głos gracza: wysiłek, ból (2 różne samogłoski/kontury), upadek.
* **Kroki** — pięta + palce, 5 wariantów × 4 powierzchnie (beton/metal modalny/ziemia z chrzęstem/woda z bąblami).
* **Ambient** — stereo z niezależnych realizacji, okresowe; nowe emitery jednorazowe (podmuch, skrzyp, huk, zew).
* **Muzyka** — 4 **stemy addytywne** (96 BPM = 30 000 próbek/beat, 8 taktów, d-moll, Dm–B♭–Gm–A ×2):
  pad+sub+szklane akcenty / ostinato basowe + melodia / perkusja z gated snare + bas 16-tkowy / arpeggio, toomy, crash, riser.
  Plus dwa stingery. Wszystkie stemy mają identyczną siatkę.
* **Poziomy** — policy w `bake_common.finalize()`: one-shoty impulsowe po *peaku*, trwałe po *LUFS*, zawsze
  true-peak ≤ −1,5 dBTP. Poziomy są **w parytecie z dotychczasowym miksem** (wartości `vol_db` w skryptach były dobrane
  do starych, głośnych assetów — np. szept grany z −34…−20 dB), więc call-site'y nie wymagały zmian.

### 3.3 Runtime (`scripts/audio_director.gd`, `default_bus_layout.tres`)
* **Okluzja progowa 0–3**: promień środkowy + dwa boczne (dyfrakcja) → szyny `OccLight/OccHeavy/OccBlocked`
  (LP 3,4 k / 1,3 k / 480 Hz, 12–18 dB/okt.). Pętle pozycyjne przeliczane co 0,2 s z histerezą 0,35 s.
* **Szept stalkera pozycyjny** (`start_loop_at`): panorama + okluzja, głośność nadal z `stalker.gd`.
* **Pogłos środowiskowy**: 12 promieni wokół słuchawki → zamknięcie/odległość → wygładzone `wet/room_size/damping`
  efektu Reverb na szynie SFX. Assety niosą tylko krótki ogon źródła.
* **Muzyka stemowa**: wszystkie stemy grają równolegle (start pod `AudioServer.lock()`), Uwaga steruje głośnością.
  Wejście kwantyzowane do beatu (1 / ½ / ¼), zejście z hold 2,5–8 s, crossfade liniowy w amplitudzie, ducking na stingery.
* **Sidechain** w bus layout: Music ← SFX (−20 dB, 2,2:1), Ambience ← Weapons.
* **Ogłuszenie**: LP na Music/Ambience/SFX + szum w uszach po wybuchu blisko słuchawki i mocnym trafieniu.
* **Voice management**: priorytety, limity na rodzinę, minimalny odstęp, kradzież najsłabszego, brak powtórzeń tego
  samego wariantu, jitter głośności, pomijanie źródeł poza zasięgiem.
* **Emitery ambientu** (gęstsze przy wysokiej Uwadze), **łuski**, foley biegu, sygnał **`caption`** + `CAPTIONS` w manifeście
  (napisy dla niesłyszących, GDD §14 — jeszcze bez UI).
* `project.godot`: `audio/driver/mix_rate = 48000` (assety są 48 kHz; wcześniej resampling do 44,1 kHz).

## 4. Narzędzia

```bash
cd prototype
pip install -r tools/requirements.txt
python3 tools/test_audio_dsp.py                  # testy rdzenia DSP
python3 tools/bake_audio.py [--only weapons,music] [--list]
python3 tools/audio_audit.py                     # LUFS/TP/DC/szwy/widmo/mono/różnorodność wariantów
python3 tools/audio_audit.py --compare tools/baseline/audit_before.json tools/baseline/audit_after.json
python3 tools/audio_view.py out.png m83_shot_1 stalker_growl_1 mus_combat   # przebieg + spektrogram
godot --headless --path . --import               # po bake'u — inaczej grają stare sample'e
```

## 5. Ograniczenia i uczciwa ocena

* **To nie jest jeszcze „AAA" w sensie brzmienia.** AAA = nagrany materiał (foley, głosy, broń), miksowany w
  middleware (Wwise/FMOD) przez sound designera na słuchawkach. Synteza proceduralna — nawet poprawna — tego nie zastąpi.
  Ten overhaul usuwa defekty techniczne, wprowadza architekturę miksu klasy AAA i przygotowuje pipeline, w którym
  nagrane pliki wchodzą **1:1 w miejsce syntetycznych** (te same klucze, `finalize()` normalizuje poziomy).
* **Brzmienia nie oceniałem uchem.** Weryfikacja: pomiary (LUFS/TP/DC/widmo), testy DSP i spektrogramy
  (`audio_view.py`). Barwa, „waga" strzałów, wiarygodność głosów stalkera i kompozycja muzyki wymagają odsłuchu na słuchawkach.
  Pierwsze, co warto poprawić po odsłuchu: balans crack/body w `gun()`, jasność szeptu, głośność stemów (`finalize(lufs=…)`).
* **Zmian w silniku nie uruchomiłem** (Godot 4.7 nie był dostępny w środowisku). Sprawdzone: parser GDScript
  (`gdparse`) dla wszystkich skryptów, statyczna zgodność wywołań `Audio.*` i kluczy z manifestem, struktura bus layoutu
  (własny walidator), nazwy właściwości efektów względem typów API 4.7.2. **Do zrobienia przy pierwszym uruchomieniu**:
  `godot --headless --path . --import` (wygeneruje `.import` dla nowych WAV-ów), sprawdzić log `[AUDIO] manifest OK: 118`,
  posłuchać okluzji za ścianą, przejść Uwagę 0→100→0 i sprawdzić wejścia stemów, wybuch blisko (ogłuszenie + szum w uszach).
  Najbardziej ryzykowne miejsce: `AudioServer.lock()` wokół startu stemów (idiom znany z praktyki, nie testowany tutaj).
* Rozmiar WAV: 38 MB (było 24). Przed wydaniem warto przejść na Vorbis/QOA dla muzyki i ambientu (kod nie wymaga zmian
  poza `loop` na `AudioStreamOggVorbis`).
* Dalsze kroki: UI napisów (sygnał `caption`), suwaki głośności (Master/Music/SFX/Voice) i mono-audio w opcjach (GDD §14),
  profil ogłuszenia/szumu per trudność, miksowanie „na słuchawkach" co sprint (GDD ryzyko „Groza nie działa w 2D"),
  obsługa hot-reload banku w edytorze.
