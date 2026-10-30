import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/presentation/note_presentation_page.dart';
import 'package:journal/modules/presentation/website_contract.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart'
    show MemorySummaries, SummaryTransport, TestReset, computer, settle;
import 'support/sync_fixture.dart';

const _page =
    '<!doctype html><html><head><style>body{font-family:system-ui}</style></head>'
    '<body><h1>Garden plan</h1><p>Tomatoes in the raised bed.</p></body></html>';

String _design(String body) => jsonEncode({
  'theme': 'garden',
  'accent': 'forest',
  'hero': {'heading': 'Garden plan', 'tagline': ''},
  'sections': [
    {'kind': 'text', 'heading': '', 'body': body, 'items': [], 'photo': -1},
  ],
});

/// A companion that makes themed websites.
class _WebsiteConnection extends CompanionController {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [computer],
    selectedId: computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'text',
          'status': 'ready',
          'websiteDesignContract': noteWebsiteDesignContract,
          'websiteModel': 'Llama 3.1 · 8B Instruct',
          'operations': [noteWebsiteDesignOperation, 'markdown-note'],
        },
      ],
    },
  );
}

/// An outdated companion that only made freehand websites.
class _FreehandConnection extends CompanionController {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [computer],
    selectedId: computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'text',
          'status': 'ready',
          'websiteContract': 1,
          'operations': [noteWebsiteOperation],
        },
      ],
    },
  );
}

ProviderContainer _container(
  SyncFixture app,
  MemorySummaries store,
  SummaryTransport wire, {
  bool outdated = false,
}) => ProviderContainer(
  overrides: [
    notesRepositoryProvider.overrideWithValue(app.notes),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(
      outdated ? _FreehandConnection.new : _WebsiteConnection.new,
    ),
    accountResetProvider.overrideWith(TestReset.new),
  ],
);

Future<void> _until(ProviderContainer scope, String phase) async {
  for (var i = 0; i < 100; i++) {
    if (scope.read(noteSummaryProvider).phase == phase &&
        !scope.read(noteSummaryProvider).busy) {
      return;
    }
    await settle();
  }
  fail('Never reached $phase: ${scope.read(noteSummaryProvider).message}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sanitizeWebsite', () {
    test('keeps the page and adds a strict content policy', () {
      final html = sanitizeWebsite(_page);
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('Garden plan'));
      expect(html, contains("default-src 'none'"));
      expect(html, contains('name="viewport"'));
    });

    test('strips scripts, handlers, frames, forms and remote resources', () {
      final html = sanitizeWebsite(
        '```html\n<html><head><link rel="stylesheet" href="https://x.test/a.css">'
        '<meta http-equiv="refresh" content="0;url=https://x.test">'
        '<style>@import "x.css"; body{background:url(https://x.test/b.png)}</style></head>'
        '<body onload="go()"><script>alert(1)</script><h1 onclick="x()">Hi</h1>'
        '<a href="https://x.test">out</a><a href="#top">top</a>'
        '<img src="https://x.test/p.png"><img src="data:image/png;base64,AAAA">'
        '<iframe src="https://x.test"></iframe><form action="https://x.test"></form>'
        '<p style="background:url(//x.test/c.png)">Body</p></body></html>\n```',
      );
      for (final banned in [
        '<script',
        'onload',
        'onclick',
        '<iframe',
        '<form',
        '<link',
        'refresh',
        'https://',
        '//x.test',
        '@import',
      ]) {
        expect(html, isNot(contains(banned)), reason: banned);
      }
      expect(html, contains('href="#top"'));
      expect(html, contains('data:image/png'));
      expect(html, contains('Body'));
    });

    test('refuses empty, oversized and control-character pages', () {
      for (final raw in [
        '',
        '<html><body>   </body></html>',
        '<html><body>${'x' * 17000}</body></html>',
        '<html><body>a\x00b</body></html>',
      ]) {
        expect(() => sanitizeWebsite(raw), throwsFormatException);
      }
    });

    test(
      'requests send only the title, text and description, within limits',
      () {
        const request = WebsiteRequest(
          noteId: 'n',
          version: '{}',
          title: 'Garden',
          content: 'Tomatoes',
          description: '  A calm   page ',
        );
        expect(jsonDecode(request.request()), {
          'title': 'Garden',
          'text': 'Tomatoes',
          'description': 'A calm page',
        });
        expect(
          WebsiteRequest.decode(request.encode()).contentHash,
          websiteContentHash('Tomatoes'),
        );
        for (final bad in [
          const WebsiteRequest(
            noteId: 'n',
            version: '{}',
            title: '',
            content: 'x',
            description: '',
          ),
          WebsiteRequest(
            noteId: 'n',
            version: '{}',
            title: '',
            content: 'x' * 2000,
            description: 'page',
          ),
        ]) {
          expect(bad.request, throwsFormatException);
        }
      },
    );
  });

  test('notes sync their presentation and parse older payloads', () {
    final note = NoteEntity(
      uuid: 'n',
      presentationMode: 'html',
      website: _page,
      websiteSourceHash: 'a' * 64,
    );
    final copy = NoteEntity.fromSyncJson(note.toSyncJson('phone'));
    expect(copy.presentationMode, 'html');
    expect(copy.website, _page);
    expect(copy.websiteSourceHash, 'a' * 64);
    final old = note.toSyncJson('phone')
      ..remove('presentation_mode')
      ..remove('website')
      ..remove('website_source_hash');
    final parsed = NoteEntity.fromSyncJson(old);
    expect([parsed.presentationMode, parsed.website], ['', '']);
  });

  test('the repository keeps the text, checks the version and syncs', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final note = app.notes.saveNote(uuid: 'n', title: 'T', content: 'Body');
    final version = note.versionVectorJson;
    final hash = websiteContentHash('Body');
    final saved = app.notes.setWebsite(
      uuid: 'n',
      expectedVersion: version,
      html: _page,
      sourceHash: hash,
    );
    expect(saved.content, 'Body');
    expect(saved.website, _page);
    expect(saved.presentationMode, 'html');
    expect(saved.status, SyncStatus.pendingUpload);
    expect(saved.versionVectorJson, isNot(version));
    expect(
      () => app.notes.setWebsite(
        uuid: 'n',
        expectedVersion: version,
        html: _page,
        sourceHash: hash,
      ),
      throwsStateError,
    );
    // Editing the text keeps the website.
    app.notes.saveNote(uuid: 'n', title: 'T', content: 'Body, edited');
    expect(app.notes.getNoteByUuid('n')!.website, _page);
    final markdown = app.notes.setPresentationMode('n', 'markdown');
    expect([markdown.website, markdown.presentationMode], ['', 'markdown']);
    app.notes.setWebsite(
      uuid: 'n',
      expectedVersion: markdown.versionVectorJson,
      html: _page,
      sourceHash: hash,
    );
    final cleared = app.notes.clearWebsite('n');
    expect([cleared.website, cleared.presentationMode], ['', '']);
    app.storage.setPrimary(
      const PrimaryDevice(deviceId: 'other', deviceName: 'Other', fileId: 'p'),
    );
    expect(() => app.notes.clearWebsite('n'), throwsStateError);
    app.container.dispose();
  });

  test('a website is generated, sanitized and saved beside the text', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(
      uuid: 'site-note',
      title: 'Garden plan',
      content: 'Tomatoes in the raised bed.',
    );
    final store = MemorySummaries();
    final wire = SummaryTransport(
      store,
    )..output = _design('<script>steal()</script> Tomatoes in the raised bed.');
    final scope = _container(app, store, wire);
    addTearDown(scope.dispose);
    final controller = scope.read(noteSummaryProvider.notifier);
    await controller.restore();
    await controller.startNoteWebsite('site-note', 'A calm green page');
    await _until(scope, 'completed');
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'title': 'Garden plan',
      'text': 'Tomatoes in the raised bed.',
      'description': 'A calm green page',
      'theme': 'auto',
      'photos': 0,
    });
    // The note's markup is text: escaped in the page, inert inside the
    // spec's meta attribute, and never an element.
    final preview = (await controller.noteWebsitePreview())!;
    expect(html.parse(preview).querySelectorAll('script'), isEmpty);
    expect(preview, contains('&lt;script&gt;steal()'));
    expect(await controller.acceptNoteWebsite(), isTrue);
    final note = app.notes.getNoteByUuid('site-note')!;
    expect(note.content, 'Tomatoes in the raised bed.');
    expect(note.presentationMode, 'html');
    expect(note.website, contains('Garden plan'));
    expect(html.parse(note.website).querySelectorAll('script'), isEmpty);
    expect(note.website, contains('class="t-garden a-forest"'));
    expect(note.websiteSourceHash, websiteContentHash(note.content));
    app.container.dispose();
  });

  test('a themed website is drawn here and keeps its spec', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(
      uuid: 'site-note',
      title: 'Garden plan',
      content: 'Tomatoes in the raised bed.',
    );
    final store = MemorySummaries();
    final wire = SummaryTransport(store)
      ..output = jsonEncode({
        'theme': 'zine',
        'accent': 'sun',
        'hero': {'heading': 'Tomatoes', 'tagline': ''},
        'sections': [
          {
            'kind': 'text',
            'heading': '',
            'body': 'Tomatoes in the raised bed.',
            'items': [],
            'photo': -1,
          },
        ],
      });
    final scope = _container(app, store, wire);
    addTearDown(scope.dispose);
    final controller = scope.read(noteSummaryProvider.notifier);
    await controller.restore();
    await controller.startNoteWebsite('site-note', 'Loud', theme: 'zine');
    await _until(scope, 'completed');
    expect(wire.submitted.single['operation'], noteWebsiteDesignOperation);
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'title': 'Garden plan',
      'text': 'Tomatoes in the raised bed.',
      'description': 'Loud',
      'theme': 'zine',
      'photos': 0,
    });
    expect(await controller.acceptNoteWebsite(), isTrue);
    final note = app.notes.getNoteByUuid('site-note')!;
    expect(note.website, contains('class="t-zine a-sun"'));
    expect(note.website, contains('name="journal-website"'));
    app.container.dispose();
  });

  test('an outdated computer is asked to update, not used', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'old', title: 'T', content: 'Body');
    final store = MemorySummaries();
    final wire = SummaryTransport(store)..output = _page;
    final scope = _container(app, store, wire, outdated: true);
    addTearDown(scope.dispose);
    final controller = scope.read(noteSummaryProvider.notifier);
    await controller.restore();
    await controller.startNoteWebsite('old', 'Calm');
    await settle();
    expect(wire.submitted, isEmpty);
    expect(
      scope.read(noteSummaryProvider).message,
      contains('Update the companion to make websites.'),
    );
    app.container.dispose();
  });

  test('a website made from older text cannot be saved', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'changed', title: 'T', content: 'Before');
    final store = MemorySummaries();
    final wire = SummaryTransport(store)..output = _design('Before');
    final scope = _container(app, store, wire);
    addTearDown(scope.dispose);
    final controller = scope.read(noteSummaryProvider.notifier);
    await controller.restore();
    await controller.startNoteWebsite('changed', 'Simple');
    await _until(scope, 'completed');
    app.notes.saveNote(uuid: 'changed', title: 'T', content: 'After');
    await settle();
    expect(await controller.acceptNoteWebsite(), isFalse);
    expect(app.notes.getNoteByUuid('changed')!.website, '');
    app.container.dispose();
  });

  testWidgets('the page offers the chosen mode and flags a stale website', (
    tester,
  ) async {
    final app = (await tester.runAsync(
      () => SyncFixture.create(MemoryDrive(), 'phone'),
    ))!;
    final note = app.notes.saveNote(uuid: 'n', title: 'T', content: 'Body');
    app.notes.setWebsite(
      uuid: 'n',
      expectedVersion: note.versionVectorJson,
      html: _page,
      sourceHash: websiteContentHash('Body'),
    );
    final scope = ProviderContainer.test(
      overrides: [
        objectBoxProvider.overrideWithValue(app.db),
        syncStateStoreProvider.overrideWithValue(app.storage),
        notesRepositoryProvider.overrideWithValue(app.notes),
        summaryStoreProvider.overrideWithValue(MemorySummaries()),
        companionControllerProvider.overrideWith(_WebsiteConnection.new),
        accountResetProvider.overrideWith(TestReset.new),
        syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const MaterialApp(home: NotePresentationPage(noteId: 'n')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('This note has a website'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-website-stale')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('note-website-model')),
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('note-presentation')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.text('Built on your computer with Llama 3.1 · 8B Instruct.'),
      findsOneWidget,
    );
    app.notes.saveNote(uuid: 'n', title: 'T', content: 'Body, edited');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('note-website-stale')).hitTestable(),
      -180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('note-presentation')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const ValueKey('note-website-stale')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-website-remove')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(app.notes.getNoteByUuid('n')!.website, '');
    expect(find.text('This note has a website'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Markdown').hitTestable(),
      -180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('note-presentation')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-markdown-start')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    app.container.dispose();
  });

  testWidgets('a website note is previewed on its own page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.unknown),
        ],
        child: MaterialApp(
          home: EditNotePage(
            existingNote: NoteEntity(
              uuid: 'site',
              title: 'Garden title',
              content: 'Tomatoes',
              website: _page,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-website-view')), findsOneWidget);
    // The bar names the note and flags text edited after the site was made.
    expect(find.text('Garden title'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('note-website-page-stale')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Edit note'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-website-view')), findsNothing);
    expect(find.text('Garden title'), findsOneWidget);

    await tester.tap(find.byTooltip('Close editor'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-website-view')), findsOneWidget);
    expect(find.byTooltip('Edit note'), findsOneWidget);
  });
}
