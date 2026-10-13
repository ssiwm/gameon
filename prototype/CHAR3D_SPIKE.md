# Postać 3D w czasie rzeczywistym (domyślna od 1.7.156; `--char3d` lub ustawienie w menu)

Gracze i bot jako modele 3D (rig Mixamo z Tripo) renderowane do tekstury w grze 2D, zamiast wypiekanych arkuszy.
Ręce naprawdę trzymają broń przy każdym kącie celowania, animacji, broni i wyglądzie (dwukostkowe IK obu rąk).

## Uruchomienie

```bash
godot --path prototype -- --char3d                                                      # gra z postaciami 3D (gracze i bot)
godot --path prototype --script tools/shot_char3d.gd -- --set=poses|weapons|looks|states|aims|misc --part=0 --zoom=9 [--light] --out=/tmp/c3d.png
godot --path prototype --script tools/shot_guns3d.gd -- --out=/tmp/guns3d.png          # modele broni z punktami chwytu
godot --path prototype --script tools/bench_char3d.gd -- --n=1,5,10 [--lq]             # koszt renderu (--lq = niska jakość)
godot --path prototype -- --char3d-lq                                                   # gra z postaciami 3D w niskiej jakości (SS 2, bez MSAA)
# test sieciowy (dwa okna): host `--script tools/shot_net3d.gd -- --host --port=8980 --act`, klient `... -- --join=127.0.0.1 --port=8980 --watch`
python prototype/tools/prep_char3d_all.py [--chars|--guns] [--only=m83,male_scav]       # ponowny wypiek modeli (Blender)
```

Flaga działa tylko z oknem (w trybie headless gra używa sprite'ów, więc `--maptest` i `test_weapons.sh` są bez zmian).

## Jak działa

- `scripts/char3d.gd` — `SubViewport` (176×176 px, 4 px na piksel świata) z kamerą ortogonalną z boku; `Sprite2D` pokazuje wynik,
  shader dodaje obrys, światła 2D gry oświetlają sprite. Odbicie (patrzenie w lewo) = `flip_h`. Poza ekranem viewport jest wyłączany.
- Pozy w kodzie: nogi i ręce przez własne dwukostkowe IK (idle, bieg, skok, spadanie, kucanie, marsz w kucaniu, leżenie), tułów zwraca się ku kamerze
  i pochyla za celem.
- Broń: 12 modeli (`art/char3d/gun_<klucz>.glb` + `.json` z chwytami: tylny, przedni, wylot, liczba rąk). Broń obraca się wokół barku;
  prawa dłoń trzyma chwyt pistoletowy, lewa łoże (karabiny, strzelby, miotacze) — pistolet i broń biała jedną ręką, druga zwisa.
  Gdy łoże jest za daleko, broń jest wsuwana ku ciału.
- Ruch broni z `weapon_view.gd` (odrzut, dobycie, przeładowanie, zamach) trafia do postaci (`gun_extra`, `gun_kick_px`, `reload_t`, `swing_t`);
  przy przeładowaniu lewa dłoń schodzi po magazynek i wraca, przy ciosie postać robi wypad.
- Wyglądy: 6 modeli (`<płeć>_<strój>.glb`: scav / hazmat / medic) wg `player.look` (replikowane, kosmetyka); bot = kobieta Scavenger.
  Wymiana wyglądu w trakcie gry przez `Char3D.set_look`.
- Wszystko czyta zreplikowany stan gracza (`aim_dir`, kierunek, animacja z prędkości/podłoża, `weapon`, `w_state`); serwer i sieć bez zmian.
- `tools/prep_char3d.py` / `prep_gun3d.py` (Blender) robią lekkie GLB: 6 tys. ścian postaci, 2,5 tys. broni, sama tekstura koloru (≈0,5 MB zamiast 13 MB);
  `prep_char3d_all.py` zawiera tabelę wszystkich broni (długość, chwyty, flip lufy). Długość broni 3D = 0,8 × sprite 2D.

## Pomiar (RTX 3080, 4 px na piksel świata, MSAA 2×)

| postaci | GPU | CPU render | `update()` (pozy+IK) |
|---|---|---|---|
| 1 | 0,3 ms | 0,5 ms | 0,2 ms |
| 5 | 0,9 ms | 1,1 ms | 0,5 ms |
| 10 | 1,6 ms | 1,9 ms | 0,8 ms |

Typowa sesja (4 graczy + bot) ≈ 2,5 ms z 16,7 ms. Nie mierzono na słabszym GPU (zintegrowane) — do sprawdzenia przed włączeniem domyślnym.
Pokrętła kosztu: `Char3D.ss` (rozdzielczość renderu, 4), `Char3D.msaa`, `FRAME_WP` (rozmiar ramki); tryb niskiej jakości `--char3d-lq` = SS 2 + bez MSAA.
Test sieciowy (host + klient, oba z 3D): zdalni gracze i bot mają model, broń i wygląd; przeładowanie hosta widoczne u klienta.

## Klipy animacji (postój, bieg, kucanie, upadek, reanimacja — biblioteka CC0)

Ruch ciała w stanach pętlonych i przy upadku pochodzi z klipów zamiast z wzorów w kodzie; ręce z bronią i postawienie stóp dalej liczy IK,
na wierzchu klipu.
Źródło klipów: `art_src/animations/ual1/` — Universal Animation Library (Quaternius, CC0, 46 klipów; patrz `SOURCE.md` w tym katalogu).

| Stan gry | Klip z paczki | Czas klipu | Tłumienie tułowia (`upper`) | Inne |
|---|---|---|---|---|
| `idle` | `Idle_Loop` | zegar postaci | 0,5 | — |
| `run` | `Sprint_Loop` | faza kroku | 0,35 | `bounce` 0,45 |
| `crouch` | `Crouch_Idle_Loop` | zegar postaci | 0,35 | `drop` 0,05 m |
| `crouch_walk` | `Crouch_Fwd_Loop` | faza kroku | 0,35 | `drop` 0,06 m |
| `revive` | `Fixing_Kneeling` | czas od wejścia w stan (`hold`) | 1 | `arms` — ręce z klipu, broń schowana |
| upadek (`down`) | `Death01` | postęp upadku (`scrub` 0,15–1,65 s) | 1 | `drop` −0,05 m |

Skok, spadanie, lądowanie, trafienie, rzut, cios i przeładowanie to nadal pozy z kodu — po obejrzeniu klipów z paczki (`shot_clip3d.gd`):
`Hit_Chest` / `Hit_Head` są przy tej wielkości postaci niemal niewidoczne (poza z kodu szarpie tułowiem i głową wyraźniej), a `Jump_Loop`
to jedna nieruchoma poza, podczas gdy poza z kodu zmienia się z prędkością pionową (wyprost, podciągnięte kolana, sięganie do ziemi).

```bash
L=art_src/animations/ual1/AnimationLibrary_Godot_Standard.glb
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --list                                          # klipy i kości paczki
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --map=Idle_Loop:idle,Crouch_Idle_Loop:crouch       # pętle na zegarze
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --map=Sprint_Loop:run,Crouch_Fwd_Loop:crouch_walk --step-sync   # pętle kroku
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --map=Death01:down --keep-travel                 # klip jednorazowy: ciało ma się przemieścić
godot --path prototype --script tools/shot_clip3d.gd -- --clips=down,idle --out=/tmp/clips.png   # stykówka surowych klipów na modelu (wybór klipów)
godot --path prototype --script tools/shot_anim3d.gd -- --set=run|stand|crouch|revive --out=/tmp/anim   # klatki porównania: pozy z kodu | klip surowy | klip + IK (film składa ffmpeg)
# reanimacja w sieci (dwa okna): host powala bota i go podnosi, klient zapisuje zrzut, gdy zdalny gracz klęczy
godot --path prototype --script tools/shot_net3d.gd -- --host --port=8980 --mission=z1_m1 --revive --wait=440 --out=/tmp/h.png
godot --path prototype --script tools/shot_net3d.gd -- --join=127.0.0.1 --port=8980 --watch --wait=520 --out=/tmp/c.png
godot --path prototype -- --host --mission=z1_m1 --shot=/tmp/run.png --shotat=20 [--shotrun|--shotcrouch] [--noclips]   # w grze, z klipami i bez
```

- `tools/prep_anim3d.py` przenosi klip z obcego szkieletu (tu Rigify `DEF-*`; nazwy kości innych układów w tabeli `ALIASES`) na nasz, w przestrzeni
  świata: wyrównuje kierunek „przodu", skalę i pozę spoczynkową (T źródła kontra nasze A), zdejmuje przemieszczanie się postaci (klip gra w miejscu),
  a `--step-sync` zaczyna pętlę od lądowania prawej stopy, żeby zgadzała się z fazą kroku gry. Wynik: `art/char3d/anim/<nazwa>.glb` (sam szkielet i klip).
- `scripts/char_clips.gd` wczytuje te pliki, przelicza klip na szkielet każdego wyglądu (obroty względem pozy spoczynkowej, przesunięcie bioder
  w skali wysokości bioder, reszta przesunięć pominięta) i buduje `AnimationTree`: poza spoczynkowa → kolejno `mix_<stan>` ← `seek_<stan>` ← klip.
  Tabela `CLIPS` mówi, który stan bazowy ma klip i jak go dostroić.
- `upper`: klipy tej paczki są przerysowane — pochylają tułów i skręcają barki o kilkadziesiąt stopni, co przy celowaniu rzucało bronią; tułów
  i głowa dostają tylko część tego ruchu, biodra i nogi cały.
- `bounce`: sprint kołysze biodrami o 11 cm, a z barkiem idzie chwyt broni, czyli punkt, z którego gra liczy celowanie i wylot pocisku
  (`player._aim_origin`, `weapon_controller.muzzle_pos`). Zostaje 45% kołysania (głowa 4 cm, jak w pozie z kodu); stopy trzyma na torze IK nóg.
- `drop`: kucanie z klipu jest wyższe niż poza z kodu, a sylwetka ma mieć wysokość hitboxa kucania — biodra schodzą o `drop`, głowa jest wtedy
  na tej samej wysokości co w pozie z kodu (1,00–1,02 m dla `male_scav`).
- `char3d.gd` co klatkę podaje drzewu wagi stanów (te same co póz z kodu, więc przejścia trwają jak dotąd ok. 80 ms), fazę kroku (`_phase`)
  i zegar; tempo kroku i bieg tyłem działają jak dotąd. Drzewo działa w trybie ręcznym (`advance(0)` w `update()`).
- Upadek: klip `down` przejmuje całą pozę w pierwszych 12% upadku, a jego czas wybiera postęp upadku `_down`, który gra już liczy
  (`scrub`); wstawanie po reanimacji gra ten sam klip wstecz. Postać pada na plecy (poza z kodu padała twarzą w dół), upadek trwa 1,0 s
  zamiast 0,75 s. Ręce i kolana zostają z klipu (biegun IK nóg to kierunek kolana w klipie). Drgawki i zapadanie się w ostatniej sekundzie
  wykrwawiania to dalej nakładka z kodu. Bez klipu (`--noclips`) udział klipów przy upadku znika i upadek liczy kod.
- Reanimacja: `player.is_reviving` (replikowane przez `MultiplayerSynchronizer`, kosmetyka — serwer niczego z tego nie liczy) wybiera stan
  `revive`, więc klęczenie widzą wszyscy gracze, nie tylko podnoszący (wcześniej zdalny gracz stał przy rannym). Postać w 0,4 s schodzi do
  klęczenia (klip od 0,3 do 1,0 s), potem ręce pracują tam i z powrotem między 1,0 a 3,6 s klipu, dopóki trwa podnoszenie; broń jest
  schowana, ręce idą z klipu, tułów nie celuje, a postać odwraca się twarzą do rannego. Bez klipu `revive` to przysiad z bronią, jak dotąd.
- Po klipie idą nakładki z kodu: celowanie tułowiem, odrzut, trafienie, lądowanie, chwyt Pijawki. Stopy z klipu są celem IK nóg, więc nakładki
  ruszające biodrami nie odrywają ich od podłoża.
- `--noclips` wyłącza klipy (same pozy z kodu); `Char3D.clips_on` robi to samo dla jednej postaci, `Char3D.clips_raw` wyłącza dostrojenie
  (`upper`, `bounce`).
- Koszt (`bench_char3d.gd --n=10`, RTX 3080): `update()` rośnie o ok. 0,03–0,05 ms na postać, a czas CPU renderu postaci spada o podobną
  wartość (pozę szkieletu liczy się wcześniej); suma mieści się w szumie pomiaru.
- Chwyt broni (punkt celowania) względem póz z kodu: w biegu waha się o 1,3 px zamiast 0,4 px, w kucaniu jest o ok. 1,2 px wyżej.

Kandydat z paczki na później: `Interact` (sięgnięcie ręką po przedmiot, dźwignię). Wymaga tego samego co reanimacja: schowania broni, rąk
z klipu i stanu replikowanego w sieci.

### Wrogowie dwunożni: chód z klipu

Ten sam mechanizm w `enemy3d.gd` (zestaw klipów „enemy" w `char_clips.gd`): w chodzie biodra i nogi idą z klipu `Walk_Loop`, a postawę
potwora (pochylenie, ręce, głowa) dalej daje profil rodzaju z `SPEC`. Klip jest włączany na rodzaj flagą `walk_clip`:

| Rodzaj | Chód z klipu | Uwagi |
|---|---|---|
| Ślepiec, Podsłuchacz, Stalker, Mimik | tak | kolano i stopa pracują jak w kroku, postawa z profilu |
| Wołek | nie | za krótkie nogi: z ludzkim krokiem kuca i unosi kolana pod brzuch |
| Skoczek, Trzosek, Ćma, gniazdo, bossowie | nie dotyczy | pełzacz, czworonóg i modele bez szkieletu mają własny ruch |

- Z klipu zostaje 15% ruchu tułowia (`upper`), reszta to pochylenie z profilu; ręce idą za biodrami z klipu.
- Stopa nie schodzi poniżej poziomu spoczynkowego: potwory mają inne proporcje nóg niż człowiek z klipu i bez tego wchodziły w podłoże
  (Wołek do 26 cm, Stalker 11 cm).
- Postój, sen, zapowiedź ciosu, szarża, oszołomienie, trafienie, cios i śmierć to dalej pozy z kodu.
- Porównanie: `godot --path prototype --script tools/shot_enemy_clip3d.gd -- --kinds=slepiec,podsluchacz,stalker,mimik --anim=walk --movie=/tmp/en`
  (górny wiersz poza z kodu, dolny klip + profil) albo bez `--movie` stykówka: kod | surowy klip | w grze.

Różnica względem chodu z kodu jest mniejsza niż u gracza: chód z kodu już stawia wyraźne kroki, klip dodaje pracę kolana i stopy.
Paczka nie ma ruchu potworów; pasujące klipy (chód zombie) są w drugiej części biblioteki (Universal Animation Library 2), której w repo nie ma.

## Ograniczenia / dalsze kroki

- Rzut flary i przedmiotów ma pozę (prawa ręka zamachem nad głową), ale tylko lokalnie — rzut jest zdarzeniem lokalnego gracza, inni widzą dopiero rzucony przedmiot.
- Celowanie w dół wysuwa broń ku kamerze (inaczej chowa się za tułowiem); celowanie prosto w górę zasłania głowę ramieniem.
- Oświetlenie: drugi przebieg renderu (kopie siatek na warstwie 2, shader wypisuje normalne widokowe) daje mapę normalnych, więc latarka i flara dają relief jak na sprite'ach HD (odbicie `flip_h` odwraca X normalnych w shaderze). Kosztuje ok. +50% renderu postaci; `--char3d-lq` go wyłącza.
- Kucanie / skradanie to **przysiad** (biodra 0,48 m niżej, tułów niemal pionowo — wysokość ok. 0,75 stojącej); przesunięcia bioder liczy `_move_global` w przestrzeni szkieletu (osie lokalne kości Mixamo są obrócone, wcześniej przesunięcie ruszało biodra w bok, a nie w dół).
- Poza postojem, biegiem, kucaniem, upadkiem i reanimacją (klipy, patrz wyżej) pozy to proste funkcje sin/cos, nie animacje artysty; dłonie nie obejmują palcami chwytu (tylko orientacja).
- Broń biała ma jedną, uproszczoną pozę zamachu. SPECTER-1 używa swojego modelu `widmo1_01` (cewka, ten sam co w sprite'ach HD); `widmo1_02` (szyny + cewki, olive) to nieużywana alternatywa.
- Wrogowie nadal sprite'y HD — styl postaci gracza (3D) i wrogów trzeba będzie zestroić.
- Od 1.7.156 domyślne: widok 3D zawsze używa modeli, a w widoku 2D decyduje ustawienie **Characters in 2D view** (`Settings.char3d`, domyślnie 3D) lub flaga `--char3d`. Pomiar na słabszym sprzęcie nadal nie jest zrobiony.
