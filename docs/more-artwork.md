# More menu artwork

Two original illustrations generated on 28 October 2026 with the built-in `image_gen` tool. No CLI/API fallback was used.

## Production assets

- [Appearance](../assets/images/more_appearance.png): `assets/images/more_appearance.png`.
- [Local QVAC](../assets/images/more_local_qvac.png): `assets/images/more_local_qvac.png`.

Both are 416 × 416 RGBA PNGs, downsampled using macOS `sips` with genuine alpha preserved. They display at 104 × 104 logical pixels, or 88 × 88 in narrower layouts, without runtime tinting. Large-text layouts prioritize the destination labels and actions. The assets are bundled by the existing `assets/images/` declaration.

## Visual direction and references

The pair follows the app's existing navigation artwork: tactile gouache and cut paper, muted indigo and lilac, sage and warm ivory, with small honey/brass and terracotta details. Both cutouts work on the app's original light and dark surfaces.

Appearance is an artist's fan of color samples in a folded paper sleeve with a short paintbrush. Local QVAC is an original conceptual compute module with a geometric Q core, a QVAC maker's plate and a journal note. It is not an official QVAC hardware product or a reproduction of the official logo.

The local/modular intelligence concept was informed by [QVAC's official ecosystem page](https://qvac.tether.io/?section=local-ai) and [the QV.AC assistant page](https://qv.ac/). Existing app assets `assets/images/navigation/notes_active.png` and `more_active.png` were inspected as style references; the tool received the textual specifications below.

## Generated masters

- Appearance: `/Users/lewis/.codex/generated_images/01a18262-870d-7280-b2a2-1eb5d58478c7/exec-e9917118-a84c-4eed-b973-72e2eb71f4f8.png`.
- Local QVAC: `/Users/lewis/.codex/generated_images/01a18262-870d-7280-b2a2-1eb5d58478c7/exec-f516095b-2b46-44b4-911c-b50730d876ed.png`.

The app uses the optimized workspace copies.

## Exact Appearance prompt

```text
Use case: stylized-concept.
Asset type: ONE original production raster cutout for the Appearance entry in a personal journaling Flutter app, displayed at about 104 by 104 logical pixels.
Primary request: an exquisite miniature artist's swatch set: three thick fanned color sample cards in muted lilac, sage and honey, partly tucked into a small warm-ivory folded paper sleeve, with one short indigo wooden paintbrush resting diagonally across the lower foreground. The brush has a small terracotta handle end and a warm brass ferrule. Make this a cohesive compact still life, not three disconnected symbols.
Style/medium: refined hand-painted gouache on tactile cut paper, softly sculptural 2.5D handmade stationery illustration. Visible delicate paper fibers, thick softly irregular edges, lovely gentle contained shadows between layers, soft upper-left lighting. Match a cozy journal app whose navigation uses lavender cloth books, sage paper notes, and an open purple keepsake box. Artistic and tactile, not a flat vector icon.
Palette: restrained muted indigo #65618c, lilac #b4abd3, sage #8c9b81, warm ivory #f4ead4, small honey #cfaa62 and terracotta accents. Medium-value silhouette and warm highlights must remain readable on both off-white #faf8fc and near-black #17151d.
Composition: square canvas, single centered object group filling about 84 percent of the canvas, broad rounded silhouette, near-frontal three-quarter view from slightly above, generous clean transparent padding, entire subject unclipped. 4-5 broad clear shapes that read immediately at 104px, finely crafted but not fussy.
Constraints: genuinely transparent alpha background and transparent negative space. No scene, tabletop, rectangular background, enclosing tile or badge, broad cast shadow, checkerboard, writing, letters, numbers, watermark, shiny plastic, neon, thick black outlines, tiny scattered props. ONE image only.
```

## Exact Local QVAC prompt

```text
Use case: stylized-concept.
Asset type: ONE original production raster cutout for a menu entry named Local QVAC in a personal journaling Flutter app, displayed at about 104 by 104 logical pixels.
Primary request: a charming miniature LOCAL QVAC computing atelier, a compact rounded lavender-indigo personal computer/compute module with a warm ivory inset front and a small sage-green modular geometric Q-shaped circuit core visible in its center. Add a clearly legible small ivory maker's plate reading exactly "QVAC" in restrained dark indigo uppercase letters, Q V A C, on the front lower bezel. At its side, one small warm-ivory folded journal note with two indigo abstract ink strokes slips into a little brass input slot; the note and device form one compact object. The idea is private intelligence living in a small local device helping with your writing. Give the core a clever interlocking layered-paper construction, a small warm honey status light, and a gently beveled base. No generic monitor with an AI sparkle, no robot.
Brand/concept reference: QVAC by Tether is a local-first AI ecosystem designed as modular intelligence running on your own hardware. Interpret this as an original handcrafted conceptual illustration, not a claim about an actual QVAC hardware product. Make QVAC recognizable through the exact maker's plate and the geometric Q core.
Style/medium: refined hand-painted gouache on tactile cut paper, softly sculptural 2.5D handmade stationery object. Delicate paper fibers and soft fabric-like housing, softly irregular layered edges, subtle contained shading, soft upper-left lighting. Match the same visual family as an app with lavender clothbound books, sage paper notes and a purple keepsake box; interesting, calm and premium, not a glossy tech icon.
Palette: muted indigo #65618c and lilac #b4abd3 housing, sage #8c9b81 geometric core, warm ivory #f4ead4 face and note, tiny honey #cfaa62 brass details. Medium-value silhouette and ivory highlights readable on both off-white #faf8fc and near-black #17151d.
Composition: square canvas, one centered compact object group filling 84 percent, near-frontal three-quarter view from slightly above, broad clear forms readable at 104px, entire subject unclipped, clean transparent padding.
Constraints: genuinely transparent alpha background and negative space. No room, tabletop, background tile, badge, glow cloud, broad cast shadow, connection diagram, watermark, neon, glossy plastic, thick outlines, scattered tiny props. No writing except the exact four-letter "QVAC" plate; the note has abstract strokes only. ONE image only.
```
