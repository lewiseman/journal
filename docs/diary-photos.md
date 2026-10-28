# I01 — Save and reopen diary photo stories

Photo stories are saved to the diary and can be reopened. Before this, the photo
flow was preview-only. The I01 milestone needs no image inference and makes no
desktop or companion changes. The reflection questions are still fixed sample
prompts. Real photo questions are milestone I02.

## Use

1. On the diary page, tap the image action and choose photos.
2. Choose **Just the photos**, or **Generate questions**. The reflection page
   says "Sample questions for now · not drawn from your photos, and nothing is
   sent."
3. Read the entry. Then choose **Save to diary**. Only this button writes
   anything. Closing with **Close without saving**, going back, or leaving
   while the picker is open saves nothing and creates no files.
4. The diary page shows the story's prints in order (four at most, then "+N"),
   followed by its words. Tap the prints to reopen the story at its entry.
   **Edit photos** adds, removes, reorders and recaptions photos, and the
   reflect tabs revisit answers. **Save changes** keeps the story's ID.
   Closing without saving changes nothing.

The entry footer says: "Photos stay on this device. Sync shares captions and
words, not photos." Nothing claims cross-device photo backup.

## What is stored

A story is one `DiaryItem`, so it gets the existing item ID, ordering, LWW
merge, tombstones and sync outbox. Its new optional `photos` list holds the
photos in order. For each photo it stores:

- `id`: a stable UUID. It survives reorders and edits so that I02 can cite a
  photo.
- `path`: relative, for example `diary_photos/<id>.jpg` under the app support
  directory. It names an app-owned copy.
- `sha256`: a hash of the copy's bytes. It identifies the source and drops
  re-picked duplicates without recording picker paths, file names or EXIF.
  The picker is already called with `requestFullMetadata: false`.
- `caption`, and `reflections` as `{question, answer}` pairs, with blank
  answers dropped.

The legacy `attachment_paths` field mirrors the ordered paths for older
readers. A text item never writes `photos`, so text documents stay
byte-identical. Malformed photo records are skipped, so they never hide an
entry. `content` is the reviewed words only: captions and answers, without
prompts. "Just the photos" with no captions gives empty content.

**Readers.** `visibleItems` still filters on text. Search, daily questions,
history, suggestions and summaries therefore see only the user's words and
never get an empty photo-only item. A new `displayItems` also includes
photo-only stories. The diary page and calendar use it. **Day details** and
**Presentation** appear only when the day has entries with text.

**Copies.** `DiaryPhotoStore` writes each copy through a `.partial` file and a
rename, and only when you save. If the save then fails, it removes the copies
it just made. An edit deletes a removed photo's copy after the new record
commits, and only when no other live item references it. Only well-formed
`diary_photos/<name>` paths are ever resolved or deleted. Absolute paths,
traversal, picker files and the source photo in the gallery are never
touched.

**Device roles.** These are the same as for text. A secondary device can save a
new story for today, which goes into the outbox with its photo records. It can
open saved stories read-only, without Edit or Save, and it sees "Saved stories
can be changed on your primary device." The repository rechecks the role
inside the write transaction.

**Sync and missing photos.** Sync copies the records, not the bytes. On another
device, or if a copy is gone, the photo shows **Not on this device**, and the
footer says some photos are kept on the device that added them. The record is
kept when the story is edited, so a primary-device edit never silently drops a
photo that was added on a secondary device.

**Reset.** Account reset now deletes `<support>/diary_photos` along with
`note_backgrounds`. It does this without following links.

## Verification

Run these tests:

```sh
flutter test test/diary_photos_page_test.dart test/diary_photo_stories_test.dart \
  test/diary_day_content_test.dart test/diary_storage_test.dart \
  test/account_reset_integration_test.dart
```

- `diary_photos_page_test.dart` has 23 widget tests over ObjectBox and an
  in-memory copy store. They cover:
  - saving a photo-only story;
  - a reflected story with order, captions and reviewed words, reopened after
    an ObjectBox restart;
  - reorder and remove with release of the removed copy;
  - close and back without saving, for both new and reopened stories;
  - a photo missing on this device being kept through an edit;
  - read-only reopen;
  - a secondary device saving today and being refused for a past day, with the
    draft kept;
  - a failed copy, then a retry;
  - the visible sample-questions note.
- `diary_photo_stories_test.dart` has 8 tests on the real file system. They
  cover:
  - path ownership and traversal;
  - copies with no leftover `.partial` files;
  - order, words and hashes surviving a restart;
  - edit release, and cleanup after a refused save;
  - secondary-device rules;
  - the sync JSON round-trip, including skipping a malformed photo record;
  - photo-only stories in `displayItems`, the calendar and the diary page, and
    not in `visibleItems`;
  - reset removing copies while leaving sources.
- Full suite: 401 passed, 1 skipped and 3 failed. All 3 failures also happen
  on the base commit `96d220d`: `companion_protocol_test` (Node TLS) and two
  `onboarding_test` large-text layouts. `diary_day_content_test` was updated
  for the renamed close tooltip.

### On a real phone

The device test is
[`integration_test/diary_photos_device_test.dart`](../integration_test/diary_photos_device_test.dart).
It ran in two separate app processes on a Samsung SM-S928B (Android 17, USB).
The results are in [diary-photos-evidence.json](diary-photos-evidence.json).

```sh
flutter test integration_test/diary_photos_device_test.dart -d SERIAL \
  --no-uninstall --dart-define=I01_PHASE=save
flutter test integration_test/diary_photos_device_test.dart -d SERIAL \
  --no-uninstall --dart-define=I01_PHASE=reopen
```

The test uses its own ObjectBox and its own `diary_photos` folder under
`<support>/i01-synthetic`. It never opens the real journal, and the reopen
phase deletes the folder.

**Save phase.** The real page saved 3 photos. The test entered a caption and
an answer, and checked that nothing was written before **Save to diary**. On
disk, the three copies matched the source bytes (222,646, 335,014 and 229,842
bytes). There was one outbox creation.

**Reopen phase** (a fresh process):

- All three copies decoded: 1448×1086, 1122×1402 and 1448×1086.
- The entry showed the caption and the answer.
- A cancelled edit left the record unchanged.
- **Save changes** after removing photo 1 kept 2 photos and deleted the removed
  copy.
- A deleted copy showed as **Not on this device** together with the
  local-only notice.
- Account reset removed `diary_photos` and every diary record.

**Not covered on the device:**

- The system photo picker UI. The test injected bundled images in its place.
- iOS.
- A real secondary device receiving a story through Drive sync.
- The diary page's print strip loading from disk. That is covered only by
  widget tests.

After the run, the phone keeps this branch's debug build, and its existing
journal data was left in place.

## Limitations

- Photos are local-only. There is no cloud or cross-device media sync, and
  media backup is still a separate product decision. Android OS auto-backup
  rules are unchanged, so copies follow the same rules as the database.
- There is no UI to delete a story, which matches text items.
  `deleteTimelineItem` tombstones the record but does not remove its copies.
  Account reset removes them.
- If the picker is interrupted because Android recreates the activity, the
  photos are lost. There is no `retrieveLostData` recovery yet.
- Copies are stored as the picker returns them: at most 1800 px, quality 85.
  The original files are never modified.
