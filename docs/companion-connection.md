# Local QVAC

Use **More → Local QVAC**. Open **Connect a phone** on the Electron companion, keep both devices on the same private Wi-Fi, scan/paste its current code, verify its identity and compare the phone verification code before desktop approval. No Google sign-in or journal content is involved.

The phone page uses an illustrated **Wi-Fi → Scan → Approve** walkthrough.
Tap a step to explore its picture, or tap QVAC / **Listen** to hear that step
using the phone’s text-to-speech. Speech is requested explicitly, reads only setup
instructions (including the phone verification code while pairing), and stops
when the step, connection phase, route or foreground state changes. Voice
availability depends on the phone’s installed speech engine and voice; a failed
voice leaves the visual walkthrough usable. No extra AI request is made.

**Next** leads to the large **Scan QR** action. The scanner also offers **Use a
code instead**, including when camera permission is denied. Exploring the
walkthrough never grants trust: identity confirmation, matching phone codes and
desktop approval are still required. Only the live connected phase displays the
success scene. Model readiness appears in a compact horizontal strip below it,
with activity icons and plain labels such as Writing, Photos, Search and Ready.
Tap a status for its model’s explanation. The strip remembers its horizontal
position for each selected computer when a connection check temporarily hides it.

The saved-computer card sits directly below the strip. It opens **Computers**
for selection, reconnect, disconnect, Forget, discovery and adding another
computer. Pairing started on that page displays the same live verification guide
there, so the approval code remains visible. Before a computer is saved, **Use a
code** and **Find computer** are also available directly below the guide.

Illustrated **Voice** and **Past work** shortcuts open the existing reply-voice
picker and AI task history. **Make it yours** opens a dedicated preferences page
for daily diary questions and search by meaning, retaining their existing opt-in
disclosures and controls. **Need help?** and **Connection details** open separate
pages for visual troubleshooting, privacy information and the saved computer’s
full identity. The main page keeps its top connection card and has no inline
settings panels or destructive device actions.

Layouts follow the selected theme and font, use a bounded column on wide
screens, stack controls at large text sizes, and respect reduced motion. The
mascot reacts to taps with a short bounce, and dashboard controls react with a
short press animation. There is no continuous idle animation. Detail pages keep
the floating assistant hidden and stop the main guide’s speech while open.

Transport and model readiness are separate. Retry uses saved platform-protected trust. Disconnect retains trust/work and pauses automatic connection; Forget also revokes/deletes retained desktop work when reachable. Offline Forget explains how to revoke later on the desktop. Identity changes require explicit recovery.

Discovery stops in the background. Camera denial has a full-code fallback. Allow Local Network on iPhone if denied. IPv4 routing is required; guest Wi-Fi, VPNs and some hotspots block discovery or direct access. A QR does not bypass isolation.

See [the protocol, architecture, reproducible commands and evidence limits](../../desktop/docs/CONNECTION.md). Real Android results, native QVAC, deterministic tests, the unsigned iOS build, and unverified WAN-offline/topology cases are reported separately.

```sh
flutter analyze lib/modules/settings/companion lib/main.dart integration_test/companion_device_test.dart
flutter test test/companion_protocol_test.dart test/companion_controller_test.dart test/sync_account_sheet_test.dart test/account_reset_settings_test.dart
flutter test test/companion_page_test.dart test/qvac_assistant_test.dart test/more_page_test.dart
```

`test/companion_page_test.dart` covers the visual steps, requested speech and its
cancellation, camera-denied fallback, expired codes, identity confirmation,
pairing cancellation, live success/model readiness, saved connection controls,
discovery, dashboard navigation, pairing from Computers, model-status details,
advanced options, dark mode, 320-pixel screens at 2× text, landscape, wide screens
and reduced motion. The adaptive checks also navigate all four new detail pages.
These use fake camera/voice/connection services;
they do not demonstrate physical-camera scanning or native audio playback. Set
`--dart-define=COMPANION_CAPTURES=true` to save rendered previews under
`/tmp/journal-companion-*.png`.

Real-device tests need the private short-lived configuration described in the companion documentation. Keep `--no-uninstall` on successive runs so Flutter's default teardown does not erase Android trust storage.
