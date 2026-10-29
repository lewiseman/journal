# I02 — Diary photo questions from your computer

Choosing photos and tapping **Generate questions** asks the paired computer
about each photo. Qwen3-VL there writes questions under **The moment**,
**The feeling** and **The little things**. Until a photo's questions arrive,
and whenever the computer isn't available, that photo shows the usual questions
from I01. Nothing is saved until **Save to diary**, as before.

The companion side is described in
[`desktop/docs/VISION.md`](../../desktop/docs/VISION.md#i02-diary-photo-questions).

## Use

1. Choose photos and tap **Generate questions**. Reflect opens and shows a
   spinner, "Writing questions for your photos…", with **Stop**, until the
   computer has finished every photo. The shared task slot runs one request at
   a time, so photos are asked about in order. **Stop** drops the waiting
   photos and cancels the current one.
2. Reflect then shows the question desk. Each photo that got questions has
   them under its three groups; any photo that didn't keeps the usual
   questions. Answers already written are never lost: an answered question
   stays reachable in its group whichever questions are showing.
3. Photos that already have questions (cached by photo) aren't asked again,
   and neither are photos that aren't on this device. If the computer refuses
   before anything is sent (not connected, no vision model, another AI task
   open), nothing more is tried and a short snackbar says why once.

There is no info panel on Reflect. The computer's observations of each photo
are validated and cached but not shown; the entry still shows a saved `seen`
note, labelled, for stories that have one.

Reopening a saved story at its entry doesn't ask again; it shows any questions
still cached for its photos.

## What is sent and kept

- **Sent:** the photo re-encoded as PNG at most 1280 px (drops EXIF, location
  and anything appended), and the caption as typed (≤240 characters). No diary
  text, date, other photos or file names are sent. The request goes through
  the shared, recoverable AI task slot (R01) on the signed image route.
- **Kept on the phone, local only, never synced**, under
  `<support>/diary_photo_questions`:
  - `<photo sha256>.json`: the validated questions and observations for that
    exact photo, kept for 30 days and then deleted. Results are keyed by the
    photo's bytes, not its position, so reordering, removing or adding photos
    never attaches questions to the wrong one. A different photo gets its own
    request.
  - `uploads/<task id>.png`: the exact upload, kept only until its task is
    cleared, so a retry after an interrupted submission resends identical
    bytes. A retry whose upload is missing or changed sends nothing and says
    why.
  - Account reset deletes the whole folder.
- **Saved in the diary (synced like other photo-story fields):** each answer
  now records its `group` (`moment`, `feeling` or `little`) and
  `"source": "photo"` when the computer wrote the question. A photo's optional
  `seen` text is stored separately and is **not** part of `content`, so search,
  daily questions, suggestions and summaries see only the person's words.
  Older records without these fields read and write exactly as before.

## Recovery

A finished result is moved into the local cache by an app-wide listener, so it
arrives even if the photo page was closed or the app restarted. The listener
then clears the task slot for the next photo. A failure, cancellation, expiry
or interruption leaves a short reason on that photo, and the usual questions
remain. If another feature's task holds the slot, the page names it instead of
silently doing nothing.

Not recovered: unsaved answers in a story that was never saved, if the app is
killed. I01 writes nothing before Save, and that is unchanged. The generated
questions do survive (they are cached by photo), so re-picking the same photo
shows them again.

## Verification

```sh
flutter test test/diary_photo_questions_test.dart test/diary_photos_page_test.dart test/diary_photo_stories_test.dart
```

- `diary_photo_questions_test.dart` (12 tests) uses the real task controller,
  real file storage and a fake signed transport. It covers:
  - parsing and limits;
  - cache expiry, upload pruning and account reset;
  - exactly what is sent;
  - caching and freeing the slot;
  - an unavailable vision model sending nothing;
  - a lost acceptance retrieved after a restart without a second upload;
  - a changed upload refused;
  - failed jobs, and the slot held by another task;
  - Generate questions asking about each photo in turn, skipping cached and
    missing photos, stopping with one reason when there's no vision model, and
    Stop generating;
  - JSON round-trip with `seen` kept out of `content`.
- `diary_photos_page_test.dart` adds 4 widget tests over ObjectBox:
  - generated questions shown with no info panel, saved with group and source;
  - a usual-question answer surviving when photo questions arrive;
  - the loading state until the computer finishes, and Stop;
  - no vision model: the usual questions, the reason once, nothing repeated.
- The full suite passed: 575 tests.

Real model evidence is in
[`desktop/docs/photo-questions-evidence.json`](../../desktop/docs/photo-questions-evidence.json).

## Limitations

- **Not run on a phone yet.** No device was attached (`adb` isn't installed on
  this Mac), so phone ↔ computer behaviour is shown only with the fake
  transport. Run the I01 device test pattern with a paired companion before
  claiming device support.
- Question quality is limited by the 2B model; see the desktop doc.
- The note summary/writing pages don't have a dedicated view for a photo task
  that holds the shared slot. It appears as "Photo questions" in AI task
  history, and the photo page's loading state offers Stop.
- Photos added to a reopened story aren't asked about, since its footer shows
  **Back to entry** rather than **Generate questions**.
- No face identification, library-wide analysis or background generation:
  only the photos the person chose for this story, one request per photo.
