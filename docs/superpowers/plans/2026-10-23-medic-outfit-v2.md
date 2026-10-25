# Medic Outfit v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the male and female medic uniforms with a matching, fitted navy field-medic set while preserving their bodies, rigs, gear, and gameplay identities.

**Architecture:** Extend the existing Blender/MPFB cloth pipeline with female medic jacket and trouser exports, then point both character recipes at the generated sewn garments. Rebuild only the two medic character GLBs, import them through Godot’s existing asset workflow, and review both generated previews and game renders.

**Tech Stack:** Blender 5.2.2, MPFB2, Python/bpy, GLB, Godot 4.7.2 / GDScript.

**Spec:** `docs/superpowers/specs/2026-10-23-medic-outfit-v2-design.md`

## Global Constraints

- Preserve the current male/female medic identities, Mixamo rigs, gear, outfit IDs, and gameplay behavior.
- Keep the navy/blue-gray uniform and readable red-and-white medical markings; use the existing local Blender/MPFB2 pipeline without new dependencies or paid services.
- Preserve all existing working-tree changes; apply narrow edits to files with line-ending-only diffs.
- Export jacket and trouser GLBs for both sexes, rebuild only the two medic character GLBs, and review front/side/back previews plus in-game renders.
- After importing rebuilt GLBs, run `python tools/tex_vram.py`, reimport, and run the existing proportion check.

## Review Focus

- **Male and female body fit:** inspect both garment sets from front, side, and back in generated previews.
- **Layer interaction:** verify trousers are generated before jackets and that the sewn garments replace the correct MPFB uniform pieces.
- **Medic identity at game scale:** confirm navy cloth, red/white markings, and practical pockets remain legible in character renders.
- **Rig deformation:** inspect idle, movement, crouch, and revive poses in the Godot character renderer.
- **Asset import and size:** confirm Godot imports both rebuilt GLBs, applies VRAM texture compression, and the proportion check passes.

---

### Task 1: Generate the matching medic garment set

**Files:**
- Modify: `prototype/tools/cloth_garments.py` (medic garment profiles and `WARDROBE`)
- Modify: `art_src/clothes/male_medic_emt_jacket.glb`
- Modify: `art_src/clothes/male_medic_emt_trousers.glb`
- Create: `art_src/clothes/female_medic_emt_jacket.glb`
- Create: `art_src/clothes/female_medic_emt_trousers.glb`
- Create: front/side/back review renders under `build/cloth/medic_v2/`
- Modify: `art_src/clothes/SOURCE.md`

**Interfaces:**
- Consumes: `OUTFITS` from `prototype/tools/char_mpfb.py`, the existing `EMT_JACKET` / `EMT_TROUSERS` patterns, and `WARDROBE` in `cloth_garments.py`.
- Produces: four GLBs named `<sex>_medic_emt_{jacket,trousers}.glb`, with the existing Mixamo bind pose/orientation and material workflow.

- [ ] Refine the shared EMT profiles for a clearer field-rescue silhouette: keep navy cloth and light seams, retain chest/cargo pockets and cuffs, and add visible knee reinforcement to the trousers.
- [ ] Add a small white patch with a red cross on the upper left sleeve of both jackets; bake the colors into the game albedo so the mark survives the low-poly export and stays readable at gameplay scale.
- [ ] Add `emt_trousers` then `emt_jacket` to `WARDROBE["female_medic"]`, using its MPFB female body and the same coordinated uniform design.
- [ ] Generate `male_medic` and `female_medic` garments and their front/side/back review renders with Blender; inspect and correct fit or collisions before accepting exports.
- [ ] Update `art_src/clothes/SOURCE.md` with both female files and revised descriptions/triangle counts for all medic garments.
- [ ] Confirm each exported GLB opens and has non-empty geometry/materials; confirm previews show both silhouettes without obvious cloth/body intersections.

Run: `blender -b -P prototype/tools/cloth_garments.py -- male_medic female_medic --work=build/cloth/medic_v2 --tex=1024`
Expected: four medic garment GLBs and review renders are produced; Blender exits successfully.

### Task 2: Rebuild both medic characters with sewn uniforms

**Files:**
- Modify: `prototype/tools/char_mpfb.py` (`female_medic.sewn`)
- Modify: `prototype/art/char3d/mpfb/male_medic.glb` and generated character textures
- Modify: `prototype/art/char3d/mpfb/female_medic.glb` and generated character textures

**Interfaces:**
- Consumes: the four garment GLBs from Task 1 and the existing `add_sewn()` replacement mapping.
- Produces: the same two runtime GLB paths used by `Char3D`, with each jacket and trouser replacing its corresponding MPFB uniform mesh.

- [ ] Add female sewn mappings for `elvs_emt_uniform_pants_female` and `elvs_emt_uniform_jacket_female`, with budgets matching the male trousers (4,200) and jacket (6,000); replace each matching MPFB mesh in full.
- [ ] Rebuild only `male_medic` and `female_medic` with `--sewn`; preserve all other character recipes and assets.
- [ ] Inspect the game character renders for male/female medic in idle, run, crouch, and revive poses; fix visible clipping, detached details, or unreadable markings in the generator and regenerate affected assets.

Run: `blender -b -P prototype/tools/char_mpfb.py -- male_medic female_medic --sewn`
Expected: Blender completes and overwrites only the two medic runtime GLBs and their exported textures.

### Task 3: Import and verify the integrated assets

**Files:**
- Modify: Godot import metadata for rebuilt medic GLBs/textures as generated by the existing import pipeline.

**Interfaces:**
- Consumes: both rebuilt runtime GLBs from Task 2.
- Produces: Godot-imported resources with VRAM-compressed textures and successful character proportion validation.

- [ ] Import the rebuilt assets, run the project texture-compression tool, and reimport them.
- [ ] Run the existing proportion check and capture/render both medic variants in the Godot character renderer for final visual review.
- [ ] Check the final working-tree diff to confirm only the planned generators, source notes, garment outputs, and medic runtime assets changed; leave unrelated user changes untouched.

Run from the project root:

```bash
godot --headless --path prototype --import
python prototype/tools/tex_vram.py
godot --headless --path prototype --import
godot --headless --path prototype -s tools/test_proportions.gd
```

Expected: imports complete without GLB/texture errors and the proportion script prints `PASS`; both medics retain their existing runtime scale and skeleton compatibility.
