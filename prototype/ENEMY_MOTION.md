# Ruch wrogów 3D

## Stan implementacji

`enemy_motion.gd` opisuje autorskie klatki riga, a `tools/bake_enemy_motion.gd` zapisuje je w natywnej Godot AnimationLibrary `art/enemy3d/motion.tres`. Klipy zawierają kanały ciała i cele kończyn normalizowane wysokością bioder. `Enemy3D` próbkuje zasób i retargetuje cele przez IK. Są to ręcznie opracowane klipy riga sterującego, nie nagrania motion capture ani nowe GLB z animacjami wszystkich kości. Chód zachowuje istniejące biblioteki, a bossowie swoje sekwencje deformacji.

| Rodzaj / działanie | Klip | Kontakt w zasobie / powrót (s) |
|---|---|---|
| Wołek | smash | 0,60 / 0,76 |
| Rzeźnik | cleave | 0,50 / 0,64 |
| Ślepiec | claw | 0,35 / 0,46 |
| Stalker | grab | 0,40 / 0,68 |
| Mimik | reveal_grab | 0,40 / 0,55 |
| Podsłuchacz | scream | 0,90 / 0,60 |
| Kapłan | ritual | 0,70 / 0,82 |
| Skoczek | pounce | 0,30 / 0,38 |
| Żerca | snatch | 0,40 / 0,56 |
| Trzosek | bite | 0,28 / 0,42 |
| Ćma | dive | 0,20 / 0,40 |
| Szarża / rzut Wołka | charge / throw | 0,70 / 0,25; 0,60 / 0,52 |
| Amortyzacja lądowania | landing | 0,00 / 0,24 |

## Zegar i autorytet

`enemy.gd:view_info` i `stalker.gd:view_info` przekazują pozostały i całkowity czas zapowiedzi oraz stan podłoża. Zachowania Wołka, Kapłana, Podsłuchacza i Mimika dostarczają własne czasy. Zapowiedź klipu skaluje się do czasu gameplayu, w tym trudności. Samo wyzerowanie licznika nie odtwarza ciosu.

`attack_seq` zwiększa serwer przy rozstrzygnięciu, również chybionego ciosu. Niezawodne RPC przenosi numer i rodzaj działania (np. szarżę lub rzut); starszy numer nie zmienia rodzaju. `view3d.gd:_sync_enemies` przekazuje kontekst przed zdarzeniem. Pierwsza poza po zdarzeniu wypada dokładnie w punkcie kontaktu zasobu, a potem odtwarza osobny powrót. Nie wykonuje dodatkowego zamachu. Przerwanie zapowiedzi wygasza nakładkę bez zdarzenia; obrót zostaje wstrzymany w pierwszej ćwiartce powrotu.

Obrażenia, zasięgi i czasy gameplayu nadal rozstrzyga serwer. Obserwator widzi zdarzenie po jego dostarczeniu przez sieć; ta zmiana nie usuwa fizycznego opóźnienia transmisji. Zmieniony kontrakt RPC wymaga tej samej wersji gry na peerach.

Stalker replikuje wysokość tułowia rzeczywistej ofiary, uwzględniając przysiad oraz poziom mapy. Model obniża biodra i dłonie do celu zamiast chwytać na wysokości własnej klatki piersiowej. Zasięg rąk nadal ogranicza IK. Niezawodne zdarzenie niesie także kierunek chwytu, który pozostaje skierowany do ofiary podczas cofania przez czas powrotu klipu. Spóźniona migawka z innego kanału nie nadpisuje wysokości rozstrzygniętego chwytu podczas tej fazy. Na hoście model zachowuje pozycję w klatce kontaktu i płynnie odtwarza serwerowe odsunięcie po ciosie; klient zachowuje interpolację symulacji.

## Lokomocja i podparcie

`pose` otrzymuje prędkość poziomą w pikselach świata/s. Faza chodu i biblioteka Trzoska podążają za rzeczywistym tempem. Bez tego argumentu narzędzia zachowują nominalny cykl. Zmiana kierunku, stanu lub skok pozycji zwalniają kotwice stóp.

Humanoidy korygują biodra do zasięgu nóg. Podporowe stopy mają cele w świecie i orientację normalnej podłoża. Pełzaki prowadzą dłonie i stopy przez IK w przeciwfazie. Cztery łapy Trzoska korzystają z animacji źródłowej i korekty dwukostkowej również podczas przejścia z siadu. Orientacje krótkich kości łapy pozostają z klipu, bez skręcania skóry.

`_prepare_soles` raz na rodzaj oblicza otoczkę podeszwy i niewielką próbkę wierzchołków ze skóry. Uwzględnia inverse bind, w tym przesunięcie bind pose Trzoska. Wierzchołki z mieszanymi wagami piszczeli, stopy i palców również uczestniczą w korekcie. W klatce sprawdzane są wybrane punkty, a cele IK podnoszone w razie zagłębiania; długości kości i wagi pozostają bez zmian. Dane geometrii i neutralny poziom podparcia są buforowane.

Widok próbuje wysokość i normalną podłoża promieniami fizyki 2D w zakresie ±8 px, z maksymalną korektą terenu 45 cm. Stan `grounded` utrzymuje pozę lotu także przy zerowej prędkości w szczycie skoku. Lądowanie po opadaniu uruchamia amortyzację zależną od prędkości. Pełzak wiszący pod stropem nie jest traktowany jak spadający.

Pijawka odtwarza pełną własną śmierć przed zatrzymaniem i zapadaniem modelu. Ćma porusza skrzydłami pionowo i obraca normalne oraz styczne. Materiały pozostałych modeli i geometria GLB zostały zachowane.

## Chód Wołka

Wołek chodzi pozą z kodu (SPEC `gait: heavy`, `enemy3d.gd::_heavy_gait`), nie klipem: klip `zombie` dawał przy jego krótkich nogach drobny krok na palcach z głową pod barkami. Każda stopa przez `GAIT_STANCE` (0,62) cyklu stoi w podporze i przesuwa się liniowo do tyłu z prędkością ciała — długość kroku to prędkość z `DEFS` × cykl (0,62 s) × podpora, więc stopa nie ślizga się w żadnym tempie — potem przenoszenie z uniesieniem. Ciało jest najniżej przy postawieniu stopy (krótkie osiadanie ciężaru) i najwyżej nad podporą, ciężar i barki przechylają się nad stopę podporową (kanał `roll`, głowa trzyma poziom), miednica i klatka skręcają się przeciwnie. Długie ręce zwisają nisko przy ciele i wymachują przeciwnie do nogi tej samej strony; dłoń z przodu unosi się. `test_enemy_motion.gd::heavy_gait` sprawdza brak poślizgu podpory przy 30/60/120 kl./s i tempie 0,5/1/1,5, udział podpory, wymach i kołysanie.

## Zapowiedź i śmierć Wołka

Kamera gry patrzy z boku, więc pięści Wołka w szczycie `smash` stoją wysoko i za głową; nad samymi barkami chowały się za garbem i rogami. Po krótkim zawieszeniu cios to młot obiema pięściami w grunt przed nim z wykrokiem przedniej nogi, a nie poziome pchnięcie. Tekstura ma tylko kilka ciepłych pikseli, więc maska HSV nie dawała żaru oczu: SPEC `eye_lamp` stawia przy kości głowy dwie emisyjne kulki (jasność jak `eye_glow`, w zapowiedzi pulsuje), a w zapowiedzi zapala ciepłe `OmniLight3D` przed pyskiem, czytelne w nocy. SPEC `flare` dodaje ciepłą obwódkę ciała w ostatnich 0,25 s zapowiedzi (czas z symulacji) i krótko po kontakcie; dotyczy też zapowiedzi szarży i rzutu.

Przewrót wokół stóp wbijał zgarbionego Wołka głową i rogami ok. 1 m w podłogę. SPEC `death_floor` liczy przy budowie modelu otoczkę skóry (skrajne wierzchołki każdej kości w 26 kierunkach, ok. 400 próbek, ok. 40 ms raz na rodzaj) i w czasie upadku podnosi ciało do najniższego punktu; zapadanie zwłok liczy się od tego podparcia. Pozostałe dwunożne też wchodzą w podłogę przy śmierci (Rzeźnik ok. 1 m, Podsłuchacz i Kapłan ok. 0,3 m), ale samo podparcie ich nie naprawia — Rzeźnik oparłby się na sztorc na tasaku — więc flaga jest na razie tylko u Wołka. `test_enemy_motion.gd` mierzy najniższy punkt całej skóry po skinningu w upadku i leżeniu rodzajów z tą flagą.

## Testy i narzędzia odbioru

```text
godot --headless --path prototype --editor --import
godot --headless --path prototype -s tools/bake_enemy_motion.gd
godot --headless --path prototype -s tools/test_enemy_motion.gd
godot --headless --path prototype -s tools/audit_enemy_assets.gd -- --out=/tmp/enemy-assets.json
python3 prototype/tools/test_enemy_motion_proxy.py
godot --headless --path prototype -s tools/test_enemy_motion_network.gd -- --motion-server
godot --headless --path prototype -s tools/test_enemy_motion_network.gd -- --motion-client --motion-port=19074
godot --headless --path prototype -- --host --enemytest --autoquit=150
godot --headless --path prototype -- --host --stalkertest --autoquit=70
godot --path prototype -s tools/shot_enemy_motion.gd -- --dir=/tmp/enemy-film
godot --path prototype -s tools/bench_enemy_motion.gd -- --count=36 --out=/tmp/enemy-bench.json
godot --path prototype -s tools/shot_enemies.gd -- --mission=z1_m2 --dir=/tmp/enemy-map --reveal
```

Relay, serwer i klient działają jednocześnie: serwer na 18974, relay na 19074. Relay wprowadza 75 ms w każdą stronę oraz stratę co 13. datagramu po zestawieniu połączenia. Test sprawdza zapowiedź, stan podłoża, punkt kontaktu, typ działania, trzy niezawodne zdarzenia oraz wysokość i kierunek chwytu Stalkera, także po spóźnionym zdarzeniu ze starszym numerem.

Regresja modeli obejmuje 14 rodzajów, 30/60/120 kl./s, prędkości 0/0,25/1/1,5, długości kości, podparcie, obrót, kontakt przy różnych długościach zapowiedzi, przerwanie, skok, lądowanie, śmierć i powrót do życia. Audyt siatek dodatkowo sprawdza bindy, sumy wag i wszystkie wierzchołki regionu stóp w wybranych sekwencjach przy tych samych FPS; tolerancja zagłębiania wynosi 2,5 cm. Nie jest to test każdej kolizji całej skóry.

Film zapisuje 240 klatek 30 kl./s po wyrenderowaniu obrazu. Każda komórka ma własną skalę kamery, więc atlas nie porównuje wzrostu gatunków. Zrzuty mapy korzystają z docelowej kamery gry. Benchmark zapisuje koszt CPU pozowania, rzeczywisty czas klatki, liczbę draw calls i pamięć wideo w stanowisku 1280×720 po rozgrzaniu. Wynik stanowiska nie zastępuje pomiaru całej misji na docelowym sprzęcie.

## Granice weryfikacji

Regresje numeryczne i render nie gwarantują filmowej jakości ruchu w każdej sytuacji. Ragdoll, motion capture i przebudowa topologii nie są częścią tej implementacji. Ustawienia importu włączają generowanie LOD oraz kompresję VRAM, lecz pomiar nie stanowi certyfikacji wydajności na słabszych kartach ani osobnego odbioru każdego poziomu LOD. Shaderowe deformacje bossów nie uczestniczą w CPU pomiarze podeszew.
