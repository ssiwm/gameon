# Strażnica 1.1 w 3D — plan przebudowy (TOWER_PLAN.md)

Stan: **szkic do akceptacji (2026-11-23)**. Prototyp w gałęzi `spike/watchtower` (worktree `gameon-tower`), dev `--towerv2`;
porównanie: `C:\deadair87\shots_tower\porownanie.jpg`.

Strażnica przed rampą kopalni na 1.1 (kol. 210–223, wiersze 7–23; nieśmiertelnik 4, Ćmy i Skoczek pod dachem, lekcja flary) nie ma
własnego modelu. Składa się z trzech ogólnych reguł widoku 3D:
- nogi — `Backdrop3D.build_frames` dla ciągów `w` z blachą `M` nad sobą (`Level3D.frame_role` „tower”): dwie proste płaszczyzny nóg
  i krzyż na całą szerokość z tyłu;
- dach i podłoga kabiny — `Level3D._build_roofs` dla `tower_slabs`: arkusz z okapem i wiązarami co 2 kafle (jak dach szopy);
- podesty zygzaka — kładki `-` z własnymi nogami i wieszakami z `deck_supports`.

## Co jest źle (zrzut gracza i `shots_tower/now_*`, `old_*`)

1. **Dach „grzebień”.** Arkusz wystaje poza nogi, a pod nim co 2 kafle wiszą wiązary (pas dolny i słupki). Z kamery to rząd zębów nad
   wieżą, bez połączenia z nogami.
2. **Kabina bez ścian.** Piętro między podłogą (w. 11) a dachem (w. 7) to pusty prostokąt z krzyżem — nie czyta się jako budka obserwacyjna.
3. **Podesty jak palety w powietrzu.** Każdy podest stoi na własnych chudych nogach albo wisi na prętach. Nic ich nie łączy z wieżą
   i nic nie mówi, że to klatka schodowa (gracz skacze z podestu na podest).
4. **Nogi bez konstrukcji.** Proste, bez rozstawu, bez stóp, z jednym krzyżem z tyłu przez całą wysokość.
5. **Podłoga z dwóch materiałów.** Płyty `M` jako deski i właz (`-`) z modelu kładki, ze szwami na styku.

## Cel

Drewniana wieża przeciwpożarowa z lat 80.: cztery nogi z bali z rozstawem u dołu na betonowych stopach, stężenia na każdym poziomie podestu,
kabina z desek z pasem okien i okiennicami, dach czterospadowy z papy. Nocą czytelna sylwetka na tle nieba, ale bez własnego światła
(ciemność to mechanika, GDD §8.3).

**Bez zmian:** kafle mapy, kolizja, trasa, wrogowie, znaczniki, cel misji, lekcja flary. Tylko widok.

## Zasady

- Przed płaszczyzną gry (z > 0) stoją tylko przednie nogi (z = 0,85, jak dziś) i podwalina kabiny pod podłogą. Żadnych stężeń ani poręczy
  przed postaciami. Przód kabiny zostaje otwarty jak przekrój budynku (oczep pod dachem, podwalina).
- Drabiny między podestami i poręcze podestów stoją za postaciami (z ≤ −0,05).
- Belki stropu leżą na spodzie kafla dachu, czyli tam, gdzie dziś wiszą Ćmy i Skoczek.
- Jeden wpis `WATCHTOWER` w danych mapy zamiast reguł zgadujących konstrukcję z kafli. Ogólne `frame_role` „tower” i `tower_slabs` pomijają
  kafle wpisu (dziś używa ich tylko 1.1).

## Prototyp T0 (zrobiony, do akceptacji)

`scripts/watchtower3d.gd`, dev `--towerv2`, światło podglądowe do zrzutów `--towerlit` (także dla starej wersji).
Elementy: nogi z rozstawem (1 m w bok, 0,7 m w głąb u gruntu) na betonowych stopach; oczepy z tyłu i z boków pod każdym podestem
i pod podłogą kabiny; krzyże stężeń co dwa poziomy (tył w dwóch przęsłach, boki); podesty na legarach z obrzeżem i poręczą z tyłu;
strome drabiny schodowe od gruntu przez wszystkie podesty do włazu; kabina z desek z pasem okien, słupkami i okiennicami (część
zamknięta, część krzywo); belki stropu; dach czterospadowy z papy z deską okapową. Ok. 300 pudeł w trzech MultiMeshach i jedna siatka dachu.

Zrzuty (`C:\deadair87\shots_tower`): `porownanie.jpg` (teraz | propozycja), osobno `old_*` / `v2_*`: `game` — kadr z podestu
w grze, `full` — cała wieża, `orb` — z ukosu.

## Etapy

| Etap | PR | Zawartość |
|---|---|---|
| **T0** prototyp — **zrobiony** | — (gałąź `spike/watchtower`) | `watchtower3d.gd` pod `--towerv2`, zrzuty przed / po |
| **T1** wdrożenie | 1 | `WATCHTOWER` w `z1_m1.gd` na stałe (bez flagi), pominięcie starej geometrii w kaflach wpisu, poprawki z akceptacji; test `tools/test_watchtower.gd` (nogi na gruncie, legary pod każdym podestem, drabiny i poręcze za płaszczyzną gry, przed nią tylko nogi i podwalina, belki stropu na spodzie kafla dachu, dach nad belkami); `test_structures.gd`, `test_front.gd`, `--maptest`; wersja + CHANGELOG |
| **T2** detal | 1 | tabliczka „STRAŻNICA PPOŻ.” (dekal z `world_decals_gen.py`, PL/EN), latarnia sztormowa pod stropem (bez światła), zerwana papa i wybite okiennice z ziarna, zużycie drewna przy gruncie |
| **T3** dźwięk (opcjonalnie) | 0–1 | skrzypienie desek i wiatr na wysokości kabiny (warstwa `amb_creak` w strefie wieży) |

## Do decyzji (zalecenia)

1. **Dach czterospadowy z papy** (prototyp) czy płaski z blachy jak dziś? *Zalecam* czterospadowy — tylko on daje sylwetkę strażnicy.
2. **Ciemny pas nad oknami.** W kadrze z gry (kamera pod okapem) dach od spodu i ściana nad oknami tworzą ciemny pas przez pół kabiny.
   *Zalecam* wyższe okna (parapet 1,0 m, nadproże 2,6 m zamiast 2,15 m) i niższy okap — Ćmy pod stropem zostają widoczne.
3. **Drabiny między podestami** są tylko obrazem (gracz dalej skacze). *Zalecam* zostawić — tłumaczą, czemu podesty idą zygzakiem.
4. **Model proceduralny czy GLB z Blendera?** *Zalecam* proceduralny (jak `building3d.gd`): wymiary z danych mapy, zero assetów, łatwe poprawki.
