#!/usr/bin/env bash
# Buduje wszystkie bronie 3D skryptem gun_proc.py do prototype/art/char3d/ (z korzenia repo; Blender w PATH albo w zmiennej BLENDER).
#   prototype/tools/gun_proc_all.sh [klucz…] [-- opcje gun_proc.py]     np. prototype/tools/gun_proc_all.sh p64 spread12 -- --tex=1024
# Potem: godot --headless --path prototype --import
set -euo pipefail
cd "$(dirname "$0")/../.."
BL="${BLENDER:-blender}"
keys=()
opts=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; opts=("$@"); break; fi
  keys+=("$1"); shift
done
[ ${#keys[@]} -gt 0 ] || keys=(m83 spread12 p64 srut8 lr7 hkm9 gniew4 sokol6 widmo1 ciegno6 maczeta kilof)
for k in "${keys[@]}"; do
  out=$("$BL" -b --factory-startup -P prototype/tools/gun_proc.py -- "$k" "prototype/art/char3d/gun_$k.glb" "${opts[@]}" 2>&1) || { echo "$out" | tail -20; exit 1; }
  if echo "$out" | grep -qE "Traceback|Error:"; then echo "$out" | grep -E -A8 "Traceback|Error:"; exit 1; fi
  echo "$out" | grep -E "^(TRIS|OK)"
done
