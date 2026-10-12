#!/usr/bin/env python3
"""Strona do odsłuchu A/B dźwięków: samodzielna strona HTML (dźwięk jest w niej zaszyty, bezstratnie — FLAC).

Porównuje wersje tego samego assetu obok siebie, domyślnie „na ślepo" (wersje jako A/B/C w losowej kolejności),
i zbiera werdykt do skopiowania. Pomiar (tools/audio_audit.py) pilnuje techniki — o brzmieniu decyduje ucho.

    python tools/audio_ab.py --licensed                             # synteza (audio/) obok wersji z nagrań (audio_licensed/)
    python tools/audio_ab.py --licensed --only shot,explosion       # tylko rodziny zawierające podane fragmenty nazwy
    python tools/audio_ab.py --alts ../build/audio_alt              # obecne assety obok wersji alternatywnych z bake_audio.py --alts
    python tools/audio_ab.py --ref origin/main                      # assety zmienione względem gałęzi (przed / po)
    python tools/audio_ab.py --alts ../build/audio_alt --out ../build/audio_ab.html

Dźwięki dłuższe niż 8 s (pętle ambientu) są zaszyte stratnie — Ogg Vorbis ok. 190 kb/s, z zachowaną długością co do próbki,
więc szew pętli słychać tak jak w grze; --lossless wyłącza. Duże zestawy są dzielone na kilka stron (--max-mb, domyślnie 3,5 MB na stronę): podgląd plików w aplikacjach
często nie otwiera większych. Stronę zawsze da się otworzyć zwykłą przeglądarką (dwuklik na pliku).

Uruchamiać z katalogu prototype/. Tylko stdlib (+ ffmpeg do FLAC, git przy --ref).
"""
import argparse
import base64
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "audio")
LICENSED = os.path.join(ROOT, "audio_licensed")
# nazwa wersji → opis na stronie (po odkryciu nazw)
LABELS = {"obecna": "obecna (synteza)", "przed": "przed zmianą", "po": "po zmianie", "hybrid": "z nagrań", "hybrid2": "z nagrań, wersja 2", "gen": "wygenerowana"}
# odstęp serii [ms] dla rodzin, w których liczy się powtarzalność; reszta gra warianty jeden po drugim
# (pierwsze dopasowanie wygrywa; strzały wg `cooldown` z scripts/weapons.gd — seria ma brzmieć jak ogień w grze)
SERIES_MS = (("m83_shot", 110), ("p64_shot", 200), ("spread12_shot", 260), ("srut8_shot", 800), ("sokol6_shot", 200),
             ("gniew4_shot", 1200), ("ciegno6_shot", 800), ("_shot", 150), ("step_", 330), ("impact_", 160), ("shell", 140))


WAV_ONLY = [False]
LOSSLESS = [False]
LOSSY_OVER_S = 8.0                    # dłuższe pliki (szumowe pętle ambientu) nie kompresują się bezstratnie — strona byłaby za duża


def _seconds(data: bytes) -> float:
    try:
        with wave.open(io.BytesIO(data)) as w:
            return w.getnframes() / float(w.getframerate())
    except (wave.Error, EOFError):
        return 0.0


def _encode(data: bytes, suffix: str, args: list) -> bytes:
    fd, tmp = tempfile.mkstemp(suffix=suffix)             # do pliku, nie do potoku: nagłówek dostaje wtedy długość
    os.close(fd)
    try:
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", "pipe:0"] + args + [tmp], input=data, capture_output=True)
        return open(tmp, "rb").read() if r.returncode == 0 else b""
    except OSError:
        return b""
    finally:
        os.remove(tmp)


def _uri(data: bytes) -> tuple:
    """WAV → (data URI, czy stratnie). Domyślnie FLAC (bezstratnie); pliki dłuższe niż LOSSY_OVER_S — Ogg Vorbis;
    bez ffmpeg albo z --wav zostaje WAV."""
    if not WAV_ONLY[0]:
        if not LOSSLESS[0] and _seconds(data) > LOSSY_OVER_S:
            ogg = _encode(data, ".ogg", ["-c:a", "libvorbis", "-q:a", "6"])
            if ogg:
                return "data:audio/ogg;base64," + base64.b64encode(ogg).decode("ascii"), True
        flac = _encode(data, ".flac", ["-c:a", "flac", "-compression_level", "8"])
        if 0 < len(flac) < len(data):
            return "data:audio/flac;base64," + base64.b64encode(flac).decode("ascii"), False
    return "data:audio/wav;base64," + base64.b64encode(data).decode("ascii"), False


def _loop_keys() -> set:
    """Klucze pętli z banku (audio/_bank.json) — na stronie grają w kółko."""
    try:
        with open(os.path.join(AUDIO, "_bank.json"), encoding="utf-8") as f:
            return {k for k, v in json.load(f).items() if v[1]}
    except OSError:
        return set()


def _family(rel: str) -> str:
    return re.sub(r"_\d+$", "", os.path.splitext(os.path.basename(rel))[0])


def _collect_dir(name, base, fams):
    """Wersja `name` z katalogu `base` (ten sam układ co audio/) obok obecnego assetu z audio/."""
    for dp, _, fs in os.walk(base):
        for f in sorted(fs):
            if not f.endswith(".wav"):
                continue
            rel = os.path.relpath(os.path.join(dp, f), base).replace("\\", "/")
            cur = os.path.join(AUDIO, *rel.split("/"))
            fam = fams.setdefault(_family(rel), {})
            if os.path.exists(cur):
                fam.setdefault("obecna", {})[rel] = open(cur, "rb").read()
            fam.setdefault(name, {})[rel] = open(os.path.join(dp, f), "rb").read()


def _collect_alts(alts_dir, fams):
    for name in sorted(os.listdir(alts_dir)):
        if os.path.isdir(os.path.join(alts_dir, name)):
            _collect_dir(name, os.path.join(alts_dir, name), fams)


def _collect_ref(ref, fams):
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    pre = os.path.relpath(AUDIO, top).replace("\\", "/") + "/"
    out = subprocess.run(["git", "diff", "--name-only", ref, "--", pre], cwd=top, capture_output=True, text=True, check=True).stdout
    for path in sorted(p for p in out.splitlines() if p.endswith(".wav")):
        rel = path[len(pre):]
        old = subprocess.run(["git", "show", "%s:%s" % (ref, path)], cwd=top, capture_output=True)
        new = os.path.join(top, *path.split("/"))
        fam = fams.setdefault(_family(rel), {})
        if old.returncode == 0:
            fam.setdefault("przed", {})[rel] = old.stdout
        if os.path.exists(new):
            fam.setdefault("po", {})[rel] = open(new, "rb").read()


PAGE = r"""<!doctype html>
<html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Odsłuch A/B — Dead Air '87</title>
<style>
:root { --bg:#f4f2ee; --card:#fff; --ink:#1d1b18; --mute:#6b655c; --line:#d9d4ca; --acc:#a23b1f; --accink:#fff; --pick:#e9dfd0; }
@media (prefers-color-scheme: dark) { :root { --bg:#16140f; --card:#211e18; --ink:#ece7dc; --mute:#9d968a; --line:#3a352b; --acc:#e0683f; --accink:#16140f; --pick:#3a3023; } }
* { box-sizing:border-box; }
body { margin:0; padding:24px 16px 80px; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui, "Segoe UI", sans-serif; }
main { max-width:860px; margin:0 auto; }
h1 { font-size:22px; margin:0 0 6px; } h2 { font-size:17px; margin:0; font-family:ui-monospace, Consolas, monospace; }
p.lead { color:var(--mute); margin:0 0 18px; max-width:64ch; }
.bar { display:flex; gap:16px; flex-wrap:wrap; align-items:center; margin:0 0 18px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:16px; margin:0 0 16px; }
.head { display:flex; justify-content:space-between; align-items:baseline; gap:12px; flex-wrap:wrap; margin-bottom:10px; }
.head small { color:var(--mute); }
.grid { display:grid; gap:6px 10px; align-items:center; overflow-x:auto; }
.grid .h { font-weight:600; text-align:center; } .grid .v { color:var(--mute); font-family:ui-monospace, Consolas, monospace; font-size:13px; white-space:nowrap; }
button { font:inherit; color:var(--ink); background:transparent; border:1px solid var(--line); border-radius:7px; padding:6px 10px; cursor:pointer; min-width:64px; }
button:hover { border-color:var(--acc); } button.on { background:var(--acc); color:var(--accink); border-color:var(--acc); }
.verdict { display:flex; gap:8px; flex-wrap:wrap; align-items:center; margin-top:12px; padding-top:12px; border-top:1px solid var(--line); }
.verdict label { border:1px solid var(--line); border-radius:7px; padding:5px 10px; cursor:pointer; }
.verdict label:has(input:checked) { background:var(--pick); border-color:var(--acc); }
.verdict input[type=radio] { margin:0 6px 0 0; } .verdict input[type=text] { flex:1 1 220px; font:inherit; color:var(--ink); background:transparent; border:1px solid var(--line); border-radius:7px; padding:6px 10px; }
textarea { width:100%; min-height:130px; font:13px/1.5 ui-monospace, Consolas, monospace; color:var(--ink); background:var(--card); border:1px solid var(--line); border-radius:8px; padding:10px; }
</style></head><body><main>
<h1>Odsłuch A/B</h1>
<p class="lead">__PART__Słuchaj na słuchawkach. Wersje są wymieszane i podpisane literami; nazwy odkryjesz dopiero po wyborze. „Seria" gra wszystkie warianty po kolei, tak jak w grze przy ogniu ciągłym albo w marszu. Pętle grają w kółko aż do „Zatrzymaj" — słuchaj, czy nie słychać szwu.</p>
<div class="bar"><label><input type="checkbox" id="reveal"> Pokaż nazwy wersji</label><button id="stop">Zatrzymaj</button></div>
<div id="fams"></div>
<div class="card"><div class="head"><h2>Werdykt</h2><button id="copy">Kopiuj</button></div><textarea id="out" readonly></textarea></div>
</main>
<script>
const DATA = __DATA__;
const LABELS = __LABELS__;
const playing = new Set();
function stopAll() { for (const a of playing) { a.pause ? a.pause() : a.stop(); } playing.clear(); for (const t of timers) clearTimeout(t); timers.length = 0; }
const timers = [];
let actx = null;
// Pętle przez Web Audio: znacznik <audio loop> zostawia przerwę na zawinięciu, a w grze pętla jest bezszwowa.
async function playLoop(uri) {
  actx = actx || new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 48000 });   // bez przepróbkowania: szew co do próbki
  const buf = await actx.decodeAudioData(await (await fetch(uri)).arrayBuffer());
  const src = actx.createBufferSource(); src.buffer = buf; src.loop = true; src.connect(actx.destination); src.start(); playing.add(src);
}
function play(uri, loop) { if (loop) { playLoop(uri); return null; } const a = new Audio(uri); playing.add(a); a.onended = () => playing.delete(a); a.play(); return a; }
function shuffle(n) { const o = [...Array(n).keys()]; for (let i = n - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [o[i], o[j]] = [o[j], o[i]]; } return o; }
const state = DATA.map(f => ({ order: shuffle(f.versions.length), pick: null, note: "" }));
const letter = i => String.fromCharCode(65 + i);
function vname(fi, slot) { const v = DATA[fi].versions[state[fi].order[slot]]; return LABELS[v.name] || v.name; }
function render() {
  const reveal = document.getElementById("reveal").checked, root = document.getElementById("fams");
  root.innerHTML = "";
  DATA.forEach((f, fi) => {
    const st = state[fi], nv = f.versions.length, card = document.createElement("div");
    card.className = "card";
    const head = document.createElement("div"); head.className = "head";
    head.innerHTML = "<h2></h2><small></small>"; head.children[0].textContent = f.name; head.children[1].textContent = f.dir + " · wariantów: " + f.rows.length + (f.lossy ? " · do odsłuchu zakodowane stratnie (Ogg Vorbis)" : "");
    card.appendChild(head);
    const grid = document.createElement("div"); grid.className = "grid"; grid.style.gridTemplateColumns = "minmax(120px, auto) repeat(" + nv + ", minmax(84px, 1fr))";
    grid.appendChild(document.createElement("div"));
    for (let s = 0; s < nv; s++) { const h = document.createElement("div"); h.className = "h"; h.textContent = letter(s) + (reveal ? " — " + vname(fi, s) : ""); grid.appendChild(h); }
    f.rows.forEach(row => {
      const l = document.createElement("div"); l.className = "v"; l.textContent = row; grid.appendChild(l);
      for (let s = 0; s < nv; s++) {
        const uri = f.versions[st.order[s]].files[row], cell = document.createElement("div"); cell.style.textAlign = "center";
        if (uri) { const b = document.createElement("button"); b.textContent = f.loop ? "▶ pętla" : "▶"; b.onclick = () => { stopAll(); play(uri, f.loop); }; cell.appendChild(b); } else { cell.textContent = "—"; }
        grid.appendChild(cell);
      }
    });
    if (f.rows.length > 1) {
      const l = document.createElement("div"); l.className = "v"; l.textContent = "seria" + (f.series ? " co " + f.series + " ms" : ""); grid.appendChild(l);
      for (let s = 0; s < nv; s++) {
        const cell = document.createElement("div"); cell.style.textAlign = "center"; const b = document.createElement("button"); b.textContent = "▶▶";
        b.onclick = () => { stopAll(); const files = f.versions[st.order[s]].files, seq = []; for (let k = 0; k < (f.series ? 12 : f.rows.length); k++) seq.push(files[f.rows[k % f.rows.length]]);
          if (f.series) { seq.forEach((u, k) => u && timers.push(setTimeout(() => play(u), k * f.series))); }
          else { let k = 0; const next = () => { if (k >= seq.length) return; const a = play(seq[k++]); a.addEventListener("ended", () => timers.push(setTimeout(next, 250))); }; next(); } };
        cell.appendChild(b); grid.appendChild(cell);
      }
    }
    card.appendChild(grid);
    const ver = document.createElement("div"); ver.className = "verdict"; ver.appendChild(document.createTextNode("Lepsza:"));
    const opts = [...Array(nv).keys()].map(s => [s, letter(s)]).concat([["same", "bez różnicy"]]);
    opts.forEach(([val, text]) => { const lab = document.createElement("label"), inp = document.createElement("input"); inp.type = "radio"; inp.name = "v" + fi; inp.checked = st.pick === val;
      inp.onchange = () => { st.pick = val; summary(); }; lab.appendChild(inp); lab.appendChild(document.createTextNode(text)); ver.appendChild(lab); });
    const note = document.createElement("input"); note.type = "text"; note.placeholder = "uwagi (np. za jasny, za długi ogon)"; note.value = st.note; note.oninput = () => { st.note = note.value; summary(); };
    ver.appendChild(note); card.appendChild(ver); root.appendChild(card);
  });
  summary();
}
function summary() {
  const lines = DATA.map((f, fi) => { const st = state[fi];
    const pick = st.pick === null ? "(brak wyboru)" : st.pick === "same" ? "bez różnicy" : DATA[fi].versions[st.order[st.pick]].name;
    return f.name + ": " + pick + (st.note ? " — " + st.note : ""); });
  document.getElementById("out").value = lines.join("\n");
}
document.getElementById("reveal").onchange = render;
document.getElementById("stop").onclick = stopAll;
document.getElementById("copy").onclick = () => { const t = document.getElementById("out"); t.select(); navigator.clipboard && navigator.clipboard.writeText(t.value); };
render();
</script></body></html>
"""


def build(fams, out, max_mb=3.5):
    data = []
    loops = _loop_keys()
    for fam in sorted(fams):
        versions = fams[fam]
        if len(versions) < 2:
            continue
        rels = sorted({r for v in versions.values() for r in v})
        series = next((ms for key, ms in SERIES_MS if key in fam and len(rels) > 1), 0)
        lossy = False
        vers = []
        for n, v in versions.items():
            files = {}
            for r, b in v.items():
                files[os.path.splitext(os.path.basename(r))[0]], was_lossy = _uri(b)
                lossy = lossy or was_lossy
            vers.append({"name": n, "files": files})
        rows = [os.path.splitext(os.path.basename(r))[0] for r in rels]
        data.append({"name": fam, "dir": os.path.dirname(rels[0]), "series": series, "rows": rows, "versions": vers,
                     "loop": any(r in loops for r in rows), "lossy": lossy})
    if not data:
        sys.exit("nie ma czego porównywać (brak wersji alternatywnych i zmienionych plików)")
    # podział na strony: rodziny po kolei, nowa strona, gdy bieżąca przekroczyłaby limit
    pages, cur, size = [], [], 0
    for d in data:
        w = sum(len(u) for v in d["versions"] for u in v["files"].values())
        if cur and size + w > max_mb * 1e6:
            pages.append(cur)
            cur, size = [], 0
        cur.append(d)
        size += w
    pages.append(cur)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    stem, ext = os.path.splitext(out)
    outs = []
    for i, page in enumerate(pages):
        path = out if len(pages) == 1 else "%s_%d%s" % (stem, i + 1, ext)
        part = "" if len(pages) == 1 else "<b>Strona %d z %d.</b> " % (i + 1, len(pages))
        html = PAGE.replace("__DATA__", json.dumps(page)).replace("__LABELS__", json.dumps(LABELS, ensure_ascii=False)).replace("__PART__", part)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(html)
        outs.append(path)
        print("OK %s: rodzin %d, %.1f MB" % (path, len(page), os.path.getsize(path) / 1e6))
        for d in page:
            print("   %-22s %s" % (d["name"], " / ".join(v["name"] for v in d["versions"])))
    return outs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--licensed", action="store_true", help="wersje z nagrań z audio_licensed/ obok syntezy z audio/")
    ap.add_argument("--only", help="fragmenty nazw rodzin po przecinku (np. shot,step)")
    ap.add_argument("--alts", help="katalog z bake_audio.py --alts")
    ap.add_argument("--ref", help="gałąź albo commit do porównania (np. origin/main)")
    ap.add_argument("--out", default=os.path.join(ROOT, "..", "build", "audio_ab.html"))
    ap.add_argument("--max-mb", type=float, default=3.5, help="limit rozmiaru jednej strony; większy zestaw jest dzielony na strony _1, _2…")
    ap.add_argument("--wav", action="store_true", help="zaszyj WAV zamiast FLAC")
    ap.add_argument("--lossless", action="store_true", help="długie pliki też bezstratnie (większa strona)")
    a = ap.parse_args()
    if not a.alts and not a.ref and not a.licensed:
        ap.error("podaj --licensed, --alts KATALOG albo --ref GAŁĄŹ")
    fams = {}
    if a.licensed:
        if not os.path.isdir(LICENSED):
            sys.exit("brak %s — najpierw: audio_lib_fetch.py sync i bake_audio.py" % LICENSED)
        _collect_dir("hybrid", LICENSED, fams)
    if a.alts:
        _collect_alts(a.alts, fams)
    if a.ref:
        _collect_ref(a.ref, fams)
    if a.only:
        want = [w for w in a.only.split(",") if w]
        fams = {k: v for k, v in fams.items() if any(w in k for w in want)}
    WAV_ONLY[0] = a.wav
    LOSSLESS[0] = a.lossless
    build(fams, a.out, a.max_mb)


if __name__ == "__main__":
    main()
