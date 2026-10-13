#!/usr/bin/env bash
# Paczka dla testerów: zip z folderem gry po eksporcie (tools/export_build.sh), z identyfikatorem Steam i instrukcją dla testera.
#   tools/package_build.sh [Windows|Linux]      # z katalogu prototype/ albo z dowolnego innego
# Wynik: ../build/dead-air-87_<wersja>+<commit>_<windows|linux>.zip (folder dead-air-87/ w środku). Wymaga `python` w PATH.
# Instrukcja to tools/testers_readme.txt ({VERSION} = numer wersji i skrót commita ze stopki menu).
set -eu
cd "$(dirname "$0")/.."
PRESET="${1:-Windows}"
case "$PRESET" in
  Windows) DIR=../build/windows; BIN=dead-air-87.exe; TAG=windows ;;
  Linux) DIR=../build/linux; BIN=dead-air-87.x86_64; TAG=linux ;;
  *) echo "Nieznany preset: $PRESET (Windows albo Linux)"; exit 2 ;;
esac
[ -f "$DIR/$BIN" ] || { echo "Brak $DIR/$BIN — najpierw tools/export_build.sh $PRESET"; exit 1; }
[ -f build_stamp.txt ] || { echo "Brak build_stamp.txt — eksportuj skryptem tools/export_build.sh"; exit 1; }
VERSION="$(grep -m1 '^config/version=' project.godot | cut -d'"' -f2)+$(tr -d '\r\n' < build_stamp.txt)"
cp steam_appid.txt "$DIR/"
OUT="../build/dead-air-87_${VERSION}_${TAG}.zip"
python - "$DIR" "$OUT" "$VERSION" tools/testers_readme.txt <<'EOF'
import os
import sys
import zipfile

src, out, version, readme = sys.argv[1:5]
text = open(readme, encoding="utf-8").read().replace("{VERSION}", version)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for name in sorted(os.listdir(src)):
        path = os.path.join(src, name)
        if os.path.isfile(path):
            z.write(path, "dead-air-87/" + name)
    # CRLF i BOM: Notatnik Windows pokaże polskie znaki i podział na wiersze
    z.writestr("dead-air-87/CZYTAJ.txt", ("﻿" + text.replace("\r\n", "\n").replace("\n", "\r\n")).encode("utf-8"))
print("OK %s  %.0f MB" % (out, os.path.getsize(out) / 1048576))
EOF
