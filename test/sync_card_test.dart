import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/account/views/widgets/sync_card.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
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

void main() {
  setUpAll(() => CacheStorage.init(store: _Preferences()));

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
