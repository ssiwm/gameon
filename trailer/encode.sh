#!/usr/bin/env bash
# Surowy klip z capture.sh → MP4 (H.264 + AAC 48 kHz), dźwięk do -14 LUFS / true peak -1 dBTP (loudnorm w dwóch przebiegach).
# Użycie: trailer/encode.sh WEJŚCIE.avi [WYJŚCIE.mp4] [CRF]
#   Opcjonalnie MUSIC=plik.wav podmienia ścieżkę dźwiękową (nagranie z gry zostaje wyciszone do -18 dB pod muzyką).
set -euo pipefail

IN="${1:?podaj plik wejściowy}"
OUT="${2:-${IN%.*}.mp4}"
CRF="${3:-14}"
LN="I=-14:TP=-1:LRA=11"

if [ -n "${MUSIC:-}" ]; then
  INPUTS=(-i "$IN" -i "$MUSIC")
  MIX="[0:a]volume=-18dB[g];[1:a][g]amix=inputs=2:duration=first:normalize=0"
else
  INPUTS=(-i "$IN")
  MIX="[0:a]anull"
fi

# Przebieg 1: pomiar.
STATS=$(ffmpeg -nostats -hide_banner "${INPUTS[@]}" -filter_complex "${MIX},loudnorm=${LN}:print_format=json[a]" -map "[a]" -f null - 2>&1 | sed -n '/^{/,/^}/p')
get() { echo "$STATS" | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p"; }
MEAS="measured_I=$(get input_i):measured_TP=$(get input_tp):measured_LRA=$(get input_lra):measured_thresh=$(get input_thresh):offset=$(get target_offset)"

# Przebieg 2: normalizacja liniowa z pomiarem + kodowanie.
ffmpeg -v error -y "${INPUTS[@]}" \
  -filter_complex "${MIX},loudnorm=${LN}:${MEAS}:linear=true,aresample=48000[a]" \
  -map 0:v -map "[a]" -c:v libx264 -preset slow -crf "$CRF" -pix_fmt yuv420p \
  -c:a aac -b:a 256k -movflags +faststart "$OUT"
echo "$OUT"
