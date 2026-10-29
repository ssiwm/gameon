# Plan: operatorzy — wiele postaci, własny kryptonim, reset postępu przez gracza

Status: **zaakceptowany 2026-10-29** (decyzje D1–D7 z rekomendacjami). Stan kodu: main 1.7.425.
Nie mylić z [`CHARACTERS_PLAN.md`](CHARACTERS_PLAN.md) — tamten dotyczy wyglądu postaci 3D, ten zapisu gracza.

## Cel

Kilka postaci („operatorów”) na jednym komputerze, każda z własnym kryptonimem, wyglądem i postępem; gracz sam zeruje postęp
(w różnych zakresach) z menu, bez kasowania plików. Dziś jedyną drogą do świeżego startu jest ręczne usunięcie `profile.cfg`
i `progress.cfg` z `%APPDATA%`, a gracze w co-opie widzą się jako „P1–P4”.

## 1. Stan dziś

| Plik | Właściciel w kodzie | Co trzyma | Kto zapisuje |
|------|---------------------|-----------|--------------|
| `user://profile.cfg` | `Profile` (`profile.gd`) | XP, poziom, perki, wygląd, montaż części i zestawy, stan / zużycie / ostrze broni, wprawa, historia broni, bestiariusz, rekordy strzelnicy, `completed` | każdy gracz u siebie |
| `user://progress.cfg` | `Scrap` (`scrap.gd`) | złom, kupione bronie, części, próbki, badania, tokarka, zamówienia, zapas sprzętu, `campaign.cleared` | tylko host |
| `user://settings.cfg` | `Settings`, `Difficulty`, `Voice`, `Actions` | grafika, dźwięk, klawisze, język, mikrofon, towarzysz AI — **ale też rzeczy gracza:** `seen_tips`, `difficulty` (nowy gracz = `FIRST_RUN` EASY), `[shift]` rekord Nocnego Dyżuru, `[range] board` | każdy u siebie |

- Gracze w grze to „P%d” z `display_id` i „BOT” — 22 miejsca w kodzie (etykieta nad głową, karta drużyny, czat, podpowiedź podnoszenia,
  rzut mapy, dziennik sesji, Mimik w `enemy_mimic.gd`). Nazwa ze Steama nie jest używana (`steam_net.gd` tylko ją drukuje).
- Ściana wyników (`RunLog`) jest statyczna i znika po wyjściu z gry.

## 2. Inspiracje

| Gra | Rozwiązanie | Co bierzemy |
|-----|-------------|-------------|
| Elden Ring, Hollow Knight | kilka slotów, karta z poziomem, miejscem i czasem gry | karta operatora z podsumowaniem postępu |
| Valheim, Terraria | postać osobno od świata, przenośna na cudze serwery | dołączając do kogoś, przynosisz postać (tak działa już dziś) |
| Risk of Rain 2 | lokalne profile z nazwą, każdy z własnymi odblokowaniami | wiele postaci na jednym komputerze |
| Warhammer 40K: Darktide | własne imię albo losowe z puli | „Losuj” z tematycznymi kryptonimami |
| Destiny 2 | usunięcie postaci przytrzymaniem przycisku | potwierdzenie przytrzymaniem (mysz i pad) |
| World of Warcraft | usunięcie po wpisaniu słowa | odrzucone — pad nie ma klawiatury |
| Deep Rock Galactic, Phasmophobia | dobrowolny reset poziomu za trwały znak (awans / prestiż) | etap E5, po playtestach |
| Lethal Company | kilka plików zapisu, kasowanie z potwierdzeniem w menu | reset bez grzebania w plikach |

## 3. Decyzje (zaakceptowane)

### D1. Postać = folder z profilem i własną kampanią
`user://characters/<id>/` z `profile.cfg` (dzisiejszy `Profile`), `progress.cfg` (dzisiejszy `Scrap`), `player.cfg` (rzeczy gracza
wyjęte z ustawień, D5) i `character.cfg` (meta). Hostując, grasz kampanię swojej postaci; dołączając — przynosisz XP, perki, wygląd
i montaż, kampania jest hosta (jak dziś). `<id>` to losowy krótki hex, nie kryptonim (zmiana nazwy nie przenosi folderu).
Wariant Valheim (osobny wybór postaci i kampanii) odrzucony na EA — struktura folderów pozwala go dołożyć później.

### D2. Kryptonim
- 2–16 znaków: litery (z polskimi), cyfry, spacja, `-`, `_`; obcięte spacje, bez podwójnych; unikalny wśród własnych postaci (bez
  rozróżniania wielkości liter). „Losuj” z puli w klimacie radia (Sowa, Iskra, Wilk…); na Steamie pierwsza propozycja = nazwa Steam.
- Zmiana nazwy w każdej chwili w menu (bez kosztu).
- Widać go nad głową, w karcie drużyny, w wynikach i wyróżnieniach, w czacie, na rzucie mapy i w podpowiedzi podnoszenia.
  **Mimik** podszywa się pod prawdziwe kryptonimy drużyny zamiast „P2”.
- Sieć: kryptonim replikowany jak `look` (od właściciela, przy zmianie), każdy peer przepuszcza go przez tę samą funkcję czyszczącą
  przed wyświetleniem (kosmetyka — serwer nic z niego nie liczy). Dwa takie same w drużynie → dopisek „(2)”.
- P1–P4 zostają jako kolor slotu. Dziennik sesji dostaje anonimowy identyfikator postaci (`<id>`), nie kryptonim.
- Bez filtra wulgaryzmów w EA.

### D3. Ekran OPERATORZY
- Do 6 kart: kryptonim, miniatura wyglądu, poziom, postęp kampanii (np. „1.3 GNIAZDO”, trofea), czas gry, ostatnia gra.
  Akcje: Graj, Nowa, Zmień nazwę, Resetuj…, Usuń.
- W menu głównym ostatnia postać jest wybrana automatycznie — „HOST GAME” dalej jednym kliknięciem; panel „Operator LV” dostaje
  kryptonim i [ZMIEŃ].
- Pierwsze uruchomienie (i postać z migracji): krótki kreator — kryptonim i wygląd — potem menu.
- Całość padem; nazwę z pada daje „Losuj” (Steam Deck ma klawiaturę ekranową).

### D4. Reset postępu
1. **Nowa kampania** — zeruje `progress.cfg` (złom, bronie, części, próbki, ukończone misje, zapas); zostaje XP, perki, wygląd, wprawa.
2. **Reset postaci** — wszystko poza kryptonimem i wyglądem.
3. **Usuń postać.**

Zabezpieczenia: okno „stracisz / zostaje” z liczbami z zapisu, potwierdzenie przytrzymaniem (2 s reset, 3 s usunięcie), kopia przed
każdą operacją i „Cofnij” dla ostatniej, dostępne tylko w menu głównym (nie w lobby ani w trakcie sesji).
**Awans / prestiż** po L6 (PROGRESSION_PLAN §2.3) — etap E5 po playtestach; pole `promotions` w `character.cfg` od E1.

### D5. Co przechodzi z ustawień do postaci
`seen_tips`, `difficulty` (nowa postać startuje na `FIRST_RUN`), `[shift]` rekord Nocnego Dyżuru, `[range] board`.
Grafika, dźwięk, klawisze, język, mikrofon i towarzysz AI zostają wspólne w `settings.cfg`.

### D6. Migracja
Pierwsze uruchomienie nowej wersji: `profile.cfg` i `progress.cfg` przenoszą się do postaci nr 1, klucze z D5 — z `settings.cfg` do jej
`player.cfg`; oryginały trafiają do `user://backup_characters_migration/`. Postać z migracji ma `needs_name = true` (kreator z E3 poprosi
o kryptonim). Świeża instalacja też dostaje postać nr 1 z `needs_name`. Testy headless nie dotykają zapisu (jak dziś `persist`).

### D7. Etapy

| Etap | Zakres | Test |
|------|--------|------|
| **E1** | autoload `Characters` (przed `Settings`), foldery, `index.cfg`, `character.cfg`, migracja, D5, ścieżki `Profile` / `Scrap` / `Settings` / `Difficulty` z aktywnej postaci, walidacja kryptonimu (funkcja, bez UI), anonimowy id w dzienniku | `--charactertest` |
| **E2** | kryptonim w grze i w sieci (zamiast P1–P4 w UI, Mimik, „(2)”), funkcja czyszcząca na każdym peerze | `test_net_session.sh` + `--charactertest` |
| **E3** | ekran OPERATORZY, kreator (kryptonim + wygląd), zmiana nazwy, przełączanie postaci w menu | `--uifittest`, zrzut `--shotchars` |
| **E4** | reset (kampania / postać) i usuwanie z kopią i „Cofnij” | `--charactertest` |
| **E5** | awans / prestiż — po playtestach | — |

Każdy etap: PR do `main`, podbicie `config/version`, wiersz w `CHANGELOG.md`, opis w README/GDD tam, gdzie mechanika jest opisana.

## 4. E1 — szczegóły techniczne

```
user://characters/index.cfg            [characters] order = [<id>…], active = <id>
user://characters/<id>/character.cfg   [character] id, name, needs_name, created, last_played, play_time, promotions
user://characters/<id>/profile.cfg     Profile.save_to / load_from
user://characters/<id>/progress.cfg    Scrap.save_progress / load_progress
user://characters/<id>/player.cfg      [game] seen_tips, difficulty; [shift]; [range] board
```

- `characters.gd` (autoload `Characters`, pierwszy na liście): `ensure_ready()`, `migrate_legacy(src_dir)`, `create(name)`, `list()`,
  `file(name)`, `rename(id, name)`, `validate_name(name)`, `clean_name(name)`. Katalog bazowy podmienialny (`use_root`), żeby test
  działał na kopii w `user://`, a nie na zapisie gracza. W headless bez zapisu (`persist`).
- `Profile`, `Scrap`, `Settings`, `Difficulty` biorą ścieżki z `Characters.file(...)` zamiast stałych `SAVE_PATH`.
- Czas gry: `play_time` rośnie o czas uruchomienia przy wyjściu z gry; `last_played` przy starcie.
- Przełączanie postaci w trakcie działania gry (przeładowanie `Profile` / `Scrap` / ustawień gracza) — E3.

## 5. Ryzyka

- **Playtest w toku** — zmiana formatu zapisu nie może zgubić postępu testerów: migracja pierwsza, z kopią i testem na starych plikach.
- **Moment** — nowa funkcja w trakcie zbierania opinii; E1–E3 najlepiej w jednej paczce dla testerów, nie po kawałku.
- **Steam Cloud** — folder `characters/` jest gotowy pod Auto-Cloud (`prototype/STEAM_RELEASE.md`), ale konfiguracja to osobny krok.
