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
import 'package:journal/modules/tasks/views/pages/tasks_page.dart';
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
  fixture.backend.auth.user = null;
  final scope = ProviderContainer.test(
    overrides: [
      objectBoxProvider.overrideWithValue(fixture.db),
      deviceIdentityProvider.overrideWithValue(fixture.device),
      syncBackendProvider.overrideWithValue(fixture.backend),
      accountResetStorageProvider.overrideWithValue(TestResetStorage()),
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

  testWidgets('More opens the Tasks UI without task editing controls', (
    tester,
  ) async {
    await _mount(tester);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Birthdays'), findsNothing);
    expect(find.text('Watchlist'), findsNothing);
    expect(find.text('Bucket list'), findsNothing);
    await _capture(tester, 'account');
    await _collapseAccount(tester);
    await _capture(tester, 'empty');
    await tester.tap(find.text('View all tasks'));
    await tester.pumpAndSettle();
    expect(find.byType(TasksPage), findsOneWidget);
    expect(find.text('Your tasks will live here.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Saved on this device'), findsNothing);
    await _capture(tester, 'tasks');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('0 to do'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
      await tester.ensureVisible(
        find.byKey(const ValueKey('more-people-preview')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _collapseAccount(tester);
      await tester.tap(find.text('Tasks').first);
      await tester.pumpAndSettle();
      expect(find.byType(TasksPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
