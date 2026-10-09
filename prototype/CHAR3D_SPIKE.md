# Postać 3D w czasie rzeczywistym (beta; `--char3d` lub ustawienie w menu)

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

## Ograniczenia / dalsze kroki

- Rzut flary i przedmiotów ma pozę (prawa ręka zamachem nad głową), ale tylko lokalnie — rzut jest zdarzeniem lokalnego gracza, inni widzą dopiero rzucony przedmiot.
- Celowanie w dół wysuwa broń ku kamerze (inaczej chowa się za tułowiem); celowanie prosto w górę zasłania głowę ramieniem.
- Oświetlenie: drugi przebieg renderu (kopie siatek na warstwie 2, shader wypisuje normalne widokowe) daje mapę normalnych, więc latarka i flara dają relief jak na sprite'ach HD (odbicie `flip_h` odwraca X normalnych w shaderze). Kosztuje ok. +50% renderu postaci; `--char3d-lq` go wyłącza.
- Kucanie / skradanie to **przysiad** (biodra 0,48 m niżej, tułów niemal pionowo — wysokość ok. 0,75 stojącej); przesunięcia bioder liczy `_move_global` w przestrzeni szkieletu (osie lokalne kości Mixamo są obrócone, wcześniej przesunięcie ruszało biodra w bok, a nie w dół).
- Pozy to proste funkcje sin/cos, nie animacje artysty; brak przejść (blend) między animacjami; dłonie nie obejmują palcami chwytu (tylko orientacja).
- Broń biała ma jedną, uproszczoną pozę zamachu. SPECTER-1 używa swojego modelu `widmo1_01` (cewka, ten sam co w sprite'ach HD); `widmo1_02` (szyny + cewki, olive) to nieużywana alternatywa.
- Wrogowie nadal sprite'y HD — styl postaci gracza (3D) i wrogów trzeba będzie zestroić.
- Włączane ustawieniem **Characters: 3D (BETA)** (`Settings.char3d`, domyślnie wyłączone) lub flagą `--char3d`; domyślnie włączymy po pomiarze na słabszym sprzęcie.
