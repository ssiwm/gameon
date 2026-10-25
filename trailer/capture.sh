#!/usr/bin/env bash
# Nagranie klipu z gry przez Godot Movie Maker (klatka po klatce, bez gubienia klatek, z dźwiękiem).
# Użycie: trailer/capture.sh NAZWA KLATKI [SZEROKOŚĆxWYSOKOŚĆ] [FPS] [-- flagi gry...]
#   trailer/capture.sh wolek_corridor 600                      # 10 s w 1920x1080 @ 60
#   trailer/capture.sh stalker 900 2560x1440 60 -- --host --mission=z1_m3 --shotrun
# Wynik: trailer/raw/NAZWA.avi (MJPEG + PCM 48 kHz) i NAZWA.log. Czas nagrania ≈ 9× dłuższy niż klip (+ ~35 s startu).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$HERE/../prototype"
NAME="${1:?podaj nazwę klipu}"
FRAMES="${2:?podaj liczbę klatek (sekundy × fps)}"
RES="${3:-1920x1080}"
FPS="${4:-60}"
shift $(( $# < 4 ? $# : 4 ))
[ "${1:-}" = "--" ] && shift
GAME_ARGS=("$@")
[ ${#GAME_ARGS[@]} -eq 0 ] && GAME_ARGS=(--host --mission=z1_m2)

W="${RES%x*}"; H="${RES#*x}"
mkdir -p "$HERE/raw"

# Rozmiar okna wymusza project.godot (window_*_override), a --resolution go nie przebija. Tymczasowy override.cfg
# ustawia go na czas nagrania; trap sprząta, żeby nie zostawić śladu w repozytorium.
CFG="$PROJECT/override.cfg"
[ -e "$CFG" ] && { echo "override.cfg już istnieje w prototype/ — przerywam, żeby go nie nadpisać"; exit 1; }
printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$W" "$H" > "$CFG"
trap 'rm -f "$CFG"' EXIT

godot --path "$PROJECT" \
  --write-movie "$HERE/raw/$NAME.avi" --fixed-fps "$FPS" --quit-after "$FRAMES" \
  -- "${GAME_ARGS[@]}" > "$HERE/raw/$NAME.log" 2>&1

ffprobe -v error -show_entries stream=codec_type,width,height,r_frame_rate:format=duration -of compact "$HERE/raw/$NAME.avi"
