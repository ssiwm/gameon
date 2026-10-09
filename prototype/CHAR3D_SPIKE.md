# Postać 3D w czasie rzeczywistym (`--char3d`, spike → prototyp)

Gracze i bot jako modele 3D (rig Mixamo z Tripo) renderowane do tekstury w grze 2D, zamiast wypiekanych arkuszy.
Ręce naprawdę trzymają broń przy każdym kącie celowania, animacji, broni i wyglądzie (dwukostkowe IK obu rąk).

## Uruchomienie

```bash
godot --path prototype -- --char3d                                                      # gra z postaciami 3D (gracze i bot)
godot --path prototype --script tools/shot_char3d.gd -- --set=poses|weapons|looks|states --part=0 --zoom=9 --out=/tmp/c3d.png
godot --path prototype --script tools/shot_guns3d.gd -- --out=/tmp/guns3d.png          # modele broni z punktami chwytu
godot --path prototype --script tools/bench_char3d.gd -- --n=1,5,10                    # koszt renderu
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
Pokrętła kosztu: `SS` (rozdzielczość renderu), MSAA, `FRAME_WP` (rozmiar ramki).

## Ograniczenia / dalsze kroki

- Oświetlenie: sprite jest oświetlony płasko przez światła 2D (bez mapy normalnych), cieniowanie bryły pochodzi z 3D. Dwa przebiegi (kolor + normalne) byłyby droższe.
- Pozy to proste funkcje sin/cos, nie animacje artysty; brak przejść (blend) między animacjami; dłonie nie obejmują palcami chwytu (tylko orientacja).
- SPECTER-1 (`widmo1`) nie ma własnego modelu — używa LR-7. Broń biała ma jedną, uproszczoną pozę zamachu.
- Wrogowie nadal sprite'y HD — styl postaci gracza (3D) i wrogów trzeba będzie zestroić.
- Flaga dev; włączenie domyślne (ustawienie w menu) po pomiarze na słabszym sprzęcie.
