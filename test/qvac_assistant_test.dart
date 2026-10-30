import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/config/app_motion.dart';
import 'package:journal/modules/settings/controllers/settings_ctrl.dart';
import 'package:journal/modules/settings/models/local_settings.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/more/views/widgets/more_index_entry.dart';
import 'package:journal/modules/recall/recall_indexer.dart';
import 'package:journal/modules/root/views/widgets/bottom_navbar.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';

class _Connection extends CompanionController {
  @override
  CompanionState build() => const CompanionState(phase: CompanionPhase.idle);
  void phase(CompanionPhase value) => state = CompanionState(phase: value);
}

class _Recall extends RecallIndexer {
  @override
  RecallIndexState build() => const RecallIndexState(enabled: {});
}

class _MotionSettings extends SettingsNotifier {
  _MotionSettings(this.enabled);
  final bool enabled;

  @override
  LocalSettings build() => LocalSettings(animationsEnabled: enabled);

  void animations(bool value) =>
      state = state.copyWith(animationsEnabled: value);
}

final _button = find.byKey(const ValueKey('qvac-assistant-button'));
final _captureKey = GlobalKey();

Widget _withTools(String label, Widget child, {bool enabled = true}) => enabled
    ? QvacAssistantContent(
        label: label,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [Text('$label tools')],
        ),
        child: child,
      )
    : child;

class _Tabs extends StatefulWidget {
  const _Tabs({
    super.key,
    required this.onBuild,
    this.onboarding = false,
    this.moreTools = false,
  });
  final VoidCallback onBuild;
  final bool onboarding, moreTools;
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int page = 0;
  final scroll = ScrollController();
  void select(int value) => setState(() => page = value);
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return QvacAssistantPage(
      label: const ['Diary', 'Notes', 'Flow', 'More'][page],
      enabled: !widget.onboarding,
      root: true,
      dock: page == 3,
      child: Scaffold(
        body: IndexedStack(
          index: page,
          children: [
            for (final label in ['Diary', 'Notes', 'Flow'])
              _withTools(
                label,
                Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
              ),
            _withTools(
              'More',
              ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                children: [
                  const SizedBox(height: 180),
                  MoreIndexEntry(
                    title: 'Appearance',
                    description: 'Colors, theme and fonts',
                    artwork: MoreEntryArtwork.appearance,
                    onTap: () {},
                  ),
                  MoreIndexEntry(
                    title: 'Local QVAC',
                    status: 'No computer connected',
                    artwork: MoreEntryArtwork.qvac,
                    showDivider: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CompanionPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 800),
                ],
              ),
              enabled: widget.moreTools,
            ),
          ],
        ),
        bottomNavigationBar: JournalBottomNavbar(
          selectedIndex: page,
          onSelected: select,
        ),
      ),
    );
  }
}

Future<
  ({
    ProviderContainer scope,
    QvacAssistantController assistant,
    GlobalKey<NavigatorState> nav,
    GlobalKey<_TabsState> tabs,
    int Function() builds,
  })
>
_mount(
  WidgetTester tester, {
  bool dark = false,
  bool reduced = false,
  bool systemReduced = false,
  bool onboarding = false,
  bool moreTools = false,
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);
  final scope = ProviderContainer.test(
    overrides: [
      companionControllerProvider.overrideWith(_Connection.new),
      recallIndexerProvider.overrideWith(_Recall.new),
      settingsController.overrideWith(() => _MotionSettings(!reduced)),
    ],
  );
  final assistant = scope.read(qvacAssistantProvider);
  final nav = GlobalKey<NavigatorState>();
  final tabs = GlobalKey<_TabsState>();
  var builds = 0;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: (dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme)
              .copyWith(
                textTheme:
                    (dark
                            ? AppThemeConfig.darkTheme
                            : AppThemeConfig.lightTheme)
                        .textTheme
                        .apply(fontFamily: 'QvacTest'),
              ),
          navigatorKey: nav,
          navigatorObservers: [QvacAssistantObserver(assistant)],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: systemReduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: AppMotionScope(
              child: QvacAssistantHost(
                controller: assistant,
                navigatorKey: nav,
                child: child!,
              ),
            ),
          ),
          home: _Tabs(
            key: tabs,
            onboarding: onboarding,
            moreTools: moreTools,
            onBuild: () => builds++,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(const AssetImage(qvacArtwork), nav.currentContext!),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
  });
  return (
    scope: scope,
    assistant: assistant,
    nav: nav,
    tabs: tabs,
    builds: () => builds,
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('QVAC_CAPTURES')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-qvac-$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('QvacTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets('live connection badge, contextual sheet and modal exclusion', (
    tester,
  ) async {
    final app = await _mount(tester);
    expect(_button, findsOneWidget);
    expect(
      find.byKey(const ValueKey('qvac-status-disconnected')),
      findsOneWidget,
    );
    await _capture(tester, 'disconnected');
    final builds = app.builds();
    (app.scope.read(companionControllerProvider.notifier) as _Connection).phase(
      CompanionPhase.connected,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qvac-status-connected')), findsOneWidget);
    expect(app.builds(), builds);
    await _capture(tester, 'connected');
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.text('Diary tools'), findsOneWidget);
    expect(_button, findsNothing);
    await _capture(tester, 'sheet');
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    app.tabs.currentState!.select(1);
    await tester.pumpAndSettle();
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.text('Notes tools'), findsOneWidget);
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    (app.scope.read(companionControllerProvider.notifier) as _Connection).phase(
      CompanionPhase.connecting,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('qvac-status-connecting')),
      findsOneWidget,
    );
    await _capture(tester, 'connecting');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the overlay lets taps reach the app outside the button', (
    tester,
  ) async {
    final app = await _mount(tester);
    await tester.tap(find.text('Notes').last);
    await tester.pumpAndSettle();
    expect(app.tabs.currentState!.page, 1);
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(app.tabs.currentState!.page, 3);
    expect(_button, findsNothing);
    await tester.tap(find.text('Diary').last);
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
    expect(app.assistant.dismissed, false);
  });

  testWidgets(
    'long press opens the companion and hides the assistant on that route',
    (tester) async {
      final app = await _mount(tester);
      await tester.longPress(_button);
      await tester.pumpAndSettle();
      expect(find.byType(CompanionPage), findsOneWidget);
      expect(_button, findsNothing);
      app.nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_button, findsOneWidget);
      expect(find.byType(QvacAssistantSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sheet action opens the companion', (tester) async {
    await _mount(tester);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('qvac-local-ai-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(CompanionPage), findsOneWidget);
    expect(find.byType(QvacAssistantSheet), findsNothing);
    expect(_button, findsNothing);
  });

  testWidgets('settings sit above every page sheet and hide at full height', (
    tester,
  ) async {
    final app = await _mount(tester);
    final settings = find.byKey(const ValueKey('qvac-local-ai-settings'));
    final handle = find.byKey(const ValueKey('qvac-sheet-handle'));
    final surface = find.byKey(const ValueKey('qvac-sheet-surface'));
    for (var page = 0; page < 3; page++) {
      app.tabs.currentState!.select(page);
      await tester.pumpAndSettle();
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(settings, findsOneWidget);
      expect(
        tester.getBottomLeft(settings).dy,
        lessThan(tester.getTopLeft(surface).dy),
      );
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(settings, findsNothing);
      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      expect(sheet.controller!.size, closeTo(1, .001));
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(settings, findsOneWidget);
      app.nav.currentState!.pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding remains excluded, including its pushed dialogs', (
    tester,
  ) async {
    final app = await _mount(tester, onboarding: true);
    expect(_button, findsNothing);
    app.nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Terms')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_button, findsNothing);
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_button, findsNothing);
  });

  testWidgets('pages without tools hide the assistant and restore it on back', (
    tester,
  ) async {
    final app = await _mount(tester);
    app.nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Details')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_button, findsNothing);
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
    showDialog<void>(
      context: app.nav.currentState!.overlay!.context,
      builder: (_) => const AlertDialog(content: Text('A dialog')),
    );
    await tester.pumpAndSettle();
    expect(_button, findsNothing);
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
  });

  testWidgets('visibility follows tools being added and removed on a page', (
    tester,
  ) async {
    final app = await _mount(tester);
    var hasTools = false;
    late StateSetter updatePage;
    app.nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => QvacAssistantPage(
          label: 'Details',
          child: StatefulBuilder(
            builder: (_, setState) {
              updatePage = setState;
              return _withTools(
                'Details',
                const Scaffold(body: Text('Details')),
                enabled: hasTools,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_button, findsNothing);
    updatePage(() => hasTools = true);
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.text('Details tools'), findsOneWidget);
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    updatePage(() => hasTools = false);
    await tester.pumpAndSettle();
    expect(_button, findsNothing);
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
    expect(tester.binding.hasScheduledFrame, false);
  });

  testWidgets(
    'one image docks into a page with tools and lifts back to its floating position',
    (tester) async {
      final app = await _mount(tester, moreTools: true);
      final floating = tester.getRect(_button);
      app.tabs.currentState!.select(3);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final inFlight = tester.getRect(_button);
      expect(inFlight, isNot(floating));
      await tester.pumpAndSettle();
      final dock = tester.getRect(find.byType(QvacAssistantDock));
      expect(tester.getRect(_button), dock);
      final original = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(QvacAssistantDock),
          matching: find.byType(Opacity),
        ),
      );
      expect(original.opacity, 0);
      await _capture(tester, 'docked');
      app.tabs.currentState!.select(0);
      await tester.pumpAndSettle();
      expect(tester.getRect(_button), floating);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'docked image tracks scrolling and floats when its slot leaves the viewport',
    (tester) async {
      final app = await _mount(tester, moreTools: true);
      app.tabs.currentState!.select(3);
      await tester.pumpAndSettle();
      app.tabs.currentState!.scroll.jumpTo(50);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_button),
        tester.getRect(find.byType(QvacAssistantDock)),
      );
      app.tabs.currentState!.scroll.jumpTo(650);
      await tester.pumpAndSettle();
      expect(tester.getSize(_button).width, 68);
      app.tabs.currentState!.scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_button),
        tester.getRect(find.byType(QvacAssistantDock)),
      );
    },
  );

  testWidgets(
    'drag snaps to an edge without rebuilding the page or opening a sheet',
    (tester) async {
      final app = await _mount(tester);
      final builds = app.builds();
      await tester.drag(_button, const Offset(-240, -240));
      await tester.pumpAndSettle();
      expect(tester.getRect(_button).left, 14);
      expect(app.builds(), builds);
      expect(find.byType(QvacAssistantSheet), findsNothing);
      expect(app.assistant.dismissed, false);
      final gesture = await tester.startGesture(tester.getCenter(_button));
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      expect(find.byKey(const ValueKey('qvac-dismiss-target')), findsOneWidget);
      await _capture(tester, 'dragging');
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qvac-dismiss-target')), findsNothing);
    },
  );

  testWidgets(
    'dragging to the bottom dismisses for the session and restores More artwork',
    (tester) async {
      final app = await _mount(tester);
      final gesture = await tester.startGesture(tester.getCenter(_button));
      await gesture.moveBy(const Offset(-30, 30));
      await gesture.moveTo(const Offset(195, 785));
      await tester.pump();
      expect(find.text('Release to hide'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
      expect(app.assistant.dismissed, true);
      app.tabs.currentState!.select(3);
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
      final original = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(QvacAssistantDock),
          matching: find.byType(Opacity),
        ),
      );
      expect(original.opacity, 1);
      await tester.tap(find.text('Local QVAC'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionPage), findsOneWidget);
      app.nav.currentState!.pop();
      await tester.pumpAndSettle();
      app.tabs.currentState!.select(0);
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
    },
  );

  testWidgets('the docked assistant can be dragged out and closed', (
    tester,
  ) async {
    final app = await _mount(tester, moreTools: true);
    app.tabs.currentState!.select(3);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(_button));
    await gesture.moveBy(const Offset(-30, 30));
    await tester.pump();
    await gesture.moveTo(const Offset(195, 785));
    await tester.pump();
    expect(find.text('Release to hide'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(app.assistant.dismissed, true);
    expect(_button, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid tab changes retain the assistant and settle without idle frames',
    (tester) async {
      final app = await _mount(tester, moreTools: true);
      for (final page in [3, 0, 3, 1, 3, 2, 3]) {
        app.tabs.currentState!.select(page);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
      }
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_button),
        tester.getRect(find.byType(QvacAssistantDock)),
      );
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, false);
    },
  );

  testWidgets('saved motion mode settles the assistant and restores movement', (
    tester,
  ) async {
    final app = await _mount(tester, systemReduced: true, moreTools: true);
    final settings =
        app.scope.read(settingsController.notifier) as _MotionSettings;
    final controller = app.scope.read(qvacAssistantProvider);
    app.tabs.currentState!.select(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    settings.animations(false);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_button),
      tester.getRect(find.byType(QvacAssistantDock)),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    settings.animations(true);
    app.tabs.currentState!.select(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpAndSettle();
    expect(app.scope.read(qvacAssistantProvider), same(controller));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a sheet mid-flight pauses and then resumes docking', (
    tester,
  ) async {
    final app = await _mount(tester, moreTools: true);
    app.tabs.currentState!.select(3);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.byType(QvacAssistantSheet), findsOneWidget);
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_button),
      tester.getRect(find.byType(QvacAssistantDock)),
    );
    expect(tester.binding.hasScheduledFrame, false);
  });

  for (final layout in [
    (
      name: 'dark',
      dark: true,
      reduced: false,
      size: const Size(390, 844),
      scale: 1.0,
    ),
    (
      name: 'large-text',
      dark: false,
      reduced: false,
      size: const Size(320, 568),
      scale: 2.0,
    ),
    (
      name: 'reduced',
      dark: false,
      reduced: true,
      size: const Size(900, 650),
      scale: 1.0,
    ),
  ]) {
    testWidgets('fits ${layout.name}, keyboard and rotation', (tester) async {
      final app = await _mount(
        tester,
        dark: layout.dark,
        reduced: layout.reduced,
        size: layout.size,
        scale: layout.scale,
      );
      app.tabs.currentState!.select(1);
      await tester.pumpAndSettle();
      expect(_button, findsOneWidget);
      await _capture(tester, layout.name);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(find.text('Notes tools'), findsOneWidget);
      expect(tester.takeException(), isNull);
      app.nav.currentState!.pop();
      await tester.pumpAndSettle();
      app.tabs.currentState!.select(0);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_button).bottom,
        lessThan(layout.size.height - 250),
      );
      tester.view.physicalSize = Size(layout.size.height, layout.size.width);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_button).right,
        lessThanOrEqualTo(layout.size.height),
      );
      expect(
        tester.getRect(_button).bottom,
        lessThanOrEqualTo(layout.size.width - 24),
      );
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, false);
    });
  }
}
