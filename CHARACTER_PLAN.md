# Realistyczne postacie i naturalny ruch — projekt do akceptacji

**Stan (2026-10-15):** E0–E2 zrobione i wydane w 1.7.220: sześć postaci z MPFB2 domyślnie w grze (stare: `--charset=tripo`). Po uwagach użytkownika („zbyt cywilne”, „za mało detali”, „śpiwór za mały / za niskiej jakości”): stroje z paczek CC-BY (kamizelka, hełmy, maska, mundur ratownika, kombinezony), kamuflaż i przebarwienia skryptem, wypiekane AO i brud, a cały ekwipunek z lokalnej generacji FLUX.1 [schnell] + TRELLIS 2 (`art_src/gear/`) w rzeczywistych wymiarach (generator sprawdza ±10%). Mixar odpadł (0 kredytów). Zostają: E3 (mocap), E4 (palce na broni), broń biała po playteście.

Cel: postacie o naturalnej budowie (jak broń, meble i gabloty po 1.7.217–1.7.219), ruch nóg i tułowia z prawdziwego nagrania ruchu (mocap),
dłonie zaciśnięte na broni palcami. Broń biała dostaje podstawy pod emocjonującą walkę (osobny etap, po playteście).

## 1. Stan dziś

Sześć modeli z Tripo (`art/char3d/<płeć>_<strój>.glb`, `tools/prep_char3d.py`): ok. 12 tys. trójkątów, tekstury PBR 2K, szkielet 23 kości
(nazwy Mixamo, poza A, bez palców, kości skrętu i twarzy). Pomiar (H = wzrost modelu, głowa z kaskiem / kapturem):

| | Nasze modele | Dorosły człowiek |
|---|---|---|
| Głowa | 0,21–0,24 H (1/4,1–1/4,8) | ok. 0,13 H (1/7,5) |
| Broda | ok. 0,75 H | 0,87 H |
| Dłoń | 0,12–0,14 H | ok. 0,105 H |
| Ramię (bark–nadgarstek) | 0,24–0,31 H | ok. 0,33 H |
| Noga (biodro–kostka) | 0,41–0,51 H | 0,47–0,50 H |

Modele różnią się też między sobą (hazmat i medyk mają większe głowy niż scav). Przy broni i meblach w naturalnej skali postać wygląda jak
figurka: karabin 1,1 m w wielkiej dłoni na krótkiej ręce czyta się jak zabawka. Klipy ruchu (Quaternius UAL, CC0) są ręcznie animowane i
stylizowane.

## 2. Ciało — skąd

| | MPFB2 (MakeHuman dla Blendera) — **rekomendacja** | Character Creator 5 (Reallusion) |
|---|---|---|
| Koszt | darmowy (dodatek GPL, wynik i paczki zasobów CC0) | płatny |
| Licencja w publicznym repo | CC0 — bez zastrzeżeń | ubrania i dodatki mają osobne licencje treści; trzeba sprawdzić każdą |
| Praca | skrypt w `tools/` uruchamiany headless (jak `gun_proc.py`), powtarzalny — zgodnie z zasadą repo „edytuj generatory” | ręcznie w programie (GUI), eksport FBX |
| Ubrania | proste (CC0: koszule, spodnie, buty i kozaki, hełmy, maski, torby); braki dorabiamy | bogaty wybór, gotowe stroje |
| Szkielet | kilka wariantów, w tym z palcami (do sprawdzenia po instalacji, który pasuje) | pełny z palcami i skrętami |

MPFB2 (2.0.18, Blender 4.2+, mamy 5.2.2) da się zrobić w całości bez Twojej pracy w programach i przed playtestem. CC5 zostaje opcją
na później, jeśli stroje z MPFB okażą się za ubogie.

## 3. Stroje

Trzy stroje × dwie płcie, jak dziś (`Look.outfit_id`: scav, hazmat, medic). Kolory i sylwetki zostają, żeby gracze rozpoznawali się
w kooperacji tak jak dziś.

| Strój | Z paczek CC0 | Do dorobienia |
|---|---|---|
| Scav | koszula, bojówki (pants01), kozaki (shoes01), czapka (hats01) | plecak ze śpiworem, kurtka polowa, pas z ładownicami |
| Hazmat | kozaki, rękawice (gloves01), maska (masks01, jeśli jest przeciwgazowa) | kombinezon z kapturem — z kopii siatki ciała (powiększona, z fałdami, guma), butla na plecach |
| Medic | spodnie, kozaki, hełm (hats02) | kamizelka z czerwonym krzyżem, torba medyczna |

Dodatki sztywne (plecak, butla, maska, ładownice) przypinamy do kości (`BoneAttachment3D` albo waga 100% w Blenderze). Kształty bierzemy
z paczek CC0 (equipment01) albo modelujemy skryptem. Lokalny TRELLIS 2 (obraz → 3D) też wchodzi w grę, ale tylko z gotowych obrazów, bo
nie mamy lokalnie modelu tekst → obraz. Zużycie (brud, przetarcia) wypiekamy skryptem w teksturach. Budżet: do 20 tys. trójkątów na postać,
jeden lub dwa materiały, tekstury 2K.

## 4. Szkielet i chwyt

- Nazwy kości zostają jak dziś (`mixamorig_*`), więc `char3d.gd`, `char_clips.gd`, `prep_anim3d.py` i Mimik (`enemy3d.gd`, model
  `male_scav`) działają bez przepisywania. Dochodzą kości palców (3 na palec) i skrętu przedramienia.
- Palce: poza dłoni na każdą broń, policzona z punktów `grip` / `hold` w `gun_<klucz>.json`. Prawa dłoń obejmuje chwyt, palec wskazujący
  leży na spuście, lewa obejmuje łoże. Poza zmienia się przy strzale (spust), przeładowaniu i rzucie.
- Chwyt i wylot pocisku: `aim_points` z pozy nominalnej (1.7.215) zostaje. Po zmianie modeli przeliczamy `_stance_pts` i pilnujemy testów
  `test_aim_points.gd` (błąd ≤ 1 px) i `test_proportions.gd`.

## 5. Ruch — mocap

Nogi i tułów dostają nagrania prawdziwego ruchu; ręce z bronią dalej prowadzi IK (tak jest dziś i tak robią to gry z bronią palną).

| Źródło | Licencja | Co bierzemy | Pobranie |
|---|---|---|---|
| Rokoko — darmowe paczki (chód i bieg, walka i broń, codzienne idle) | „w każdej grze, także komercyjnie”; o redystrybucji surowych plików licencja milczy | chód, bieg, idle | formularz z danymi osobowymi — **pobierasz Ty** |
| CMU Motion Capture Database | wolno włączać do produktów, także płatnych; nie wolno sprzedawać samych danych; podziękowanie w napisach | skradanie, przykucnięcie, skok, lądowanie, upadek | bezpośrednio z mocap.cs.cmu.edu |
| Quaternius UAL (dziś) | CC0 | zostaje tam, gdzie mocap nie ma odpowiednika (reanimacja, wstawanie) | jest w repo |

Surowe pliki trzymamy tylko lokalnie (`art_src/animations/mocap_local/`, w `.gitignore` — jak `audio_licensed/`). Do repo idą tylko klipy
przeniesione na nasz szkielet (`art/char3d/anim/*.glb`) i `SOURCE.md` z pochodzeniem każdego klipu. Klipy przenosi istniejący
`prep_anim3d.py` (obsługuje szkielety Mixamo, UE i humanoid). Każdy klip oceniamy na stykówce i filmie przed włączeniem, tak jak klipy UAL.

Klipy do wymiany: `idle`, `run`, `walk`, `crouch`, `crouch_walk`, skok / lądowanie (dziś z kodu, nowy klip tylko jeśli czyta się lepiej),
`down`. Reakcje na trafienie zostają z kodu (w tej skali klipy były niewidoczne — sprawdzone w 1.7.209).

## 6. Broń biała — po playteście (osobny projekt)

Narzędzie: **Cascadeur** (klatki kluczowe z fizyką i AI; walka w Shadow Fight 4). Ciosy układamy w płaszczyźnie widoku z boku — klipy
CC0 obracały całe ciało plecami do kamery (sprawdzone i odrzucone 1.7.215). W grze: fazy zamach / uderzenie / powrót z przerwaniem w
powrocie, zatrzymanie gry przy trafieniu (50–100 ms), strefa ciosu włączana z klatek klipu, ślad ostrza, częściowy ragdoll wroga
(`PhysicalBoneSimulator3D`). Konto i instalację Cascadeur robisz Ty; klipy zapisujemy w FBX i przenosimy `prep_anim3d.py`.

## 7. Etapy

| Etap | Zakres | Szacunek |
|---|---|---|
| E0 | Pobrania: MPFB2 (43,8 MB, extensions.blender.org) i paczki CC0 (makehuman_system_assets, skins01–02, shirts01, pants01, shoes01, hats01–02, gloves01, masks01, equipment01); CMU (wybrane klipy); Rokoko (Ty) | pół godziny |
| E1 | **Próbka: jeden model (male_scav)** — generator `tools/char_mpfb.py`, szkielet, strój, w grze obok obecnego; zrzuty w kamerze gry, w kryjówce i przy gablocie → **Twoja akceptacja wyglądu** | 1 dzień |
| E2 | Pozostałe pięć modeli, ujednolicone proporcje (test) | 1–2 dni |
| E3 | Klipy mocap: przeniesienie, ocena, podmiana | 1–2 dni |
| E4 | Palce i chwyt każdej broni, kalibracja `aim_points`, testy, zrzuty, `CHAR3D_SPIKE.md` / `README.md` / `GDD.md` / `CHANGELOG.md`, PR | 1 dzień |

Razem ok. 5 dni pracy. Do akceptacji E1 obecne modele zostają domyślne; nowe można włączyć flagą `--charset=mpfb` (do porównań i
playtestu A/B). Jeśli playtest przyjdzie przed E4, gra idzie z tym, co jest gotowe i zaakceptowane.

`test_proportions.gd` dostaje sprawdzenie anatomii każdego modelu: głowa 1/7–1/8 H, broda ≥ 0,85 H, noga ≥ 0,45 H, rozstaw barków
0,20–0,25 H, dłoń ≤ 0,12 H.

## 8. Ryzyka

- **Czytelność w widoku gry:** postać ma ok. 145 px, realistyczna głowa to ok. 19 px (dziś ok. 32 px). Gracze w kooperacji rozpoznają się
  dziś po głowie i stroju — mocniejsze kolory stroju i sylwetka dodatków (plecak, butla, hełm) muszą to przejąć. Sprawdzamy na zrzutach E1.
- **Doliny niesamowitości:** realistyczne twarze z bliska (kryjówka, oględziny broni). Maska, hełm, kaptur i oświetlenie gry to łagodzą; twarz
  bez mimiki.
- **Uboższe stroje niż Tripo** na starcie: detal Tripo (kieszenie, pasy) trzeba odtworzyć dodatkami i teksturami. Jeśli E1 wypadnie za
  ubogo → CC5 albo hybryda (ciało MPFB, stroje dopasowane z siatek Tripo, czego dziś nie zakładam).
- **Wydajność:** więcej kości (palce) i dodatki; budżet 20 tys. trójkątów, pomiar `tools/bench_char3d.gd` przed i po.
- **Kalibracja chwytu i wylotu** liczy się od nowa — testy w CI to pilnują.

## 9. Do akceptacji

1. Ciało z MPFB2 teraz (CC5 jako opcja po playteście)?
2. Zgoda na pobranie MPFB2 i paczek CC0 (E0) oraz wybranych klipów CMU.
3. Paczki Rokoko (chód i bieg, idle, walka i broń) — pobierzesz je i wrzucisz do `art_src/animations/mocap_local/`?
4. Kolejność: E1 (próbka do akceptacji), potem E2–E4 przed playtestem, broń biała po playteście?
