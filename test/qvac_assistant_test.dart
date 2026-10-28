import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
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

final _button = find.byKey(const ValueKey('qvac-assistant-button'));
final _captureKey = GlobalKey();

class _Tabs extends StatefulWidget {
  const _Tabs({super.key, required this.onBuild, this.onboarding = false});
  final VoidCallback onBuild;
  final bool onboarding;
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
              Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
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
  bool onboarding = false,
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
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: QvacAssistantHost(
              controller: assistant,
              navigatorKey: nav,
              child: child!,
            ),
          ),
          home: _Tabs(
            key: tabs,
            onboarding: onboarding,
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
    expect(find.text('A little help with Diary'), findsOneWidget);
    expect(_button, findsNothing);
    await _capture(tester, 'sheet');
    app.nav.currentState!.pop();
    await tester.pumpAndSettle();
    app.tabs.currentState!.select(1);
    await tester.pumpAndSettle();
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.text('A little help with Notes'), findsOneWidget);
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
    expect(
      tester.getRect(_button),
      tester.getRect(find.byType(QvacAssistantDock)),
    );
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
    await tester.tap(find.text('Open AI companion'));
    await tester.pumpAndSettle();
    expect(find.byType(CompanionPage), findsOneWidget);
    expect(find.byType(QvacAssistantSheet), findsNothing);
    expect(_button, findsNothing);
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

  testWidgets('floats above pushed pages and yields to dialogs', (
    tester,
  ) async {
    final app = await _mount(tester);
    app.nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Details')),
      ),
    );
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

  testWidgets(
    'one image docks into More and lifts back to its floating position',
    (tester) async {
      final app = await _mount(tester);
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
      final app = await _mount(tester);
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
    final app = await _mount(tester);
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
      final app = await _mount(tester);
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

  testWidgets('opening a sheet mid-flight pauses and then resumes docking', (
    tester,
  ) async {
    final app = await _mount(tester);
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
      app.tabs.currentState!.select(3);
      await tester.pumpAndSettle();
      expect(_button, findsOneWidget);
      await _capture(tester, layout.name);
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('qvac-page-placeholder')),
        findsOneWidget,
      );
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
