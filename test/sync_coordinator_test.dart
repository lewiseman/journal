import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

class _Auth extends MemoryAuth {
  int silentSignIns = 0;
  Completer<void>? entered, release;
  @override
  Future<SyncAccount?> trySilentSignIn() async {
    silentSignIns++;
    entered?.complete();
    if (release != null) {
      await release!.future;
      user = const SyncAccount(id: 'owner', email: 'owner@example.test');
      changes.add(user);
    }
    return user;
  }
}

class _NoopLocalData implements AccountResetLocalData {
  @override
  Future<void> clear() async {}
}

class _Network extends Fake implements NetworkService {
  bool online = true;
  final changes = StreamController<NetworkType>.broadcast();
  @override
  Future<bool> isOnline() async => online;
  @override
  Stream<NetworkType> get onConnectivityChanged => changes.stream;
}

void main() {
  test(
    'pending reset blocks startup auth and connectivity/local-write scheduling',
    () async {
      final drive = MemoryDrive();
      final fixture = await SyncFixture.create(drive, 'phone');
      final auth = _Auth();
      final backend = MemoryBackend(drive, auth: auth);
      final network = _Network();
      final storage = TestResetStorage()
        ..intent = const ResetIntent('owner', backendId: 'memory');
      addTearDown(backend.dispose);
      addTearDown(network.changes.close);
      final container = ProviderContainer.test(
        overrides: [
          accountResetStorageProvider.overrideWithValue(storage),
          objectBoxProvider.overrideWithValue(fixture.db),
          deviceIdentityProvider.overrideWithValue(fixture.device),
          networkServiceProvider.overrideWithValue(network),
          syncBackendProvider.overrideWithValue(backend),
        ],
      );
      container.read(syncCoordinatorProvider);
      await container.read(accountResetProvider.notifier).ready;
      network.changes.add(NetworkType.wifiOrEthernet);
      container.read(journalChangesProvider).add(null);
      await Future<void>.delayed(Duration.zero);
      await container.read(syncEngineProvider.notifier).syncNow(manual: true);
      expect(container.read(accountResetProvider).blocksDataAccess, isTrue);
      expect(auth.silentSignIns, 0);
      expect(backend.sessions, 0);
    },
  );

  test(
    'a late startup sign-in cannot reconnect an account after reset',
    () async {
      final drive = MemoryDrive();
      final fixture = await SyncFixture.create(drive, 'phone');
      final auth = _Auth()
        ..entered = Completer<void>()
        ..release = Completer<void>();
      final backend = MemoryBackend(drive, auth: auth);
      final network = _Network();
      addTearDown(backend.dispose);
      addTearDown(network.changes.close);
      final container = ProviderContainer.test(
        overrides: [
          accountResetStorageProvider.overrideWithValue(TestResetStorage()),
          accountResetLocalDataProvider.overrideWithValue(_NoopLocalData()),
          objectBoxProvider.overrideWithValue(fixture.db),
          deviceIdentityProvider.overrideWithValue(fixture.device),
          networkServiceProvider.overrideWithValue(network),
          syncBackendProvider.overrideWithValue(backend),
        ],
      );
      container.read(syncCoordinatorProvider);
      await auth.entered!.future;
      await container
          .read(accountResetProvider.notifier)
          .reset(expectedAccountId: 'owner');
      expect(container.read(accountResetProvider).completed, isTrue);
      expect(auth.currentUser, isNull);
      auth.release!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser, isNull);
    },
  );

  test('app provider wiring starts sync once and local diary saves schedule uploads', () async {
    final drive = MemoryDrive();
    final fixture = await SyncFixture.create(drive, 'primary');
    final auth = _Auth();
    final backend = MemoryBackend(drive, auth: auth);
    final network = _Network();
    addTearDown(backend.dispose);
    addTearDown(network.changes.close);
    final container = ProviderContainer.test(
      overrides: [
        accountResetStorageProvider.overrideWithValue(TestResetStorage()),
        objectBoxProvider.overrideWithValue(fixture.db),
        deviceIdentityProvider.overrideWithValue(fixture.device),
        networkServiceProvider.overrideWithValue(network),
        syncBackendProvider.overrideWithValue(backend),
      ],
    );
    container.read(syncCoordinatorProvider);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(auth.silentSignIns, 1);
    expect(container.read(syncEngineProvider).status, EngineSyncState.idle);
    container
        .read(diaryRepositoryProvider)
        .addTimelineItem(
          dateString: '2026-10-26',
          content: 'From the app providers',
        );
    container
        .read(notesRepositoryProvider)
        .saveNote(uuid: 'note', title: 'From providers', content: 'Saved here');
    expect(container.read(syncEngineProvider).status, EngineSyncState.pending);
    await container.read(syncEngineProvider.notifier).syncNow(manual: true);
    expect(drive.documents['diary/2026-10-26']!.payload['items'], hasLength(1));
    expect(drive.documents['note/note']!.payload['content'], 'Saved here');
    await Future<void>.delayed(Duration.zero);
    expect(auth.silentSignIns, 1);
  });
}
