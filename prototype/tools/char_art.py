#!/usr/bin/env python3
"""Silnik postaci pixel-art (1.7): szkielet → render w 4× → cieniowanie z rampami → pikseloza.

Dlaczego tak: ręcznie rysowane w kodzie prostokąty (1.5) dawały płaskie, „drewniane" postacie
bez objętości i z kilkuklatkową animacją. Tu każda klatka powstaje z **pozy** (kąty stawów,
kinematyka prosta), ciało to kapsuły/elipsy z normalnymi, oświetlone jednym światłem z lewej-góry
i kwantyzowane do ramp 4 tonów na materiał (cień, baza, światło, odblask). Render w 4×
trafia do siatki gry zwykłym „najczęstszym kolorem w bloku", potem dochodzą: obrys kolorowy
(selektywny — ciemniejszy odcień sąsiedniego materiału), czyszczenie osieroconych pikseli
i ręcznie rysowane detale na docelowej siatce (twarz, paski, kieszenie, żarzące się oczy).

Układ arkuszy i manifest są takie same jak dawniej (wiersz = animacja), więc gra nie
wymaga zmian w kodzie. Wymaga numpy (`tools/requirements.txt`).
"""
import math
import numpy as np

SS = 4                      # nadpróbkowanie
LIGHT = np.array([-0.48, -0.62, 0.62])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# ---------------------------------------------------------------- kolor

def clamp(v):
    return max(0, min(255, int(round(v))))


def mix(a, b, t):
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(3))


def ramp(base, warm=(1.0, 0.86, 0.62), cool=(0.14, 0.12, 0.30), n=4, sh=1.0):
    """Rampa cień→odblask z przesunięciem barwy: cienie chłodne, światła ciepłe (nie tylko ciemniej/jaśniej)."""
    b = tuple(base[:3])
    sh2 = mix(b, tuple(int(c * 255) for c in cool), 0.52 * sh)
    sh1 = mix(b, tuple(int(c * 255) for c in cool), 0.26 * sh)
    hi1 = mix(b, tuple(int(c * 255) for c in warm), 0.20)
    hi2 = mix(b, tuple(int(c * 255) for c in warm), 0.50)
    out = [sh2, sh1, b, hi1, hi2]
    return out[:n] if n < 5 else out


def dark(c, k=0.38, tint=(0.05, 0.05, 0.12)):
    """Kolor obrysu: mocno przyciemniony odcień wypełnienia, lekko granatowy."""
    return mix(tuple(int(v * k) for v in c[:3]), tuple(int(t * 255) for t in tint), 0.35)


# ---------------------------------------------------------------- płótno wysokiej rozdzielczości

class Hi:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.mat = np.full((self.H, self.W), -1, np.int16)
        self.band = np.zeros((self.H, self.W), np.int8)
        yy, xx = np.mgrid[0:self.H, 0:self.W]
        self.X = (xx + 0.5) / SS
        self.Y = (yy + 0.5) / SS
        self.mats = []          # lista ramp

    def material(self, rp, bands=(-0.2, 0.18, 0.5, 0.82)):
        self.mats.append((rp, bands))
        return len(self.mats) - 1

    def _paint(self, mask, nx, ny, nz, m, gain=1.0, bias=0.0):
        if not mask.any():
            return
        rp, th = self.mats[m]
        inten = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) * gain + bias
        band = np.zeros(inten.shape, np.int8)
        for i, t in enumerate(th):
            band = np.where(inten > t, i, band)
        band = np.clip(band, 0, len(rp) - 1)
        self.mat[mask] = m
        self.band[mask] = band[mask]

    # --- prymitywy
    def capsule(self, a, b, ra, rb, m, **kw):
        ax, ay = a
        bx, by = b
        dx, dy = bx - ax, by - ay
        l2 = max(dx * dx + dy * dy, 1e-6)
        t = np.clip(((self.X - ax) * dx + (self.Y - ay) * dy) / l2, 0, 1)
        cx, cy = ax + t * dx, ay + t * dy
        r = ra + (rb - ra) * t
        ox, oy = self.X - cx, self.Y - cy
        d = np.sqrt(ox * ox + oy * oy)
        mask = d <= r
        nx, ny = ox / np.maximum(r, 1e-6), oy / np.maximum(r, 1e-6)
        nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
        self._paint(mask, nx, ny, nz, m, **kw)

    def ellipse(self, c, rx, ry, m, rot=0.0, **kw):
        cr, sr = math.cos(rot), math.sin(rot)
        ox, oy = self.X - c[0], self.Y - c[1]
        u = (ox * cr + oy * sr) / rx
        v = (-ox * sr + oy * cr) / ry
        f = u * u + v * v
        mask = f <= 1.0
        nxl, nyl = u, v
        nzl = np.sqrt(np.clip(1 - f, 0, 1))
        nx = nxl * cr - nyl * sr
        ny = nxl * sr + nyl * cr
        self._paint(mask, nx, ny, nzl, m, **kw)

    def rbox(self, c, w, h, m, rot=0.0, curve=0.7, **kw):
        """Zaokrąglony prostokąt (superelipsa) — tułów, plecak, buty."""
        cr, sr = math.cos(rot), math.sin(rot)
        ox, oy = self.X - c[0], self.Y - c[1]
        u = (ox * cr + oy * sr) / (w / 2)
        v = (-ox * sr + oy * cr) / (h / 2)
        f = np.abs(u) ** 4 + np.abs(v) ** 4
        mask = f <= 1.0
        nxl, nyl = u * curve, v * curve
        nzl = np.sqrt(np.clip(1 - nxl * nxl - nyl * nyl, 0, 1))
        nx = nxl * cr - nyl * sr
        ny = nxl * sr + nyl * cr
        self._paint(mask, nx, ny, nzl, m, **kw)

    def poly(self, pts, m, normal=(0.0, -0.25, 0.97), **kw):
        from PIL import Image, ImageDraw
        im = Image.new("L", (self.W, self.H), 0)
        ImageDraw.Draw(im).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
        mask = np.array(im) > 127
        nx = np.full(mask.shape, normal[0])
        ny = np.full(mask.shape, normal[1])
        nz = np.full(mask.shape, normal[2])
        self._paint(mask, nx, ny, nz, m, **kw)

    # --- pikseloza do siatki gry
    def reduce(self, min_cover=0.42):
        h, w = self.h, self.w
        K = len(self.mats) * 8 + 1
        keys = np.where(self.mat >= 0, self.mat.astype(np.int32) * 8 + self.band, K - 1)
        blk = keys.reshape(h, SS, w, SS).transpose(0, 2, 1, 3).reshape(h, w, SS * SS)
        counts = (blk[..., None] == np.arange(K)).sum(2)
        opaque = SS * SS - counts[..., K - 1]
        counts[..., K - 1] = 0
        best = counts.argmax(2)
        grid = [[None] * w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                if opaque[y, x] >= SS * SS * min_cover:
                    k = int(best[y, x])
                    m, b = divmod(k, 8)
                    grid[y][x] = (m, b)
        return self._smooth(grid)

    @staticmethod
    def _smooth(grid, passes=2):
        """Wygładza pasma cienia: pojedynczy piksel o innym paśmie niż otoczenie tego samego
        materiału dostaje pasmo większości (likwiduje „szum" po pikselozie, zostawia kształt)."""
        h, w = len(grid), len(grid[0])
        for _ in range(passes):
            out = [row[:] for row in grid]
            for y in range(h):
                for x in range(w):
                    c = grid[y][x]
                    if c is None:
                        continue
                    m, b = c
                    votes = {}
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            if dx == 0 and dy == 0:
                                continue
                            if 0 <= x + dx < w and 0 <= y + dy < h:
                                n = grid[y + dy][x + dx]
                                if n is not None and n[0] == m:
                                    votes[n[1]] = votes.get(n[1], 0) + 1
                    if not votes:
                        continue
                    top = max(votes, key=votes.get)
                    if top != b and votes[top] >= 4 and votes.get(b, 0) <= 1:
                        out[y][x] = (m, top)
            grid = out
        return grid


# ---------------------------------------------------------------- rama końcowa (siatka gry)

class Frame:
    """Siatka w rozdzielczości gry: kolory RGBA + indeks materiału (do obrysu)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]    # (r,g,b,a)

    @classmethod
    def from_hi(cls, hi, min_cover=0.42):
        f = cls(hi.w, hi.h)
        for y, row in enumerate(hi.reduce(min_cover)):
            for x, mb in enumerate(row):
                if mb is not None:
                    m, b = mb
                    rp = hi.mats[m][0]
                    f.px[y][x] = (*rp[b], 255)
        return f

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return None

    def put(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.px[y][x] = (*c[:3], c[3] if len(c) > 3 else 255)

    def only_opaque_put(self, x, y, c):
        if self.get(int(x), int(y)) is not None:
            self.put(x, y, c)

    def despeckle(self):
        """Usuwa piksele bez sąsiada (artefakt pikselozy), nie ruszając cienkich, ciągłych linii."""
        kill = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is None:
                    continue
                n4 = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if self.get(x + dx, y + dy) is not None)
                n8 = sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and self.get(x + dx, y + dy) is not None)
                if n4 == 0 and n8 <= 1:
                    kill.append((x, y))
        for x, y in kill:
            self.px[y][x] = None

    def outline(self, k=0.36):
        """Obrys selektywny: kolor = ciemniejszy odcień sąsiedniego wypełnienia (górny/lewy sąsiad wygrywa)."""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is not None:
                    continue
                for dx, dy in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                    n = self.get(x + dx, y + dy)
                    if n is not None:
                        add.append((x, y, (*dark(n, k), 255)))
                        break
        for x, y, c in add:
            self.px[y][x] = c

    def to_rgba(self):
        return [[p if p is not None else (0, 0, 0, 0) for p in row] for row in self.px]


# ---------------------------------------------------------------- kinematyka

def fk(origin, ang_deg, length):
    """Punkt końcowy: kąt od pionu w dół, dodatni = do przodu (+x)."""
    a = math.radians(ang_deg)
    return (origin[0] + length * math.sin(a), origin[1] + length * math.cos(a))


def up(origin, ang_deg, length):
    """Jak fk, ale w górę (tułów, szyja): kąt od pionu w górę, dodatni = do przodu."""
    a = math.radians(ang_deg)
    return (origin[0] + length * math.sin(a), origin[1] - length * math.cos(a))


# ---------------------------------------------------------------- arkusz → PNG

def write_png(rows, path):
    from PIL import Image
    h = len(rows)
    w = len(rows[0])
    im = Image.new("RGBA", (w, h))
    im.putdata([p for r in rows for p in r])
    im.save(path)


def sheet_rows(frames_by_anim, fw, fh, cols):
    """frames_by_anim: [[Frame,...], ...] → macierz RGBA arkusza (wiersz = animacja)."""
    H = fh * len(frames_by_anim)
    W = fw * cols
    out = [[(0, 0, 0, 0)] * W for _ in range(H)]
    for r, frames in enumerate(frames_by_anim):
        for i, fr in enumerate(frames):
            rgba = fr.to_rgba()
            for y in range(fh):
                for x in range(fw):
                    out[r * fh + y][i * fw + x] = rgba[y][x]
    return out
