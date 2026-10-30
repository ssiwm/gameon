#!/usr/bin/env bash
# Testy sesji sieciowej (headless, ~1 min). Kod wyjścia ≠ 0 przy błędzie.
#   tools/test_net_session.sh        # z katalogu prototype/
# 1. Inna wersja: klient z --fakebuild nie wchodzi do gry (host nie tworzy mu postaci), lobby klienta podaje powód.
# 2. Utrata hosta: klient przeładowuje scenę (jak leave_session), wraca do lobby z komunikatem i nie dołącza ponownie z --join.
# 4. Bez AI towarzysza (NOBOT_PLAN.md): host z --nobot, klient dostaje ustawienie hosta, przy dwóch ludziach nie ma bota.
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
godot --headless --path . -- --host --nobot --port=8964 --callsign=Sowa --printsquad=9 --autoquit=12 >"$LOG/call_host.log" 2>&1 &
HOST=$!
sleep 4
godot --headless --path . -- --join=127.0.0.1 --port=8964 --callsign=sowa --printsquad=7 --autoquit=10 >"$LOG/call_c1.log" 2>&1 &
C1=$!
sleep 1
godot --headless --path . -- --join=127.0.0.1 --port=8964 '--callsign=<b>Wi!lk</b>' --printsquad=6 --autoquit=9 >"$LOG/call_c2.log" 2>&1
wait $C1 $HOST
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

# Błąd GDScript może przerwać pojedynczą korutynę bez niezerowego kodu procesu.
for f in "$LOG"/*.log; do
	if grep -a -E "SCRIPT ERROR|Parse Error" "$f"; then fail "błąd skryptu w $(basename "$f")"; fi
done

[ $rc -eq 0 ] && echo "SIEĆ: WSZYSTKO OK" || echo "SIEĆ: BŁĘDY — logi w $LOG"
exit $rc
