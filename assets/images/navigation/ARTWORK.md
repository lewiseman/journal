# Journal navigation artwork

Eight original transparent PNG illustrations generated with the built-in `image_gen` tool on 25 October 2026. No CLI/API fallback was used.

## Visual direction

Hand-painted gouache and tactile cut-paper stationery, inspired by the app's warm onboarding book, paper notes, indigo ink, sage, honey and terracotta details. Shared materials, illumination and palette keep the destinations in one visual family.

| Destination | Inactive | Active |
| --- | --- | --- |
| Diary | Closed clothbound journal | Open journal with a sun and ribbon |
| Notes | Resting paper stack and pencil | Fanned notes, writing pencil and gold glint |
| Flow | Resting paper boat | Boat sailing over two brushstrokes |
| More | Closed keepsake box | Open box revealing a botanical card and film ticket |

The same full-color cutouts are used in light and dark themes. Medium-value lilac/indigo silhouettes and warm ivory highlights give each object contrast on both surfaces. No runtime monochrome tint or reduced inactive opacity is applied. Labels and the existing selection glow continue to use the user's accent color.

## Production assets

All `*_active.png` and `*_inactive.png` files in this directory are 192 × 192 RGBA PNGs, downsampled from generated masters using macOS `sips` with alpha preserved. They occupy fixed 44 × 44 logical-pixel layout slots in `JournalBottomNavbar`, rendering at about 36 pixels inactive and 47 pixels active. Selection lifts the artwork 3 pixels with a subtle 320 ms spring settle; deselection returns in 180 ms. Both states stay mounted and crossfade over 150 ms. Pressing compresses only the artwork, and changing tabs triggers one selection haptic. Labels stay in place while a stronger, theme-aware edge glow follows the selection, with luminance compensation to keep lower-contrast accents visible. Navbar transitions use fixed durations without a custom reduced-motion branch.

Keep transparent padding and visual weight consistent when replacing an image. Do not add a background tile or bake a light/dark surface into the artwork.

## Generation order and references

1. Generate `diary_active.png` as the material/style anchor.
2. Use that anchor as the reference for the four inactive destination images.
3. Use each destination's inactive image as the identity reference for its active counterpart (Notes, Flow, More).

The full-resolution source masters remain in the original built-in generation output directory; the app consumes only the optimized workspace assets.

## Exact prompt set

### diary_inactive.png

```text
Use case: style-transfer. Asset type: one production transparent-background bottom navigation illustration, 44px display size.
Reference image role: style and material reference for a coordinated set in a personal journaling app. Transform the reference into the subject below. Preserve the SAME refined hand-painted gouache, tactile cut-paper texture, gently sculptural 2.5D handmade stationery style, soft upper-left lighting, gently rounded paper edges, and restrained palette. Artistic yet immediately readable at 44px, 3-4 large clear shapes. Warm ivory #f4ead4, muted indigo #65618c and lilac #b4abd3, sage #8c9b81, small honey #cfaa62 / terracotta accents. Preserve a medium-value silhouette with light areas so it reads on BOTH near-black #17151d and off-white #faf8fc.
Square canvas. One isolated centered compact object, fills 82 percent of canvas, generous transparent padding, nothing clipped. Near frontal three-quarter view from slightly above. Soft contained object shading only.
Real transparent alpha, clean cutout, no background, no checkerboard, no enclosing circle/tile/badge, no scene, no lettering or words or watermark. No glossy plastic, thick black outline, fussy tiny details or broad cast shadow. Produce ONE object/image, not a sprite sheet.
Subject: DIARY INACTIVE state. The same lavender-indigo clothbound journal as the reference, now CLOSED with its soft cloth cover visible, a slim warm ivory page block visible on the right edge and the same small terracotta ribbon bookmark peeking from the bottom. A subtle small debossed sun emblem centered on the cover, matching the sun on the open book. Calm, resting, slightly muted but fully opaque and legible. Preserve the reference book's overall scale and style, with a comfortably broad book silhouette. This is a closed companion of the selected open diary.
```

### diary_active.png

```text
Use case: stylized-concept.
Asset type: one production transparent-background bottom navigation illustration for a warm personal journaling Flutter app, DIARY selected state.
Primary request: an inviting miniature OPEN CLOTHBOUND DIARY, visibly two facing warm ivory pages, lavender-indigo fabric cover, a single little terracotta ribbon bookmark hanging from the center fold, and a tiny honey-gold sun painted on one page. No writing or letters.
Style/medium: refined hand-painted gouache on tactile cut paper, softly sculptural 2.5D paper-collage object, restrained wabi-sabi stationery illustration, softly rounded handmade edges, gentle natural shading. Artistic but SIMPLE, 3-4 large shapes; must read immediately at just 44px.
Composition: single isolated centered object, square canvas, near frontal three-quarter view from slightly above, fills about 82 percent of the canvas with generous unclipped padding. Main silhouette roughly square. No other scene elements.
Palette: warm ivory paper, muted indigo #65618c, lilac #b4abd3, honey gold #cfaa62 and a small terracotta ribbon. Medium-value cover edges with light paper interiors ensure visibility on BOTH near-black #17151d and warm off-white #faf8fc. Keep the handmade warm journal mood, not shiny plastic.
Lighting: soft upper-left illumination, subtle contained contact shading under the object, no broad cast shadow.
Constraints: real transparent alpha background, clean cutout with no background, no checkerboard, no colored tile, no badge or enclosing circle, no text, no watermark, no thin wispy details, no photorealism, no glossy emoji, no thick black outlines. Only one image/object, never a sprite sheet.
```

### notes_inactive.png

```text
Use case: style-transfer. Asset type: one production transparent-background bottom navigation illustration, 44px display size.
Reference image role: style and material reference for a coordinated set in a personal journaling app. Transform the reference into the subject below. Preserve the SAME refined hand-painted gouache, tactile cut-paper texture, gently sculptural 2.5D handmade stationery style, soft upper-left lighting, gently rounded paper edges, and restrained palette. Artistic yet immediately readable at 44px, 3-4 large clear shapes. Warm ivory #f4ead4, muted indigo #65618c and lilac #b4abd3, sage #8c9b81, small honey #cfaa62 / terracotta accents. Preserve a medium-value silhouette with light areas so it reads on BOTH near-black #17151d and off-white #faf8fc.
Square canvas. One isolated centered compact object, fills 82 percent of canvas, generous transparent padding, nothing clipped. Near frontal three-quarter view from slightly above. Soft contained object shading only.
Real transparent alpha, clean cutout, no background, no checkerboard, no enclosing circle/tile/badge, no scene, no lettering or words or watermark. No glossy plastic, thick black outline, fussy tiny details or broad cast shadow. Produce ONE object/image, not a sprite sheet.
Subject: NOTES INACTIVE state. A tidy compact stack of TWO square-ish slightly irregular torn paper notes, warm ivory rear sheet and sage green front sheet, accompanied by one short muted-indigo wooden pencil resting diagonally across the lower right corner. Two bold short indigo handwritten-like horizontal strokes on the front sheet; these are abstract marks, NO letters. Paper faces camera. Quiet restful composition, flat stacked sheets, mostly sage and cream. Distinct from a bound book. Restrict to stack and pencil only.
```

### notes_active.png

```text
Use case: precise-object-edit. Asset type: one production transparent-background 44px bottom navigation illustration, NOTES ACTIVE selected state.
Reference image role: edit target / exact identity reference for inactive notes in a coordinated paper stationery illustration set.
Primary request: create the selected companion of these EXACT SAGE NOTES AND INDIGO PENCIL. Gently FAN APART the two sheets, tilt the front sage sheet a little upward, and lift the same short indigo pencil so it sits diagonally along the right side with its graphite TIP TOUCHING the lower handwritten stroke on the front sheet, actively writing. Keep the same two bold indigo abstract horizontal strokes on the sage note, no letters. The lifted front corner reveals the warm ivory rear sheet. Add one small honey-gold four-point glint attached near the top right of the note, a large enough simple shape to read at 44px. A livelier open composing pose clearly different from the resting stack. Keep the composition compact and the sage sheet as the largest shape.
Invariants: retain same objects, scale, colors, near-frontal three-quarter view, refined hand-painted gouache cut-paper material, softly sculptural 2.5D handmade stationery aesthetic, rounded torn paper edges, soft upper-left lighting. Warm ivory #f4ead4, muted indigo #65618c, sage #8c9b81, small honey-gold accent. Bold simple shapes with fully opaque crisp paper silhouettes readable on BOTH near-black #17151d and off-white #faf8fc.
Square canvas, single compact centered illustration occupying 82 percent, generous transparent padding, nothing clipped. Genuine transparent alpha background. No background or checkerboard or enclosing tile/circle/badge or words or lettering or watermark. No glossy plastic, thick black outline, fussy small details, flowers, broad cast shadow or scene. One image only, no sprite sheet.
```

### flow_inactive.png

```text
Use case: style-transfer. Asset type: one production transparent-background bottom navigation illustration, 44px display size.
Reference image role: style and material reference for a coordinated set in a personal journaling app. Transform the reference into the subject below. Preserve the SAME refined hand-painted gouache, tactile cut-paper texture, gently sculptural 2.5D handmade stationery style, soft upper-left lighting, gently rounded paper edges, and restrained palette. Artistic yet immediately readable at 44px, 3-4 large clear shapes. Warm ivory #f4ead4, muted indigo #65618c and lilac #b4abd3, sage #8c9b81, small honey #cfaa62 / terracotta accents. Preserve a medium-value silhouette with light areas so it reads on BOTH near-black #17151d and off-white #faf8fc.
Square canvas. One isolated centered compact object, fills 82 percent of canvas, generous transparent padding, nothing clipped. Near frontal three-quarter view from slightly above. Soft contained object shading only.
Real transparent alpha, clean cutout, no background, no checkerboard, no enclosing circle/tile/badge, no scene, no lettering or words or watermark. No glossy plastic, thick black outline, fussy tiny details or broad cast shadow. Produce ONE object/image, not a sprite sheet.
Subject: FLOW INACTIVE state. A simple folded PAPER BOAT representing a passing thought carried gently onward. Sculptural warm ivory and muted lilac paper with one broad sage folded panel, three clearly visible triangular folds, one pointed upward central fold. Calm and resting, compact centered silhouette, no water or surroundings or motion marks. The boat is the only object. Strong recognizable folds that read even at 44px. Same tactile gouache cut-paper style as the reference journal; do not include a book or pencil.
```

### flow_active.png

```text
Use case: precise-object-edit. Asset type: one production transparent-background 44px bottom navigation illustration, FLOW ACTIVE selected state.
Reference image role: edit target / exact identity reference for the inactive paper boat in a coherent handmade journal stationery set.
Primary request: create the SELECTED, GENTLY SAILING companion of this EXACT paper boat. Keep the boat made from the same lilac, warm ivory and sage folded paper. Give it a small jaunty upward tilt with the right bow slightly higher, and add TWO SHORT BROAD SAGE GOUACHE SWOOSHES just underneath the hull, curving toward the left like a gentle current carrying a passing thought. Add one small honey-gold four-point glint near the right bow. The swishes and the slight tilt express the Flow destination: thoughts drifting forward. The boat remains the dominant simple silhouette. Slightly richer muted-indigo shading on the front fold than the resting state. Compact, calm and joyful, not a busy scene. At 44px the selected moving boat must look distinct from the static resting one.
Invariants: SAME paper-boat identity and folds, hand-painted gouache on tactile cut paper, softly sculptural 2.5D craft aesthetic, paper texture, soft upper-left lighting, near-frontal three-quarter view from slightly above, scale and palette. Warm ivory #f4ead4, muted indigo #65618c, lilac #b4abd3, sage #8c9b81 and honey #cfaa62. A clear medium-value silhouette and cream edges readable on BOTH near-black #17151d and off-white #faf8fc.
Square canvas, single centered illustration filling 82 percent, generous transparent padding, nothing clipped. Truly transparent alpha background including gaps between swishes. No background or environment, no blue water scene, no broad cast shadow, no enclosing tile/circle/badge, no text, no watermark, no glossy plastic or thick black outlines or fussy particles. One image only, no sprite sheet.
```

### more_inactive.png

```text
Use case: style-transfer. Asset type: one production transparent-background bottom navigation illustration, 44px display size.
Reference image role: style and material reference for a coordinated set in a personal journaling app. Transform the reference into the subject below. Preserve the SAME refined hand-painted gouache, tactile cut-paper texture, gently sculptural 2.5D handmade stationery style, soft upper-left lighting, gently rounded paper edges, and restrained palette. Artistic yet immediately readable at 44px, 3-4 large clear shapes. Warm ivory #f4ead4, muted indigo #65618c and lilac #b4abd3, sage #8c9b81, small honey #cfaa62 / terracotta accents. Preserve a medium-value silhouette with light areas so it reads on BOTH near-black #17151d and off-white #faf8fc.
Square canvas. One isolated centered compact object, fills 82 percent of canvas, generous transparent padding, nothing clipped. Near frontal three-quarter view from slightly above. Soft contained object shading only.
Real transparent alpha, clean cutout, no background, no checkerboard, no enclosing circle/tile/badge, no scene, no lettering or words or watermark. No glossy plastic, thick black outline, fussy tiny details or broad cast shadow. Produce ONE object/image, not a sprite sheet.
Subject: MORE INACTIVE state. A small closed KEEPSAKE BOX for collecting life's little things. Compact broad square rounded box in muted lilac-indigo textured paperboard, a warm ivory gently domed lid, and a small honey-gold star printed in its center. A narrow terracotta pull tab on its front. Near-frontal three-quarter angle shows lid and front. Quiet resting closed state. The box is the only object, no floating items. Same tactile hand-painted paper material and muted warmth as the reference journal. Do not include a book or pencil.
```

### more_active.png

```text
Use case: precise-object-edit. Asset type: one production transparent-background 44px bottom navigation illustration, MORE ACTIVE selected state.
Reference image role: edit target / exact identity reference for an inactive keepsake box in a coherent journal stationery illustration set.
Primary request: OPEN THIS SAME KEEPSAKE BOX to create the selected companion image. Keep the muted lilac-indigo textured paperboard base, small terracotta front pull tab, warm ivory lid and tiny honey-gold star on that lid. Lift and tilt the lid toward the back so the box is clearly open. Just TWO broad keepsakes peek out: a sage paper card and a warm ivory film ticket with two bold indigo perforation marks, plus the existing gold star on the lifted lid. A compact inviting feeling of a little collection of memories. The open silhouette must be distinct from the closed box, with a gentle sense of discovery.
Invariants: SAME refined hand-painted gouache cut-paper material, subtly sculptural 2.5D handmade stationery aesthetic, softly rounded edges, near-frontal three-quarter angle from slightly above, upper-left soft lighting, same overall scale as the reference. Only change the lid position and add the two keepsakes. Restrained warm ivory #f4ead4, muted indigo #65618c, lilac #b4abd3, sage #8c9b81, honey #cfaa62, terracotta. Bold simple shapes readable at 44px and on BOTH near-black #17151d and off-white #faf8fc. Crisp fully opaque paper edges against transparent surroundings.
Square canvas, one compact centered object filling 82 percent of canvas, generous transparent margin, no clipping. Truly transparent alpha background. No background, checkerboard, enclosing tile/circle/badge, environment, words, lettering, watermark, glossy plastic, thick black outlines or fussy floating debris. Only one image, not a sprite sheet.
```
