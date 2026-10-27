# Rozgrywka bez bota — plan

Status: **plan z 2026-10-27 (main 1.7.399, 632efdf); N1–N8 wdrożone w 1.7.400** (gałąź `docs/nobot-plan`). Decyzje D1–D4 podjęte 2026-10-27 (§3): D1a, D2a, D3a, D4 — tylko drezyna.

## 1. Cel

Host może zagrać kampanię, Nocny Dyżur i kryjówkę **bez AI towarzysza**: sam (czysty horror solo) albo w dwie osoby bez bota.
Domyślnie nic się nie zmienia — bot zostaje (GDD §16.3: towarzysz ratuje graczy solo), a brak bota to świadomy wybór hosta.

Po co: część graczy chce grać sama, bez „opiekuna”; na playteście warto porównać solo z botem i bez (dziennik ma już `bots`
w `mission_start`), a my sami możemy grać mapy bez bota, który zabiera część uwagi wrogów i Stalkera.

## 2. Stan obecny (z kodu)

| Obszar | Fakt | Gdzie |
|---|---|---|
| Liczba botów | 1 bot przy 1–2 ludziach, 0 przy 3+; liczy serwer przy każdym dołączeniu, wyjściu i upadku | `main._bot_target_count`, `_reconcile_bots` |
| Wipe | „wszyscy (ludzie i boty) leżą” → restart misji po 3 s, łup misji przepada; Nocny Dyżur — koniec serii | `main._all_down`, `_physics_process` |
| Sam bez bota | upadek = od razu wipe: nikt nie podniesie, a wykrwawienie (powrót na start z 1 HP) nigdy nie nastąpi | wynika z powyższego |
| Podnoszenie | tylko kolega (człowiek lub bot) trzymając E; sam — tylko perk „Second chance” (raz na misję) | `player._handle_revive`, `perks.gd` |
| Drezyna (1.2) | moc = ludzie + 0,5 × boty (gdy jest człowiek) — sam bez bota jedzie o 1/3 wolniej, a Stalker dogania | `handcar.gd` (`power`) |
| Cele wrogów | bot jest celem zastępczym (waga 1,3): bez bota cała agresja idzie w ludzi | `enemy._target_weight`, `TARGET_BOT_W` |
| Stalker | w dziennikach 156 z 191 trafionych zamachów poszło w boty (przed 1.7.396) — bez bota cały w ludziach | log sesji |
| Mimik | „udaje kolegę z drużyny”; sam bez drużyny każdy „kolega” jest od razu podejrzany | `enemy_mimic.gd` |
| Bossy, Dyrektor | HP bossów i skład grup Dyrektora liczą tylko ludzi — bez zmian | `boss_base.scaled_hp`, `director.gd` |
| Podpowiedzi | „downed”: „kolega może cię podnieść” — sam bez bota nieprawda | `hints.gd` |
| Kryjówka, gotowość | liczy tylko ludzi — bez zmian | `main._hub_humans` |
| Testy | `--bottest`, unik bota w `--stalkertest`, `--wipetest` (wypisuje bota) zakładają bota | `scripts/*_test.gd`, `main.gd` |

## 3. Decyzje (podjęte 2026-10-27 — wybrane warianty oznaczone ✅)

**D1. Co znaczy upadek, gdy nie ma kto podnieść (sam bez bota)?**
- ✅ (a) **Wykrwawienie zamiast wipe'u:** wipe tylko wtedy, gdy leżą wszyscy *i* nikt nie wstanie (jest drugi człowiek albo bot,
  który może podnieść). Sam bez bota: po upadku biegnie zegar wykrwawienia, potem powrót na start z 1 HP (dzisiejsza kara „dystansem
  i czasem” z GDD §4), łup zostaje. Druga śmierć w tej samej próbie = wipe, żeby porażka nadal była możliwa.
- (b) Wipe od razu (jak dziś bez zmian) — najostrzejsze, pasuje do „hardcore”, ale nowy gracz traci misję po jednym błędzie.
- (c) Raz na misję wstaje sam po zegarze (jak „Second chance” dla każdego), drugi upadek = wipe.

**D2. Kiedy host wybiera?** ✅ (a) w lobby przed startem i w kryjówce (w misji zmiana składu zmieniałaby trudność w pół walki);
(b) także w menu pauzy w trakcie misji.

**D3. Zakres przełącznika:** ✅ (a) ON / OFF; (b) ON / OFF / FILL — „dopełnij do 4” (GDD §16.3 mówi o wypełnianiu pustych
slotów, dziś bot jest najwyżej jeden). FILL to osobna, większa praca (kilku botów naraz, `_behind_side` dla wielu) — po playteście.

**D4. Strojenie solo bez bota przed playtestem?** Drezyna (moc 1,0 zamiast 1,5) i Mimik. ✅ Wybrane: drezyna — minimalna moc 1,5 dla
jednego człowieka bez bota (bez tego tunel 1.2 jest dużo trudniejszy niż z botem); Mimik — bez zmian, ale pomiar w dzienniku
(czy samotny gracz daje się nabrać). Reszta (agresja wrogów, Stalker) — bez zmian, mierzymy.

## 4. Plan wdrożenia (po decyzjach)

| Etap | Zakres | Gdzie | Rozmiar |
|---|---|---|---|
| N1 | Ustawienie hosta `ai_companion` (ON/OFF) w lobby, sekcja OPTIONS, obok trudności; zapis w `settings.cfg`; klient widzi wartość hosta jak trudność (`_sync_difficulty` → wspólna synchronizacja ustawień sesji) i ma przycisk zablokowany. Dev: `--nobot`. Tekst EN + wiersz `ui.csv`. | `lobby.gd`, `settings.gd`, `main.gd` | mały |
| N2 | `_bot_target_count` zwraca 0 przy OFF; zmiana w kryjówce (D2a) od razu wywołuje `_reconcile_bots` (bot znika albo się pojawia). | `main.gd` | mały |
| N3 | Upadek bez nikogo, kto podniesie — wg D1. Dla (a): `_all_down` → „nikt nie może wstać” (leżą wszyscy, a wśród stojących — nikt); licznik upadków solo w próbie; druga śmierć = wipe. Nocny Dyżur: ta sama reguła. | `main.gd`, `player.gd` | średni |
| N4 | Podpowiedź „downed” w wersji solo („Nikt cię nie podniesie — wykrwawisz się i wrócisz na start”, D1a) i karta wyniku pokazuje „bez bota”. | `hints.gd`, `hud.gd`, `ui.csv` | mały |
| N5 | Drezyna wg D4: minimalna moc dla samotnego człowieka. | `handcar.gd` | mały |
| N6 | Dziennik: `mission_start.ai_companion` (on/off); `session_progress.py` dzieli wyniki map na „z botem / bez bota”. | `mission.gd`, `tools/session_progress.py` | mały |
| N7 | Testy: nowy `--nobottest` (host z `--nobot`: brak bota solo i przy 2 ludziach; upadek solo → wykrwawienie → powrót na start; druga śmierć → wipe; przełącznik w kryjówce dodaje/usuwa bota); `test_net_session.sh`: klient widzi ustawienie hosta. Istniejące testy bez zmian (domyślnie ON). | `scripts/nobot_test.gd`, `main.gd`, CI | średni |
| N8 | Dokumenty: GDD §16.3 (towarzysz domyślny, wyłączany przez hosta), §4 (reguła upadku solo), README (lobby, flaga), PLAYTEST.md (wariant sesji solo bez bota), CHANGELOG, wersja. | dokumenty | mały |

Kolejność: N1–N2 i N6 (sam przełącznik i pomiar) mogą wejść jako pierwszy PR, ale bez N3 gra solo bez bota kończy misję przy każdym
upadku — dlatego proponuję jeden PR N1–N8 albo dwa: (N1, N2, N3, N4, N6, N7) i (N5, N8).

## 5. Ryzyka

- Bez bota trudność solo rośnie skokowo (Stalker, agresja wrogów, drezyna). Nie stroimy przed danymi — dziennik rozdziela wyniki (N6).
- `_all_down` decyduje o wipe'ach w każdym trybie — zmiana w N3 musi zostawić dzisiejsze zachowanie, gdy jest bot albo drugi człowiek
  (pilnuje `--wipetest` i nowy test).
- Przełącznik w trakcie misji (D2b) dodawałby/usuwał bota w walce — dlatego polecana jest tylko kryjówka i lobby.
- GDD §16.3 stawia towarzysza jako warunek EA; wyłączenie jest opcją hosta, nie zmianą domyślnego zachowania.
