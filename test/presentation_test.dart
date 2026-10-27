import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/presentation/presentation_body.dart';
import 'package:journal/modules/presentation/presentation_contract.dart';
import 'package:journal/modules/presentation/presentation_entity.dart';
import 'package:journal/modules/presentation/presentation_repository.dart';
import 'package:journal/modules/presentation/presentation_page.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

String template(
  int count, {
  String css = '.s0 {font-size:1.125em;line-height:1.6;margin-bottom:1em;}',
}) => jsonEncode({
  'html':
      '<article>${List.generate(count, (i) => '<section data-source="b$i" class="s0"></section>').join()}</article>',
  'css': css,
});

class PresentationConnection extends summary.TestConnection {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [summary.computer],
    selectedId: summary.computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'text',
          'status': 'ready',
          'operations': [presentationOperation],
          'presentationContract': 1,
        },
      ],
    },
  );
}

ProviderContainer presentationContainer(
  SyncFixture app,
  SummaryStore store,
  summary.SummaryTransport wire,
) => ProviderContainer(
  overrides: [
    objectBoxProvider.overrideWithValue(app.db),
    syncStateStoreProvider.overrideWithValue(app.storage),
    notesRepositoryProvider.overrideWithValue(app.notes),
    diaryRepositoryProvider.overrideWithValue(app.diary),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(PresentationConnection.new),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bounded compiler accepts source references, finite CSS and persisted typed documents', () async {
    final document = compilePresentation(template(2), 2);
    expect(document.blocks.length, 2);
    expect(document.blocks.first.values['font-size'], '1.125em');
    expect(
      (await compilePresentationBounded(template(2), 2)).encode(),
      document.encode(),
    );
    expect(
      SafePresentationDocument.decode(document.encode(), 2).encode(),
      document.encode(),
    );
    await expectLater(
      compilePresentationBounded(template(1), 1, timeout: Duration.zero),
      throwsA(isA<TimeoutException>()),
    );
  });
  test('adversarial markup and CSS never compile; no rewritten, omitted or reordered words', () {
    final valid = jsonDecode(template(2)) as Map<String, dynamic>;
    final html = valid['html'] as String;
    final hostileHtml = [
      '<script>alert(1)</script>$html',
      '<!doctype html>$html',
      '<!--hidden-->$html',
      html.replaceFirst('<article>', '<article onclick="evil()">'),
      html.replaceFirst('class="s0"', 'class="s0" style="display:none"'),
      html.replaceFirst('</section>', 'replacement</section>'),
      html.replaceFirst(
        '</section>',
        '<img src="https://example.invalid/leak"></section>',
      ),
      html.replaceFirst('</section>', '<svg onload="evil()"></svg></section>'),
      html.replaceFirst(
        '</section>',
        '<iframe src="file:///private"></iframe></section>',
      ),
      html.replaceFirst(
        '</section>',
        '<form action="https://example.invalid"><input></form></section>',
      ),
      html.replaceAll('b1', 'b0'),
      html.replaceAll('b0', 'b1'),
      html.replaceFirst('data-source="b0"', 'data-source="b1"'),
      html.replaceFirst(
        'data-source="b0"',
        'data-source="b0" data-source="b1"',
      ),
      '<article><section data-source="b0" class="s0"></section></article>',
      '<article>${'<div>' * 100}$html${'</div>' * 100}</article>',
      html.replaceFirst(
        '</section>',
        '<a href="javascript:evil()">click</a></section>',
      ),
    ];
    for (final attack in hostileHtml) {
      expect(
        () => compilePresentation(jsonEncode({...valid, 'html': attack}), 2),
        throwsA(anything),
        reason: attack,
      );
    }
    final hostileCss = [
      '@import "https://example.invalid";',
      '@font-face {src:url(file:///private);}',
      '.s0 {background:url(https://example.invalid)}',
      '.s0 {font-size:0}',
      '.s0 {color:transparent}',
      '.s0 {opacity:0}',
      '.s0 {display:none}',
      '.s0 {visibility:hidden}',
      '.s0 {position:fixed}',
      '.s0 {margin-bottom:-1em}',
      '.s0 {transform:scale(0)}',
      '.s0 {height:0;overflow:hidden}',
      '.s0 {font-size:calc(1em)}',
      '.s0 {font-size:var(--size)}',
      '.s0 {font-size:1em!important}',
      '.s0::before {content:"changed"}',
      '.s0,.s1 {font-size:1em}',
      '* {font-size:1em}',
      r'.\73 0 {font-size:1em}',
      r'.s0 {font-\73 ize:1em}',
      '.s0 {font-size:1em; font-size:1.25em}',
      '.s0 {font-size:1em} .s0 {font-size:1em}',
      '.s0 {font-size:1/**/em}',
      '.s0 {font-size:1e0em}',
      '.s0 {font-size:1em; broken}',
      '.s0 {font-size:1em; } trailing',
    ];
    for (final attack in hostileCss) {
      expect(
        () => compilePresentation(jsonEncode({...valid, 'css': attack}), 2),
        throwsA(anything),
        reason: attack,
      );
    }
    for (final attack in [
      '',
      '{}',
      '${template(1)}x',
      'x' * 4097,
      jsonEncode({...valid, 'script': 'evil'}),
    ]) {
      expect(() => compilePresentation(attack, 2), throwsA(anything));
    }
    expect(
      () => SafePresentationDocument.decode('{"policy":2,"blocks":[{}]}', 1),
      throwsFormatException,
    );
    expect(
      () => SafePresentationDocument.decode(
        '{"policy":1,"blocks":[{"display":"none"}]}',
        1,
      ),
      throwsFormatException,
    );
  });
  test(
    'source blocks preserve Markdown structure and bounded private context',
    () {
      final blocks = PresentationBlocks(
        '# Original\n\n- One\n- Two',
        markdown: true,
      );
      final input = jsonDecode(blocks.request('Comfortable')) as Map;
      expect(input.keys.toSet(), {'blocks', 'intent'});
      expect((input['blocks'] as List).length, 2);
      expect(input.toString(), isNot(contains('uuid')));
      expect(
        () => PresentationBlocks('a\n\n' * 17, markdown: false),
        throwsFormatException,
      );
      expect(
        () => PresentationBlocks('x' * 65537, markdown: true),
        throwsFormatException,
      );
      expect(
        () => PresentationBlocks('x' * 2000, markdown: false).request(''),
        throwsFormatException,
      );
    },
  );
  test('atomic local acceptance, stale source, role guard, revert, restart, reset and sync exclusion', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final repo = PresentationRepository(app.db, app.storage);
    final note = app.notes.saveNote(
      uuid: 'source',
      title: 'Private title',
      content: 'My words.',
    );
    final ref = PresentationSourceRef.note(note.uuid);
    final before = note.toSyncJson('phone');
    final source = repo.source(ref)!;
    repo.accept(
      taskId: 'task-one',
      snapshot: source,
      document: compilePresentation(template(1), 1),
    );
    expect(app.notes.getNoteByUuid(note.uuid)!.toSyncJson('phone'), before);
    expect(app.collections.map((c) => c.type), ['note', 'diary', 'thought']);
    expect(
      () => repo.accept(
        taskId: 'task-one',
        snapshot: source,
        document: compilePresentation(template(1), 1),
      ),
      throwsStateError,
    );
    final directory = app.db.store.directoryPath;
    app.db.close();
    final reopened = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: directory),
    );
    addTearDown(reopened.close);
    final reopenedSync = SyncStateStore(
      storage: JournalSyncKeyValueStore(reopened.store),
      deviceId: 'phone',
    );
    final reopenedRepo = PresentationRepository(reopened, reopenedSync);
    expect(reopenedRepo.get(ref.key)!.snapshot, source.encode());
    reopenedRepo.revert(ref);
    expect(reopenedRepo.get(ref.key)!.enabled, false);
    // Use the reopened box directly; old repositories deliberately held the closed store.
    final changed = reopened.noteBox.getAll().single..content = 'Later words.';
    reopened.noteBox.put(changed);
    expect(reopenedRepo.matches(source), false);
    expect(
      () => reopenedRepo.accept(
        taskId: 'task-two',
        snapshot: source,
        document: compilePresentation(template(1), 1),
      ),
      throwsStateError,
    );
    reopenedSync.setPrimary(
      const PrimaryDevice(
        deviceId: 'other',
        deviceName: 'Other',
        fileId: 'primary',
      ),
    );
    expect(
      () => reopenedRepo.accept(
        taskId: 'task-three',
        snapshot: reopenedRepo.source(ref)!,
        document: compilePresentation(template(1), 1),
      ),
      throwsStateError,
    );
    expect(() => reopenedRepo.revert(ref), throwsStateError);
    await JournalAccountResetData(
      db: reopened,
      supportDirectory: () async => app.directory,
      clearCachedImages: () async {},
    ).clear();
    expect(reopened.store.box<PresentationEntity>().count(), 0);
  });
  test(
    'diary revision belongs to an item; appending another item preserves it',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      final repo = PresentationRepository(app.db, app.storage);
      final item = app.diary.addTimelineItem(
        dateString: '2026-10-26',
        content: 'A moment.',
      );
      final ref = PresentationSourceRef.diary('2026-10-26', item.itemUuid);
      final source = repo.source(ref)!;
      app.diary.addTimelineItem(
        dateString: '2026-10-26',
        content: 'Another moment.',
      );
      expect(repo.matches(source), true);
      repo.accept(
        taskId: 'diary-task',
        snapshot: source,
        document: compilePresentation(template(1), 1),
      );
      app.diary.updateTimelineItem(
        dateString: '2026-10-26',
        itemUuid: item.itemUuid,
        content: 'New words.',
      );
      expect(repo.matches(source), false);
      app.diary.deleteTimelineItem(
        dateString: '2026-10-26',
        itemUuid: item.itemUuid,
      );
      expect(repo.source(ref), null);
    },
  );
  testWidgets(
    'offline renderer, theme, scaling, RTL, selection, semantics and renderer failure',
    (tester) async {
      final requests = <Uri>[];
      final client = HttpOverrides.current;
      HttpOverrides.global = _NoNetwork(requests);
      addTearDown(() => HttpOverrides.global = client);
      const source =
          '# Heading\n\nمرحبا **words** [link](https://example.invalid) ![alt](file:///private) <script>evil()</script>';
      final blocks = PresentationBlocks(source, markdown: true);
      for (final size in [const Size(320, 568), const Size(844, 390)]) {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(2),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: SafePresentationBody(
                        blocks: blocks,
                        document: compilePresentation(template(2), 2),
                        original: source,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), null);
          expect(find.byType(SelectableText), findsWidgets);
          expect(
            find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.headingLevel == 1,
            ),
            findsOneWidget,
          );
        }
      }
      // Colored note paper supplies its contrast ink independently of the app
      // brightness; accepted styling must inherit that resolved foreground.
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 16),
            child: SafePresentationBody(
              blocks: blocks,
              document: compilePresentation(template(2), 2),
              original: source,
            ),
          ),
        ),
      );
      bool whiteInk(InlineSpan span) =>
          span.style?.color == Colors.white ||
          (span is TextSpan && (span.children?.any(whiteInk) ?? false));
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .any((w) => w.textSpan != null && whiteInk(w.textSpan!)),
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SafePresentationBody(
            blocks: blocks,
            document: compilePresentation(template(2), 2),
            original: source,
            renderBlock: (_) => throw StateError('Injected renderer failure'),
          ),
        ),
      );
      expect(find.text(source), findsOneWidget);
      expect(requests, isEmpty);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'styled diary curl face and live prose stay aligned and react to local style replacement',
    (tester) async {
      final app = (await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      ))!;
      final item = app.diary.addTimelineItem(
        dateString: '2026-10-26',
        content: 'A quiet walk.\n\nAfternoon light.',
      );
      final source = PresentationSourceRef.diary('2026-10-26', item.itemUuid);
      final repo = PresentationRepository(app.db, app.storage);
      repo.accept(
        taskId: 'first-style',
        snapshot: repo.source(source)!,
        document: compilePresentation(template(2), 2),
      );
      final day = app.diary.getDay('2026-10-26')!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            objectBoxProvider.overrideWithValue(app.db),
            syncStateStoreProvider.overrideWithValue(app.storage),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DiaryPresentationScope(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 320,
                        height: 240,
                        child: DiarySheet(day: day),
                      ),
                      SizedBox(
                        width: 320,
                        child: DiaryDayContent(day: day, interactive: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bodies = find.byType(SafePresentationBody);
      expect(bodies, findsNWidgets(2));
      final before = tester.getSize(bodies.first).height;
      expect(tester.getSize(bodies.last).height, closeTo(before, 0.1));
      repo.accept(
        taskId: 'second-style',
        snapshot: repo.source(source)!,
        document: compilePresentation(
          template(
            2,
            css: '.s0 {font-size:1.25em;line-height:1.8;margin-bottom:1em;}',
          ),
          2,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      final after = tester.getSize(bodies.first).height;
      expect(after, greaterThan(before));
      expect(tester.getSize(bodies.last).height, closeTo(after, 0.1));
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'accepted reader reacts to live source changes, deletion and unsupported storage',
    (tester) async {
      final app = (await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      ))!;
      final source = PresentationSourceRef.note('live');
      app.notes.saveNote(
        uuid: source.id,
        title: '',
        content: 'Original words.',
      );
      final repo = PresentationRepository(app.db, app.storage);
      repo.accept(
        taskId: 'live-task',
        snapshot: repo.source(source)!,
        document: compilePresentation(template(1), 1),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            objectBoxProvider.overrideWithValue(app.db),
            syncStateStoreProvider.overrideWithValue(app.storage),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PresentationBody(
                source: source,
                content: 'Original words.',
                fallback: const Text('Original words.'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SafePresentationBody), findsOneWidget);
      app.notes.saveNote(
        uuid: source.id,
        title: '',
        content: 'Later manual words.',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SafePresentationBody), findsNothing);
      expect(find.text('Later manual words.'), findsOneWidget);
      final record = repo.get(source.key)!..policy = 999;
      repo.box.put(record);
      await tester.pumpAndSettle();
      expect(find.text('Later manual words.'), findsOneWidget);
      final note = app.db.noteBox.getAll().single..isDeleted = true;
      app.db.noteBox.put(note);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Source no longer available.'), findsOneWidget);
    },
  );
  testWidgets(
    'recoverable presentation task uses selected text only, accepts through UI, rejects hostile output',
    (tester) async {
      final app = (await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      ))!;
      final note = app.notes.saveNote(
        uuid: 'source',
        title: 'Private title',
        content: 'Words only.',
      );
      final store = summary.MemorySummaries();
      final wire = summary.SummaryTransport(store)..output = template(1);
      final container = presentationContainer(app, store, wire);
      addTearDown(container.dispose);
      final ref = PresentationSourceRef.note(note.uuid);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: PresentationPage(source: ref)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('presentation-generate')),
      );
      await tester.tap(find.byKey(const ValueKey('presentation-generate')));
      for (
        var i = 0;
        i < 40 && container.read(noteSummaryProvider).phase != 'completed';
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(container.read(noteSummaryProvider).phase, 'completed');
      final prompt = wire.submitted.single['prompt'] as String;
      expect(prompt, contains('Words only.'));
      expect(prompt, isNot(contains('Private title')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('presentation-accept')),
      );
      await tester.tap(find.byKey(const ValueKey('presentation-accept')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final repo = container.read(presentationRepositoryProvider);
      expect(repo.get(ref.key)!.enabled, true);
      expect(app.notes.getNoteByUuid(note.uuid)!.content, note.content);
      final controller = container.read(noteSummaryProvider.notifier);
      wire.output = jsonEncode({
        'html': '<script>bad</script>',
        'css': '.s0 {display:none}',
      });
      await tester.runAsync(() => controller.startPresentation(ref));
      expect(container.read(noteSummaryProvider).phase, 'failed');
      expect(repo.get(ref.key)!.enabled, true);
      await tester.runAsync(controller.clear);
      expect(app.notes.getNoteByUuid(note.uuid)!.content, note.content);
    },
  );
}

class _NoNetwork extends HttpOverrides {
  _NoNetwork(this.requests);
  final List<Uri> requests;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests.add(Uri.parse('https://blocked.invalid/client-created'));
    throw StateError('Unexpected network client');
  }
}
