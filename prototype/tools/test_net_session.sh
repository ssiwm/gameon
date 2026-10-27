#!/usr/bin/env bash
# Testy sesji sieciowej (headless, ~1 min). Kod wyjścia ≠ 0 przy błędzie.
#   tools/test_net_session.sh        # z katalogu prototype/
# 1. Inna wersja: klient z --fakebuild nie wchodzi do gry (host nie tworzy mu postaci), lobby klienta podaje powód.
# 2. Utrata hosta: klient przeładowuje scenę (jak leave_session), wraca do lobby z komunikatem i nie dołącza ponownie z --join.
# 3. Czterech ludzi: numery P1–P4 (bot nie zabiera numeru, P5 się nie pojawia).
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
godot --headless --path . -- --host --port=8962 --autoquit=30 >"$LOG/four_host.log" 2>&1 &
HOST=$!
sleep 4
CLIENTS=()
for i in 1 2 3; do
	godot --headless --path . -- --join=127.0.0.1 --port=8962 --autoquit=$((24 - 2 * i)) >"$LOG/four_c$i.log" 2>&1 &
	CLIENTS+=($!)
	sleep 2
done
wait "${CLIENTS[@]}" $HOST
for n in 2 3 4; do
	grep -a -q "\[NET\] spawned player [0-9]* (display P$n)" "$LOG/four_host.log" && ok "człowiek dostaje P$n" || fail "żaden człowiek nie dostał P$n"
done
grep -a -q "display P[5-9]" "$LOG/four_host.log" && fail "numer ponad P4 przy czterech ludziach" || ok "bez numerów ponad P4"
grep -a -q "\[BOT\] spawned companion slot 4" "$LOG/four_host.log" && ok "bot zajmuje najwyższy wolny numer (P4)" || fail "bot nie wziął P4"

# Błąd GDScript może przerwać pojedynczą korutynę bez niezerowego kodu procesu.
for f in "$LOG"/*.log; do
	if grep -a -E "SCRIPT ERROR|Parse Error" "$f"; then fail "błąd skryptu w $(basename "$f")"; fi
done

[ $rc -eq 0 ] && echo "SIEĆ: WSZYSTKO OK" || echo "SIEĆ: BŁĘDY — logi w $LOG"
exit $rc
