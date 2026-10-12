#!/usr/bin/env python3
"""Podgląd nagrania źródłowego liczbami: gdzie są zdarzenia (strzały, kroki, warknięcia) i jak brzmią w pomiarze.

Służy do wybierania wycinków do przepisów w bake_hybrid.py bez edytora audio: podaje początki zdarzeń w sekundach,
ich długość, szczyt, czas wybrzmiewania i rozkład energii w pasmach. O brzmieniu i tak decyduje odsłuch (audio_ab.py).

    python tools/audio_probe.py "AK47_big_open"                 # fragment nazwy pliku w katalogu nagrań (regex)
    python tools/audio_probe.py audio/sfx/weapons/m83_shot_1.wav
    python tools/audio_probe.py "BOOT_CONC" --thr -26 --gap 0.15 --max 20
    python tools/audio_probe.py "SIG_P229_9mm_1m" --hits            # początki pojedynczych strzałów w serii
    python tools/audio_probe.py "WINTER Forest night" --steady 20   # najrówniejsze 20-sekundowe okna (materiał na pętlę)
"""
import argparse
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as d  # noqa: E402
import bake_common as bc  # noqa: E402

BANDS = ((20, 80), (80, 250), (250, 1000), (1000, 4000), (4000, 10000), (10000, 24000))


def events(x, thr_db=-30.0, gap=0.12, minlen=0.02):
    """Odcinki powyżej progu liczonego od szczytu pliku: [(start_s, długość_s)]."""
    m = np.abs(x)
    env = np.maximum.reduceat(m, np.arange(0, len(m), 480))            # bloki 10 ms
    on = env > m.max() * d.db_to_lin(thr_db)
    out, start, last = [], None, None
    for i, o in enumerate(on):
        if o:
            start = i if start is None else start
            last = i
        elif start is not None and (i - last) * 0.01 > gap:
            out.append((start * 0.01, (last + 1 - start) * 0.01))
            start = None
    if start is not None:
        out.append((start * 0.01, (last + 1 - start) * 0.01))
    return [e for e in out if e[1] >= minlen]


def hits(x, thr_db=-12.0, min_gap=0.06):
    """Początki uderzeń (strzałów w serii): szczyty obwiedni powyżej progu, rozdzielone o co najmniej min_gap [s]."""
    m = np.abs(x)
    env = np.maximum.reduceat(m, np.arange(0, len(m), 48))             # bloki 1 ms
    thr = env.max() * d.db_to_lin(thr_db)
    out, i, gap = [], 0, int(min_gap * 1000)
    while i < len(env):
        if env[i] > thr:
            j = i + int(np.argmax(env[i:i + 12]))                      # czubek w ciągu 12 ms od przekroczenia progu
            out.append(max(0, d.onset(x[max(0, (j - 12) * 48):(j + 1) * 48], -18.0) + max(0, (j - 12) * 48)) / d.SR)
            i = j + gap
        else:
            i += 1
    return out


def steady(x, win_s, top=3):
    """Najrówniejsze okna długości win_s (materiał na pętlę ambientu): [(start_s, średni poziom dB, rozrzut dB, szczyt−średnia dB)].
    Rozrzut liczony z poziomów w blokach 0,25 s — okno bez wyraźnych zdarzeń ma mały rozrzut i mały odstęp szczytu."""
    blk = d.SR // 4
    nb = len(x) // blk
    lev = np.array([d.lin_to_db(np.sqrt(np.mean(x[i * blk:(i + 1) * blk] ** 2)) + 1e-9) for i in range(nb)])
    w = max(2, int(win_s * 4))
    cands = []
    for i in range(0, nb - w + 1):
        seg = lev[i:i + w]
        cands.append((float(seg.std()) + 0.5 * float(seg.max() - seg.mean()), i))
    out, used = [], []
    for score, i in sorted(cands):
        if all(abs(i - j) >= w // 2 for j in used):
            seg = lev[i:i + w]
            out.append((i / 4.0, float(seg.mean()), float(seg.std()), float(seg.max() - seg.mean())))
            used.append(i)
        if len(out) >= top:
            break
    return out


def features(x):
    n = len(x)
    X = np.abs(np.fft.rfft(x * np.hanning(n))) ** 2
    f = np.fft.rfftfreq(n, 1.0 / d.SR)
    tot = X.sum() + 1e-20
    m = np.abs(x)
    pk = m.max()
    ip = int(np.argmax(m))
    env = np.maximum.reduceat(m, np.arange(0, n, 48))                  # bloki 1 ms

    def below(db):
        idx = np.where(env[ip // 48:] > pk * d.db_to_lin(db))[0]
        return int(idx[-1]) if len(idx) else 0
    return {"pk": d.lin_to_db(pk), "d20": below(-20.0), "d40": below(-40.0), "cen": float((X * f).sum() / tot),
            "bands": [10 * np.log10(X[(f >= a) & (f < b)].sum() / tot + 1e-12) for a, b in BANDS]}


def find(pattern):
    if os.path.exists(pattern):
        return [pattern]
    rx = re.compile(pattern, re.I)
    hits = []
    for dp, _, fs in os.walk(bc.LIB_DIR):
        hits += [os.path.join(dp, f) for f in fs if f.lower().endswith((".wav", ".flac")) and rx.search(os.path.join(dp, f))]
    return sorted(hits)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("pattern")
    ap.add_argument("--thr", type=float, default=-30.0, help="próg zdarzenia [dB od szczytu]")
    ap.add_argument("--gap", type=float, default=0.12, help="cisza rozdzielająca zdarzenia [s]")
    ap.add_argument("--win", type=float, default=1.0, help="okno pomiaru po początku zdarzenia [s]")
    ap.add_argument("--max", type=int, default=16, help="ile zdarzeń pokazać")
    ap.add_argument("--steady", type=float, default=0.0, help="zamiast zdarzeń: najrówniejsze okna tej długości [s] (pętle ambientu)")
    ap.add_argument("--hits", action="store_true", help="zamiast zdarzeń: pojedyncze uderzenia (strzały w serii)")
    ap.add_argument("--hits-thr", type=float, default=-12.0, help="próg uderzenia [dB od szczytu]")
    ap.add_argument("--hits-gap", type=float, default=0.06, help="najmniejszy odstęp uderzeń [s]")
    a = ap.parse_args()
    files = find(a.pattern)
    if not files:
        sys.exit("nic nie pasuje w %s" % bc.LIB_DIR)
    for path in files:
        x = d.read_audio(path)
        ev = events(x, a.thr, a.gap)
        print("%s\n  %.2f s, szczyt %.1f dB, zdarzeń: %d   (pasma: sub low lmid mid high air)" % (
            os.path.relpath(path, bc.LIB_DIR) if path.startswith(bc.LIB_DIR) else path, len(x) / d.SR, d.lin_to_db(d.peak(x)), len(ev)))
        if a.steady > 0.0:
            for t, mean, std, crest in steady(x, a.steady):
                s = x[d.sec(t):d.sec(t + a.steady)]
                ft = features(s)
                print("    równe okno t=%7.2f  poziom=%5.1f dB  rozrzut=%.1f dB  szczyt−śr.=%.1f dB  cen=%5.0f Hz  | %s" % (
                    t, mean, std, crest, ft["cen"], " ".join("%5.1f" % b for b in ft["bands"])))
            continue
        if a.hits:
            hs = hits(x, a.hits_thr, a.hits_gap)
            print("  uderzenia (%d): %s" % (len(hs), " ".join("%.3f" % h for h in hs)))
            for k, h in enumerate(hs[:a.max]):
                end = hs[k + 1] if k + 1 < len(hs) else len(x) / d.SR
                s = x[d.sec(h):d.sec(min(end - 0.004, h + a.win))]
                if len(s) < 64:
                    continue
                ft = features(s)
                print("    t=%7.3f  do nast.=%5.0f ms  pk=%5.1f  d20=%4d ms  cen=%5.0f Hz  | %s" % (
                    h, (end - h) * 1000, ft["pk"], ft["d20"], ft["cen"], " ".join("%5.1f" % b for b in ft["bands"])))
            continue
        for t, ln in ev[:a.max]:
            s = d.from_onset(x[max(0, d.sec(t - 0.03)):d.sec(t + max(ln, a.win))], 1.0)[:d.sec(a.win)]
            if len(s) < 64:
                continue
            ft = features(s)
            print("    t=%7.2f  dł=%5.2f s  pk=%5.1f  d20=%4d ms  d40=%4d ms  cen=%5.0f Hz  | %s" % (
                t, ln, ft["pk"], ft["d20"], ft["d40"], ft["cen"], " ".join("%5.1f" % b for b in ft["bands"])))


if __name__ == "__main__":
    main()
