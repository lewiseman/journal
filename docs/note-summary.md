# F01: summarize one saved note

Implemented 27 October 2026. **R01 update:** [task recovery](task-recovery.md) extends the original single-handle persistence and acknowledgment/retention contract described below with ObjectBox history and durable receipts. `journal/` remains the authoritative Flutter app; its sibling `desktop/` is a separate Electron repository. Existing staged connection work was preserved; `old/` was excluded. No dependency or database schema changes were needed.

## Use

Open a saved nonempty note in preview mode → **Summarize saved note** (summary icon) → **Summarize**. The second action explicitly authorizes sending the saved title and body to the selected trusted computer. Unsaved drafts have no summary action. Attachments, tags, artwork, other notes, account identifiers and source UUID/revision are not transmitted.

The preview distinguishes submitting without confirmed acceptance, accepted/queued, running, retrieving, completed, cancelled, interrupted and actionable errors. It offers **Copy summary**, **Dismiss**, explicit cancellation, and **Clear preview** for terminal work. Copy exports inert plain text to the system clipboard; it never edits or saves a note. There is no editor insertion action. Dismiss retains recovery information; More → Local AI computer → **AI task history** reopens it, including when the source was deleted. Only one preview is retained per phone; finish/cancel and clear it before starting another.

The model may miss or invent details. Review the preview against the source. A changed/deleted source is prominently labelled **Earlier note version**, and its Copy button is disabled. The source editor/repository retains its existing saving, conflict, attachment and add-only role behavior. Summary generation itself invokes no repository write. Reading/summarizing an existing note is available to secondary devices.

## Contract and limits

The existing pinned TLS / per-phone Ed25519 protocol and device-scoped durable jobs are reused, with no second runtime server. Text capability status now advertises `operations: ["text", "summarize-note"]` and `summaryLimits: {inputBytes:2000,outputBytes:2048,outputTokens:192}`. An older companion without this operation produces an update message. Submission remains signed `POST /v1/jobs {id,operation:"summarize-note",prompt}`; `prompt` contains exactly the selected note's title, a blank line, and body (outer whitespace removed). GET, cancel and ack routes are unchanged.

The pinned Qwen2.5 0.5B Instruct Q4_K_M model uses QVAC 0.22.0, a 4,096-token context, a factual system instruction and a separate JSON-encoded note data message. Temperature is 0, seed 42, generation is capped at 192 tokens, and KV caching is off. No tools or active-content renderer is supplied. Instructions embedded in a note are designated data; this is a model instruction, not a guarantee against semantic prompt injection. Output is always inert `SelectableText` even if it resembles HTML or Markdown.

2,000 UTF-8 bytes including title/body is a conservative limit within that context, with room for instructions/template/output. Real packaged inference passed at the exact input boundary. Unicode can reach the byte limit sooner than character count. Longer, empty, malformed-surrogate or control-bearing inputs are refused with an explanation; none is silently truncated. Output must be nonempty, valid text and at most 2,048 UTF-8 bytes. A QVAC `final.stopReason` of `length` is an explicit `OUTPUT_LIMIT` failure, with no partial preview. No validity check can establish factual accuracy.

## Recovery, privacy and reset

A Riverpod controller manages the preview. Before first submission, it saves an opaque task UUID, desktop identity, source UUID, SHA-256 source revision, timestamp and bounded retry input in the existing KeyStore/Keychain-backed secure-storage namespace. This preserves the exact request through lost acknowledgment or process death. Before resubmitting uncertain work, it retrieves the same ID first. The server deduplicates operation plus exact input under the authenticated device; ID reuse with different input fails. Confirmed acceptance drops the phone's retry text, retaining only recovery metadata. Output is kept in memory on the phone and retrieved from encrypted desktop storage when reopening.

ObjectBox monitoring queries only the chosen UUID. Revision checks include persisted title, body, version vector, timestamps and deletion flags. No whole-journal query/index was added. A changed source cannot cause an older result to be presented as current. If no accepted task exists after a source change/deletion, retry stops before resending the old snapshot. A task already accepted can still be retrieved as an earlier version.

Foreground polling runs every three seconds while queued/running; backgrounding stops polling. Reconnection of the original trusted identity resumes retrieval, including a verified endpoint change. Switching the selected computer never redirects an accepted task. Disconnect suspends retrieval without cancelling desktop work; cancellation is explicit and its intent is saved before transmission. Cancellation/completion races accept whichever terminal state the server committed. Revocation, unavailable computer, identity mismatch, missing model, queue limits, storage failures and expired tasks have recovery guidance. Transient errors expose retry; they do not create a new task ID.

Phone recovery data and desktop results expire after 24 hours from request creation. Phone secure records are deleted on expired restore/retrieval; a quit/backgrounded app cannot perform wall-clock deletion. Desktop retention/acknowledgment and encrypted persistence retain their existing guarantees. A clear while offline removes the local record; remote retention still applies. Copy explicitly places text on the OS clipboard, outside this retention policy.

Account reset blocks new work and late callbacks immediately, clears local recovery storage as part of mandatory local cleanup, and prevents old results from repopulating the new account. An unsuccessful reset preflight recovers the existing task. Reset confirmation explains that accepted encrypted work on a disconnected desktop can remain until its 24-hour expiry; revoke the phone on that desktop to remove it immediately. Computer trust is separate from the sync account and is not silently revoked by account reset.

## Verification and reproduction

All 46 focused Flutter checks passed; changed-file analysis was clean. The desktop suite passed 22 tests. Focused regression command:

```sh
flutter test test/note_summary_test.dart test/note_attachments_test.dart test/account_reset_integration_test.dart test/account_reset_settings_test.dart test/companion_protocol_test.dart test/companion_controller_test.dart
```

These checks include real ObjectBox note/reset operations; transport/runtime fault injection is explicitly synthetic. They cover exact selected input, UTF-8/malformed input, inert rendering, secondary-role source preservation, persisted identity before send, lost acknowledgment/reopen, changed/deleted source, changed source before acceptance, cancel, missing model, secure write failure, invalid output, reset/late-response races and slow secure-store startup. Existing note saving/attachment/conflict and account-reset regressions remain included.

The physical Samsung SM-S928B (Android 17), Flutter 3.47.5/Dart 3.13.4, and packaged macOS arm64 Electron 45.0.0/QVAC 0.22.0 passed these separate runs:

1. Real editor summary action → signed LAN submission → real QVAC preview; original persisted note unchanged. Test-only transport injection discarded one real accepted response, then production recovery retrieved the same task with exactly one POST. Explicit Settings disconnect/reconnect worked. A subsequent synthetic source edit displayed the earlier-version warning.
2. Cold phone-app restart recovered the protected task identity and earlier-version preview with **zero new submissions**.
3. Actual desktop model unload produced phone guidance with **zero submissions**, then the test removed only its isolated synthetic notes, pairing and retained work.

Pairing used a full QR code injected into a test binary and the real desktop approval UI, with the verification code compared. Note data used a separate `f01-synthetic-objectbox` directory; no real journal was read. The physical editor used the secondary UI role; deterministic tests additionally enforce the repository's actual secondary role. This is not a camera QR test. See the checked-in compact `note-summary-evidence.json`.

Reproduce with a provisioned packaged companion launched using the existing `--connection-demo=/absolute/isolated-directory` mode (see companion connection docs). Create a fresh QR immediately before the first command and approve the matching phone code on the desktop:

```sh
flutter test integration_test/note_summary_device_test.dart -d DEVICE_ID --no-uninstall --dart-define-from-file=/absolute/isolated-directory/device-config.json
flutter test integration_test/note_summary_device_test.dart -d DEVICE_ID --no-uninstall --dart-define=SUMMARY_RESTART=true
# Unload the model on the demo desktop first; this run also cleans up synthetic data/trust.
flutter test integration_test/note_summary_device_test.dart -d DEVICE_ID --no-uninstall --dart-define=SUMMARY_MISSING_MODEL=true
```

Default integration-test uninstall erases protected Android trust. Use `--no-uninstall`. Replace the test app with a normal `flutter build apk --debug` result using `adb install -r`, which preserves unrelated app data. Never commit pairing-code files.

Packaged cold-start desktop verification also passed with external literal-IP connections **denied by macOS**, loopback allowed for the synthetic signed HTTPS client, and renderer network access disabled. It covered real summary inference, the 2,000-byte boundary, missing model, Activity attribution, lost acknowledgment, cancellation, encrypted storage, and completed-result retrieval after desktop restart. This proves offline desktop inference, separately from the phone's real Wi-Fi route.

**Remaining device gate:** simultaneous phone + desktop operation with WAN unavailable remains unverified because router access was unavailable. The phone run had normal Wi-Fi; it must not be labelled a full offline-device test. Physical iPhone behavior and broader model quality/language coverage were not tested for F01. The desktop remains an unsigned Apple Silicon preview. No new platform support is claimed.

Primary reference: [QVAC v0.22 text generation](https://docs.qvac.tether.io/sdk/ai-capabilities/text-generation/), cross-checked with the installed 0.22.0 `completion-stream` declarations and `completion-stop-reason.js` example. Existing cryptographic/storage libraries and the connection contract were reused rather than introducing alternatives.
