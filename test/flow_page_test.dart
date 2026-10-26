import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/flow/controllers/thoughts_providers.dart';
import 'package:journal/components/transparent_video_player.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/flow/views/pages/flow_page.dart';
import 'package:journal/modules/flow/views/widgets/flow_opening.dart';
import 'package:journal/modules/flow/views/widgets/flow_thought_card.dart';
import 'package:journal/modules/root/views/widgets/bottom_navbar.dart';
import 'package:journal/modules/voice/voice.dart';

import 'support/memory_thoughts_repository.dart';

const _captureKey = ValueKey('flow-capture');
final _history = find.byKey(const PageStorageKey('flow-history'));
Finder _card(int id) => find.byKey(ValueKey('flow-thought-$id'));
ScrollController _scroll(WidgetTester tester) =>
    tester.widget<CustomScrollView>(_history).controller!;
FlowSceneLayout _layout(WidgetTester tester) =>
    (tester
                .widget<SliverPersistentHeader>(
                  find.byType(SliverPersistentHeader),
                )
                .delegate
            as FlowOpening)
        .layout;

Future<void> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  bool reduced = false,
  MemoryThoughtsRepository? repository,
}) async {
  final thoughts = repository ?? MemoryThoughtsRepository(sampleThoughts());
  addTearDown(thoughts.changes.close);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);
  final base = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [thoughtsRepositoryProvider.overrideWithValue(thoughts)],
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'FlowTest'),
            primaryTextTheme: base.primaryTextTheme.apply(
              fontFamily: 'FlowTest',
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            child: child!,
          ),
          home: const _Tabs(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/j.png'),
      tester.element(find.byType(FlowPage)),
    ),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('FLOW_CAPTURES')) return;
  final previous = debugDisableShadows;
  try {
    // Capture the actual Material shadows, then restore the test debug state.
    debugDisableShadows = false;
    for (final object in tester.allRenderObjects) {
      object.markNeedsPaint();
    }
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/journal-flow-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = previous;
    for (final object in tester.allRenderObjects) {
      object.markNeedsPaint();
    }
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await cupertino.load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      final loader = FontLoader('FlowTest')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
    }
  });

  for (final dark in [false, true]) {
    testWidgets('same-color clouds remain tappable, dark: $dark', (
      tester,
    ) async {
      final thoughts = sampleThoughts(6);
      for (var i = 0; i < thoughts.length; i++) {
        // Unique IDs with the same palette hash reproduce overlapping sand.
        thoughts[i].uuid = String.fromCharCode(48 + i * 6);
      }
      await _mount(
        tester,
        dark: dark,
        repository: MemoryThoughtsRepository(thoughts),
      );
      final scheme = Theme.of(tester.element(find.byType(FlowPage)))
          .colorScheme;
      expect(
        thoughts
            .map((thought) => flowThoughtColors(thought, scheme).background)
            .toSet(),
        hasLength(1),
      );
      await _capture(tester, dark ? 'same-color-dark' : 'same-color');
      await tester.tap(
        find.byKey(ValueKey('flow-thought-${thoughts[2].uuid}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, thoughts[2].content),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final count in [0, 1, 3, 4, 5, 6, 12, 20]) {
    testWidgets(
      '$count saved thoughts render without placeholders or duplicates',
      (tester) async {
        final repository = MemoryThoughtsRepository(sampleThoughts(count));
        await _mount(tester, repository: repository);
        expect(_layout(tester).previewCount, count < 6 ? count : 6);
        expect(find.text('SAMPLE THOUGHT'), findsNothing);
        if (count == 0) {
          expect(
            find.textContaining('Write your first thought below.'),
            findsOneWidget,
          );
          expect(find.byType(FlowThoughtCard), findsNothing);
        } else {
          expect(
            find.textContaining('Write your first thought below.'),
            findsNothing,
          );
          expect(_card(0), findsOneWidget);
          _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(_card(count - 1).hitTestable(), findsOneWidget);
          final ids = tester
              .widgetList<FlowThoughtCard>(find.byType(FlowThoughtCard))
              .map((card) => card.thought.uuid)
              .toList();
          expect(ids.toSet().length, ids.length);
        }
        expect(find.byType(TextField), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the first saved thought replaces the empty state', (
    tester,
  ) async {
    final repository = MemoryThoughtsRepository([]);
    await _mount(tester, repository: repository);
    await tester.enterText(
      find.byType(TextField),
      '  First thought\nSecond line  ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add thought'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Write your first thought below.'),
      findsNothing,
    );
    expect(repository.thoughts.single.summary, '');
    expect(repository.thoughts.single.content, 'First thought\nSecond line');
    expect(_card(0), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed saving retains the draft and Retry saves it once', (
    tester,
  ) async {
    final repository = MemoryThoughtsRepository([])..failSaves = true;
    await _mount(tester, repository: repository);
    const draft = '  A thought I must keep  ';
    await tester.enterText(find.byType(TextField), draft);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add thought'));
    await tester.pumpAndSettle();
    expect(repository.thoughts, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      draft,
    );
    expect(
      find.text('Couldn’t save your thought. Your draft is still here.'),
      findsOneWidget,
    );
    repository.failSaves = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.thoughts, hasLength(1));
    expect(repository.thoughts.single.content, 'A thought I must keep');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(_card(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading shows no sample cards and saved data appears when ready',
    (tester) async {
      final repository = MemoryThoughtsRepository(sampleThoughts(1))
        ..holdReads = true;
      await _mount(tester, repository: repository);
      expect(find.text('Loading your thoughts…'), findsOneWidget);
      expect(find.byType(FlowThoughtCard), findsNothing);
      repository.changes.add(repository.thoughts);
      await tester.pumpAndSettle();
      expect(find.text('Loading your thoughts…'), findsNothing);
      expect(_card(0), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read failure offers Retry and recovers saved thoughts', (
    tester,
  ) async {
    final repository = MemoryThoughtsRepository(sampleThoughts(1))
      ..failReads = true;
    await _mount(tester, repository: repository);
    expect(find.text('Couldn’t load your thoughts.'), findsOneWidget);
    expect(find.byType(FlowThoughtCard), findsNothing);
    repository.failReads = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load your thoughts.'), findsNothing);
    expect(_card(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening cards settle into the collection and input yields to history',
    (tester) async {
      await _mount(tester);
      final originalComposer = tester.getRect(find.byType(TextField));
      expect(find.byTooltip('Voice capture').hitTestable(), findsOneWidget);
      expect(_card(0), findsOneWidget);
      expect(_card(3), findsOneWidget);
      expect(_layout(tester).previewCount, 6);
      expect(_card(4).hitTestable(), findsOneWidget);
      expect(_card(5).hitTestable(), findsOneWidget);
      expect(tester.getSize(_card(5)).height, lessThanOrEqualTo(131));
      await _capture(tester, 'opening');

      // A small scroll leaves the input floating at exactly the same position.
      _scroll(tester).jumpTo(30);
      await tester.pump();
      expect(tester.getRect(find.byType(TextField)), originalComposer);

      _scroll(tester).jumpTo(_layout(tester).collapseExtent * .5);
      await tester.pump();
      await _capture(tester, 'transition');
      _scroll(tester).jumpTo(_layout(tester).collapseExtent);
      await tester.pump();
      expect(
        tester.getTopLeft(_card(0)).dx,
        closeTo(tester.getTopLeft(_card(2)).dx, .01),
      );
      expect(
        tester.getTopLeft(_card(1)).dx,
        closeTo(tester.getTopLeft(_card(3)).dx, .01),
      );
      expect(
        tester.getTopLeft(_card(1)).dx,
        greaterThan(tester.getTopLeft(_card(0)).dx),
      );
      expect(
        tester.getTopLeft(_card(4)).dx,
        closeTo(tester.getTopLeft(_card(0)).dx, .01),
      );
      expect(
        tester.getTopLeft(_card(5)).dx,
        closeTo(tester.getTopLeft(_card(1)).dx, .01),
      );
      await _capture(tester, 'collection');
      _scroll(tester).jumpTo(_layout(tester).collapseExtent + 80);
      await tester.pump();
      expect(find.byTooltip('Voice capture').hitTestable(), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .focusNode!
            .canRequestFocus,
        isFalse,
      );
      expect(
        tester
            .widget<TransparentVideoPlayer>(find.byType(TransparentVideoPlayer))
            .playing,
        isFalse,
      );
      expect(_card(0), findsOneWidget);

      _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(_card(11).hitTestable(), findsOneWidget);
      final ids = tester
          .widgetList<FlowThoughtCard>(find.byType(FlowThoughtCard))
          .map((card) => card.thought.id)
          .toList();
      expect(ids.toSet().length, ids.length);
      expect(find.byTooltip('Voice capture').hitTestable(), findsNothing);
      await _capture(tester, 'older');

      _scroll(tester).jumpTo(0);
      await tester.pump();
      expect(tester.getRect(find.byType(TextField)), originalComposer);
      expect(find.byTooltip('Voice capture').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'blank drafts cannot submit and new thoughts survive tab switches',
    (tester) async {
      await _mount(tester);
      expect(find.byTooltip('Add thought'), findsNothing);
      await tester.enterText(find.byType(TextField), '   \n  ');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add thought'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        '  A tiny idea worth keeping.  ',
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Voice capture'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Diary tab'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TransparentVideoPlayer>(
              find.byType(TransparentVideoPlayer, skipOffstage: false),
            )
            .playing,
        isFalse,
      );
      await tester.tap(find.bySemanticsLabel('Flow tab'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '  A tiny idea worth keeping.  ',
      );
      await tester.tap(find.byTooltip('Add thought'));
      await tester.pumpAndSettle();
      expect(_card(12), findsOneWidget);
      expect(find.text('A tiny idea worth keeping.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(_scroll(tester).offset, 0);
      await tester.tap(find.bySemanticsLabel('Diary tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Flow tab'));
      await tester.pumpAndSettle();
      expect(_card(12), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the round action animates between mic and send without shifting the pill',
    (tester) async {
      await _mount(tester);
      final inputWidth = tester.getSize(find.byType(TextField)).width;
      final action = tester.getRect(find.byTooltip('Voice capture'));
      expect(action.size, const Size(56, 56));

      await tester.enterText(find.byType(TextField), 'A tiny idea.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byTooltip('Voice capture'), findsNothing);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(tester.getRect(find.byTooltip('Add thought')), action);
      expect(tester.getSize(find.byType(TextField)).width, inputWidth);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      await _capture(tester, 'typing');

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Voice capture'), findsOneWidget);
      expect(find.byTooltip('Add thought'), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
      expect(tester.getSize(find.byType(TextField)).width, inputWidth);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cards reveal full text and voice clearly opens a preview', (
    tester,
  ) async {
    await _mount(tester);
    // The frontmost card is fully tappable even in the scattered arrangement.
    final text = tester.widget<FlowThoughtCard>(_card(3)).thought.content;
    await tester.tap(_card(3));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, text), findsOneWidget);
    expect(find.text('YOUR THOUGHT'), findsOneWidget);
    await _capture(tester, 'detail');
    Navigator.of(tester.element(find.byType(SelectableText))).pop();
    await tester.pumpAndSettle();
    final thoughtsBefore = tester
        .widgetList<FlowThoughtCard>(find.byType(FlowThoughtCard))
        .map((card) => card.thought.content)
        .toList();
    await tester.tap(find.byTooltip('Voice capture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<VoiceSessionPage>(find.byType(VoiceSessionPage)).mode,
      VoiceSessionMode.transcription,
    );
    expect(find.text('Preview · sample text'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    await _capture(tester, 'voice');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceSessionPage), findsNothing);
    expect(
      tester
          .widgetList<FlowThoughtCard>(find.byType(FlowThoughtCard))
          .map((card) => card.thought.content),
      thoughtsBefore,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('focused multiline input stays usable above the keyboard', (
    tester,
  ) async {
    await _mount(tester);
    await tester.enterText(
      find.byType(TextField),
      'One thought\nAnd another\nA little more\nOne last line',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final input = tester.getRect(find.byType(TextField));
    final button = tester.getRect(find.byTooltip('Add thought'));
    expect(input.top, greaterThanOrEqualTo(24));
    expect(button.bottom, lessThan(844 - 300));
    // Programmatic scrolling must not hide a focused draft either.
    _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add thought').hitTestable(), findsOneWidget);
    await _capture(tester, 'keyboard');
    await tester.tap(find.byTooltip('Add thought'));
    await tester.pumpAndSettle();
    expect(_card(12), findsOneWidget);
    expect(_scroll(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact large-text input keeps its send action above the keyboard',
    (tester) async {
      await _mount(tester, size: const Size(320, 568), scale: 2, reduced: true);
      await tester.enterText(
        find.byType(TextField),
        'A thought\nAnother line\nAnd more\nLast line',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add thought').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Add thought'));
      await tester.pumpAndSettle();
      expect(_card(12), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final config in [
    (
      name: 'narrow',
      size: const Size(320, 568),
      scale: 1.0,
      dark: false,
      reduced: false,
    ),
    (
      name: 'large-text',
      size: const Size(390, 844),
      scale: 2.0,
      dark: false,
      reduced: true,
    ),
    (
      name: 'tablet',
      size: const Size(1024, 1366),
      scale: 1.0,
      dark: false,
      reduced: false,
    ),
    (
      name: 'dark',
      size: const Size(390, 844),
      scale: 1.0,
      dark: true,
      reduced: false,
    ),
  ]) {
    testWidgets('${config.name} layout remains readable and scrollable', (
      tester,
    ) async {
      await _mount(
        tester,
        size: config.size,
        scale: config.scale,
        dark: config.dark,
        reduced: config.reduced,
      );
      expect(_layout(tester).width, lessThanOrEqualTo(760));
      expect(
        _layout(tester).columns,
        config.size.width < 350 || config.scale > 1.4 ? 1 : 2,
      );
      expect(
        _layout(tester).previewCount,
        config.size.width < 350 || config.scale > 1.4 ? 4 : 6,
      );
      if (config.reduced) {
        expect(
          tester
              .widget<TransparentVideoPlayer>(
                find.byType(TransparentVideoPlayer),
              )
              .playing,
          isFalse,
        );
      }
      await _capture(tester, config.name);
      _scroll(tester).jumpTo(_layout(tester).collapseExtent);
      await tester.pumpAndSettle();
      for (final card in find.byType(FlowThoughtCard).evaluate()) {
        final cardFinder = find.byWidget(card.widget);
        final cardRect = tester.getRect(cardFinder);
        final material = tester.widget<Material>(
          find.descendant(of: cardFinder, matching: find.byType(Material)),
        );
        final outline = material.shape!.getOuterPath(
          Offset.zero & cardRect.size,
        );
        for (final text
            in find
                .descendant(of: cardFinder, matching: find.byType(Text))
                .evaluate()) {
          final textRect = tester
              .getRect(find.byWidget(text.widget))
              .shift(-cardRect.topLeft);
          for (final corner in [
            textRect.topLeft,
            textRect.topRight,
            textRect.bottomLeft,
            textRect.bottomRight,
          ]) {
            expect(
              outline.contains(corner),
              isTrue,
              reason: '${config.name} text must stay inside the cloud edge',
            );
          }
        }
      }
      await _capture(tester, '${config.name}-collection');
      _scroll(tester).jumpTo(_scroll(tester).position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(_card(11).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs();
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  bool flow = true;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: flow ? 0 : 1,
      children: [
        TickerMode(enabled: flow, child: const FlowPage()),
        const Center(child: Text('Another page')),
      ],
    ),
    bottomNavigationBar: JournalBottomNavbar(
      selectedIndex: flow ? 2 : 0,
      onSelected: (index) => setState(() => flow = index == 2),
    ),
  );
}
