# Interakcja [E] i [H] — jeden cel na klatkę (INTERACT_PLAN)

Stan: **wdrożone w 1.7.691** (etapy I0–I5 w jednym PR), dokończone w 1.7.692–1.7.694 (niżej „Po wdrożeniu”). Wizualizacja planu i symulator zasięgów: artefakt „Plan interakcji E i H”.

## Problem (przed 1.7.691)

Każdy obiekt reagujący na [E] sam czytał `Input` i sam pilnował pierwszeństwa. Reguła „ratowanie kolegi > broń > obiekt” była skopiowana
w sześciu obiektach (sejf, generator, zwłoki, barykada, stempel i taśma w strefie wydobycia), drezyna miała jej połowę, a stanowiska
kryjówki, tablica i drzwi strzelnicy nie miały jej wcale. Pasek akcji HUD ustalał kolejność trzeci raz, z własnej listy. Skutki:

- dwa obiekty na przytrzymanie z zachodzącymi zasięgami (np. sejf obok zwłok) ruszały jednocześnie od jednego [E], a pasek pokazywał jeden;
- w kryjówce marginesy zasięgów stanowisk utrzymywano ręcznie (stół konserwacji i ława: 2 px);
- w świecie nie było widać, czego dotyczy [E] (poza uchyloną gablotą);
- na padzie (profil Classic) oględziny broni z ziemi były niedostępne, a podpowiedź pokazywała dosłowne „[—] Inspect”.

## Rozwiązanie

`prototype/scripts/interact.gd` — arbiter celu [E] lokalnego gracza, raz na klatkę fizyki:

1. obiekty z grupy `interactables` zwracają `interact_offer(me)` (`{}` — nic), gracz sam oferuje podnoszenie kolegi;
2. wygrywa oferta możliwa (`ok`), potem wyższy priorytet, potem mniejsza odległość; przy różnicy odległości < 4 px — obiekt po stronie spojrzenia;
3. cel trzymanego [E] (przytrzymanie) zostaje celem do puszczenia klawisza, póki jego oferta jest możliwa;
4. oferta niemożliwa (brak desek, broń zablokowana) wygrywa tylko bez możliwych — pasek i znacznik pokazują powód, [E] trafia gdzie indziej.

Obiekty pytają `Interact.pressed(self)` / `Interact.held(self)`. Serwer bez zmian: zgłoszenia „trzymam / puściłem”, zasięg, życie i blokady
sprawdza jak dotąd.

| Priorytet | Oferta | Rodzaj | Plik |
|---|---|---|---|
| 100 | podnoszenie kolegi (też Mimik jako powalony kolega) | przytrzymanie | `player.gd` |
| 90 | pompowanie drezyny | przytrzymanie | `handcar.gd` |
| 80 | broń na ziemi, na stojaku, gablota | naciśnięcie | `pickup.gd` → `weapon_controller.gd` |
| 70 | taśma odsłonięta w ścianie (K4b) | przytrzymanie | `dig_zone.gd` |
| 65 | stempel pod stropem (P2d) | przytrzymanie | `dig_zone.gd` |
| 60 | sejf, generator, barykada | przytrzymanie | `strongbox.gd`, `generator.gd`, `barricade_spot.gd` |
| 50 | zwłoki (także Mimik-zwłoki) | przytrzymanie | `corpse.gd` |
| 40 | stanowiska kryjówki | naciśnięcie | `workshop.gd`, `*_bench.gd`, `locker_station.gd` |
| 30 | tablica odprawy, drzwi strzelnicy | naciśnięcie | `board.gd`, `range3d/range_door.gd` |

Decyzje (rekomendacje planu, przyjęte): stanowiska ustępują broni; remis rozstrzyga odległość, a strona spojrzenia tylko przy różnicy
< 4 px; oględziny na padzie bez przycisku — przytrzymanie [B] 0,4 s; znacznik domyślnie włączony z przełącznikiem.

## Etapy

- **I0** `tools/test_interact.gd`: reguły wyboru, prawdziwe obiekty obok siebie (sejf + zwłoki, broń + sejf, broń + stanowisko, blokada
  przytrzymania, powalony gracz), odstępy zasięgów stanowisk w `z1_hub`, oględziny przytrzymaniem na padzie, wiersze `ui.csv`. W CI.
- **I1** arbiter i przeniesienie obiektów (lista w tabeli).
- **I2** pasek akcji (`hud._prompt_candidates`) pokazuje podpowiedź obiektu tylko wtedy, gdy jest celem; ostrzeżenia bez [E] (zawał,
  drezyna bez zasilania, „wejdź na drezynę”) zostają.
- **I3** (od 1.7.699 zastąpione klawiszem w świecie — `INTERACT_KEY_PLAN.md`) `interact_mark3d.gd`: cztery bursztynowe narożniki wokół celu w widoku 3D (bez światła, mgły i cienia, bez testu głębi), pasek
  postępu przy przytrzymaniu, szary przy ofercie niemożliwej, pojawia się po 0,15 s, gaśnie w 0,2 s, oddech jasności (stały przy
  „Reduce effects”). Ukryty w oględzinach i na strzelnicy. Opcja „Interaction highlight” w menu pauzy (GAMEPLAY), domyślnie włączona.
- **I4** pad: `Actions.inspect_by_hold()` — krótkie [B] bierze broń, przytrzymanie 0,4 s otwiera oględziny; podpowiedź bez „[—]”
  (`hud._weapon_prompt`); `tr()` w „Healing %s…”.
- **I5** dokumenty: `CONTROLS.md`, `GDD.md` §5, `prototype/README.md`, `CLAUDE.md`, `CHANGELOG.md`.

## Po wdrożeniu (1.7.692)

- **I2 dokończone:** pasek akcji czyta cel arbitra przez jeden pomocnik `hud._target_in(group)` (w 1.7.694 zastąpiony przez `interact_hint`); 13 funkcji `_near_*` (i
  `_brief_choices`) z osobnymi pętlami po grupach i własnym sprawdzaniem zasięgu zniknęło. Zasięg, panel kryjówki i liczba misji na
  tablicy żyją tylko w ofercie obiektu.
- **I4 dokończone:** `Actions.fmt` pomija nawias akcji bez wiązania na bieżącym urządzeniu, gdy stoi przed drugim klawiszem — stopka
  oględzin na padzie Classic to „[START]  Close”, nie „[—] [START]  Close”. Sprawdza to `test_interact.gd`.
- **I3, prostokąty z zrzutów:** sejf (dawna strefa 2D 26 × 20 px obejmowała gracza) i broń na ziemi (leży płasko, ~13 × 2 px) mają
  prostokąty modeli 3D. Zrzuty w oknie (z latarką i bez): sejf i zwłoki 1.1, broń na ziemi, generator i pusty otwór 1.2, ława, gablota i
  prasa w kryjówce.
- Warunki etapów sprawdzone po wdrożeniu: `test_net_session.sh` (I1), `test_front.gd` i `test_shadow_casts.gd` (I3).

## Ramka z bryły modelu (1.7.693)

- Widok 3D liczy ramkę znacznika z modeli celu: AABB jego siatek rzutowane z oka kamery na płaszczyznę gry
  (`interact_mark3d.project_box`, `view3d._target_box`). Ramka obejmuje to, co widać na ekranie — także sejf i meble stojące w głębi
  (perspektywa) — i idzie za ruchomym modelem. Modele celu: przedmioty HD jego poddrzewa (`_items`: sejf, generator, tablica narzędzi,
  drezyna), wyposażenie stanowisk kryjówki (`_station_props3d`: szafki z ławką, ława z tablicą narzędzi i skrzynią, prasa z regałem,
  stół pirotechniczny z szafą) i model broni (`_guns`).
- `box` oferty zostaje zapasem dla obiektów bez modelu (zwłoki, pusty otwór pod barykadę, strefa wydobycia, powalony kolega) i dla
  oferty z `"fit": false` — gablota w zbrojowni ma ramkę całej szafy, nie broni w środku.
- Zrzuty w oknie: sejf 1.1, broń na ziemi, generator i pusty otwór 1.2; w kryjówce szafki, warsztat, prasa, stół pirotechniczny, gablota.
  Test: `test_interact.gd` (rzut w płaszczyźnie gry bez zmian, w głębi mniejszy i bliżej osi oka, gruba bryła = obrys obu; gablota bez `fit`).

## Podpowiedź od obiektu (1.7.694)

- Pełny wariant I2: tekst, postęp i kolor podpowiedzi podaje sam obiekt (`interact_hint(me)` obok `interact_offer`), a pasek akcji
  (`hud._prompt_candidates`) bierze je od celu arbitra. Mają ją generator, sejf, zwłoki, pusty otwór pod barykadę, osiem stanowisk
  kryjówki z tablicą misji, wejście na strzelnicę i broń / gablota (`pickup.gd`). HUD nie zna już stanu tych obiektów — nowy obiekt
  dopisuje ofertę i podpowiedź u siebie.
- Kolejność ważności bez zmian: podpowiedź celu stoi tam, gdzie dawny generator (pod ratowaniem, narzędziami i drezyną), broń i gablota —
  niżej, pod ostrzeżeniami stropu strefy wydobycia. Strefa wydobycia (taśma, stempel, ostrzeżenie), drezyna, ratowanie i drzwi zostają
  w HUD: mieszają podpowiedź celu z ostrzeżeniami, które nie zależą od [E].
- `test_interact.gd`: podpowiedź sejfu przed i w trakcie wyważania, zwłoki, `interact_hint` w każdym obiekcie z podpowiedzią.

## Granice

- Bez zrzutu do akceptacji: drezyna (cel dopiero po uruchomieniu generatorów), taśma i stempel w strefie wydobycia, tablica misji i
  stanowiska kryjówki jeszcze nieodblokowane na świeżym profilu (konserwacja, laboratorium, tokarka), drzwi strzelnicy, powalony kolega.
- Ramka stanowiska obejmuje całe jego wyposażenie (np. tokarka z wózkiem, szlifierką i skrzynią) — tak wygląda „stanowisko” na ekranie.
- Arbiter wybiera cel tylko dla lokalnego człowieka. Boty mają własną logikę (`player._bot_brain`).
- Wygląd znacznika wymaga oceny w oknie gry (testy headless nie renderują).
