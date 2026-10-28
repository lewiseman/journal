import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/account/views/widgets/sync_card.dart';
import 'package:journal/modules/account/views/widgets/sync_account_sheet.dart';
import 'package:journal/utils/cache.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

class _Network extends Fake implements NetworkService {
  Future<void>? wait;

  @override
  Future<bool> isOnline() async {
    await wait;
    return true;
  }
}

class _Preferences extends Fake implements KeyValueStore {
  @override
  Object? get(String key) => null;
}

void main() {
  late MemoryDrive drive;
  late SyncFixture fixture;
  late ProviderContainer scope;
  late _Network network;

  setUpAll(() => CacheStorage.init(store: _Preferences()));

  setUp(() async {
    drive = MemoryDrive()
      ..primary = const PrimaryDevice(
        deviceId: 'old',
        deviceName: 'Old phone',
        fileId: 'registry',
      );
    fixture = await SyncFixture.create(drive, 'reinstalled');
    await fixture.sync();
    network = _Network();
    scope = ProviderContainer.test(
      overrides: [
        accountResetStorageProvider.overrideWithValue(TestResetStorage()),
        objectBoxProvider.overrideWithValue(fixture.db),
        deviceIdentityProvider.overrideWithValue(fixture.device),
        networkServiceProvider.overrideWithValue(network),
        syncBackendProvider.overrideWithValue(fixture.backend),
      ],
    );
  });

  Future<void> mount(
    WidgetTester tester, {
    double scale = 1,
    bool openSheet = true,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer(
                builder: (context, ref, _) => SizedBox(
                  height: SyncAccountCard.expandedHeight(
                    context,
                    isSignedIn: ref.watch(syncAccountProvider) != null,
                  ),
                  child: SyncAccountCard(collapseProgress: 0, onExpand: () {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (openSheet) {
      final status = find.byKey(const ValueKey('sync-card-status'));
      await tester.ensureVisible(status);
      await tester.pumpAndSettle();
      await tester.tap(status);
      await tester.pumpAndSettle();
    }
  }

  Future<void> openConfirmation(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('reclaim-primary-role'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the status panel opens account actions and cancelling recovery keeps the primary',
    (tester) async {
      await mount(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Sync & devices'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Primary device: Old phone'), findsOneWidget);
      await openConfirmation(tester);
      expect(find.text('Reclaim primary role?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(drive.primary!.deviceId, 'old');
      expect(drive.reclaims, 0);
    },
  );

  testWidgets('confirmation reclaims the role and restores the saved diary', (
    tester,
  ) async {
    final day = DiaryDayEntity(dateString: '2026-10-26')
      ..items = [
        DiaryItem(
          itemUuid: 'cloud',
          createdAt: fixture.now,
          updatedAt: fixture.now,
          content: 'Saved before reinstall',
        ),
      ];
    drive.seed('diary', day.dateString, day.toSyncJson('Old phone'));
    await mount(tester);
    await openConfirmation(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-reclaim-primary')));
    await tester.pumpAndSettle();
    expect(find.text('This device is primary'), findsOneWidget);
    expect(find.byKey(const ValueKey('reclaim-primary-role')), findsNothing);
    expect(find.byKey(const ValueKey('account-sync-now')), findsOneWidget);
    expect(
      scope
          .read(diaryRepositoryProvider)
          .getDay(day.dateString)!
          .items
          .single
          .content,
      'Saved before reinstall',
    );
    expect(
      find.text('This device is now primary. Your synced journal is restored.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed recovery shows its error and can be retried', (
    tester,
  ) async {
    drive.failReclaim = true;
    await mount(tester);
    await openConfirmation(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-reclaim-primary')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SyncAccountSheet),
        matching: find.textContaining('Primary recovery failed'),
      ),
      findsOneWidget,
    );
    expect(drive.primary!.deviceId, 'old');
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('reclaim-primary-role')),
          )
          .onPressed,
      isNotNull,
    );
    drive.failReclaim = false;
    await openConfirmation(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-reclaim-primary')));
    await tester.pumpAndSettle();
    expect(find.text('This device is primary'), findsOneWidget);
    expect(drive.reclaims, 2);
  });

  testWidgets('a signed-out installation must connect before reclaiming', (
    tester,
  ) async {
    fixture.backend.auth.user = null;
    await mount(tester, openSheet: false);
    expect(find.byKey(const ValueKey('reclaim-primary-role')), findsNothing);
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('sync-card-status')))
          .onTap,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('sync-card-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-card-action')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sync-card-status')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reclaim-primary-role')), findsOneWidget);
    expect(drive.reclaims, 0);
    expect(drive.primary!.deviceId, 'old');
  });

  testWidgets('logging out closes the sheet and keeps local and cloud data', (
    tester,
  ) async {
    fixture.notes.saveNote(
      uuid: 'keep',
      title: 'Local',
      content: 'Keep my journal',
    );
    await fixture.sync();
    final cloudCount = drive.documents.length;
    await mount(tester);
    final logout = find.byKey(const ValueKey('account-log-out'));
    await tester.ensureVisible(logout);
    await tester.pumpAndSettle();
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Connect Account'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('owner@example.test'), findsNothing);
    expect(scope.read(syncAccountProvider), isNull);
    expect(fixture.notes.getNoteByUuid('keep')!.content, 'Keep my journal');
    expect(drive.documents.length, cloudCount);
    expect(drive.primary!.deviceId, 'old');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync disables account actions until it finishes', (
    tester,
  ) async {
    final release = Completer<void>();
    network.wait = release.future;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('account-sync-now')));
    await tester.pump();
    expect(scope.read(syncEngineProvider).isSyncing, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('account-sync-now')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('reclaim-primary-role')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('account-log-out')))
          .enabled,
      isFalse,
    );
    release.complete();
    await tester.pumpAndSettle();
    expect(scope.read(syncEngineProvider).isSyncing, isFalse);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('account-log-out')))
          .enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recovery controls remain usable on narrow screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, scale: 1.8);
      await openConfirmation(tester);
      expect(
        find.byKey(const ValueKey('confirm-reclaim-primary')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
