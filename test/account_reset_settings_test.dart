import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/account/views/pages/reset_account_page.dart';
import 'package:journal/modules/account/views/widgets/sync_card.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/root/views/widgets/account_reset_gate.dart';
import 'package:journal/utils/cache.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

class _Network extends Fake implements NetworkService {
  bool online = true;
  @override
  Future<bool> isOnline() async => online;
}

class _Preferences extends Fake implements KeyValueStore {
  @override
  Object? get(String key) => null;
}

class _LocalData implements AccountResetLocalData {
  final SyncFixture fixture;
  int calls = 0;
  _LocalData(this.fixture);
  @override
  Future<void> clear() async {
    calls++;
    fixture.db.store.runInTransaction(TxMode.write, () {
      fixture.db.noteBox.removeAll();
      fixture.db.diaryBox.removeAll();
      fixture.storage.clear();
    });
  }
}

void main() {
  late SyncFixture fixture;
  late MemoryDrive drive;
  late ProviderContainer scope;
  late TestResetStorage storage;
  late _LocalData local;
  late _Network network;

  setUpAll(() => CacheStorage.init(store: _Preferences()));

  setUp(() async {
    drive = MemoryDrive();
    fixture = await SyncFixture.create(drive, 'phone');
    fixture.notes.saveNote(
      uuid: 'one',
      title: 'Private',
      content: 'Saved journal',
    );
    await fixture.sync();
    storage = TestResetStorage();
    local = _LocalData(fixture);
    network = _Network();
    scope = ProviderContainer.test(
      overrides: [
        objectBoxProvider.overrideWithValue(fixture.db),
        deviceIdentityProvider.overrideWithValue(fixture.device),
        syncBackendProvider.overrideWithValue(fixture.backend),
        networkServiceProvider.overrideWithValue(network),
        accountResetStorageProvider.overrideWithValue(storage),
        accountResetLocalDataProvider.overrideWithValue(local),
      ],
    );
  });

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            navigatorKey: ref.watch(journalNavigatorKeyProvider),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: AccountResetGate(child: child!),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder: (context, ref, _) => SizedBox(
                    height: SyncAccountCard.expandedHeight(
                      context,
                      isSignedIn: ref.watch(syncAccountProvider) != null,
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
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    final status = find.byKey(const ValueKey('sync-card-status'));
    await tester.ensureVisible(status);
    await tester.pumpAndSettle();
    await tester.tap(status);
    await tester.pumpAndSettle();
  }

  Future<void> openResetPage(WidgetTester tester) async {
    await openSheet(tester);
    final reset = find.byKey(const ValueKey('reset-account-data'));
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.byType(ResetAccountPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(drive.deletions, 0);
  }

  Future<void> confirm(WidgetTester tester) async {
    await openResetPage(tester);
    final input = find.byKey(const ValueKey('reset-confirmation-input'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'DELETE');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('confirm-reset-account')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reset needs an account, exact DELETE confirmation and supports cancelling',
    (tester) async {
      await mount(tester);
      await openResetPage(tester);
      expect(
        find.textContaining('owner@example.test', findRichText: true),
        findsWidgets,
      );
      final delete = find.byKey(const ValueKey('confirm-reset-account'));
      expect(tester.widget<FilledButton>(delete).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('reset-confirmation-input')),
        'delete',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(delete).onPressed, isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(drive.deletions, 0);
      expect(fixture.db.noteBox.count(), 1);
      expect(find.byType(ResetAccountPage), findsNothing);
      await confirm(tester);
      await fixture.backend.auth.signOut();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(delete).onPressed, isNull);
      expect(
        find.textContaining('Reconnect owner@example.test'),
        findsOneWidget,
      );
      fixture.backend.auth.user = const SyncAccount(
        id: 'different-owner',
        email: 'different@example.test',
      );
      fixture.backend.auth.changes.add(fixture.backend.auth.user);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(delete).onPressed, isNull);
      expect(drive.deletions, 0);
    },
  );

  testWidgets(
    'sync disables reset and the controller rejects reset without interrupting sync',
    (tester) async {
      await mount(tester);
      await openSheet(tester);
      final button = find.byKey(const ValueKey('reset-account-data'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      drive.beforeList = (_) => release.future;
      final syncing = scope
          .read(syncEngineProvider.notifier)
          .syncNow(manual: true);
      await tester.pump();
      expect(scope.read(syncEngineProvider).isSyncing, isTrue);
      expect(tester.widget<ListTile>(button).enabled, isFalse);
      expect(
        find.text('Wait for sync to finish before resetting account data.'),
        findsOneWidget,
      );
      await scope
          .read(accountResetProvider.notifier)
          .reset(expectedAccountId: 'owner');
      expect(scope.read(accountResetProvider).blocksDataAccess, isFalse);
      expect(
        scope.read(accountResetProvider).error,
        contains('Wait for sync to finish'),
      );
      expect(drive.deletions, 0);
      expect(local.calls, 0);
      expect(storage.intent, isNull);
      expect(fixture.backend.auth.isSignedIn, isTrue);
      release.complete();
      await syncing;
      await tester.pumpAndSettle();
      expect(scope.read(syncEngineProvider).status, EngineSyncState.idle);
      expect(tester.widget<ListTile>(button).enabled, isTrue);
    },
  );

  testWidgets('sync starting during confirmation disables permanent deletion', (
    tester,
  ) async {
    await mount(tester);
    await confirm(tester);
    final button = find.byKey(const ValueKey('confirm-reset-account'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    drive.beforeList = (_) => release.future;
    final syncing = scope
        .read(syncEngineProvider.notifier)
        .syncNow(manual: true);
    await tester.pump();
    expect(scope.read(syncEngineProvider).isSyncing, isTrue);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(drive.deletions, 0);
    release.complete();
    await syncing;
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'confirmed reset clears data, signs out and returns to fresh navigation',
    (tester) async {
      await mount(tester);
      await confirm(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-reset-account')));
      await tester.pumpAndSettle();
      expect(scope.read(accountResetProvider).completed, isTrue);
      expect(local.calls, 1);
      expect(fixture.db.noteBox.count(), 0);
      expect(drive.documents, isEmpty);
      expect(fixture.backend.auth.currentUser, isNull);
      expect(find.text('Connect Account'), findsOneWidget);
      expect(find.byType(ResetAccountPage), findsNothing);
      expect(
        find.text('Account data reset. You are signed out.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an interrupted reset replaces all routes and can be finished after restart',
    (tester) async {
      storage.intent = const ResetIntent('owner', backendId: 'memory');
      await mount(tester);
      expect(find.byType(SyncAccountCard), findsNothing);
      expect(find.byKey(const ValueKey('reclaim-primary-role')), findsNothing);
      expect(
        find.byKey(const ValueKey('resume-account-reset')),
        findsOneWidget,
      );
      expect(fixture.db.noteBox.count(), 1);
      await scope.read(syncEngineProvider.notifier).reclaimPrimary();
      expect(drive.reclaims, 0);
      drive.failDelete = true;
      await tester.tap(find.byKey(const ValueKey('resume-account-reset')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Deletion interrupted'), findsOneWidget);
      expect(local.calls, 0);
      drive.failDelete = false;
      await tester.tap(find.byKey(const ValueKey('resume-account-reset')));
      await tester.pumpAndSettle();
      expect(scope.read(accountResetProvider).completed, isTrue);
      expect(find.byType(SyncAccountCard), findsOneWidget);
      expect(local.calls, 1);
    },
  );

  testWidgets('offline preflight explains the failure without deleting data', (
    tester,
  ) async {
    network.online = false;
    await mount(tester);
    await confirm(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-reset-account')));
    await tester.pumpAndSettle();
    expect(scope.read(accountResetProvider).blocksDataAccess, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('Connect to the internet to delete'),
      findsWidgets,
    );
    expect(fixture.db.noteBox.count(), 1);
    expect(drive.deletions, 0);
  });

  testWidgets(
    'even a fast reset disposes an editor open above the account card',
    (tester) async {
      await mount(tester);
      final navigator = scope.read(journalNavigatorKeyProvider).currentState!;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Old private draft')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old private draft'), findsOneWidget);
      await scope
          .read(accountResetProvider.notifier)
          .reset(expectedAccountId: 'owner');
      await tester.pumpAndSettle();
      expect(find.text('Old private draft'), findsNothing);
      expect(
        scope.read(journalNavigatorKeyProvider).currentState!.canPop(),
        isFalse,
      );
    },
  );

  testWidgets('reset confirmation fits narrow screens and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, scale: 1.8);
    await confirm(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('confirm-reset-account')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('confirm-reset-account')).hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
