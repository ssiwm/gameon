"""
audio_view.py — arkusz kontaktowy: przebieg + spektrogram wybranych assetów (PNG).

    python3 tools/audio_view.py out.png m83_shot_1 p64_shot_1 spread12_shot_1 ...
    python3 tools/audio_view.py out.png --dir audio/sfx/weapons          # cały katalog

Bez słuchu to najszybszy sposób, żeby ZOBACZYĆ obwiednię, widmo, ogon i szwy pętli.
Wymaga matplotlib (tylko do podglądu, nie do bake'u).
"""
import json, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import signal as sg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "audio")

def load(path):
    import wave
    with wave.open(path) as w:
        n, ch, sr = w.getnframes(), w.getnchannels(), w.getframerate()
        a = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
    return (a.reshape(-1, ch).T if ch == 2 else a[None, :]), sr

def main():
    out = sys.argv[1]
    bank = {}
    for dp, _, fs in os.walk(AUDIO):
        for f in fs:
            if f.endswith(".wav"):
                rel = os.path.relpath(os.path.join(dp, f), AUDIO)[:-4].replace("\\", "/")
                bank[f[:-4]] = [rel, 1 if f.endswith("_loop.wav") or rel.startswith(("amb/", "music/mus_")) else 0]
    keys = []
    args = sys.argv[2:]
    if args and args[0] == "--dir":
        pre = os.path.relpath(args[1], "audio").replace("\\", "/")
        keys = [k for k, v in sorted(bank.items()) if v[0].startswith(pre.split("audio/")[-1])]
    else:
        keys = args
    n = len(keys)
    cols = 2 if n > 1 else 1
    rows = (n + cols - 1) // cols
    fig, axes = plt.subplots(rows * 2, cols, figsize=(7.2 * cols, 2.6 * rows), squeeze=False,
                             gridspec_kw={"height_ratios": [1, 2] * rows})
    for i, k in enumerate(keys):
        r, c = divmod(i, cols)
        x, sr = load(os.path.join(AUDIO, bank[k][0] + ".wav"))
        m = x.mean(axis=0)
        t = np.arange(len(m)) / sr
        a0, a1 = axes[r * 2][c], axes[r * 2 + 1][c]
        a0.plot(t, x[0], lw=.4, color="#2a6")
        if len(x) == 2:
            a0.plot(t, x[1], lw=.4, color="#c63", alpha=.7)
        a0.set_xlim(0, t[-1]); a0.set_ylim(-1, 1)
        a0.set_title("%s%s  %.2fs" % (k, " [loop]" if bank[k][1] else "", t[-1]), fontsize=8, pad=2)
        a0.tick_params(labelsize=6); a0.set_xticklabels([])
        nper = 1024 if t[-1] > 0.5 else 512
        f, tt, S = sg.spectrogram(m, sr, nperseg=nper, noverlap=nper * 3 // 4, window="hann")
        S = 10 * np.log10(S + 1e-12)
        a1.pcolormesh(tt, f, S, vmin=S.max() - 85, vmax=S.max(), shading="auto", cmap="magma")
        a1.set_yscale("symlog", linthresh=200); a1.set_ylim(20, sr / 2)
        a1.set_yticks([50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000])
        a1.set_yticklabels(["50", "100", "200", "500", "1k", "2k", "5k", "10k", "20k"], fontsize=6)
        a1.tick_params(labelsize=6)
    for j in range(n, rows * cols):
        r, c = divmod(j, cols)
        axes[r * 2][c].axis("off"); axes[r * 2 + 1][c].axis("off")
    plt.tight_layout()
    plt.savefig(out, dpi=100)
    print("zapisano", out)

main()
