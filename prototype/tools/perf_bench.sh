#!/usr/bin/env bash
# Pomiar wydajności renderowania (wymaga okna/GPU): konfiguracje × mapy × pozycje kamery. Użycie: tools/perf_bench.sh [SEKUNDY]
#   tools/perf_bench.sh 5        # ~5 s na przebieg; wynik: linie [PERF] z etykietą konfiguracji
set -u
SECS="${1:-5}"
PORT=9400
run() {   # etykieta mapa kolumna flagi...
  local label="$1" map="$2" col="$3"; shift 3
  PORT=$((PORT+1))
  local out
  out=$(timeout 90 godot --path . --windowed -- --port=$PORT --host --mission="$map" --perf="$SECS" --shotat="$col" "$@" 2>&1 | grep -a "\[PERF\]" | head -1)
  printf '%-14s %-6s col=%-4s %s\n' "$label" "$map" "$col" "${out#\[PERF\] }"
}
for m in "z1_m2:12:120:260" "z1_m3:12:90:170"; do
  IFS=: read map c1 c2 c3 <<<"$m"
  for col in $c1 $c2 $c3; do
    run classic "$map" "$col"
    run world "$map" "$col" --newworld
    run all-hd "$map" "$col" --newchar=tripo-hd-male --newgun --newworld --newmon
  done
done
