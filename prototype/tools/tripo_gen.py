#!/usr/bin/env python3
"""Klient API Tripo (v3, region globalny) do generowania postaci 3D: tekst → model, rig-check, rig, pobranie GLB, saldo i zużycie.

Klucz: ~/.config/dead-air/tripo.env (TRIPO_API_KEY=...) albo zmienna środowiskowa — nigdy nie jest wypisywany ani zapisywany w repo.
Tylko stdlib. Przykłady:
    python3 tools/tripo_gen.py balance
    python3 tools/tripo_gen.py text "opis..." --out art_src/characters/tripo/male_scav --tag male_scav
    python3 tools/tripo_gen.py rigcheck TASK_ID
    python3 tools/tripo_gen.py rig TASK_ID --out art_src/characters/tripo/male_scav_rig
    python3 tools/tripo_gen.py usage
Koszty (cennik 2026-10: 1 kredyt = 0,01 USD): tekst→3D 20 (+10 tekstura HD, +20 geometria HD), rig 25, rig-check 0. Zadania nieudane nie są pobierane.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "https://openapi.tripo3d.ai/v3"        # konto globalne (platform.tripo3d.ai); .com to strona chińska
KEYFILE = os.path.expanduser("~/.config/dead-air/tripo.env")
MODEL = "v3.1-20260211"


def key():
    k = os.environ.get("TRIPO_API_KEY", "")
    if not k and os.path.exists(KEYFILE):
        for line in open(KEYFILE, encoding="utf-8"):
            if line.startswith("TRIPO_API_KEY="):
                k = line.split("=", 1)[1].strip()
    if not k:
        sys.exit("Brak TRIPO_API_KEY (patrz nagłówek skryptu).")
    return k


def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, headers={"Authorization": "Bearer " + key(), "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return json.load(e)
        except ValueError:
            sys.exit(f"HTTP {e.code} {path}")


def ok(resp, what):
    if resp.get("code") != 0:
        sys.exit(f"{what}: błąd {resp.get('code')} {resp.get('message')} ({resp.get('suggestion')})")
    return resp["data"]


def wait(task_id, every=4, timeout=900):
    t0 = time.time()
    last = None
    while time.time() - t0 < timeout:
        d = ok(call("GET", f"/tasks/{task_id}"), "task")
        st, pr = d.get("status"), d.get("progress")
        if (st, pr) != last:
            print(f"  {task_id}: {st} {pr}%")
            last = (st, pr)
        if st == "success":
            return d
        if st in ("failed", "cancelled", "banned"):
            sys.exit(f"zadanie {task_id}: {st}")
        time.sleep(every)
    sys.exit("przekroczono czas oczekiwania")


def download(url, path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with urllib.request.urlopen(url, timeout=120) as r, open(path, "wb") as f:
        f.write(r.read())
    return os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance")
    sub.add_parser("usage")
    t = sub.add_parser("text")
    t.add_argument("prompt")
    t.add_argument("--neg", default="")
    t.add_argument("--out", required=True, help="ścieżka bez rozszerzenia (zapisze .glb i _preview.png)")
    t.add_argument("--face-limit", type=int, default=60000)
    t.add_argument("--texture-quality", default="detailed")
    t.add_argument("--geometry-quality", default="detailed")
    t.add_argument("--seed", type=int)
    rc = sub.add_parser("rigcheck")
    rc.add_argument("task_id")
    rg = sub.add_parser("rig")
    rg.add_argument("task_id")
    rg.add_argument("--out", required=True)
    rg.add_argument("--spec", default="mixamo")
    a = ap.parse_args()

    if a.cmd == "balance":
        d = ok(call("GET", "/account/balance"), "balance")
        print(f"saldo: {d['balance']} kredytów (≈ {d['balance'] / 100:.2f} USD), zamrożone: {d['frozen']}")
    elif a.cmd == "usage":
        for u in ok(call("GET", "/account/usage"), "usage")[:20]:
            print(u["created_at"], u["type"], u["task_id"], u["credits_consumed"])
    elif a.cmd == "text":
        body = {"prompt": a.prompt, "model": MODEL, "texture": True, "pbr": True, "texture_quality": a.texture_quality,
                "geometry_quality": a.geometry_quality, "face_limit": a.face_limit, "auto_size": True}
        if a.neg:
            body["negative_prompt"] = a.neg
        if a.seed is not None:
            body["model_seed"] = a.seed
        tid = ok(call("POST", "/generation/text-to-model", body), "create")["task_id"]
        print("zadanie:", tid)
        d = wait(tid)
        o = d["output"]
        n = download(o["model_url"], a.out + ".glb")
        if o.get("rendered_image_url"):
            download(o["rendered_image_url"], a.out + "_preview.png")
        print(f"OK {a.out}.glb {n / 1e6:.1f} MB, zużycie: {d.get('credits_consumed')} kredytów, task_id={tid}")
    elif a.cmd == "rigcheck":
        tid = ok(call("POST", "/animations/rig-check", {"input": a.task_id}), "rig-check")["task_id"]
        d = wait(tid, every=2)
        print("rig-check:", d["output"], "kredyty:", d.get("credits_consumed"))
    elif a.cmd == "rig":
        body = {"input": a.task_id, "model": "v1.0-20240301", "rig_type": "biped", "spec": a.spec, "out_format": "glb"}
        tid = ok(call("POST", "/animations/rig", body), "rig")["task_id"]
        print("zadanie:", tid)
        d = wait(tid)
        n = download(d["output"]["model_url"], a.out + ".glb")
        print(f"OK {a.out}.glb {n / 1e6:.1f} MB, zużycie: {d.get('credits_consumed')} kredytów, task_id={tid}")


if __name__ == "__main__":
    main()
