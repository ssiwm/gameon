"""Regresja walidacji tekstur: zestaw MPFB w podkatalogu, normalna WebP, wspólny obraz albedo/normalnej.

    python3 prototype/tools/test_tex_vram.py
"""
import contextlib
import io
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

import tex_vram


class TextureValidation(unittest.TestCase):
    def test_nested_webp_normal_and_shared_color(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            models = root / "art/char3d/mpfb"
            models.mkdir(parents=True)
            document = {
                "images": [{"name": "Image_2"}, {"name": "brow"}],
                "textures": [{"extensions": {"EXT_texture_webp": {"source": i}}} for i in range(2)],
                "materials": [
                    {"normalTexture": {"index": 0}},
                    {"normalTexture": {"index": 1}, "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}}},
                ],
            }
            data = json.dumps(document).encode()
            data += b" " * (-len(data) % 4)
            (models / "medic.glb").write_bytes(struct.pack("<IIIII", 0x46546C67, 2, 20 + len(data), len(data), 0x4E4F534A) + data)
            template = 'importer="texture"\ncompress/mode=0\ncompress/normal_map=0\ndetect_3d/compress_to=1\n'
            normal = models / "medic_Image_2.webp.import"
            color = models / "medic_brow.webp.import"
            normal.write_text(template)
            color.write_text(template)
            previous = os.getcwd()
            try:
                with patch.object(tex_vram, "ROOT", str(root)), patch.object(sys, "argv", ["tex_vram.py", "--check"]):
                    with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as failure:
                        tex_vram.main()
                    self.assertEqual(failure.exception.code, 1, "CI musi wykryć nieskompresowane tekstury w podkatalogu")
                    self.assertEqual(normal.read_text(), template, "--check nie zmienia plików")
                with patch.object(tex_vram, "ROOT", str(root)), patch.object(sys, "argv", ["tex_vram.py"]):
                    with contextlib.redirect_stdout(io.StringIO()):
                        tex_vram.main()
                self.assertIn("compress/mode=2", normal.read_text())
                self.assertIn("compress/normal_map=1", normal.read_text(), "normalna WebP bez opisowej nazwy musi dostać kompresję RG")
                self.assertIn("compress/mode=2", color.read_text())
                self.assertIn("compress/normal_map=0", color.read_text(), "obraz albedo musi zachować kanały koloru")
                with patch.object(tex_vram, "ROOT", str(root)), patch.object(sys, "argv", ["tex_vram.py", "--check"]):
                    with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as success:
                        tex_vram.main()
                    self.assertEqual(success.exception.code, 0)
            finally:
                os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
