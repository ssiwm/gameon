"""
bake_audio.py — generator biblioteki dźwięków Dead Air '87 (wersja 2, numpy/scipy).

Uruchomienie (z katalogu prototype/):
    pip install -r tools/requirements.txt
    python3 tools/bake_audio.py                       # wszystko
    python3 tools/bake_audio.py --only weapons,music  # wybrane grupy
    python3 tools/bake_audio.py --list                # lista assetów
    python3 tools/bake_audio.py --reset               # zignoruj stary indeks _bank.json
    python3 tools/test_audio_dsp.py                   # testy rdzenia DSP
    python3 tools/audio_audit.py                      # pomiar jakości po bake'u

Wynik:
    audio/**/*.wav             assety (deterministyczne: ten sam seed = ten sam bajt)
    audio/_bank.json           indeks key -> [ścieżka, pętla?]
    scripts/audio_manifest.gd  wygenerowany manifest dla runtime (PATHS, LOOPS, muzyka, napisy)

Moduły: audio_dsp (rdzeń), bake_common (rejestr + finalize), bake_weapons, bake_sfx
(stalker/świat/gracz/UI), bake_amb (ambient), bake_music (stemy + stingery).
Docelowy materiał nagrany zastępuje te pliki 1:1 — runtime nie widzi różnicy.
"""

from __future__ import annotations

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bake_amb  # noqa: E402
import bake_common as bc  # noqa: E402
import bake_music  # noqa: E402
import bake_sfx  # noqa: E402
import bake_weapons  # noqa: E402

ROOT = bc.ROOT
AUDIO = bc.AUDIO
MANIFEST = os.path.join(ROOT, "scripts", "audio_manifest.gd")
BANK_JSON = os.path.join(AUDIO, "_bank.json")

BUILDERS = [
    ("weapons", bake_weapons.build_weapons),
    ("stalker", bake_sfx.build_stalker),
    ("world", bake_sfx.build_world),
    ("player", bake_sfx.build_player),
    ("ui", bake_sfx.build_ui),
    ("ambience", bake_amb.build_ambience),
    ("music", bake_music.build_music),
]

# Napisy dla niesłyszących / „napisy z opisem dźwięków" (GDD §14): prefiks klucza -> [tekst, ważność 0–3].
# Runtime dobiera NAJDŁUŻSZY pasujący prefiks.
CAPTIONS = {
    "m83_shot": ["[Gunfire]", 1], "p64_shot": ["[Pistol shot]", 1], "spread12_shot": ["[Shotgun blast]", 2],
    "explosion": ["[Explosion]", 3], "stalker_growl": ["[Low growl]", 3], "stalker_shriek": ["[Shriek]", 3],
    "stalker_step": ["[Heavy footsteps]", 3], "stalker_whisper": ["[Whispering]", 2],
    "stalker_appear": ["[Something appears]", 3], "amb_far_cry": ["[Distant cry]", 2],
    "amb_creak": ["[Creaking]", 1], "amb_thud": ["[Distant thud]", 1], "amb_gust": ["[Wind gust]", 0],
    "step_": ["[Footsteps]", 0], "player_hurt": ["[Cry of pain]", 2], "player_down": ["[Teammate down]", 3],
    "revive": ["[Revived]", 2], "glass_break": ["[Glass breaks]", 2], "alarm_bell": ["[Alarm bell]", 2],
    "door_": ["[Door]", 1], "impact_flesh": ["[Impact]", 0], "ricochet": ["[Ricochet]", 1],
    "radio_beep": ["[Radio beep]", 1], "casing_": ["[Casing drops]", 0], "ear_ring": ["[Ringing]", 1],
}


def write_bank() -> None:
    os.makedirs(AUDIO, exist_ok=True)
    with open(BANK_JSON, "w", encoding="utf-8") as f:
        json.dump({k: [v[0], int(v[1])] for k, v in sorted(bc.REG.items())}, f, indent=1, ensure_ascii=False)


def load_bank() -> None:
    """Przy --only wczytuje indeks z poprzednich przebiegów (inaczej manifest zgubiłby pozostałe grupy)."""
    if "--reset" in sys.argv or not os.path.exists(BANK_JSON):
        return
    try:
        with open(BANK_JSON, encoding="utf-8") as f:
            for k, v in json.load(f).items():
                bc.REG.setdefault(k, (v[0], bool(v[1])))
    except Exception as e:  # uszkodzony indeks nie może zablokować bake'u
        print("  ! nie udało się wczytać _bank.json (%s) — zapisuję od zera" % e)


def write_manifest() -> None:
    m = bake_music
    lines = [
        "extends RefCounted",
        "# GENEROWANE przez tools/bake_audio.py — nie edytuj ręcznie.",
        "# Tablica ścieżek + flagi pętli + parametry muzyki. Runtime ładuje leniwie (load) i cache'uje.",
        "",
        "const PATHS := {",
    ]
    for key in sorted(bc.REG):
        lines.append('\t"%s": "res://audio/%s.wav",' % (key, bc.REG[key][0]))
    lines += ["}", "", "# Klucze, które muszą się zapętlać (nie mogą mieć fade-outu).", "const LOOPS := ["]
    for key in sorted(bc.REG):
        if bc.REG[key][1]:
            lines.append('\t"%s",' % key)
    lines += [
        "]", "",
        "# Muzyka: STEMY NAKŁADAJĄ SIĘ (addytywne): cisza ⊂ napięcie ⊂ walka ⊂ pościg.",
        "# Wszystkie mają identyczną długość i siatkę, więc wchodzą w tym samym miejscu taktu.",
        'const MUSIC_STEMS := ["mus_silence", "mus_tension", "mus_combat", "mus_chase"]',
        "# Czas dochodzenia stemu do pełnej głośności [s] (asymetryczne: spokój wolno, akcja szybko).",
        "const MUSIC_BLEND := [4.0, 1.6, 0.7, 0.35]",
        "# Tempo i długość pętli — runtime kwantyzuje wejścia stemów do beatu.",
        "const MUSIC_BPM := %.1f" % m.BPM,
        "const MUSIC_BEATS := %d" % m.BEATS,
        "const MUSIC_LOOP_SEC := %.6f" % (m.LOOP_N / bc.SR),
        "",
        "# Napisy dla niesłyszących: prefiks klucza -> [tekst, ważność 0-3].",
        "const CAPTIONS := {",
    ]
    for k, (txt, pr) in CAPTIONS.items():
        lines.append('\t"%s": ["%s", %d],' % (k, txt, pr))
    lines += ["}", ""]
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main() -> int:
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
    if only:
        load_bank()
    t_all = time.time()
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        t0, before = time.time(), len(bc.REG)
        fn()
        print("[%-8s] %3d assetów  %5.1fs" % (name, len(bc.REG) - before, time.time() - t0))
    write_bank()
    write_manifest()
    missing = [k for k, (p, _) in bc.REG.items() if not os.path.exists(os.path.join(AUDIO, p + ".wav"))]
    print("-" * 56)
    print("manifest: %s" % MANIFEST)
    print("bank: %d ścieżek, %d pętli, brakujących plików: %d, czas %.0fs" % (
        len(bc.REG), sum(1 for v in bc.REG.values() if v[1]), len(missing), time.time() - t_all))
    for k in missing[:10]:
        print("   ! brak pliku: %s" % k)
    if "--list" in sys.argv:
        for k in sorted(bc.REG):
            print("   %-28s %s%s" % (k, bc.REG[k][0], "  [loop]" if bc.REG[k][1] else ""))
    total = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(AUDIO) for f in fs if f.endswith(".wav"))
    print("pamięć audio: %.1f MB WAV" % (total / 1048576.0))
    print("NASTĘPNY KROK: godot --headless --path . --import  (inaczej grają stare sample'e)")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
