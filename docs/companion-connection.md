# Local AI computer

Use **Settings → Local AI computer**. Open **Connect a phone** on the Electron companion, keep both devices on the same private Wi-Fi, scan/paste its current code, verify its identity and compare the phone verification code before desktop approval. No Google sign-in or journal content is involved.

Transport and model readiness are separate. Retry uses saved platform-protected trust. Disconnect retains trust/work and pauses automatic connection; Forget also revokes/deletes retained desktop work when reachable. Offline Forget explains how to revoke later on the desktop. Identity changes require explicit recovery.

Discovery stops in the background. Camera denial has a full-code fallback. Allow Local Network on iPhone if denied. IPv4 routing is required; guest Wi-Fi, VPNs and some hotspots block discovery or direct access. A QR does not bypass isolation.

See [the protocol, architecture, reproducible commands and evidence limits](../../desktop/docs/CONNECTION.md). Real Android results, native QVAC, deterministic tests, the unsigned iOS build, and unverified WAN-offline/topology cases are reported separately.

```sh
flutter analyze lib/modules/settings/companion lib/main.dart integration_test/companion_device_test.dart
flutter test test/companion_protocol_test.dart test/companion_controller_test.dart test/primary_device_settings_test.dart test/account_reset_settings_test.dart
```

Real-device tests need the private short-lived configuration described in the companion documentation. Keep `--no-uninstall` on successive runs so Flutter's default teardown does not erase Android trust storage.
