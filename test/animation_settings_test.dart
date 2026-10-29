import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/common.dart';
import 'package:journal/config/app_motion.dart';
import 'package:journal/modules/notes/views/widgets/notes_top_artwork.dart';
import 'package:journal/modules/notes/views/widgets/edit_note_card_bg.dart';
import 'package:journal/modules/notes/views/widgets/edit_note_page_bg.dart';
import 'package:journal/modules/root/views/widgets/bottom_navbar.dart';

class _Preferences implements KeyValueStore {
  final data = <String, Object>{};
  bool fail = false;
  Completer<void>? pending;

  @override
  Object? get(String key) => data[key];
  @override
  Future<void> put(String key, Object value) async {
    await pending?.future;
    if (fail) throw StateError('Storage unavailable');
    data[key] = value;
  }

  @override
  bool containsKey(String key) => data.containsKey(key);
  @override
  Set<String> getKeys() => data.keys.toSet();
  @override
  Future<void> remove(String key) async => data.remove(key);
  @override
  Future<void> reload() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final preferences = _Preferences();
  setUpAll(() => CacheStorage.init(store: preferences));
  setUp(() {
    preferences.data.clear();
    preferences.fail = false;
    preferences.pending = null;
  });

  Future<void> mount(
    WidgetTester tester,
    ProviderContainer container,
    Widget home, {
    bool systemReduced = false,
    bool accessible = false,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppThemeConfig.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: systemReduced,
              accessibleNavigation: accessible,
              textScaler: TextScaler.linear(scale),
              viewInsets: const EdgeInsets.only(bottom: 17),
            ),
            child: AppMotionScope(child: child!),
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  test('animations default on for new, old and invalid settings', () {
    expect(const LocalSettings().animationsEnabled, isTrue);
    for (final map in <Map<String, dynamic>?>[
      null,
      {},
      {'theme_mode': 'dark'},
      {'animations_enabled': null},
      {'animations_enabled': 'false'},
      {'animations_enabled': 0},
    ]) {
      expect(LocalSettings.fromMap(map).animationsEnabled, isTrue);
    }
    final off = const LocalSettings().copyWith(animationsEnabled: false);
    expect(LocalSettings.fromMap(off.toMap()).animationsEnabled, isFalse);
    expect(off.copyWith(accent: AppAccent.teal).animationsEnabled, isFalse);
  });

  test(
    'saving motion persists and preserves appearance and unknown keys',
    () async {
      await CacheStorage.instance.set(localSettingsKey, {
        'font_family': 'Roboto',
        'diary_title_font_family': 'Lora',
        'diary_body_font_family': 'Caveat',
        'theme_mode': 'dark',
        'accent_color': 'walnut',
        'future_setting': 42,
      });
      final container = ProviderContainer.test();
      final before = container.read(settingsController);
      await container
          .read(settingsController.notifier)
          .setAnimationsEnabled(false);
      expect(container.read(settingsController).toMap(), {
        ...before.toMap(),
        'animations_enabled': false,
      });
      expect(
        CacheStorage.instance.get(localSettingsKey)!['future_setting'],
        42,
      );
      final restarted = ProviderContainer.test();
      expect(restarted.read(settingsController).animationsEnabled, isFalse);
      await restarted
          .read(settingsController.notifier)
          .setAnimationsEnabled(true);
      expect(
        CacheStorage.instance.get(localSettingsKey)!['animations_enabled'],
        true,
      );
    },
  );

  for (final enabled in [false, true]) {
    for (final systemReduced in [false, true]) {
      testWidgets(
        'app motion overrides system: enabled=$enabled, system=$systemReduced',
        (tester) async {
          await CacheStorage.instance.set(localSettingsKey, {
            'animations_enabled': enabled,
          });
          final container = ProviderContainer.test();
          MediaQueryData? media;
          await mount(
            tester,
            container,
            Builder(
              builder: (context) {
                media = MediaQuery.of(context);
                return const SizedBox();
              },
            ),
            systemReduced: systemReduced,
            accessible: true,
            scale: 1.6,
          );
          expect(media!.disableAnimations, !enabled);
          expect(media!.accessibleNavigation, isTrue);
          expect(media!.textScaler.scale(10), 16);
          expect(media!.viewInsets.bottom, 17);
          await container
              .read(settingsController.notifier)
              .setAnimationsEnabled(!enabled);
          await tester.pump();
          expect(media!.disableAnimations, enabled);
        },
      );
    }
  }

  testWidgets('motion preference reaches pushed routes and dialog overlays', (
    tester,
  ) async {
    final container = ProviderContainer.test();
    late BuildContext homeContext;
    await mount(
      tester,
      container,
      Builder(
        builder: (context) {
          homeContext = context;
          return const Scaffold();
        },
      ),
      systemReduced: true,
    );
    MediaQueryData? routeMedia, dialogMedia;
    final navigator = Navigator.of(homeContext);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) {
            routeMedia = MediaQuery.of(context);
            return const Scaffold();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(routeMedia!.disableAnimations, isFalse);
    unawaited(
      showDialog<void>(
        context: homeContext,
        builder: (context) {
          dialogMedia = MediaQuery.of(context);
          return const AlertDialog(content: Text('Motion check'));
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(dialogMedia!.disableAnimations, isFalse);
    await container
        .read(settingsController.notifier)
        .setAnimationsEnabled(false);
    await tester.pumpAndSettle();
    expect(routeMedia!.disableAnimations, isTrue);
    expect(dialogMedia!.disableAnimations, isTrue);
    navigator.pop();
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced routes appear immediately and retain the back gesture', (
    tester,
  ) async {
    final container = ProviderContainer.test();
    await container
        .read(settingsController.notifier)
        .setAnimationsEnabled(false);
    late BuildContext homeContext;
    await mount(
      tester,
      container,
      Builder(
        builder: (context) {
          homeContext = context;
          return const Scaffold(body: Text('Home'));
        },
      ),
    );
    final navigator = Navigator.of(homeContext);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Details'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(find.text('Details')).dx, 400);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(1, 300), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('disabling an active note unfold completes the edit action', (
    tester,
  ) async {
    final container = ProviderContainer.test();
    final preview = ValueNotifier(true);
    addTearDown(preview.dispose);
    var edits = 0;
    double expansion = 0;
    await mount(
      tester,
      container,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: preview,
          builder: (context, value, _) => EditNoteCardBg(
            color: Colors.white,
            isPreviewMode: value,
            onExpansionChanged: (value) => expansion = value,
            onEdit: () {
              edits++;
              preview.value = false;
            },
            children: const [SliverToBoxAdapter(child: Text('A saved note'))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(edits, 0);
    await container
        .read(settingsController.notifier)
        .setAnimationsEnabled(false);
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(expansion, 1);
    expect(preview.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced note painting shows its finished readable paper', (
    tester,
  ) async {
    final container = ProviderContainer.test();
    await container
        .read(settingsController.notifier)
        .setAnimationsEnabled(false);
    late Animation<double> opacity;
    await mount(
      tester,
      container,
      Scaffold(
        body: EditNotepageBg(
          builder: (context, paperOpacity, _) {
            opacity = paperOpacity;
            return const Text('Readable note');
          },
        ),
      ),
    );
    expect(opacity.status, AnimationStatus.completed);
    expect(opacity.value, .78);
    expect(find.text('Readable note'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Appearance saves, reports failure and retries at large text sizes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer.test();
      await mount(tester, container, const AppearancePage(), scale: 2);
      final toggle = find.byKey(const ValueKey('animations-toggle'));
      await tester.scrollUntilVisible(
        toggle,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      preferences.fail = true;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('animations-save-error')),
        findsOneWidget,
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(container.read(settingsController).animationsEnabled, isTrue);
      expect(CacheStorage.instance.get(localSettingsKey), isNull);
      preferences.fail = false;
      final pending = preferences.pending = Completer<void>();
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(container.read(settingsController).animationsEnabled, isTrue);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(find.byKey(const ValueKey('animations-save-error')), findsNothing);
      expect(
        CacheStorage.instance.get(localSettingsKey)!['animations_enabled'],
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained artwork stops and resumes without replacing its state',
    (tester) async {
      final container = ProviderContainer.test();
      final first = GlobalKey(), second = GlobalKey();
      await mount(
        tester,
        container,
        Scaffold(
          body: IndexedStack(
            children: [
              NotesTopArtwork(key: first),
              TickerMode(enabled: false, child: NotesTopArtwork(key: second)),
            ],
          ),
        ),
        systemReduced: true,
      );
      final firstState = first.currentState, secondState = second.currentState;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await container
          .read(settingsController.notifier)
          .setAnimationsEnabled(false);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await container
          .read(settingsController.notifier)
          .setAnimationsEnabled(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(first.currentState, same(firstState));
      expect(second.currentState, same(secondState));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('navigation artwork settles when animations are switched off', (
    tester,
  ) async {
    final container = ProviderContainer.test();
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await mount(
      tester,
      container,
      Scaffold(
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, _) => JournalBottomNavbar(
            selectedIndex: value,
            onSelected: (index) => selected.value = index,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    selected.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await container
        .read(settingsController.notifier)
        .setAnimationsEnabled(false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    selected.value = 2;
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
