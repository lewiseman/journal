# I04 — Scan a physical note into editable text

From a saved note's wand menu, **Scan a page** photographs or imports a printed or handwritten page. The text is transcribed on the paired computer and shown for correction. Only on **Insert text and attach page** is the corrected text appended to the note and the page attached. General document ingestion, automatic rewriting and handwriting guarantees are out of scope; rewriting stays a separate, explicit N01 action afterwards.

## Flow

1. **Take photo** (camera) or **Choose image** (gallery) via `image_picker` (≤2400 px, metadata not requested). Denied camera/photo permission shows how to allow it. The picked file is immediately copied to app-owned storage (`<support>/note_scans/<uuid>.<ext>`); the original is never modified.
2. Preview the page and **Rotate** in 90° steps if needed. Rotation writes a new app-owned PNG through `dart:ui` and removes the previous copy.
3. **Read text** sends the page, re-encoded like I03 (PNG, ≤1280 px, metadata dropped), plus the fixed prompt `{"mode":"transcribe"}`. Nothing else about the note is sent.
4. Review:
   - **No legible text** (blank, blurred, wrong orientation) → explanation and *Try again with this page*.
   - Otherwise the transcription is in an editable field. Above it: whether a second reader cross-checked the page, chips for numbers and capitalised words the two readers disagree on ("Check these"), and the count of `[?]` marks. Nothing is corrected automatically.
   - **Original transcription** stays viewable while editing.
5. **Insert text and attach page** appends the edited text and adds the scan as an image attachment in one version-checked repository write, with a prior-body recovery copy ("Scanned text inserted"). The unedited transcription is saved beside the scan (`<scan>.json`) and shown under *Earlier scans of this note*. **Discard scan** deletes the copy.

## Protection and lifecycle

- **Stale note:** a changed note version marks the result stale and blocks insertion. A missing scan file does the same.
- **Retry integrity:** retries re-encode the app-owned page and compare SHA-256; a changed page is never re-sent (`SOURCE_CHANGED`).
- **Roles:** scanning is refused on read-only (secondary) devices before anything is sent, and the repository rechecks role at insertion.
- **Capability:** needs the computer's `vision` capability with `scanContract: 1` and status `ready` (after its image self-test).
- **Oversized or unsupported input:** source files over 40 MB or with an unknown signature are refused. Re-encoding steps down to fit 2.5 MB.
- **Storage:** scan copies and their original transcriptions are local, app-owned files. Account reset deletes `note_scans`. Unreferenced copies (picked but never inserted, or discarded) are swept after a day's grace whenever the scan page opens. Notes in Trash keep their scans. Sync copies the attachment **path only**: the image and original transcription are not backed up or transferred, and other devices see a path they cannot open (I03 shows it as not available).

## Verification

- `flutter test test/note_scan_test.dart` (6 tests): verbatim result parsing; disagreement flags (`3:15pm` vs `315pm`, `Priya's` vs `priyas`) and `[?]` counting; app-owned import/rotate/delete/original/sweep, including never deleting non-owned files; full request→insert flow (image route, fixed prompt, no note text, attachment added, original kept, recovery restore, path-only sync); stale note, changed page (no resubmit), foreign file, untested model and read-only device; account reset removing scans; widget flow pick → read → unreadable → retry → flags/marks shown → insert disabled for empty text.
- Full suite: 409 passed, 2 failed (the pre-existing `onboarding_test.dart` large-text overflow baseline).
- Real model runs, engine comparison and limits: [VISION.md](../../desktop/docs/VISION.md#i04-page-scanning) and [scan-evidence.json](../../desktop/docs/scan-evidence.json).

## Limitations

- **Handwriting:** only handwriting-style fonts were tested, not real handwriting. Real cursive, faint pencil, mixed layouts, tables and non-Latin scripts are unmeasured; the second reader is English/Latin-only. Treat every scan as a draft to check.
- No automatic perspective correction or cropping; users retake or rotate.
- No physical-phone camera run yet.
