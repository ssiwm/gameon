#!/usr/bin/env python3
"""Zamiennik polecenia `blender` oparty na module `bpy` z PyPI (5.2.x = ta sama wersja co Blender 5.2 LTS).

Używany w sesjach w chmurze, gdzie download.blender.org jest zablokowany, a PyPI działa. Obsługuje to,
czego używają skrypty projektu (prototype/tools): `blender -b [plik.blend] [--factory-startup] -P skrypt.py -- args`,
`--python-expr`, `-o ŚCIEŻKA -F FORMAT -f KLATKA | -a`, `-E SILNIK`, `--version`. Argumenty przetwarzane po kolei, jak w Blenderze;
w skrypcie `sys.argv` to oryginalne argumenty (własne po `--`). Brak GUI i wtyczek z dysku (np. MPFB) — to nie jest pełny Blender.
"""
import os
import sys
import traceback


def main() -> int:
    argv = sys.argv[1:]
    if "--version" in argv or "-v" in argv:
        import bpy
        print("Blender %s (bpy module)" % bpy.app.version_string)
        return 0
    import bpy

    exit_code = 0
    py_exit_code = None
    argv = argv[:argv.index("--")] if "--" in argv else argv
    sys.argv = ["blender"] + sys.argv[1:]          # skrypty szukają własnych argumentów po „--"

    def run_python(code: str, path: str) -> None:
        nonlocal exit_code
        try:
            exec(compile(code, path, "exec"), {"__name__": "__main__", "__file__": path})
        except SystemExit:
            raise
        except BaseException:
            traceback.print_exc()
            if py_exit_code is not None:
                exit_code = py_exit_code
                raise SystemExit(exit_code)

    i = 0
    while i < len(argv):
        a = argv[i]

        def nxt() -> str:
            nonlocal i
            i += 1
            return argv[i]

        if a in ("-b", "--background", "--factory-startup", "-noaudio", "--no-window-focus", "-y", "--enable-autoexec", "-d", "--debug"):
            pass
        elif a == "--python-exit-code":
            py_exit_code = int(nxt())
        elif a in ("-P", "--python"):
            path = nxt()
            with open(path, "r", encoding="utf-8") as fh:
                run_python(fh.read(), os.path.abspath(path))
        elif a == "--python-expr":
            run_python(nxt(), "<expr>")
        elif a in ("-o", "--render-output"):
            bpy.context.scene.render.filepath = nxt()
        elif a in ("-F", "--render-format"):
            bpy.context.scene.render.image_settings.file_format = nxt()
        elif a in ("-E", "--engine"):
            bpy.context.scene.render.engine = nxt()
        elif a in ("-s", "--frame-start"):
            bpy.context.scene.frame_start = int(nxt())
        elif a in ("-e", "--frame-end"):
            bpy.context.scene.frame_end = int(nxt())
        elif a in ("-f", "--render-frame"):
            bpy.context.scene.frame_set(int(nxt()))
            bpy.ops.render.render(write_still=True)
        elif a in ("-a", "--render-anim"):
            bpy.ops.render.render(animation=True)
        elif a.startswith("-"):
            print("blender-shim: pomijam nieobsługiwany argument %s" % a, file=sys.stderr)
        else:
            bpy.ops.wm.open_mainfile(filepath=os.path.abspath(a))
        i += 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
