# Sylwetki Wołka i Rzeźnika — 1.7.377

## Wynik i przyczyna

Naprawa obejmuje zgłoszone pęknięcia w grze i podglądzie animacji. Pewność
wysoka: porównano stare i nowe GLB tym samym testem rzeczywistego skinningu.

Wołek był upraszczany jako zbiór osobnych indeksów na granicach UV.
Decimate otwierał szczeliny w geometrycznie wspólnej powierzchni.
U Rzeźnika ten problem łączył się z różnymi wagami kości na szwach:
klasyfikowanie drobnych wysp atlasu przypisywało fragmenty ciała do ręki.
Sama suma wag równa 1 nie wykrywa takiej nieprawidłowości.

## Zrealizowane w kodzie i zasobach

- `tools/enemy_mesh_repair.py`: scalenie geometrii z zachowaniem UV na
  narożnikach, odległości po powierzchni i normalizacja czterech wpływów.
- `tools/prep_enemy3d.py`: naprawa przed Decimate; dla Rzeźnika osobne budżety
  25k ciała i 5k tasaka, aby pełny model ostrza nie zabierał detali postaci.
  Błąd skryptu Blendera kończy generator kodem 1.
- `tools/rig_trellis.py`: nowe rigi korzystają z tej samej ciągłej powierzchni
  zamiast klasyfikacji wysp UV jako osobnych części anatomii.
- `art/enemy3d/wolek.glb`, `art/enemy3d/rzeznik.glb`: przebudowane modele.
  Zachowano dotychczasowy wygląd, tekstury i szkielet; tasak ma wpływ 1
  prawej dłoni. Pełny rig wejściowy Rzeźnika odzyskano ze starszego katalogu
  projektu i dodano do `art_src/enemies_f4/rzeznik_rig.glb` w Git LFS.
- `scripts/enemy3d.gd::_prepare_materials`: shader zachowuje culling
  materiału źródłowego, istotny m.in. dla dwustronnego osprzętu.
- `tools/shot_enemy_motion.gd`: MSAA 2×, zgodne z viewportem postaci gry.
- `tools/test_enemy_surface.gd` i CI: rzeczywisty skinning szwów przy
  30/60/120 fps, budżet brzegów, obecność ciała i osprzętu, wagi nóg.

## Pomiary końcowych zasobów

| Miara | Wołek przed | Wołek po | Rzeźnik przed | Rzeźnik po |
|---|---:|---:|---:|---:|
| Trójkąty | 5 999 | 5 999 | 29 978 | 29 990 |
| Otwarte krawędzie po wirtualnym scaleniu UV | 5 581 | 45 | 31 480 | 132 |
| Największa szczelina szwu w próbkach animacji | 0,010 mm | 0 mm | 1,931 m | 0 mm |

Metoda tabeli: ten sam `test_enemy_surface.gd`, kwantyzacja pozycji 0,00001
jednostki modelu, osobno dla materiałów. Inna tolerancja w poprzednim audycie
dawała 31 556 brzegów Rzeźnika; nie jest to wzrost lub zniknięcie geometrii
między tymi dwoma pomiarami. 0 mm dotyczy badanych duplikatów szwów, a nie
gwarancji braku każdego lokalnego otworu w całym modelu.

Rzeźnik po: 24 990 trójkątów ciała i 5 000 tasaka. Budżet modelu pozostaje
praktycznie taki sam. Oba modele mają 0 zdegenerowanych trójkątów w audycie.

## Weryfikacja

- Nowy test powierzchni: PASS dla postoju, chodu, zamachu, kontaktu i
  powrotu przy 30, 60 i 120 fps. Stare GLB stanowią kontrolę negatywną:
  test je odrzuca, wykrywając brzegi oraz szczeliny Rzeźnika do 1,93 m.
- `test_enemy_motion.gd`: PASS, 31 116 sprawdzeń, 0 błędów.
- `audit_enemy_assets.gd`: PASS, 14 modeli, 30/60/120 fps, 0 błędów.
- `--enemytest`: PASS 284/284. Przy zamykaniu całego testu występują
  ostrzeżenia o sprzątaniu obiektów/zasobów; podobne były też w starszym
  logu testu, sprzed tej naprawy. Testy samych modeli kończą się bez nich.
- Import Godota i `tex_vram.py --check`: PASS; 0 tekstur wymagających poprawy.
- Render klipów w Forward+ (Vulkan): 240 klatek, chód, zamach, kontakt,
  powrót, obrót, lot/lądowanie i śmierć, bez błędów skryptów lub shaderów.
- Kamera i nocne oświetlenie gry: oba modele sprawdzono na `z1_m3`
  z flagą deweloperską `--elite=rzeznik`, w Forward+ (Vulkan).

## Ograniczenia i następny krok

Zrealizowano naprawę generatorów, modeli oraz regresje. Nie jest to pełna
ręczna retopologia: źródła mają pozostałe lokalne brzegi i krawędzie
niemanifold. Budżet brzegów jest jawny; AA nie zastępuje naprawy geometrii.
Ocena plastyczna drobnych detali nadal wymaga renderu. Dalsze podnoszenie
jakości na dużych zbliżeniach powinno obejmować ręczną retopologię i wypiek
normalnych, po osobnej ocenie artystycznej. Tego rozszerzenia nie wykonano
w ramach usuwania zgłoszonych pęknięć.
