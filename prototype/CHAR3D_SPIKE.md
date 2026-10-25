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
  shader dodaje obrys, światła 2D gry oświetlają sprite. Odbicie (patrzenie w lewo) = `flip_h` — tylko w podglądzie 2D; w widoku 3D model się obraca (sekcja „Chwyt broni i punkty celowania”). Poza ekranem viewport jest wyłączany.
- Pozy w kodzie: nogi i ręce przez własne dwukostkowe IK (idle, bieg, skok, spadanie, kucanie, marsz w kucaniu, leżenie), tułów zwraca się ku kamerze
  i pochyla za celem.
- Broń: 12 modeli (`art/char3d/gun_<klucz>.glb` + `.json` z chwytami: tylny, przedni, wylot, liczba rąk), od 1.7.213 budowanych skryptem
  `tools/gun_proc.py` w naturalnej skali. Broń obraca się wokół barku;
  prawa dłoń trzyma chwyt pistoletowy, lewa łoże (karabiny, strzelby, miotacze) — pistolet i broń biała jedną ręką, druga zwisa.
  Gdy łoże jest za daleko, broń jest wsuwana ku ciału. Szczegóły chwytu i punktów celowania: sekcja „Chwyt broni i punkty celowania".
- Ruch broni z `weapon_view.gd` (odrzut, dobycie, przeładowanie, zamach) trafia do postaci (`gun_extra`, `gun_kick_px`, `reload_t`, `swing_t`);
  przy przeładowaniu lewa dłoń schodzi po magazynek i wraca, przy ciosie postać robi wypad.
- Wyglądy: 6 modeli (`<płeć>_<strój>.glb`: scav / hazmat / medic) wg `player.look` (replikowane, kosmetyka); bot = kobieta Scavenger.
  Wymiana wyglądu w trakcie gry przez `Char3D.set_look`.
- Wszystko czyta zreplikowany stan gracza (`aim_dir`, kierunek, animacja z prędkości/podłoża, `weapon`, `w_state`); serwer i sieć bez zmian.
  W drugą stronę idą tylko punkty celowania (`aim_points`) — liczone z pozy nominalnej, nie z klatki animacji.
- `tools/prep_char3d.py` (Blender) robi lekkie GLB postaci: 6 tys. ścian, sama tekstura koloru (≈0,5 MB zamiast 13 MB).
- Bronie buduje `tools/gun_proc.py` (wszystkie naraz: `tools/gun_proc_all.sh`, ok. 3 min): bryły z fazami + materiały proceduralne wypieczone
  w Cycles do koloru, normalnych, ORM i emisji 2048² (2–11 tys. trójkątów, ok. 1 MB na broń). Projekty wzorowane na prawdziwych konstrukcjach,
  długości naturalne względem postaci 1,8 m (P-83 0,19 m, M-83 0,88 m, SPECTER-1 1,15 m). Początek układu modelu = nadgarstek dłoni tylnej.
  Stara droga (`prep_gun3d.py`, tabela w `prep_char3d_all.py --guns`) przycinała modele z Tripo do 2,5 tys. trójkątów.
- Stal broni ma pełną metaliczność: w rękach odbija niewidoczne „niebo odbić" warstwy graczy (`view3d.gd`, `ACTOR_REFLECT`), na stojakach
  kryjówki — sondę odbić z dwoma ekranami (`_add_rack_probe`); oglądana broń kołysze się i ma dwa własne reflektory.

## Chwyt broni i punkty celowania (1.7.215)

```bash
godot --path prototype --script tools/shot_hands3d.gd -- --guns=m83,p64 --aims=-50,0,50 --out=/tmp/hands.png   # zbliżenia rąk: z boku, od lufy, z góry
godot --path prototype --script tools/shot_hands3d.gd -- --guns=maczeta,kilof --aims=0 --views=side --size=2.3 --swing=0.45   # cała postać, faza ciosu
godot --headless --path prototype -s tools/test_aim_points.gd                                                    # wylot rozgrywki kontra lufa modelu, PASS
blender -b --factory-startup -P prototype/tools/gun_proc.py -- m83 prototype/art/char3d/gun_m83.glb --json-only  # sam .json (punkty chwytu), bez wypieku
```

- **Punkty celowania rozgrywki.** `player._aim_origin()` i `weapon_controller.muzzle_pos()` biorą chwyt i wylot z `Char3D.aim_points(aim, strona,
  kuca, klucz broni)`, a nie z modelu. Poza nominalna to postawa z klipu postoju / kucania danego modelu (chwila 0, obojczyki w spoczynku; bez klipów —
  poza spoczynkowa z pochyleniem z kodu) plus obroty z `_pose_body`, które zależą tylko od stanu rozgrywki: pochylenie od broni, zwrot tułowia ku kamerze
  i celowanie kręgosłupem (`SPINE_AIM`). Nie ma w niej kroku, kołysania, odrzutu, trafienia, lądowania, przeładowania ani odbicia lustrzanego modelu,
  więc te rzeczy nie ruszają toru pocisków. `muzzle_px` / `grip_px` zostały jako punkty MODELU dla efektów (błysk, wiązka, latarka).
  `tools/test_aim_points.gd` (CI) sprawdza niezależność od animacji, symetrię stron i odchylenie wylotu od lufy modelu w spokojnej pozie (próg 1,5 px
  świata, jest 0,8). Tryb headless nie ma postaci 3D — serwer dedykowany liczy wylot po staremu, od korpusu (`MUZZLE_TOLERANCE` 40 px to przykrywa).
- **Broń trzyma się pozy nominalnej.** Początek układu broni liczymy od barku nominalnego, a odchylenie barku modelu od niego przechodzi na broń
  w części `GUN_FOLLOW` (0,5; P-83 0,8; broń biała 1): ciało pracuje pod bronią, ręce to wybierają. Kąt broni modelu goni kąt celowania sprężyną
  (`AIM_SPRING`, tłumienie 0,78): obrót o 45° trwa ok. 0,1 s z drobnym wybiegiem, a strzał dociąga broń na linię celowania od razu.
- **Dłonie z geometrii.** Kości dłoni z Tripo mają przypadkowe osie, inne w każdym modelu i w każdej dłoni, więc `_measure_hands` wyznacza układ dłoni
  z wierzchołków przypisanych do kości: palce = od nadgarstka do środka ciężkości, grzbiet = najcieńszy wymiar bryły po stronie, przy której kciuk
  wypada z przodu; do tego długość i grubość dłoni. `_hand_target` ustawia środek dłoni (`PALM_AT` długości) w punkcie broni: dłoń tylna na `grip`
  grzbietem do kamery (kąt śródręcza `wrist` z `WEAPON_POSE`: chwyt pistoletowy 12°, szyjka kolby −8°, rękojeść −50°), przednia pod `hold` wnętrzem
  do góry, a przy `hold_v` (WRATH-4) na chwycie pionowym. Punkty `grip` / `hold` są w `gun_<klucz>.json` (z `gun_proc.py`); stare `rear` / `fore`
  to nadgarstki z poprzedniego układu (początek układu modelu się nie zmienił).
- **IK ręki** (`_arm_ik`): po wyznaczeniu łokcia ramię i przedramię są obracane wokół własnej osi tak, żeby zgięcie wypadało w anatomicznej osi łokcia
  (z lekkiego ugięcia ręki w pozie spoczynkowej); `_set_hand` oddaje przedramieniu 55% skrętu nadgarstka (model nie ma kości skrętu), `_reach_clavicle`
  przesuwa bark ku dłoni (22% kąta, najwyżej 16°). Obojczyki nie biorą ruchu z klipów (`_rest_clavicles`), gdy ręce prowadzi IK.
- **Obrót (1.7.216).** Zmiana kierunku to obrót modelu wokół pionu w `TURN_TIME` (0,16 s, sinusem — łagodny start i hamowanie), przez pozę przodem
  do kamery: `_face` (−1..1) → `_cam_c` → `model_yaw`, który `view3d.gd` przykłada do aktora zamiast odbicia skalą. Broń zostaje w prawej ręce. Tułów
  zwraca się ku kamerze w obie strony, celując w dół broń wysuwa się ku kamerze po właściwej stronie. Rozgrywka bierze stronę od razu docelową;
  poza nominalna jest zawsze liczona jak dla zwrotu w prawo i odbijana, a stałe przesunięcie barków od zwrotu tułowia (ok. 0,18 m) wybierają ręce —
  broń modelu zostaje przy wylocie rozgrywki (`test_aim_points.gd`: 0,6 px w obie strony). `muzzle_px` / `grip_px` liczy `_to_px` tak jak widok 3D
  (aktor w pozycji gracza, obrócony o `model_yaw`). Podgląd obrotu: `tools/shot_hands3d.gd -- --guns=m83 --views=game --size=2.1 --turn=-2,2,4,6,8,10,20`.
- **P-83** (klucz `p64`) oburącz na wyprostowanych rękach, lewa dłoń podpiera stopkę chwytu; przy przeładowaniu schodzi do pasa i wraca. **Broń biała** w spoczynku
  stoi w gardzie (`MELEE_GUARD`), cios wychodzi z gardy i do niej wraca; kilof jest zawsze trzymany oburącz.
- Klipy z paczek CC0 do walki wręcz (`Sword_Regular_A/B/C`, `Sword_Attack`, `Melee_Hook`) obejrzane na stykówce i odrzucone: to cięcia z obrotem całego
  ciała, w widoku z boku postać odwraca się plecami do kamery (ten sam powód co przy `OverhandThrow`). Klipy pistoletowe (`Pistol_*`) nic nie dają, dopóki
  ręce prowadzi IK pod dowolny kąt celowania.

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
| `run` | `Sprint_Loop` | faza kroku | 0,55 | `bounce` 0,8 |
| `crouch` | `Crouch_Idle_Loop` | zegar postaci | 0,35 | `drop` 0,05 m |
| `crouch_walk` | `Crouch_Fwd_Loop` | faza kroku | 0,5 | `drop` 0,06 m |
| `revive` | `Fixing_Kneeling` | czas od wejścia w stan (`hold`) | 1 | `arms` — ręce z klipu, broń schowana |
| upadek (`down`) | `Death01` | postęp upadku (`scrub` 0,15–1,65 s) | 1 | `drop` −0,05 m |
| wstawanie (`getup`) | `LayToIdle` (druga paczka, `art_src/animations/ual2/`) | postęp wstawania (`scrub` 0,1–1,5 s) | 1 | — |

Skok, spadanie, lądowanie, trafienie, rzut, cios i przeładowanie to nadal pozy z kodu — po obejrzeniu klipów z paczek (`shot_clip3d.gd`):
`Hit_Chest` / `Hit_Head` są przy tej wielkości postaci niemal niewidoczne (poza z kodu szarpie tułowiem i głową wyraźniej), a `Jump_Loop`
to jedna nieruchoma poza, podczas gdy poza z kodu zmienia się z prędkością pionową (wyprost, podciągnięte kolana, sięganie do ziemi).
`OverhandThrow` sprawdzony jako nakładka na górę ciała: postać odwraca się przy zamachu do kamery i kłania po rzucie, a poza z kodu
prowadzi rękę łukiem w kierunku celowania — w widoku z boku czyta się lepiej.

```bash
L=art_src/animations/ual1/AnimationLibrary_Godot_Standard.glb
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --list                                          # klipy i kości paczki
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --map=Idle_Loop:idle,Crouch_Idle_Loop:crouch       # pętle na zegarze
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --map=Sprint_Loop:run,Crouch_Fwd_Loop:crouch_walk --step-sync   # pętle kroku
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=$L --map=Death01:down --keep-travel                 # klip jednorazowy: ciało ma się przemieścić
blender -b --factory-startup -P prototype/tools/prep_anim3d.py -- --from=art_src/animations/ual2/UAL2_Standard.glb --map=LayToIdle:getup --keep-travel
godot --path prototype --script tools/shot_clip3d.gd -- --clips=down,idle --out=/tmp/clips.png   # stykówka surowych klipów na modelu (wybór klipów)
godot --path prototype --script tools/shot_anim3d.gd -- --set=run|stand|crouch|revive|getup --out=/tmp/anim   # klatki porównania: pozy z kodu | klip surowy | klip + IK (film składa ffmpeg)
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
- `upper`: klipy tej paczki są przerysowane — pochylają tułów i skręcają barki o kilkadziesiąt stopni; tułów i głowa dostają część tego ruchu
  (bieg 0,55, postój 0,5), biodra i nogi cały. Do 1.7.214 było 0,35, bo z barkiem szła broń i punkt wylotu pocisku.
- `bounce`: sprint kołysze biodrami o 11 cm; zostaje 80% kołysania (do 1.7.214 — 45%). Od 1.7.215 rozgrywka liczy celowanie i wylot z pozy nominalnej
  (`aim_points`), a broń modelu bierze tylko połowę ruchu barku, więc kołysanie ciała nie rzuca już bronią ani torem pocisku.
- `drop`: kucanie z klipu jest wyższe niż poza z kodu, a sylwetka ma mieć wysokość hitboxa kucania — biodra schodzą o `drop`, głowa jest wtedy
  na tej samej wysokości co w pozie z kodu (1,00–1,02 m dla `male_scav`).
- `char3d.gd` co klatkę podaje drzewu wagi stanów (te same co póz z kodu, więc przejścia trwają jak dotąd ok. 80 ms), fazę kroku (`_phase`)
  i zegar; tempo kroku i bieg tyłem działają jak dotąd. Drzewo działa w trybie ręcznym (`advance(0)` w `update()`).
- Upadek: klip `down` przejmuje całą pozę w pierwszych 12% upadku, a jego czas wybiera postęp upadku `_down`, który gra już liczy
  (`scrub`). Postać pada na plecy (poza z kodu padała twarzą w dół), upadek trwa 1,0 s zamiast 0,75 s. Wstawanie po reanimacji gra
  klip `getup` (siada, podpiera się, wstaje; 0,95 s jak dotąd) — zaczyna się w tej samej pozie, w której kończy się upadek, a przejście
  między klipami trwa 0,2 s; powalenie w trakcie wstawania wraca płynnie do klipu upadku. Ręce i kolana zostają z klipu (biegun IK nóg to kierunek kolana w klipie). Drgawki i zapadanie się w ostatniej sekundzie
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

### Wrogowie dwunożni: chód i cios z klipów

Ten sam mechanizm w `enemy3d.gd`: w chodzie biodra i nogi idą z klipu, a postawę potwora (pochylenie, ręce, głowa) dalej daje profil
rodzaju z `SPEC`. Klipy potworów pochodzą z drugiej paczki tego samego autora: `art_src/animations/ual2/` (Universal Animation Library 2,
CC0, 43 klipy; patrz `SOURCE.md`). Zestaw klipów wybiera na rodzaj klucz `walk_clip`, cios z klipu — `attack_clip`:

| Rodzaj | Chód | Zapowiedź i cios | Uwagi |
|---|---|---|---|
| Ślepiec | `zombie` (`Zombie_Walk_Fwd_Loop`) | klip `Zombie_Scratch` | powłóczysty krok; przy ciosie unosi się i rzuca w dół |
| Stalker | `zombie` | klip `Zombie_Scratch` | jak wyżej |
| Podsłuchacz | `zombie` | z kodu (krzyk) | klip ataku to zamach pazurami, nie pasuje do krzyku |
| Mimik | `human` (`Walk_Loop`) | z kodu | udaje człowieka, więc chodzi jak człowiek |
| Wołek | z kodu (`gait: heavy`) | z kodu | za krótkie nogi: z klipem kuca i unosi kolana pod brzuch (1.7.378–1.7.380 próbowano klipu `zombie`: drobny krok na palcach); od 1.7.382 ciężki, kołyszący chód goryli z wymachem rąk |
| Skoczek, Trzosek, Ćma, gniazdo, bossowie | nie dotyczy | nie dotyczy | pełzacz, czworonóg i modele bez szkieletu mają własny ruch |

- Chód zombie obniża sylwetkę. Z klipu zostaje 20% ruchu tułowia (`upper`), a biodra stoją o 5% swojej wysokości wyżej niż w klipie
  (`rise`); mimo to głowa jest w chodzie niżej niż w pozie z kodu: Ślepiec ok. 20 cm, Podsłuchacz ok. 15 cm, Stalker ok. 20 cm.
- Zapowiedź ciosu (`windup`) trzyma chwilę klipu, w której potwór unosi się z ręką w górze; cios (`attack`) gra rzut w dół postępem ciosu
  z gry. Ręce idą wtedy z klipu (cele IK = dłonie z klipu), więc **zapowiedź wygląda inaczej niż dotąd** (było: ręce wyciągnięte w przód
  u Stalkera, uniesione u Ślepca). Czas zapowiedzi i ciosu, rozżarzenie oczu i trafienie liczy gra jak dotąd.
- Stopa nie schodzi poniżej poziomu spoczynkowego: potwory mają inne proporcje nóg niż człowiek z klipu.
- Postój, sen, szarża, oszołomienie, trafienie i śmierć to dalej pozy z kodu. Klip postoju zombie (`Zombie_Idle_Loop`) odrzucony: zgina
  Stalkera do ok. 60% wysokości.
- Porównania: `godot --path prototype --script tools/shot_enemy_clip3d.gd -- --kinds=slepiec,podsluchacz,stalker,mimik --anim=walk
  --sets=human,zombie --movie=/tmp/en` (wiersze: kod, klip human, klip zombie); `--anim=attackseq --movie=…` (chód → zapowiedź → cios,
  kod kontra zestaw rodzaju); bez `--movie` stykówka: kod | surowy klip | w grze.

W drugiej paczce są też klipy dla gracza, jeszcze nieużyte: `Consume`, `Chest_Open`, `ClimbUp_1m_RM` — każdy wymaga stanu w grze
(leczenie, otwieranie skrzyni, wspinaczka), którego postać dziś nie ma.

## Realistyczne postacie (1.7.220, CHARACTER_PLAN.md)

Stylizowane modele Tripo (głowa 1/4–1/5 wzrostu, krótkie ręce, wielkie dłonie) zastąpił komplet sześciu realistycznych postaci w
`art/char3d/mpfb/` (`Char3D.charset = "mpfb"`; stare: `--charset=tripo`). Wszystko powstaje skryptem — `tools/char_mpfb.py` w Blenderze
z dodatkiem MPFB2 i paczkami zasobów MakeHuman (instrukcja w nagłówku skryptu):

- **Ciało:** MPFB2 (CC0), fenotyp z tabeli `OUTFITS`, wzrost 1,8 m (mężczyzna) i 1,7 m (kobieta). Szkielet „mixamo" z MPFB ma te same nazwy
  kości co modele Tripo, plus palce — `char3d.gd`, IK, `aim_points` i klipy działają bez zmian w logice.
- **Stroje:** ubrania z paczek MakeHuman (CC0 i CC-BY: kamizelka taktyczna, hełmy KZ45 i M1951, maska przeciwgazowa, mundur ratownika,
  kombinezony), przebarwiane skryptem: kamuflaż leśny lat 80. (scav), żółty kombinezon (hazmat), granat (medyk). Maska scava wisi przy
  biodrze (`relocate`).
- **Ekwipunek:** modele z lokalnej generacji — obraz z FLUX.1 [schnell], model 3D z PBR z TRELLIS 2 (ComfyUI) — w `art_src/gear/`
  (`GEAR_MODELS`): plecak, śpiwór, aparat oddechowy, plecak medyczny, ładownice, manierka. Generator skaluje je do rzeczywistych wymiarów
  i przerywa pracę przy odchyłce ponad 10%; szelki, pas, chusta, taśma i krzyż na hełmie są bryłami ze skryptu.
- **Detal:** Cycles wypieka w kolor ubrań i ekwipunku cienie kontaktowe (AO) i brud od dołu; tekstury w GLB jako WebP (1024 px),
  ok. 30 tys. trójkątów na postać, 1–3 MB na model.
- **Klipy:** `char_clips._retarget` przelicza klip w przestrzeni szkieletu (ten sam obrót względem pozy spoczynkowej w świecie szkieletu),
  więc klip ze szkieletu Tripo gra na szkielecie MPFB mimo innych osi kości; przy identycznych osiach wynik jest jak dawniej.
- **Mimik** używa modelu `mpfb/male_scav`; świecące oczy liczone z pozy kości głowy przez transformację szkieletu (`eye_off` w SPEC).
- **Test:** `test_proportions.gd` (6) sprawdza ze szkieletu anatomię każdej postaci: kark 0,80–0,88 H, biodra 0,50–0,60 H, ręka 0,28–0,36 H,
  noga 0,42–0,52 H, barki 0,18–0,26 H, głowa z nakryciem od karku ≤ 0,22 H.

Ograniczenia: ubrania MakeHuman mają prostsze tekstury niż stroje Tripo (kombinezon damski hazmat ma smugi po napisach oryginału);
od 1.7.314 palce zginają się na chwycie (`_measure_fingers` / `_apply_fingers`: oś zgięcia członu = grzbiet dłoni × kierunek członu w spoczynku; zacisk 1 na chwycie i rękojeści, 0,7 pod łożem, 0,25 w luźnej dłoni), a prawa rękawica nie ma już wierzchołków przypiętych do obojczyka (`glb_glove_weights.py`, w generatorze `fix_glove_weights`; w pozie z bronią rozciągały się w „pręty” do bioder); klipy ruchu to nadal Quaternius UAL (mocap — E3).

## Ograniczenia / dalsze kroki

- Rzut flary i przedmiotów ma pozę (prawa ręka zamachem nad głową), ale tylko lokalnie — rzut jest zdarzeniem lokalnego gracza, inni widzą dopiero rzucony przedmiot.
- Celowanie w dół wysuwa broń ku kamerze (inaczej chowa się za tułowiem). Przy celowaniu w górę tułów odchyla się do tyłu (`SPINE_AIM_UP`), a broń odsuwa się od barku (`UP_REACH`); przy celowaniu pionowo w górę ręce i tak przechodzą przed twarzą (bark postaci jest na wysokości brody).
- Oświetlenie: drugi przebieg renderu (kopie siatek na warstwie 2, shader wypisuje normalne widokowe) daje mapę normalnych, więc latarka i flara dają relief jak na sprite'ach HD (odbicie `flip_h` odwraca X normalnych w shaderze). Kosztuje ok. +50% renderu postaci; `--char3d-lq` go wyłącza.
- Kucanie / skradanie to **przysiad** (biodra 0,48 m niżej, tułów niemal pionowo — wysokość ok. 0,75 stojącej); przesunięcia bioder liczy `_move_global` w przestrzeni szkieletu (osie lokalne kości Mixamo są obrócone, wcześniej przesunięcie ruszało biodra w bok, a nie w dół).
- Poza postojem, biegiem, kucaniem, upadkiem i reanimacją (klipy, patrz wyżej) pozy to proste funkcje sin/cos, nie animacje artysty; dawne modele Tripo (23 kości, bez palców) mają sztywną, otwartą rękawicę — zgięcie palców działa tylko w postaciach MPFB, które mają kości palców.
- Przy zmianie kierunku tułów zwraca się ku kamerze w obie strony (`BODY_YAW` ze znakiem `_cam_c`) — to nie jest anatomiczna postawa praworęcznego strzelca, ale przy anatomicznej postać zwrócona w lewo pokazywała głównie plecak.
- Broń biała ma jedną, uproszczoną pozę zamachu. SPECTER-1 używa swojego modelu `widmo1_01` (cewka, ten sam co w sprite'ach HD); `widmo1_02` (szyny + cewki, olive) to nieużywana alternatywa.
- Wrogowie nadal sprite'y HD — styl postaci gracza (3D) i wrogów trzeba będzie zestroić.
- Od 1.7.156 domyślne: widok 3D zawsze używa modeli, a w widoku 2D decyduje ustawienie **Characters in 2D view** (`Settings.char3d`, domyślnie 3D) lub flaga `--char3d`. Pomiar na słabszym sprzęcie nadal nie jest zrobiony.
