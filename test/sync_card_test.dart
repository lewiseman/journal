import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/account/views/widgets/sync_card.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/root/views/widgets/account_reset_gate.dart';
import 'package:journal/utils/cache.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

class _Preferences extends Fake implements KeyValueStore {
  @override
  Object? get(String key) => null;
}

class _Network extends Fake implements NetworkService {
  @override
  Future<bool> isOnline() async => true;
}

class _LocalData implements AccountResetLocalData {
  @override
  Future<void> clear() async {}
}

void main() {
  setUpAll(() => CacheStorage.init(store: _Preferences()));

  testWidgets(
    'reset immediately shows the signed-out card and replays current authentication',
    (tester) async {
      final fixture = await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'primary'),
      );
      final scope = ProviderContainer.test(
        overrides: [
          accountResetStorageProvider.overrideWithValue(TestResetStorage()),
          accountResetLocalDataProvider.overrideWithValue(_LocalData()),
          objectBoxProvider.overrideWithValue(fixture!.db),
          deviceIdentityProvider.overrideWithValue(fixture.device),
          networkServiceProvider.overrideWithValue(_Network()),
          syncBackendProvider.overrideWithValue(fixture.backend),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              navigatorKey: ref.watch(journalNavigatorKeyProvider),
              builder: (context, child) => AccountResetGate(child: child!),
              home: Scaffold(
                body: Builder(
                  builder: (context) => SizedBox(
                    height: SyncAccountCard.expandedHeight(
                      context,
                      isSignedIn: true,
                    ),
                    child: SyncAccountCard(
                      collapseProgress: 0,
                      onExpand: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await scope.read(accountResetProvider.notifier).ready;
      await scope.read(syncEngineProvider.notifier).syncNow(manual: true);
      await tester.pumpAndSettle();
      expect(find.text('owner@example.test'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      await scope
          .read(accountResetProvider.notifier)
          .reset(expectedAccountId: 'owner');
      await tester.pumpAndSettle();
      expect(scope.read(accountResetProvider).completed, isTrue);
      expect(find.text('Connect Account'), findsOneWidget);
      expect(find.text('On this device'), findsWidgets);
      expect(
        find.text('Connect Memory Cloud to sync your journal.'),
        findsOneWidget,
      );
      expect(find.text('owner@example.test'), findsNothing);
      expect(find.text('Connected'), findsNothing);
      expect(find.text('Journal synced'), findsNothing);
      expect(scope.read(authStateProvider), isA<AsyncData<SyncAccount?>>());
      expect(scope.read(authStateProvider).value, isNull);

      // Reconnecting must update the same card, without reopening the page.
      await tester.tap(find.byKey(const ValueKey('sync-card-action')));
      await tester.pumpAndSettle();
      expect(find.text('owner@example.test'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(scope.read(syncEngineProvider).status, EngineSyncState.idle);
      expect(tester.takeException(), isNull);
      scope.dispose();
    },
  );

  testWidgets(
    'connected account exposes manual restore and reports sync errors',
    (tester) async {
      final drive = MemoryDrive();
      final fixture = await tester.runAsync(
        () => SyncFixture.create(drive, 'primary'),
      );
      drive.seed(
        'note',
        'remote',
        NoteEntity(uuid: 'remote', content: 'From Drive').toSyncJson('phone'),
      );
      final scope = ProviderContainer.test(
        overrides: [
          accountResetStorageProvider.overrideWithValue(TestResetStorage()),
          objectBoxProvider.overrideWithValue(fixture!.db),
          deviceIdentityProvider.overrideWithValue(fixture.device),
          networkServiceProvider.overrideWithValue(_Network()),
          syncBackendProvider.overrideWithValue(fixture.backend),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => SizedBox(
                  height: SyncAccountCard.expandedHeight(
                    context,
                    isSignedIn: true,
                  ),
                  child: SyncAccountCard(collapseProgress: 0, onExpand: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Sync now'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sync-card-action')));
      await tester.pumpAndSettle();
      expect(
        scope.read(notesRepositoryProvider).getNoteByUuid('remote')!.content,
        'From Drive',
      );
      expect(scope.read(syncEngineProvider).status, EngineSyncState.idle);
      drive.failDownloads = true;
      await tester.tap(find.byKey(const ValueKey('sync-card-action')));
      await tester.pumpAndSettle();
      expect(scope.read(syncEngineProvider).status, EngineSyncState.error);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Cancel the retry timer before the widget test checks for pending timers.
      scope.dispose();
    },
  );
}
