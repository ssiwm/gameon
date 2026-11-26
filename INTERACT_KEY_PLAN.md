# Klawisze [E], [H] i [B] w świecie zamiast ramki (INTERACT_KEY_PLAN)

Stan: **prototyp na gałęzi `feat/interact-key-mark`** (zrzuty z gry do akceptacji). Poprzednik: `INTERACT_PLAN.md` I3 (ramka z narożników).

## Problem

- Cztery bursztynowe narożniki wokół celu (`interact_mark3d.gd`) obejmują całe stanowisko razem z graczem, który przy nim stoi — wyglądają
  jak celownik albo kadr aparatu, nie jak „tu naciśnij”. Przy dużych stanowiskach (warsztat, tokarka) ramka zajmuje pół piętra.
- Postęp przytrzymania to zielony pasek 0,6 px pod dolną krawędzią ramki — prawie niewidoczny i bez charakteru gry.

## Rozwiązanie

Ramkę zastępuje **mały, zardzewiały klawisz na wierzchu celu**. Bez podpisu: nazwa akcji i koszt zostają w pasku akcji HUD jak dotąd.
Stany wg arkusza inspiracji (`art_src/ui/interact_key_ref.png`, 8 klatek):

| Stan | Wygląd | Klatka arkusza |
|---|---|---|
| pojawienie | po 0,15 s przy tym samym celu klawisz wskakuje ze skali 0,6 z przestrzeleniem (0,22 s) | — |
| możliwa | bursztynowa poświata z oddechem jasności 1,2 s, lekkie kołysanie bryły | 1 |
| naciśnięcie (stanowiska, broń) | klawisz wciśnięty w głąb i do 0,86, litera rozżarzona, mały błysk | 7 (słabiej) |
| przytrzymanie | drut kolczasty owija klawisz od góry zgodnie z postępem, poświata i drut z bursztynu w czerwień, litera i lico się rozżarzają, iskry na końcu drutu | 3–6 |
| koniec przytrzymania | wybuch: błysk, promienie, 26 iskier z grawitacją, fala; okruchy | 7–8 |
| niemożliwa | klawisz wyszarzony, bez poświaty | — |
| [E] przy niemożliwej | czerwone „zakłócenie”: pasy bryły przesunięte w bok, czerwona poświata (0,32 s) | 2 |

„Reduce effects”: bez oddechu, kołysania, wskakiwania, iskier, promieni i zakłócenia (zostaje kolor, drut postępu i błysk).

Rozmiar: **4 px świata** (ok. 18 % wzrostu postaci; 10 i 6 px po ocenie — za duże). Drut 1,85 ×, poświata 2,6 ×, wybuch 4 × boku klawisza.

## Zasoby (generatory, nie ręczne pliki)

- **Model nakładki** `art/world3d/interact/key_cap.glb` — Meshy image-to-3d z klatki 1 arkusza (litera zamalowana), 362 tys. → 6 tys.
  trójkątów i tekstura 512 px w `tools/blender_key_cap.py`. Shader udaje światło z lewej góry (`unshaded`), więc klawisz wygląda tak samo
  w jasnej kryjówce i w ciemnym lesie; górna ścianka (Meshy jej nie widział i wymyślił jaskrawą fakturę) przyciemniona w shaderze.
- **Litera**: `Label3D` z czcionki gry na licu modelu (`Actions.key("interact")`) — działa zmiana klawisza i przyciski pada.
- **Pierścień z drutu kolczastego** `art/world3d/interact/key_ring.png` — model w Blenderze (`tools/blender_barbed_ring.py`: dwie skręcone
  żyły, 12 kolców owiniętych wokół nich), render z góry, spakowany przez `tools/gen_interact_key.py` do kanałów (jasność, krycie, poświata).
  Barwę i odsłanianie po kącie daje shader.
- **Płaska nakładka** `art/world3d/interact/key_cap.png` (`tools/gen_interact_key.py`) — wariant porównawczy (`--ekeyflat`).

## Klawisze [H] i [B] — oględziny broni

Dziś obie akcje widać tylko w pasku akcji („[E] Weź M-83 (zostawia P-83) · [H] Oględziny”). Znacznik pokazuje je tak samo jak [E]:
ta sama nakładka z Meshy, ta sama litera z `Actions.key`, te same stany.

| Akcja | Wiązanie | Gdzie | Dziś (kod) |
|---|---|---|---|
| [H] oględziny | `inspect_weapon`, klawiatura `H` (pad: tylko gdy gracz przypisze przycisk) | broń na ziemi i na stojaku; przy gablocie otwiera ją w oględzinach | `weapon_controller.gd`: `Input.is_action_just_pressed("inspect_weapon")` |
| [B] interakcja na padzie | `interact` → `JOY_BUTTON_B` | wszędzie tam, gdzie [E] | arbiter `interact.gd` jak dla [E] |
| [B] przytrzymane — oględziny na padzie Classic | `Actions.inspect_by_hold()` (pad bez przycisku oględzin) | broń na ziemi i na stojaku (bez gabloty) | krótkie [B] bierze broń, przytrzymanie `INSPECT_HOLD_S` = 0,4 s otwiera oględziny (`_pad_look_t`) |

Wygląd:

- **Para [E] + [H]** (klawiatura; pad z przypisanym przyciskiem oględzin): dwa klawisze obok siebie na wierzchu broni albo gabloty —
  [E] (weź / otwórz) po lewej, [H] (oględziny) po prawej, 1 px odstępu, para wyśrodkowana na osi celu. [H] ma te same stany co [E]:
  możliwa (poświata), naciśnięcie (wciśnięcie i błysk — otwiera oględziny, potem znacznik gaśnie jak dziś w oględzinach).
- **Broń zablokowana** (kryjówka, niekupiona): [E] szary z zakłóceniem po naciśnięciu, [H] zostaje aktywny — oględziny zablokowanej
  broni są dozwolone i to one mówią, czego brakuje.
- **Pad**: litera z `Actions.key` daje nazwę przycisku pada (B, Circle, A na Nintendo) — bez osobnego kodu. Wszystkie stany [E] działają dla [B].
- **Pad Classic (oględziny przytrzymaniem)**: jeden klawisz [B]. Krótkie naciśnięcie (puszczenie przed 0,4 s) = naciśnięcie (weź).
  Przytrzymanie: drut owija klawisz w 0,4 s z postępu `_pad_look_t / INSPECT_HOLD_S`, na końcu mały wybuch (siła 0,55 jak przy
  naciśnięciu) i otwarcie oględzin. Drut zaczyna się dopiero po 0,1 s, żeby szybkie stuknięcie nie migało drutem.
- **Bez przypisanych oględzin i bez przytrzymania**: sam [E].

Dane: oferta broni (`pickup.gd interact_offer`) dostaje `"alt": "inspect_weapon"`, gdy klawisz oględzin jest przypisany, i
`"alt_hold": true` na padzie Classic; postęp przytrzymania podaje `weapon_controller.pad_look_progress()` (0..1, −1 bez przytrzymania).
`view3d._sync_interact_mark` przekazuje `pressed_alt` (`inspect_weapon` w tej klatce) i postęp. `interact_mark3d.gd` buduje klawisz
funkcją `_make_key()` (model, litera, materiały) i trzyma drugi egzemplarz dla [H]; poświata i drut są osobno dla każdego klawisza,
podkład wspólny pod parą. Pasek akcji bez zmian — klawisze w świecie mówią „gdzie”, pasek „co i za ile”.

## Położenie

- **Oś pozioma** = środek rzutu modeli celu (`view3d._target_box`, ten sam co środek dawnej ramki), bez modelu — środek strefy `box` oferty.
- **Wysokość** = wierzch obiektu ze strefy oferty w płaszczyźnie gry: górna krawędź `box`, ale najwyżej `SURFACE_PX` = 11 px (ok. 0,9 m)
  nad jej spodem (podłogą); klawisz 0,8 px nad nim. Efekt: nad blatem ławy, nad sejfem, nad zwłokami.
- Odrzucone: środek całego rzutu modeli (stanowisko = ława + tablica na ścianie + skrzynia → klawisz wisiał w powietrzu na tablicy),
  wysokość z rzutu modeli (meble stoją w głębi, ich podłoga rzutuje się wyżej), filtr „modele stojące na podłodze” (ława z tablicą to
  jedna bryła), sama strefa oferty (węzeł warsztatu stoi z boku ławy).
- Oferta może podać własny punkt `anchor` (px świata) — dla obiektów, gdzie reguła nie trafi.
- **Pozycja stała** (decyzja 1): klawisz (albo para) stoi w jednym miejscu obiektu i nie reaguje na położenie gracza. Gracz stojący
  w osi obiektu może go przykryć — drut przytrzymania, poświata i wybuch wystają spod postaci.

## Plan obrazu

Klawisz jest **pomiędzy meblem a graczem**: cały znacznik w warstwie świata (`LAYER_WORLD`), 0,6 m przed płaszczyzną gry z testem głębi
(przed meblami, które stoją w głębi). Postacie i pierwszy plan rysuje druga kamera widoku 3D (`LAYER_ACTORS`) na wierzchu, więc gracz
zawsze przykrywa klawisz. Położenie przesunięte po promieniu z oka — na ekranie klawisz zostaje nad wierzchem obiektu.
Gracz w osi obiektu przykrywa klawisz — świadomie, pozycja się nie zmienia (decyzja 1).
**Podkład** (decyzja 3): ciemna miękka plama pod klawiszem (lub parą), 2,2 × boku klawisza, krycie 0,7, w obrazie świata — klawisz
czytelny także na jasnej tablicy narzędzi i w snopie latarki. W prototypie podkład prawie nie działa — do sprawdzenia w K2c, czy nie
przykrywa go kolejność rysowania przezroczystych (render_priority) albo poświata środowiska.

## Etapy

- **K1 zasoby**: Meshy → `blender_key_cap.py`, `blender_barbed_ring.py` → `gen_interact_key.py`, import + `tex_vram.py`. ✔ (prototyp)
- **K2 znacznik**: `interact_mark3d.gd` — model, litera, poświata, drut, wybuch w płaszczyźnie gry; to samo API `tick()` (+ `pressed`);
  `view3d._sync_interact_mark` podaje naciśnięcie [E] i ustawia warstwy (`set_view_layers`). ✔ (prototyp)
- **K2b [H] i [B]**: `pickup.gd` (`alt`, `alt_hold` w ofercie), `weapon_controller.pad_look_progress()`, para klawiszy i pierścień
  przytrzymania 0,4 s w `interact_mark3d.gd`, `pressed_alt` w `view3d.gd`.
- **K2c decyzje**: podkład 2,2 × / 0,7; usunięcie wariantu płaskiego (kod `flat`,
  `--ekeyflat`, `key_cap.png`; `gen_interact_key.py` zostaje tylko dla pierścienia).
- **K3 test**: `tools/test_interact.gd` — stan znacznika (ok / muted / hold / burst) z wymuszonej oferty, wybuch tylko po pełnym
  przytrzymaniu (nie po puszczeniu w połowie), zakłócenie tylko przy niemożliwej ofercie, warstwy dzieci; [H]: para tylko przy
  przypisanym `inspect_weapon`, broń zablokowana = [E] szary i [H] aktywny, gablota z parą; pad Classic: jeden klawisz, drut dopiero
  po 0,1 s, pełny przy 0,4 s, krótkie naciśnięcie bez drutu; pozycja stała: ruch gracza wzdłuż obiektu nie zmienia położenia klawisza.
- **K4 zrzuty**: `tools/shot_interact_key.gd` (`--ekeyshots=KATALOG`, `--ekeyflat`, `--ekeystation=GRUPA`) — wszystkie stany przy
  stanowisku kryjówki, z Movie Makerem Godota klatki animacji ze stałym krokiem. ✔ Do zrobienia przed PR: sejf 1.1 w ciemności i w snopie
  latarki, zwłoki, pusty otwór 1.2 (prawdziwe przytrzymanie), broń na ziemi z parą [E] + [H] (wolna i zablokowana), gablota,
  pad Classic z przytrzymaniem [B], gracz w osi ławy (klawisz pod postacią), kamera kryjówki WIDE / CLOSE.
- **K5 dokumenty**: `INTERACT_PLAN.md` (I3 → odnośnik tutaj), `CONTROLS.md`, `GDD.md` §5, `prototype/README.md`, `CLAUDE.md`
  (linia `--ekeyshots`), `CHANGELOG.md`, wersja.

## Decyzje (przyjęte)

1. **Klawisz nie zmienia pozycji** — stoi na wierzchu obiektu niezależnie od gracza; gracz w osi obiektu może go przykryć.
2. **Model 3D z Meshy**, nie płaska tekstura — łapie kołysanie i wciśnięcie w głąb; wariant płaski znika przed PR (K2c).
3. **Kontrast** — mocniejszy ciemny podkład pod klawiszem (2,2 × boku, krycie 0,7), sprawdzony na tablicy narzędzi i w ciemnym lesie.
4. **Bez podpisu** pod klawiszem — nazwa akcji i koszt w pasku akcji.
5. **Rozmiar 4 px**, plan obrazu **pomiędzy meblem a graczem**.

## Granice

- Zmiana wyglądu: arbiter (`interact.gd`), pasek akcji HUD i serwer bez zmian; oferta broni dostaje tylko pola dla znacznika
  (`alt`, `alt_hold`), a `weapon_controller.gd` — odczyt postępu przytrzymania [B] (bez zmiany zachowania).
- Klawisze w świecie tylko dla akcji celu arbitra: [E] / [B] i [H] przy broni i gablocie. Pozostałe klawisze (flara, krzyk, latarka,
  ruch) — bez zmian, w pasku akcji i w panelu sterowania.
- Wygląd wymaga oceny w oknie gry (testy headless nie renderują).
