#!/usr/bin/env bash
# Hook SessionStart (tylko sesje w chmurze): doinstalowuje to, czego potrzebuje projekt — Godot 4.7.2 (testy headless,
# hook gd-check.sh), zależności Pythona narzędzi grafiki/audio oraz Blendera (moduł bpy z PyPI + wrapper `blender`).
# Idempotentny: kolejne uruchomienia pomijają to, co już jest. Synchroniczny — sesja startuje po instalacji.
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

PROJECT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
GODOT_VERSION="4.7.2"
BIN="${GAME_BIN_DIR:-/usr/local/bin}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() { echo "[session-start] $*" >&2; }

# --- Godot --------------------------------------------------------------------------------------------------
if ! command -v godot >/dev/null 2>&1 || ! godot --version 2>/dev/null | grep -q "^$GODOT_VERSION"; then
  log "instaluję Godot $GODOT_VERSION"
  url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  curl -fsSL --retry 3 -o "$TMP/godot.zip" "$url"
  unzip -q -o "$TMP/godot.zip" -d "$TMP"
  install -m 755 "$TMP/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$BIN/godot"
fi

# import zasobów (cache .godot/ jest w .gitignore, więc w nowym klonie trzeba go zrobić raz)
if [ ! -d "$PROJECT/prototype/.godot/imported" ]; then
  log "import zasobów Godota"
  godot --headless --path "$PROJECT/prototype" --import >/dev/null 2>&1 || log "import zakończył się ostrzeżeniami (patrz godot --import)"
fi

# --- Python: narzędzia grafiki/audio -------------------------------------------------------------------------
if ! python3 -c "import numpy, scipy, PIL, matplotlib" >/dev/null 2>&1; then
  log "instaluję zależności Pythona (prototype/tools/requirements.txt)"
  pip install -q -r "$PROJECT/prototype/tools/requirements.txt"
fi

# --- Blender: bpy 5.2.x z PyPI (download.blender.org jest w chmurze blokowany) + wrapper `blender` ---------------
# biblioteki systemowe, bez których render w bpy kończy się abortem (libEGL.so.1 itd.)
if ! ldconfig -p | grep -q "libEGL.so.1"; then
  log "instaluję biblioteki systemowe dla renderu Blendera"
  apt-get install -y -qq libegl1 libgl1 libxrender1 libxi6 libxkbcommon0 libsm6 libxxf86vm1 libxfixes3 libgomp1 >/dev/null 2>&1 || log "apt-get nie powiódł się — render w Blenderze może się wywalać"
fi
if ! pip show bpy >/dev/null 2>&1; then
  log "instaluję bpy (Blender 5.2 jako moduł Pythona, ~400 MB)"
  pip install -q "bpy>=5.2,<5.3"
fi
install -m 755 "$PROJECT/.claude/hooks/blender-shim.py" "$BIN/blender"
sed -i "1s|.*|#!$(command -v python3)|" "$BIN/blender"

log "gotowe: $(godot --version 2>/dev/null | head -1), $(blender --version 2>/dev/null | tail -1)"
