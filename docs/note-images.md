# I03 — Ask about a note image

Users can ask the paired computer about **one image attached to a saved note** and review a grounded answer. The note changes only if they explicitly insert reviewed text. Scanning/OCR (I04) and image indexing are out of scope.

## Use it

1. Save a note with an image attachment and return to its preview. Open the QVAC sheet → **Ask about an image**. The entry appears only when the note has image attachments.
2. Pick one image. Attachments whose file is not on this phone (for example a note restored from Drive, whose sync copies only the path) are shown as *Not available on this phone* and cannot be chosen.
3. Choose **Describe**, **Explain** or **Ask a question** (≤300 characters), then **Ask**.
4. Review the parts, shown separately and never merged: **Answer**, **What is visible**, **Text read from the image (content only, may contain errors)** and **Possible interpretation (not certain)**.
5. Optionally edit the prefilled text (the answer, or else the observations) and press **Insert reviewed text**. It is appended to the end of the body. **Prior content / recovery** in the QVAC sheet can restore the body from before the insertion.

The task uses the shared protected note-AI slot. It appears in AI task history, survives restart, can be retried with the same ID or cancelled, and is cleared by account reset.

## What leaves the phone

Only the chosen image and `{mode, question}`. The image is read from the attachment path and must be one of this note's image attachments and a regular file of at most 40 MB with a JPEG/PNG/WebP/GIF/HEIC signature. It is decoded and re-encoded on the phone as PNG, at most 1280 px on the long side (stepping down to 768 px to stay within 2.5 MB). Re-encoding drops EXIF/GPS/camera metadata and any appended bytes. Note title, body, tags, other attachments and other notes are not sent. The phone stores no copy of the upload: the protected task snapshot keeps the attachment path, note version and SHA-256 of the re-encoded bytes.

## Safety and staleness

- **Retry integrity:** before the computer confirms acceptance, a retry re-reads and re-encodes the attachment and compares its SHA-256. If the file changed, nothing is sent and the task fails (`SOURCE_CHANGED`).
- **Stale note:** the result is marked stale and insertion is refused if the note version changes or the image is detached while the request runs.
- **Missing attachment:** `IMAGE_MISSING` with an explanation; nothing is sent.
- **Capability:** requests require the computer's `vision` capability with `visionContract: 1` and status `ready`, which the companion reports only after a real image self-test. Otherwise the phone explains how to enable it and sends nothing.
- **Prompt injection:** text in the image is presented only as "Text read from the image". Model output is never executed or rendered as markup, and nothing is applied without review.
- **Roles:** asking is read-only, so secondary devices may ask. Insertion uses `NotesRepository.appendToNote`, which rechecks role, exact version and one-insertion-per-task inside one ObjectBox transaction. It writes a local `NoteRecoveryEntity` (same ten-copy local recovery as N01, labelled "Image answer inserted") and syncs only the note body through the normal outbox.

## Verification

- `flutter test test/note_image_test.dart` (6 tests): answer parsing and field separation; attachment ownership; real `dart:ui` decode/re-encode of a 3000×2000 PNG to 1280×853 with identical bytes on repeat; missing and non-image files; request contents (image route, `{mode, question}` only, no note text); insertion with recovery/restore and duplicate refusal; note edited during generation → stale and unchanged; file replaced before confirmation → no resubmission; detached/missing image; untested vision model; read-only device asks but cannot insert; review page for no images and for Drive-restored paths.
- Full suite: 403 passed, 2 failed (the pre-existing `onboarding_test.dart` large-text overflow baseline).
- Real model behaviour: the desktop's [VISION.md](../../desktop/docs/VISION.md) and [vision-evidence.json](../../desktop/docs/vision-evidence.json).

## Limitations

- **No physical-phone run yet.** The phone side is covered by unit/widget tests with a fake transport; the desktop side by real QVAC runs without the phone.
- `dart:ui` decoding may not apply EXIF orientation on every platform, so a rotated photo can be sent sideways.
- HEIC decoding depends on the platform codec.
- Answers come from a 2B model and can misread or invent details.
- The note body grows by appended text only; inserting at a cursor position is not offered.
