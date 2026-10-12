#!/usr/bin/env bash
# Eksport builda do rozdania graczom: zapisuje skrót commita (wersja buildu w menu i w dzienniku sesji)
# i pilnuje, żeby build miał dźwięk z nagrań (prototype/audio_licensed/, poza repo — patrz AUDIO.md).
#   tools/export_build.sh [Windows|Linux] [--allow-synth]      # z katalogu prototype/ albo z dowolnego innego
# Wymaga `godot` w PATH i szablonów eksportu 4.7.2. Wynik: ../build/<windows|linux>/.
set -eu
cd "$(dirname "$0")/.."
PRESET="${1:-Windows}"
ALLOW_SYNTH=0
[ "${2:-}" = "--allow-synth" ] && ALLOW_SYNTH=1

case "$PRESET" in
  Windows) OUT=../build/windows ;;
  Linux) OUT=../build/linux ;;
  *) echo "Nieznany preset: $PRESET (Windows albo Linux)"; exit 2 ;;
esac

n=$(find audio_licensed -type f \( -name '*.wav' -o -name '*.ogg' \) 2>/dev/null | wc -l)
if [ "$n" -eq 0 ] && [ "$ALLOW_SYNTH" -eq 0 ]; then
  echo "Brak audio_licensed/ w tym drzewie: build zagrałby samą syntezą."
  echo "Odtwórz nagrania (python3 tools/audio_lib_fetch.py sync && python3 tools/bake_audio.py) albo dodaj --allow-synth."
  exit 1
fi
echo "Dźwięk: $n plików z nagrań"

stamp=$(git rev-parse --short HEAD)
git diff --quiet HEAD -- scripts scenes project.godot || stamp="$stamp-dirty"
echo "$stamp" > build_stamp.txt
echo "Build: $(grep -m1 '^config/version=' project.godot | cut -d'"' -f2)+$stamp"

mkdir -p "$OUT"
godot --headless --path . --import
godot --headless --path . --export-release "$PRESET"
echo "Gotowe: $OUT"
