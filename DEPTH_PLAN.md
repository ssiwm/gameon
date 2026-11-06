# Plan: światło w głębi i wnęki w ścianach wnętrz

Status: **plan z 2026-11-06, nic nie wdrożone.** Etap po analizie głębi świata
(`C:\deadair87\reports\world-depth-recommendations-2026-11-04.md`, punkty 1 i 3 tego raportu robione razem).
Stan odniesienia: `main` 1.7.506 (b7c11e3).

## Werdykt

Wnętrza (hala stacji i tunel drezyny na 1.2, podziemia 1.1, cała 1.3, B1, kryjówka) mają za płaszczyzną gry jedną płaską ścianę
2,4 m w głąb (`Level3D.DEPTH_BACK`, płyty 0,3 m z `build_level` → `walls`). Nic jej nie oświetla poza światłami przy graczach,
więc na zrzutach (`C:\deadair87\shots_cave\cave_z1_m2_0.png`, `cave_z1_m1_1.png`) tło wnętrza jest jednolicie czarne:
oko nie ma czym odczytać odległości. Sama głębsza geometria nic nie da, bo w ciemności jej nie widać. Potrzebne jest
**światło za płaszczyzną gry, które nie zmienia ciemności przy postaciach** (GDD §8.3).

Zapas jest: release 1.7.505 na 1.2 (4K, HIGH, RTX 3080) to 60 kl./s przy GPU 8,8 ms z 16,7 ms (pomiar 2026-11-06).

## Zasady (obowiązują każdą wnękę)

1. **Światło wnęki oświetla tylko wnękę.** Bryła wnęki leży na warstwie świata i nowej warstwie `LAYER_NICHE` (128).
   Światło wnęki ma `light_cull_mask = LAYER_NICHE`, a jego zasięg kończy się co najmniej 1 m za tylną ścianą
   (z ≤ −DEPTH_BACK − 1). Ten sam wzór działa już w lesie: `MoonRim` świeci tylko na `LAYER_FOREST`.
   Wrogowie, gracze, podłoga i ściana przy płaszczyźnie gry nie dostają z wnęki ani odrobiny światła.
2. **Bez wpływu na symulację.** Wnęka to czysta oprawa: nie ma kolizji, nie zmienia wzroku wrogów, nie jest `GameLight`,
   nie budzi ćm i nie liczy się do Uwagi. Mapa ASCII i nawigacja się nie zmieniają.
3. **Mgła wolumetryczna ignoruje `light_cull_mask`.** Światło wnęki ma `light_volumetric_fog_energy = 0` albo zasięg,
   który nie dosięga płaszczyzny gry. Smugę w samej wnęce można dać lokalnym `FogVolume` tylko w jej wnętrzu.
4. **Sylwetki to decyzja, nie przypadek.** Wróg przed oświetloną wnęką rysuje się ciemną sylwetką. Jasność wnętrza wnęki
   ma górny próg (luminancja ekranu do ustalenia w N0), żeby sylwetka była słaba. Wnęk nie stawia się tam, gdzie mapa
   celowo chowa wroga (zasadzki Ślepca, gniazda ćm).
5. **Nie zderzać się z resztą tylnej ściany.** W komórkach wnęki nie ma płyt `walls`, pilastrów `_build_ribs`, stóp
   `_build_wall_feet`, dekali tła ani słupów (`POST_Z`, `TRUNK_Z`). Wnęka nie leży za oknem `|`, lampą `I`, stemplem `!`,
   strefą zawału `^` ani strefą wydobycia — to sprawdza test.
6. **Taniej niż 0,5 ms GPU na kadr** przy HIGH 4K, z 1–2 wnękami w kadrze. LOW: bez świateł, sama emisja żarówek.
7. Tylko 3D (CLAUDE.md): modele, światła i mgła w scenie, nic rysowanego w 2D.

Lekcja z przeszłości: plan pierwszy z `ATMOSPHERE_PLAN.md` F4 wycofano, bo dawał prostokątne ciemne bryły przy brzegach kadru.
Wnęka ma więc nieregularny brzeg (futryna, wykruszony tynk, rury wchodzące w otwór), a nie gołe prostokątne cięcie.

## Etapy

### N0 — punkt wyjścia (pomiar i zrzuty, bez zmian w grze)

- Zrzuty hali stacji 1.2 i tunelu drezyny w 5 kolumnach, noc bez pogody, burza i mgła, WIDE / NORMAL / CLOSE.
  Przez `--host --nohud --mission=z1_m2 --shotat=KOL --shot=…`, profil QA (`override.cfg`).
- `--perf=15 --perfreport` w tych samych miejscach na eksporcie release.
- Luminancja ekranu przy graczu i 6–9 m od niego (jak przy strojeniu ciemności, GDD §8.3). Te liczby nie mogą się zmienić po N2.
- Wybór kolumn pilota na zrzucie (propozycja niżej).

### N1 — mechanizm wnęki (`scripts/niches3d.gd`)

- Dane w pliku mapy, obok `BACKDROP`: `const NICHES := [{"kind": "doorway", "c0": 85, "c1": 88, "r0": 23, "r1": 25, "d": 8.0, "lit": "bulb"}]`.
  Ręczne wpisy, nie generator: pilot potrzebuje kontroli kadru.
- `Level3D.build_level` pomija płyty `walls` w prostokącie wnęki. `niches3d.gd` buduje otwór z futryną, podłogę, strop, boki
  i tylną ścianę wnęki z materiałów ściany i betonu, z cieniowaniem w głąb (jak `shade` w lesie).
- Światło: `OmniLight3D` (albo `SpotLight3D` z żarówki w dół) na `LAYER_NICHE`, zasięg w obrębie wnęki, plus żarówka
  z emisją (`unshaded`, jak lampki `backdrop3d.gd`). Cień światła wnęki tylko na HIGH i tylko, jeśli pomiar w N2 go uzasadni.
- Kamera świata dostaje `LAYER_NICHE` w `cull_mask` (`view3d.gd` obok `LAYER_FOREST`).
- Test `--nichetest` (headless, dopisany do CLAUDE.md i CI): wnęka nie zachodzi na zasady z punktu 5, światło nie sięga z > −DEPTH_BACK,
  maska światła to tylko `LAYER_NICHE`, płyty ściany w otworze usunięte, a poza nim nietknięte. `--maptest` bez zmian (PASS).

### N2 — pilot: jedna wnęka w hali stacji 1.2

- **Miejsce (propozycja): kolumny 85–88, wiersze 23–25** (podłoga w wierszu 25). To parter hali pod kratą `=` z wiersza 22,
  między znacznikiem `L` (kolumna 83) a skrzynią `k` (kolumna 92). Gracz widzi halę w pierwszej minucie misji,
  a zrzut `cave_z1_m2_0` pokazuje tu czarną ścianę. Otwór ma 5,2 × 3,9 m.
- **Treść:** korytarz zaplecza 8 m w głąb z dwiema żarówkami (na 3 i 7 m), drzwi uchylone na końcu, rura i kable
  wzdłuż stropu. Daleka żarówka słabsza i chłodniejsza, bliska cieplejsza: dwa punkty światła dają oku skalę odległości.
- **A/B:** te same kadry co w N0 (noc, burza, mgła; WIDE / NORMAL / CLOSE; HIGH / MEDIUM / LOW), krótkie nagranie przejścia
  przez halę (`trailer/capture.sh`), `--perfreport` na release, luminancja przy graczach, Trzosek ustawiony przed wnęką
  (sylwetka). Użytkownik ogląda pilota w grze ze skrótu „Dead Air 87 (release)”.
- **Kryteria przyjęcia:** wnęka czytelnie „idzie w głąb” w ruchu kamery; luminancja przy graczach bez zmian (±2%);
  GPU ≤ +0,5 ms; brak migotania, szwów i prostokątnych krawędzi; sylwetka wroga zauważalna dopiero z bliska.
- **Bramka:** decyzja użytkownika po obejrzeniu. Bez niej nie ma N3.

### N3 — katalog wnęk i rozmieszczenie (po bramce)

Rodzaje: `doorway` (zaplecze z żarówką), `corridor` (korytarz 10–15 m z lampami co 4 m, najmocniejszy efekt),
`grate` (pomieszczenie za kratą, cienie prętów), `shelf` (płytka wnęka 1–1,5 m z regałem, bez światła),
`drift` (boczna sztolnia w tunelu z daleką lampą górniczą).
Rozmieszczenie: 1.2 hala i tunel (np. między słupami `w` w kolumnach 187–193), podziemia 1.1, 1.3, B1, kryjówka.
Najwyżej 1–2 oświetlone wnęki w jednym kadrze i odstęp ok. 30 m, żeby nie powstał rytm „co kafel to wnęka”.
Każda mapa: zrzuty, `--perfreport`, luminancja, `--nichetest`.

### N4 — światło w głębi poza wnękami (opcjonalnie)

Tylko jeśli N3 się sprawdzi: dalekie okna i lampy za kratami w ścianach szybów, poświata z głębi tunelu na końcu kadru.
Zasada 1 obowiązuje tak samo.

## Kolejność i rozmiar

| Etap | Co | Rozmiar | Wersja |
|---|---|---|---|
| N0 | zrzuty, pomiar, wybór kolumn | 0,5 d | bez wersji (wyniki w tym pliku) |
| N1 | `niches3d.gd`, dane mapy, wycięcie ściany, `--nichetest` | 1 d | PR, podbicie wersji |
| N2 | pilot w hali 1.2 + A/B | 0,5–1 d | ten sam PR albo następny |
| N3 | katalog i mapy | 2–3 d | po jednym PR na mapę |
| N4 | światło w głębi poza wnękami | do oceny | — |

## Ryzyka

- **SSIL** we wnętrzach może przenieść odrobinę światła wnęki na podłogę przy otworze (efekt w przestrzeni ekranu nie zna maski).
  Sprawdza to pomiar luminancji w N2. Jeśli to za dużo: mniejsza energia światła wnęki, reflektor skierowany w głąb zamiast
  żarówki świecącej na wszystkie strony albo ciemniejsza podłoga przy otworze.
- **Mgła głębi** (`Environment.fog`) może rozjaśnić daleką część korytarza. Jeśli tak, materiał tylnej ściany wnęki dostaje `fog_disabled`.
- **Perspektywa kamery** (oko 2,2 m nad środkiem kadru, przesunięta projekcja) odsłania strop wnęki bardziej niż podłogę.
  Strop musi mieć detal, nie pustą płytę.
- **Zniszczenia D1–D5** dokładają elementy przy ścianie (gruz, dziury w deskach). Test z N1 pilnuje, że wnęka ich nie przecina.

## Decyzje do podjęcia

1. Miejsce pilota: **hala stacji 1.2 (propozycja)** czy tunel drezyny 1.2.
2. Sylwetki wrogów na tle wnęki: **słabe, z progiem jasności (propozycja)**, całkiem wykluczone (wnęki tylko nad głową)
   czy świadoma mechanika („oświetlone tło zdradza wroga”).
3. Cień światła wnęki na HIGH: dopiero po pomiarze w N2 (propozycja) czy od razu.
