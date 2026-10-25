# Trailer Dead Air '87 — pipeline

Film z gry nagrywamy samym silnikiem (Godot Movie Maker), składamy i kodujemy FFmpegiem. Podejście z `motion_director_prompt.md`
(audio najpierw, brief, storyboard, krytyka, pomiar jakości) w wersji pod Godota; nie ma tu Three.js, GSAP ani Remotiona, bo obraz
robi sama gra.

Pliki: `capture.sh` (nagranie), `encode.sh` (MP4 + głośność), `qa.sh` (pomiary i arkusz kontaktowy), `brief.md` (szablon).
Katalogi `raw/` zawierają surowe AVI, a `out/` zakodowane MP4 i arkusze kontaktowe. Dołączone filmy są materiałami referencyjnymi; AVI i MP4 przechowujemy przez Git LFS.

## Nagranie

```bash
trailer/capture.sh NAZWA KLATKI [1920x1080] [60] [-- flagi gry...]
trailer/capture.sh korytarz 600 1920x1080 60 -- --host --mission=z1_m2 --shotrun
```

- `KLATKI` = sekundy × fps. Nagranie idzie wolniej niż czas rzeczywisty (test: 5 s klipu w 44 s, z czego większość to start gry).
- Skrypt sam ustawia rozmiar okna (tymczasowy `prototype/override.cfg`, usuwany po nagraniu), bo `project.godot` wymusza 1280×720.
- Klatki są stałe (`--fixed-fps`), więc nic się nie gubi, ale gra liczy czas symulacji zgodnie z klatkami, nie z zegarem.
- Dźwięk z gry wpada do AVI (PCM 48 kHz). Nagranie wymaga okna i GPU (nie `--headless`).
- Co robi bohater w kadrze, ustawiają flagi gry (`--shotrun`, `--shotat=KOLUMNA`, `--mission=ID`, `--shotweather=storm` itd., lista w
  `prototype/README.md`). Do ustawionych scen (boss, wróg, broń w ręku) są flagi `--shotboss`, `--shotmon`, `--shotgunid=N`.
  Dłuższe, wyreżyserowane ujęcia wymagają osobnego skryptu sceny — to jest następny krok, jeśli trailer ma mieć kamerę poza gameplayem.

## Kodowanie i kontrola

```bash
trailer/encode.sh trailer/raw/korytarz.avi trailer/out/korytarz.mp4          # dźwięk z gry
MUSIC=muzyka.wav trailer/encode.sh trailer/raw/korytarz.avi trailer/out/k.mp4 # muzyka + gra pod spodem (-18 dB)
trailer/qa.sh trailer/out/korytarz.mp4 10                                     # 10 = oczekiwana długość w s
```

`qa.sh` sprawdza: wymiary/fps/długość, głośność (cel ok. −14 LUFS, true peak ≤ −1 dBTP), odcinki nieruchome >0,5 s i robi arkusz
kontaktowy `*_sheet.png`. Jeśli wynik LUFS jest niższy od celu, a peak ≈ −1, to ogranicza go true peak (cichy, rzadki dźwięk z
nielicznymi szczytami) — pomaga muzyka pod spodem albo kompresja, nie głośniejsze kodowanie.

## Składanie

Cięcie i sklejanie zwykłym FFmpegiem, na przykład:

```bash
# cięcie fragmentu bez ponownego kodowania obrazu: -ss/-to przed -i dla szybkości, -c copy tylko na klatkach kluczowych
ffmpeg -ss 2 -to 6 -i trailer/raw/a.avi -c:v libx264 -crf 14 trailer/out/a_cut.mp4
# sklejka (pliki o tych samych parametrach) z listy
printf "file 'a_cut.mp4'\nfile 'b_cut.mp4'\n" > trailer/out/list.txt
ffmpeg -f concat -safe 0 -i trailer/out/list.txt -c copy trailer/out/trailer_raw.mp4
# plansza z tekstem (czcionka z Windows, wszystko jako funkcja czasu)
ffmpeg -i in.mp4 -vf "drawtext=fontfile='C\:/Windows/Fonts/impact.ttf':text='DEAD AIR 87':fontsize=96:fontcolor=white:x=(w-tw)/2:y=(h-th)/2:enable='between(t,0,2)'" out.mp4
```

Gdy napisów i przejść będzie dużo, wtedy dopiero warto dołożyć Remotion (tylko warstwa tytułów/logo/napisów na nagraniu z gry).

## Kolejność pracy (skrót z promptu)

1. `brief.md`: długość, format, widz, ostatnia sekunda, fakty. Fakty o grze tylko z `GDD.md` i `CHANGELOG.md` — nic wymyślonego.
2. Muzyka i timing najpierw (bity, moment uderzenia, miejsca na ciszę); cięcia na bitach.
3. Storyboard w tabeli: czas | obraz | cel | dźwięk | wyjście do następnej sceny. Musi się czytać bez dźwięku.
4. Nagranie klipów (`capture.sh`), przegląd arkuszem kontaktowym, wybór ujęć.
5. Montaż, `encode.sh`, `qa.sh`; krytyka: ktoś (lub świeży subagent) ogląda tylko arkusz 2 fps bez dźwięku i opowiada fabułę.
6. Poprawka największego problemu, ponowny pomiar, wpis do `ledger.md`.

## Dla gry horrorowej: pułapki

- Obraz jest ciemny (noc, latarka). Przed montażem sprawdź jasność klatek; w razie potrzeby krzywa w FFmpegu (`eq=gamma=1.2` / `curves`),
  ale najpierw spróbuj flag pogody i oświetlenia w grze.
- Interfejs (HUD) jest w kadrze. Flaga `--nohud` (PR ssiwm/gameon#322; do czasu scalenia tylko na gałęzi `feat/nohud-flag`) ukrywa HUD,
  celownik i plakietki graczy: dopisz ją po `--` w `capture.sh`.
- Teksty w kadrze są domyślnie po angielsku; `--lang=pl` (dev, bez zapisu) daje wersję polską.
- Czułość na spoilery i dźwięk: nagranie zawiera dźwięk z gry z lokalnych `audio_licensed/` (repo publiczne, nagrania tylko lokalnie) —
  przed publikacją sprawdź licencje użytych nagrań.
