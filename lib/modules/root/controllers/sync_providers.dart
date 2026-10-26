import 'dart:async';

import 'package:journal/common.dart' hide NetworkService, NetworkType;
import 'package:sync_wise/google_drive.dart';
import 'package:sync_wise/sync_wise.dart';

import 'journal_sync_collections.dart';
import 'journal_sync_store.dart';

// Repositories publish local commits without depending back on the sync engine.
final journalChangesProvider = Provider<StreamController<void>>((ref) {
  final changes = StreamController<void>.broadcast(sync: true);
  ref.onDispose(changes.close);
  return changes;
});

final objectBoxProvider = Provider<ObjectBox>((ref) => objectbox);
final deviceIdentityProvider = Provider<DeviceIdentityService>(
  (ref) => DeviceIdentityService.instance,
);
final networkServiceProvider = Provider<NetworkService>(
  (ref) => NetworkService(),
);

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  final auth = GoogleAuthService();
  ref.onDispose(auth.dispose);
  return auth;
});

final syncBackendProvider = Provider<SyncBackend>((ref) {
  final backend = GoogleDriveBackend(
    auth: ref.watch(googleAuthServiceProvider),
    documentIdFields: const {'note': 'uuid', 'diary': 'dateString'},
  );
  ref.onDispose(backend.dispose);
  return backend;
});

final syncAuthProvider = Provider<SyncAuth>(
  (ref) => ref.watch(syncBackendProvider).auth,
);
final authStateProvider = StreamProvider<SyncAccount?>(
  (ref) => ref.watch(syncAuthProvider).onAuthStateChanged,
);
final syncStateStoreProvider = Provider<SyncStateStore>(
  (ref) => SyncStateStore(
    storage: JournalSyncKeyValueStore(ref.watch(objectBoxProvider).store),
    deviceId: ref.watch(deviceIdentityProvider).deviceId,
  ),
);
final NotifierProvider<SyncEngine, SyncEngineState> syncEngineProvider =
    NotifierProvider<SyncEngine, SyncEngineState>(
      () => SyncEngine((ref) {
        final device = ref.watch(deviceIdentityProvider);
        final storage = ref.watch(syncStateStoreProvider);
        return SyncEngineConfig(
          backend: ref.watch(syncBackendProvider),
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          network: ref.watch(networkServiceProvider),
          storage: storage,
          collections: journalSyncCollections(
            db: ref.watch(objectBoxProvider),
            device: device,
            notes: ref.watch(notesRepositoryProvider),
            diary: ref.watch(diaryRepositoryProvider),
            storage: storage,
          ),
        );
      }),
      retry: (_, _) => null,
    );

// Read above navigation: authentication and connectivity keep working on every tab.
final syncCoordinatorProvider = Provider<void>((ref) {
  final auth = ref.watch(syncAuthProvider);
  ref.watch(syncEngineProvider.notifier);
  final subscription = ref
      .watch(networkServiceProvider)
      .onConnectivityChanged
      .listen((type) {
        if (type != NetworkType.none && ref.mounted) {
          ref.read(syncEngineProvider.notifier).scheduleSync();
        }
      });
  final localChanges = ref.watch(journalChangesProvider).stream.listen((_) {
    if (ref.mounted) ref.read(syncEngineProvider.notifier).scheduleSync();
  });
  ref.onDispose(localChanges.cancel);
  final authentication = auth.onAuthStateChanged.listen((account) {
    if (account != null && ref.mounted) {
      ref.read(syncEngineProvider.notifier).scheduleSync();
    }
  });
  ref.onDispose(subscription.cancel);
  ref.onDispose(authentication.cancel);
  Future<void>(() async {
    if (!ref.mounted) return;
    await auth.trySilentSignIn();
    if (ref.mounted) ref.read(syncEngineProvider.notifier).scheduleSync();
  });
});

final syncDeviceRoleProvider = Provider<SyncDeviceRole>(
  (ref) => ref.watch(syncEngineProvider.select((state) => state.role)),
);
