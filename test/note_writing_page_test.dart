import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:journal/config/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/transform/note_writing_voice.dart';
import 'package:journal/modules/notes/transform/transform_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import 'note_summary_test.dart' as summary;
import 'note_transform_test.dart' show writingContainer;
import 'support/sync_fixture.dart';

class _Voice implements NoteWritingVoice {
  final spoken = <String>[];
  Completer<void>? reading;
  int stops = 0;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    reading = Completer<void>();
    return reading!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (reading?.isCompleted == false) reading!.complete();
    reading = null;
  }
}

typedef _Harness = ({
  SyncFixture app,
  ProviderContainer scope,
  summary.SummaryTransport wire,
  _Voice voice,
});
const _original = 'First sentence. second sentense. Last sentence.';
const _replacement = 'First sentence. Second sentence. Last sentence.';
final _captureKey = GlobalKey();
final _scroll = find
    .descendant(
      of: find.byType(NoteTransformPage),
      matching: find.byType(Scrollable),
    )
    .first;

Future<_Harness> _mount(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = scale > 1
      ? const Size(320, 568)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final base = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  final app = (await tester.runAsync(
    () => SyncFixture.create(MemoryDrive(), 'phone'),
  ))!;
  app.notes.saveNote(uuid: 'chosen', title: 'A note', content: _original);
  final store = summary.MemorySummaries();
  final wire = summary.SummaryTransport(store)..output = _replacement;
  final scope = writingContainer(app, store, wire);
  final voice = _Voice();
  scope.read(noteSummaryProvider);
  await tester.runAsync(summary.settle);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'WritingTest'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        NoteTransformPage(noteId: 'chosen', voice: voice),
                  ),
                ),
                child: const Text('Open writing'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open writing'));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
    app.container.dispose();
  });
  return (app: app, scope: scope, wire: wire, voice: voice);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  final chips = find.ancestor(of: target, matching: find.byType(ChoiceChip));
  final control = chips.evaluate().isNotEmpty ? chips.first : target;
  if (control.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(control), alignment: .5);
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    control.hitTestable(),
    100,
    scrollable: _scroll,
  );
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _preview(WidgetTester tester) async {
  final start = find.byKey(const ValueKey('transform-start'));
  await tester.scrollUntilVisible(
    start.hitTestable(),
    100,
    scrollable: _scroll,
  );
  await tester.runAsync(() async {
    await tester.tap(start);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('QVAC_CAPTURES')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-writing-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    await (FontLoader('WritingTest')..addFont(
          Future.value(ByteData.sublistView(await font.readAsBytes())),
        ))
        .load();
  });
  testWidgets(
    'visual actions preview the whole note and only save after Use this',
    (tester) async {
      final h = await _mount(tester);
      await _capture(tester, 'choose');
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Choose part of the note'), findsNothing);
      await _tap(
        tester,
        find.byKey(const ValueKey('writing-action-clarify-note')),
      );
      await _preview(tester);
      await _capture(tester, 'preview');
      expect(h.wire.submitted.single['operation'], 'clarify-note');
      expect(jsonDecode(h.wire.submitted.single['prompt'] as String), {
        'text': _original,
        'intent': '',
      });
      expect(h.app.notes.getNoteByUuid('chosen')!.content, _original);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('transform-output')),
            )
            .data,
        _replacement,
      );
      await _tap(tester, find.text('Before'));
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('transform-original')),
            )
            .data,
        _original,
      );
      await _capture(tester, 'before');
      await _tap(tester, find.text('After'));
      final accept = find.byKey(const ValueKey('transform-accept'));
      await tester.scrollUntilVisible(
        accept.hitTestable(),
        100,
        scrollable: _scroll,
      );
      await tester.runAsync(() async {
        await tester.tap(accept);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(h.app.notes.getNoteByUuid('chosen')!.content, _replacement);
      expect(find.byType(NoteTransformPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tone presets supply the required intent without typing', (
    tester,
  ) async {
    final h = await _mount(tester);
    await _tap(tester, find.byKey(const ValueKey('writing-action-tone-note')));
    await _tap(tester, find.text('Simple'));
    await _capture(tester, 'tone');
    expect(find.byType(TextField), findsNothing);
    await _preview(tester);
    expect(h.wire.submitted.single['operation'], 'tone-note');
    final prompt = jsonDecode(
      h.wire.submitted.single['prompt'] as String,
    ) as Map<String, dynamic>;
    expect(prompt['text'], _original);
    expect(prompt['intent'], contains('simple, everyday words'));
    expect(h.app.notes.getNoteByUuid('chosen')!.content, _original);
  });

  testWidgets(
    'Listen reads choices and previews and stops when leaving the page',
    (tester) async {
      final h = await _mount(tester);
      await _tap(tester, find.byKey(const ValueKey('writing-listen-choices')));
      expect(h.voice.spoken.single, contains('Choose a picture'));
      expect(find.text('Stop'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('writing-listen-choices')));
      expect(h.voice.reading, isNull);
      await _preview(tester);
      await _tap(tester, find.byKey(const ValueKey('writing-listen-preview')));
      expect(h.voice.spoken.last, _replacement);
      final stops = h.voice.stops;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(h.voice.stops, greaterThan(stops));
      expect(h.voice.reading, isNull);
      expect(h.app.notes.getNoteByUuid('chosen')!.content, _original);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('tone controls remain usable on a small screen with large text', (
    tester,
  ) async {
    await _mount(tester, dark: true, scale: 2);
    await _tap(tester, find.byKey(const ValueKey('writing-action-tone-note')));
    await _tap(tester, find.text('Formal'));
    await _capture(tester, 'tone-large-dark');
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account reset stops an active reading', (tester) async {
    final h = await _mount(tester);
    await _tap(tester, find.byKey(const ValueKey('writing-listen-choices')));
    expect(h.voice.reading, isNotNull);
    (h.scope.read(accountResetProvider.notifier) as summary.TestReset).block();
    await tester.pumpAndSettle();
    expect(h.voice.reading, isNull);
    expect(tester.takeException(), isNull);
  });
}
