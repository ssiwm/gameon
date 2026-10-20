#!/usr/bin/env bash
# Buduje modele części broni (gun_proc.py --part, PART_BUILDERS) do prototype/art/char3d/gunpart_<id>.glb + .json (z korzenia repo;
# Blender w PATH albo w zmiennej BLENDER). Bez argumentów — wszystkie części z modelem; z argumentami — tylko podane id.
#   prototype/tools/gun_parts_all.sh [id…] [-- opcje gun_proc.py]     np. prototype/tools/gun_parts_all.sh m83_pbs1 -- --tex=1024
# Część buduje się w układzie swojej broni, więc po zmianie broni bazowej (gun_proc_all.sh) trzeba przebudować też jej części.
# Potem: godot --headless --path prototype --import, python prototype/tools/tex_vram.py i jeszcze raz import (CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")/../.."
BL="${BLENDER:-blender}"
ids=()
opts=(--tex=1024)
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; opts=("$@"); break; fi
  ids+=("$1"); shift
done
[ ${#ids[@]} -gt 0 ] || ids=(m83_rpk40 m83_drum75 m83_rpkbar m83_short m83_pbs1 m83_hider m83_akms p64_supp sp12_drum30 sp12_box8 sp12_ported)
for id in "${ids[@]}"; do
  case "$id" in
    m83_*) key=m83 ;;
    p64_*) key=p64 ;;
    sp12_*) key=spread12 ;;
    *) echo "nieznana broń części $id"; exit 1 ;;
  esac
  out=$("$BL" -b --factory-startup -P prototype/tools/gun_proc.py -- "$key" "prototype/art/char3d/gunpart_$id.glb" --part="$id" "${opts[@]}" 2>&1) || { echo "$out" | tail -20; exit 1; }
  if echo "$out" | grep -qE "Traceback|Error:"; then echo "$out" | grep -E -A8 "Traceback|Error:"; exit 1; fi
  echo "$out" | grep -E "^(TRIS|OK)"
done
