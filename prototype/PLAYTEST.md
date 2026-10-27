# Playtest i publikacja dema — lista kontrolna

Cel playtestu (GDD §16.0 pkt 2): **kiedy się nudziłeś, a kiedy się bałeś**. Wyniki trafiają do tabeli w GDD §23.3 —
decydują o priorytetach przed jakąkolwiek nową zawartością.

## 1. Przed sesją (10 min)

- [ ] Eksport skryptem `tools/export_build.sh Windows` (**nie z edytora**) z drzewa, w którym jest komplet `audio_licensed/`
      (`python tools/audio_lib_fetch.py sync`, potem `python tools/bake_audio.py`; kontrola: `python tools/audio_audit.py --licensed`;
      na Windows w Git Bash `python3` to alias Microsoft Store — używaj `python`). Paczka dla testerów: `tools/package_build.sh Windows`.
      Skrypt odmawia eksportu bez nagrań: build z samej syntezy brzmi inaczej, a groza Stalkera stoi na dźwięku — wszyscy
      uczestnicy muszą dostać ten sam zestaw. Sprawdź build na komputerze, na którym nie ma Godota ani repozytorium.
- [ ] Uruchom eksport: menu → host → cała misja → ekran wyniku → [ENTER] → druga misja. Zero błędów w konsoli.
- [ ] Włącz nagrywanie ekranu **z dźwiękiem i mikrofonem** (OBS). Reakcje graczy są ważniejsze od ich opinii.
- [ ] Zapisz wersję buildu ze stopki menu głównego (np. `1.7.397+abc1234`; ta sama trafia do dziennika sesji). Od 1.7.396 gra sama
      odrzuca dołączenie z innym buildem (komunikat w lobby) — wszyscy muszą mieć tę samą paczkę.
- [ ] Ustaw poziom trudności w menu głównym: **EASY** dla nowych graczy. Gra startuje na NORMAL i zapamiętuje ostatni wybór,
      więc sprawdź go na każdym komputerze, który będzie hostem.
- [ ] Język: przy pierwszym starcie gra bierze język systemu (od 1.7.397: polski Windows → POLSKI). Zanotuj, w jakim języku grał tester.
- [ ] Zakres: kampania to 1.1 → 1.2 → 1.3 → boss B1. Do 1.7.397 **B1 Pijawka nie została pokonana w żadnej sesji autora** (13 podejść,
      także na EASY); od 1.7.398 ma 2000 HP zamiast 5000 (symulacja przy 20 DPS: EASY ok. 2 min, NORMAL ok. 3 min). Zanotuj czas walki
      i liczbę podejść — to pierwszy pomiar nowego HP.
- [ ] Nowy gracz (bez zapisu ustawień) zaczyna od obsługi broni CLASSIC i bez zacięć (od 1.7.398, GDD §16.0a). Gdy tester sam włączy
      REALISTIC albo zacięcia w ustawieniach — zanotuj kiedy i dlaczego. Na zintegrowanej karcie gra startuje w MEDIUM i 75%.
- [ ] Gracze mają słuchawki. Bez nich cały filar „dźwięk jako groza" przepada.
- [ ] Dziennik sesji pisze się sam u hosta (`%APPDATA%\Godot\app_userdata\Dead Air '87 Prototype\sessions\`). Po sesji skopiuj
      ten katalog razem z nagraniem — jest w nim źródło każdego upadku, Uwaga, zamachy Stalkera i statystyki broni (README, „Dziennik sesji”).
      Od 1.7.397 dziennik zapisuje też misje przerwane wyjściem z gry (`"result":"quit"`) i każde friendly fire ze strzelcem (`"ev":"ff"`).
      Raport: `python tools/session_progress.py --dir KATALOG --since RRRR-MM-DD` (mapy, przerwane próby, kryjówka, perki, broń).

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

## 3b. Misja 1.2 „Przerwa w Nadawaniu" (druga misja kampanii; pierwsza to 1.1 — zbieranie, Stalker tylko przechodzi za hałas)

- [ ] Czy gracz rozumie, co robić z generatorem (podpowiedź „Hold E”, pasek postępu)? Ile prób, zanim to zrobi?
- [ ] Czy generator jest „za głośny / za cichy”? Ile Uwagi zwykle wyrabia drużyna do końca celu (karta wyniku: stealth kept/lost)?
- [ ] Skok Uwagi po ostatnim generatorze: czy gracze rozumieją, że Stalker idzie na źródło, i czy używają Q (podpowiedź)?
- [ ] Droga powrotna na początek mapy: czy jest za długa / za pusta? Czy wrogowie z tyłu nie wyskakują nieuczciwie?
- [ ] Podsłuchacze na wieży i w hali: czy da się je cicho zdjąć (kusza, maczeta)?
- [ ] Czas misji (cel GDD: ~10 min) i ile osób opuszcza ją po wipe.
- [ ] Drezyna: czy gracze znajdują szyb i rozumieją, że trzeba trzymać E? Czy wybór „pompuj albo strzelaj" tworzy napięcie, czy frustruje?
- [ ] Drezyna: czy tunel (23 wrogów, Skoczki z sufitu komór) jest za trudny / za łatwy? Czy Stalker dogania, gdy ktoś przestaje pompować?
- [ ] Drezyna w sieci: czy klient na pokładzie nie szarpie się i nie spada? Czy boty wsiadają i pomagają?
- [ ] Kryjówka: czy karta statystyk broni jest czytelna i pomaga wybrać? Czy tablica z odprawą zostaje zauważona i czy lista zagrożeń jest przydatna (nie za długa)?
- [ ] Kryjówka: czy nic się tam nie pojawia (żadnych wrogów, żadnych odgłosów straszaków)?
- [ ] Kryjówka: czy gracze zauważają skrzynki i bronie? Czy [Enter] hosta nie pojawia się za wcześnie (klient czeka)?
- [ ] Kampania: [Enter] po 1.2 → kryjówka → 1.3 (zmiana mapy u klienta bez zawieszenia), po 1.3 → kryjówka → boss B1 → kryjówka → znowu 1.1.

## 4. Sieć (osobny test, 2 komputery w różnych sieciach)

- [ ] Steam P2P: host + klient przez internet (własny App ID — `steam_appid.txt`; 480 działa tylko do testów).
- [ ] Opóźnienie 50–150 ms (np. klient na VPN / hotspot): strzały trafiają, wrogowie nie „skaczą".
- [ ] Dołączenie w środku misji (znane ograniczenie GDD §19 poz. 23 — sprawdź, jak bardzo przeszkadza).
- [ ] Host wychodzi w trakcie gry: klient wraca do lobby z komunikatem „Rozłączono z hostem” (od 1.7.396 czysta scena, wyjście z lobby Steam).
- [ ] Klient ze starszym/innym buildem: komunikat o innej wersji w lobby, host nie tworzy mu postaci.
- [ ] Rozłączenie klienta i ponowne dołączenie.

## 5. Wydajność i komfort

- [ ] Stabilne 60 fps na najsłabszym dostępnym komputerze (walka z wieloma wrogami + boss + flary).
- [ ] 1080p i 1440p: HUD czytelny? (menu pauzy → HUD size: L, jeśli za mały).
- [ ] Wczytywanie mapy: czarna plansza „LOADING…” — ile trwa u testera i czy Windows pokazuje „Nie odpowiada”. Od 1.7.399 świat buduje się
      krokami (najdłuższa klatka ok. 1–2 s na i9 + RTX 3080 zamiast 4–8 s), więc „Nie odpowiada” nie powinno się już pojawić.
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
Do wniosków dołącz liczby z dziennika sesji: trafienia Stalkera w ludzi na misję, źródła upadków, czas faz, użycia Q, udział broni
w obrażeniach i w Uwadze. Pytania, na które sesja ma odpowiedzieć, są w `REVIEW_PLAN.md` (etap R6).
