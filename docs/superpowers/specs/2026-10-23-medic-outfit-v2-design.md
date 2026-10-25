# Medic Outfit v2 Design

## Intent

Improve the in-game medic clothing for both male and female MPFB characters. Keep the existing character identity and rig, while making the uniform read as a cohesive field-medic outfit at the game's render scale.

## Goals

- Create matching, body-fitted jacket and trouser meshes for both medic variants using the existing Blender cloth-garment pipeline.
- Keep the current navy/blue-gray uniform, clear red-and-white medical markings, and practical rescue equipment.
- Improve garment construction and visible detail: fabric shape, seams, pockets, cuffs, and reinforced knees, without adding visual clutter that disappears at gameplay scale.
- Export and integrate game-ready GLBs through the existing MPFB and Godot import workflow.

## Non-goals

- Replace either character body, skeleton, animations, gear loadout, outfit IDs, or gameplay behavior.
- Introduce a paid generation service or a new software dependency.
- Change non-medic outfits.

## Approaches

1. Recolor the existing MPFB garments. This is the least work, but does not address weak garment shape and construction.
2. Replace both complete medic characters with newly generated models. This could change the look more, but adds rig, animation, and integration risk unrelated to the clothing issue.
3. Extend the existing cloth-garment generator with a coordinated male/female medic set, then rebuild only those two character assets. **Selected:** it targets clothing quality directly and preserves the current game rig and asset pipeline.

## Constraints and implementation calls

- Project files show that the male medic has custom sewn EMT jacket/trousers, while the female medic currently uses MPFB clothing and custom boots. The new version should bring both onto the same garment workflow.
- Treat `concepts/stage3_outfits_models.png` and the current medic assets as visual references; retain the established field-medic palette and symbols rather than copying the older full-body Tripo meshes.
- Preserve the current local working tree. The relevant generator files have line-ending-only differences from Git; edits should be narrowly applied without normalizing unrelated lines.
- Produce front/side/back previews and check the result in the game character renderer. Import new GLBs into Godot and run the existing proportion check before considering the assets integrated.

## Deliverables

- Male and female medic jacket/trouser GLBs generated from the fitted MPFB bodies.
- Rebuilt male and female medic character GLBs using those garments.
- Updated garment source notes and review previews.
