#!/usr/bin/env bash
# Testy broni: jednostkowe (~2,5 min) + sieciowe host/klient (~20 s). Kod wyjścia ≠ 0 przy błędzie.
#   tools/test_weapons.sh            # z katalogu prototype/
# Wymaga `godot` w PATH i zaimportowanego projektu (godot --headless --path . --import).
set -u
cd "$(dirname "$0")/.."
LOG="${TMPDIR:-/tmp}/dead_air_weapon_tests"
mkdir -p "$LOG"
rc=0

echo "== jednostkowe =="
godot --headless --path . -- --host --port=8950 --weapontest --autoquit=220 >"$LOG/unit.log" 2>&1
u=$?
grep -a "\[WTEST\]" "$LOG/unit.log" | grep -a -E "FAIL|====" || true
[ $u -ne 0 ] && rc=1

echo "== sieć (host + klient) =="
godot --headless --path . -- --host --port=8951 --weaptestnet --autoquit=60 >"$LOG/net_host.log" 2>&1 &
HOST=$!
sleep 4
godot --headless --path . -- --join=127.0.0.1 --port=8951 --weaptestclient --autoquit=40 >"$LOG/net_client.log" 2>&1
wait $HOST
n=$?
grep -a "\[WTEST\]" "$LOG/net_host.log" | grep -a -E "FAIL|====" || true
[ $n -ne 0 ] && rc=1

[ $rc -eq 0 ] && echo "WSZYSTKO OK" || echo "BŁĘDY — logi w $LOG"
exit $rc
