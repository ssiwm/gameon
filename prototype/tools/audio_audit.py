"""
audio_audit.py — pomiar jakości biblioteki dźwięków (stdlib + ffmpeg).

Uruchomienie:
    python3 tools/audio_audit.py                  # tabela + werdykty, zapis audit_report.json
    python3 tools/audio_audit.py --json out.json  # inny plik wynikowy
    python3 tools/audio_audit.py --compare a.json b.json   # różnice przed/po
    python3 tools/audio_audit.py --only music amb          # tylko wybrane katalogi

Co mierzy (na każdym WAV):
    LUFS (EBU R128 przez ffmpeg), true peak, RMS, crest factor, DC offset,
    liczba próbek na 0 dBFS (clipping), cisza na początku/końcu, szew pętli
    (skok na styku koniec→początek vs typowy skok między próbkami),
    rozkład energii w pasmach, rolloff 95%, korelację L/R i zgodność z mono,
    różnorodność wariantów rodziny (odległość widmowa).

Werdykty to progi jakościowe „AAA-ish" — patrz THRESHOLDS. Narzędzie niczego nie
zmienia w assetach; służy do tego, żeby overhaul miał liczby przed i po.
"""

from __future__ import annotations

import cmath
import json
import math
import os
import re
import statistics
import subprocess
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "audio")
BANK = os.path.join(AUDIO, "_bank.json")

BANDS = (("sub", 20, 80), ("low", 80, 250), ("lmid", 250, 1000),
         ("mid", 1000, 4000), ("high", 4000, 10000), ("air", 10000, 24000))

THRESHOLDS = {
    "clip_samples": 0,          # żadnej próbki na pełnej skali
    "dc_abs": 0.002,            # składowa stała
    "loop_seam_ratio": 6.0,     # skok szwu / mediana skoków międzypróbkowych
    "oneshot_tail_abs": 0.004,  # ostatnia próbka one-shota
    "mono_compat_db": -3.0,     # spadek energii po zsumowaniu do mono
    "true_peak_db": -1.0,
}


# ------------------------------------------------------------------ IO

def read_wav(path: str):
    with wave.open(path, "rb") as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    assert sw == 2, "oczekuję 16-bit PCM: %s" % path
    import array
    a = array.array("h")
    a.frombytes(raw)
    if sys.byteorder == "big":
        a.byteswap()
    data = [x / 32768.0 for x in a]
    if ch == 1:
        return [data], sr
    return [data[0::2], data[1::2]], sr


def fft(x: list) -> list:
    """Iteracyjny radix-2 (len(x) = potęga 2)."""
    n = len(x)
    j = 0
    a = [complex(v) for v in x]
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    size = 2
    while size <= n:
        w_m = cmath.exp(-2j * math.pi / size)
        half = size // 2
        for k in range(0, n, size):
            w = 1.0 + 0j
            for m in range(half):
                u = a[k + m]
                v = a[k + m + half] * w
                a[k + m] = u + v
                a[k + m + half] = u - v
                w *= w_m
        size <<= 1
    return a


def spectrum(mono: list, sr: int, win: int = 4096, frames: int = 6) -> list:
    """Uśrednione widmo mocy z kilku okien Hanna rozłożonych równomiernie."""
    n = len(mono)
    if n < win:
        mono = mono + [0.0] * (win - n)
        n = win
    hann = [0.5 - 0.5 * math.cos(2 * math.pi * i / (win - 1)) for i in range(win)]
    acc = [0.0] * (win // 2)
    starts = [0] if frames == 1 else [int(i * (n - win) / (frames - 1)) for i in range(frames)]
    for s in dict.fromkeys(starts):
        seg = [mono[s + i] * hann[i] for i in range(win)]
        f = fft(seg)
        for k in range(win // 2):
            acc[k] += (f[k].real ** 2 + f[k].imag ** 2)
    return [v / max(1, len(starts)) for v in acc]


def band_energy(spec: list, sr: int, win: int = 4096) -> dict:
    hz = sr / win
    tot = sum(spec) or 1e-30
    out = {}
    for name, lo, hi in BANDS:
        a, b = int(lo / hz), min(len(spec), int(hi / hz))
        out[name] = sum(spec[a:b]) / tot
    acc, roll = 0.0, 0.0
    for k, v in enumerate(spec):
        acc += v
        if acc >= 0.95 * tot:
            roll = k * hz
            break
    out["rolloff95"] = roll
    cen = sum(k * hz * v for k, v in enumerate(spec)) / tot
    out["centroid"] = cen
    return out


def db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-9))


def ebur128(path: str) -> dict:
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af",
                        "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True)
    t = p.stderr
    m = t.rfind("Summary:")
    s = t[m:] if m >= 0 else t
    def g(pat):
        r = re.search(pat, s)
        return float(r.group(1)) if r else None
    return {"lufs": g(r"I:\s+(-?[\d.]+) LUFS"), "lra": g(r"LRA:\s+(-?[\d.]+) LU"),
            "tp": g(r"Peak:\s+(-?[\d.]+) dBFS")}


# ------------------------------------------------------------------ analiza jednego pliku

def analyze(path: str, is_loop: bool) -> dict:
    ch, sr = read_wav(path)
    mono = ch[0] if len(ch) == 1 else [(a + b) * 0.5 for a, b in zip(ch[0], ch[1])]
    n = len(ch[0])
    allv = ch[0] + (ch[1] if len(ch) == 2 else [])
    peak = max(max(allv), -min(allv))
    rms = math.sqrt(sum(x * x for x in allv) / len(allv))
    dc = sum(allv) / len(allv)
    clip = sum(1 for x in allv if abs(x) >= 0.99997)
    # cisza na brzegach (próg −60 dBFS)
    thr = 10 ** (-60 / 20)
    lead = next((i for i, x in enumerate(mono) if abs(x) > thr), n)
    trail = next((i for i, x in enumerate(reversed(mono)) if abs(x) > thr), n)
    # szew pętli
    diffs = sorted(abs(mono[i + 1] - mono[i]) for i in range(0, n - 1, max(1, n // 20000)))
    med = diffs[len(diffs) // 2] if diffs else 0.0
    p90 = diffs[int(len(diffs) * 0.9)] if diffs else 0.0
    seam = abs(mono[0] - mono[-1])
    seam_ratio = seam / max(med, 1e-6)
    spec = spectrum(mono, sr)
    r = {
        "dur": n / sr, "ch": len(ch), "sr": sr, "loop": is_loop,
        "peak_db": db(peak), "rms_db": db(rms), "crest_db": db(peak) - db(rms),
        "dc": dc, "clip": clip,
        "lead_ms": lead / sr * 1000, "trail_ms": trail / sr * 1000,
        "end_abs": abs(mono[-1]), "start_abs": abs(mono[0]),
        "seam_ratio": seam_ratio, "step_p90": p90,
        "bands": band_energy(spec, sr),
    }
    if len(ch) == 2:
        l, rr = ch
        el = sum(x * x for x in l)
        er = sum(x * x for x in rr)
        em = sum((a + b) ** 2 * 0.25 for a, b in zip(l, rr))
        den = math.sqrt(el * er) or 1e-30
        r["lr_corr"] = sum(a * b for a, b in zip(l, rr)) / den
        r["mono_loss_db"] = 10 * math.log10(max(em, 1e-30) / max((el + er) * 0.5, 1e-30))
    r.update(ebur128(path))
    return r


# ------------------------------------------------------------------ werdykty

def verdicts(key: str, r: dict) -> list:
    v = []
    T = THRESHOLDS
    if r["clip"] > T["clip_samples"]:
        v.append("CLIP(%d)" % r["clip"])
    if abs(r["dc"]) > T["dc_abs"]:
        v.append("DC(%.4f)" % r["dc"])
    if r["loop"] and r["seam_ratio"] > T["loop_seam_ratio"]:
        v.append("SEAM(x%.0f)" % r["seam_ratio"])
    if not r["loop"] and r["end_abs"] > T["oneshot_tail_abs"]:
        v.append("TAIL-CUT(%.4f)" % r["end_abs"])
    if r["ch"] == 2 and r.get("mono_loss_db", 0) < T["mono_compat_db"]:
        v.append("MONO(%.1fdB)" % r["mono_loss_db"])
    if r.get("tp") is not None and r["tp"] > T["true_peak_db"]:
        v.append("TP(%.1f)" % r["tp"])
    if not r["loop"] and r["lead_ms"] > 25:
        v.append("LEAD(%dms)" % r["lead_ms"])
    return v


def family(key: str) -> str | None:
    m = re.match(r"^(.*)_(\d+)$", key)
    return m.group(1) if m else None


def log_vec(r: dict) -> list:
    return [math.log10(max(r["bands"][n], 1e-6)) for n, _, _ in BANDS]


def diversity(rows: dict) -> dict:
    fams: dict = {}
    for k in rows:
        f = family(k)
        if f:
            fams.setdefault(f, []).append(k)
    out = {}
    for f, ks in fams.items():
        if len(ks) < 2:
            continue
        ds = []
        for i in range(len(ks)):
            for j in range(i + 1, len(ks)):
                a, b = log_vec(rows[ks[i]]), log_vec(rows[ks[j]])
                ds.append(math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b))))
        dur = [rows[k]["dur"] for k in ks]
        out[f] = {"n": len(ks), "spectral_dist": statistics.mean(ds),
                  "dur_spread": (max(dur) - min(dur)) / max(statistics.mean(dur), 1e-6),
                  "rms_spread_db": max(rows[k]["rms_db"] for k in ks) - min(rows[k]["rms_db"] for k in ks)}
    return out


# ------------------------------------------------------------------ main

def load_bank() -> dict:
    with open(BANK, encoding="utf-8") as f:
        return json.load(f)


def run(only: list | None) -> dict:
    bank = load_bank()
    rows = {}
    for key in sorted(bank):
        path, loop = bank[key]
        if only and path.split("/")[0] not in only and path.split("/")[1] not in only:
            continue
        full = os.path.join(AUDIO, path + ".wav")
        if not os.path.exists(full):
            continue
        rows[key] = analyze(full, bool(loop))
        rows[key]["path"] = path
    return rows


def show(rows: dict) -> None:
    print("%-22s %5s %2s %6s %6s %6s %6s %7s  %s" % (
        "asset", "dur", "ch", "peak", "rms", "LUFS", "crest", "centr", "uwagi"))
    flagged = 0
    for k, r in rows.items():
        v = verdicts(k, r)
        flagged += bool(v)
        lufs = "%6.1f" % r["lufs"] if r.get("lufs") not in (None, -70.0) else "     -"
        print("%-22s %5.2f %2d %6.1f %6.1f %s %6.1f %7.0f  %s%s" % (
            k, r["dur"], r["ch"], r["peak_db"], r["rms_db"], lufs, r["crest_db"],
            r["bands"]["centroid"], " ".join(v), "  [loop]" if r["loop"] else ""))
    print("-" * 100)
    print("assetów: %d, z uwagami: %d" % (len(rows), flagged))


def compare(a_path: str, b_path: str) -> None:
    a, b = json.load(open(a_path))["rows"], json.load(open(b_path))["rows"]
    print("%-22s %10s %10s %10s %10s" % ("asset", "rms A", "rms B", "centr A", "centr B"))
    for k in sorted(set(a) & set(b)):
        print("%-22s %10.1f %10.1f %10.0f %10.0f" % (
            k, a[k]["rms_db"], b[k]["rms_db"], a[k]["bands"]["centroid"], b[k]["bands"]["centroid"]))
    fa = sum(1 for k in a if verdicts(k, a[k]))
    fb = sum(1 for k in b if verdicts(k, b[k]))
    print("z uwagami: A=%d B=%d" % (fa, fb))


def main() -> int:
    if "--compare" in sys.argv:
        i = sys.argv.index("--compare")
        compare(sys.argv[i + 1], sys.argv[i + 2])
        return 0
    out = "audit_report.json"
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1:]
    rows = run(only)
    show(rows)
    div = diversity(rows)
    print("\nRÓŻNORODNOŚĆ WARIANTÓW (spectral_dist <0.25 = brzmią prawie identycznie)")
    for f, d in sorted(div.items(), key=lambda kv: kv[1]["spectral_dist"]):
        print("  %-18s n=%d  spectral=%.2f  dur±=%.0f%%  rms±=%.1fdB" % (
            f, d["n"], d["spectral_dist"], d["dur_spread"] * 100, d["rms_spread_db"]))
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"rows": rows, "diversity": div}, f, indent=1)
    print("zapisano: %s" % out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
