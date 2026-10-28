# L01 — Optional one-line Flow reflections

You can ask your paired computer for one short reflection on a saved Flow
thought. It only happens when you tap. The thought itself is never edited, and
capturing a thought never waits for AI. The companion side is described in
`desktop/docs/REFLECTION.md`.

## Prerequisite check

F01's secure text inference is present and still passes `note_summary_test`.
Flow had a creation-only `ThoughtsRepository`, and its sync collection is
add-only (`PendingCreation`, `appendCreations` keeps the remote copy). There
was no way to edit a thought. That decided where reflections are stored (see
below).

## Use

1. Pair a computer (Settings → Local AI computer). Until a computer is paired,
   Flow looks exactly as before.
2. Tap a thought to open it. Under the text, tap **Reflect on this**. A line
   says: "Sends only this thought's text to your paired computer. Nothing is
   saved unless you keep it."
3. The result appears labelled **Suggested reflection · not kept yet**:
   - **Keep** saves it as **Your kept reflection**.
   - **Dismiss** deletes it.
4. With a reflection kept, **Reflect again** asks for another one. The new
   suggestion sits next to the kept one ("Keeping it replaces your kept
   reflection.") until you keep or dismiss it. If the new one is refused or
   fails, the kept reflection stays.
5. **Remove reflection** deletes the kept line. The thought stays.

You can close the sheet while your computer is working. The result is moved to
the thought while Flow is open, or when you open Settings → AI task history →
**Flow reflection**, which also offers retry, cancel and clear.

## What is sent

Exactly the thought's saved text, at most 2,000 UTF-8 bytes. It is never
shortened. Nothing else is sent: no UUID, date, device, other thoughts, notes
or diary. This uses the shared recoverable AI task slot:

- the input is saved in protected storage before it is sent;
- uncertain work is retrieved with the same ID;
- tasks expire after 24 hours and are acknowledged after use;
- there is one slot per phone. If another AI request is open, Flow says so and
  sends nothing.

## Checks on the phone

The companion only checks that the result is one bounded line. The phone,
which holds the thought, then refuses a reflection that:

- copies the thought or one of its sentences;
- speaks as an assistant ("I'm sorry", "I can't assist", "as an AI");
- introduces a sensitive term the person did not write (the shared J01 list:
  diagnoses, health, sexuality, religion, …);
- sounds more sweeping than the thought ("always", "never", "everyone",
  "truly", "profound", "your whole life", "you're clearly…", "no matter
  what", …);
- pushes or instructs ("you should", "it's important to", "tell me", "be
  honest", more than one question).

A word the person wrote themselves may be used again. For example, "never" is
allowed back if the thought says "never". A refused result shows a plain reason
and saves nothing. These checks are English-only safety nets and can miss
paraphrases.

## Storage, sync, roles and reset

| State | Where | Sync | Cleared by |
| --- | --- | --- | --- |
| Thought | `ThoughtEntity`, unchanged; `summary` stays unused | Add-only, as before | Account reset |
| Proposal / kept reflection | `ThoughtReflectionEntity` (ObjectBox): thought UUID, thought revision, text, task ID, status, time | **No**, device-local | Dismiss/Remove, account reset; unkept proposals after 7 days |
| In-flight task | Shared AI task slot (protected storage + local history) | No | Existing slot rules |

- **Why not `ThoughtEntity.summary`:**
  - Thought sync has no update path. A local change would be overwritten by
    the next merge, or stay stuck as an unsyncable pending record.
  - Adding a thought-edit operation is out of scope.
  - A derived local artifact keeps the thought byte-for-byte as written.
- **Replacing a kept reflection:** a new result is only ever a proposal. Only
  **Keep** replaces the kept line, and it does so in one ObjectBox transaction.
- **Recovery:** a completion delivered twice (for example after a crash between
  saving and acknowledging) is stored once, keyed by task ID.
- **Stale results:** each row stores a SHA-256 revision of the thought (UUID,
  creation time, content).
  - A result that arrives after sync replaced the thought's content is dropped
    with an explanation.
  - A stored reflection whose revision no longer matches is hidden.
- **Roles:** nothing synced is written, so secondary devices may reflect too.
  This is the same rule as J02 and S01.
- **Account reset:** reflections are hidden as soon as reset starts, new
  requests are blocked, and `JournalAccountResetData` removes every
  `ThoughtReflectionEntity`. The shared task slot keeps its existing reset
  behaviour.
- **Schema:** the ObjectBox model was regenerated with `build_runner`
  (ObjectBox 6.0.0-preview.4). See the merge note below.

## Verify

```sh
# journal/
flutter test test/flow_reflection_test.dart test/flow_page_test.dart test/note_summary_test.dart \
  test/daily_question_test.dart test/account_reset_integration_test.dart test/thoughts_sync_test.dart
flutter test
# desktop/
npm test
node scripts/verify-reflection.cjs /absolute/new/empty/dir /absolute/model.gguf [catalog-model-id]
```

## Evidence (2026-10-28)

- `test/flow_reflection_test.dart` has 8 tests, using real ObjectBox and a
  synthetic companion transport. They cover:
  - the phone checks, including wording seen from the real 0.5B model;
  - the store: proposals vs kept, replacement, task-ID idempotency, 7-day
    pruning, reopening the database, account-reset deletion;
  - end to end: the exact thought text is the only thing sent; then review,
    keep, a refused replacement keeping the kept line, dismiss, and remove.
    The thought's sync JSON, `summary` and outbox stay unchanged;
  - capture during a running reflection: a direct local save completes in
    under 200 ms;
  - content replaced mid-task (a synthetic sync replacement) drops the result,
    and a stale kept line is hidden;
  - unavailable computer, old companion, missing model, a busy slot owned by
    another feature, desktop failure and cancellation all send nothing extra.
    Capture keeps working throughout;
  - a secondary device reflects without changing anything synced;
  - account reset hides reflections and blocks requests;
  - the sheet widget: hidden until paired, then Reflect → Keep → Reflect again
    → Dismiss.
- The full Flutter suite passes (396) except the two known
  `onboarding_test.dart` large-text cases, which are unrelated. One earlier
  full run hit a timing flake in the new end-to-end test under concurrent
  load. Its wait window was widened, and the next full run passed.
- Desktop: 80 tests pass.
- Real QVAC 0.22.0 inference ran on Apple Silicon through the actual `Runtime`
  and `Jobs` under Node (not the packaged app). Results are in
  `desktop/docs/reflection-evidence.json`:
  - Llama 3.1 8B: all 10 reflections were calm and passed the phone checks,
    for example "It sounds like you're feeling uncertain about reaching out to
    your sister right now."
  - Qwen 0.5B: poor results (see Limitations).
  - Unloading the model gives `NOT_READY`.

## Limitations

- **No physical phone run:** there was no physical-phone or packaged-app
  run, and the signed LAN transport was not exercised for this operation. The
  transport is unchanged from F01/J02, where it was verified on a Samsung
  SM-S928B.
- **Quality depends on the model:**
  - Qwen 0.5B (the default) followed a prompt injection about pirates, read
    the Swahili word "Leo" ("today") as a name, and once returned a refusal
    line (now refused).
  - Use a 3B+ writing model.
  - Llama answered the Swahili thought in English.
  - Wording checks can't judge whether a line is accurate or helpful.
- **Language:** the safety checks are English-only.
- **Device-local:** reflections don't follow you to other devices. That is a
  deliberate result of add-only thought sync, not an oversight.
- **Kept reflection only shows in the sheet:** cards don't show a marker.
- **Merge note:** this branch adds an ObjectBox entity, `ThoughtReflectionEntity`
  (entity id 9). If another branch also adds an entity, the
  `objectbox-model.json` ids will collide when merging. Keep both entities,
  give one the next free id and uid, and re-run `dart run build_runner build`.
  Do not hand-edit `objectbox.g.dart`.
- **Not included:** question answering (L02), voice capture of reflections, and
  general thought editing.
