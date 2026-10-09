# Spike: postać 3D w czasie rzeczywistym (`--char3d`)

Test, czy gracze mogą być modelami 3D (rig Mixamo z Tripo) renderowanymi do tekstury w grze 2D, zamiast wypiekanych arkuszy.
Cel: ręce naprawdę trzymają broń przy każdym kącie celowania, animacji i broni (dwukostkowe IK obu rąk).

## Uruchomienie

```bash
godot --path prototype -- --char3d                                   # gra z postaciami 3D (gracze i bot)
godot --path prototype --script tools/shot_char3d.gd -- --part=0 --zoom=13 --out=/tmp/c3d.png   # poza × kąty celowania
godot --path prototype --script tools/bench_char3d.gd -- --n=1,5,10  # koszt renderu
```

## Jak działa

- `scripts/char3d.gd` — `SubViewport` (176×176 px, 4 px na piksel świata) z kamerą ortogonalną z boku; `Sprite2D` pokazuje wynik,
  shader dodaje obrys, światła 2D gry oświetlają sprite. Odbicie (patrzenie w lewo) = `flip_h`.
- Pozy w kodzie: nogi i ręce przez własne dwukostkowe IK (idle, bieg, skok, spadanie, kucanie, marsz w kucaniu, leżenie), tułów zwraca się ku kamerze
  i pochyla za celem. Broń 3D obraca się wokół barku; prawa dłoń trzyma chwyt pistoletowy, lewa łoże (`art/char3d/gun_*.json`).
  Gdy łoże jest za daleko, broń jest wsuwana ku ciału.
- Wszystko czyta zreplikowany stan gracza (`aim_dir`, kierunek, animacja z prędkości/podłoża); serwer i sieć bez zmian.
- `tools/prep_char3d.py` / `prep_gun3d.py` (Blender) robią lekkie GLB: 6 tys. ścian postaci, 2,5 tys. broni, sama tekstura koloru (0,5 MB zamiast 13 MB).

## Pomiar (RTX 3080, 4 px/px świata, MSAA 2×)

| postaci | GPU | CPU render | `update()` (pozy+IK) |
|---|---|---|---|
| 1 | 0,3 ms | 0,6 ms | 0,16 ms |
| 5 | 1,3 ms | 1,3 ms | 0,44 ms |
| 10 | 3,0 ms | 1,9 ms | 0,75 ms |
| 20 | 3,7 ms | 3,2 ms | 1,4 ms |

Typowa sesja (4 graczy + bot) ≈ 2,5 ms z 16,7 ms. Do sprawdzenia na słabszym GPU (zintegrowane).

## Ograniczenia spike'a (do zrobienia, jeśli idziemy dalej)

- Jedna postać (`male_scav`) i jedna broń (`gun_m83`) dla wszystkich; reszta 11 broni, wygląd z warsztatu (Look) i bot-kobieta nie podpięte.
- Broń biała (maczeta, kilof), przeładowanie, dobycie i cios nie mają dedykowanych póz rąk (przeładowanie = ta sama poza).
- Oświetlenie: sprite jest oświetlony płasko przez światła 2D (bez mapy normalnych), cieniowanie bryły pochodzi z 3D. Dwa przebiegi (kolor + normalne) byłyby droższe.
- Pozy to proste funkcje sin/cos, nie animacje artysty; brak przejść (blend) między animacjami.
- Wrogowie nadal sprite'y HD — styl postaci gracza (3D) i wrogów trzeba będzie zestroić.
