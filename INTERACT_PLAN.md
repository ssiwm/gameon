# Interakcja [E] i [H] — jeden cel na klatkę (INTERACT_PLAN)

Stan: **wdrożone w 1.7.691** (etapy I0–I5 w jednym PR). Wizualizacja planu i symulator zasięgów: artefakt „Plan interakcji E i H”.

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
- **I3** `interact_mark3d.gd`: cztery bursztynowe narożniki wokół celu w widoku 3D (bez światła, mgły i cienia, bez testu głębi), pasek
  postępu przy przytrzymaniu, szary przy ofercie niemożliwej, pojawia się po 0,15 s, gaśnie w 0,2 s, oddech jasności (stały przy
  „Reduce effects”). Ukryty w oględzinach i na strzelnicy. Opcja „Interaction highlight” w menu pauzy (GAMEPLAY), domyślnie włączona.
- **I4** pad: `Actions.inspect_by_hold()` — krótkie [B] bierze broń, przytrzymanie 0,4 s otwiera oględziny; podpowiedź bez „[—]”
  (`hud._weapon_prompt`); `tr()` w „Healing %s…”.
- **I5** dokumenty: `CONTROLS.md`, `GDD.md` §5, `prototype/README.md`, `CLAUDE.md`, `CHANGELOG.md`.

## Granice

- Prostokąty znacznika (`box` oferty) są przybliżone ręcznie dla każdego rodzaju obiektu; nowy obiekt podaje własny.
- Arbiter wybiera cel tylko dla lokalnego człowieka. Boty mają własną logikę (`player._bot_brain`).
- Wygląd znacznika wymaga oceny w oknie gry (testy headless nie renderują).
