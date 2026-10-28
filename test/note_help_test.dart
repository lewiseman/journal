import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/metadata/note_help_contract.dart';
import 'package:journal/modules/notes/metadata/note_help_pages.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/notes/models/note_tag.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

String modelStatus = 'ready';

class HelpConnection extends summary.TestConnection {
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
          'status': modelStatus,
          'noteHelpContract': 1,
          'operations': [noteMetadataOperation, noteIdeasOperation],
        },
      ],
    },
  );
}

ProviderContainer helpContainer(
  SyncFixture app,
  SummaryStore store,
  summary.SummaryTransport wire, {
  SyncDeviceRole role = SyncDeviceRole.primary,
}) => ProviderContainer(
  overrides: [
    notesRepositoryProvider.overrideWithValue(app.notes),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(HelpConnection.new),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(role),
  ],
);

const suggestions = {
  'titles': ['Raised bed plan', 'Untitled Note', 'raised bed plan'],
  'tags': [
    {'name': 'Gardening', 'emoji': '🌱'},
    {'name': 'home', 'emoji': '🏡'},
    {'name': 'Ideas', 'emoji': '💡'},
    {'name': '#Spring', 'emoji': '🌿'},
    {'name': 'all', 'emoji': '🌿'},
    {'name': 'Depression', 'emoji': '💭'},
    {'name': 'Mental Health', 'emoji': '🧠'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => modelStatus = 'ready');

  test(
    'metadata requests send only title, body and tag names, never shortened',
    () {
      final note = NoteMetadataSource(
        noteId: 'n',
        title: 'Untitled Note',
        content: 'Tomato seedlings for the bed.',
        tags: ['🏡#Home'],
        version: '{}',
      );
      expect(jsonDecode(note.request()), {
        'title': '',
        'text': 'Tomato seedlings for the bed.',
        'tags': ['Home'],
      });
      expect(
        () => NoteMetadataSource(
          noteId: 'n',
          title: 'T',
          content: '  ',
          tags: const [],
          version: '{}',
        ).request(),
        throwsFormatException,
      );
      expect(
        () => NoteMetadataSource(
          noteId: 'n',
          title: 'T',
          content: '🦉' * 500,
          tags: const [],
          version: '{}',
        ).request(),
        throwsFormatException,
      );
    },
  );

  test('a few words are not enough to suggest from', () {
    expect(
      () => const NoteMetadataSource(
        noteId: 'n',
        title: '',
        content: 'ok then',
        tags: [],
        version: '{}',
      ).request(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('too short'),
        ),
      ),
    );
  });

  test('suggestions follow tag conventions: no repeats, duplicates or invalid names; reuse library spelling', () {
    final source = NoteMetadataSource(
      noteId: 'n',
      title: 'Untitled Note',
      content: 'x',
      tags: ['🏡#Home'],
      version: '{}',
    );
    final parsed = NoteMetadataSuggestions.parse(
      jsonEncode(suggestions),
      source,
      library: const [NoteTag(name: 'IDEAS', emoji: '🪣')],
    );
    expect(parsed.titles, ['Raised bed plan']);
    expect(parsed.tags.map((t) => t.encoded), [
      '🌱#Gardening',
      '🪣#IDEAS',
      '🌿#Spring',
    ]);
    for (final broken in [
      '{}',
      '{"titles":[],"tags":[],"x":1}',
      '{"titles":["a\\nb"],"tags":[]}',
      '{"titles":[],"tags":[{"name":"A","emoji":"🦄"}]}',
    ]) {
      expect(
        () => NoteMetadataSuggestions.parse(broken, source),
        throwsFormatException,
        reason: broken,
      );
    }
  });

  test('generic ideas send nothing personal; chosen notes send only the disclosed excerpt', () {
    expect(jsonDecode(const NoteIdeaSource().request()), {
      'topic': '',
      'notes': [],
    });
    final chosen = NoteIdeaContext.fromNote(
      NoteEntity(uuid: 'u', title: ' Garden ', content: 'a  b\n' * 200),
    );
    expect(chosen.excerpt.runes.length, noteIdeaExcerptChars);
    final request = jsonDecode(
      NoteIdeaSource(topic: ' spring ', notes: [chosen]).request(),
    );
    expect(request['topic'], 'spring');
    expect((request['notes'] as List).single.keys, ['id', 'title', 'excerpt']);
    expect(
      () => NoteIdeaSource(notes: List.filled(4, chosen)).request(),
      throwsFormatException,
    );
    expect(parseNoteIdeas('{"ideas":["A", "a", "B"]}'), ['A', 'B']);
    expect(() => parseNoteIdeas('{"ideas":[]}'), throwsFormatException);
  });

  test('chosen title and tags apply through the version check, keep manual tags, sync, and undo', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'Untitled Note',
      content: 'Bought tomato seedlings for the raised bed.',
      tags: ['🏡#Home'],
      attachmentPaths: [
        {'path': '/private/file', 'type': 'text/plain'},
      ],
    );
    app.notes.saveNote(uuid: 'other', title: 'Other', content: 'Private');
    await app.sync();
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)
      ..output = jsonEncode(suggestions);
    final container = helpContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteMetadata('chosen');
    expect(wire.submitted.single['operation'], noteMetadataOperation);
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'title': '',
      'text': 'Bought tomato seedlings for the raised bed.',
      'tags': ['Home'],
    });
    expect(store.value!.pendingText, null);
    final before = app.notes.getNoteByUuid('chosen')!;
    final beforeVersion = before.versionVectorJson;
    final result = controller.noteMetadataSuggestions()!;
    // Nothing is applied without an explicit choice.
    expect(await controller.acceptNoteMetadata(), false);
    expect(
      await controller.acceptNoteMetadata(
        title: result.titles.first,
        tags: [result.tags.first],
      ),
      true,
    );
    final after = app.notes.getNoteByUuid('chosen')!;
    expect(after.title, 'Raised bed plan');
    expect(after.tags, ['🏡#Home', '🌱#Gardening']);
    expect(after.content, before.content);
    expect(after.attachments, before.attachments);
    expect(after.versionVectorJson, isNot(beforeVersion));
    expect(after.status, SyncStatus.pendingUpload);
    expect(store.value, null);
    await app.sync();
    expect(drive.documents['note/chosen']!.payload['title'], 'Raised bed plan');
    expect(drive.documents['note/chosen']!.payload['tags'], [
      '🏡#Home',
      '🌱#Gardening',
    ]);
    // Undo restores exactly; a later edit blocks a stale undo.
    app.notes.updateNoteMetadata(
      uuid: 'chosen',
      expectedVersion: after.versionVectorJson,
      title: 'Untitled Note',
      tags: ['🏡#Home'],
    );
    expect(app.notes.getNoteByUuid('chosen')!.tags, ['🏡#Home']);
    expect(
      () => app.notes.updateNoteMetadata(
        uuid: 'chosen',
        expectedVersion: after.versionVectorJson,
        title: 'X',
        tags: const [],
      ),
      throwsStateError,
    );
    expect(
      () => app.notes.updateNoteMetadata(
        uuid: 'chosen',
        expectedVersion: app.notes.getNoteByUuid('chosen')!.versionVectorJson,
        title: 'X',
        tags: ['🏡#Home', '🏠#home'],
      ),
      throwsStateError,
    );
  });

  test('a manual edit during generation makes suggestions stale; rejection changes nothing', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'Mine',
      content: 'Seeds for the garden bed.',
    );
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)
      ..output = jsonEncode(suggestions)
      ..phase = 'running';
    final container = helpContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteMetadata('chosen');
    app.notes.saveNote(
      uuid: 'chosen',
      expectedVersionVectorJson: app.notes
          .getNoteByUuid('chosen')!
          .versionVectorJson,
      title: 'Manual title',
      content: 'Seeds for the garden bed.',
      tags: ['🌿#Manual'],
    );
    wire.phase = 'completed';
    await controller.retry();
    expect(container.read(noteSummaryProvider).stale, true);
    expect(
      await controller.acceptNoteMetadata(title: 'Raised bed plan'),
      false,
    );
    expect(app.notes.getNoteByUuid('chosen')!.title, 'Manual title');
    expect(app.notes.getNoteByUuid('chosen')!.tags, ['🌿#Manual']);
    await controller.clear();
    expect(store.value, null);
    expect(app.notes.getNoteByUuid('chosen')!.title, 'Manual title');
  });

  test('restart retrieves the same task; read-only, empty and unavailable models send nothing', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'T',
      content: 'Seeds for the garden bed.',
    );
    app.notes.saveNote(uuid: 'empty', title: 'Only a title', content: '');
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)
      ..output = jsonEncode(suggestions)
      ..phase = 'running';
    var container = helpContainer(app, store, wire);
    container.read(noteSummaryProvider);
    await summary.settle();
    await container
        .read(noteSummaryProvider.notifier)
        .startNoteMetadata('chosen');
    final id = store.value!.id;
    container.dispose();
    wire.phase = 'completed';
    container = helpContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    await summary.settle();
    expect(container.read(noteSummaryProvider).handle!.id, id);
    expect(container.read(noteSummaryProvider).phase, 'completed');
    expect(wire.posts, 1);
    final controller = container.read(noteSummaryProvider.notifier);
    expect(controller.noteMetadataSuggestions()!.titles, isNotEmpty);
    await controller.clear();

    await controller.startNoteMetadata('empty');
    expect(container.read(noteSummaryProvider).message, contains('note body'));
    await controller.clear();
    modelStatus = 'unloaded';
    container.invalidate(companionControllerProvider);
    await controller.startNoteMetadata('chosen');
    expect(
      container.read(noteSummaryProvider).message,
      contains('writing model'),
    );
    await controller.clear();
    expect(wire.posts, 1);

    final secondary = helpContainer(
      app,
      summary.MemorySummaries(),
      wire,
      role: SyncDeviceRole.secondary,
    );
    addTearDown(secondary.dispose);
    app.storage.setPrimary(
      const PrimaryDevice(
        deviceId: 'other-primary',
        deviceName: 'Desktop',
        fileId: 'primary',
      ),
    );
    secondary.read(noteSummaryProvider);
    await summary.settle();
    await secondary
        .read(noteSummaryProvider.notifier)
        .startNoteMetadata('chosen');
    expect(secondary.read(noteSummaryProvider).message, contains('read-only'));
    expect(wire.posts, 1);
    expect(
      () => app.notes.updateNoteMetadata(
        uuid: 'chosen',
        expectedVersion: app.notes.getNoteByUuid('chosen')!.versionVectorJson,
        title: 'X',
        tags: const [],
      ),
      throwsStateError,
    );
  });

  test('ideas work without history and on read-only devices', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)
      ..output = '{"ideas":["Three things to plant next."]}';
    final container = helpContainer(
      app,
      store,
      wire,
      role: SyncDeviceRole.secondary,
    );
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteIdeas(const NoteIdeaSource());
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'topic': '',
      'notes': [],
    });
    expect(controller.noteIdeas(), ['Three things to plant next.']);
    expect(store.value!.noteId, noteIdeasKey);
  });

  testWidgets(
    'empty note explains why; suggestions need an explicit choice before applying',
    (tester) async {
      final app = await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      );
      app!.notes.saveNote(uuid: 'empty', title: 'Title', content: '');
      app.notes.saveNote(
        uuid: 'chosen',
        title: 'Mine',
        content: 'Seeds for the garden bed.',
      );
      final store = summary.MemorySummaries();
      final wire = summary.SummaryTransport(store)
        ..output = jsonEncode(suggestions);
      final container = helpContainer(app, store, wire);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NoteMetadataPage(noteId: 'empty')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-metadata-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-metadata-start')), findsNothing);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NoteMetadataPage(noteId: 'chosen')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container
            .read(noteSummaryProvider.notifier)
            .startNoteMetadata('chosen'),
      );
      await tester.pumpAndSettle();
      FilledButton apply() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('note-metadata-apply')),
      );
      expect(apply().onPressed, isNull);
      await tester.tap(find.text('Gardening'));
      await tester.pumpAndSettle();
      expect(apply().onPressed, isNotNull);
      await tester.tap(find.text('Gardening'));
      await tester.pumpAndSettle();
      expect(apply().onPressed, isNull);
      expect(app.notes.getNoteByUuid('chosen')!.tags, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
