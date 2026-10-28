import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/account/views/widgets/sync_card.dart';
import 'package:journal/modules/more/views/pages/more_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/root/views/widgets/bottom_navbar.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:journal/modules/settings/views/pages/settings_page.dart';
import 'package:journal/utils/cache.dart';

import 'support/sync_fixture.dart';

class _Preferences implements KeyValueStore {
  final values = <String, Object>{};

  @override
  Object? get(String key) => values[key];
  @override
  bool containsKey(String key) => values.containsKey(key);
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<void> put(String key, Object value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> reload() async {}
}

class _CompanionConnection extends CompanionController {
  @override
  CompanionState build() => const CompanionState(phase: CompanionPhase.idle);
}

const _captureKey = ValueKey('more-capture');

ScrollController _moreScroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byKey(const PageStorageKey('more-scroll')))
    .controller!;

Future<void> _collapseAccount(WidgetTester tester) async {
  final header = tester.widget<SliverPersistentHeader>(
    find.byType(SliverPersistentHeader),
  );
  _moreScroll(tester)
      .jumpTo(header.delegate.maxExtent - header.delegate.minExtent);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool dark = false,
  double scale = 1,
  bool signedIn = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final fixture = (await tester.runAsync(
    () => SyncFixture.create(MemoryDrive(), 'phone'),
  ))!;
  if (signedIn) {
    await tester.runAsync(() => fixture.sync());
  } else {
    fixture.backend.auth.user = null;
  }
  final scope = ProviderContainer.test(
    overrides: [
      objectBoxProvider.overrideWithValue(fixture.db),
      deviceIdentityProvider.overrideWithValue(fixture.device),
      syncBackendProvider.overrideWithValue(fixture.backend),
      accountResetStorageProvider.overrideWithValue(TestResetStorage()),
      companionControllerProvider.overrideWith(_CompanionConnection.new),
    ],
  );
  final theme = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'MoreTest'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: const MorePage(),
            bottomNavigationBar: JournalBottomNavbar(
              selectedIndex: 3,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(MorePage));
    await Future.wait([
      for (final destination in ['diary', 'notes', 'flow', 'more'])
        for (final state in ['active', 'inactive'])
          precacheImage(
            AssetImage('assets/images/navigation/${destination}_$state.png'),
            context,
          ),
    ]);
  });
  await tester.pumpAndSettle();
  return scope;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('MORE_CAPTURES')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-more-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final preferences = _Preferences();
    await CacheStorage.init(store: preferences);
    await CacheStorage.instance.set(userNameKey, 'Lewis');
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('MoreTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets(
    'More opens Local AI computer directly and removes it from Settings',
    (tester) async {
      await _mount(tester);
      expect(find.byType(SyncAccountCard), findsOneWidget);
      expect(find.text('Make it yours'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Local AI computer'), findsOneWidget);
      expect(find.text('No computer connected'), findsOneWidget);
      expect(find.text('Tasks'), findsNothing);
      expect(find.text('People'), findsNothing);
      expect(find.text('View all tasks'), findsNothing);
      expect(find.text('COMING SOON'), findsNothing);
      await _capture(tester, 'account');
      await _collapseAccount(tester);
      await _capture(tester, 'settings');
      expect(find.text('Settings').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Local AI computer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local AI computer'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionPage), findsOneWidget);
      expect(find.text('Connect to your own computer'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Local AI computer'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the original sync card still collapses and expands at the top', (
    tester,
  ) async {
    await _mount(tester);
    expect(
      tester
          .widget<SyncAccountCard>(find.byType(SyncAccountCard))
          .collapseProgress,
      0,
    );
    await _collapseAccount(tester);
    expect(
      tester
          .widget<SyncAccountCard>(find.byType(SyncAccountCard))
          .collapseProgress,
      1,
    );
    await tester.tap(find.byType(SyncAccountCard));
    await tester.pumpAndSettle();
    expect(_moreScroll(tester).offset, 0);
    expect(
      tester
          .widget<SyncAccountCard>(find.byType(SyncAccountCard))
          .collapseProgress,
      0,
    );
    expect(find.text('Connect Account').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the signed-in More card opens account actions and updates on logout',
    (tester) async {
      final scope = await _mount(tester, signedIn: true);
      expect(find.byKey(const ValueKey('sync-card-action')), findsNothing);
      await _capture(tester, 'connected');
      await _collapseAccount(tester);
      await tester.tap(find.byType(SyncAccountCard));
      await tester.pumpAndSettle();
      expect(_moreScroll(tester).offset, 0);
      await tester.tap(find.byKey(const ValueKey('sync-card-status')));
      await tester.pumpAndSettle();
      await _capture(tester, 'sync-sheet');
      expect(find.text('This device is primary'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-log-out')));
      await tester.pumpAndSettle();
      expect(scope.read(syncAccountProvider), isNull);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Connect Account').hitTestable(), findsOneWidget);
      expect(find.text('On this device'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in [
    (name: 'narrow', size: const Size(320, 568), scale: 2.0, dark: false),
    (name: 'dark', size: const Size(390, 844), scale: 1.0, dark: true),
    (name: 'wide', size: const Size(900, 1000), scale: 1.0, dark: false),
  ]) {
    testWidgets('More fits ${layout.name} layout', (tester) async {
      await _mount(
        tester,
        size: layout.size,
        scale: layout.scale,
        dark: layout.dark,
      );
      await _collapseAccount(tester);
      await _capture(tester, layout.name);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Local AI computer'));
      await tester.pumpAndSettle();
      expect(find.text('Local AI computer').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('A quiet space for a busy mind.'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('connected More and account sheet fit ${layout.name} layout', (
      tester,
    ) async {
      await _mount(
        tester,
        size: layout.size,
        scale: layout.scale,
        dark: layout.dark,
        signedIn: true,
      );
      await _capture(tester, 'connected-${layout.name}');
      await tester.tap(find.byKey(const ValueKey('sync-card-status')));
      await tester.pumpAndSettle();
      await _capture(tester, 'sheet-${layout.name}');
      await tester.ensureVisible(find.byKey(const ValueKey('account-log-out')));
      await tester.pumpAndSettle();
      expect(find.text('Log out').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
