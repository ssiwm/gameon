# Ruch wrogów 3D

Stan wdrożony: tempo kroku od przemieszczenia, płynny obrót modeli szkieletowych, korekta bioder i kotwiczenie stóp humanoidów w fazie podparcia, cele IK dłoni/stóp pełzaków, osobne proceduralne pozy pazura/chwytu/tasaka oraz widoczna pełna śmierć Pijawki.

`enemy3d.gd:pose` otrzymuje prędkość w pikselach świata/s z `view3d.gd`. Biblioteka chodu i animacja Trzoska są próbkowane z tej samej fazy kroku. Bez prędkości podglądy narzędzi zachowują nominalny cykl. Przejście kierunku zwalnia kotwice, podobnie jak skok pozycji, zmiana stanu i rozpoczęcie zdarzenia.

Humanoidy: cel stopy jest kotwiczony w świecie przy niskim uniesieniu; biodra obniżają się do zasięgu obu nóg. Widok próbkuje wysokość i normalną podłoża promieniami fizyki 2D pod stopami (u pełzaków również pod dłońmi), w zakresie ±8 px i korekty do 45 cm. Stopa podporowa dopasowuje orientację do normalnej. Poza tym zakresem oraz w locie korekta terenu wygasa. Nie jest to kontrola każdego wierzchołka podeszwy ani fizyczny ragdoll. Pełzaki mają przeciwfazowe kończyny oraz osobne cele IK. Trzosek zachowuje istniejącą animację i zbudowaną przez IK pozycję siadu.

Ataki: niedopasowany wspólny klip został zastąpiony przez ręcznie ustalone, ograniczone anatomicznie cele w runtime. Chód nadal korzysta z biblioteki. Rzeźnik ma odrębną prawą rękę z tasakiem; Stalker sięga do ofiary bez składania tułowia ku ziemi. Nie zmieniono czasu zadawania obrażeń, zasięgów ani balansu gameplayu.

`enemy.gd` i `stalker.gd` udostępniają `attack_seq`. Serwer zwiększa numer przy rozstrzygnięciu ciosu, także chybionego. Zdarzenie jest wysyłane przez niezawodne RPC autorytetu; klient ignoruje starsze numery. Przerwanie zapowiedzi nie wysyła zdarzenia. Podsłuchacz, Kapłan i specjalne działania Wołka wysyłają zdarzenia w miejscach wykonania. Bossowie z własnymi sekwencjami sprite'a zachowują swój kontrakt. Spóźniony obserwator nie odtwarza historycznych ataków.

Pijawka ma własny czas śmierci niezależny od ogólnych klipów. `die()` nie ukrywa jej natychmiast: deformacja death jest próbkowana z czasu śmierci, po czym działa wspólne zatrzymanie i zapadanie modelu.

Ćma porusza skrzydłami w płaszczyźnie pionowej wokół osi korpusu, zamiast obracać je poziomo. Shader obraca również normalne, styczne i binormalne skrzydła.

## Weryfikacja

```text
godot --headless --path prototype -s tools/test_enemy_motion.gd
godot --headless --path prototype -s tools/test_enemy_motion_network.gd -- --motion-server
godot --headless --path prototype -s tools/test_enemy_motion_network.gd -- --motion-client
godot --headless --path prototype -- --host --enemytest --autoquit=150
godot --headless --path prototype -- --host --stalkertest --autoquit=70
```

Serwer i klient testu ENet uruchamiają się jednocześnie; używają portu 18974 lub `--motion-port=N`. Regresja modeli obejmuje 14 rodzajów, 30/60/120 kl./s, prędkości 0/0,25/1/1,5, długości kości, dryf stopy podczas podparcia, płynny obrót, podparcie w postoju i zapowiedzi, nierówne wysokości i normalną podłoża, wysokość dłoni w ataku, śmierć oraz powrót do życia. Testy zachowań obejmują ogłuszenie podczas błysku, chybiony cios i starszy numer zdarzenia.

Kontrola obrazu: `tools/shot_enemy_clip3d.gd -- --anim=attackseq --movie=KATALOG --kinds=wolek,rzeznik,slepiec,stalker` oraz `tools/shot_enemies.gd -- --mission=z1_m2 --port=8970 --dir=KATALOG --reveal`. Podgląd studyjny ocenia anatomię; zrzuty mapy oceniają obraz z docelowej kamery. Materiały, LOD i fizyczny ragdoll nie są częścią tej poprawki.
