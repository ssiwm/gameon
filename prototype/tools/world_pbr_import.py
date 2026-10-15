"""Importuje materiały CC0 z ambientCG (paczki *_1K-JPG.zip rozpakowane do art_src/world_pbr_cc0/<Asset>/) do zestawów gry:
<nazwa>_albedo.png (RGB; kratka RGBA z maską otworów z mapy Opacity), <nazwa>_normal.png (OpenGL), <nazwa>_orm.png (R = AO, G = roughness, B = metallic).
Uruchomienie: python prototype/tools/world_pbr_import.py [--src=art_src/world_pbr_cc0] [--out=art_src/world_pbr_cc0/out] [--preview] [--only=nazwa,nazwa]
`--only=` buduje tylko wskazane materiały (reszta zostaje, jak jest) — surowe skany ambientCG nie muszą wtedy leżeć lokalnie.
Drugie źródło: Poly Haven (CC0, api.polyhaven.com) — mapy kolor / normalne GL / ARM (R = AO, G = roughness, B = metallic, od razu układ ORM gry)
pobierane do <src>/polyhaven/<id>/ (katalog ignorowany przez git, jak ambientCG); ten sam grading na styl nocny.
Zestaw jest hybrydowy: skany CC0 dla betonu, metalu, kratki, desek, słupa i cegły; proceduralne (art_src/world_pbr, `world_pbr_gen.py`) dla terenu,
błota, oleju i wody. Wynik kopiuje się do prototype/art/world3d/.
Licencja źródeł: CC0 1.0 (ambientCG) — bez obowiązku podania autora; lista źródeł w CREDITS-world-textures.md.
Brakujące mapy: AO liczone z mapy wysokości (Displacement), metaliczność 0.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_pbr_gen as G  # noqa: E402

# Materiały proceduralne (z `world_pbr_gen.py`, art_src/world_pbr/): teren i błoto — czytelniejsze z dystansu kamery gry niż skany; olej i woda
# nie mają odpowiedników w ambientCG. Przechodzą ten sam grading i zmniejszenie do RES co skany.
PROC = ("terrain", "mud", "oil", "water")

# nazwa materiału w grze → asset ambientCG
MAP = {
    "terrain": "ScatteredLeaves009",      # (nieużywany: teren jest proceduralny — patrz PROC)
    "concrete": "Concrete034",
    "metal": "MetalPlates013",
    "grate": "MetalWalkway013",
    "plank": "Planks037A",
    "post": "Wood096",
    "wall": "Bricks097",
    "mud": "Ground109",                # (nieużywany: błoto jest proceduralne)
}


# materiały z Poly Haven: nazwa w grze → id zasobu (1K, JPG). Kafel rusty_corrugated_iron ma 2×2 m, fale biegną w poziomie.
PH = {
    "roof": "rusty_corrugated_iron",    # blacha falista na dachach szop (level3d: samotna warstwa betonu „C” z niebem nad i pustką pod)
}
PH_URL = "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/{id}/{id}_{kind}_1k.jpg"

# Grading do stylu gry (noc, zimne zubożone barwy): docelowa średnia luminancja albedo w przestrzeni liniowej (skany są robione w dziennym świetle),
# nasycenie (1 = bez zmian), odcień (mnożnik RGB, chłodny / ciepły). Normalne i ORM zostają bez zmian.
GRADE = {
    "terrain": dict(target=0.115, sat=0.50, tint=(0.88, 0.96, 0.97)),
    "concrete": dict(target=0.20, sat=0.55, tint=(0.88, 0.94, 1.00)),
    "metal": dict(target=0.14, sat=0.80, tint=(0.90, 0.96, 1.00)),
    "grate": dict(target=0.16, sat=0.70, tint=(0.90, 0.96, 1.00)),
    "plank": dict(target=0.15, sat=0.55, tint=(1.00, 0.94, 0.86)),
    "post": dict(target=0.11, sat=0.75, tint=(1.00, 0.88, 0.74)),
    "wall": dict(target=0.115, sat=0.65, tint=(0.95, 0.92, 0.95)),
    "mud": dict(target=0.105, sat=0.45, tint=(0.95, 0.95, 0.90)),
    "roof": dict(target=0.10, sat=0.45, tint=(0.88, 0.94, 1.00)),
}


# Dopracowanie pod dystans kamery gry (~60 px/m na 4K, więc tekstury 465 px/m są zmniejszane ~8×): zmniejszenie do RES, wygładzenie normalnych
# (nk = siła 0..1, blur = sigma w px 1K przed zmniejszeniem) i makro-zmienność koloru plamami (macro = ±amplituda jasności, hue = przesunięcie barwy).
RES = 512
FINISH = {
    "terrain": dict(nk=0.45, blur=1.4, macro=0.28, hue=(0.10, 0.04, -0.06)),
    "concrete": dict(nk=0.50, blur=1.0, macro=0.22, hue=(0.0, 0.0, 0.05)),
    "metal": dict(nk=0.55, blur=0.8, macro=0.18, hue=(0.05, 0.0, 0.0)),
    "grate": dict(nk=0.45, blur=0.6, macro=0.10, hue=(0.0, 0.0, 0.0)),
    "plank": dict(nk=0.80, blur=0.0, macro=0.18, hue=(0.04, 0.0, -0.03)),
    "post": dict(nk=0.80, blur=0.0, macro=0.15, hue=(0.03, 0.0, -0.03)),
    "wall": dict(nk=0.85, blur=0.0, macro=0.15, hue=(0.0, 0.0, 0.0)),
    "mud": dict(nk=0.45, blur=1.4, macro=0.25, hue=(0.06, 0.03, -0.05)),
    "roof": dict(nk=1.00, blur=0.0, macro=0.16, hue=(0.04, 0.0, 0.0)),    # fale muszą zostać wyraźne: normalne bez osłabiania
}


def finish(alb, nrm, orm, alpha, name):
    """Wygładza normalne, zmniejsza do RES i dodaje makro-zmienność (okresowa, więc kafelkuje się bez szwów)."""
    from scipy.ndimage import gaussian_filter
    f = FINISH[name]
    if f["blur"] > 0:
        nxy = nrm[..., :2] * 2 - 1
        nxy = np.dstack([gaussian_filter(nxy[..., i], f["blur"], mode="wrap") for i in (0, 1)])
        nrm = np.dstack([nxy * 0.5 + 0.5, nrm[..., 2]])
    v = nrm * 2 - 1
    v[..., :2] *= f["nk"]
    v /= np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-5)
    nrm = v * 0.5 + 0.5

    def down(a):
        if a.ndim == 2:
            return np.asarray(Image.fromarray(G.to8(a)).resize((RES, RES), Image.LANCZOS), np.float32) / 255.0
        return np.asarray(Image.fromarray(G.to8(a)).resize((RES, RES), Image.LANCZOS), np.float32) / 255.0
    alb, nrm, orm = down(alb), down(nrm), down(orm)
    alpha = down(alpha) if alpha is not None else None
    if f["macro"] > 0:
        m = G.fbm(RES, 3, 3, 4, 7000 + len(name)) * 0.65 + G.fbm(RES, 7, 7, 3, 7100 + len(name)) * 0.35
        m = (m - m.mean()) / max(float(m.std()), 1e-4)
        k = 1.0 + np.clip(m, -2.2, 2.2) * f["macro"] * 0.5
        lin = srgb_to_lin(alb) * k[..., None]
        lin = lin * (1.0 + np.array(f["hue"], np.float32) * np.clip(m, -2.2, 2.2)[..., None])
        alb = lin_to_srgb(lin)
    return alb, nrm, orm, alpha


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def grade(alb, g):
    lin = srgb_to_lin(alb)
    y = (lin * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1, keepdims=True)
    lin = y + (lin - y) * g["sat"]                          # nasycenie wokół luminancji
    lin = lin * np.array(g["tint"], np.float32)
    y2 = (lin * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1)
    k = g["target"] / max(float(y2.mean()), 1e-4)
    lin = lin * k                                           # średnia luminancja → cel
    # miękkie ściskanie światłocieni, żeby jasne plamy nie przepalały się po przyciemnieniu
    lin = lin / (1.0 + lin * 1.2)
    k2 = g["target"] / max(float(((lin * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1)).mean()), 1e-4)
    return lin_to_srgb(lin * k2)


def square(a):
    """Kafle 2:1 (1024×512) układamy do kwadratu — dwie kopie jedna nad drugą (kafelkowanie nie zmienia wyglądu, a triplanar nie rozciąga wzoru)."""
    h, w = a.shape[:2]
    if w == 2 * h:
        return np.concatenate([a, a], axis=0)
    return a


def load_map(d, asset, kind):
    p = os.path.join(d, f"{asset}_1K-JPG_{kind}.jpg")
    if not os.path.exists(p):
        return None
    return Image.open(p)


def convert(name, asset, src, out, preview):
    d = os.path.join(src, asset)
    col = load_map(d, asset, "Color").convert("RGB")
    w, h = col.size
    alb = np.asarray(col, np.float32) / 255.0
    nrm = np.asarray(load_map(d, asset, "NormalGL").convert("RGB").resize((w, h)), np.float32) / 255.0
    rough = np.asarray(load_map(d, asset, "Roughness").convert("L").resize((w, h)), np.float32) / 255.0
    ao_i = load_map(d, asset, "AmbientOcclusion")
    disp = np.asarray(load_map(d, asset, "Displacement").convert("L").resize((w, h)), np.float32) / 255.0
    ao = np.asarray(ao_i.convert("L").resize((w, h)), np.float32) / 255.0 if ao_i is not None else G.ao_from_height(disp, (2, 6, 18), 5.0)
    met_i = load_map(d, asset, "Metalness")
    metal = np.asarray(met_i.convert("L").resize((w, h)), np.float32) / 255.0 if met_i is not None else np.zeros((h, w), np.float32)
    op_i = load_map(d, asset, "Opacity")
    alpha = np.asarray(op_i.convert("L").resize((w, h)), np.float32) / 255.0 if op_i is not None else None
    alb = grade(alb, GRADE[name])
    alb, nrm, rough, ao, metal = square(alb), square(nrm), square(rough), square(ao), square(metal)
    if alpha is not None:
        alpha = square(alpha)
    h, w = alb.shape[:2]
    orm = np.dstack([ao, rough, metal])
    alb, nrm, orm, alpha = finish(alb, nrm, orm, alpha, name)
    h, w = alb.shape[:2]
    rough, ao = orm[..., 1], orm[..., 0]
    if alpha is not None:
        Image.fromarray(G.to8(np.dstack([alb, alpha]))).save(os.path.join(out, name + "_albedo.png"))
    else:
        Image.fromarray(G.to8(alb)).save(os.path.join(out, name + "_albedo.png"))
    Image.fromarray(G.to8(nrm)).save(os.path.join(out, name + "_normal.png"))
    Image.fromarray(G.to8(orm)).save(os.path.join(out, name + "_orm.png"))
    if preview:
        os.makedirs(os.path.join(out, "preview"), exist_ok=True)
        one = G.lit(alb, nrm, orm)
        if alpha is not None:
            one = one * alpha[..., None] + 0.08 * (1 - alpha[..., None])
        tile = np.tile(one, (2, 2, 1))
        s = 512
        a = Image.fromarray(G.to8(one)).resize((s, int(s * h / w)), Image.LANCZOS)
        b = Image.fromarray(G.to8(tile)).resize((s, int(s * h / w)), Image.LANCZOS)
        hh = a.size[1]
        c = Image.new("RGB", (s * 2 + 6, hh), (20, 20, 20))
        c.paste(a, (0, 0))
        c.paste(b, (s + 6, 0))
        c.save(os.path.join(out, "preview", name + "_preview.png"))
    print("OK", name, asset, (w, h), "alpha" if alpha is not None else "", "AO" if ao_i is not None else "AO<-height", "metal" if met_i is not None else "")


def ph_fetch(aid, d):
    """Pobiera mapy kolor / normalne GL / ARM zasobu Poly Haven do katalogu d (pomija te, które już leżą)."""
    import urllib.request
    os.makedirs(d, exist_ok=True)
    for kind in ("diff", "nor_gl", "arm"):
        p = os.path.join(d, f"{aid}_{kind}_1k.jpg")
        if os.path.exists(p):
            continue
        req = urllib.request.Request(PH_URL.format(id=aid, kind=kind), headers={"User-Agent": "dead-air-87-asset-fetch/1.0"})
        with urllib.request.urlopen(req, timeout=60) as r, open(p, "wb") as f:
            f.write(r.read())
        print("POBRANO", p)


def convert_ph(name, aid, src, out, preview):
    d = os.path.join(src, "polyhaven", aid)
    ph_fetch(aid, d)
    col = Image.open(os.path.join(d, f"{aid}_diff_1k.jpg")).convert("RGB")
    w, h = col.size
    alb = np.asarray(col, np.float32) / 255.0
    nrm = np.asarray(Image.open(os.path.join(d, f"{aid}_nor_gl_1k.jpg")).convert("RGB").resize((w, h)), np.float32) / 255.0
    orm = np.asarray(Image.open(os.path.join(d, f"{aid}_arm_1k.jpg")).convert("RGB").resize((w, h)), np.float32) / 255.0
    alb = grade(alb, GRADE[name])
    alb, nrm, orm = square(alb), square(nrm), square(orm)
    alb, nrm, orm, _ = finish(alb, nrm, orm, None, name)
    Image.fromarray(G.to8(alb)).save(os.path.join(out, name + "_albedo.png"))
    Image.fromarray(G.to8(nrm)).save(os.path.join(out, name + "_normal.png"))
    Image.fromarray(G.to8(orm)).save(os.path.join(out, name + "_orm.png"))
    if preview:
        os.makedirs(os.path.join(out, "preview"), exist_ok=True)
        one = G.lit(alb, nrm, orm)
        s = 512
        a = Image.fromarray(G.to8(one)).resize((s, s), Image.LANCZOS)
        b = Image.fromarray(G.to8(np.tile(one, (2, 2, 1)))).resize((s, s), Image.LANCZOS)
        c = Image.new("RGB", (s * 2 + 6, s), (20, 20, 20))
        c.paste(a, (0, 0))
        c.paste(b, (s + 6, 0))
        c.save(os.path.join(out, "preview", name + "_preview.png"))
    print("OK", name, "Poly Haven", aid, (w, h))


def convert_proc(name, out, preview):
    src = "art_src/world_pbr"
    a = np.asarray(Image.open(f"{src}/{name}_albedo.png"), np.float32) / 255.0
    rgb, al = a[..., :3], (a[..., 3] if a.shape[-1] == 4 else None)
    if name in GRADE:
        rgb = grade(rgb, GRADE[name])

    def rs(x):
        return np.asarray(Image.fromarray(G.to8(x)).resize((RES, RES), Image.LANCZOS))
    o = rs(rgb)
    if al is not None:
        o = np.dstack([o, rs(al)])
    Image.fromarray(o).save(os.path.join(out, name + "_albedo.png"))
    for k in ("normal", "orm"):
        Image.open(f"{src}/{name}_{k}.png").convert("RGB").resize((RES, RES), Image.LANCZOS).save(os.path.join(out, f"{name}_{k}.png"))
    print("OK", name, "(proceduralny)")


def main():
    a = sys.argv[1:]
    src = next((x.split("=")[1] for x in a if x.startswith("--src=")), "art_src/world_pbr_cc0")
    out = next((x.split("=")[1] for x in a if x.startswith("--out=")), os.path.join(src, "out"))
    only = next((x.split("=")[1].split(",") for x in a if x.startswith("--only=")), None)
    os.makedirs(out, exist_ok=True)

    def want(name):
        return only is None or name in only
    for name, asset in MAP.items():
        if not want(name):
            continue
        if name in PROC:
            convert_proc(name, out, "--preview" in a)
        else:
            convert(name, asset, src, out, "--preview" in a)
    for name, aid in PH.items():
        if want(name):
            convert_ph(name, aid, src, out, "--preview" in a)
    for name in PROC:
        if name not in MAP and want(name):
            convert_proc(name, out, False)


if __name__ == "__main__":
    main()
