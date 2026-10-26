import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/views/pages/settings_page.dart';
import 'package:sync_wise/sync_wise.dart';

import 'support/sync_fixture.dart';

class _Network extends Fake implements NetworkService {
  @override
  Future<bool> isOnline() async => true;
}

void main() {
  late MemoryDrive drive;
  late SyncFixture fixture;
  late ProviderContainer scope;

  setUp(() async {
    drive = MemoryDrive()
      ..primary = const PrimaryDevice(
        deviceId: 'old',
        deviceName: 'Old phone',
        fileId: 'registry',
      );
    fixture = await SyncFixture.create(drive, 'reinstalled');
    await fixture.sync();
    scope = ProviderContainer.test(
      overrides: [
        accountResetStorageProvider.overrideWithValue(TestResetStorage()),
        objectBoxProvider.overrideWithValue(fixture.db),
        deviceIdentityProvider.overrideWithValue(fixture.device),
        networkServiceProvider.overrideWithValue(_Network()),
        syncBackendProvider.overrideWithValue(fixture.backend),
      ],
    );
  });

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openConfirmation(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('reclaim-primary-role'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Settings offers recovery and cancellation does not change the primary',
    (tester) async {
      await mount(tester);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('settings-sync-now')), findsOneWidget);
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
    expect(find.textContaining('Primary recovery failed'), findsOneWidget);
    expect(drive.primary!.deviceId, 'old');
    expect(
      tester
          .widget<FilledButton>(
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
    await mount(tester);
    expect(find.byKey(const ValueKey('reclaim-primary-role')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-connect-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reclaim-primary-role')), findsOneWidget);
    expect(drive.reclaims, 0);
    expect(drive.primary!.deviceId, 'old');
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
