# Playtest i publikacja dema — lista kontrolna

Cel playtestu (GDD §16.0 pkt 2): **kiedy się nudziłeś, a kiedy się bałeś**. Wyniki trafiają do tabeli w GDD §23.3 —
decydują o priorytetach przed jakąkolwiek nową zawartością.

## 1. Przed sesją (10 min)

- [ ] Eksport z Godota (**nie z edytora**): Project → Export → Windows Desktop, „Export Project". Sprawdź na komputerze,
      na którym nie ma Godota ani repozytorium.
- [ ] Uruchom eksport: menu → host → cała misja → ekran wyniku → [ENTER] → druga misja. Zero błędów w konsoli.
- [ ] Włącz nagrywanie ekranu **z dźwiękiem i mikrofonem** (OBS). Reakcje graczy są ważniejsze od ich opinii.
- [ ] Zapisz wersję gry (changelog GDD §22) i poziom trudności (domyślnie EASY — dla nowych graczy zostaw).
- [ ] Gracze mają słuchawki. Bez nich cały filar „dźwięk jako groza" przepada.

## 2. Zasady sesji

- **Nie tłumacz gry.** Gracz dostaje tylko: „Wyjdźcie z lasu żywi." Jeśli czegoś nie rozumie — to jest wynik testu.
- Nie podpowiadaj, nie komentuj, nie broń decyzji projektowych. Notuj.
- Pierwsza próba: 1 gracz solo z botem (większość graczy dema zagra solo). Druga: 2–4 osoby w koopie.
- Po sesji 5 pytań, bez sugerowania odpowiedzi: (1) co było najstraszniejsze? (2) kiedy się nudziłeś? (3) co Cię
  zdziwiło / nie zrozumiałeś? (4) dlaczego zginąłeś? (5) zagrałbyś jeszcze raz — i dlaczego tak/nie?

## 3. Co obserwować (znacznik czasu przy każdej uwadze)

| Obserwacja | Pytanie diagnostyczne |
|---|---|
| Czy gracz zauważył miernik hałasu przed pierwszym „SOMETHING IS LISTENING"? | HUD / podpowiedzi czytelne? |
| Czy użył Q (wabik), F (flara), G (krzyk), Shift (skradanie) bez podpowiedzi z zewnątrz? | Mechaniki odkrywalne? |
| Czy wiedział, co jest celem (gniazda, boss, ekstrakcja)? | Karta celu wystarczy? |
| Momenty bezruchu / szukania drogi > 20 s | Mapa i znaczniki |
| Zgony: gdzie, od czego, czy gracz rozumiał dlaczego | Uczciwość trudności |
| Reakcje na głos / śmiech / krzyk do mikrofonu | Czy VAD działa u kogoś innego niż my? |
| Ile powtórek bez znudzenia | Powtarzalność mapy (GDD §16.0) |

## 4. Sieć (osobny test, 2 komputery w różnych sieciach)

- [ ] Steam P2P: host + klient przez internet (własny App ID — `steam_appid.txt`; 480 działa tylko do testów).
- [ ] Opóźnienie 50–150 ms (np. klient na VPN / hotspot): strzały trafiają, wrogowie nie „skaczą".
- [ ] Dołączenie w środku misji (znane ograniczenie GDD §19 poz. 23 — sprawdź, jak bardzo przeszkadza).
- [ ] Host wychodzi w trakcie gry: klient dostaje czytelny komunikat, nie zawieszenie.
- [ ] Rozłączenie klienta i ponowne dołączenie.

## 5. Wydajność i komfort

- [ ] Stabilne 60 fps na najsłabszym dostępnym komputerze (walka z wieloma wrogami + boss + flary).
- [ ] 1080p i 1440p: HUD czytelny? (menu pauzy → HUD SIZE: LARGE, jeśli za mały).
- [ ] Menu pauzy (Esc / P): ustawienia zapisują się po restarcie; Esc w lobby nic nie robi; w solo gra się zatrzymuje,
      w koopie idzie dalej.
- [ ] Mikrofon: czułość LOW/MED/HIGH u kogoś z innym mikrofonem; „NO MIC" gdy brak urządzenia.
- [ ] Wyłączone podpowiedzi i SCREEN SHAKE: OFF działają.

## 6. Strona Steam (potrzebna do publikacji dema)

- [ ] Opłata Steam Direct (100 USD, zwracana po 1000 USD przychodu) + weryfikacja podatkowa / bankowa.
- [ ] Trailer 15–30 s: pierwsze sekundy = cisza, hałas, krzyk. Zrzuty ekranu min. 5. Grafiki kapsuły w wymaganych rozmiarach.
- [ ] Opis zawiera zdanie o mikrofonie: „Opcjonalny krzyk do mikrofonu — dźwięk przetwarzany lokalnie, nigdy nie nagrywany
      ani wysyłany."
- [ ] Ocena wiekowa (horror, przemoc). Tagi. Strona „Coming Soon" publiczna ≥ 2 tygodnie przed premierą dema.
- [ ] Po uzyskaniu adresu strony: wpisz go w `scripts/settings.gd` → `STORE_URL` (ekran końcowy dema pokaże [O] Open the Steam page).
- [ ] Nowy App ID w `steam_appid.txt`; `Settings.DEMO := false` w pełnej wersji (ukrywa zachętę do listy życzeń).

## 7. Wynik

Wypełnij tabelę w GDD §23.3 (data, osoby, moment nudy, moment strachu, wniosek → zmiana) i dopiero wtedy zaplanuj kolejne prace.
