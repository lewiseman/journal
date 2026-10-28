import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/images/note_background_gen.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart'
    show hexHash;
import 'package:sync_wise/sync_wise.dart';

import 'note_image_test.dart' show png;
import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

String imageStatus = 'ready';

class ImageConnection extends summary.TestConnection {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [summary.computer],
    selectedId: summary.computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'image',
          'status': imageStatus,
          'backgroundContract': 1,
          'operations': [noteBackgroundOperation],
        },
      ],
    },
  );
}

/// Serves the generated image on its result route, like the companion.
class BackgroundTransport extends summary.SummaryTransport {
  BackgroundTransport(super.store);
  List<int> image = const [];
  List<int>? served;
  final routes = <String>[];
  Future<void> finish(List<int> png) async {
    image = png;
    output = jsonEncode({
      'width': 64,
      'height': 96,
      'seed': 7,
      'bytes': png.length,
      'sha256': await hexHash(png),
      'model': 'sd',
    });
  }

  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    routes.add('$method $route');
    final result = RegExp(r'^/v1/image-jobs/([^/]+)/result$').firstMatch(route);
    if (result != null) {
      return {'id': result[1], 'image': base64Encode(served ?? image)};
    }
    final response = await super.request(
      endpoint,
      pin,
      method,
      route,
      body: body,
      headers: headers,
    );
    return phase == 'running' &&
            route.startsWith('/v1/jobs/') &&
            method == 'GET'
        ? {
            ...response,
            'progress': {'step': 8, 'total': 20},
          }
        : response;
  }
}

ProviderContainer backgroundContainer(
  SyncFixture app,
  SummaryStore store,
  BackgroundTransport wire,
  NoteBackgroundStore images, {
  SyncDeviceRole role = SyncDeviceRole.primary,
}) => ProviderContainer(
  overrides: [
    notesRepositoryProvider.overrideWithValue(app.notes),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(ImageConnection.new),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(role),
    noteBackgroundStoreProvider.overrideWithValue(images),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late NoteBackgroundStore images;
  const original = {'type': 'sand', 'image': null, 'image_source': null};
  setUp(() async {
    imageStatus = 'ready';
    dir = await Directory.systemTemp.createTemp('journal-i06-');
    images = NoteBackgroundStore(support: () async => dir);
  });
  tearDown(() => dir.delete(recursive: true));

  test('only the typed description and tone are sent', () {
    const request = NoteBackgroundRequest(
      noteId: 'n',
      prompt: ' sea glass ',
      tone: 'dark',
      background: {},
    );
    expect(jsonDecode(request.request()), {
      'prompt': 'sea glass',
      'tone': 'dark',
    });
    for (final bad in [
      const NoteBackgroundRequest(
        noteId: 'n',
        prompt: ' ',
        tone: 'dark',
        background: {},
      ),
      NoteBackgroundRequest(
        noteId: 'n',
        prompt: 'x' * 241,
        tone: 'dark',
        background: const {},
      ),
      const NoteBackgroundRequest(
        noteId: 'n',
        prompt: 'a\nb',
        tone: 'dark',
        background: {},
      ),
      const NoteBackgroundRequest(
        noteId: 'n',
        prompt: 'x',
        tone: 'neon',
        background: {},
      ),
    ]) {
      expect(bad.request, throwsFormatException);
    }
  });

  test('generate → verified preview → explicit accept survives restart, syncs the choice only, and reverts', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'Private title',
      content: 'Private body.',
      background: original,
    );
    final store = summary.MemorySummaries();
    final wire = BackgroundTransport(store)..phase = 'running';
    final container = backgroundContainer(app, store, wire, images);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteBackground(
      'chosen',
      prompt: 'sea glass',
      tone: 'light',
    );
    expect(wire.submitted.single['operation'], noteBackgroundOperation);
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'prompt': 'sea glass',
      'tone': 'light',
    });
    expect(wire.submitted.single.toString(), isNot(contains('Private')));
    await controller.retry();
    expect(
      container.read(noteSummaryProvider).message,
      contains('step 8 of 20'),
    );
    wire.phase = 'completed';
    await wire.finish(await png(64, 96, Colors.teal));
    await controller.retry();
    expect(wire.routes, contains(matches(r'GET /v1/image-jobs/.+/result')));
    final preview = await controller.noteBackgroundPreview();
    expect(preview!.readAsBytesSync(), wire.image);
    expect(
      app.notes.getNoteByUuid('chosen')!.background,
      original,
      reason: 'nothing changes before acceptance',
    );
    // A text edit meanwhile does not block applying a background.
    final note = app.notes.getNoteByUuid('chosen')!;
    app.notes.saveNote(
      uuid: 'chosen',
      expectedVersionVectorJson: note.versionVectorJson,
      title: note.title,
      content: 'Edited text.',
      background: note.background,
    );
    expect(await controller.acceptNoteBackground(), true);
    expect(
      await preview.exists(),
      false,
      reason: 'the preview moves into the accepted copy',
    );
    final applied = app.notes.getNoteByUuid('chosen')!;
    expect(applied.content, 'Edited text.');
    expect(applied.background['type'], 'sand');
    expect(applied.background['image_source'], 'local');
    final path = applied.background['image'] as String;
    expect(File(path).readAsBytesSync(), wire.image);
    expect(applied.status, SyncStatus.pendingUpload);
    // "Restart": a fresh repository over the same database sees the same background.
    expect(app.notes.getNoteByUuid('chosen')!.background['image'], path);
    await app.sync();
    expect(
      (drive.documents['note/chosen']!.payload['background'] as Map)['image'],
      path,
      reason: 'sync carries the path, not the bytes',
    );
    expect(
      store.value,
      null,
      reason: 'accepting clears and acknowledges the task',
    );
    expect(wire.routes.where((r) => r.endsWith('/ack')), isNotEmpty);
    await controller.revertNoteBackground('chosen');
    expect(app.notes.getNoteByUuid('chosen')!.background, original);
    await expectLater(
      controller.revertNoteBackground('chosen'),
      throwsStateError,
    );
  });

  test('a mismatched image is refused; a changed background makes the preview stale', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'T',
      content: 'Body.',
      background: original,
    );
    final store = summary.MemorySummaries();
    final wire = BackgroundTransport(store)
      ..finish(await png(64, 96, Colors.teal));
    wire.served = await png(64, 96, Colors.red);
    final container = backgroundContainer(app, store, wire, images);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteBackground(
      'chosen',
      prompt: 'sea glass',
      tone: 'light',
    );
    expect(
      container.read(noteSummaryProvider).message,
      contains('different image'),
    );
    expect(await controller.noteBackgroundPreview(), isNull);
    wire.served = null;
    await controller.retry();
    expect(await controller.noteBackgroundPreview(), isNotNull);
    final note = app.notes.getNoteByUuid('chosen')!;
    app.notes.saveNote(
      uuid: 'chosen',
      expectedVersionVectorJson: note.versionVectorJson,
      title: 'T',
      content: 'Body.',
      background: {'type': 'mint'},
    );
    await controller.refreshSource();
    expect(container.read(noteSummaryProvider).stale, true);
    expect(await controller.acceptNoteBackground(), false);
    expect(app.notes.getNoteByUuid('chosen')!.background, {'type': 'mint'});
  });

  test('cancel, unready model and read-only devices leave the note unchanged and send nothing extra', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'T',
      content: 'Body.',
      background: original,
    );
    final store = summary.MemorySummaries();
    final wire = BackgroundTransport(store)..phase = 'running';
    final container = backgroundContainer(app, store, wire, images);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteBackground(
      'chosen',
      prompt: 'sea glass',
      tone: 'light',
    );
    await controller.cancel();
    expect(wire.routes, contains(matches(r'POST /v1/jobs/.+/cancel')));
    expect(container.read(noteSummaryProvider).phase, 'cancelled');
    await controller.clear();
    expect(app.notes.getNoteByUuid('chosen')!.background, original);
    final posts = wire.posts;
    imageStatus = 'needs_download';
    container.invalidate(companionControllerProvider);
    await controller.startNoteBackground(
      'chosen',
      prompt: 'sea glass',
      tone: 'light',
    );
    expect(
      container.read(noteSummaryProvider).message,
      contains('image model'),
    );
    await controller.clear();
    app.storage.setPrimary(
      const PrimaryDevice(
        deviceId: 'other',
        deviceName: 'Desktop',
        fileId: 'primary',
      ),
    );
    imageStatus = 'ready';
    container.invalidate(companionControllerProvider);
    await controller.startNoteBackground(
      'chosen',
      prompt: 'sea glass',
      tone: 'light',
    );
    expect(container.read(noteSummaryProvider).message, contains('read-only'));
    expect(wire.posts, posts);
  });

  test('old previews expire, the active one is kept, and reset removes generated images', () async {
    await images.savePreview('task-active-1', await png(8, 8, Colors.white));
    await images.savePreview('task-old-0001', await png(8, 8, Colors.white));
    final stale = DateTime.now().subtract(const Duration(hours: 25));
    (await images.preview('task-old-0001')).setLastModifiedSync(stale);
    (await images.preview('task-active-1')).setLastModifiedSync(stale);
    await images.sweepPreviews(keep: 'task-active-1');
    expect(await (await images.preview('task-active-1')).exists(), true);
    expect(await (await images.preview('task-old-0001')).exists(), false);
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    await JournalAccountResetData(
      db: app.db,
      supportDirectory: () async => dir,
      clearCachedImages: () async {},
    ).clear();
    expect(Directory('${dir.path}/note_backgrounds').existsSync(), false);
  });
}
