#!/usr/bin/env bash
# Testy sesji sieciowej (headless, ~1 min). Kod wyjścia ≠ 0 przy błędzie.
#   tools/test_net_session.sh        # z katalogu prototype/
# 1. Inna wersja: klient z --fakebuild nie wchodzi do gry (host nie tworzy mu postaci), lobby klienta podaje powód.
# 2. Utrata hosta: klient przeładowuje scenę (jak leave_session), wraca do lobby z komunikatem i nie dołącza ponownie z --join.
# 4. Bez AI towarzysza (NOBOT_PLAN.md): host z --nobot, klient dostaje ustawienie hosta, przy dwóch ludziach nie ma bota.
# 5. Raport po akcji (RESULTS_PLAN.md): gotowość klienta dochodzi do hosta, poziomy z misji i rozbicie złomu do wszystkich.
# 6. Bateria 4,5 V (BATTERY_PLAN.md): klient z 20% baterii bierze baterię z ziemi — rozstrzyga serwer, dolicza właściciel.
# 7. Ładowarka (BATTERY_PLAN.md B3): klient przy ładowarce B1 ładuje się u siebie, serwer widzi, że ładowarka pracuje.
# 8. Zniszczenia (DESTRUCTION_PLAN.md D0): rany ściany, rozbicie, powrót do migawki z przebudzenia bossa i wipe — u klienta obecnego
#    od początku (RPC na żywo) i u dołączającego po ciosach (`send_walls_to`) stan taki sam jak u hosta.
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
# host: po 10 s rozbija skrzynię Crate1 i tłucze lampę MissionLamp1 (SC), po 1 s dwa ciosy kilofem (S1), gdy są obaj klienci — migawka
# i rozbicie (S2), +3 s powrót do migawki (S1 z zapaloną lampą), +3 s wipe (S0, ściana i skrzynia całe, lampa świeci), +2 s koniec.
# Klient A od początku, klient B dołącza dopiero po ciosach — plamy, HP, rozbitą skrzynię i stłuczoną lampę dostaje z `send_walls_to`.
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
dnet() { grep -a "\[DESTRUCTION-NET\] $1 map=z1_m2 " "$2" | sed "s/.*\] $1 map=z1_m2 //" | tr '\n' ';'; }
H=$(dnet host "$LOG/dnet_host.log")
IFS=';' read -r S0 SC S1 S2 S3 S4 _ <<<"$H"
if [ "${S0% crate=ok lamp=lit}" = "$S0" ] || [ "$SC" != "${S0% crate=ok lamp=lit} crate=gone lamp=out" ] || [ "${S1#*splats=2/}" = "$S1" ] 		|| [ "$S2" != "opened=[BrickWall1] crate=gone lamp=out" ] || [ "$S3" != "${S1% lamp=out} lamp=lit" ] || [ "$S4" != "$S0" ]; then
	fail "host: zły przebieg ($H)"
else
	ok "host: cała → skrzynia rozbita, lampa stłuczona → ranna → rozbita → ranna, lampa świeci (migawka) → cała ze skrzynią (wipe)"
	A=$(dnet client "$LOG/dnet_a.log")
	[ "$A" = "$H" ] && ok "klient od początku: te same plamy, HP, rozbicie, skrzynia, migawka i wipe co host" || fail "klient A: $A (host: $H)"
	B=$(dnet client "$LOG/dnet_b.log")
	[ "$B" = "$S1;$S2;$S3;$S4;" ] && ok "dołączający po ciosach: plamy, HP, rozbita skrzynia i stłuczona lampa z synchronizacji, potem rozbicie, migawka i wipe jak u hosta" || fail "klient B: $B (host: $H)"
fi

# Błąd GDScript może przerwać pojedynczą korutynę bez niezerowego kodu procesu.
for f in "$LOG"/*.log; do
	if grep -a -E "SCRIPT ERROR|Parse Error" "$f"; then fail "błąd skryptu w $(basename "$f")"; fi
done

[ $rc -eq 0 ] && echo "SIEĆ: WSZYSTKO OK" || echo "SIEĆ: BŁĘDY — logi w $LOG"
exit $rc
