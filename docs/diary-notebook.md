# Diary notebook presentation

The diary reader uses Caveat day titles and 17px Lora prose, with quiet pencil
marks between entries. Conversation annotations reopen the existing reader;
an unwritten conversation shows the first nonempty user turn, limited to two
lines. The underlined writing prompt keeps its existing typography and placement.
The selected date remains in navigation; each sheet starts with its title or mood.

Saved stories show one mounted print or an overlapping stack, with a remaining count. Captions
and reflections are already in the saved prose and are not repeated on the mounts.
A miniature stack of photo prints carries a pencilled number and an ink plus;
the whole control opens the unchanged photo editor. Empty days show a single
empty print without a zero label. Screen readers retain the full photo count. Missing copies,
story ordering, read-only access, storage and sync semantics are unchanged.

## Fonts

Appearance retains Journal font and adds Diary title font and Diary body font.
The device-local preferences are `diary_title_font_family` and
`diary_body_font_family`; old or invalid settings default to Caveat and Lora.
Both bundled families work in either role offline. Other fonts use the existing
catalog and bounded download client. Selection is saved after loading succeeds;
errors appear in the picker without changing the saved font. A late previous
selection cannot overwrite a newer choice.

`DiaryTypography` supplies resolved styles to reading, paper snapshots and the
Appearance preview. A reader holds its current typography during a turn and
adopts a new selection when the gesture settles. Metadata, controls and writing
questions continue to use the interface font. Font licenses are bundled and
registered with Flutter.

## Rendering

The paper and curl renderer are retained. Entry widgets and geometry are cached
between entity/theme changes. The reading column is at most 560 logical pixels.
Print angles depend only on the entry identity. Borders, shadows and ink marks
use plain canvas drawing, with no new composited layers or animation controllers.

At most two images are decoded per story. The front print uses a 576px decode
bucket and the partly visible print behind it uses 384px, preserving aspect ratio and sharing identical
cache keys between live and curled faces. Neither dimension exceeds 640px. File
resolution is retained by each print's state rather than repeated while dragging.

## Verification

Run the notebook, typography, day-content, diary-page, daily-question, photo,
conversation, paper-curl, paper-material, diary-assistant and More widget tests.
`NOTEBOOK_CAPTURES=true` writes light, dark, narrow RTL at 2x text and tablet
paper previews to `/tmp/journal-notebook-*.png`.

The opt-in performance fixture uses temporary synthetic data, no account and no
real journal database. Run on the same phone before and after a change:

```sh
flutter drive --no-pub --profile -d DEVICE \
  --target=integration_test/diary_notebook_performance_test.dart \
  --driver=test_driver/diary_notebook_driver.dart \
  --dart-define=NOTEBOOK_PHASE=after
```

The driver writes `/tmp/journal-notebook-after.json`. As with other device tests,
restore a normal app build after using the integration-test entrypoint.

On Samsung SM-S928B, 24 measured alternating swipes plus long-page scrolling
produced these p95 frame timings (milliseconds):

These measurements cover the original paired-print presentation. The later
overlapping-stack layout has widget and curl coverage but has not been timed
again on the device.

| Run | Build | Raster |
| --- | ---: | ---: |
| Initial previous presentation | 7.876 | 62.687 |
| Initial notebook | 10.044 | 63.221 |
| Notebook with sized thumbnails | 10.336 | 67.085 |
| Previous presentation, repeated on the warmed phone | 10.054 | 64.118 |

The initial build-time increase exceeded the 10% investigation threshold. A repeat
of the prior presentation from isolated temporary source showed significant
device/run variation. Against that warmed reference, the final notebook differs
by +2.80% build and +4.63% raster. This is comparative evidence, not a 60fps claim:
the old presentation also had a high raster p95. Device logs reported Vulkan
shader compilation failures; the renderer and device graphics configuration were
not changed. Raw measurements are in `diary-notebook-performance.json`.

Widget tests additionally verify bounded curl textures, no per-frame recapture of
unchanged faces, matching questions across live/curl content, font-change deferral,
and that mixed notebook content needs no composited layers inside the paper.
