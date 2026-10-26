# Journal

A Flutter journal with local ObjectBox storage and Google Drive sync. The sync
flow is adapted from the earlier Journal project's `sync_kit` into the existing
`packages/sync_wise` package. The reference checkout is not modified.

## Storage and diary writing

Diaries, notes and sync metadata live in the existing `Journal-wise` ObjectBox
store. Save in the diary text editor writes the entry and its pending upload
operation in one transaction, then returns to the diary. Reader pages update
from ObjectBox; calendars and local search read saved entries. An empty database
shows empty days. Example diary data exists only under `test/support`.

## More and tasks

More shows a Tasks preview that opens the full Tasks page. Tasks is UI only
for now, with no task storage or add, edit, complete or delete actions. People
is a preview for a future page. The original expandable account sync card stays
at the top of More, with Settings below the Tasks and People cards.

## Sync behavior

- The first registered device is primary. Startup and **Sync now** restore shared
  notes/days before uploading pending local changes. Later automatic primary
  syncs upload pending changes without downloading the whole journal.
- Secondary devices send new notes and append new items to today's diary. They
  fetch only the affected day and preserve its other entries and reflection.
  Existing notes and older diary days are read-only. Offline drafts created
  before a role was known are kept locally if they cannot be sent.
- Writes debounce for 300 ms; automatic attempts have a one-minute cooldown.
  Offline/network failures retry with backoff. Queues, roles, edit protection and
  remote revisions survive restart. Concurrent edits remain pending until the
  latest saved snapshot has uploaded.
- Shared Drive JSON documents use guarded ETag writes. A stale automatic upload
  waits for startup/manual refresh. The primary imports old per-device documents
  once, retaining legacy cloud files. Device roles have no automatic promotion.
- Sync coordinates above tab navigation. More contains **Connect Account** and,
  once connected, **Sync now**, progress and errors.
- After reinstalling, use **Settings → Sync & devices → Reclaim primary role**.
  Confirming transfers the existing primary registration to this installation
  and restores the journal in a full sync. Backups and document links are kept.
  The former primary becomes add-only on its next sync. If restore is interrupted
  after the role changes, **Sync now** resumes it. Recovery requires the original
  Google account and an internet connection.

This is JSON/content sync. Attachment metadata is preserved, but image, voice
and other attachment bytes are not transferred.

The diary image button opens a UI-only photo-story preview. Select one or more
photos, swipe or enlarge them, add optional captions, then choose **Just the
photos** or **Generate questions**. Captions sit on each print's paper border;
hold and drag prints in the filmstrip to change their order. Sample question
cards explore the moment, the feeling and small details for each photo.
Reflect uses loose photo prints,
paper index tabs and a swipeable deck of question slips with ruled writing space.
The header switches between Photos, Reflect and Entry. Reflect's footer offers
**Review** alongside the next-question action.
Answers survive changing photos, moving between questions and trying alternatives.
The final entry preview brings each photo and its words together on a scrapbook
page. Prompts can be shown as annotations, and **Edit photos** returns to the
prints while keeping the reflections.
Paper, ink and accents follow the active app theme.
Closing the preview does not save photos or text;
AI image analysis and persistence will be connected separately.

Microphones in Notes, Diary and Flow open a shared voice-interface preview.
Notes and Flow show sample transcription; Diary demonstrates a conversation
with occasional AI responses. The preview does not record audio, contact an AI
service or save its sample text. It supports pause, resume and replay, and pauses
when the app becomes inactive. Real voice services and capture remain future work.

## Resetting account data

**Settings → Reset account data** requires the connected account and typing
`DELETE` in its confirmation. Reset is disabled while syncing, including in an
open confirmation dialog. Once sync is idle, it pauses sync, persists reset progress,
deletes all Journal Drive app-data (including legacy backups and primary
registration), then removes local notes, diary days, trash, sync metadata,
private note-background copies and cached images. It signs out and clears the
account binding after cleanup. Original photos/imported files, device identity
and personalization settings are kept.

Cloud deletion needs an internet connection. An interrupted reset blocks journal
navigation and syncing across restarts and offers **Retry and finish reset**.
Once cloud deletion is recorded as complete, local cleanup can resume offline.
Old editors/routes are disposed, including when a reset finishes within a frame.
Close Journal on other devices first: their local copies are not remotely erased
and can upload again if reconnected before being cleared.

## Running and checking

Configure the app's Google OAuth clients and Drive app-data access. The existing
ignored `env.json` supplies `GOOGLE_SERVER_CLIENT_ID` and `GOOGLE_CLIENT_ID`:

```sh
flutter pub get
flutter run --dart-define-from-file=env.json
dart run build_runner build
flutter analyze
flutter test
flutter test packages/sync_wise/test
```

Native platform OAuth registration must match the app's bundle/package ID and
signing credentials. These automated tests use a memory backend and mocked Drive
HTTP responses; they do not sign into a real Google account.

ObjectBox integration tests need a matching desktop native ObjectBox library in
`lib/` (for macOS, `lib/libobjectbox.dylib`). The local ignored runtime used here
was reused from the earlier project's `lib/`. Flutter mobile builds use
`objectbox_flutter_libs`. Keep `lib/objectbox/objectbox-model.json` when generating
bindings so existing database entity/property IDs are preserved.

See `packages/sync_wise/README.md` for backend and collection adapter contracts.
