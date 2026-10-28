# J01 — Diary title, mood and theme suggestions

J01 lets you ask your paired computer for an optional title, a tentative mood
and up to three emotional themes for one diary day. Nothing is written until you
accept it, field by field. The companion is unchanged in model choice: it uses
whatever writing model is assigned and loaded (Electron 45.0.0, QVAC SDK 0.22.0).

## Use

In the live diary reader, tap the floating QVAC logo and choose **Day details**
for the selected day. The expandable sheet
shows the current title, mood and themes and offers:

- **Edit details yourself** — always available on the primary device, with or
  without a computer. This is the manual path and the override for anything a
  suggestion proposes.
- **Suggest title, mood and themes** — sends the day's saved entries to the
  trusted computer as a recoverable task (same task slot, history, cancellation,
  expiry and acknowledgment as summaries and presentations).

When the result arrives, each field is shown beside its current value with the
short phrase from your entries that supports it. Each field has **Accept**,
**Edit** (which accepts your edited value) and **Reject**. **Save accepted
details** writes only accepted fields; rejected and undecided fields keep their
current values. **Reject all and clear** discards the result. A completed result
survives app restart until you save or clear it (desktop retention is 24 hours).

Accepted details appear under the day's title in the reader. The mood also
appears in the calendar, which already read the existing `dayMood` field.

## Grounding and safety

The page states that mood is a tentative suggestion, not a judgment of how you
felt. The companion asks the model, under a per-request JSON-schema grammar, for:

- `title` — up to 80 characters, or empty;
- `mood` — one of `happy`, `calm`, `excited`, `tired`, `low` (the five existing
  calendar moods), `mixed` or `unclear`, with a quoted supporting phrase;
- `themes` — at most three labels of up to 40 characters, each with a quoted phrase.

Flutter, which holds the source text, is the authoritative check:

- A mood or theme is kept only if its evidence phrase appears in the saved entries
  (case, whitespace and quote style are normalized). Otherwise it is dropped, and
  the page says how many suggestions were left out.
- A title must share at least one meaningful word (or, for scripts without spaces,
  a two-character sequence) with the entries.
- `mixed` and `unclear` never become a saved mood. The page explains that mixed
  feelings or unstated feelings produce no single mood; grounded themes can still
  describe both sides of a mixed day.
- Titles and theme labels containing diagnosis or sensitive-fact terms (for
  example *depression*, *disorder*, *pregnancy*, *religion*, *medication*) are
  dropped. This list is a safety net after the prompt and grounding rules, not a
  classifier; it is English-only and can miss paraphrases. You can still type any
  word yourself.
- An empty grounded result is a successful, honest outcome for a sparse day.
- Invalid envelopes, extra fields, oversized output and token exhaustion fail
  closed without a partial result.

## What is sent

Only the selected day's visible entry text, as
`{"entries":[{"id":"e0","text":"..."}]}` with temporary IDs. No date, item UUIDs,
existing title/mood/themes, photos, attachments, device names or other days.
The whole request must fit 2,000 UTF-8 bytes and at most 12 entries; larger days
are refused with an explanation and are never shortened. Photo-only items are not
sent. The exact local snapshot (full serialized visible items) stays in the
existing protected task storage and is excluded from task-history metadata.

## Stale results, roles and writes

The snapshot is the stale-result fence. Editing, deleting or adding an entry
while the computer is working marks the result out of date and disables saving.
Saving rereads the device role and the exact entries inside the same ObjectBox
transaction as the write (`DiaryRepository.applyDaySuggestions`), so a stale
result or a newly secondary device cannot write. Entry text is never modified.

Secondary devices can read day details but cannot request suggestions or edit
details, matching the existing rule that day metadata is read-only there. The
request button is disabled with an explanation, and the controller and
repository both refuse.

## Storage, sync and reset

| Field | Meaning | Storage |
| --- | --- | --- |
| `dayTitle` | Reused as-is. | Existing field. |
| `dayMood` | Reused with its existing JSON `{emoji,name,category}`, so the calendar reads it unchanged. Clearing writes an empty string. | Existing field. |
| `dayThemes` | **New**: JSON list of up to three user-approved labels. | New nullable `DiaryDayEntity` string, ObjectBox property 14. |

Themes were not put in `dayMood` or `daySummary`: mood is a single calendar
category and the summary is a reflection. Overloading either would break the
calendar parser or mix unrelated meanings.

`dayThemes` syncs as `day_themes` in the existing Drive diary document. It is
omitted when unset, so existing documents and their ETags are byte-identical.
It joins the existing metadata conflict rule (dirty/protected local metadata wins
over a remote copy). Writes mark the day pending upload and record a `metadata`
edit, exactly like other day metadata.

**Mixed app versions:** a device running an older Journal build ignores
`day_themes`, and if that device rewrites the day (as primary, or when appending
today's entry as secondary) the themes are dropped from the shared document.
Update every device before relying on synced themes. Titles and moods are not
affected.

Account reset already removes diary days (and so themes) and the protected task
slot. No new background work, profiling, history or notification was added.

## ObjectBox binding

Generation tools were unavailable in the implementation environment, so the new
property was added to `objectbox-model.json` and `objectbox.g.dart` by hand,
following the generator's layout (property ID 14, FlatBuffers slot 13 / vtable
offset 30, existing IDs untouched). Before release, regenerate and confirm only
formatting changes, if any:

```sh
dart run build_runner build --delete-conflicting-outputs
git diff lib/objectbox/
```

The `14:7988663521190690088` UID must stay as written in `objectbox-model.json`.

## Verify

```sh
# journal/
flutter analyze lib/modules/diary lib/modules/notes/summary \
  lib/modules/notes/transform lib/objectbox test/diary_suggestions_test.dart
flutter test test/diary_suggestions_test.dart
flutter test
flutter test packages/sync_wise/test

# desktop/
npm test
npm run package
node scripts/verify-notes.cjs /absolute/new/empty/j01-evidence \
  /absolute/verified/model.gguf --diary
# Any catalog writing model (the file must match that entry's hash):
node scripts/verify-notes.cjs /absolute/new/empty/j01-evidence-8b \
  /absolute/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf --diary \
  --model-id=llama-3.1-8b-instruct-q4_k_m@bf5b95e96dac0462e2a09145ec66cae9a3f12067
```

`test/diary_suggestions_test.dart` covers the request boundary, a sparse day,
mixed emotions, ungrounded/diagnostic suggestions, malformed output, per-field
acceptance preserving manual choices, manual override, stale edits/additions,
unavailable model and old companion, secondary-device refusal, sync wire format,
and persistence after reopening the ObjectBox store.

The `--diary` harness sends synthetic sparse, mixed and ordinary days through the
packaged companion with real signed/pinned TLS and QVAC, restarts it, retrieves
and acknowledges each result, and writes `diary-native-1.json` and
`diary-native-2.json`. It checks the envelope only; inspect the outputs to judge
quality.

## Evidence status

Verified on macOS arm64 (2026-10-27):

- `flutter analyze` on the J01 paths: no issues.
- `flutter test test/diary_suggestions_test.dart`: 9/9 pass (two tests had to
  wait for the controller's async restore and scroll to the themes Reject button).
- `flutter test`: all pass except two `onboarding_test.dart` large-text overflow
  cases, which do not touch diary code.
- `packages/sync_wise` tests and `desktop` `npm test` (50): all pass.
- `build_runner` regeneration produced byte-identical ObjectBox output, so the
  hand-written `dayThemes` binding matches the generator.
- Packaged `--diary` harness, real signed TLS and QVAC, both phases (restart,
  retrieval, acknowledgment) pass with the default Qwen2.5 0.5B and with
  Llama 3.1 8B. Outputs are in `desktop/evidence-local/j01-native*/`.

Observed quality, after Flutter grounding:

| Day | Llama 3.1 8B | Qwen2.5 0.5B (default) |
| --- | --- | --- |
| Sparse (`Lunch.`) | nothing suggested | mood *excited* (evidence "lunch.") |
| Mixed | "River walk and deadline", *mixed* (not saved as a mood), themes *proud*, *deadline stress* | nothing (all dropped) |
| Ordinary | "Breakfast and reading", *calm* | nothing (all dropped) |

The prompt was tightened after a first 8B run that chose *low* for the mixed day
and copied the prompt's example theme label.

Limitations: the 0.5B default copies instruction text and is not useful for
this feature; prefer a 3B+ writing model. Grounding checks that evidence appears
in the entries, not that it expresses a feeling, so a weak model can still offer
an unsupported mood, which the user sees beside its evidence and must accept.
Non-English days remain unchecked.

### Physical phone

`integration_test/diary_suggestions_device_test.dart` passed on a Samsung
SM-S928B (Android 17) over Wi-Fi against the packaged companion running
Llama 3.1 8B. Results are in `diary-suggestions-evidence.json`. It covers:

- only the selected day's entry text being sent;
- accepting a title and mood through the real page, with entries unchanged;
- mixed (*mixed*, no saved mood) and sparse (nothing suggested) days rejected
  without writes;
- an edit after the computer accepted the work, which makes the result
  unsavable;
- manual override;
- a secondary role that sends nothing;
- after stopping the companion and restarting the app: details persisted, an
  honest "connect your computer" message, and manual editing still working.

Trust uses the test-only companion fixture rather than the pairing UI, and the
secondary role is a provider override, not a second phone. To reproduce:

```sh
# desktop/: isolated dir whose app-data/model.json names the model path and modelId
"out/Journal Companion-darwin-arm64/Journal Companion.app/Contents/MacOS/Journal Companion" \
  --connection-demo=/absolute/isolated/j01-phone --demo-port=47927 --recovery-phone-fixture
# journal/
flutter test integration_test/diary_suggestions_device_test.dart -d DEVICE_ID --no-uninstall \
  --dart-define-from-file=/absolute/isolated/j01-phone/device-config.json
# stop the companion, then:
flutter test integration_test/diary_suggestions_device_test.dart -d DEVICE_ID --no-uninstall \
  --dart-define=J01_RESTART=true
# restore the normal entry point without wiping data:
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
