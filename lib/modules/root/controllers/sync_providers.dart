import 'dart:async';

import 'package:journal/common.dart' hide NetworkService, NetworkType;
import 'package:sync_wise/google_drive.dart';
import 'package:sync_wise/sync_wise.dart';

import 'journal_sync_collections.dart';
import 'journal_sync_store.dart';
import 'journal_account_reset_data.dart';

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
    documentIdFields: const {
      'note': 'uuid',
      'diary': 'date_string',
      'thought': 'uuid',
    },
  );
  ref.onDispose(backend.dispose);
  return backend;
});

final syncAuthProvider = Provider<SyncAuth>(
  (ref) => ref.watch(syncBackendProvider).auth,
);
final authStateProvider = StreamProvider<SyncAccount?>((ref) {
  final auth = ref.watch(syncAuthProvider);
  return Stream.multi((events) {
    // Subscribe before reading the snapshot so refreshing after reset cannot
    // miss sign-out, even when the backend only broadcasts future changes.
    final subscription = auth.onAuthStateChanged.listen(
      events.add,
      onError: events.addError,
      onDone: events.close,
    );
    events.add(auth.currentUser);
    events.onCancel = subscription.cancel;
  });
});
final syncAccountProvider = Provider<SyncAccount?>((ref) {
  final auth = ref.watch(syncAuthProvider);
  return ref
      .watch(authStateProvider)
      .when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        data: (account) => account,
        loading: () => auth.currentUser,
        error: (_, _) => auth.currentUser,
      );
});
final syncStateStoreProvider = Provider<SyncStateStore>(
  (ref) => SyncStateStore(
    storage: JournalSyncKeyValueStore(ref.watch(objectBoxProvider).store),
    deviceId: ref.watch(deviceIdentityProvider).deviceId,
  ),
);
final accountResetStorageProvider = Provider<AccountResetStorage>(
  (ref) => AccountResetStorage(),
);
final accountResetLocalDataProvider = Provider<AccountResetLocalData>(
  (ref) => JournalAccountResetData(db: ref.watch(objectBoxProvider)),
);
final accountResetProvider =
    NotifierProvider<AccountResetController, AccountResetState>(
      () => AccountResetController(
        (ref) => AccountResetConfig(
          storage: ref.watch(accountResetStorageProvider),
          engine: ref.watch(syncEngineProvider.notifier),
          backend: ref.watch(syncBackendProvider),
          network: ref.watch(networkServiceProvider),
          localData: ref.watch(accountResetLocalDataProvider),
        ),
      ),
      retry: (_, _) => null,
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
          canSync: ref.watch(accountResetStorageProvider).canSync,
          collections: journalSyncCollections(
            db: ref.watch(objectBoxProvider),
            device: device,
            notes: ref.watch(notesRepositoryProvider),
            diary: ref.watch(diaryRepositoryProvider),
            thoughts: ref.watch(thoughtsRepositoryProvider),
            storage: storage,
          ),
        );
      }),
      retry: (_, _) => null,
    );

// Read above navigation: authentication and connectivity keep working on every tab.
final syncCoordinatorProvider = Provider<void>((ref) {
  final auth = ref.watch(syncAuthProvider);
  final reset = ref.watch(accountResetProvider.notifier);
  ref.watch(syncEngineProvider.notifier);
  bool canSchedule() =>
      ref.mounted && !ref.read(accountResetProvider).blocksDataAccess;
  var resetGeneration = 0;
  ref.listen(accountResetProvider, (previous, next) {
    if (next.running && previous?.running != true) resetGeneration++;
  });
  final subscription = ref
      .watch(networkServiceProvider)
      .onConnectivityChanged
      .listen((type) {
        if (type != NetworkType.none && canSchedule()) {
          ref.read(syncEngineProvider.notifier).scheduleSync();
        }
      });
  final localChanges = ref.watch(journalChangesProvider).stream.listen((_) {
    if (canSchedule()) ref.read(syncEngineProvider.notifier).scheduleSync();
  });
  ref.onDispose(localChanges.cancel);
  final authentication = auth.onAuthStateChanged.listen((account) {
    if (account != null && canSchedule()) {
      ref.read(syncEngineProvider.notifier).scheduleSync();
    }
  });
  ref.onDispose(subscription.cancel);
  ref.onDispose(authentication.cancel);
  Future<void>(() async {
    await reset.ready;
    if (!canSchedule()) return;
    final generation = resetGeneration;
    await auth.trySilentSignIn();
    if (!ref.mounted) return;
    if (generation != resetGeneration) {
      // A startup sign-in finishing late must not reconnect a reset account.
      if (ref.read(accountResetProvider).completed && auth.isSignedIn) {
        await auth.signOut();
      }
      return;
    }
    if (canSchedule()) ref.read(syncEngineProvider.notifier).scheduleSync();
  });
});

final syncDeviceRoleProvider = Provider<SyncDeviceRole>(
  (ref) => ref.watch(syncEngineProvider.select((state) => state.role)),
);
