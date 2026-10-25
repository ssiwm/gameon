#!/usr/bin/env bash
# Kontrola jakości gotowego pliku wg quality_bar z motion_director_prompt.md.
# Użycie: trailer/qa.sh FILM.mp4 [OCZEKIWANA_DŁUGOŚĆ_S]
# Drukuje: wymiary / fps / długość, głośność (LUFS, true peak), zamrożone odcinki; zapisuje arkusz kontaktowy FILM_sheet.png.
set -euo pipefail

F="${1:?podaj plik}"
EXPECT="${2:-}"
BASE="${F%.*}"

echo "== strumienie"
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate:format=duration -of compact "$F"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$F")
if [ -n "$EXPECT" ]; then
  awk -v d="$DUR" -v e="$EXPECT" 'BEGIN{ if (d-e<0.05 && e-d<0.05) print "długość OK: " d " s"; else print "DŁUGOŚĆ ZŁA: " d " s, oczekiwano " e " s" }'
fi

echo "== głośność (cel: ok. -14 LUFS, TP <= -1 dBTP)"
ffmpeg -nostats -i "$F" -af ebur128=peak=true -f null - 2>&1 | awk '/Summary:/{s=1} s && /I:|Peak:/' | sed 's/^ *//'

echo "== zamrożone odcinki (cel: <=1 s na 30 s, żaden >0,5 s)"
FROZEN=$(ffmpeg -nostats -i "$F" -vf "freezedetect=n=-60dB:d=0.5" -an -f null - 2>&1 | grep -c freeze_start || true)
echo "odcinków nieruchomych >0,5 s: $FROZEN"

echo "== arkusz kontaktowy ${BASE}_sheet.png"
N=$(awk -v d="$DUR" 'BEGIN{ n=int(d/1.5); if(n<8)n=8; if(n>20)n=20; print n }')
ffmpeg -v error -y -i "$F" -vf "fps=${N}/${DUR},scale=480:-1,tile=5x$(( (N+4)/5 ))" -frames:v 1 "${BASE}_sheet.png"
echo "${BASE}_sheet.png"
