import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/common.dart';
import 'package:journal/config/diary_typography.dart';

class _Preferences implements KeyValueStore {
  final data = <String, Object>{};
  @override
  Object? get(String key) => data[key];
  @override
  Future<void> put(String key, Object value) async => data[key] = value;
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
  setUp(() async {
    preferences.data.clear();
    await CacheStorage.instance.set(localSettingsKey, {
      'font_family': 'Poppins',
      'theme_mode': 'dark',
      'accent_color': 'walnut',
      'future_setting': 42,
    });
  });

  test('old and invalid settings get independent diary defaults', () {
    final old = LocalSettings.fromMap({'font_family': 'Roboto'});
    expect(old.fontFamily, 'Roboto');
    expect(old.diaryTitleFontFamily, 'Caveat');
    expect(old.diaryBodyFontFamily, 'Lora');
    final invalid = LocalSettings.fromMap({
      'diary_title_font_family': 'Missing font',
      'diary_body_font_family': 12,
    });
    expect(invalid.diaryTitleFontFamily, 'Caveat');
    expect(invalid.diaryBodyFontFamily, 'Lora');
    final chosen = old.copyWith(
      diaryTitleFontFamily: 'Bitter',
      diaryBodyFontFamily: 'Kalam',
    );
    expect(LocalSettings.fromMap(chosen.toMap()).toMap(), chosen.toMap());
  });

  test(
    'font selection waits for loading, persists, and preserves other settings',
    () async {
      final pending = Completer<TextStyle>();
      final container = ProviderContainer.test(
        overrides: [
          diaryFontLoaderProvider.overrideWithValue(
            (family, role) => pending.future,
          ),
        ],
      );
      final controller = container.read(settingsController.notifier);
      final selection = controller.setDiaryTitleFontFamily('Bitter');
      expect(container.read(settingsController).diaryTitleFontFamily, 'Caveat');
      pending.complete(const TextStyle(fontFamily: 'Bitter'));
      await selection;
      final settings = container.read(settingsController);
      expect(settings.diaryTitleFontFamily, 'Bitter');
      expect(settings.diaryBodyFontFamily, 'Lora');
      expect(settings.fontFamily, 'Poppins');
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.accent, AppAccent.walnut);
      expect(
        CacheStorage.instance.get(localSettingsKey)!['future_setting'],
        42,
      );
      final restarted = ProviderContainer.test();
      expect(restarted.read(settingsController).diaryTitleFontFamily, 'Bitter');
    },
  );

  test(
    'body selection is independent and failed loads keep the saved fonts',
    () async {
      final container = ProviderContainer.test(
        overrides: [
          diaryFontLoaderProvider.overrideWithValue((family, role) async {
            if (family == 'Bitter') throw StateError('offline');
            return TextStyle(fontFamily: family);
          }),
        ],
      );
      final controller = container.read(settingsController.notifier);
      await controller.setDiaryBodyFontFamily('Kalam');
      final before = CacheStorage.instance.get(localSettingsKey);
      await expectLater(
        controller.setDiaryBodyFontFamily('Bitter'),
        throwsStateError,
      );
      expect(container.read(settingsController).diaryBodyFontFamily, 'Kalam');
      expect(container.read(settingsController).diaryTitleFontFamily, 'Caveat');
      expect(CacheStorage.instance.get(localSettingsKey), before);
      await expectLater(
        controller.setDiaryTitleFontFamily('Missing font'),
        throwsArgumentError,
      );
    },
  );

  test('default typography resolves without a font download', () async {
    final container = ProviderContainer.test();
    final type = await container.read(diaryTypographyProvider.future);
    expect(type.title.fontFamily, 'Caveat');
    expect(type.body.fontFamily, 'Lora');
    expect(type.body.fontSize, 17);
    expect(type, const DiaryTypography());
    final load = container.read(diaryFontLoaderProvider);
    expect((await load('Lora', DiaryFontRole.title)).fontFamily, 'Lora');
    expect((await load('Caveat', DiaryFontRole.body)).fontFamily, 'Caveat');
  });

  test(
    'a slower previous font choice cannot overwrite a newer choice',
    () async {
      final first = Completer<TextStyle>();
      final second = Completer<TextStyle>();
      final container = ProviderContainer.test(
        overrides: [
          diaryFontLoaderProvider.overrideWithValue(
            (family, role) => family == 'Bitter' ? first.future : second.future,
          ),
        ],
      );
      final controller = container.read(settingsController.notifier);
      final previous = controller.setDiaryTitleFontFamily('Bitter');
      final latest = controller.setDiaryTitleFontFamily('Kalam');
      second.complete(const TextStyle(fontFamily: 'Kalam'));
      await latest;
      first.complete(const TextStyle(fontFamily: 'Bitter'));
      await previous;
      expect(container.read(settingsController).diaryTitleFontFamily, 'Kalam');
      expect(
        CacheStorage.instance.get(localSettingsKey)!['diary_title_font_family'],
        'Kalam',
      );
    },
  );

  testWidgets(
    'Appearance previews both fonts and reports failed selections inline',
    (tester) async {
      final container = ProviderContainer.test(
        overrides: [
          fontThemeLoaderProvider.overrideWithValue(
            (_) async => (
              light: AppThemeConfig.lightTheme,
              dark: AppThemeConfig.darkTheme,
            ),
          ),
          diaryFontLoaderProvider.overrideWithValue((family, role) async {
            if (family == 'Bitter') throw StateError('offline');
            return (role == DiaryFontRole.title
                    ? const DiaryTypography().title
                    : const DiaryTypography().body)
                .copyWith(fontFamily: family);
          }),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: ref.watch(appThemesProvider).light,
              home: const AppearancePage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary-appearance-preview')),
        findsOneWidget,
      );
      final title = find.text('Diary title font');
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bitter');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Bitter'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('font-load-error')), findsOneWidget);
      expect(container.read(settingsController).diaryTitleFontFamily, 'Caveat');
      await tester.enterText(find.byType(TextField), 'Lora');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Lora'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('font-load-error')), findsNothing);
      expect(container.read(settingsController).diaryTitleFontFamily, 'Lora');
      expect(container.read(settingsController).diaryBodyFontFamily, 'Lora');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Appearance and font picker fit a narrow screen at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer.test(
      overrides: [
        diaryFontLoaderProvider.overrideWithValue(
          (family, role) async => role == DiaryFontRole.title
              ? const DiaryTypography().title
              : const DiaryTypography().body,
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppThemeConfig.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const AppearancePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Diary body font'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diary body font'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Lora');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Lora'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Accent color'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
