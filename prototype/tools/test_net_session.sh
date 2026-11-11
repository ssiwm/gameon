#!/usr/bin/env bash
# Testy sesji sieciowej (headless, ~1 min). Kod wyjścia ≠ 0 przy błędzie.
#   tools/test_net_session.sh        # z katalogu prototype/
# 1. Inna wersja: klient z --fakebuild nie wchodzi do gry (host nie tworzy mu postaci), lobby klienta podaje powód.
# 2. Utrata hosta: klient przeładowuje scenę (jak leave_session), wraca do lobby z komunikatem i nie dołącza ponownie z --join.
# 4. Bez AI towarzysza (NOBOT_PLAN.md): host z --nobot, klient dostaje ustawienie hosta, przy dwóch ludziach nie ma bota.
# 5. Raport po akcji (RESULTS_PLAN.md): gotowość klienta dochodzi do hosta, poziomy z misji i rozbicie złomu do wszystkich.
# 6. Bateria 4,5 V (BATTERY_PLAN.md): klient z 20% baterii bierze baterię z ziemi — rozstrzyga serwer, dolicza właściciel.
# 7. Ładowarka (BATTERY_PLAN.md B3): klient przy ładowarce B1 ładuje się u siebie, serwer widzi, że ładowarka pracuje.
# 8. Zniszczenia (DESTRUCTION_PLAN.md D0–D3): rany ściany, rozbicie, powrót do migawki z przebudzenia bossa i wipe na 1.2, a złamany stempel
#    i zawał na mapie testowej t_mine, wykopy, wybuch, wykopana znajdźka, osypany żwir, spadła wyspa i pula znajdziek hosta w strefach wydobycia (D5) na mapie testowej t_dig — u klienta obecnego od początku
#    (RPC na żywo) i u dołączającego później (`send_walls_to`) stan taki sam jak u hosta.
# 3. Czterech ludzi: numery P1–P4 (bot nie zabiera numeru, P5 się nie pojawia); klienci wychodzą po kolei, a ci, którzy zostają, nie dostają
#    błędu silnika `on_despawn_receive … ERR_UNAUTHORIZED` (postać wychodzącego usuwa tylko serwer).
# Wymaga `godot` w PATH i zaimportowanego projektu (godot --headless --path . --import).
set -u
cd "$(dirname "$0")/.."
LOG="${TMPDIR:-/tmp}/dead_air_net_session"
mkdir -p "$LOG"
rm -f "$LOG"/*.log
rc=0

fail() { echo "FAIL  $1"; rc=1; }
ok() { echo "PASS  $1"; }

echo "== inna wersja =="
godot --headless --path . -- --host --port=8960 --autoquit=16 >"$LOG/ver_host.log" 2>&1 &
HOST=$!
sleep 4
godot --headless --path . -- --join=127.0.0.1 --port=8960 --fakebuild=0.0.0-test --autoquit=9 >"$LOG/ver_client.log" 2>&1
wait $HOST
grep -a -q "\[NET\] version mismatch" "$LOG/ver_client.log" && ok "klient wykrywa inną wersję" || fail "klient nie wykrył innej wersji"
grep -a -q "\[NET\] po końcu sesji: sieć=false graczy=0 lobby=true powód=version" "$LOG/ver_client.log" && ok "klient w lobby z powodem" || fail "klient nie wrócił do lobby z powodem"
[ "$(grep -a -c "\[NET\] spawned player" "$LOG/ver_host.log")" -eq 1 ] && ok "host nie tworzy postaci klientowi z inną wersją" || fail "host stworzył postać klientowi z inną wersją"

echo "== utrata hosta =="
godot --headless --path . -- --host --port=8961 --autoquit=9 >"$LOG/drop_host.log" 2>&1 &
HOST=$!
sleep 4
godot --headless --path . -- --join=127.0.0.1 --port=8961 --autoquit=14 >"$LOG/drop_client.log" 2>&1
wait $HOST
grep -a -q "\[NET\] connected as peer" "$LOG/drop_client.log" && ok "klient dołączył" || fail "klient nie dołączył"
grep -a -q "\[NET\] po końcu sesji: sieć=false graczy=0 lobby=true powód=host_lost" "$LOG/drop_client.log" \
	&& ok "po utracie hosta: czysta scena, lobby z komunikatem" || fail "po utracie hosta brak czystej sceny albo komunikatu"
[ "$(grep -a -c "\[NET\] connected as peer" "$LOG/drop_client.log")" -eq 1 ] && ok "bez ponownego dołączenia z --join" || fail "klient dołączył ponownie po przeładowaniu"

echo "== czterech ludzi =="
godot --headless --path . -- --host --port=8962 --autoquit=40 >"$LOG/four_host.log" 2>&1 &
HOST=$!
sleep 4
CLIENTS=()
for i in 1 2 3; do
	# start co 2 s, wyjście co 6 s (c1 pierwszy): pozostali widzą odejście kolegi
	godot --headless --path . -- --join=127.0.0.1 --port=8962 --autoquit=$((10 + 4 * i)) >"$LOG/four_c$i.log" 2>&1 &
	CLIENTS+=($!)
	sleep 2
done
wait "${CLIENTS[@]}" $HOST
for n in 2 3 4; do
	grep -a -q "\[NET\] spawned player [0-9]* (display P$n)" "$LOG/four_host.log" && ok "człowiek dostaje P$n" || fail "żaden człowiek nie dostał P$n"
done
grep -a -q "display P[5-9]" "$LOG/four_host.log" && fail "numer ponad P4 przy czterech ludziach" || ok "bez numerów ponad P4"
grep -a -q "\[BOT\] spawned companion slot 4" "$LOG/four_host.log" && ok "bot zajmuje najwyższy wolny numer (P4)" || fail "bot nie wziął P4"
[ "$(grep -a -c "\[NET\] peer disconnected" "$LOG/four_c3.log")" -ge 2 ] && ok "ostatni klient widzi odejście dwóch kolegów" || fail "ostatni klient nie widział odejść kolegów"
if grep -a -q "ERR_UNAUTHORIZED" "$LOG"/four_c*.log; then fail "błąd despawnu u klienta po odejściu kolegi (ERR_UNAUTHORIZED)"; else ok "bez błędów despawnu u klientów po odejściu kolegów"; fi

echo "== wyjście z sesji w kryjówce =="
# jak „Wyjdź” z menu pauzy: wyjście przed krokiem fizyki; stanowiska kryjówki nie mogą pytać o peera, którego już nie ma
godot --headless --path . -- --host --mission=z1_hub --leavetest --port=8965 --autoquit=20 >"$LOG/leave.log" 2>&1
grep -a -q "\[LEAVE-TEST\] PASS" "$LOG/leave.log" && ok "po wyjściu scena od nowa, host hostuje ponownie" || fail "wyjście z sesji: brak PASS"
[ "$(grep -a -c "No multiplayer peer is assigned" "$LOG/leave.log")" -eq 0 ] && ok "wyjście bez błędów „No multiplayer peer” (stanowiska, broń)" || fail "wyjście z sesji: $(grep -a -c "No multiplayer peer is assigned" "$LOG/leave.log") × „No multiplayer peer”"

echo "== kryptonimy =="
# host i pierwszy klient mają ten sam kryptonim (drugi dostaje „(2)”), drugi klient wysyła śmieci w nazwie (czyszczenie na każdym peerze)
# Drugi klient startuje dopiero, gdy host stworzy postać pierwszemu (stałe `sleep 1` dawało na CI odwróconą kolejność P2/P3).
# Liczniki --printsquad/--autoquit biegną od startu każdego procesu, a start Godota trwa kilka sekund: host i pierwszy klient muszą
# żyć, aż drugi wypisze listę (przy autoquit=12 hosta drugi klient wypisywał już pustą listę po utracie hosta), a drugi klient —
# aż wypisze ją host. Drugi startuje najwcześniej ok. 7 s po hoście i najpóźniej po 14 s, więc host wypisuje listę w 26 s, a drugi
# żyje 24 s (przy autoquit=12 szybki runner rozłączał go przed wypisaniem listy hosta: „P1=Sowa | P2=sowa (2)” bez P3).
godot --headless --path . -- --host --nobot --port=8964 --callsign=Sowa --printsquad=26 --autoquit=44 >"$LOG/call_host.log" 2>&1 &
HOST=$!
sleep 4
godot --headless --path . -- --join=127.0.0.1 --port=8964 --callsign=sowa --printsquad=7 --autoquit=38 >"$LOG/call_c1.log" 2>&1 &
C1=$!
for _ in $(seq 40); do grep -a -q "display P2)" "$LOG/call_host.log" && break; sleep 0.25; done
godot --headless --path . -- --join=127.0.0.1 --port=8964 '--callsign=<b>Wi!lk</b>' --printsquad=10 --autoquit=24 >"$LOG/call_c2.log" 2>&1 &
C2=$!
wait $C2 $C1 $HOST
grep -a -q "\[SQUAD\] P1=Sowa | P2=sowa (2) | P3=bWilkb" "$LOG/call_host.log" && ok "host widzi kryptonimy klientów, powtórka z „(2)”, śmieci wycięte" || fail "host: zła lista kryptonimów ($(grep -a "\[SQUAD\]" "$LOG/call_host.log"))"
grep -a -q "\[SQUAD\] P1=Sowa | P2=sowa (2) | P3=bWilkb" "$LOG/call_c2.log" && ok "klient widzi te same kryptonimy co host" || fail "klient: zła lista kryptonimów ($(grep -a "\[SQUAD\]" "$LOG/call_c2.log"))"

echo "== bez AI towarzysza =="
godot --headless --path . -- --host --nobot --port=8963 --autoquit=12 >"$LOG/nobot_host.log" 2>&1 &
HOST=$!
sleep 4
godot --headless --path . -- --join=127.0.0.1 --port=8963 --autoquit=6 >"$LOG/nobot_client.log" 2>&1
wait $HOST
grep -a -q "\[NET\] AI companion (host): OFF" "$LOG/nobot_client.log" && ok "klient dostaje od hosta: towarzysz OFF" || fail "klient nie dostał ustawienia towarzysza"
grep -a -q "\[NET\] spawned player [0-9]* (display P2)" "$LOG/nobot_host.log" && ok "klient dołączył (P2)" || fail "klient nie dołączył"
grep -a -q "\[BOT\] spawned" "$LOG/nobot_host.log" && fail "host z --nobot stworzył bota" || ok "host z --nobot: bez bota solo i przy dwóch ludziach"

echo "== raport po akcji =="
# RESULTS_PLAN.md: host kończy misję, klient zgłasza „gotowy” — host to widzi; poziomy obu graczy i rozbicie złomu dochodzą do wszystkich
godot --headless --path . -- --host --mission=z1_m1 --port=8966 --resultnet=5 --autoquit=15 >"$LOG/result_host.log" 2>&1 &
HOST=$!
sleep 3
godot --headless --path . -- --join=127.0.0.1 --port=8966 --resultnet=6 --autoquit=11 >"$LOG/result_client.log" 2>&1
wait $HOST
grep -a -q "\[RESULT-NET\] host ready=\[[0-9]\+\] levels=2 gain=[0-9]\+ report=true" "$LOG/result_host.log" && ok "host widzi gotowość klienta i poziomy obu graczy" || fail "host: $(grep -a "\[RESULT-NET\]" "$LOG/result_host.log")"
grep -a -q "\[RESULT-NET\] client ready=\[[0-9]\+\] levels=2 gain=[0-9]\+ report=true" "$LOG/result_client.log" && ok "klient: raport otwarty, złom od serwera, własna gotowość odbita" || fail "klient: $(grep -a "\[RESULT-NET\]" "$LOG/result_client.log")"

echo "== hala Żyły =="
# VEIN_PLAN.md E1: host po 6 s niszczy gniazda i wchodzi do hali; klient A został w przedsionku — brama zamyka się po 4 s i wciąga go
# do hali. Klient B dołącza przy zamkniętej bramie — stan bramy dostaje z `send_vein_gate_to`, stan Żyły z `_sync`, a serwer wciąga go
# do hali (`pull_into_arena`, co ARENA_PULL_EVERY s). E2: host 7 s po zamknięciu bramy zanurza Żyłę — klient A widzi zanurzenie (Move 2),
# przejście (3) i zapowiedź (4), przesunięcie o gardziel, a Żyła wychodzi w innej gardzieli.
godot --headless --path . -- --host --mission=z1_m3 --port=8972 --veinnet=6 --autoquit=34 >"$LOG/vnet_host.log" 2>&1 &
HOST=$!
sleep 3
godot --headless --path . -- --join=127.0.0.1 --port=8972 --veinnet=14 --autoquit=31 >"$LOG/vnet_a.log" 2>&1 &
CA=$!
sleep 11
godot --headless --path . -- --join=127.0.0.1 --port=8972 --veinnet=6 --autoquit=12 >"$LOG/vnet_b.log" 2>&1
wait $CA $HOST
grep -a -q "\[VEIN-NET\] host gate=true boss=1 client_in=true" "$LOG/vnet_host.log" && ok "host: Żyła walczy, brama zamknięta, klient z przedsionka wciągnięty" || fail "host: $(grep -a "\[VEIN-NET\]" "$LOG/vnet_host.log")"
grep -a -q "\[VEIN-NET\] client gate=true blocks=true boss=1 in=true cam=true" "$LOG/vnet_a.log" && ok "klient: brama i jej kolizja, Żyła przebudzona, sam w hali, kamera areny" || fail "klient A: $(grep -a "\[VEIN-NET\]" "$LOG/vnet_a.log")"
grep -a -q "\[VEIN-NET\] host moved=true" "$LOG/vnet_host.log" && ok "host: Żyła zanurzona przeszła do innej gardzieli" || fail "host: $(grep -a "\[VEIN-NET\] host moved" "$LOG/vnet_host.log")"
grep -a -q "\[VEIN-NET\] client moves=.*2,3,4.* shift=\([1-9][0-9][0-9]\) sinkvis=1.0" "$LOG/vnet_a.log" && ok "klient: przejście i zapowiedź z _sync, przesunięcie o gardziel, model pod podłogą" || fail "klient A: $(grep -a "\[VEIN-NET\] client moves" "$LOG/vnet_a.log")"
grep -a -q "\[VEIN-NET\] client gate=true blocks=true boss=1 in=true" "$LOG/vnet_b.log" && ok "dołączający przy zamkniętej bramie: brama, kolizja, stan Żyły, wciągnięty do hali" || fail "klient B: $(grep -a "\[VEIN-NET\]" "$LOG/vnet_b.log")"

echo "== bateria 4,5 V =="
# BATTERY_PLAN.md B1: serwer rozstrzyga podniesienie po replikowanym `bat_pct` klienta, a baterię dolicza właściciel postaci (RPC apply_battery)
godot --headless --path . -- --host --mission=z1_m1 --port=8967 --batterynet=9 --autoquit=16 >"$LOG/battery_host.log" 2>&1 &
HOST=$!
sleep 3
godot --headless --path . -- --join=127.0.0.1 --port=8967 --batterynet=5 --autoquit=12 >"$LOG/battery_client.log" 2>&1
wait $HOST
grep -a -q "\[BATTERY-NET\] host client_pct=\(6[89]\|7[0-9]\) taken=true" "$LOG/battery_host.log" && ok "host: klient z 20% wziął baterię, bat_pct po replikacji ok. 70%" || fail "host: $(grep -a "\[BATTERY-NET\]" "$LOG/battery_host.log")"
grep -a -q "\[BATTERY-NET\] client battery=12[0-9] pct=\(6[89]\|7[0-9]\)" "$LOG/battery_client.log" && ok "klient: +90 s baterii od serwera" || fail "klient: $(grep -a "\[BATTERY-NET\]" "$LOG/battery_client.log")"

echo "== ładowarka =="
# BATTERY_PLAN.md B3: klient przy ładowarce B1 ładuje się u siebie (właściciel), stan „pracuje” rozstrzyga serwer i rozsyła RPC
godot --headless --path . -- --host --mission=z1_b1 --port=8968 --chargernet=11 --autoquit=18 >"$LOG/charger_host.log" 2>&1 &
HOST=$!
sleep 3
godot --headless --path . -- --join=127.0.0.1 --port=8968 --chargernet=5 --autoquit=12 >"$LOG/charger_client.log" 2>&1
wait $HOST
grep -a -q "\[CHARGER-NET\] host active=true client_pct=[2-9][0-9]" "$LOG/charger_host.log" && ok "host: ładowarka pracuje, klient ładowany (bat_pct z replikacji)" || fail "host: $(grep -a "\[CHARGER-NET\]" "$LOG/charger_host.log")"
grep -a -q "\[CHARGER-NET\] client gain=\(1[5-9]\|2[0-2]\) active=true" "$LOG/charger_client.log" && ok "klient: ok. +6 s/s u właściciela, stan ładowarki z serwera" || fail "klient: $(grep -a "\[CHARGER-NET\]" "$LOG/charger_client.log")"

echo "== zniszczenia =="
# host: po 10 s rozbija skrzynię Crate1, tłucze lampę MissionLamp1 i okno Window1, zabija pusty otwór Opening1 dwiema deskami (SC), po 1 s dwa ciosy kilofem (S1), gdy są obaj
# klienci — migawka i rozbicie (S2), +3 s powrót do migawki (S1 z zapaloną lampą i całym oknem), +3 s wipe (S0, ściana i skrzynia całe,
# lampa świeci, szyba cała), +2 s koniec. Klient A od początku, klient B dołącza dopiero po ciosach — plamy, HP, rozbitą skrzynię,
# stłuczoną lampę i okno dostaje z `send_walls_to`.
# Klienci kończą po końcowym wipe'ie (albo w lobby po utracie hosta); `--autoquit` to tylko bezpiecznik.
godot --headless --path . -- --host --mission=z1_m2 --port=8969 --destructionnet=10 --autoquit=60 >"$LOG/dnet_host.log" 2>&1 &
HOST=$!
sleep 3
godot --headless --path . -- --join=127.0.0.1 --port=8969 --destructionnet=0 --autoquit=60 >"$LOG/dnet_a.log" 2>&1 &
CA=$!
for _ in $(seq 120); do grep -a -q "\[DESTRUCTION-NET\] host .*splats=2/" "$LOG/dnet_host.log" && break; sleep 0.25; done
godot --headless --path . -- --join=127.0.0.1 --port=8969 --destructionnet=0 --autoquit=50 >"$LOG/dnet_b.log" 2>&1 &
CB=$!
wait $CB $CA $HOST
# stany na mapie misji jako „S;S;…” (przed dołączeniem i po utracie hosta klient jest w lobby — pomijane)
# strefa wydobycia 1.2 (D5 część 3) nie należy do tej sekcji — skrót stref („ dig1=…” na końcu stanu) odcięty, strefy sprawdza sekcja t_dig
dnet() { grep -a "\[DESTRUCTION-NET\] $1 map=z1_m2 " "$2" | sed "s/.*\] $1 map=z1_m2 //; s/ dig[0-9]*=.*$//" | tr '\n' ';'; }
H=$(dnet host "$LOG/dnet_host.log")
IFS=';' read -r S0 SC S1 S2 S3 S4 _ <<<"$H"
S0X="${S0% bar=0 crate=ok lamp=lit win=ok}"          # stan bez desek, skrzyni, lampy i okna
HW="${S0X#opened=\[Opening1\] }"                     # sama ściana; na starcie wolny jest tylko pusty otwór
if [ "$S0X" = "$S0" ] || [ "$HW" = "$S0X" ] || [ "$SC" != "opened=[] $HW bar=2 crate=gone lamp=out win=out" ] \
		|| [ "${S1#*splats=2/}" = "$S1" ] || [ "$S2" != "opened=[BrickWall1] bar=2 crate=gone lamp=out win=out" ] \
		|| [ "$S3" != "${S1% lamp=out win=out} lamp=lit win=ok" ] || [ "$S4" != "$S0" ]; then
	fail "host: zły przebieg ($H)"
else
	ok "host: cała → skrzynia rozbita, lampa i okno stłuczone, otwór zabity dwiema deskami → ranna → rozbita → ranna, lampa świeci, szyba cała (migawka) → cała ze skrzynią (wipe)"
	A=$(dnet client "$LOG/dnet_a.log")
	[ "$A" = "$H" ] && ok "klient od początku: te same plamy, HP, rozbicie, skrzynia, migawka i wipe co host" || fail "klient A: $A (host: $H)"
	B=$(dnet client "$LOG/dnet_b.log")
	[ "$B" = "$S1;$S2;$S3;$S4;" ] && ok "dołączający po ciosach: plamy, HP, rozbita skrzynia, stłuczona lampa i okno, zabity otwór z synchronizacji, potem rozbicie, migawka i wipe jak u hosta" || fail "klient B: $B (host: $H)"
fi

echo "== zawał (t_mine) =="
# host: po 8 s łamie stempel Support1 kilofem (SS), po CAVE_DELAY strefa Rubble1 się zawala (SV); gdy są obaj klienci: wipe (stempel cały,
# strefa wolna = S0), migawka z przebudzenia bossa (zawał wraca = SV) i wipe (S0). Klient A od początku, klient B dołącza po zawale —
# złamany stempel i gruz dostaje z `send_walls_to`.
godot --headless --path . -- --host --mission=t_mine --port=8970 --cavenet=8 --autoquit=50 >"$LOG/cnet_host.log" 2>&1 &
HOST=$!
sleep 3
godot --headless --path . -- --join=127.0.0.1 --port=8970 --cavenet=0 --autoquit=50 >"$LOG/cnet_a.log" 2>&1 &
CA=$!
for _ in $(seq 120); do grep -a -q "\[DESTRUCTION-NET\] host map=t_mine opened=\[\] sup=down" "$LOG/cnet_host.log" && break; sleep 0.25; done
godot --headless --path . -- --join=127.0.0.1 --port=8970 --cavenet=0 --autoquit=40 >"$LOG/cnet_b.log" 2>&1 &
CB=$!
wait $CB $CA $HOST
cnet() { grep -a "\[DESTRUCTION-NET\] $1 map=t_mine " "$2" | sed "s/.*\] $1 map=t_mine //" | tr '\n' ';'; }
H=$(cnet host "$LOG/cnet_host.log")
CS0="opened=[Rubble1] sup=ok"
CSS="opened=[Rubble1] sup=down"
CSV="opened=[] sup=down"
if [ "$H" != "$CS0;$CSS;$CSV;$CS0;$CSV;$CS0;" ]; then
	fail "host: zły przebieg zawału ($H)"
else
	ok "host: stempel cały → złamany (strefa trzeszczy) → zawał → wipe (stempel cały, strefa wolna) → migawka (zawał wraca) → wipe"
	A=$(cnet client "$LOG/cnet_a.log")
	[ "$A" = "$H" ] && ok "klient od początku: złamany stempel, zawał, migawka i wipe jak u hosta" || fail "klient A: $A (host: $H)"
	B=$(cnet client "$LOG/cnet_b.log")
	[ "$B" = "$CSV;$CS0;$CSV;$CS0;" ] && ok "dołączający po zawale: złamany stempel i gruz z synchronizacji, potem wipe, migawka i wipe jak u hosta" || fail "klient B: $B (host: $H)"
fi

echo "== strefy wydobycia (t_dig) =="
# host: po 8 s trzy ciosy kilofem w DigZone1 i wybuch w DigZone2 (DS); gdy są obaj klienci: wipe (strefy z danych mapy = D0), migawka
# (wykopy wracają = DS) i wipe (D0). Klient A od początku (operacje kopania na żywo), klient B dołącza po wykopach — gęstość stref dostaje
# z `send_walls_to`. Stan = skrót gęstości i materiału każdej strefy, więc zgodność znaczy: te same komórki u wszystkich. Host przed
# klientem B kopie też dół w żwirze (DigZone3, osypuje się) i odcina blok w skale (DigZone2, spada jako wyspa) — oba idą deltą z serwera.
# Pula znajdziek DigZone1 jest u hosta odnowiona raz i z jednym miejscem wykopanym — skrót znajdziek u klientów zgadza się tylko po sync Scrap.
godot --headless --path . -- --host --mission=t_dig --port=8971 --dignet=8 --autoquit=50 >"$LOG/gnet_host.log" 2>&1 &
HOST=$!
sleep 3
godot --headless --path . -- --join=127.0.0.1 --port=8971 --dignet=0 --autoquit=50 >"$LOG/gnet_a.log" 2>&1 &
GA=$!
for _ in $(seq 120); do [ "$(grep -a -c "\[DESTRUCTION-NET\] host map=t_dig " "$LOG/gnet_host.log")" -ge 2 ] && break; sleep 0.25; done
godot --headless --path . -- --join=127.0.0.1 --port=8971 --dignet=0 --autoquit=40 >"$LOG/gnet_b.log" 2>&1 &
GB=$!
wait $GB $GA $HOST
gnet() { grep -a "\[DESTRUCTION-NET\] $1 map=t_dig " "$2" | sed "s/.*\] $1 map=t_dig //" | tr '\n' ';'; }
H=$(gnet host "$LOG/gnet_host.log")
D0=$(echo "$H" | cut -d';' -f1)
DS=$(echo "$H" | cut -d';' -f2)
if [ -z "$D0" ] || [ "$D0" = "$DS" ] || [ "$H" != "$D0;$DS;$D0;$DS;$D0;" ]; then
	fail "host: zły przebieg stref wydobycia ($H)"
else
	ok "host: strefy całe → wykopy i wybuch → wipe (całe) → migawka (wykopy wracają) → wipe"
	grep -a -q -E "\[DIG-NET\] host islands=[1-9][0-9]* settled=true" "$LOG/gnet_host.log" && ok "host: dół w żwirze osypał się, odcięta wyspa w skale spadła, strefy stoją" \
		|| fail "host: wyspa / osypisko ($(grep -a "\[DIG-NET\]" "$LOG/gnet_host.log"))"
	A=$(gnet client "$LOG/gnet_a.log")
	[ "$A" = "$H" ] && ok "klient od początku: te same komórki stref po wykopach, wybuchu, migawce i wipe'ie" || fail "klient A: $A (host: $H)"
	B=$(gnet client "$LOG/gnet_b.log")
	[ "$B" = "$DS;$D0;$DS;$D0;" ] && ok "dołączający po wykopach: gęstość stref z synchronizacji, potem wipe, migawka i wipe jak u hosta" || fail "klient B: $B (host: $H)"
fi

# Błąd GDScript może przerwać pojedynczą korutynę bez niezerowego kodu procesu.
for f in "$LOG"/*.log; do
	if grep -a -E "SCRIPT ERROR|Parse Error" "$f"; then fail "błąd skryptu w $(basename "$f")"; fi
done

[ $rc -eq 0 ] && echo "SIEĆ: WSZYSTKO OK" || echo "SIEĆ: BŁĘDY — logi w $LOG"
exit $rc
