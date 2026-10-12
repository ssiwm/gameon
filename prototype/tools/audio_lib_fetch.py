#!/usr/bin/env python3
"""Pobiera POJEDYNCZE nagrania z oficjalnych paczek Sonniss GDC (bez ściągania całych archiwów po kilka GB).

Archiwa leżą na serwerze Sonniss jako pliki ZIP; serwer obsługuje żądania zakresu (HTTP Range), więc wystarczy
wczytać spis treści z końca archiwum i dociągnąć wybrane pliki. Tylko stdlib.

    python prototype/tools/audio_lib_fetch.py index 2020            # spis plików rocznika → <lib>/_index/sonniss_2020.json
    python prototype/tools/audio_lib_fetch.py find "gun|rifle"      # szukaj w pobranych spisach (regex, bez rozróżniania wielkości liter)
    python prototype/tools/audio_lib_fetch.py get 2020 "AK47.*Close"  # pobierz pasujące pliki → <lib>/sonniss/2020/<paczka>/<plik>
    python prototype/tools/audio_lib_fetch.py sha <ścieżka względem lib>   # SHA-256 do wpisania w tools/audio_sources.json

<lib> = zmienna DA87_AUDIO_LIB albo art_src/audio_lib/ (w .gitignore).

LICENCJA (Sonniss GDC Bundle License 2.0, https://sonniss.com/gdc-bundle-license/): wolno używać i przerabiać w projektach
własnych, także komercyjnych, bez podawania autora. NIE wolno udostępniać tych dźwięków innym jako efektów dźwiękowych —
także przerobionych — ani trenować na nich modeli AI. Dlatego pliki źródłowe nie trafiają do repo.
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys
import urllib.request
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIB = os.environ.get("DA87_AUDIO_LIB") or os.path.join(REPO, "art_src", "audio_lib")
HOST = "https://downloads.sonniss.com/"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# rocznik → (wzorzec nazwy archiwum, liczba części); nazwy ze strony https://sonniss.com/gameaudiogdc i https://gdc.sonniss.com/
YEARS = {
    2026: ("Sonniss.com-GDC2026-GameAudioBundle%dof5.zip", 5),
    2024: ("Sonniss.com-GDC2024-GameAudioBundle%dof9.zip", 9),
    2023: ("Sonniss.com-GDC2023-GameAudioBundle%dof14.zip", 14),
    2020: ("Sonniss.com%%20-%%20GDC%%202020%%20-%%20Game%%20Audio%%20Bundle%%20Part%dof14.zip", 14),
    2019: ("Sonniss.com%%20-%%20GDC%%202019%%20-%%20Game%%20Audio%%20Bundle%%20Part%%20%dof8.zip", 8),
    2018: ("Sonniss.com%%20-%%20GDC%%202018%%20-%%20Game%%20Audio%%20Bundle%%20Part%%20%dof8.zip", 8),
    2017: ("Sonniss.com%%20-%%20GDC%%202017%%20-%%20Game%%20Audio%%20Bundle%%20Part%%20%dof9.zip", 9),
    2016: ("Sonniss.com%%20-%%20GDC%%202016-%%20Game%%20Audio%%20Bundle%%20Part%%20%dof6.zip", 6),
}


class HttpFile(io.RawIOBase):
    """Plik tylko do odczytu nad HTTP Range — tyle, ile potrzebuje zipfile (seek/tell/read)."""

    def __init__(self, url):
        self.url = url
        self.pos = 0
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=60) as r:
            cr = r.headers.get("Content-Range", "")
            if r.status != 206 or "/" not in cr:
                raise OSError("serwer nie obsługuje żądań zakresu: " + url)
            self.size = int(cr.rsplit("/", 1)[1])

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def readinto(self, b):
        n = min(len(b), self.size - self.pos)
        if n <= 0:
            return 0
        req = urllib.request.Request(self.url, headers={"User-Agent": UA, "Range": "bytes=%d-%d" % (self.pos, self.pos + n - 1)})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                break
            except OSError:
                if attempt == 3:
                    raise
        b[:len(data)] = data
        self.pos += len(data)
        return len(data)


def _open_zip(year, part):
    pat, _ = YEARS[year]
    return zipfile.ZipFile(io.BufferedReader(HttpFile(HOST + pat % part), buffer_size=1 << 20))


def _index_path(year):
    return os.path.join(LIB, "_index", "sonniss_%d.json" % year)


def cmd_index(year):
    out = []
    for part in range(1, YEARS[year][1] + 1):
        with _open_zip(year, part) as z:
            for i in z.infolist():
                if not i.is_dir():
                    out.append({"part": part, "name": i.filename, "size": i.file_size})
        print("  część %d/%d: razem %d plików" % (part, YEARS[year][1], len(out)), flush=True)
    os.makedirs(os.path.dirname(_index_path(year)), exist_ok=True)
    with open(_index_path(year), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=0, ensure_ascii=False)
    print("OK %s: %d plików, %.1f GB" % (_index_path(year), len(out), sum(e["size"] for e in out) / 2 ** 30))


def _load_index(year):
    if not os.path.exists(_index_path(year)):
        sys.exit("brak spisu rocznika %d — najpierw: audio_lib_fetch.py index %d" % (year, year))
    with open(_index_path(year), encoding="utf-8") as f:
        return json.load(f)


def cmd_find(pattern, year=None, limit=80):
    rx = re.compile(pattern, re.I)
    n = 0
    for y in ([year] if year else sorted(YEARS)):
        if not os.path.exists(_index_path(y)):
            continue
        for e in _load_index(y):
            if rx.search(e["name"]) and e["name"].lower().endswith((".wav", ".flac", ".aif", ".aiff")):
                n += 1
                if n <= limit:
                    print("%d  %6.1f MB  %s" % (y, e["size"] / 2 ** 20, e["name"]))
    print("%d trafień%s" % (n, "" if n <= limit else " (pokazano %d)" % limit))


def _safe_rel(name):
    """Ścieżka z archiwum → ścieżka względna bez wyjścia poza katalog docelowy."""
    parts = [p for p in name.replace("\\", "/").split("/") if p not in ("", ".", "..")]
    return "/".join(re.sub(r'[<>:"|?*]', "_", p).strip() for p in parts)


def cmd_get(year, patterns, max_mb=400.0):
    rxs = [re.compile(p, re.I) for p in patterns]
    want = [e for e in _load_index(year) if any(r.search(e["name"]) for r in rxs)]
    total = sum(e["size"] for e in want) / 2 ** 20
    if not want:
        sys.exit("nic nie pasuje")
    if total > max_mb:
        sys.exit("pasuje %d plików, %.0f MB — ponad limit %.0f MB (zawęź wzorzec albo podaj --max-mb)" % (len(want), total, max_mb))
    by_part = {}
    for e in want:
        by_part.setdefault(e["part"], []).append(e)
    for part, items in sorted(by_part.items()):
        with _open_zip(year, part) as z:
            for e in items:
                rel = "sonniss/%d/%s" % (year, _safe_rel(e["name"]))
                dst = os.path.join(LIB, *rel.split("/"))
                if os.path.exists(dst) and os.path.getsize(dst) == e["size"]:
                    print("  jest   %s" % rel)
                    continue
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with z.open(e["name"]) as src, open(dst + ".part", "wb") as out:
                    while True:
                        blk = src.read(1 << 20)
                        if not blk:
                            break
                        out.write(blk)
                os.replace(dst + ".part", dst)
                print("  pobrano %5.1f MB  %s" % (e["size"] / 2 ** 20, rel), flush=True)
    print("OK %d plików, %.0f MB w %s" % (len(want), total, LIB))


def cmd_sha(rel):
    h = hashlib.sha256()
    with open(os.path.join(LIB, *rel.replace("\\", "/").split("/")), "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    print(h.hexdigest())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("index")
    i.add_argument("year", type=int, choices=sorted(YEARS))
    f = sub.add_parser("find")
    f.add_argument("pattern")
    f.add_argument("--year", type=int, choices=sorted(YEARS))
    f.add_argument("--limit", type=int, default=80)
    g = sub.add_parser("get")
    g.add_argument("year", type=int, choices=sorted(YEARS))
    g.add_argument("patterns", nargs="+")
    g.add_argument("--max-mb", type=float, default=400.0)
    s = sub.add_parser("sha")
    s.add_argument("rel")
    a = ap.parse_args()
    if a.cmd == "index":
        cmd_index(a.year)
    elif a.cmd == "find":
        cmd_find(a.pattern, a.year, a.limit)
    elif a.cmd == "get":
        cmd_get(a.year, a.patterns, a.max_mb)
    else:
        cmd_sha(a.rel)


if __name__ == "__main__":
    main()
