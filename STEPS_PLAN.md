# STEPS_PLAN — stopnie z natury i z historii miejsca

Stan na 2026-11-21. Źródło: dwie rundy propozycji (wizualizacje w artefaktach: runda 1 „konstrukcje + podciąganie”,
runda 2 „natura i lore”). Gracz wybrał warianty polecane.

## Problem

Pomosty `-` / `=` pod gołym niebem to deski na cienkich nogach co ≤ 4 kafle (`Level3D.deck_supports`) albo deski bez oparcia.
Nocą w 1.1 wyglądają jak lewitujące stoły. Nie wynikają z miejsca: w lesie, przy brodzie i na polanie nikt nie stawiał rusztowań.

## Zasady (fizyka widoku 3D)

- Mapa, kolizja, nawigacja i skok (szczyt 3,44 m) **bez zmian**. Zmienia się tylko obraz.
- Pod pomostem gracz chodzi w pasie gry (z ≈ 0). W pasie z ∈ [−0,5; 0,5] od podłoża do **1,85 m** nad nim nie ma niczego
  (`Step3D.CLEAR`, sprawdza test). Nośność tylko z tyłu (z < −0,9), łukiem nad pasem albo wspornikiem (konar, płyta skalna).
- Pełne bryły pod pomostem (głaz, sąg, skrzynie) odpadają.
- Wierzch, po którym się chodzi, leży na wysokości pokładu (±3 cm) na całej długości ciągu.
- Element przed pasem gry (z > 0,9) najwyżej do 1 m (ścięty czubek kłody); bez zasłaniania postaci.

## Dane

Stała `STEPS` w danych mapy (czyta `level.gd`, jak `NICHES`):

```
{"kind": "bank" | "windfall" | "tor" | "boughs", "decks": [[r, c0], …], "posts": [c, …], "cache": true, "trunks": [[c, r_foot], …]}
```

- `decks` — początki ciągów pomostu (wiersz, pierwsza kolumna); ciąg musi istnieć w mapie.
- `posts` — kolumny słupów `w`, które znikają (skarpa zastępuje nogi pomostu).
- `boughs`: słupy `w` z ciągiem ≥ 6 kafli w zasięgu 3,5 kafla stają się sosnami (`_trunk_add`); `trunks` dodaje sosnę tam, gdzie słupa nie ma.

Pomosty z wpisu nie mają modelu desek ani nóg (`Level3D.step_cells`).

## Rodzaje

| Rodzaj | Gdzie | Opis |
|---|---|---|
| `bank` — podmyta skarpa | 1.1 bród (Wołek śpi na górze) | Bryła ziemi za pasem gry, płaski wierzch z darnią, nawis darni na korzeniach do z ≈ +0,7. Korzenie zwisają nie niżej niż 2,15 m nad ścieżką w pasie gry. |
| `windfall` — wykrot | 1.1 bród, schodek nad błotem | Dwupienny świerk wyrwany z talerzem korzeniowym (z ≈ −3,5), pnie leżą w poprzek ścieżki na głazie za pasem gry (z ≈ −1,5). Czubki odpiłowane przez patrol (z ≈ +0,85), jasne przekroje. |
| `tor` — ostaniec granitowy | 1.1 polana, półki przy przyczółkach mostu | Płyty granitu jak materace wystają nad ścieżką (z −1,05 … +0,8), masa skały za pasem gry. Opcja `cache`: nisza ze skrytką pod nawisem na szczycie, lina patrolu na haku i czerwona strzałka. |
| `boughs` — konary sosen | 1.1 obóz pod zerwanym mostem | Dwie stare sosny w miejscu słupów `w`, poziome konary (⌀ 0,68 → 0,26 m) niosą pomosty. Most zostaje mostem; belka przybita do pnia trzyma koniec przęsła. |

## Etapy

- **S0** dane `STEPS`, odczyt w `level.gd`, `Level3D.set_steps` (bez desek, nóg i ukrytych słupów), test `tools/test_steps.gd`: wpisy istnieją,
  wolny pas pod pomostem, wierzch na wysokości pokładu na całym ciągu.
- **S1** rodzaje `bank`, `windfall`, `tor`, `boughs` w `scripts/step3d.gd`; 1.1 (bród, polana, obóz, półki przyczółków); zrzuty przed i po.
- **Stan 2026-11-21 (1.7.640):** S0 i S1 zrobione. Ustalenia z zrzutów (`--view3dlit`, `--shottorch`, z pomostu `--shotplat --shotrow=N`):
  - ostaniec z płyt o równych przekrojach i rzędów bloków co 1,2–2,8 m czytał się jak mur z worków; teraz płyty to zaokrąglone bloki (`_rbox`
    z płaskim wierzchem) o grubości 0,42–0,74 m i nierównym podziale, masa z poduch 2,4–4,6 × 0,9–1,8 m o zaokrągleniu 0,4–0,5 krótszego boku,
    garb za niższym stopniem do wysokości następnego, głazy u stóp, na szczycie bez skrytki luźne głazy (gdy nad pomostem nie ma mostu);
  - granit pod niebem: mech na wierzchach, ciemniejsze spody, odcień bloku z koloru wierzchołków (`OUTDOOR_ROCK`); porosty na licach z szumu
    wartości dawały kwadratowe plamy („moro”) — odrzucone;
  - korona sosny z konarami na wysokości pomostów i korona sosny pierwszego planu (dół 6,5–8 m nad gruntem, pomosty obozu ok. 12 m) zasłaniały
    gracza na pomoście: korona sosen z konarami 5,5 m nad najwyższym pomostem (`BOUGH_CROWN`), las `FRONT` 1.1 z pominięciem kol. 98–106.
- **S2** 1.3: plac — ciepłociąg na wspornikach Γ (rura ⌀ 0,6 m, ramię na ok. 1,85 m, pętla rury w głębi przy zmianie poziomu);
  przy budynkach — narośl Żyły z drzwi (łuki co 1,3 m nad ścieżką, mata żył na wierzchu).
- **S3** podciąganie na przedniej krawędzi pokładu (`char3d`): model przed pokładem z ≈ +0,8, IK dłoni na krawędzi, faza wypchnięcia; ścieżka symulacji bez zmian.
- **S4** 1.2 — osobna runda propozycji (maszt z platformą i koszem drabiny, stacja słupowa).

Drabiny tylko w obrazie (decyzja z rundy 1). Szyby kopalni 1.1 (c40–43, 111–114, 193–197) zostają bez zmian.
