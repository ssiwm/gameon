# Zasoby znacznika celu interakcji (INTERACT_KEY_PLAN.md K1, interact_mark3d.gd):
#   key_ring.png — pierścień z drutu kolczastego z Blendera (`tools/blender_barbed_ring.py`), spakowany do kanałów:
#                  R = jasność drutu, G = krycie drutu, B = poświata (rozmyte krycie). Barwa i odsłanianie po kącie — w shaderze.
#   --meshy-input — obraz wejściowy dla Meshy (image-to-3d) z pierwszej klatki arkusza inspiracji `art_src/ui/interact_key_ref.png`:
#                  nieprzezroczysta nakładka (poświata obok ma krycie < 1 — odcinamy ją), litera zamalowana dyfuzją z ziarnem rdzy
#                  (literę rysuje Label3D z czcionki gry, więc model jest bez litery), białe tło, 1024 px. Model z Meshy przetwarza dalej
#                  `tools/blender_key_cap.py`.
#
#   blender -b --factory-startup -P prototype/tools/blender_barbed_ring.py -- --out=C:/tmp/barbed_ring.png
#   python prototype/tools/gen_interact_key.py --ring=C:/tmp/barbed_ring.png [--meshy-input=C:/tmp/ekey_meshy_in.png]
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROTO = os.path.dirname(HERE)
REF = os.path.join(os.path.dirname(PROTO), "art_src", "ui", "interact_key_ref.png")
OUT = os.path.join(PROTO, "art", "world3d", "interact")
CELL = (0, 0, 336, 378)          # pierwsza klatka arkusza 4 × 2 (spoczynek, bez pierścienia)
MESHY_PX = 1024
RING_PX = 512


def arg(name, default=None):
	for a in sys.argv[1:]:
		if a.startswith("--%s=" % name):
			return a.split("=", 1)[1]
	return default


def diffuse(img, mask, iters=900):
	out = img.copy()
	for _ in range(iters):
		p = np.pad(out, ((1, 1), (1, 1), (0, 0)), mode="edge")
		avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4.0
		out[mask] = avg[mask]
	return out


def make_meshy_input(path):
	sheet = Image.open(REF).convert("RGBA")
	cell = np.array(sheet.crop(CELL)).astype(float)
	solid = cell[..., 3] >= 250.0
	ys, xs = np.nonzero(solid)
	cap = cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
	alpha = np.clip((cap[..., 3] - 235.0) / 20.0, 0.0, 1.0)          # tylko nieprzezroczysta nakładka, krawędź wygładzona
	rgb = cap[..., :3]
	h, w = alpha.shape
	# litera: jasne, mało nasycone piksele w środkowym polu nakładki, z obrysem
	lum = rgb @ np.array([0.3, 0.59, 0.11])
	sat = rgb.max(axis=2) - rgb.min(axis=2)
	yy, xx = np.mgrid[0:h, 0:w]
	centre = (xx > w * 0.28) & (xx < w * 0.74) & (yy > h * 0.16) & (yy < h * 0.66)
	letter = centre & (lum > 120.0) & (sat < 90.0)
	letter = np.array(Image.fromarray((letter * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(17))) > 0
	filled = diffuse(rgb, letter)
	rng = np.random.default_rng(87)
	grain = np.array(Image.fromarray(np.clip(rng.normal(128.0, 40.0, (h, w)), 0, 255).astype(np.uint8))
		.filter(ImageFilter.GaussianBlur(0.8))).astype(float)
	filled[letter] += ((grain[..., None] - 128.0) * 0.12)[letter]      # drobne ziarno rdzy, żeby zamalowane pole nie było gładkie
	a = alpha[..., None]
	on_white = filled * a + 255.0 * (1.0 - a)
	img = Image.fromarray(np.clip(on_white, 0, 255).astype(np.uint8))
	side = max(w, h)
	sq = Image.new("RGB", (side, side), (255, 255, 255))
	sq.paste(img, ((side - w) // 2, (side - h) // 2))
	sq.resize((MESHY_PX, MESHY_PX), Image.LANCZOS).save(path)


def make_ring(path):
	src = Image.open(path).convert("RGBA").resize((RING_PX, RING_PX), Image.LANCZOS)
	a = np.array(src).astype(float)
	lum = (a[..., :3] @ np.array([0.3, 0.59, 0.11])) / 255.0
	alpha = a[..., 3] / 255.0
	glow = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9))
	g = np.array(glow).astype(float) / 255.0
	g = np.clip(g / max(g.max(), 1e-3) * 1.4, 0.0, 1.0)
	packed = np.dstack([lum * 255.0, alpha * 255.0, g * 255.0, np.full_like(lum, 255.0)]).astype(np.uint8)
	Image.fromarray(packed).save(os.path.join(OUT, "key_ring.png"))


def main():
	os.makedirs(OUT, exist_ok=True)
	ring_src = arg("ring")
	if ring_src:
		make_ring(ring_src)
	meshy = arg("meshy-input")
	if meshy:
		make_meshy_input(meshy)
	if not ring_src and not meshy:
		print(__doc__ if __doc__ else "użycie: --ring=RENDER.png [--meshy-input=WYJŚCIE.png]")
		return
	print("[GEN-INTERACT-KEY] gotowe")


if __name__ == "__main__":
	main()
