#!/usr/bin/env bash
# Odtwarza sprite'y przedmiotów HD (art/items/): modele proceduralne (items_proc_bake.py) + warsztat i złom z Tripo (art_src/world/tripo/*.glb) → pack_items_hd.py.
# Wymaga: blender w PATH oraz Pythona z Pillow i numpy (domyślnie `python3`; inny: PYTHON=ścieżka).
set -euo pipefail
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/items" "$TMP/tp"
blender -b --factory-startup -P prototype/tools/concept/items_proc_bake.py -- "$TMP/items" "$@" | grep -E "^OK|Error|Traceback" || true
# warsztat (30 wp szerokości, kamera +X, 24 px/wp) i kupka złomu (14 wp, 32 px/wp)
blender -b --factory-startup -P prototype/tools/concept/prop_tripo_bake.py -- art_src/world/tripo/workshop.glb "$TMP/tp/workshop" +X 30 32 22 24 | grep -E "^INFO|Error|Traceback" || true
blender -b --factory-startup -P prototype/tools/concept/prop_tripo_bake.py -- art_src/world/tripo/scrap_pile.glb "$TMP/tp/scrap_pile" +X 14 15 11 32 | grep -E "^INFO|Error|Traceback" || true
"$PY" prototype/tools/pack_items_hd.py "$TMP/items" "$@" --extra=workshop:"$TMP/tp/workshop":24:+X --extra=scrap_pile:"$TMP/tp/scrap_pile":32:+X
