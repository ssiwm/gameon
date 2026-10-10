# Spike: misja 1.1 w prawdziwym 3D (Bramka B)

Status: **spike wykonany 2026-10-10** — osobna scena, bez ruszania gry. **Następny krok (rekomendacja §5) wdrożony jako opcja graficzna „3D view” (`view3d.gd`, GDD 1.7.128).** Cel Bramki B z `ATMOSPHERE_PLAN.md`: sprawdzić, czy „prawdziwe 3D”
(perspektywa, światła i cienie 3D, mgła głębi, modele postaci bez sprite'ów) daje na tyle lepszy obraz, żeby uzasadnić koszt, i **ile
naprawdę kosztuje port**. To nie jest port rozgrywki: nie ma wrogów, celu misji, sieci, dźwięku ani HUD-u gry.

## 1. Uruchomienie

```bash
godot --path prototype res://scenes/spike_mission3d.tscn
```

Sterowanie: **A/D** chód, **SPACJA** skok, **mysz** celowanie, **LPM** strzał (smuga i błysk), **L** latarka, **[ ]** zmiana FOV.
Flagi (po `--`): `--shot3d=PLIK.png [--at=KOLUMNA] [--delay=S] [--fov=°] [--aimx=-1] [--anim=run]` (zrzut i wyjście), `--bench=S` (czas klatki).

Zrzuty w repo: `concepts/spike3d_exit_flare.jpg`, `concepts/spike3d_campfire.jpg`, `concepts/spike3d_mirrored.jpg`.

## 2. Co zbudowano

| Element | Jak | Plik |
|---|---|---|
| Geometria poziomu | z tej samej mapy ASCII `maps/z1_m1.gd`: odsłonięte kafle `#`, `C`, `M`, `m`, `O`, `~` jako `MultiMesh` skrzynek, trawa, tło ścian `b`, pnie `w`, kładki `-` / `=` | `scripts/spike3d/mission3d.gd` |
| Materiały | `StandardMaterial3D` z trójpłaszczyznowym szumem i mapą normalnych (bez dedykowanych tekstur) | j.w. |
| Las w głębi | ok. 300 świerków z `MultiMesh` (pień + trzy stożki) w płaszczyznach z = −3,5 … −46 m; paralaksa wynika z perspektywy | j.w. |
| Postać | **ten sam model, poza i broń co w grze** (`char3d.gd`): model i broń są wyjęte ze świata podglądu do sceny, a poza liczy dalej `Char3D.update()`; światło daje scena | j.w. |
| Światła | księżyc (kierunkowe, cienie), latarka (reflektor z cieniami, z piersi wzdłuż celowania), ogniska `F` (omni, migotanie), flara wyjścia `E`/`e` (omni, zielona), błysk lufy | j.w. |
| Środowisko | niebo proceduralne, mgła głębi, glow, tonemapping filmic, korekta kontrastu | j.w. |
| Fizyka | ruch jak w `player.gd` (95 px/s, skok −275, grawitacja 900) na siatce kafli z podkrokami 8 ms; kładki jednokierunkowe | j.w. |
| Kamera | perspektywiczna, FOV 38° (zmienny), 17 m od płaszczyzny gry, podąża za graczem | j.w. |

Skala: 1 piksel świata = 0,0818 m (postać 22 px = 1,8 m), kafel 16 px ≈ 1,31 m. Płaszczyzna gry to z = 0; bryły wysunięte o 1,1 m przed nią
i 2,4 m w głąb.

## 3. Obserwacje

**Co wychodzi lepiej niż w 2D**
- **Cienie i światło są prawdziwe**: cień postaci pada na ziemię od księżyca, od ogniska i od latarki bez żadnych obejść (okludery 2D, maski normalnych).
  Ognisko oświetla postać od przodu, flara od zielonej strony — z jednego, spójnego modelu.
- **Głębia za darmo**: las, kładki i skały mają paralaksę z perspektywy, mgła głębi zaciera dalsze plany (zamiast ręcznego `FOREST` i gradientów).
- **Brak „plakatu”**: model postaci ma objętość w świetle, a nie renderowany sprite z mapą normalnych — nie ma sprite'ów o ograniczonej rozdzielczości
  przy zoomie i 4K.
- **Odbicia zwrotne od istniejącego potoku działają**: ta sama poza IK (celowanie, broń w dwóch dłoniach), lustro przez skalę X = −1 działa bez problemów
  z odwróconymi ściankami.

**Co jest gorsze albo trzeba dopracować**
- **Wygląd „pudełek”**: kafle jako skrzynki z szumem są oczywiście tańsze niż ręczne tekstury HD terenu (`terrain_hd.png`); do porównania z grą 2D
  potrzebna jest warstwa materiałów (zob. §5).
- **Kształt sylwetki w ciemności**: scena jest bardzo ciemna, więc czytelność zależy od świateł; w 2D ten sam problem rozwiązują „rimy” i podbicia (`TINTS`).
- **Drzewa z brył** wyglądają jak low-poly, a nie jak malowane sylwetki 2D; styl trzeba wybrać świadomie.
- **Koszt wizualny kadru 3/4**: perspektywa pokazuje wnętrze pudełek (głębokość 3,5 m), a nie płaski przekrój — gracz „widzi” boki skał.

**Wydajność:** 60 fps utrzymane przy 4K (RTX 3080, tryb zgodności GL, vsync) z ok. 2400 instancjami `MultiMesh` (kafle, trawa, drzewa) i 12 światłami, z czego 7 z cieniami (księżyc, latarka, 3 ogniska, 2 flary); piki do
27 ms tylko przy kompilacji shaderów. Zapas GPU nie jest zmierzony (vsync trzymał 16,7 ms) — potrzebny pomiar w trybie bez vsync na słabszym GPU.

## 4. Czego spike NIE sprawdza (i koszt portu)

| Obszar | Stan | Szacunek pełnego portu |
|---|---|---|
| Wrogowie (9 typów + 2 bossy + gniazdo) | brak — gra ma tylko arkusze sprite'ów HD (11 plików `art/sprites/*_hd.png`), bez modeli 3D | **duże**: albo billboardy (łatwo, ale to wciąż 2D), albo modele 3D + animacje + wizualizacja ataków (kilka tygodni) |
| Pociski, efekty, cząsteczki | w 2D (CPUParticles2D, `Vfx`) | średnie: przepisanie `Vfx` na 3D (CPUParticles3D / mesh) — 1–2 tyg. |
| Pogoda (deszcz, mgła ekranowa, błyskawice) | w 2D (`weather_fx.gd`) | średnie: deszcz jako cząsteczki 3D, mgła głębi środowiska zastępuje welon |
| Dźwięk pozycyjny | 2D (`AudioStreamPlayer2D`) | małe: przepięcie pozycji na 3D |
| Logika, AI, nawigacja, sieć | w 2D, tak ma zostać | **0, jeśli symulacja zostaje w 2D** (zob. §6) |
| HUD i menu | `CanvasLayer` — działa bez zmian nad 3D | ~0 |
| Mapy i poziomy | ASCII + kinds | geometria z mapy (zrobione), ale materiały i dekoracje (rośliny, kamienie, rekwizyty HD) trzeba przenieść: 2–3 tyg. |

## 5. Rekomendacja

1. **Nie przepisywać symulacji.** Architektura, która wychodzi ze spike'a: zostawić grę jako symulację 2D (fizyka kafli, AI, sieć, rozstrzygnięcia serwera),
   a 3D zrobić **widokiem**: `View3D` tworzy scenę 3D z mapy i co klatkę przenosi pozycje encji (gracze, wrogowie, pociski, światła) na proxy 3D.
   To jest dokładnie to, co robi spike dla jednego gracza; reszta to rozszerzenie liczby proxy.
2. **Zacząć od widoku jako opcji graficznej** (`--view3d` / ustawienie „Graphics: 3D view”), nie jako zamiennika 2D — kosztem jest wizualizacja wrogów, więc
   na początku wrogowie jako billboardy HD (te same arkusze) w scenie 3D.
3. **Decyzja** (Bramka B): jeśli powyższy obraz (cienie, głębia, objętość) jest tym, czego chcesz — kolejny krok to prototyp `View3D` w głównej scenie
   (1 tydzień: proxy graczy, billboardy wrogów, światła z `Lights`, materiały z `terrain_hd`); jeśli nie — zostajemy w 2D i domykamy atmosferę F4/F6
   (`ATMOSPHERE_PLAN.md`), a spike zostaje jako dokumentacja kosztu.

## 6. Ryzyka i nieznane

- **Zgodność trybu renderowania**: spike działa w `gl_compatibility` (jak gra). Limity świateł na obiekt i brak części efektów (SSAO, SSR, volumetric fog)
  oznaczają, że „AAA” wygląd 3D wymagałby przejścia na Forward+/Mobile — to osobna decyzja o platformach.
- **Spójność z potokiem postaci**: spike wyjmuje model z `Char3D` i omija jego SubViewport; docelowo trzeba wydzielić w `char3d.gd` czyste „nadawanie pozy”
  (bez sprite'a i kamer), żeby nie trzymać dwóch ścieżek.
- **Grafika klasyczna i tryb `--classic`** w widoku 3D nie mają sensu; widok 3D byłby tylko dla grafiki HD.
- **Cel poboczny misji, finał (zawał), kopalnia** — nie sprawdzone: wymagają dynamicznych zmian geometrii (zawał rampy) w 3D.
