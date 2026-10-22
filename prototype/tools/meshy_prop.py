#!/usr/bin/env python3
"""Rekwizyt 3D z obrazu przez Meshy API (image-to-3D z teksturą PBR, bez rigu) — źródło dla `prep_items3d.py`.

Do maszyn, których nie ma w bibliotekach CC0 (tokarka, szlifierka, prasa…): obraz wejściowy robi `comfy_gen.py image --flux`
(pojedynczy obiekt, ujęcie 3/4, jasne tło), a wynik ląduje w art_src/world/meshy/<nazwa>.glb obok obrazu i pliku .json z parametrami.

Klucz API: zmienna MESHY_API_KEY albo plik wskazany przez --key-file (domyślnie C:/deadair87/.meshy_key — poza repo; nigdy go nie
commitujemy ani nie wypisujemy). Koszt (cennik API z 10.2026): ok. 30 kredytów za obraz → model z teksturą 2K, +5 przy geometrii 2K/4K.

    python prototype/tools/meshy_prop.py balance
    python prototype/tools/meshy_prop.py make OBRAZ.png --name lathe [--geo standard] [--texture 2k] [--dry-run]
    python prototype/tools/meshy_prop.py remesh --name ammo_shelf [--polycount 30000]   # retopologia gęstego wyniku (ok. 5 kredytów)
"""
import argparse
import base64
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request

API = "https://api.meshy.ai"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "art_src", "world", "meshy"))
DEFAULT_KEY_FILE = "C:/deadair87/.meshy_key"

try:                                                             # polskie znaki i strzałki w konsoli Windows (cp1250)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def _key(path):
    k = os.environ.get("MESHY_API_KEY", "").strip()
    if not k and os.path.isfile(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#"):
                k = line.split("=", 1)[1].strip().strip('"\'') if "=" in line else line
                break
    if not k:
        sys.exit("Brak klucza Meshy: ustaw MESHY_API_KEY albo podaj --key-file.")
    return k


def _req(method, path, key, payload=None, timeout=60):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {"Authorization": "Bearer " + key, "Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    delay = 2.0
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(API + path, data=data, headers=headers, method=method), timeout=timeout) as r:
                body = r.read().decode("utf-8", "replace")
                return json.loads(body) if body.strip() else {}
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(delay)
                delay *= 2
                continue
            sys.exit("Meshy HTTP %d: %s" % (e.code, body[:300]))


def cost(geo, texture):
    return (35 if texture == "8k" else 30) + (5 if geo in ("2k", "4k") else 0)


def make(image, name, key, geo="standard", texture="2k", dry=False):
    ext = os.path.splitext(image)[1].lower()
    mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}.get(ext)
    if mime is None:
        sys.exit("Obraz musi być png / jpg / webp.")
    payload = {
        "image_url": "data:%s;base64,%s" % (mime, base64.b64encode(open(image, "rb").read()).decode()),
        "ai_model": "latest",
        "geometry_resolution": geo,
        "should_texture": True,
        "enable_pbr": True,
        "texture_resolution": texture,
        "target_formats": ["glb"],
    }
    print("Meshy image-to-3D: %s → %s.glb, ok. %d kredytów" % (os.path.basename(image), name, cost(geo, texture)))
    if dry:
        print("(dry run — nic nie wysłano)")
        return
    tid = _req("POST", "/openapi/v1/image-to-3d", key, payload).get("result")
    if not tid:
        sys.exit("Meshy nie zwróciło id zadania.")
    t0 = time.time()
    while True:
        task = _req("GET", "/openapi/v1/image-to-3d/" + tid, key)
        st = (task.get("status") or "").upper()
        sys.stdout.write("\r  %s %3s%%  %4.0f s" % (st, task.get("progress", 0), time.time() - t0))
        sys.stdout.flush()
        if st in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            print()
            break
        if time.time() - t0 > 1800:
            sys.exit("\nMeshy: przekroczony czas (zadanie %s)." % tid)
        time.sleep(6)
    if st != "SUCCEEDED":
        sys.exit("Meshy: zadanie %s — %s %s" % (tid, st, (task.get("task_error") or {}).get("message", "")))
    url = (task.get("model_urls") or {}).get("glb")
    if not url:
        sys.exit("Meshy: brak pliku GLB w wyniku.")
    os.makedirs(OUT_DIR, exist_ok=True)
    dest = os.path.join(OUT_DIR, name + ".glb")
    with urllib.request.urlopen(urllib.request.Request(url), timeout=300) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 18)
    shutil.copy(image, os.path.join(OUT_DIR, name + "_source" + ext))
    with open(os.path.join(OUT_DIR, name + ".json"), "w", encoding="utf-8") as f:
        json.dump({"task": tid, "ai_model": "latest", "geometry_resolution": geo, "texture_resolution": texture,
                   "source_image": name + "_source" + ext, "credits": cost(geo, texture)}, f, indent=1)
    print("OK %s (%.1f MB, %.0f s)" % (dest, os.path.getsize(dest) / 1e6, time.time() - t0))


def _wait(path, tid, key):
    t0 = time.time()
    while True:
        task = _req("GET", path + tid, key)
        st = (task.get("status") or "").upper()
        sys.stdout.write("\r  %s %3s%%  %4.0f s" % (st, task.get("progress", 0), time.time() - t0))
        sys.stdout.flush()
        if st in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            print()
            return task, st, time.time() - t0
        if time.time() - t0 > 1800:
            sys.exit("\nMeshy: przekroczony czas (zadanie %s)." % tid)
        time.sleep(6)


def remesh(name, key, polycount=30000, dry=False):
    """Retopologia po stronie Meshy dla gęstych modeli z wieloma drobnymi bryłami (regał pełen puszek): lokalne upraszczanie
    w `prep_items3d.py` rwie je na strzępy albo rozmywa UV. Wynik zastępuje <nazwa>.glb, zadanie trafia do <nazwa>.json."""
    meta_path = os.path.join(OUT_DIR, name + ".json")
    meta = json.load(open(meta_path, encoding="utf-8"))
    print("Meshy remesh: %s (zadanie %s) → %d trójkątów, ok. 5 kredytów" % (name, meta["task"], polycount))
    if dry:
        print("(dry run — nic nie wysłano)")
        return
    tid = _req("POST", "/openapi/v1/remesh", key, {"input_task_id": meta["task"], "target_formats": ["glb"],
                                                   "topology": "triangle", "target_polycount": polycount}).get("result")
    if not tid:
        sys.exit("Meshy nie zwróciło id zadania.")
    task, st, dt = _wait("/openapi/v1/remesh/", tid, key)
    if st != "SUCCEEDED":
        sys.exit("Meshy: zadanie %s — %s %s" % (tid, st, (task.get("task_error") or {}).get("message", "")))
    dest = os.path.join(OUT_DIR, name + ".glb")
    with urllib.request.urlopen(urllib.request.Request(task["model_urls"]["glb"]), timeout=300) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 18)
    meta.pop("note", None)
    meta["remesh"] = {"task": tid, "target_polycount": polycount, "credits": task.get("consumed_credits")}
    json.dump(meta, open(meta_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("OK %s (%.1f MB, %.0f s, %s kredytów)" % (dest, os.path.getsize(dest) / 1e6, dt, task.get("consumed_credits")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key-file", default=DEFAULT_KEY_FILE)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance")
    m = sub.add_parser("make")
    m.add_argument("image")
    m.add_argument("--name", required=True)
    m.add_argument("--geo", default="standard", choices=["standard", "2k", "4k"])
    m.add_argument("--texture", default="2k", choices=["2k", "4k", "8k"])
    m.add_argument("--dry-run", action="store_true")
    r = sub.add_parser("remesh")
    r.add_argument("--name", required=True)
    r.add_argument("--polycount", type=int, default=30000)
    r.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    key = _key(a.key_file)
    if a.cmd == "balance":
        b = _req("GET", "/openapi/v1/balance", key)
        print("Meshy: %s kredytów" % b.get("balance"))
    elif a.cmd == "remesh":
        remesh(a.name, key, a.polycount, a.dry_run)
    else:
        make(a.image, a.name, key, a.geo, a.texture, a.dry_run)


if __name__ == "__main__":
    main()
