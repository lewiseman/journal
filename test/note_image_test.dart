import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/images/note_image_contract.dart';
import 'package:journal/modules/notes/images/note_image_page.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

String visionStatus = 'ready';

class VisionConnection extends summary.TestConnection {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [summary.computer],
    selectedId: summary.computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {'id': 'text', 'status': 'unloaded', 'operations': []},
        {
          'id': 'vision',
          'status': visionStatus,
          'visionContract': 1,
          'operations': [noteImageOperation],
        },
      ],
    },
  );
}

/// Routes image uploads through the shared fake while recording them.
class ImageTransport extends summary.SummaryTransport {
  ImageTransport(super.store);
  final images = <String>[];
  final routes = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) {
    routes.add('$method $route');
    if (route == '/v1/image-jobs') {
      images.add(body!['image'] as String);
      return super.request(
        endpoint,
        pin,
        method,
        '/v1/jobs',
        body: Map.of(body)..remove('image'),
        headers: headers,
      );
    }
    return super.request(
      endpoint,
      pin,
      method,
      route,
      body: body,
      headers: headers,
    );
  }
}

ProviderContainer imageContainer(
  SyncFixture app,
  SummaryStore store,
  ImageTransport wire, {
  SyncDeviceRole role = SyncDeviceRole.primary,
}) => ProviderContainer(
  overrides: [
    notesRepositoryProvider.overrideWithValue(app.notes),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(VisionConnection.new),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(role),
  ],
);

Future<Uint8List> png(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

const answer = {
  'observations': 'A red square.',
  'text': 'The image does not show this.',
  'inference': 'Possibly a colour sample.',
  'answer': 'Red',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    visionStatus = 'ready';
    dir = await Directory.systemTemp.createTemp('journal-i03-');
  });
  tearDown(() => dir.delete(recursive: true));

  test('answers keep observations, read text and interpretation separate', () {
    final parsed = NoteImageAnswer.parse(jsonEncode(answer));
    expect(parsed.observations, 'A red square.');
    expect(parsed.text, '', reason: 'a repeated refusal is not image text');
    expect(parsed.inference, 'Possibly a colour sample.');
    expect(parsed.insertion, 'Red');
    for (final bad in [
      '{}',
      jsonEncode({...answer, 'observations': ''}),
      jsonEncode({...answer, 'extra': ''}),
      jsonEncode({...answer, 'text': 'a\u0000b'}),
    ]) {
      expect(() => NoteImageAnswer.parse(bad), throwsFormatException);
    }
    expect(
      () => NoteImageRequest.validate('question', ''),
      throwsFormatException,
    );
    expect(
      () => NoteImageRequest.validate('describe', 'x'),
      throwsFormatException,
    );
    NoteImageRequest.validate('question', 'What colour is the door?');
  });

  test('only a regular image attached to this note is read and re-encoded within limits', () async {
    final big = File('${dir.path}/big.png')
      ..writeAsBytesSync(await png(3000, 2000, Colors.red));
    final note = NoteEntity(
      uuid: 'n',
      attachments: [
        {'path': big.path, 'type': 'image/png'},
        {'path': '${dir.path}/doc.txt', 'type': 'text/plain'},
      ],
    );
    expect(noteImageAttachment(note, big.path), isNotNull);
    expect(noteImageAttachment(note, '${dir.path}/doc.txt'), isNull);
    expect(noteImageAttachment(note, '${dir.path}/other.png'), isNull);
    final prepared = await prepareNoteImage(
      noteImageAttachment(note, big.path)!,
    );
    expect(prepared.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    final descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(prepared),
    );
    expect([descriptor.width, descriptor.height], [1280, 853]);
    expect(prepared.length, lessThanOrEqualTo(noteImageUploadBytes));
    // Identical input re-encodes identically, so a retry can be verified.
    expect(
      await prepareNoteImage(noteImageAttachment(note, big.path)!),
      prepared,
    );
    await expectLater(
      prepareNoteImage(
        NoteAttachment(path: '${dir.path}/gone.png', type: 'image/png'),
      ),
      throwsA(
        isA<CompanionFailure>().having((e) => e.code, 'code', 'IMAGE_MISSING'),
      ),
    );
    final fake = File('${dir.path}/fake.png')
      ..writeAsStringSync('not an image');
    await expectLater(
      prepareNoteImage(NoteAttachment(path: fake.path, type: 'image/png')),
      throwsA(
        isA<CompanionFailure>().having((e) => e.code, 'code', 'INVALID_IMAGE'),
      ),
    );
  });

  test('asks with only the image and question; inserting is explicit, version-checked and recoverable', () async {
    final drive = MemoryDrive();
    final app = await SyncFixture.create(drive, 'phone');
    final file = File('${dir.path}/photo.png')
      ..writeAsBytesSync(await png(64, 64, Colors.red));
    final attachments = [
      {'path': file.path, 'type': 'image/png'},
    ];
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'Private title',
      content: 'Private body.',
      attachmentPaths: attachments,
    );
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)..output = jsonEncode(answer);
    final container = imageContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteImage(
      'chosen',
      path: file.path,
      mode: 'question',
      question: 'What colour is it?',
    );
    expect(wire.routes, contains('POST /v1/image-jobs'));
    expect(wire.submitted.single['operation'], noteImageOperation);
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'mode': 'question',
      'question': 'What colour is it?',
    });
    expect(wire.submitted.single.toString(), isNot(contains('Private')));
    expect(base64Decode(wire.images.single).sublist(0, 4), [
      0x89,
      0x50,
      0x4e,
      0x47,
    ]);
    expect(container.read(noteSummaryProvider).phase, 'completed');
    expect(controller.noteImageAnswer()!.answer, 'Red');
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Private body.');
    expect(await controller.acceptNoteImage('  The square is red.  '), true);
    final saved = app.notes.getNoteByUuid('chosen')!;
    expect(saved.content, 'Private body.\n\nThe square is red.');
    expect(saved.attachments, attachments);
    expect(saved.status, SyncStatus.pendingUpload);
    final recovery = app.notes.transformationHistory('chosen').single;
    expect(recovery.beforeContent, 'Private body.');
    expect(recovery.operation, noteImageOperation);
    app.notes.restoreTransformation(recovery.id);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Private body.');
    expect(
      () => app.notes.appendToNote(
        taskId: recovery.taskId,
        uuid: 'chosen',
        expectedVersion: app.notes.getNoteByUuid('chosen')!.versionVectorJson,
        operation: noteImageOperation,
        text: 'again',
      ),
      throwsStateError,
      reason: 'one insertion per task',
    );
  });

  test('stale notes, changed or missing images, and an unready model never send or insert', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final file = File('${dir.path}/photo.png')
      ..writeAsBytesSync(await png(64, 64, Colors.red));
    final attachments = [
      {'path': file.path, 'type': 'image/png'},
    ];
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'T',
      content: 'Body.',
      attachmentPaths: attachments,
    );
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)
      ..output = jsonEncode(answer)
      ..phase = 'running';
    final container = imageContainer(app, store, wire);
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteImage(
      'chosen',
      path: file.path,
      mode: 'describe',
    );
    final note = app.notes.getNoteByUuid('chosen')!;
    app.notes.saveNote(
      uuid: 'chosen',
      expectedVersionVectorJson: note.versionVectorJson,
      title: 'T',
      content: 'Edited meanwhile.',
      attachmentPaths: attachments,
    );
    wire.phase = 'completed';
    await controller.retry();
    expect(container.read(noteSummaryProvider).stale, true);
    expect(await controller.acceptNoteImage('Inserted'), false);
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Edited meanwhile.');
    await controller.clear();

    // The file is replaced before the request is confirmed: no resubmission.
    wire
      ..job = null
      ..offline = true;
    await controller.startNoteImage(
      'chosen',
      path: file.path,
      mode: 'describe',
    );
    expect(store.value!.accepted, false);
    file.writeAsBytesSync(await png(64, 64, Colors.blue));
    final posts = wire.posts;
    wire.offline = false;
    await controller.retry();
    expect(wire.posts, posts);
    expect(
      container.read(noteSummaryProvider).message,
      contains('image file changed'),
    );
    await controller.clear();

    file.deleteSync();
    await controller.startNoteImage(
      'chosen',
      path: file.path,
      mode: 'describe',
    );
    expect(
      container.read(noteSummaryProvider).message,
      contains('not available on this phone'),
    );
    await controller.clear();
    await controller.startNoteImage(
      'chosen',
      path: '${dir.path}/never.png',
      mode: 'describe',
    );
    expect(
      container.read(noteSummaryProvider).message,
      contains('no longer attached'),
    );
    await controller.clear();
    visionStatus = 'untested';
    container.invalidate(companionControllerProvider);
    await controller.startNoteImage(
      'chosen',
      path: file.path,
      mode: 'describe',
    );
    expect(container.read(noteSummaryProvider).message, contains('self-test'));
    expect(wire.posts, posts);
  });

  test('a read-only device may ask but cannot insert', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final file = File('${dir.path}/photo.png')
      ..writeAsBytesSync(await png(32, 32, Colors.red));
    app.notes.saveNote(
      uuid: 'chosen',
      title: 'T',
      content: 'Body.',
      attachmentPaths: [
        {'path': file.path, 'type': 'image/png'},
      ],
    );
    app.storage.setPrimary(
      const PrimaryDevice(
        deviceId: 'other',
        deviceName: 'Desktop',
        fileId: 'primary',
      ),
    );
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)..output = jsonEncode(answer);
    final container = imageContainer(
      app,
      store,
      wire,
      role: SyncDeviceRole.secondary,
    );
    addTearDown(container.dispose);
    container.read(noteSummaryProvider);
    await summary.settle();
    final controller = container.read(noteSummaryProvider.notifier);
    await controller.startNoteImage(
      'chosen',
      path: file.path,
      mode: 'describe',
    );
    expect(controller.noteImageAnswer(), isNotNull);
    expect(await controller.acceptNoteImage('x'), false);
    expect(container.read(noteSummaryProvider).message, contains('read-only'));
    expect(app.notes.getNoteByUuid('chosen')!.content, 'Body.');
  });

  testWidgets(
    'a note without images explains it; missing files cannot be chosen',
    (tester) async {
      final app = await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      );
      app!.notes.saveNote(uuid: 'plain', title: 'T', content: 'Body.');
      app.notes.saveNote(
        uuid: 'restored',
        title: 'T',
        content: 'Body.',
        attachmentPaths: [
          {'path': '${dir.path}/from-drive.jpg', 'type': 'image/jpeg'},
        ],
      );
      final store = summary.MemorySummaries();
      final container = imageContainer(app, store, ImageTransport(store));
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NoteImagePage(noteId: 'plain')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-image-none')), findsOneWidget);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NoteImagePage(noteId: 'restored')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Not available on this phone'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('note-image-start')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
