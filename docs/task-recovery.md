# R01: recoverable Flutter task history

Implemented 27 October 2026 on F01's saved-note summary and Electron/QVAC lifecycle. `journal/` is authoritative; `old/` was excluded. No new packages, general scheduler, background service or resumable token stream was added. Existing in-progress changes in both repositories were preserved.

## Use and recovery

More → Local QVAC → **AI task history** lists accepted/waiting, running, completed, failed/interrupted, cancelled and expired summaries. Open the active task to retrieve its preview, copy valid plain text, request cancellation, or clear/acknowledge a terminal result. **Try again as a new task** is explicit, requires an unchanged available source, and allocates a new identity only after clearing a terminal failure/cancellation/expiry. Unknown acceptance uses **Retry / retrieve same task**, never that new-task action. One summary remains active per phone; clearing it leaves a status receipt and permits another.

Leaving a screen or closing Flutter does not cancel accepted work. Foreground startup, resumed lifecycle and authenticated reconnection reconcile the original task and pending result acknowledgments. Foreground polling stops when the app backgrounds. No mobile background execution guarantee is assumed. A missing/paused/untrusted desktop gives connection guidance and preserves the task identity. Source version monitoring still queries only the selected UUID. Changed/deleted notes are labelled as earlier versions and cannot be copied or automatically retried; generation never writes source content.

## Storage and protocol choices

`SummaryTaskEntity` is a small ObjectBox entity containing a unique task ID, creation time, active flag and JSON recovery metadata. Metadata carries operation, source UUID/revision, companion identity, owning phone credential identity, accepted/result status, cancellation intent and acknowledgment status. It contains no note title/body, model output or trust secrets. Existing model UIDs were preserved and the new entity was generated with installed ObjectBox 6.0.0-preview.4 tooling.

History is deliberately **local-only**. It is absent from `journalSyncCollections`; sync_wise still syncs only notes, diary and thoughts. SharedPreferences is not used as a second task database. The existing protected KeyStore/Keychain namespace retains the single active request and its bounded exact input until acceptance is confirmed. Secure writes precede metadata commits; startup imports the protected record, including existing F01 handles, if a metadata write was interrupted. A missing retry payload fails closed. Confirmed acceptance, expiry or clearing drops raw retry input. Output remains memory-only on Flutter. New handles bind the owning phone's public-key-derived device ID as well as the desktop identity, so re-pairing cannot redirect an uncertain submission under new credentials. Legacy F01 records bind on a successful authenticated retrieval.

New submissions require authenticated `status.recovery == 1`, retain signed pinned TLS protocol v1, and add the original absolute `expires` timestamp to `{id,operation,prompt}`. The desktop caps expiry at 24 hours, refuses an expired new request and never extends a duplicate's deadline. All input is validated and encrypted durably before acceptance. GET precedes uncertain resubmission; deduplication uses authenticated device + task ID + operation/input digest. Input and source revision checks prevent resending a changed/deleted snapshot when acceptance is unknown.

Cancellation is a persisted intent on Flutter and an atomic terminal transition on the desktop. Cancelling an unknown ID creates a minimal durable fence: a delayed POST cannot start it later. Completion/cancellation races preserve whichever terminal transition committed first; a late worker response cannot overwrite cancellation, interruption or expiry. On restart queued inputs continue with their captured assignment; running generation becomes `interrupted` and loses its input, without restarting tokens; completed results remain retrievable. Runtime/worker errors produce failed work, with explicit retry guidance.

**Acknowledgment:** clearing a terminal preview first saves a local receipt with pending acknowledgment, then deactivates the preview. Online acknowledgment deletes desktop output and retains an idempotency receipt. If offline or its response is lost, foreground reconnection/startup retries the same acknowledgment. Acknowledgment is repeatable; the original operation cannot be executed again through that receipt. No automatic result acknowledgment occurs merely because a preview was displayed.

**Retention:** Flutter and desktop result access expires no later than 24 hours from the request (the desktop applies its own cap). Foreground expiry also removes an in-memory preview. Desktop cleanup removes input/output and marks an expiry receipt at its next minute sweep, before generation starts, and before a worker result can publish; GET hides expired data immediately. Shutdown/startup enforce expiry too. A stopped device cannot perform wall-clock deletion. Desktop digest/identity receipts last until seven days after result expiry; after their removal the original new-client request deadline still prevents replay. Local status metadata lasts seven days from request creation and is pruned on history/startup. Credentials and inputs never enter ordinary content sync. Clipboard exports remain controlled by the OS.

Account reset gates late callbacks and removes protected recovery state plus the ObjectBox history under the existing mandatory cleanup path. Trust remains separate from the sync account. An unreachable desktop can retain previously accepted encrypted work until expiry or explicit revocation, as the reset UI already explains.

## Verification and reproduction

The focused Flutter suite passed 55 checks, including real ObjectBox persistence/reset and source preservation; transport fault cases are synthetic. The desktop suite passed 26 checks, including encrypted persistence, acknowledgment replay after restart, cancel-before-submit fencing, both cancellation orderings, late output after expiry and queued/running/completed restart classification. Changed-file Flutter analysis and diff whitespace checks passed.

```sh
flutter test test/note_summary_test.dart test/companion_protocol_test.dart test/companion_controller_test.dart test/note_attachments_test.dart test/account_reset_integration_test.dart test/account_reset_settings_test.dart test/sync_schema_test.dart test/sync_storage_restart_test.dart
```

The companion's `scripts/verify-recovery.cjs` launches the actual packaged Electron 45.0.0/QVAC 0.22.0 app twice using an isolated vault and synthetic signed TLS peer. Phase one requires persisted running + queued jobs and completed results, then uses actual SIGKILL (no quit hook). Phase two verifies queued real inference, interrupted running work without rerunning it, retained completed output, acknowledgment replay, real cancellation races and cancel fencing. Expiry advances the clock deliberately; it is not a 24-hour wall-clock wait. See the compact evidence file and [the companion recovery guide](../../desktop/docs/RECOVERY.md).

Primary references consulted: [ObjectBox schema setup](https://docs.objectbox.io/getting-started), [transactions](https://docs.objectbox.io/transactions), and [Flutter lifecycle](https://api.flutter.dev/flutter/widgets/AppLifecycleListener-class.html). Implementation uses the pinned local package APIs and existing wrappers rather than copying newer dependency examples.

Physical Android evidence and remaining platform/network limitations are recorded in `task-recovery-evidence.json`. The phone harness uses only `r01-synthetic-objectbox` and separate `journal.companion.r01-demo.*` protected keys. Its CLI fixture seeds a synthetic trust identity for testing; it does not prove camera scanning or production pairing UI. See the companion documentation for setup. The first phone test launch intentionally waits after acceptance so an external `adb shell am force-stop com.lewiseman.journal` can terminate Flutter. Relaunch with the same binary/config and `--no-uninstall` to verify the same persisted identity, zero new submissions, recovered history/preview, unchanged source, deleted-source labeling and acknowledgment. After testing install a normal debug build with `adb install -r` to restore the regular entry point without wiping app data.

## Busy handling (2026-10-28)

The shared task slot no longer drops user actions silently.
- **Start:** every start method (summary, writing help, presentation, J01, J02,
  S01) first waits up to 25 seconds for an in-flight retrieval or startup restore
  to finish. If the controller is still busy, the task says "Your computer is
  still finishing the previous request. Nothing new was sent; try again in a
  moment." A slot owned by another unfinished task is left untouched, and each
  page already explains that case.
- **Clear:** waits the same way, and says "Still talking to your computer. Tap
  Clear again in a moment." if it still can't.
- **Freeing the slot:** clear frees the slot right after persisting the
  acknowledgment receipt, before the network acknowledgment. Up to three 7-second
  timeouts used to keep the old task in the slot and silently block the next
  request; a stall of over 15 seconds was observed on a phone. A late
  acknowledgment cannot wipe a newer task.
- **Tests:** `test/summary_busy_test.dart`.
