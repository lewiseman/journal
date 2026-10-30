# People

More → People contains friends and temporary notes. Add friend creates a QR/text
invitation or accepts a scanned/pasted invitation. The inviter explicitly confirms
the request. Invitations expire after five minutes and are single-use. To share
through another app, copy the invitation, share it, then return to Journal.

Friends and Notes use rounded icon tabs under a collapsing, pinned header with
the Friends artwork from More and a subtle accent wash. The tabs keep independent
scroll positions. Friends appear as rows with their blob avatars and
waiting-note counts. Add friend separates Invite from Accept (scan or paste).
Pages follow the app's background, accent and selected font; explanatory copy
lives in empty states. The QR expiry border, scanner and burning reader remain.

Incoming-note alerts are floating paper cards with an animated envelope, sender
avatar and an ink flourish. They offer Open Friends and dismiss actions, show no
note preview, and keep only the latest arrival on screen. Motion follows the app
setting; alerts stay static with animations disabled and clear on backgrounding.

The reader gives brief notes a paper sheet at least 280 logical pixels tall,
with the message centered horizontally and vertically. Longer letters grow and
scroll on ruled paper. Sender details, the reading timer and Close remain outside
the burning area; landscape layouts put the timer and controls beside the sheet.

Friend details opens Write a note, lists unopened notes, and removes a friend.
Notes contain newly written plain text, at most 500 whitespace-separated words
and 8 KiB of UTF-8. Both apps must be open. Sending makes one attempt with a
15-second budget, including connection setup. A local stream finishing is not a
delivery acknowledgement. There are no message retries, notifications, receipts,
presence records, hosted mailbox, or message history.

Opening starts `max(20, 10 + ceil(words × 60 / 150))` seconds of reading time,
measured with a monotonic clock. Closing, expiration, backgrounding or process exit
discards the note. Backgrounding also clears unopened notes and drafts. The queue
holds at most 20 notes; excess notes are discarded. Notes are never written to
ObjectBox, Drive, disk, logs, analytics, or AI requests. Dart strings cannot promise
forensic memory erasure, and recipients can capture text or use a modified client.

The secure `journal_people` namespace stores only a random device identity seed
and friends' names/public keys. It is excluded from Android cloud backup and
device transfer. Google sign-in/out does not control People. Account-data reset
stops networking and clears identity and contacts. Removing a friend discards
their pending notes and revokes their key locally; pairing again is required.
Losing the installation identity requires pairing again on each friend's phone.

## Runtime

People uses official HyperDHT 6.35.0 (Pear's networking stack), with authenticated
Noise streams and pinned friend keys. A short-lived random invitation token gates
pairing; discovery keys and display names alone never establish trust. Network
frames are length-prefixed, versioned, and bounded at 16 KiB. Unknown peers may
only request pairing while an invitation is active; they cannot send notes.

`native/qvac/people` is an independent worker with its own channels
`journal/people` and `journal/people_ipc`. It shares the existing pinned BareKit
2.5.5 artifacts and linked-addon versions with QVAC, without sharing either
worker's state. The generic Dart RPC framing lives in `lib/utils/worklet_rpc`.
Build both workers using `cd native/qvac && npm ci && node build.mjs --platform=android`
before packaging. Generated bundles/native resources remain ignored, as with QVAC.
People requires Android 10+, arm64; iOS displays an unavailable explanation.

HyperDHT uses the public bootstrap/discovery network. No Journal message backend
or owner relay is included. UDP-blocking firewalls and some mobile-carrier NAT
combinations prevent delivery. Noise encrypts content; this is not an anonymity
network and connection metadata is observable.

## Verification and release gate

Automated checks:

```sh
(cd native/qvac && npm run test:people)
(cd native/qvac && npm run test:people:bare)
flutter test test/people_test.dart test/people_transport_test.dart test/more_page_test.dart test/local_ai
flutter test integration_test/people_device_test.dart -d DEVICE_ID
flutter test integration_test/people_device_test.dart -d DEVICE_ID --release
flutter analyze
flutter build apk --debug --target-platform android-arm64
```

The Node network tests and Bare runtime smoke test use real Noise connections
over an isolated local DHT; they do not substitute for Android device validation.
The integration test checks
two independently running BareKit workers and shutdown in both orders, without
loading AI models or storing a real identity.

Before release, run the integration test on a physical Android phone and exercise
two physical phones on the same Wi-Fi and on separate Wi-Fi/mobile networks:

1. Pair using QR, then remove and re-pair using pasted invitations. Try expired,
   cancelled and previously consumed invitations; decline an unexpected candidate.
2. Restart both apps and send a short note in each direction. Check in-app alerts
   from Diary and ensure no note content appears in the alert.
3. Open, close and reopen the reader; wait for expiration; background, lock and
   kill either app. No discarded text should return. Check a 100-word note gets
   50 seconds and a 500-word note gets 210 seconds.
4. Send with the recipient closed, disconnect during send, and use a UDP-blocking
   network. The attempt must end, clear the draft, and never retry automatically.
5. Remove a friend while a note is open, and reset account data. Verify all local
   text/trust is removed and the old key no longer receives notes.
6. Start/stop local QVAC before and during a People session in both orders.

Physical-device and carrier-network testing is required before publishing this feature.
