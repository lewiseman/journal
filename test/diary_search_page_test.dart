import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/controllers/diary_search_service.dart';

import 'support/sample_diaries.dart';

import 'package:journal/modules/diary/models/diary_search_result.dart';
import 'package:journal/modules/diary/views/pages/diary_search_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_opening.dart';
import 'package:journal/modules/settings/models/local_settings.dart';

final _today = DateTime(2026, 10, 26);
final _diaries = buildSampleDiaries(_today);
final _captureKey = GlobalKey();
final _input = find.byKey(const ValueKey('diary-search-input'));
final _firstMatch = find.byKey(const ValueKey('diary-search-match-0'));

class _ControlledSearch implements DiarySearchService {
  final queries = <String>[];
  final pending = <Completer<DiarySearchResult>>[];

  @override
  Future<DiarySearchResult> search(String query) {
    queries.add(query);
    final completer = Completer<DiarySearchResult>();
    pending.add(completer);
    return completer.future;
  }
}

DiarySearchResult _response(String answer) => DiarySearchResult(
  answer: answer,
  matches: [
    DiarySearchMatch(
      date: DateTime(2026, 10, 24, 15),
      title: 'Taking the long way',
      excerpt: 'I took a different route on my walk.',
    ),
  ],
);

Future<void> _mount(
  WidgetTester tester, {
  DiarySearchService? service,
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  bool reduced = false,
  bool accessible = false,
  AppAccent accent = AppAccent.indigo,
  List<DateTime?>? results,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);
  final themes = AppThemeConfig.themesFor(accent);
  final theme = dark ? themes.dark : themes.light;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'SearchTest'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
            accessibleNavigation: accessible,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final date = await Navigator.of(context).push<DateTime>(
                    MaterialPageRoute(
                      builder: (_) => DiarySearchPage(
                        lastDate: _today,
                        service:
                            service ??
                            LocalDiarySearchService(
                              lastDate: _today,
                              diaries: _diaries,
                            ),
                      ),
                    ),
                  );
                  results?.add(date);
                },
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(_input, query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

Future<void> _capture(
  WidgetTester tester,
  String name, {
  bool settle = true,
}) async {
  if (!const bool.fromEnvironment('SEARCH_CAPTURES')) return;
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/diary_top_bg.png'),
      tester.element(find.byType(DiarySearchPage)),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-search-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
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
      await (FontLoader('SearchTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets(
    'opens with a clean header, question cards, and no keyboard; Back cancels',
    (tester) async {
      final results = <DateTime?>[];
      await _mount(tester, results: results);
      expect(find.byType(DiarySearchOpening), findsOneWidget);
      expect(find.text('Find a moment.'), findsNothing);
      expect(find.text('Search journal'), findsNothing);
      expect(find.textContaining('A feeling, a person'), findsNothing);
      expect(
        find.byKey(const ValueKey('diary-search-prompt-5')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('diary-search-prompt-0')))
            .height,
        greaterThanOrEqualTo(72),
      );
      expect(find.text('Preview'), findsNothing);
      expect(find.text('Sample entries · last 30 days'), findsNothing);
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(results, [null]);
    },
  );

  for (var i = 0; i < diarySearchPrompts.length; i++) {
    testWidgets(
      'suggested query $i returns a grounded answer and opens its day',
      (tester) async {
        final results = <DateTime?>[];
        final response = await LocalDiarySearchService(
          lastDate: _today,
          diaries: _diaries,
        ).search(diarySearchPrompts[i]);
        await _mount(tester, results: results);
        final prompt = find.byKey(ValueKey('diary-search-prompt-$i'));
        await tester.ensureVisible(prompt);
        await tester.tap(prompt);
        await tester.pumpAndSettle();
        expect(find.text('What I found'), findsOneWidget);
        expect(find.text(response.answer), findsOneWidget);
        expect(
          tester.widget<TextField>(_input).controller!.text,
          diarySearchPrompts[i],
        );
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.ensureVisible(_firstMatch);
        await tester.tap(_firstMatch);
        await tester.pumpAndSettle();
        expect(results, [response.matches.first.date]);
      },
    );
  }

  testWidgets(
    'more ideas refreshes the questions and searches the chosen idea',
    (tester) async {
      await _mount(tester);
      final more = find.byKey(const ValueKey('diary-search-more-ideas'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('A different route on my walk'), findsOneWidget);
      expect(find.text('A familiar album on a busy day'), findsOneWidget);
      expect(find.text('An ordinary conversation'), findsOneWidget);
      expect(find.text('What I found'), findsNothing);
      await _capture(tester, 'more-ideas');
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text(diarySearchPrompts.first), findsOneWidget);
      await tester.tap(more);
      await tester.pumpAndSettle();
      final conversation = find.byKey(const ValueKey('diary-search-prompt-5'));
      await tester.ensureVisible(conversation);
      await tester.tap(conversation);
      await tester.pumpAndSettle();
      expect(find.text('What I found'), findsOneWidget);
      final response = await LocalDiarySearchService(
        lastDate: _today,
        diaries: _diaries,
      ).search('An ordinary conversation');
      expect(find.text(response.answer), findsOneWidget);
      expect(
        tester.widget<TextField>(_input).controller!.text,
        'An ordinary conversation',
      );
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'fast searches retain a visible loading phase; reduced=$reduced',
      (tester) async {
        await _mount(tester, reduced: reduced);
        await _submit(tester, 'walk');
        await tester.pump(const Duration(milliseconds: 450));
        expect(
          find.byKey(const ValueKey('diary-search-loading')),
          findsOneWidget,
        );
        expect(find.text('What I found'), findsNothing);
        if (reduced) expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('diary-search-loading')),
          findsNothing,
        );
        expect(find.text('What I found'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'slow retrieval keeps loading and finishes without another delay',
    (tester) async {
      final service = _ControlledSearch();
      await _mount(tester, service: service);
      await _submit(tester, 'walk');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(
        find.byKey(const ValueKey('diary-search-loading')),
        findsOneWidget,
      );
      service.pending.single.complete(_response('The search is ready.'));
      await tester.pump();
      expect(find.text('The search is ready.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary-search-loading')), findsNothing);
    },
  );

  testWidgets(
    'typed search submits by button, clear restores opening, blank is inert',
    (tester) async {
      final service = _ControlledSearch();
      await _mount(tester, service: service);
      await _submit(tester, '   ');
      expect(service.queries, isEmpty);
      await tester.enterText(_input, 'walk');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diary-search-submit')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.queries, ['walk']);
      expect(find.text('Looking through\nyour journal…'), findsOneWidget);
      service.pending.single.complete(_response('A walk in the garden.'));
      await tester.pumpAndSettle();
      expect(find.text('A walk in the garden.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byType(DiarySearchOpening), findsOneWidget);
      expect(tester.widget<TextField>(_input).controller!.text, isEmpty);
      expect(find.text('What I found'), findsNothing);
    },
  );

  testWidgets('unknown text offers prompts, and a failed search can retry', (
    tester,
  ) async {
    await _mount(tester);
    await _submit(tester, 'submarine zeppelin');
    await tester.pumpAndSettle();
    expect(find.text('No moments found yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('diary-search-prompt-0')), findsOneWidget);
    await _capture(tester, 'empty');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final service = _ControlledSearch();
    await _mount(tester, service: service);
    await _submit(tester, 'walk');
    service.pending.single.completeError(StateError('Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('The pages need a moment.'), findsOneWidget);
    await _capture(tester, 'error');
    await tester.tap(find.byKey(const ValueKey('diary-search-retry')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.queries, ['walk', 'walk']);
    service.pending.last.complete(_response('Recovered answer.'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered answer.'), findsOneWidget);
  });

  testWidgets(
    'newer queries, clearing, and disposal invalidate pending responses',
    (tester) async {
      final service = _ControlledSearch();
      await _mount(tester, service: service);
      await _submit(tester, 'first');
      await _submit(tester, 'second');
      service.pending[1].complete(_response('Newest answer.'));
      await tester.pumpAndSettle();
      service.pending[0].completeError(StateError('Stale failure'));
      await tester.pumpAndSettle();
      expect(find.text('Newest answer.'), findsOneWidget);
      expect(find.text('The pages need a moment.'), findsNothing);

      await _submit(tester, 'third');
      await tester.tap(find.byTooltip('Clear search'));
      service.pending[2].complete(_response('Cleared answer.'));
      await tester.pumpAndSettle();
      expect(find.byType(DiarySearchOpening), findsOneWidget);
      expect(find.text('Cleared answer.'), findsNothing);

      await _submit(tester, 'fourth');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      service.pending[3].complete(_response('Disposed answer.'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected dates normalize and accessible navigation removes motion',
    (tester) async {
      final results = <DateTime?>[];
      final service = _ControlledSearch();
      await _mount(
        tester,
        service: service,
        accessible: true,
        results: results,
      );
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );
      await _submit(tester, 'walk');
      service.pending.single.complete(_response('A memory.'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_firstMatch);
      await tester.tap(_firstMatch);
      await tester.pumpAndSettle();
      expect(results, [DateTime(2026, 10, 24)]);
    },
  );

  for (final config in [
    (
      name: 'light',
      size: const Size(390, 844),
      scale: 1.0,
      dark: false,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'dark',
      size: const Size(390, 844),
      scale: 1.0,
      dark: true,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'narrow',
      size: const Size(320, 640),
      scale: 1.0,
      dark: false,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'large-type',
      size: const Size(320, 640),
      scale: 2.0,
      dark: false,
      reduced: false,
      accent: AppAccent.indigo,
    ),
    (
      name: 'tablet',
      size: const Size(900, 1000),
      scale: 1.0,
      dark: false,
      reduced: false,
      accent: AppAccent.teal,
    ),
    (
      name: 'reduced',
      size: const Size(390, 844),
      scale: 1.0,
      dark: false,
      reduced: true,
      accent: AppAccent.indigo,
    ),
  ]) {
    testWidgets(
      '${config.name} opening, results, and keyboard fit without overflow',
      (tester) async {
        await _mount(
          tester,
          size: config.size,
          scale: config.scale,
          dark: config.dark,
          reduced: config.reduced,
          accent: config.accent,
        );
        await _capture(tester, '${config.name}-opening');
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('diary-search-prompt-5')),
          findsOneWidget,
        );
        await _submit(tester, 'That walk I wrote about');
        await tester.pump(const Duration(milliseconds: 380));
        await _capture(tester, '${config.name}-loading', settle: false);
        expect(
          find.byKey(const ValueKey('diary-search-loading')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        await _capture(tester, '${config.name}-results');
        expect(tester.takeException(), isNull);
        await tester.tap(_input);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        final input = tester.getRect(_input);
        expect(input.bottom, lessThanOrEqualTo(config.size.height - 280));
        expect(
          tester
              .getSize(find.byKey(const ValueKey('diary-search-scroll')))
              .height,
          greaterThan(64),
        );
        final button = tester.getSize(
          find.byKey(const ValueKey('diary-search-submit')),
        );
        expect(button.width, greaterThanOrEqualTo(48));
        expect(button.height, greaterThanOrEqualTo(48));
        await _capture(tester, '${config.name}-keyboard');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
