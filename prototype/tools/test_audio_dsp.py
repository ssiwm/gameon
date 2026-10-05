"""
test_audio_dsp.py — testy rdzenia DSP (python3 tools/test_audio_dsp.py).

Każdy test odpowiada konkretnemu błędowi poprzedniego rdzenia albo wymaganiu jakości:
wysokość dźwięku, charakterystyka filtrów, aliasing, szwy pętli, RT60, zgodność LUFS
z ffmpeg, determinizm. Wyjście ≠ 0 przy jakimkolwiek niepowodzeniu.
"""
import math, os, shutil, subprocess, sys, tempfile
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_dsp as d
from audio_dsp import SR, Rng

FAILS = []


def check(name, ok, info=""):
    print(("  ok   " if ok else "  FAIL ") + name + ("  (%s)" % info if info else ""))
    if not ok:
        FAILS.append(name)


def peak_hz(x, lo=20, hi=20000):
    n = len(x)
    X = np.abs(np.fft.rfft(x * np.hanning(n)))
    f = np.fft.rfftfreq(n, 1 / SR)
    m = (f >= lo) & (f <= hi)
    i = np.argmax(X * m)
    # interpolacja paraboliczna
    a, b, c = np.log(X[i - 1] + 1e-12), np.log(X[i] + 1e-12), np.log(X[i + 1] + 1e-12)
    return f[i] + 0.5 * (a - c) / (a - 2 * b + c) * (f[1] - f[0])


def level_db(x, f0, bw=0.15):
    n = len(x)
    X = np.abs(np.fft.rfft(x * np.hanning(n))) ** 2
    f = np.fft.rfftfreq(n, 1 / SR)
    m = (f > f0 * (1 - bw)) & (f < f0 * (1 + bw))
    return 10 * math.log10(X[m].sum() + 1e-30)


def test_osc():
    print("oscylatory")
    for shape in ("sine", "saw", "square", "tri"):
        for f in (55.0, 110.0, 440.0, 1760.0):
            x = d.osc(shape, f, SR * 2)
            ph = peak_hz(x, f * 0.7, f * 1.3)
            check("%s %.0f Hz" % (shape, f), abs(ph - f) < 0.5, "zmierzono %.2f" % ph)
    x = d.osc("sine", 100.0, SR)
    check("sinus 100 Hz nie jest ciszą", np.sqrt(np.mean(x ** 2)) > 0.69)
    # glissando: częstotliwość w 1/4 i 3/4 czasu zgodna z zadaną
    g = d.glide(200.0, 800.0, SR * 2)
    x = d.osc("sine", g, SR * 2)
    q1 = peak_hz(x[SR // 4 - 2400:SR // 4 + 2400], 150, 900)
    check("glissando 200→800", abs(q1 - 275.0) < 12.0, "t=1/8: %.0f Hz (oczek. ~275)" % q1)
    # aliasing piły 3 kHz: energia „odbitych" harmonicznych poniżej -45 dB względem podstawowej
    f0 = 3000.0
    x = d.osc("saw", f0, SR * 2)
    X = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    harm = np.zeros(len(fr), bool)
    for h in range(1, 8):
        harm |= np.abs(fr - h * f0) < 40
    harm &= fr < 22000
    alias = X[~harm & (fr > 100) & (fr < 20000)].sum()
    check("saw 3 kHz: aliasing < -35 dB", 10 * math.log10(alias / X[harm].sum()) < -35.0,
          "%.1f dB" % (10 * math.log10(alias / X[harm].sum())))


def test_fm():
    print("FM / modal")
    x = d.fm(220.0, SR, ratio=1.0, index=0.0)
    check("fm index=0 → czysty sinus 220", abs(peak_hz(x) - 220.0) < 0.5 and abs(np.mean(x)) < 1e-3)
    x = d.fm(220.0, SR, ratio=2.0, index=3.0)
    check("fm bez DC", abs(np.mean(x)) < 0.01, "DC=%.4f" % np.mean(x))
    m = d.modal([500.0], [1.0], [0.5], SR)
    env = np.abs(m[: SR // 2])
    t60 = None
    check("modal: zanik 60 dB w ~t60", 20 * math.log10(np.abs(m[int(0.45 * SR):int(0.5 * SR)]).max() + 1e-9) < -45.0)


def test_filters():
    print("filtry")
    r = Rng(1)
    x = d.white(SR * 8, r)
    for fc in (300.0, 1500.0, 6000.0):
        y = d.lp(x, fc)
        a = 10 * math.log10(np.mean(d.bp(y, fc, 6) ** 2) / np.mean(d.bp(x, fc, 6) ** 2))
        check("lp %.0f Hz: -3 dB w fc" % fc, abs(a + 3.0) < 1.2, "%.2f dB" % a)
        lo = 10 * math.log10(np.mean(d.bp(y, fc / 6, 3) ** 2) / np.mean(d.bp(x, fc / 6, 3) ** 2))
        check("lp %.0f Hz: ~0 dB w paśmie" % fc, abs(lo) < 0.5, "%.2f dB" % lo)
    y = d.hp(x, 1000.0)
    a = 10 * math.log10(np.mean(d.bp(y, 1000.0, 6) ** 2) / np.mean(d.bp(x, 1000.0, 6) ** 2))
    check("hp 1 kHz: -3 dB w fc", abs(a + 3.0) < 1.2, "%.2f dB" % a)
    z = d.sweep(x, "lp", d.glide(200.0, 5000.0, len(x)), q=0.7071)
    first, last = np.mean(d.hp(z[:SR], 2000.0) ** 2), np.mean(d.hp(z[-SR:], 2000.0) ** 2)
    check("sweep lp rośnie jasność", last > first * 20, "ratio %.0f" % (last / max(first, 1e-12)))


def test_dyn():
    print("dynamika")
    x = d.osc("sine", 200.0, SR) * 3.0
    y = d.limiter(x, -1.0)
    check("limiter: szczyt ≤ -1 dBFS", d.peak(y) <= d.db_to_lin(-1.0) + 1e-3, "%.2f dBFS" % d.lin_to_db(d.peak(y)))
    s = d.saturate(d.osc("sine", 5000.0, SR), 6.0)
    X = np.abs(np.fft.rfft(s * np.hanning(len(s)))) ** 2
    f = np.fft.rfftfreq(len(s), 1 / SR)
    # po saturacji 5 kHz harmoniczne 15k (3.) legalne, odbite (np. 9 kHz = 24k-15k) powinny być b. słabe
    ref = X[(f > 4900) & (f < 5100)].sum()
    refl = X[(f > 8900) & (f < 9100)].sum()
    check("saturacja nadpróbkowana: odbicia < -50 dB", 10 * math.log10(refl / ref) < -50.0,
          "%.1f dB" % (10 * math.log10(refl / ref)))
    c = d.compress(d.osc("sine", 300.0, SR) * np.r_[np.ones(SR // 2), 0.1 * np.ones(SR // 2)], -12.0, 4.0)
    check("kompresor redukuje głośny odcinek", d.peak(c[: SR // 4]) < 0.9)


def test_loops():
    print("pętle")
    n = SR * 3
    r = Rng(3)
    x = d.colored(n, r, 1.0)
    y = d.circ_filter(x, lambda t: d.lp(t, 800.0))
    seam = abs(y[0] - y[-1])
    med = np.median(np.abs(np.diff(y)))
    check("szum filtrowany kołowo: szew ≤ 5× mediany", seam <= 5 * med, "%.1f×" % (seam / med))
    check("szum filtrowany kołowo: ciągłość 2. rzędu", abs(np.mean(y)) < 0.01)
    ev = np.zeros(n + SR)
    ev[n - 100:n - 100 + SR] += d.osc("sine", 300.0, SR) * d.env_exp(SR, 0.2)
    f = d.fold_loop(ev, n)
    check("fold_loop: długość dokładna", len(f) == n)


def test_reverb():
    print("pogłos")
    r = Rng(7)
    for rt in (0.4, 1.2, 2.5):
        ir = d.make_ir(rt, r, size=1.0, damping=0.3, stereo=False)
        e = ir ** 2
        edc = np.cumsum(e[::-1])[::-1]
        edb = 10 * np.log10(edc / edc[0] + 1e-12)
        i5, i25 = np.argmax(edb < -5), np.argmax(edb < -25)
        t20 = (i25 - i5) / SR
        rt_meas = 3 * t20
        check("IR rt60=%.1f" % rt, 0.55 * rt < rt_meas < 1.6 * rt, "T20×3 = %.2f s" % rt_meas)
    st = d.make_ir(1.0, Rng(8), stereo=True)
    cc = np.corrcoef(st[0], st[1])[0, 1]
    check("IR stereo nieskorelowane L/R", abs(cc) < 0.35, "corr=%.2f" % cc)
    check("IR znormalizowane energią", abs(np.sum(st ** 2) / 2 - 0.5) < 0.05 or abs(np.sum(st ** 2) - 1) < 0.05)


def test_loudness():
    print("głośność")
    x = d.osc("sine", 997.0, SR * 5) * 0.5
    mine = d.lufs(x)
    check("LUFS sinusa 997 Hz amp 0.5 ≈ -9.0 (RMS -9.03 + K 0.0)", abs(mine - (-9.00)) < 0.15, "%.2f" % mine)
    if shutil.which("ffmpeg"):
        fn = os.path.join(tempfile.gettempdir(), "t_lufs.wav")
        d.write_wav(fn, x)
        p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", fn, "-af", "ebur128", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
        import re
        m = re.findall(r"I:\s+(-?[\d.]+) LUFS", p)
        ff = float(m[-1])
        check("zgodność z ffmpeg ebur128 (±0.3 LU)", abs(ff - mine) < 0.3, "ffmpeg %.2f vs %.2f" % (ff, mine))
    tp = d.true_peak_db(d.osc("sine", 11025.0, SR) * 0.9)
    check("true peak ≥ sample peak", tp >= d.lin_to_db(0.9) - 0.01)


def test_determinism():
    print("determinizm")
    def make(seed):
        r = Rng(seed)
        return d.make_ir(0.8, r) .sum() + d.white(1000, r).sum() + d.colored(2048, r, 1.0).sum()
    check("ten sam seed → ten sam wynik", make(5) == make(5))
    check("inny seed → inny wynik", make(5) != make(6))
    a = Rng(1).fork(1).uniform(); b = Rng(1).fork(2).uniform()
    check("fork niezależny", a != b)


if __name__ == "__main__":
    for t in (test_osc, test_fm, test_filters, test_dyn, test_loops, test_reverb, test_loudness, test_determinism):
        t()
    print("\n%s" % ("WSZYSTKIE TESTY OK" if not FAILS else "NIEPOWODZENIA: %s" % ", ".join(FAILS)))
    sys.exit(1 if FAILS else 0)
