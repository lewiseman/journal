# N01 — Reviewable note writing

N01 adds explicit rewriting, expansion, tone, grammar/clarity and Markdown proposals for a saved note body or a selected passage. N02 title/tag/starting-idea suggestions are a separate milestone, following the prompt guide's one-milestone scope. The existing F01 summary and R01 protected task/recovery paths were inspected and reused, rather than introducing another transport, queue or inference provider. The previous native/Android prerequisite evidence remains in `note-summary.md` and `task-recovery.md`; their controller/transport checks still pass.

## Use it

1. Save a note and return to its preview. Open the QVAC sheet → **Writing help**.
2. Choose one action and optionally describe intent (required for tone). Use the whole saved body, or select text in the read-only body field and press **Use selected passage**. No note is sent until **Generate proposal**.
3. Compare **Original selected text** and **Proposed replacement** as inert selectable text, including literal Markdown. Check facts and voice. Accept writes only the selected body range; reject/clear leaves the note untouched. Dismiss keeps the task in More → Local QVAC → AI task history.
4. Reopen the QVAC sheet → **Prior content / recovery** to restore the body from before acceptance. Restore refuses a note changed since that acceptance; its prior body remains available to inspect/copy manually. Removing copies has an explicit confirmation.

Unsaved editor drafts never enter this workflow. Returning from writing/recovery refreshes the editor's saved snapshot. Manual editing, its conflict drafts, Markdown preview, title, tags, backgrounds, attachments and pinning retain their existing behavior. Primary/add-only rules are enforced in the repository at acceptance and restoration, even if a role changes while a model runs. Read-only devices may review/reject proposals.

## Boundaries and persistence

No dependency version changed. Flutter continues using Riverpod 3.4.3, ObjectBox 6.0.0-preview.4, the existing SharedPreferences wrapper/sync_wise paths and protected storage 11.2.0. Electron 45.0.0 and QVAC SDK 0.22.0 retain their existing model assignment, pinned TLS, Ed25519 signatures, encrypted job vault, device attribution, deadlines, cancellation, acknowledgment and receipt retention.

| Data | Storage and lifetime | Sync |
| --- | --- | --- |
| Exact retry ID/input and source snapshot/range | Existing protected task slot; input dropped after confirmed acceptance, source retained for review until clear/24-hour expiry. A closed app prunes on next startup/foreground reconciliation. | Never sent to journal sync. Only selected text + intent goes to desktop. |
| Task identity/status/source digest/operation | Existing local ObjectBox task-history entity; seven-day receipts | Local only; no source/result text |
| Prior and accepted bodies, applied version, task ID | New local ObjectBox `NoteRecoveryEntity`; ten most recent acceptances across this phone, about 1.4 MiB of prior/accepted body text. Survives process/database restart. | Local only, protected like ordinary note text in the application database, **not separately encrypted** |
| Accepted/restored note body | Existing `NotesRepository.saveNote` and version/outbox/sync machinery | Existing sync rules; add-only devices cannot change saved notes |

Account reset clears protected requests, task references and recovery rows. **Remove recovery copies** clears this note's local copies. Older copies are evicted on the eleventh acceptance. Deleting a note does not separately erase its recovery copies; they remain bounded local data until removal, eviction or reset. Deleted notes cannot be resurrected by accepting/restoring a proposal. Desktop results use the existing 24-hour expiry and explicit/retried acknowledgment.

The existing single active note-AI task slot is shared with summaries. This keeps task recovery and reset ordering unchanged. Protected source content is explicitly excluded from ObjectBox task metadata. If protected content cannot be loaded, retrieval can display a desktop result, but cannot apply it without the original snapshot.

`transform_contract.dart` defines the five actions, private range snapshot and output checks. The existing summary controller/store are operation-aware while preserving old `summarize-note` records. `NotesRepository.acceptTransformation` checks the current live record/version/content and duplicate task receipt inside the same ObjectBox write transaction that saves the new note and recovery row. Stale AI proposals are refused, not converted into manual conflict drafts. Restoration uses the same transaction and normal repository write path, requiring the acceptance version and body to still match. Later metadata edits also prevent automatic restoration; copying prior content remains available.

## Desktop contract and model limits

Authenticated capability status advertises `rewrite-note`, `expand-note`, `tone-note`, `clarify-note`, `markdown-note` and `transformLimits`. The existing signed `/v1/jobs` request carries the operation and a JSON-encoded `prompt` with exactly `{text, intent}`. Titles, other notes, tags, attachments, the full local snapshot and source identifiers never enter that prompt. Unknown cancellation fences accept an optional signed operation so delayed writing submissions retain the right task identity; old summary callers keep their previous default.

The complete encoded input is capped at 2,000 UTF-8 bytes, intent at 240 bytes, output at 4,096 bytes/768 tokens. Nothing is silently truncated. The local full body is capped at 64 KiB so recovery stays bounded, even for a small selection from a longer note. Empty/broken Unicode, control characters, HTML-shaped output and unexpected JSON replacement envelopes are refused. Model output is inert during review. Markdown renders only through the already established note preview after acceptance; no HTML/CSS renderer, tools, images or voice were added.

QVAC uses a separate editing system instruction, quoted JSON source/intent, temperature 0, seed 42 and `kvCache: false`. `final.stopReason == "length"` fails the entire task instead of offering truncated text. This API was checked against the installed SDK's own `dist/examples/completion-stop-reason.js`; the existing 4,096-token context and 90-second timeout remain in place. The operation contract is isolated in the desktop's `src/transform.cjs`. There is no new protocol framework, model dependency or schema-suggestion engine.

## Reproduce verification

```sh
# journal/
flutter analyze lib/modules/notes lib/modules/root/controllers/journal_account_reset_data.dart test/note_transform_test.dart integration_test/note_transform_device_test.dart
flutter test test/note_transform_test.dart test/note_summary_test.dart test/note_attachments_test.dart test/targeted_sync_test.dart

# desktop/
npm test
npm run package
node scripts/verify-notes.cjs /absolute/new/empty/n01-evidence /absolute/verified/model.gguf
```

The packaged harness executes all five operations against real QVAC with synthetic text over signed/pinned HTTPS, repeats identities without duplicate jobs, checks Activity attribution, then restarts the companion and retrieves/acknowledges each result. It writes `notes-native-1.json` and `notes-native-2.json`. The sanitized native outputs are included in `note-writing-evidence.json`. The harness refuses an existing nonempty evidence directory.

For the optional physical Android demo, create a fresh isolated desktop directory with `app-data/model.json` pointing at the provisioned model, then run:

```sh
"out/Journal Companion-darwin-arm64/Journal Companion.app/Contents/MacOS/Journal Companion" --connection-demo=/absolute/isolated/n01-phone --demo-port=47927 --recovery-phone-fixture

# journal/ (use the actual connected device ID)
flutter test integration_test/note_transform_device_test.dart -d DEVICE_ID --no-uninstall --dart-define-from-file=/absolute/isolated/n01-phone/device-config.json
```

This reuses R01's **test-only synthetic enrollment fixture**, not production pairing approval. It creates separate protected trust/task keys and an isolated ObjectBox store, exercises production signing, pinning, QVAC, the editor action/form, original/proposal review, explicit UI acceptance and restoration, discarded-real-acceptance retrieval, rejection, changed-source and changed-role refusals. It cleans its synthetic notes, recovery, task references and device trust, and writes `n01-device-evidence.json` in the phone's support directory. The config contains disposable test credentials: never commit it or point the fixture at ordinary app data. Afterward rebuild the normal entry point with `flutter build apk --debug` and use `adb install -r` to restore it without clearing existing data.

## Evidence and limits

The Samsung SM-S928B / Android 17 run passed all the physical cases above with real private LAN/pinned TLS/QVAC. Actual ObjectBox close/reopen, local recovery limits, stale undo, malformed output, unavailable model, failure retrieval, protected persistence failures, reset, normal manual edits/conflict drafts and outbox writes are covered by automated checks; fault injection is explicitly distinct from real network loss. Native packaged coverage is macOS arm64 with the pinned Qwen2.5 0.5B Instruct Q4_K_M weights.

The small model's writing quality is uneven. The native run produced Markdown and some wording/capitalization changes, but did not reliably correct all grammar or meaningfully expand the sample; one rewrite lowercased proper names. These are reviewable proposals, not a factual/style quality guarantee. No-op output cannot be accepted. Human review remains necessary, particularly for expansion and tense/voice changes. Broad quality/language coverage, physical iPhone, other desktop platforms and simultaneous phone/desktop WAN-disconnected operation remain unverified.

Static analysis passed. The full Flutter suite completed with **332 passed and two existing onboarding layout failures** (large text at 320×568 and 844×390). Both identical overflows reproduced from the untouched pre-N01 staged index in a temporary checkout (23 onboarding checks passed, the same two failed). They were kept outside this notes milestone. All 46 focused Flutter checks and 29 companion tests passed. The normal Android debug build passed and a data-preserving replacement installation restored the phone's normal entry point.
