# Ekwipunek postaci — modele z generacji lokalnej

Modele dopinane do postaci przez `prototype/tools/char_mpfb.py` (`GEAR_MODELS`). Powstały lokalnie w ComfyUI:
obraz koncepcyjny z **FLUX.1 [schnell]** (Black Forest Labs, licencja Apache 2.0), model 3D z PBR z **TRELLIS 2**
(Microsoft, licencja MIT) — wynik w całości nasz. Plik źródłowy uproszczony do 20 tys. trójkątów i tekstur 2048 px.
Śpiwór i aparat oddechowy są teraz skryptem w `char_mpfb.py` (z TRELLIS wychodził grudkowaty koc, a cienkie węże aparatu rwały się przy upraszczaniu).

| Plik | Obraz | Prompt FLUX (seed) |
|---|---|---|
| `backpack.glb` | `backpack_concept.png` | 1980s military field rucksack, olive drab heavy canvas with dark brown leather straps and brass buckles, big top flap, two side pockets, a rolled tan wool blanket strapped on top, worn, dusty, scuffed, realistic product photo, single object, plain white background, three-quarter rear view, whole object in frame, soft studio light (11) |
| `medbag.glb` | `medbag_concept.png` | 1980s military field medic backpack, off-white heavy canvas with a large red cross on the front flap, dark leather straps and metal buckles, worn and dusty, realistic product photo, single object, plain white background, front view, whole object in frame, soft studio light (3) |
| `pouch.glb` | `pouch_concept.png` | 1980s military ammunition belt pouch, olive drab heavy canvas with snap-closed flap and belt loop, worn and dusty, realistic product photo, single object, plain white background, front view, whole object in frame, soft studio light (3) |
| `canteen.glb` | `canteen_concept.png` | 1980s military water canteen in an olive drab canvas cover with black screw cap and belt clip, worn and dusty, realistic product photo, single object, plain white background, three-quarter view, whole object in frame, soft studio light (3) |

Wymiary docelowe (`GEAR_MODELS` w `char_mpfb.py`, generator sprawdza ±10%): plecak 0,58 m wysokości, śpiwór 0,58 m długości i 0,19 m
średnicy, aparat oddechowy 0,60 m, plecak medyczny 0,34 m wysokości i 0,12 m głębokości, ładownica 0,12 × 0,065 m,
manierka 0,20 × 0,085 m. Skala zależy od wysokości kości szyi danego fenotypu; nie jest stałym mnożnikiem płci.

Od 1.7.369 medyczny plecak jest dosunięty do kurtki bez wpuszczania frontu siatki w plecy. Szelki są rzutowane na ciało i ubranie,
z pominięciem stetoskopu. Jego rurka zachowuje grubość, ma około 0,36 m wysokości × skala fenotypu i wagi tułowia/szyi;
poprzednie wagi głowy/bioder rozciągały go w animacjach. Hełm M1951 pozostaje źródłowym zasobem MakeHuman (jaldmic, CC-BY),
z rantem i otworami wentylacyjnymi, ale cały jest przypięty do głowy. Krzyż jest malowany bezpośrednio w albedo skorupy
(`paint_helmet_cross`, po `unique_uv`), bez osobnych brył, normalnej wypukłości i dodatkowego materiału.

Przebudowa obu medyków: `blender -b -P prototype/tools/char_mpfb.py -- male_medic female_medic`, import Godota,
`python prototype/tools/tex_vram.py`, ponowny import oraz `test_proportions.gd` (osprzęt, mocowania i krzyż w teksturze).
