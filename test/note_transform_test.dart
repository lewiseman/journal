import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/notes/summary/summary_task_entity.dart';
import 'package:journal/modules/notes/transform/note_recovery_entity.dart';
import 'package:journal/modules/notes/transform/transform_contract.dart';
import 'package:journal/modules/notes/transform/transform_page.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

class WritingConnection extends summary.TestConnection {
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
          'operations': transformOperations.keys.toList(),
        },
      ],
    },
  );
}

ProviderContainer writingContainer(
  SyncFixture app,
  SummaryStore store,
  summary.SummaryTransport wire,
) => ProviderContainer(
  overrides: [
    notesRepositoryProvider.overrideWithValue(app.notes),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(WritingConnection.new),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('selected passage only, atomic acceptance preserves metadata, version, sync and recovery', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final note = app.notes.saveNote(
      uuid: 'chosen',
      title: 'Private title',
      content: 'Before. i go friday. After.',
      tags: ['🪣#Ideas'],
      attachmentPaths: [
        {'path': '/private/file', 'type': 'text/plain'},
      ],
    );
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)..output = 'I go Friday.';
    final container = writingContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start(
      'chosen',
      operation: 'clarify-note',
      start: 8,
      end: 20,
      intent: 'Keep my voice',
    );
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'text': 'i go friday.',
      'intent': 'Keep my voice',
    });
    expect(store.value!.pendingText, null);
    expect(
      TransformSource.decode(store.value!.localSource!).selected,
      'i go friday.',
    );
    expect(app.notes.getNoteByUuid('chosen')!.content, note.content);
    final originalVersion = note.versionVectorJson;
    expect(await controller.acceptTransformation(), true);
    final changed = app.notes.getNoteByUuid('chosen')!;
    expect(changed.content, 'Before. I go Friday. After.');
    expect(changed.title, note.title);
    expect(changed.tags, note.tags);
    expect(changed.attachments, note.attachments);
    expect(changed.versionVectorJson, isNot(originalVersion));
    expect(changed.status, SyncStatus.pendingUpload);
    expect(
      app.notes.transformationHistory('chosen').single.beforeContent,
      note.content,
    );
    final receipt = app.notes.transformationHistory('chosen').single;
    app.notes.restoreTransformation(receipt.id);
    expect(app.notes.getNoteByUuid('chosen')!.content, note.content);
    expect(app.notes.transformationHistory('chosen').single.restored, true);
    expect(() => app.notes.restoreTransformation(receipt.id), throwsStateError);
    expect(app.collections.map((c) => c.type), ['note', 'diary', 'thought']);
  });
  test('reject is read-only; stale source during generation and before form submission never overwrites or exports changed scope', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'Original.');
    final store = summary.MemorySummaries();
    // The transport checks that persistence precedes submission.
    final transport = summary.SummaryTransport(store)..output = 'Proposed.';
    final container = writingContainer(app, store, transport);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start('chosen', operation: 'rewrite-note');
    await controller.clear();
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Original.');
    expect(app.notes.transformationHistory('chosen'), isEmpty);
    transport.phase = 'running';
    await controller.start('chosen', operation: 'expand-note');
    app.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'Manual edit.');
    transport.phase = 'completed';
    await controller.retry();
    expect(container.read(noteSummaryProvider).stale, true);
    expect(await controller.acceptTransformation(), false);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Manual edit.');
    await controller.clear();
    final posts = transport.posts;
    await controller.start(
      'chosen',
      operation: 'rewrite-note',
      expectedContent: 'Original.',
    );
    expect(transport.posts, posts);
    expect(container.read(noteSummaryProvider).message, contains('Reopen'));
  });
  test('read-only role can review but repository rejects accept and restore, including a role change after generation', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'Original.');
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)..output = 'Proposed.';
    final container = writingContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start('chosen', operation: 'rewrite-note');
    app.storage.setPrimary(
      const PrimaryDevice(
        deviceId: 'other',
        deviceName: 'Other',
        fileId: 'primary',
      ),
    );
    expect(await controller.acceptTransformation(), false);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Original.');
    expect(app.notes.transformationHistory('chosen'), isEmpty);
  });
  test('malformed output and exhausted input do not write; retrieval after provider restart reuses original identity and protected source', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'Original.');
    final protected = summary.MemorySummaries();
    final store = ObjectBoxSummaryStore(app.db.store, protected: protected);
    final wire = summary.SummaryTransport(protected)..lostAck = true;
    var container = writingContainer(app, store, wire);
    container.read(noteSummaryProvider);
    await summary.settle();
    await container
        .read(noteSummaryProvider.notifier)
        .start('chosen', operation: 'markdown-note');
    final id = protected.value!.id;
    final raw = app.db.store.box<SummaryTaskEntity>().getAll().single.metadata;
    expect(raw, isNot(contains('Original.')));
    expect(raw, isNot(contains('localSource')));
    container.dispose();
    wire.output = '- Original.';
    container = writingContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    expect(container.read(noteSummaryProvider).handle!.id, id);
    expect(container.read(noteSummaryProvider).handle!.localSource, isNotNull);
    expect(wire.posts, 1);
    final controller = container.read(noteSummaryProvider.notifier);
    expect(await controller.acceptTransformation(), true);
    await controller.start('chosen', operation: 'rewrite-note');
    wire.output = '<script>bad</script>';
    await controller.retry();
    expect(container.read(noteSummaryProvider).phase, 'failed');
    expect(container.read(noteSummaryProvider).text, null);
    expect(await controller.acceptTransformation(), false);
    await controller.clear();
    await controller.start('chosen', operation: 'tone-note', intent: '');
    expect(container.read(noteSummaryProvider).handle, null);
    await controller.clear();
    await controller.start(
      'chosen',
      operation: 'rewrite-note',
      intent: '🦉' * 61,
    );
    expect(container.read(noteSummaryProvider).handle, null);
    await JournalAccountResetData(
      db: app.db,
      supportDirectory: () async => app.directory,
      clearCachedImages: () async {},
      clearSummaries: store.clearAll,
    ).clear();
    expect(app.db.store.box<NoteRecoveryEntity>().count(), 0);
    expect(protected.value, null);
  });
  test('acceptance recovery survives actual ObjectBox close/reopen; stale undo preserves a later manual edit', () async {
    final dir = await Directory.systemTemp.createTemp('journal-n01-');
    ObjectBox open() => ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: '${dir.path}/db'),
    );
    var db = open();
    NotesRepository repository() => NotesRepository(
      db: db,
      device: TestDevice('phone'),
      sync: SyncStateStore(
        storage: JournalSyncKeyValueStore(db.store),
        deviceId: 'phone',
      ),
    );
    var repo = repository();
    final note = repo.saveNote(
      uuid: 'chosen',
      title: 'Note',
      content: 'Original.',
    );
    final source = TransformSource(
      content: note.content,
      version: note.versionVectorJson,
      start: 0,
      end: note.content.length,
    );
    repo.acceptTransformation(
      taskId: 'persisted_task',
      uuid: 'chosen',
      operation: 'rewrite-note',
      source: source,
      replacement: 'Rewritten.',
    );
    db.close();
    db = open();
    repo = repository();
    addTearDown(() async {
      db.close();
      await dir.delete(recursive: true);
    });
    final row = repo.transformationHistory('chosen').single;
    expect(row.beforeContent, 'Original.');
    expect(
      () => repo.acceptTransformation(
        taskId: 'persisted_task',
        uuid: 'chosen',
        operation: 'rewrite-note',
        source: source,
        replacement: 'Rewritten.',
      ),
      throwsStateError,
    );
    repo.saveNote(
      uuid: 'chosen',
      title: 'Manual title',
      content: 'Later manual edit.',
    );
    expect(() => repo.restoreTransformation(row.id), throwsStateError);
    expect(repo.getNoteByUuid('chosen')!.content, 'Later manual edit.');
    expect(
      repo.transformationHistory('chosen').single.beforeContent,
      'Original.',
    );
    repo.clearTransformationHistory('chosen');
    expect(repo.transformationHistory('chosen'), isEmpty);
  });
  test('accepted and restored bodies use the existing outbox while recovery remains local', () async {
    final drive = MemoryDrive();
    final primary = await SyncFixture.create(drive, 'primary');
    primary.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'Original.');
    await primary.sync();
    final note = primary.notes.getNoteByUuid('chosen')!;
    primary.notes.acceptTransformation(
      taskId: 'sync_proposal',
      uuid: 'chosen',
      operation: 'rewrite-note',
      source: TransformSource(
        content: note.content,
        version: note.versionVectorJson,
        start: 0,
        end: note.content.length,
      ),
      replacement: 'Rewritten.',
    );
    await primary.sync();
    expect(drive.documents['note/chosen']!.payload['content'], 'Rewritten.');
    expect(primary.collections.map((c) => c.type), [
      'note',
      'diary',
      'thought',
    ]);
    primary.notes.restoreTransformation(
      primary.notes.transformationHistory('chosen').single.id,
    );
    await primary.sync();
    expect(drive.documents['note/chosen']!.payload['content'], 'Original.');
  });
  test('recovery bound keeps the latest ten and a later manual save still uses conflict protection', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'Original.');
    for (var i = 0; i < 12; i++) {
      final note = app.notes.getNoteByUuid('chosen')!;
      app.notes.acceptTransformation(
        taskId: 'bounded_task_$i',
        uuid: 'chosen',
        operation: 'rewrite-note',
        source: TransformSource(
          content: note.content,
          version: note.versionVectorJson,
          start: 0,
          end: note.content.length,
        ),
        replacement: 'Revision $i.',
      );
    }
    expect(app.notes.transformationHistory('chosen'), hasLength(10));
    final outdated = app.notes.getNoteByUuid('chosen')!;
    app.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'A newer edit.');
    final conflict = app.notes.saveNote(
      uuid: 'chosen',
      expectedVersionVectorJson: outdated.versionVectorJson,
      title: 'Manual',
      content: 'Saved manual draft.',
    );
    expect(conflict.isConflict, true);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'A newer edit.');
  });
  test('empty notes, unavailable model and terminal task failure remain explicit and retrievable', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(uuid: 'chosen', title: 'Empty', content: '');
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store);
    final container = writingContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.start('chosen', operation: 'rewrite-note');
    expect(wire.posts, 0);
    expect(store.value, null);
    expect(container.read(noteSummaryProvider).message, contains('nonempty'));
    await controller.clear();
    app.notes.saveNote(uuid: 'chosen', title: 'Note', content: 'Original.');
    wire.noModel = true;
    await controller.start('chosen', operation: 'rewrite-note');
    final id = store.value!.id;
    expect(wire.posts, 0);
    expect(store.value!.accepted, false);
    wire.noModel = false;
    wire.phase = 'failed';
    await controller.retry();
    expect(store.value!.id, id);
    expect(container.read(noteSummaryProvider).phase, 'failed');
    expect(await controller.acceptTransformation(), false);
    await controller.retry();
    expect(wire.posts, 1);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Original.');
  });
  testWidgets(
    'narrow writing review shows inert Markdown and accept/reject; recovery is reachable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          noteSummaryProvider.overrideWith(WritingPreview.new),
          accountResetProvider.overrideWith(summary.TestReset.new),
          syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NoteTransformPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('transform-output')),
            )
            .data,
        '**Original.**',
      );
      expect(find.text('Accept replacement'), findsOneWidget);
      expect(find.text('Reject / clear proposal'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class WritingPreview extends NoteSummaryController {
  @override
  NoteSummaryState build() => NoteSummaryState(
    phase: 'completed',
    text: '**Original.**',
    handle: SummaryHandle(
      id: 'preview_task',
      noteId: 'chosen',
      revision: 'a' * 64,
      computerId: 'computer',
      created: DateTime.now().millisecondsSinceEpoch,
      operation: 'markdown-note',
      accepted: true,
      localSource: const TransformSource(
        content: 'Original.',
        version: '{}',
        start: 0,
        end: 9,
      ).encode(),
    ),
  );
}
