# Plan: przeprojektowanie postaci — 2.5D, 3D-owa customizacja, płeć i strój

Status: **plan + wizualizacja koncepcyjna v0** (2026-10-08). Nic w grze nie zostało zmienione.
Wizualizacja: [`concepts/characters_3d_v0.png`](concepts/characters_3d_v0.png) — 2 płcie × 3 stroje, obrót, podgląd „w grze".
Generatory wizualizacji: `prototype/tools/concept/char3d_concept.py` (Blender) i `char3d_sheet.py` (Pillow).

## Status (aktualizacja)
- **Test MakeHuman (MPFB2) udany:** obie płcie, skóry, fryzury, ubrania i rig składają się skryptem w ~1 s na postać; licencja zasobów CC0.
- **Stylizacja i pierwszy strój Scavenger '87 (v1)** zrobione: jedna funkcja pozycji stosowana do wszystkich części, ubrania z regionów ciała (dziedziczą wagi rigu) + sztywne dodatki. Zrzut: `concepts/makehuman_scavenger_v1.png`.
- **Bramka P0 — przeszła technicznie:** 7 animacji × 2 płcie wypieczone do arkuszy `playerhd_*` (64×96 @0,25), dłoń trafia w punkt obrotu broni, flaga `--newchar`. Zrzut z gry i wszystkie klatki: `concepts/gate_p0_characters.png`. **Decyzję o stylu (czy ta jakość wystarcza, czy dojść do poziomu Meshy / artysty) podejmuje użytkownik.**
- **Tripo (pilot):** postać męska Scavenger '87 wygenerowana z promptu tekstowego (50 kredytów) + auto-rig (25) = 75 kredytów (0,75 USD); jakość wyraźnie wyższa niż MakeHuman (czytelny strój z kieszeniami, pasem, plecakiem, respiratorem, tekstury 4K PBR, 23 kości Mixamo, ~56 tys. trójkątów). Wypieczony tymi samymi 7 animacjami do arkusza `playerhd3_male`; flaga `--newchar=tripo`. Zrzut: `concepts/tripo_p0_male.png`. Saldo po pilocie: 425 z 500 kredytów.
- **Etap 1 HD (zrobiony):** postać Tripo w klatkach 256×384 z mapą normalnych i broń HD (m83), oświetlana dynamicznie (flara/latarka); zrzut: `concepts/stage1_lit_compare.png`. Karabin kosztował 30 kredytów; saldo po etapie: 395 z 500. Otwarte: pamięć i czas ładowania przy wielu wyglądach, zmiana rozdzielczości bazowej projektu (dziś 640×360, więc świat nadal pikselowy), HUD/UI i świat w nowej jakości (etap 2).
- **Etap 2 — próbka świata HD (zrobiona):** decyzja, że rozdzielczość bazowa (640×360) zostaje; teren HD z mapą normalnych (generator `tools/world_hd_tiles.py`), płot/kłody/kamień z Tripo (90 kredytów; saldo 305 z 500), flaga `--newworld`. Zrzut: `concepts/stage2_world_compare.png`. Otwarte: kafle `w`/`C`/`m`, tła parallax, drzewa w tle, wrogowie/bossowie, UI, pamięć.
- **Etap 3, krok 1 (zrobiony):** postać żeńska HD (Tripo, 75 kredytów; saldo 230), modele GLB dodane do gita. Dalej według listy: pozostałe rodzaje terenu i tła, wrogowie/bossowie, UI, kolejne stroje.
- **Etap 3, wrogowie (w toku):** Wołek, Trzosek i Ślepiec w HD (`--newmon`); zostają Skoczek, Podsłuchacz, Ćma, Stalker, Mimik, gniazdo i bossowie Żyła i Pijawka (ok. 55–75 kredytów na potwora; saldo 55). Zrzut: `concepts/stage3_enemies_hd.png`.
- **Etap 3, wrogowie i bossowie (zrobione):** wszystkie 11 rodzajów (Wołek, Trzosek, Ślepiec, Skoczek, Podsłuchacz, Stalker, Mimik, Ćma, gniazdo, Żyła, Pijawka) mają arkusze HD. Zostają: kodeks (portrety), pozostałe kafle/tła/UI, kolejne stroje graczy, optymalizacja pamięci, domyślne włączenie zamiast flag.
- **Etap 3, kodeks i tereny (zrobione):** portrety kodeksu w HD oraz materiały HD dla pozostałych kafli (beton, metal, woda, kratownica, deski, ściana, słup, błoto, olej). Zrzuty: `concepts/stage3_materials_hd.png`, `concepts/stage3_codex_hd.png`, `concepts/stage3_world_cmp.png`. Zostają: UI/HUD, tła parallax i drzewa, stroje graczy, pomiar VRAM i wydajności, domyślne włączenie zamiast flag.
- **Wydajność (zmierzona):** HD po cullingu i kompresji tekstur: ~415 fps (RTX 3080), ~140 wywołań rysowania, 192–247 MB VRAM (klasyczna gra ~80 MB); szczegóły w `concepts/perf_stage3.txt`. Nie zmierzone: słabsze GPU, integrowane karty, czas ładowania misji.
- **Tła i drzewa HD (zrobione):** tło parallax 2048×960 z trzema liniami świerków, księżycem i gwiazdami + pnie z korą (`--newworld`); zrzut: `concepts/stage3_backdrop_hd.png`. Zostają: HUD/UI, stroje graczy, zmniejszenie pamięci bossów, domyślne włączenie zamiast flag.
- **HUD i UI HD (zrobione, `--newui`):** czysty krój, gładkie serca/paski/moneta, miękkie panele, ikona M-83 z modelu HD; zrzuty `concepts/stage3_hud_hd.png`, `concepts/stage3_menus_hd.png`. Zostają: ikony pozostałych broni i przedmiotów HD (modele 3D), lobby, stroje graczy, pamięć bossów, domyślne włączenie zamiast flag.
- **Bronie HD (zrobione):** wszystkie 12 w HD z mapami normalnych i świeceniem; zrzut `concepts/stage3_weapons_hd.png`. Saldo Tripo po broniach: 400 kredytów.
- **Customizacja (zrobiona, `--newchar=tripo-hd-look`):** 3 stroje × 2 płcie, zakładka LOOK w warsztacie, zapis w profilu, replikacja; zrzuty `concepts/stage3_look_tab.png`, `concepts/stage3_look_ingame.png`. Zostają: wybór wyglądu w lobby, test sieciowy wyglądu, kolory i fryzury (osobne modele), domyślne włączenie.
- **Domyślne HD (zrobione):** ustawienie Graphics: HD / CLASSIC w menu, flagi dev jako nadpisania, `--classic`; zrzut `concepts/stage3_default_hd.png`. Zostają: zmniejszenie pamięci bossów, wybór wyglądu w lobby, test sieciowy wyglądu, pomiar na słabszych GPU i czasu ładowania.
- **Do zrobienia przed P1:** szlif v1 (szwy, fałdy, kontrast po zrzucie do pikseli, buty i nogi), poza down (siedząca; leżące ciało nie mieści się w klatce 16 px), animacje rąk przy celowaniu, boty, drugi i trzeci strój.

## Cel
- Postacie graczy w jakości wyraźnie wyższej niż dziś (obecnie: jeden ręcznie rysowany rig pikselowy 16×24, cztery przekolorowania P1–P4).
- Wygląd „2.5D": model 3D, renderowany do sprite'ów, z cieniowaniem i obrysem spójnym z resztą świata.
- **Customizacja:** wybór płci, stroju (z częściami), fryzury, odcienia skóry i kolorów; podgląd w 3D (obrotowy).
- Bez wpływu na rozgrywkę (czysto kosmetyczne), działa w co-opie (widać wygląd innych graczy) i nie psuje testów.

## Stan obecny (z kodu)
- `player.gd:206`: arkusz wybierany z `display_id` (`player_1..4`) lub `bot`; jedno miejsce wywołania `Sprites.attach(host, sheet)`.
- Klatka 32×48 przy skali 0,5 (hitbox i świat 16×24); animacje: idle 6, run 8, jump, fall, crouch, crouch_walk 6, down (`tools/char_player.py`).
- Broń jest osobnym sprite'em obracanym w osi **(9, 12)**; dłoń w sprite'cie musi tam wypaść (`weapon_view.gd`). Sprite jest odbijany poziomo.
- Wrogowie i boss mają „HD pikselowe" arkusze 2× (`char_monsters_hd.py`, `char_leech.py`), więc świat jest już w stylu wyższej gęstości.
- Kolor gracza (P1–P4) to jednocześnie jego identyfikacja w HUD (`BODY_COLORS`, etykieta „P1").

## Co pokazuje wizualizacja v0 (i czego nie)
- Model **proceduralny z prymitywów** (kapsuły, elipsoidy, pudełka), render w Blenderze 5.2 (EEVEE, cel-shading 3-stopniowy, obrys odwróconą skorupą).
- Pokazuje: proporcje „komiksowe" (większa głowa, krótsze nogi), sylwetki płci, trzy stroje (Scavenger, Hazmat Tech, Field Medic), fryzury i nakrycia głowy, obrót przód/3/4/bok/tył.
- **Uczciwie o ograniczeniach:**
  - To nie jest docelowa jakość. Proceduralne prymitywy mają sufit: wyglądają jak „low-poly concept", nie jak wymodelowany asset.
  - Różnica płci w widoku z boku jest subtelna (kucyk, węższe barki, szersze biodra); w widoku z przodu widać ją lepiej. Wymaga dopracowania sylwetki w modelu docelowym.
  - **Zrzut do klatki 32×48 wypada gorzej niż obecny sprite** (mniej czytelny, „rozmyty"): rozdzielczość dzisiejszej klatki jest za mała dla bryły 3D. Docelowo klatka musi mieć co najmniej **64×96 (gęstość 4×)** — patrz decyzja 2.
  - W podglądzie karabin jest wypieczony w render tylko poglądowo; w grze broń zostaje osobną, celowaną warstwą.

## Decyzje do potwierdzenia (rekomendacje)

1. **Architektura renderu.** Trzy opcje:
   - **A. Prerender do sprite'ów** (Blender → arkusze → `Sprites`): tanio w runtime, spójne z istniejącym potokiem, deterministyczne, działa z `Light2D`. Customizacja = warstwy.
   - **B. Prawdziwe 3D w grze** (`SubViewport` + szkielet + glTF): pełna swoboda (IK celowania, zmiana części w locie), ale kosztem: viewport na gracza, oświetlenie 2D nie działa na treść 3D bez obejść, trudniejsze testy headless.
   - **C. Hybryda (rekomendacja):** **jedno źródło 3D** (modularny model w Blenderze). W rozgrywce — prerenderowane, **warstwowe** arkusze (A). W ekranie customizacji — **prawdziwy obrotowy model 3D** (B) w `SubViewport`, bo tam nie ma świateł 2D ani walki, a to daje „3D customizację" bez kosztu w rozgrywce.
2. **Styl i rozdzielczość.** Rekomendacja: **„HD pixel" 4×** — klatka 64×96 przy skali 0,25 (świat bez zmian), redukcja palety rampami, 1-pikselowy obrys, filtr liniowy jak boss. Pasuje do Pijawki i potworów 2×. Alternatywa: wyższa rozdzielczość bez redukcji palety (bardziej „kreskówka 2.5D", ale kontrast z kaflami pikselowymi). **Rozstrzygamy w fazie P0 na testowym modelu obok Pijawki i Wołka.**
3. **Skąd modele (najważniejsza decyzja jakościowa).**
   - **(a) Proceduralnie w Pythonie** — mogę zrobić całość sam (jak v0), ale jakość pozostanie „stylizowany low-poly".
   - **(b) Zestawy CC0 jako baza** (np. modularne postacie z darmowych paczek; **licencje do sprawdzenia przed użyciem**), składane i retexturowane w Blenderze skryptami — zwykle najlepszy stosunek jakości do pracy.
   - **(c) Zlecony artysta 3D** — najwyższa jakość, poza moim zakresem; ja robię rig, animacje, bake, integrację i testy.
   - Rekomendacja: **(b) lub (c)** dla modeli, **ja** dla całego potoku. Samo (a) tylko jako wypełnienie.
4. **Płeć:** dwa typy ciała (MALE / FEMALE) na wspólnym szkielecie, osobne dopasowanie ubrań. Opcjonalnie rozdzielone warianty głosu (`player_hurt`, `player_down`) — osobne dźwięki, później.
5. **Kosmetyka bez statystyk.** Odblokowania wiążemy z istniejącym postępem (`Profile`): poziomy XP, pierwsze ukończenia misji, trofea bossów; bez złomu.
6. **Identyfikacja P1–P4.** Dziś robi to kolor ubrania. Po zmianie: kolorowy znacznik (obwódka/ikona pod etykietą „P1" i na HUD), a wygląd jest dowolny.

## Architektura docelowa

**Dane wyglądu** — `look.gd` (RefCounted): `body` (0/1), `head`, `hair`, `hair_color`, `skin`, `outfit`, `outfit_color`, `accessory`. Pakowane w jedną liczbę całkowitą (kilka bitów na pole). Zapis w `user://profile.cfg` (`[look]`), replikacja jak `player.perks` (`player.look`, synchronizowane przez `MultiplayerSynchronizer`), **serwer przycina wartości do zakresu** i ignoruje nieznane. Boty dostają wygląd z puli presetów.

**Warstwy sprite'a** — zamiast jednego arkusza `player_N`: stos `AnimatedSprite2D` o tej samej siatce klatek: *ciało+skóra → ubranie spód → ubranie góra → buty/rękawice → głowa/włosy → nakrycie głowy → plecak*. Skórę i włosy barwimy tintem (arkusz w skali szarości), ubrania mają kilka gotowych wariantów kolorystycznych lub maskę stref koloru (shader). Warstwa `glow` zostaje (soczewki maski, światełka). Zmiana mieści się w `Sprites.attach` i `player.gd:206`.

**Animacje:** obecne (idle, run, jump, fall, crouch, crouch_walk, down) + nowe: celowanie rąk (przedramię w ~7 kątach, broń nadal osobno w osi 9,12), podniesienie kolegi, cios, rzut, trafienie. Kolejność: najpierw obecny zestaw 1:1, potem nowe.

**Potok (Blender):** `tools/bake_chars3d.py` — modele i animacje z `art_src/` (`.blend` lub `.glb`), render ortho 4× → redukcja palety/obrys (wspólny kod z `bake_sprites.py`) → arkusze warstw + wpis w `sprites.json`. Edytujemy źródła i generator, nie wynikowe PNG (zasada z CLAUDE.md).

**Ekran customizacji:** zakładka lub „szafa" w kryjówce (obok warsztatu) i w lobby: lewa kolumna kafli (Płeć, Skóra, Fryzura, Kolor, Strój, Dodatki — ten sam układ kafli i panelu szczegółów co ARMS/SUPPLIES/PERKS), po prawej obrotowy model 3D (`SubViewport` + `Node3D`, glTF, ortho, ten sam shader cel-shading). Wygląd z HUD i kodeksu to portret wyrenderowany z tego samego modelu.

**Budżet:** docelowo ≤ ~40 MB VRAM na wszystkie arkusze postaci (kafle atlasowane, kompresja, wspólne warstwy dla obu ciał tam, gdzie się da); sprawdzamy pomiarem w fazie P1.

## Fazy (każda osobny PR z testem i wpisem w GDD)

- **P0. Blokada stylu (gate).** Jeden docelowej jakości model (jedna płeć, jeden strój) i zestaw animacji obecnego rigu, wypieczony w 64×96 i wstawiony w grze obok Pijawki, Wołka, Trzoska. Dwa warianty wykończenia (HD pixel vs gładki). **Użytkownik wybiera styl.** Bez tego nie budujemy reszty.
- **P1. Potok i warstwy.** Modularny szkielet, `bake_chars3d.py`, renderer warstwowy w grze, zachowanie hitboxu i osi broni (9,12), brak regresji (`--weapontest`, `--maptest`, zrzuty). Pierwsze wyglądy wpięte na sztywno (jeden strój na każdego z P1–P4).
- **P2. Dane i sieć.** `look.gd`, zapis w profilu, replikacja `player.look` z przycinaniem po stronie serwera, presety botów, test sieciowy (host widzi wygląd klienta).
- **P3. Ekran customizacji.** Zakładka w kryjówce i w lobby, obrotowy podgląd 3D, zapis na żywo, test headless na logice (zakres, zapis, stan UI).
- **P4. Zawartość.** Drugi typ ciała, 6 strojów, 6 fryzur, 6 odcieni skóry, akcesoria; powiązanie odblokowań z `Profile` (poziomy, trofea).
- **P5. Animacje rozszerzone.** Celowanie rąk, podnoszenie, cios, rzut, trafienie.
- **P6. Dopracowanie.** Portrety w HUD, na ścianie wyników i w kodeksie, rim light z `Light2D`, cień pod stopami, dokumentacja (README, GDD), przegląd wydajności.

## Ryzyka
- **Jakość modeli** to największe ryzyko (decyzja 3): bez prawdziwego modelera efekt końcowy zatrzyma się na poziomie v0.
- **Spójność stylu** z pikselowymi kaflami i potworami — dlatego bramka P0 z porównaniem obok siebie.
- **Pamięć tekstur** rośnie z liczbą warstw × kątów celowania; mitygacja: atlasy, wspólne warstwy, budżet mierzony.
- **Brak GPU w CI:** testy wizualne tylko lokalnie (zrzuty); CI sprawdza dane, manifest arkuszy i sieć.
- **Zakres zmian w `player.gd`/HUD** (kolor P1–P4 jako identyfikacja) — wymaga ostrożnej migracji, żeby nie zepsuć czytelności drużyny.
- **Licencje** zewnętrznych modeli (CC0 lub inne) — sprawdzamy przed jakimkolwiek importem; w repo trafia tylko to, do czego mamy prawa.
