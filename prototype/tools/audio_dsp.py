"""
audio_dsp.py — synteza audio na czystym stdlib Pythona (brak numpy w środowisku).

To jest "zastępca sound designera" dla prototypu: bake'uje deterministyczne,
proceduralne assety WAV (GDD §13: analogowe syntezatory lat 80., taśma, szum
+ industrialne uderzenia). Docelowo te pliki zastępuje prawdziwy materiał
nagrany — architektura runtime nie wie, czy dźwięk jest proceduralny, czy nagrany.

Bufor to lista floatów w zakresie [-1, 1] (mono) albo krotka dwóch takich list
(stereo). Wewnętrznie liczymy mono, stereo powstaje przez Haas/rozszerzenie.

Kontrakt: bake jest deterministyczny (własny RNG z seeda), więc ponowne
wygenerowanie daje bajt w bajt ten sam plik.
"""

from __future__ import annotations

import math
import struct
import wave

SR = 48000
TAU = math.tau


# --------------------------------------------------------------------------- rng

class Rng:
    """xorshift64* — szybki, deterministyczny, bez zależności zewnętrznych."""

    __slots__ = ("_s",)

    def __init__(self, seed: int = 0x9E3779B97F4A7C15):
        s = seed & 0xFFFFFFFFFFFFFFFF
        self._s = s if s else 0x123456789ABCDEF

    def _next(self) -> int:
        s = self._s
        s ^= (s << 13) & 0xFFFFFFFFFFFFFFFF
        s ^= s >> 7
        s ^= (s << 17) & 0xFFFFFFFFFFFFFFFF
        self._s = s
        return s

    def uniform(self, lo: float = 0.0, hi: float = 1.0) -> float:
        return lo + (hi - lo) * ((self._next() >> 11) / float(1 << 53))

    def bipolar(self, amp: float = 1.0) -> float:
        return (self.uniform() * 2.0 - 1.0) * amp

    def choice(self, seq):
        return seq[self._next() % len(seq)]

    def chance(self, p: float) -> bool:
        return ((self._next() >> 11) / float(1 << 53)) < p


# --------------------------------------------------------------------------- buf

def buf_new(n: int) -> list:
    return [0.0] * n


def buf_add(dst: list, src: list) -> list:
    """dst += src, z automatycznym wydłużeniem dst. Zwraca dst, żeby dało się
    użyć w wyrażeniu `x = buf_add(x, y)` bez podwójnego zapisywania.

    Auto-rozszerzanie jest tu celowe: mieszaniny mają różne długości (offset,
    env, głośniki) i ręczne wyrównywanie w każdym builderze to główne źródło
    błędów poza zakresem."""
    if len(src) > len(dst):
        dst.extend([0.0] * (len(src) - len(dst)))
    n = len(src)
    for i in range(n):
        dst[i] += src[i]
    return dst


def buf_add_scaled(dst: list, src: list, k: float) -> list:
    if k == 0.0:
        return dst
    if k == 1.0:
        return buf_add(dst, src)
    if len(src) > len(dst):
        dst.extend([0.0] * (len(src) - len(dst)))
    n = len(src)
    for i in range(n):
        dst[i] += src[i] * k
    return dst


def buf_scale(a: list, k: float) -> list:
    return [x * k for x in a]


def buf_mul(a: list, b) -> list:
    """Mnożenie elementowe. Drugi argument może być listą (env, modulacja)
    albo skalarem. Wynik ma długość max(a, b) — krótszy czynnik jest
    traktowany jak wyzerowany ogon, żeby nigdy nie ucinać sygnału po cichu."""
    if isinstance(b, (int, float)):
        return [x * b for x in a]
    n = max(len(a), len(b))
    if len(a) < n:
        a = a + [0.0] * (n - len(a))
    if len(b) < n:
        b = b + [0.0] * (n - len(b))
    return [a[i] * b[i] for i in range(n)]


def buf_offset(a: list, delay_s: float) -> list:
    """Przesunięcie w SEKUNDACH. Używaj buf_offset_n() dla offsetów w próbkach."""
    d = int(delay_s * SR)
    if d <= 0:
        return list(a)
    if d > len(a) + SR * 60:
        raise ValueError(
            "buf_offset: delay_s=%r daje %d próbek — chyba podano liczbę próbek "
            "zamiast sekund (np. _at() z bake_audio.py)?" % (delay_s, d))
    return [0.0] * d + list(a)


def buf_offset_n(a: list, offset_samples: int) -> list:
    """Przesunięcie w PRÓBKACH — kontrakt _at() w bake_audio.py.

    Osobna funkcja od buf_offset() bo mieszanie tych dwóch jednostek kosztowało
    segfault: _at() zwraca już próbki, a mnożenie przez SR dawało 204 GB listy.
    """
    n = int(offset_samples)
    if n <= 0:
        return list(a)
    return [0.0] * n + list(a)


def buf_norm(a: list, peak: float = 0.98) -> list:
    m = 0.0
    for x in a:
        ax = x if x >= 0.0 else -x
        if ax > m:
            m = ax
    if m < 1e-9:
        return a
    k = peak / m
    return [x * k for x in a]


def buf_rms(a: list) -> float:
    if not a:
        return 0.0
    return math.sqrt(sum(x * x for x in a) / len(a))


def buf_norm_rms(a: list, target: float, peak_ceiling: float = 0.98) -> list:
    """Normalizuje do zadanego RMS zamiast do peaku.

    Normalizacja po peaku wyrównuje fakturę, nie głośność: ciągły pad
    (nisk crest factor) przy peak=0.95 brzmi jak ściana, a perkusja
    (wysoki crest) przy tym samym peakie jest cicha. Warstwy muzyki
    nakładają się, więc liczy się głośność względna, nie szczyt.

    Gdy RMS-owe wzmocnienie podniosłoby peak nad sufit, bierzemy mniejszy
    współczynnik — celem jest nie przesterować, a trafność jest drugorzędna.
    """
    r = buf_rms(a)
    if r < 1e-9:
        return a
    k = target / r
    pk = 0.0
    for x in a:
        ax = x if x >= 0.0 else -x
        if ax > pk:
            pk = ax
    if pk > 1e-9:
        k_ceiling = peak_ceiling / pk
        if k_ceiling < k:
            k = k_ceiling
    if abs(k - 1.0) < 1e-9:
        return a
    return [x * k for x in a]


def buf_hp(a: list, fc: float = 22.0) -> list:
    """Usuwa składową stałą filtrem górnoprzepustowym 1. rzędu.

    Konieczne PRZED normalizacją. Kilka budżetów używa wt_square(0.42),
    czyli fali o wypełnieniu 42% — jej średnia jest różna od zera, a svf
    to zachowuje. Po normalizacji do peaku zostaje wielka stała składowa:
    w pętli daje klik co obieg, a na głośnikach intermodulację słyszalną
    jak szum/tło.

    22 Hz to dolna granica słyszalności basu; wszystkie instrumenty w tym
    projekcie (baz od ~50 Hz w górę) przechodzą bez zmian, a podstawa
    składowej stałej znika.
    """
    if not a:
        return a
    rc = 1.0 / (2.0 * math.pi * fc)
    k = rc / (rc + 1.0 / SR)
    out = [0.0] * len(a)
    y = 0.0
    x_prev = 0.0
    for i, x in enumerate(a):
        y = k * (y + x - x_prev)
        x_prev = x
        out[i] = y
    return out


def buf_fade(a: list, fade_in: float = 0.005, fade_out: float = 0.02) -> list:
    n = len(a)
    fi = min(int(fade_in * SR), n // 2)
    fo = min(int(fade_out * SR), n // 2)
    out = list(a)
    for i in range(fi):
        out[i] *= i / fi
    for i in range(fo):
        out[n - 1 - i] *= i / fo
    return out


def buf_taper(a: list, curve: float = 1.0, curve_out: float = 1.0) -> list:
    """Potęjkowe wygładzenie — brzmi naturalniej niż liniowe fade."""
    n = len(a)
    out = list(a)
    for i in range(n):
        t = i / n
        g = (t ** curve) * ((1.0 - t) ** curve_out)
        out[i] *= g
    return out


def loop_xfade(a: list, xfade_s: float = 0.5) -> list:
    """Zamienia dowolny bufor w pętlę bez szwu (crossfade ostatnich próbek
    z początkiem, prawo mocy równaj).

    Nic nie dodaje do początku — dla materiału
    zbudowanego na pełnej długości bufora (np. hum 100 Hz + szum) tamto
    wstrzykiwało energię, której w sygnale nie było, i rozrywało szew.

    Skoro nie ma „ogonu do zawinięcia", zostaje skrócić i scrossfade'ować.
    Bufor WYCAINA się o xfade z przodu, a ostatnie xfade próbek zostają
    zmieszane z początkiem:

        out = a[c:]                      # reszta nietknięta
        out[-c:] <- a[n-c:] -> a[:c]     # zejście w głowę

    Dzięki temu out[-1] == a[c-1] i out[0] == a[c], czyli szew zawija się
    na sąsiednich próbkach oryginału — a nie na dwóch przypadkowych
    fragmentach szumu. Skrócenie o c jest ceną: nic nie znika, energia
    jedynie przechodzi z głowy w ogon.
    """
    c = int(xfade_s * SR)
    n = len(a)
    if c <= 1 or n <= 2 * c:
        return a
    out = list(a[c:n])
    for i in range(c):
        th = (math.pi / 2.0) * (i + 1) / c
        idx = n - c - c + i
        out[idx] = out[idx] * math.cos(th) + a[i] * math.sin(th)
    return out


def loop_period(a: list, period: int, xfade: int) -> list:
    """Pętla o DOKŁADNEJ długości `period` (rytm: takty, uderzenia serca).

    loop_xfade() skraca bufor o długość crossfade'u — dla szumu to bez
    znaczenia, ale pętla 16 taktów skrócona o 0,5 s przeskakuje o pół
    uderzenia przy każdym obiegu. Tutaj builder dostarcza `period + xfade`
    próbek, w których wzór jest PRZEDŁUŻONY (np. takt 5 = takt 1), a ogon
    a[period:period+xfade] przechodzi liniowo w głowę:

        out[i] = a[i]·t + a[period+i]·(1-t),  i < xfade
        out[i] = a[i],                        i ≥ xfade

    Szew: out[period-1] = a[period-1], out[0] ≈ a[period] — sąsiednie
    próbki. Crossfade liniowy, bo przedłużony wzór jest SKORELOWANY z głową
    (te same uderzenia) — prawo mocy dałoby +3 dB na każdej perkusji w szwie.
    """
    need = period + xfade
    if len(a) < need:
        a = list(a) + [0.0] * (need - len(a))
    out = list(a[:period])
    for i in range(xfade):
        t = (i + 0.5) / xfade
        out[i] = a[i] * t + a[period + i] * (1.0 - t)
    return out


def buf_slice_pad(a: list, n: int) -> list:
    if len(a) >= n:
        return a[:n]
    return list(a) + [0.0] * (n - len(a))


def buf_energy(a: list) -> float:
    s = 0.0
    for x in a:
        s += x * x
    return s


def stereoize(mono: list, width_ms: float = 9.0, haas_hz: float = 340.0) -> tuple:
    """Proste rozszerzenie stereo: mid + posunięcie fazy (Haas) na kanałach + deltas."""
    d = max(1, int(width_ms * 0.001 * SR))
    haas = int(SR / haas_hz)
    left = list(mono)
    right = [0.0] * len(mono)
    for i in range(d, len(mono)):
        right[i] = mono[i - d]
    for i in range(min(haas, len(mono))):
        right[i] = mono[i]
    return left, right


# --------------------------------------------------------------------------- wav

def write_wav(path: str, data, sr: int = SR, channels: int = 1) -> None:
    if channels == 1:
        inter = data
    else:
        left, right = data
        n = min(len(left), len(right))
        inter = [0.0] * (n * 2)
        for i in range(n):
            inter[i * 2] = left[i]
            inter[i * 2 + 1] = right[i]
    frames = bytearray()
    packer = struct.Struct("<h").pack
    for x in inter:
        if x > 1.0:
            x = 1.0
        elif x < -1.0:
            x = -1.0
        frames += packer(int(x * 32767.0))
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(frames))


# --------------------------------------------------------------------------- wavetables

def wt_from_harmonics(amps: list) -> list:
    """Buduje tablicę jednocyklową z listy amplitud harmonicznych."""
    n = len(amps)
    w = [0.0] * n
    for h, a in enumerate(amps, start=1):
        if a == 0.0:
            continue
        w[h % n] += a
    norm = max(abs(x) for x in w) or 1.0
    return [x / norm for x in w]


def wt_sine() -> list:
    return [0.0, 1.0]


def wt_saw(harmonics: int = 40) -> list:
    n = harmonics * 2
    amps = [0.0] * n
    for h in range(1, n // 2 + 1):
        amps[h % n] += (1.0 / h) * (1.0 if h % 2 else -1.0)
    return wt_from_harmonics(amps)


def wt_square(width: float = 0.5, harmonics: int = 48) -> list:
    n = harmonics * 2
    amps = [0.0] * n
    for h in range(1, n // 2 + 1):
        amps[h % n] += math.sin(math.pi * h * width) / h
    return wt_from_harmonics(amps)


def wt_triangle(harmonics: int = 32) -> list:
    n = harmonics * 2
    amps = [0.0] * n
    for h in range(1, n // 2 + 1):
        odd = h if h % 2 else 0
        if odd:
            amps[h % n] += ((-1) ** ((odd - 1) // 2)) / (odd * odd)
    return wt_from_harmonics(amps)


def wt_bell(nh: int = 14) -> list:
    """Metaliczny/brzękowy: harmoniczne z losowym spadkiem i fazą."""
    amps = [0.0] * 512
    rng = Rng(0xB311)
    for h in range(1, nh + 1):
        amps[h] = (1.0 / (h ** 1.35)) * rng.uniform(0.6, 1.0)
    return wt_from_harmonics(amps)


def wt_organ(nh: int = 8) -> list:
    amps = [0.0] * 256
    for h in range(1, nh + 1):
        amps[h] = (1.0 / h) * (1.0 if h % 2 == 0 else 0.55)
    return wt_from_harmonics(amps)


def wt_noise_floor(n: int = 2048, rng_seed: int = 0x1234) -> list:
    """Szum jako 'wavetable' — pozwala odtwarzać go z modulacją fazy."""
    r = Rng(rng_seed)
    return [r.bipolar() for _ in range(n)]


# --------------------------------------------------------------------------- oscillators

def osc(wt: list, n: int, f0: float, f1: float | None = None,
        phase: float = 0.0, vib_hz: float = 0.0, vib_cents: float = 0.0,
        phase_noise: float = 0.0, rng: Rng | None = None) -> list:
    """Oscillator z interpolacją częstotliwości (f0 -> f1) i wibracją."""
    f1 = f0 if f1 is None else f1
    wn = len(wt)
    out = [0.0] * n
    ph = phase % wn
    df = (f1 - f0) / n
    f = f0
    vib_phase = 0.0
    vib_step = TAU * vib_hz / SR if vib_hz > 0.0 else 0.0
    vib_scale = (2.0 ** (vib_cents / 1200.0)) - 1.0
    rn = rng
    for i in range(n):
        fcur = f
        if vib_step:
            fcur = f * (1.0 + vib_scale * math.sin(vib_phase))
            vib_phase += vib_step
        ph += fcur
        if phase_noise and rn is not None:
            ph += rn.bipolar(phase_noise)
        p = ph
        i0 = int(p) % wn
        i1 = (i0 + 1) % wn
        fr = p - int(p)
        out[i] = wt[i0] + (wt[i1] - wt[i0]) * fr
        f += df
        while ph >= wn:
            ph -= wn
    return out


def noise_white(n: int, rng: Rng) -> list:
    return [rng.bipolar() for _ in range(n)]


def noise_pink(n: int, rng: Rng) -> list:
    out = [0.0] * n
    b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0.0
    for i in range(n):
        w = rng.bipolar()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
        b6 = w * 0.115926
    return out


def noise_brown(n: int, rng: Rng) -> list:
    out = [0.0] * n
    last = 0.0
    for i in range(n):
        last = (last + 0.02 * rng.bipolar()) / 1.02
        out[i] = last * 3.5
    return out


# --------------------------------------------------------------------------- filters

def svf(buf: list, cut0: float, cut1: float | None = None, q: float = 0.7,
        mode: str = "lp") -> list:
    """State Variable Filter (Chamberlin) z liniową zmianą cutoff i rezonansem."""
    n = len(buf)
    cut1 = cut0 if cut1 is None else cut1
    out = [0.0] * n
    low = band = 0.0
    dcut = (cut1 - cut0) / n
    cut = cut0
    inv_q = 1.0 / max(0.5, q)
    two_pi_sr = TAU / SR
    for i in range(n):
        f = cut
        if f > SR * 0.45:
            f = SR * 0.45
        elif f < 12.0:
            f = 12.0
        g = math.tan(math.pi * f / SR)
        k = inv_q
        hp = (buf[i] - k * g * low - band) / (1.0 + g * (g + k))
        band += g * hp
        low += g * band
        if mode == "lp":
            out[i] = low
        elif mode == "hp":
            out[i] = hp
        else:
            out[i] = band
        cut += dcut
    return out


def onepole_lp(buf: list, cut: float) -> list:
    a = math.exp(-TAU * cut / SR)
    b = 1.0 - a
    out = [0.0] * len(buf)
    y = 0.0
    for i, x in enumerate(buf):
        y = b * x + a * y
        out[i] = y
    return out


def highpass(buf: list, cut: float) -> list:
    lp = onepole_lp(buf, cut)
    return [buf[i] - lp[i] for i in range(len(buf))]


def tilt(buf: list, amount: float) -> list:
    """Proste tilt EQ: amount<0 cieńej, >0 jaśniej."""
    if amount == 0.0:
        return list(buf)
    lp = onepole_lp(buf, 1200.0)
    if amount < 0.0:
        k = amount * 2.0
        return [buf[i] + lp[i] * k for i in range(len(buf))]
    k = amount
    return [lp[i] * k for i in range(len(buf))]


# --------------------------------------------------------------------------- envelopes

def env_adsr(n: int, a: float, d: float, s: float, r: float) -> list:
    na = max(1, int(a * SR))
    nd = max(1, int(d * SR))
    nr = max(1, int(r * SR))
    ns = max(0, n - na - nd - nr)
    out = [0.0] * n
    idx = 0
    for i in range(min(na, n)):
        out[idx] = i / na
        idx += 1
    for i in range(min(nd, n - idx)):
        out[idx] = 1.0 + (s - 1.0) * (i / nd)
        idx += 1
    for _ in range(min(ns, n - idx)):
        out[idx] = s
        idx += 1
    rem = n - idx
    if rem > 0:
        for i in range(rem):
            out[idx] = s * (1.0 - i / rem)
            idx += 1
    return out


def env_exp(n: int, tau: float, curve: float = 1.0) -> list:
    """Wykładniczy ogon — naturalny dla strzałów, uderzeń, ech."""
    out = [0.0] * n
    k = 1.0 / (tau * SR)
    for i in range(n):
        out[i] = math.exp(-k * i) ** curve if curve != 1.0 else math.exp(-k * i)
    return out


def env_perc(n: int, attack: float = 0.002, decay: float = 0.12) -> list:
    na = max(1, int(attack * SR))
    out = [0.0] * n
    for i in range(n):
        if i < na:
            out[i] = i / na
        else:
            out[i] = math.exp(-(i - na) / (decay * SR))
    return out


# --------------------------------------------------------------------------- shaping

def saturate(buf: list, drive: float = 2.0) -> list:
    """Soft clip / tape saturation — grubość lat 80."""
    if drive <= 0.0:
        return list(buf)
    k = 1.0 / (1.0 + drive)
    return [math.tanh(x * drive) * k * (1.0 + drive) for x in buf]


def bitcrush(buf: list, bits: int = 8, downsample: int = 1) -> list:
    levels = float(2 ** (bits - 1))
    out = [0.0] * len(buf)
    hold = 0.0
    cnt = 0
    for i, x in enumerate(buf):
        if cnt <= 0:
            hold = x
            cnt = downsample
        cnt -= 1
        out[i] = round(hold * levels) / levels
    return out


def tape(buf: list, wow_hz: float = 0.6, wow_depth: float = 0.0035,
         hiss: float = 0.0, sat: float = 1.2, rng: Rng | None = None) -> list:
    """Taśma: napięcie + wow/flutter + szum. Rdzeń brzmienia 'analogowego' z GDD §13."""
    n = len(buf)
    out = [0.0] * n
    rn = rng or Rng(0x77)
    # Średnia prędkość odczytu = 1,0; wow/flutter tylko ją modulują. Wcześniej
    # step = 1 + wow_depth: taśma czytała ~0,35% szybciej, więc pętle muzyki
    # rozjeżdżały się z taktem (~40 ms na obieg), a one-shoty pod koniec
    # zawijały się do własnego początku (klik na końcu tape_stop itp.).
    step = 1.0
    phase = 0.0
    w1 = TAU * wow_hz / SR
    w2 = TAU * (wow_hz * 6.7) / SR
    p1 = p2 = 0.0
    h = 0.0
    hstep = (TAU * 5400.0) / SR
    for i in range(n):
        p1 += w1
        p2 += w2
        mod = step * (1.0 + wow_depth * math.sin(p1)) * (1.0 + wow_depth * 0.4 * math.sin(p2))
        read = phase
        i0 = int(read) % n
        i1 = (i0 + 1) % n
        fr = read - int(read)
        v = buf[i0] + (buf[i1] - buf[i0]) * fr
        phase += mod
        if phase >= n:
            phase -= n
        h += hstep
        if h >= TAU:
            h -= TAU
        if hiss:
            v += math.sin(h) * hiss + rn.bipolar(hiss * 0.6)
        out[i] = math.tanh(v * sat) / (1.0 + sat) * (1.0 + sat)
    return out


def schroeder(buf: list, room: float = 0.72, damp: float = 0.35,
              mix: float = 0.3, pre_s: float = 0.012) -> list:
    """Lekki algorytmiczny reverb do pieczenia ogonów (Schroeder/FDN-lite).

    Używany tylko przy bake'owaniu — runtime rewerberuje Godotem.
    """
    n = len(buf)
    wet = [0.0] * n
    pre = int(pre_s * SR)
    combs = (0.0297, 0.0371, 0.0411, 0.0437)
    g = 0.72 + room * 0.25
    for ct in combs:
        d = int(ct * SR * (0.7 + room * 0.6))
        if d <= 0 or d >= n:
            continue
        line = [0.0] * d
        idx = 0
        store = 0.0
        for i in range(n):
            src = buf[i - pre] if i >= pre else 0.0
            y = line[idx]
            store = y * (1.0 - damp) + store * damp
            line[idx] = src + store * g
            idx += 1
            if idx >= d:
                idx = 0
            wet[i] += y * 0.25
    aps = (0.0050, 0.0017)
    for at in aps:
        d = int(at * SR)
        line = [0.0] * d
        idx = 0
        for i in range(n):
            buf_v = wet[i]
            y = line[idx]
            outv = -buf_v + y
            line[idx] = buf_v + y * 0.5
            wet[i] = outv
            idx += 1
            if idx >= d:
                idx = 0
    return [buf[i] * (1.0 - mix) + wet[i] * mix for i in range(n)]


# --------------------------------------------------------------------------- fm

def fm2(n: int, carrier: float, ratio: float = 2.0, index: float = 3.0,
        index_end: float | None = None, vib_hz: float = 0.0, vib_cents: float = 0.0,
        rng: Rng | None = None) -> list:
    """2-operatorowy FM — charakter DX7 (GDD §13) i metaliczne brzmienia."""
    index_end = index if index_end is None else index_end
    out = [0.0] * n
    pc = 0.0
    pm = 0.0
    dpc = carrier / SR
    dpm = carrier * ratio / SR
    dind = (index_end - index) / n
    ind = index
    vp = 0.0
    vs = TAU * vib_hz / SR if vib_hz else 0.0
    vsc = (2.0 ** (vib_cents / 1200.0)) - 1.0 if vib_hz else 0.0
    for i in range(n):
        mc = math.sin(pm) * ind
        out[i] = math.sin(pc + mc)
        pc += dpc
        pm += dpm
        ind += dind
        if vs:
            vp += vs
        if pc >= 1.0:
            pc -= 1.0
        if pm >= 1.0:
            pm -= 1.0
        if vsc:
            dpc = carrier * (1.0 + vsc * math.sin(vp)) / SR
            dpm = carrier * ratio * (1.0 + vsc * math.sin(vp)) / SR
    return out


# --------------------------------------------------------------------------- mix utils

def mixdown(parts: list, lengths: int) -> list:
    out = [0.0] * lengths
    for p, k in parts:
        buf_add_scaled(out, buf_slice_pad(p, lengths), k)
    return out


def time_ms(n: int, ms: float) -> int:
    return int(SR * ms / 1000.0)