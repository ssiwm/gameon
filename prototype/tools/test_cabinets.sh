#!/usr/bin/env bash
# Regresje gablot i rzeczywiste RPC ENet, w dwóch procesach. Uruchom z dowolnego katalogu.
set -u
cd "$(dirname "$0")/.."
LOG="${TMPDIR:-/tmp}/dead_air_weapon_tests"
mkdir -p "$LOG"
rc=0

godot --headless --path . -- --host --port=8953 --cabinettest --autoquit=40 >"$LOG/cabinet.log" 2>&1 || rc=1
godot --headless --path . -- --host --port=8954 --cabinetnet --autoquit=55 >"$LOG/cabinet_host.log" 2>&1 &
host_pid=$!
trap 'kill "$host_pid" 2>/dev/null || true' EXIT
sleep 4
godot --headless --path . -- --join=127.0.0.1 --port=8954 --cabinetnet --autoquit=45 >"$LOG/cabinet_client.log" 2>&1 || rc=1
wait "$host_pid" || rc=1
trap - EXIT

for test_log in "$LOG/cabinet.log" "$LOG/cabinet_host.log" "$LOG/cabinet_client.log"; do
  if grep -a -E 'SCRIPT ERROR|Parse Error|\[CABINET-TEST\] FAIL' "$test_log"; then rc=1; fi
  grep -a -E '\[CABINET-TEST\] ==== .*błędów: 0' "$test_log" || rc=1
done
exit "$rc"
