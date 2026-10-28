# J02 — Daily reflection questions

J02 lets you ask your paired computer for one optional question on today's diary
page. It can follow up on something you wrote recently or simply help you start.
It is off by default, only runs when you tap, and writing never waits for it.

## Prerequisite note

J02 was built before S01 (source-linked historical retrieval) existed. Both now
share one retrieval layer, `lib/modules/diary/history/diary_retrieval.dart`:
civil dates, `DiaryDateScope` (J02 uses `DiaryDateScope.previousDays`),
`diaryTextItems` (which items count as sendable text) and `diaryTerms` (word
normalization for S01 matching and J02 repetition checks).
`DailyQuestionSource.select` still differs on purpose: there is no query, and it
sends whole recent entries rather than query-matched excerpts.

## Use

1. More → Local AI computer → **Daily diary questions** (off by default).
2. On today's page in the diary reader, under the writing invitation, tap
   **Ask me a question**. The invitation text becomes the question, with a line
   saying where it came from: "Following up on your entry from yesterday",
   "…from N days ago", "…something you wrote earlier today" or "A general
   question to help you start".
3. **Skip** hides it for today. **Another question** asks again; the current
   question stays until a replacement passes the checks.
4. Tapping the invitation always opens the normal writing page, whether or not a
   question is showing, loading or failed.

With the setting off, today's page is exactly the original prompt and no AI code
is built or watched. Older days and page-curl previews always show the plain
prompt.

## What is sent

A line under the button says what will be sent, for example: "Sends 3 entries
(today and 2 earlier days from the past week) and your last few questions to
your paired computer only."

- Up to 4 of today's text entries (newest first).
- Up to 8 whole text entries from the previous 7 civil days, newest first, while
  the request fits the companion's 2,000-byte limit. Entries are never shortened;
  one that doesn't fit is left out. Photo-only entries aren't sent.
- Up to 5 recent questions, so the model can avoid repeating them, but **only
  when at least one entry is selected**. With no entries nothing personal is
  sent: an 8B model given only earlier questions tended to copy their topics.
- Temporary IDs (`t0`, `p0`, …) and, for earlier entries, `ago` (days before
  today). No dates, item UUIDs, titles, moods, photos or device names.

## Checks on the phone

The companion bounds the JSON envelope (`question` ≤ 200 chars, `source` one of
the sent IDs or empty, `evidence`). The phone, which holds the text, decides:

- **Grounding:** a follow-up must quote a phrase that appears in the entry it
  names. A general question (empty source) may not refer to earlier entries
  ("yesterday", "last time", "you mentioned", …).
- **Timing:** "yesterday" must point at an entry from one day ago, and a
  follow-up on an earlier day may not say "today", "tonight" or "this
  morning/afternoon/evening". The second rule is conservative and refuses some
  harmless wording.
- **Nonintrusive:** J01's diagnosis and sensitive-term list, plus pressure
  phrases such as "tell me everything", "be honest" and "why did you".
- **Repetition:** compared with up to 30 local recent questions, using normalized
  words with light English stemming, ignoring openings like "What's".
- **Still relevant:** the question is re-checked each time it's shown. If its
  source entry is edited or deleted, or the civil day changes, it's hidden.

A refusal shows a plain reason with the usual prompt, and nothing is saved. All
of these checks are English-only safety nets and can miss paraphrases.

Questions are sampled with temperature 0.7 and a random seed, so asking again
gives a fresh question. Other bounded operations stay deterministic.

## Tasks, dates and availability

The request uses the shared recoverable AI task slot: protected retry input,
same-ID retrieval, cancellation, 24-hour expiry and acknowledgment, as in J01.
When it completes, the phone validates it, stores it, and clears and
acknowledges the task, so the slot is free again. AI task history labels it
"Daily question".

Dates follow the phone's local civil day (`DiaryRepository.formatDateKey`). A
question belongs to the day it was asked for. A result that arrives after the
date changed is dropped with an explanation, and a new day starts with the plain
prompt. This also covers timezone changes when travelling, since the key comes
from the device's local time.

With the computer unavailable, a question already saved for today still shows.
Asking again explains "Connect your trusted computer…". Writing is unaffected.
Secondary devices may ask too, since J02 writes no synced diary data.

## Storage, sync and reset

| State | Where | Sync | Cleared by |
| --- | --- | --- | --- |
| On/off | `CacheStorage` key `dailyQuestions` (app namespace) | No, per device | (device preference) |
| Questions | `DailyQuestionEntity` (ObjectBox): day, question, source date/item, evidence, ago, status | No, not in `journalSyncCollections` | Turning the setting off, account reset |

At most 30 rows from the last 30 days are kept. The question text can echo your
words, so it's stored like other local diary data. Raw model output and the
request selection exist only in the protected task slot until acknowledgment.
The model was generated with `build_runner` (ObjectBox 6.0.0-preview.4).

## Verify

```sh
# journal/
flutter test test/daily_question_test.dart
flutter test
# desktop/
npm test
npm run package
node scripts/verify-notes.cjs /absolute/new/empty/dir /absolute/model.gguf --question \
  [--model-id=<catalog id>]
```

Physical phone (see `diary-suggestions.md` for the companion fixture launch):

```sh
flutter test integration_test/daily_question_device_test.dart -d DEVICE_ID --no-uninstall \
  --dart-define-from-file=/absolute/isolated/j02-phone/device-config.json
# stop the companion, then:
flutter test integration_test/daily_question_device_test.dart -d DEVICE_ID --no-uninstall \
  --dart-define=J02_RESTART=true
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Evidence (2026-10-27)

- `test/daily_question_test.dart` (8 tests) covers:
  - selection bounds and disclosure;
  - grounding, timing, intrusive and repeat refusals;
  - the store, pruning, reopening and account reset;
  - end to end: a grounded follow-up, avoid on regenerate, source deletion, no
    history, and a date change during generation;
  - opt-out, unavailable computer, old companion and missing model;
  - a cached question shown while unavailable;
  - a secondary device asking without changing synced data;
  - the prompt widget.
- The full Flutter suite passes except the two `onboarding_test.dart`
  large-text overflow cases, which are unrelated. Companion: 54 tests pass.
- Packaged harness with real QVAC passes both phases (restart and
  acknowledgment) with Llama 3.1 8B and with the default Qwen 0.5B.
- Physical Samsung SM-S928B against Llama 3.1 8B: both phases pass. Results are
  in `daily-questions-evidence.json`. Examples:
  - grounded: "What's your plan for getting settled into the new flat after the move?";
  - after "Another": "What's still left to unpack from the last boxes on Saturday?";
  - no history: "What did you do today?", with nothing personal sent.

  The run also covered source deletion, date change, opt-out, the cached
  question after restart with the companion stopped, and a failed replacement
  keeping it.

## Limitations

- **No S01 retrieval:** the selector looks only at the last 7 days, newest
  first. It doesn't find relevant older entries, and entries over the byte
  budget are skipped.
- **Quality varies with the model:**
  - Qwen 0.5B (the default) quoted the wrong entry and repeated an avoided
    question; the phone refused both. Use a 3B+ writing model.
  - Llama 8B once put yesterday's pottery class "today"; the phone now refuses
    that wording.
  - Some follow-ups gently ask how you felt, which the prompt allows.
- **Language:** the safety checks are English-only. Non-English days are
  untested.
- **Test setup:**
  - The date change was simulated with an injected clock, not a real timezone
    change.
  - Trust used the test-only fixture, not the pairing UI.
  - The secondary-device case is a unit test.
- **Not included:** notifications and background generation (T01).
