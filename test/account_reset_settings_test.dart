import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/root/views/widgets/account_reset_gate.dart';
import 'package:journal/modules/settings/views/pages/settings_page.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

class _Network extends Fake implements NetworkService {
  bool online = true;
  @override
  Future<bool> isOnline() async => online;
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
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    final reset = find.byKey(const ValueKey('reset-account-data'));
    await tester.scrollUntilVisible(
      reset,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('reset-confirmation-input'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'DELETE');
    await tester.pump();
  }

  testWidgets(
    'reset needs an account, exact DELETE confirmation and supports cancelling',
    (tester) async {
      await mount(tester);
      final button = find.byKey(const ValueKey('reset-account-data'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(drive.deletions, 0);
      expect(fixture.db.noteBox.count(), 1);
      await fixture.backend.auth.signOut();
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    },
  );

  testWidgets(
    'sync disables reset and the controller rejects reset without interrupting sync',
    (tester) async {
      await mount(tester);
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
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
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
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
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
      expect(
        find.text('Account data deleted. Connect an account to start again.'),
        findsOneWidget,
      );
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
      expect(find.text('Settings'), findsNothing);
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
      expect(find.text('Settings'), findsOneWidget);
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

  testWidgets('even a fast reset disposes an editor open above Settings', (
    tester,
  ) async {
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
  });

  testWidgets('reset confirmation fits narrow screens and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, scale: 1.8);
    await confirm(tester);
    expect(
      find.byKey(const ValueKey('confirm-reset-account')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
