# Local AI studio artwork

Three original transparent cutouts generated with the built-in imagegen tool on 30 October 2026. No CLI/API fallback was used. Production assets `ai_studio_computer.png`, `ai_studio_phone.png` and `ai_studio_auto.png` are downsampled to 768 pixels wide with macOS `sips`, preserving alpha. The existing `assets/images/` bundle entry includes them. They form the swipeable illustration stage on the Local AI page; the app draws all type, status, paper surfaces and interactions separately.

## Production paths and source masters

- `assets/images/ai_studio_computer.png`: source `/Users/lewis/.codex/generated_images/01a18be1-4771-7bc0-ba69-407c83298c96/exec-ea52e607-7c3a-4e00-a468-b30d2c75d221.png`.
- `assets/images/ai_studio_phone.png`: source `/Users/lewis/.codex/generated_images/01a18be1-4771-7bc0-ba69-407c83298c96/exec-5b1c419c-12b4-403a-8670-32ab32f7681a.png`.
- `assets/images/ai_studio_auto.png`: source `/Users/lewis/.codex/generated_images/01a18be1-4771-7bc0-ba69-407c83298c96/exec-ceacdf17-26c1-46ce-9488-2f104c10df70.png`.

The shared paper surfaces reuse `DiaryPaperShape` and `DiaryPaperPainter`. Headings use the bundled Lora typeface; handwritten captions use bundled Caveat. The image stage responds to the horizontal drag with a small scale, lift and rotation, with motion removed when animations are disabled. View setup scrolls to the selected provider's controls. At larger text sizes, the decorative headline becomes compact and handwritten captions are omitted so the controls remain easier to reach.

## Exact generation prompts

### computer

```text
Use case: stylized-concept.
Asset type: ONE original production UI hero illustration for a premium personal journaling app. This is a full-color transparent cutout object scene, displayed about 300 by 220 logical pixels, not an app screenshot.
Style: beautifully tactile, softly sculptural 2.5D miniature stationery still life, hand-painted matte gouache and thick layered cut paper with cloth fibers, subtly rounded handmade edges, warm ivory highlights and soft upper-left lighting. Detailed material craft with large readable forms, a calm playful collectible-diorama feeling. This app's visual identity uses a chunky lilac papercraft retro computer, sage paper boats, cream journals and indigo pencils.
Palette: dusty lilac #b4abd3, muted indigo #65618c, sage #8c9b81, ivory #f4ead4, tiny honey brass #cfaa62 accents. Medium-value silhouettes and light highlights so the cutout reads on both warm off-white and dark plum. Avoid saturated colors and glossy plastic.
Composition: landscape 4:3 canvas, compact centered still life filling 88 percent width and height with modest transparent margins, three-quarter view from slightly above, no objects clipped. Ground the objects together with tiny contained contact shadows only. Visually rich but clean silhouette. No surrounding room, desk surface, floor, background tile or enclosing badge.
Critical: genuinely transparent RGBA background in all negative space and corners. No white background, checkerboard, lettering, words, numbers, logos, watermark, faces, robots, brains, UI panels, cartoon outlines or excessive floating decorations. ONE image only.
Subject: A charming chunky lavender RETRO DESKTOP COMPUTER with a warm ivory inset screen, sage screen glass and a simple little raised cream four-point spark inset on the screen. Rounded thick textured paper body, two tiny honey-gold physical buttons, a small matching ivory-and-lilac keyboard in front. In front-left sits one beautiful small open warm ivory journal with a sage cloth cover, two blank curved pages and a lavender ribbon bookmark. A short muted-indigo wooden pencil rests diagonally across the front, with a tiny honey brass ferrule. The computer is the dominant tall form in the back-right, journal and pencil balance its lower left. A cozy little thinking desk, inviting and personal. Stationery forms have real layered thickness and refined handmade material depth.
```

### phone

```text
Use case: stylized-concept.
Asset type: ONE original production UI hero illustration for a premium personal journaling app. This is a full-color transparent cutout object scene, displayed about 300 by 220 logical pixels, not an app screenshot.
Style: beautifully tactile, softly sculptural 2.5D miniature stationery still life, hand-painted matte gouache and thick layered cut paper with cloth fibers, subtly rounded handmade edges, warm ivory highlights and soft upper-left lighting. Detailed material craft with large readable forms, a calm playful collectible-diorama feeling. This app's visual identity uses a chunky lilac papercraft retro computer, sage paper boats, cream journals and indigo pencils.
Palette: dusty lilac #b4abd3, muted indigo #65618c, sage #8c9b81, ivory #f4ead4, tiny honey brass #cfaa62 accents. Medium-value silhouettes and light highlights so the cutout reads on both warm off-white and dark plum. Avoid saturated colors and glossy plastic.
Composition: landscape 4:3 canvas, compact centered still life filling 88 percent width and height with modest transparent margins, three-quarter view from slightly above, no objects clipped. Ground the objects together with tiny contained contact shadows only. Visually rich but clean silhouette. No surrounding room, desk surface, floor, background tile or enclosing badge.
Critical: genuinely transparent RGBA background in all negative space and corners. No white background, checkerboard, lettering, words, numbers, logos, watermark, faces, robots, brains, UI panels, cartoon outlines or excessive floating decorations. ONE image only.
Subject: A charming small SAGE AND LILAC PAPERCRAFT PHONE standing upright, tilted gently backward with a thick rounded sage casing and an inset warm ivory screen. The screen contains just one small raised honey-gold four-point spark, no app interface or writing. One broad cream paper writing sheet curls gently out from behind the phone on the left, with a folded lilac corner, and a short muted-indigo pencil leans diagonally along the paper's lower front edge. A small lavender fabric ribbon loops from behind the sheet. Phone is the dominant tall form, handmade writing sheet and pencil provide a balanced lower-left silhouette. A beautiful compact pocket creativity kit, tactile and inviting. Real layered cardstock thickness and cloth/paper fibers, consistent refined miniature craft.
```

### auto

```text
Use case: stylized-concept.
Asset type: ONE original production UI hero illustration for a premium personal journaling app. This is a full-color transparent cutout object scene, displayed about 300 by 220 logical pixels, not an app screenshot.
Style: beautifully tactile, softly sculptural 2.5D miniature stationery still life, hand-painted matte gouache and thick layered cut paper with cloth fibers, subtly rounded handmade edges, warm ivory highlights and soft upper-left lighting. Detailed material craft with large readable forms, a calm playful collectible-diorama feeling. This app's visual identity uses a chunky lilac papercraft retro computer, sage paper boats, cream journals and indigo pencils.
Palette: dusty lilac #b4abd3, muted indigo #65618c, sage #8c9b81, ivory #f4ead4, tiny honey brass #cfaa62 accents. Medium-value silhouettes and light highlights so the cutout reads on both warm off-white and dark plum. Avoid saturated colors and glossy plastic.
Composition: landscape 4:3 canvas, compact centered still life filling 88 percent width and height with modest transparent margins, three-quarter view from slightly above, no objects clipped. Ground the objects together with tiny contained contact shadows only. Visually rich but clean silhouette. No surrounding room, desk surface, floor, background tile or enclosing badge.
Critical: genuinely transparent RGBA background in all negative space and corners. No white background, checkerboard, lettering, words, numbers, logos, watermark, faces, robots, brains, UI panels, cartoon outlines or excessive floating decorations. ONE image only.
Subject: A charming chunky miniature LAVENDER RETRO DESKTOP COMPUTER on the left paired with a slightly smaller SAGE PAPERCRAFT PHONE on the right. Both have warm ivory frames and inset sage screen glass with one simple small raised ivory four-point spark, no app interfaces. A broad softly curved strip of warm ivory folded paper lies in an elegant shallow S on the ground BETWEEN the two devices, connecting them into ONE compact composition like a little paper bridge. A single tiny honey brass star sits on the paper bridge. A tiny lilac keyboard belongs only to the computer. The computer is slightly taller, phone slightly in front, beautifully balanced two-device still life. Very refined paper/cloth textures and layered thickness, no arrows, cloud, globe or infinity symbol.
```

