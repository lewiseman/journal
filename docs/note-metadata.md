# N02 — Note titles, tags and starting ideas

N02 adds optional, explicit AI suggestions on top of the F01/R01 task path. Nothing is generated in the background and nothing is applied without the user choosing individual suggestions. N01 rewriting, image features and any taxonomy/organisation engine are out of scope.

## Use it

1. **Title & tag ideas.** Save a note, return to its preview and open the wand menu → **Title & tag ideas** → **Suggest title & tags**. Review the result: *Keep "current title"* is selected by default; tap one suggested title to replace it. Suggested tags are unselected chips; tap the ones you want. **Apply selected** stays disabled until something is chosen. Existing tags are always kept. After applying, the editor shows **Undo**, which restores the exact previous title and tags if the note has not changed since.
2. **Starting ideas.** On the Notes page the idea card keeps its offline shuffle. The new ✨ button opens **Starting ideas**: an optional topic, and an off-by-default **Use notes I choose** switch that lists notes to tick (at most three) and shows *exactly* the title and first 240 characters that will be sent. Tapping an idea clears the task and opens a new note with that line as its title.

Both reuse the single protected note-AI slot, so they appear in More → Local AI computer → AI task history, survive app restart, retry with the same task ID and can be cancelled like summaries.

## What is sent

| Action | Sent to the paired computer | Stays on the phone |
| --- | --- | --- |
| Title & tags | The saved note's title (empty when it is the "Untitled Note" placeholder), body and up to 12 of its tag names | Tag emoji, other notes, attachments, background, the version snapshot |
| Generic ideas | The typed topic, or nothing | All notes and history |
| Personal ideas | Topic plus the displayed title/excerpt of up to three ticked notes | Everything else |

Requests are capped at 2,000 UTF-8 bytes and never shortened; a longer note is refused with an explanation.

## Validation and conventions (`lib/modules/notes/metadata/note_help_contract.dart`)

- Tags stay in the existing `emoji#name` form. Suggested names are trimmed, a leading `#` removed, `All`/`#`-containing/over-24-character names dropped, emoji restricted to the tag picker palette, and duplicates or tags already on the note removed case-insensitively. If a suggestion matches a tag used on another note (`notesTagProvider`), that tag's spelling and emoji are reused rather than creating a near-duplicate.
- Tags naming sensitive attributes (health/mental-health conditions, pregnancy, religion, sexuality, politics, ethnicity, disability…) are never suggested; users can still add them manually. Notes with fewer than four words, or an empty body, are refused before sending: there is not enough text to describe without guessing.
- Titles that repeat the current title or each other are dropped; whitespace is collapsed and surrounding quotes removed.

## Persistence, roles and conflicts

- `NotesRepository.updateNoteMetadata` sets exactly the chosen title and tag list inside one ObjectBox transaction, only if the live note still has the version captured when the request was made, and then saves through `saveNote` (version vector increment, `pendingUpload`, outbox, normal sync). It never creates a conflict draft; a stale request is refused.
- The protected task snapshot records the note's title, body, tags and version. Any change to these during generation (manual edit, sync, delete) marks the result stale and blocks Apply.
- Secondary (add-only) devices cannot request title/tag suggestions — nothing is sent — and the repository rejects writes even if the role changes mid-task. Starting ideas create nothing, so they work on any device.
- Undo is offered in the editor right after applying and is not persisted across restart; it is itself a version-checked metadata write that syncs normally.
- Account reset clears the protected slot and task history as before. No new ObjectBox entity was added.

## Verification

- `flutter test test/note_help_test.dart` (9 tests): request contents (placeholder title dropped, no other notes), empty/short/oversized refusals, convention filtering incl. library reuse and sensitive tags, generic vs. disclosed personal idea requests, selective apply preserving body/attachments/manual tags with version change and real `MemoryDrive` sync of title/tags, undo and stale undo, duplicate-tag rejection, manual edit during generation → stale and unchanged, rejection, restart retrieval of the same task without resubmission, unloaded model and read-only device sending nothing, and the review page (empty-note message; Apply disabled until a chip is selected).
- Full suite: 397 passed, 2 failed. The two failures are the pre-existing `onboarding_test.dart` large-text overflow cases recorded as baseline in `note-writing-evidence.json`; they are unrelated to N02.
- Real model evidence: see the desktop's [NOTE-HELP.md](../../desktop/docs/NOTE-HELP.md) and [note-help-evidence.json](../../desktop/docs/note-help-evidence.json) (QVAC 0.22.0, Llama 3.1 8B and Qwen2.5 0.5B on macOS arm64).

## Limitations

- **Not demonstrated on a physical phone** in this milestone; Flutter coverage is unit/widget tests with a fake transport. The desktop half used real QVAC without the TLS/phone path.
- Quality depends heavily on the assigned model. Qwen2.5 0.5B gives poor suggestions and can echo instructions into ideas; Llama 3.1 8B is good. Prompt-injected text inside a note can still produce non-sensitive suggestions; the user's explicit choice is the safeguard.
- The sensitive-tag filter is an English keyword list, not a classifier.
- Undo is session-only; there is no persisted title/tag history.
