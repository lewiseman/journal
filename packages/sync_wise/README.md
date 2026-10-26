# Sync Wise

A reusable Flutter package for a journal with one primary device and add-only
secondary devices. The host app owns its models/database and supplies handwritten
Riverpod providers. Both this package and Journal use `flutter_riverpod: ^3.4.3`;
Riverpod code generation is not used.

## Sync behavior

| Request | Behavior |
| --- | --- |
| Primary: first sync of an engine session | Download all documents, apply incoming data, upload pending changes |
| Primary: manual sync | Full round trip |
| Primary: later automatic sync | Upload pending documents without downloading journal content |
| Explicit primary recovery | Guardedly transfer the existing registry, then run a full sync |
| Secondary: note creation | Upload the new note only |
| Secondary: diary creation | Fetch the affected day, append unseen item IDs, conditionally upload that day |

Drive contains one shared JSON document per note/day. The primary designation and
shared document ID directory live in a private Drive app-data registry. If no
primary exists, the first device claims the role. Simultaneous registrations
converge on the earliest server-created claim, breaking ties by file ID. This is
not a transactional exclusive lock. Roles are checked on each eligible sync and
cached locally for offline permissions. The host may explicitly call
`engine.reclaimPrimary(expectedPrimary: state.primary)` after user confirmation.
Recovery waits for an active sync, validates the account and connectivity,
conditionally updates the elected registry, and runs a full restore. Document
reservations, migration markers, and cloud files are preserved. A concurrently
changed primary raises `PrimaryDeviceChanged` and refreshes the cached designation.
The former primary resolves as secondary on its next sync. There is no automatic
promotion. A confirmed account reset clears the designation.

Secondary diary writes preserve existing items, deletion tombstones, summary,
and mood. Creation is limited to the submitting device's current local date;
queued items retain that date when retried after midnight. Note and item UUIDs
make retries idempotent. Pending primary edits remain authoritative. The host's
collection adapter also protects recently saved fields for two minutes while
allowing unseen diary items to be appended.

Content reads obtain a coherent payload and strong Drive v2 file ETag. Content
updates use `If-Match`; a stale automatic primary upload is left pending until
the next startup/manual full sync. Secondary appends and full syncs may refetch
and retry up to three times. Registry document reservations also use guarded
updates and pre-generated file IDs. An absent baseline never authorizes replacing
an existing document. Provider metadata requests are allowed during upload-only
syncs; journal payloads are not downloaded for normal automatic primary uploads.

Eligible writes debounce for 300 ms. Automatic requests have a one-minute
cooldown, with trailing scheduled writes retained until it expires. Error/offline
attempts retry with backoff of at least one minute. Manual requests bypass the
cooldown. Requests never overlap. A record whose uploaded snapshot changed
locally stays pending. JSON transfers run with four workers by default; database
merges remain synchronous.

## Host contracts

- `SyncCollection`: detached document snapshots, validation, synchronous local
  reconciliation, pending status, diary append construction, and legacy import.
- `SyncKeyValueStore`: synchronous durable key/value storage. Write pending
  operations and edit timestamps inside the same transaction as the record.
  `SyncStateStore` manages cached roles, creation operations, field edit stamps,
  remote baselines, and records awaiting a full refresh.
- `SyncBackend` / `SyncAuth` / `SyncSession`: account and session lifecycle.
- `SyncClient`: primary registration, complete shared/legacy listings, document
  reads, guarded writes, migration completion, and app-data reset.
  Backends also implement `reclaimPrimary`, preserving the existing registry and
  rejecting a different primary than `expectedPrimary` (except an idempotent
  retry already belonging to the requesting device).

Journal's adapters are in `lib/modules/root/controllers/journal_sync_*.dart` in the host application. The package
has no dependency on Journal or ObjectBox. A memory key/value implementation is
available for tests; production hosts must provide durable storage.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/sync_wise.dart';

// backendProvider, deviceProvider, networkProvider, collectionsProvider and
// syncStorageProvider are handwritten providers supplied by the host app.
final engineProvider = NotifierProvider<SyncEngine, SyncEngineState>(
  () => SyncEngine((ref) {
    final device = ref.watch(deviceProvider);
    return SyncEngineConfig(
      backend: ref.watch(backendProvider),
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      network: ref.watch(networkProvider),
      collections: ref.watch(collectionsProvider),
      storage: ref.watch(syncStorageProvider),
      canSync: ref.watch(resetStorageProvider).canSync,
    );
  }),
  retry: (_, _) => null,
);

// After a local transaction:
ref.read(engineProvider.notifier).scheduleSync();
// A user requests a full primary sync (or sends pending secondary additions):
await ref.read(engineProvider.notifier).syncNow(manual: true);
```

Notifier instances belong to their ProviderContainer/ProviderScope. Listen/read
through the provider; do not call build or dispose on a controller directly.
Controllers cancel their timers/sessions on disposal and discard continuations
from a previous build. The host owns and disposes borrowed backends and injected
auth services. Keep startup/auth/connectivity listeners above navigation so
screen visibility does not pause coordination.

## Local data and compatibility

There is no file-transfer support. Images remain local; attachment path fields
are ordinary JSON strings. No file existence checks, downloads, path rewriting,
or transfer URI handling are performed. Removing file transfers does not make
platform identity/auth/reset adapters browser-ready.

The engine does not use conflict copies or version vectors for reconciliation.
The host retains existing note revision fields for stale-editor draft recovery.
Diary items accept both `createdAt` and the legacy `timestamp` wire field, and
day titles, note backgrounds, pinning and attachment metadata are preserved. Old per-device backups are imported once into shared documents. Import
completion is recorded only after successful uploads; old cloud files are kept
until account reset. All syncing clients must upgrade to this protocol.

Unknown-role devices may edit locally. If they resolve as secondary, existing
edits remain `SyncStatus.localOnly`; only queued creations are sent. Known
secondaries expose existing records as read-only. The host must enforce this in
its repositories and UI, including preserving drafts opened before role changes.

## Identity, accounts and reset

`DeviceIdentityService.initialize()` restores a persistent device ID. Retain it
across account resets. Configure Google sign-in, OAuth clients and Drive app-data
access for the host app. `GoogleDriveBackend` supplies the provider implementation;
additional providers implement the same contracts, including guarded writes.

`SyncAccountBinding` prevents local data from mixing with a different provider or
account. `AccountResetController` is a handwritten Notifier configured with
`AccountResetConfig`. It pauses/drains sync, persists reset intent, deletes cloud
data, invokes the host's idempotent local cleanup, signs out, and clears binding.
Use `AccountResetStorage.canSync` as the engine gate and block ordinary UI data
access while `AccountResetState.blocksDataAccess` is true. A persisted reset can
be resumed without repeating completed cloud deletion. The controller never
selects host tables or arbitrary files to delete.

Run `flutter analyze` and `flutter test` in this package and in the Journal root.
ObjectBox bindings in the host still use their existing generator; Riverpod does
not use generated code.

The reset contracts are available to hosts; this Journal integration does not expose a reset action.
