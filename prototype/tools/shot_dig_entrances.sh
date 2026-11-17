#!/usr/bin/env bash
# Zrzuty wejść stref wydobycia na 1.1, 1.2 i 1.3 (DIG_ENTRANCE_PLAN.md E5): czoło, osypisko, kilof, odrzwia i pierwszy plan
# w snopie latarki, gracz dwa kafle od czoła. Okno 1920×1080 → zrzut 4K; każdy przebieg osobno (równoległe na jednym katalogu
# zapisu pokazują ekran kalibracji jasności zamiast gry). Wymaga prototype/override.cfg z osobnym katalogiem QA — gra w oknie
# zapisuje profil i złom (patrz tools/shutdown_render_qa.gd). Uruchom: tools/shot_dig_entrances.sh KATALOG [przedrostek] [flagi...]
# np. tools/shot_dig_entrances.sh C:/tmp/dig e5 --shothide=DigTalus
set -u
cd "$(dirname "$0")/.."
OUT="${1:?katalog na zrzuty}"
PRE="${2:-dig}"
shift 2 2>/dev/null || shift $#
if ! grep -q "custom_user_dir" override.cfg 2>/dev/null; then
  echo "Brak prototype/override.cfg z config/use_custom_user_dir — gra w oknie zapisałaby prawdziwy profil." >&2
  exit 2
fi
mkdir -p "$OUT"
GODOT="${GODOT:-godot}"
rc=0
shot() {
  local name="$1"; shift
  timeout 240 "$GODOT" --path . --resolution 1920x1080 -- --host --view3d --nobot --difficulty=normal --shottorch --shotaimleft \
    --shotdelay=6 --shot="$OUT/${PRE}_$name.png" "$@" > "$OUT/${PRE}_$name.log" 2>&1 || rc=1
  if [ -f "$OUT/${PRE}_$name.png" ]; then echo "$OUT/${PRE}_$name.png"; else echo "brak zrzutu $name (log: $OUT/${PRE}_$name.log)" >&2; rc=1; fi
}
shot m1 --mission=z1_m1 --shotclear --shotat=204 --shotrow=42 "$@"
shot m2 --mission=z1_m2 --shotat=149 --shotrow=39 "$@"
shot m3 --mission=z1_m3 --shotclear --shotat=9 --shotrow=39 "$@"
exit $rc
