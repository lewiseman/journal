# I06 — Generate an optional note background

From a saved note's QVAC sheet, **Generate a background** creates an image on the paired computer from words the user types. The note changes only when they press **Use as background**, and the previous background can be restored.

## Flow

1. Type a one-line description (≤240 characters) and choose **Light** or **Dark**. Only those two values are sent. The note's title, text, tags, attachments and other notes are not.
2. **Generate** submits through the shared protected task slot. While the computer works, the page shows "step *n* of 20". You can leave and come back (also after restarting the app), or **Cancel**, which stops the computer within a couple of seconds.
3. When done, the phone downloads the image over the signed result route and checks its SHA-256, byte count and PNG dimensions against what the computer reported. A mismatch is refused (`INVALID_OUTPUT`) and nothing is saved. The verified image becomes a private preview (`<support>/note_backgrounds/generated/previews/<task>.png`).
4. The preview is shown as the note will look: the image under the note's 80%-opaque paper with the title in the note's ink colour, so legibility can be judged. The existing editor also adapts header contrast to the image.
5. Choose:
   - **Use as background:** copies the preview to `note_backgrounds/generated/<uuid>.png` and records what it replaces in `<uuid>.png.previous.json`. It then writes the note through `NotesRepository.setNoteBackground` (only if the background is still the one it was requested for). Colour type and text are kept; text edits made meanwhile are fine.
   - **Generate another:** discards this preview and runs the same description again.
   - **Discard:** deletes the preview. The note is unchanged.
6. **Restore the previous background** appears while the current background is a generated one. It is compare-and-set: refused if the background was changed again.

## Persistence, roles and sync

- Accepted backgrounds are ordinary note writes (version increment, `pendingUpload`, outbox) and persist across restart.
- Generated images, previews and recovery records are app-owned files under `note_backgrounds`, which account reset already removes. Unaccepted previews are deleted after 24 hours. The computer deletes its encrypted copy once the phone acknowledges (on accept/discard) or after 24 hours.
- **Sync carries the background choice (a local file path), not the image bytes.** Other devices cannot show a generated image unless it exists at that path there; they keep their own look. No media backup is added.
- Generating and applying are refused on read-only (secondary) devices before anything is sent; the repository rechecks role at write.
- Readiness requires the computer's `image` capability (`backgroundContract: 1`) to be `ready`, i.e. an assigned, installed model that fits memory and passed a real generation test. Otherwise the page explains what to do on the computer.

## Verification

- `flutter test test/note_background_test.dart` (5 tests): only `{prompt, tone}` sent; progress message; verified collection; accept with a text edit made meanwhile; background, colour and content preserved; persistence; path-only sync; acknowledgment; revert and repeat-revert refusal; a mismatched image refused then collected on retry; background changed meanwhile → stale and unchanged; cancel → cancelled and unchanged; untested model and read-only device send nothing; preview expiry keeps the active task; account reset removes generated files.
- Full suite: 414 passed, 2 failed (the pre-existing `onboarding_test.dart` large-text overflow baseline).
- Real generation, cancellation and SDK findings: the desktop's [BACKGROUNDS.md](../../desktop/docs/BACKGROUNDS.md) and [background-evidence.json](../../desktop/docs/background-evidence.json).

## Limitations

- No physical-phone run in this milestone.
- Generation takes about a minute on the reference Mac.
- Images can contain text-like artefacts and follow the tone loosely.
- Generated backgrounds are not synchronised as images.
- The recovery record covers one step back (the background a generated one replaced), not a full history.
