#!/usr/bin/env python3
"""Lokalne generowanie zasobów przez ComfyUI (Comfy Desktop, API na http://127.0.0.1:8188): opis → obraz (SDXL) → model 3D (TRELLIS 2 / Pixal3D).

Darmowa, lokalna alternatywa dla `tripo_gen.py`. ComfyUI musi być uruchomione. Tylko stdlib.
    python prototype/tools/comfy_gen.py image "opis..." --out art_src/gibs/meat_a.png [--seed 7] [--neg "..."]
    python prototype/tools/comfy_gen.py model art_src/gibs/meat_a.png --out art_src/gibs/meat_a.glb [--faces 60000] [--tex 2048]
    python prototype/tools/comfy_gen.py both "opis..." --out art_src/gibs/meat_a      (zapisze .png i .glb)

Model 3D powstaje z szablonu ComfyUI `3d_pixal3d_trellis2_image_to_model.json` (format interfejsu → format API, patrz `_to_api`):
usuwa tło z obrazu, generuje kształt i teksturę, upraszcza siatkę, rozwija UV i wypala kolor, metal/chropowatość, okluzję i normalne.
Model odwzorowuje obraz dosłownie — obraz ma pokazywać jeden obiekt w całości, na jednolitym tle, w równym świetle.
Czasy (RTX 3080 10 GB): obraz ok. 20–40 s, model ok. 4 min.
"""
import argparse
import glob
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request

HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
BASE = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Comfy-Desktop")
INPUT = os.path.join(BASE, "ComfyUI-Shared", "input")
OUTPUT = os.path.join(BASE, "ComfyUI-Shared", "output")
TEMPLATE = "3d_pixal3d_trellis2_image_to_model.json"
CHECKPOINT = "sd_xl_base_1.0.safetensors"
STYLE = ", single object, centered, whole object in frame, plain light grey studio background, soft even lighting, no shadow, product photo, photorealistic, highly detailed"
NEG = "multiple objects, cropped, cut off, text, watermark, hands, people, floor, table, dramatic shadow, dark background, cartoon, drawing, lowres, blurry"


def _get(path):
    return json.load(urllib.request.urlopen(HOST + path, timeout=60))


def _run(prompt, timeout=1800):
    req = urllib.request.Request(HOST + "/prompt", data=json.dumps({"prompt": prompt}).encode(), headers={"Content-Type": "application/json"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=60))
    except urllib.error.HTTPError as e:
        sys.exit("ComfyUI odrzucił zadanie: " + e.read().decode("utf-8", "replace")[:2000])
    if r.get("node_errors"):
        sys.exit("błędy węzłów: " + json.dumps(r["node_errors"])[:2000])
    pid = r["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        h = _get("/history/" + pid)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") != "success":
                sys.exit("zadanie nieudane: " + json.dumps(st)[:2000])
            return h[pid].get("outputs", {}), time.time() - t0
        time.sleep(3)
    sys.exit("przekroczono czas oczekiwania")


def _newest(pattern, since):
    files = [f for f in glob.glob(pattern) if os.path.getmtime(f) >= since - 2]
    if not files:
        sys.exit("brak pliku wynikowego: " + pattern)
    return max(files, key=os.path.getmtime)


def image(prompt_text, out, seed=1, neg="", size=1024, steps=28):
    prefix = "da87_" + os.path.splitext(os.path.basename(out))[0]
    p = {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CHECKPOINT}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"width": size, "height": size, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt_text + STYLE, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG + (", " + neg if neg else ""), "clip": ["4", 1]}},
        "3": {"class_type": "KSampler", "inputs": {"seed": seed, "steps": steps, "cfg": 6.5, "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": 1.0,
                                                   "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": prefix, "images": ["8", 0]}},
    }
    t0 = time.time()
    _, dt = _run(p, 600)
    src = _newest(os.path.join(OUTPUT, prefix + "_*.png"), t0)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    shutil.copy(src, out)
    print("OK obraz %s (%.0f s)" % (out, dt))


def _template_path():
    hits = glob.glob(os.path.join(BASE, "ComfyUI-Installs", "*", "ComfyUI", ".venv", "Lib", "site-packages", "comfyui_workflow_templates_json", "templates", TEMPLATE))
    if not hits:
        sys.exit("nie znaleziono szablonu " + TEMPLATE)
    return hits[0]


def _is_widget(spec):
    t = spec[0]
    return isinstance(t, list) or t in ("INT", "FLOAT", "STRING", "BOOLEAN", "COMBO", "COLOR") or t.startswith("COMFY_DYNAMICCOMBO")


def _to_api(wf, info):
    """Szablon w formacie interfejsu (węzły + połączenia + widgets_values) → prompt API. Węzły podglądu zostają (przekazują dane dalej);
    notatki i podgląd 3D odpadają; brakujące wymagane pola (nowsze niż szablon) dostają wartość domyślną."""
    links = {l[0]: l for l in wf["links"]}
    prompt = {}
    for n in wf["nodes"]:
        t = n["type"]
        if t in ("Note", "MarkdownNote", "Preview3DAdvanced", "Preview3D") or n.get("mode") in (2, 4) or t not in info:
            continue
        spec = info[t]["input"]
        linked = {i["name"]: i["link"] for i in n.get("inputs", []) if i.get("link") is not None}
        wv = list(n.get("widgets_values") or [])
        ins = {}
        for name, sp in list(spec.get("required", {}).items()) + list(spec.get("optional", {}).items()):
            if _is_widget(sp) and wv:
                v = wv.pop(0)
                opts = sp[1] if len(sp) > 1 and isinstance(sp[1], dict) else {}
                if (opts.get("control_after_generate") or name in ("seed", "noise_seed")) and wv and wv[0] in ("fixed", "increment", "decrement", "randomize"):
                    wv.pop(0)
                if isinstance(sp[0], str) and sp[0].startswith("COMFY_DYNAMICCOMBO"):
                    ins[name] = v
                    sub = next((o for o in opts.get("options", []) if o.get("key") == v), None)
                    if sub:
                        for sn in list(sub.get("inputs", {}).get("required", {})) + list(sub.get("inputs", {}).get("optional", {})):
                            if wv:
                                ins[name + "." + sn] = wv.pop(0)
                elif name not in linked:
                    ins[name] = v
            if name in linked:
                l = links[linked[name]]
                ins[name] = [str(l[1]), l[2]]
        for name, sp in spec.get("required", {}).items():
            if name not in ins and len(sp) > 1 and isinstance(sp[1], dict) and "default" in sp[1]:
                ins[name] = sp[1]["default"]
        prompt[str(n["id"])] = {"class_type": t, "inputs": ins}
    return prompt


def model(image_path, out, faces=60000, tex=2048, seed=42):
    wf = json.load(open(_template_path(), encoding="utf-8"))
    for n in wf["nodes"]:
        if n["type"] == "DecimateMesh":
            n["widgets_values"][0] = faces
        if n["type"] == "PrimitiveInt":
            n["widgets_values"][0] = tex
        if n["type"] == "KSampler":
            n["widgets_values"][0] = int(n["widgets_values"][0]) + seed - 42
    prompt = _to_api(wf, _get("/object_info"))
    name = "da87_" + os.path.basename(image_path)
    shutil.copy(image_path, os.path.join(INPUT, name))
    prefix = "da87_" + os.path.splitext(os.path.basename(out))[0]
    for nid, p in list(prompt.items()):
        if p["class_type"] == "LoadImage":
            p["inputs"]["image"] = name
        if p["class_type"] == "Save3DAdvanced":
            prompt[nid] = {"class_type": "SaveGLB", "inputs": {"mesh": p["inputs"]["model_3d"], "filename_prefix": "3d/" + prefix}}
    t0 = time.time()
    _, dt = _run(prompt)
    src = _newest(os.path.join(OUTPUT, "3d", prefix + "_*.glb"), t0)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    shutil.copy(src, out)
    print("OK model %s %.1f MB (%.0f s)" % (out, os.path.getsize(out) / 1e6, dt))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("image")
    i.add_argument("prompt")
    i.add_argument("--out", required=True)
    i.add_argument("--seed", type=int, default=1)
    i.add_argument("--neg", default="")
    m = sub.add_parser("model")
    m.add_argument("image")
    m.add_argument("--out", required=True)
    m.add_argument("--faces", type=int, default=60000)
    m.add_argument("--tex", type=int, default=2048)
    b = sub.add_parser("both")
    b.add_argument("prompt")
    b.add_argument("--out", required=True, help="ścieżka bez rozszerzenia")
    b.add_argument("--seed", type=int, default=1)
    b.add_argument("--neg", default="")
    b.add_argument("--faces", type=int, default=60000)
    b.add_argument("--tex", type=int, default=2048)
    a = ap.parse_args()
    try:
        _get("/system_stats")
    except Exception:
        sys.exit("ComfyUI nie odpowiada na %s — uruchom Comfy Desktop." % HOST)
    if a.cmd == "image":
        image(a.prompt, a.out, a.seed, a.neg)
    elif a.cmd == "model":
        model(a.image, a.out, a.faces, a.tex)
    else:
        image(a.prompt, a.out + ".png", a.seed, a.neg)
        model(a.out + ".png", a.out + ".glb", a.faces, a.tex)


if __name__ == "__main__":
    main()
