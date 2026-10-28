import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sync_wise/sync_wise.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/notes/controllers/note_attachment_service.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/models/note_attachment.dart';
import 'package:journal/modules/notes/models/note_colors.dart';
import 'package:journal/modules/notes/models/note_entity.dart';
import 'package:journal/modules/notes/views/pages/edit_note_page.dart';
import 'package:journal/modules/notes/views/widgets/note_attachment_strip.dart';
import 'package:journal/modules/voice/voice.dart';
import 'package:open_filex/open_filex.dart';

void main() {
  late Directory directory;
  late File document;
  late File image;
  late NoteAttachment pdf;
  late NoteAttachment photo;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('journal_attachments_');
    document = File('${directory.path}/document.pdf')..writeAsStringSync('pdf');
    image = File('${directory.path}/photo.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQ0AAAAASUVORK5CYII=',
        ),
      );
    pdf = NoteAttachment.fromPath(document.path);
    photo = NoteAttachment.fromPath(image.path);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('attachment metadata stores only a path and MIME type', () {
    expect(pdf.toMap(), {'path': document.path, 'type': 'application/pdf'});
    expect(photo.isImage, isTrue);
    expect(photo.filename, 'photo.png');
    expect(pdf.typeLabel, 'PDF');
    expect(
      NoteAttachment.fromPath('/tmp/unknown.abcxyz').type,
      'application/octet-stream',
    );
    final fromUri = NoteAttachment.tryFromMap({'path': image.uri.toString()})!;
    expect(fromUri.pathKey, photo.pathKey);
    for (final entry in <Map<String, dynamic>>[
      {},
      {'path': 42},
      {'path': ''},
      {'path': 'relative.pdf'},
      {'path': 'https://example.com/file.pdf'},
      {'path': 'file://%'},
      {'path': 'file:///tmp/file.pdf?query=bad'},
    ]) {
      expect(NoteAttachment.tryFromMap(entry), isNull);
    }
  });

  test(
    'picker returns mixed references and reports files without local paths',
    () async {
      final service = NoteAttachmentService(
        picker: () async => [
          _PickedFile(document.path),
          _PickedFile(image.path),
          _PickedFile(null),
          _PickedFile('content://provider/document/42'),
          _PickedFile(''),
        ],
      );
      final result = await service.pick();
      expect(result.attachments.map((item) => item.toMap()), [
        pdf.toMap(),
        photo.toMap(),
      ]);
      expect(result.skipped, 3);
    },
  );

  test('picker cancellation is empty and picker failures propagate', () async {
    expect(
      (await NoteAttachmentService(picker: () async => []).pick()).attachments,
      isEmpty,
    );
    await expectLater(
      NoteAttachmentService(picker: () async => throw StateError('picker'))
          .pick(),
      throwsStateError,
    );
  });

  test(
    'opening forwards path/type and handles unavailable or rejected files',
    () async {
      var calls = 0;
      var result = ResultType.done;
      final service = NoteAttachmentService(
        opener: (path, type) async {
          calls++;
          expect(path, document.path);
          expect(type, 'application/pdf');
          return OpenResult(type: result);
        },
      );
      expect(await service.open(pdf), isNull);
      result = ResultType.noAppToOpen;
      expect(await service.open(pdf), 'No installed app can open this file.');
      result = ResultType.permissionDenied;
      expect(await service.open(pdf), 'Access to this file was denied.');
      result = ResultType.fileNotFound;
      expect(await service.open(pdf), 'This file is unavailable.');
      result = ResultType.error;
      expect(
        await service.open(pdf),
        'Could not open this file. Please try again.',
      );
      document.deleteSync();
      expect(await service.open(pdf), 'This file is unavailable.');
      expect(calls, 5);
      final throwing = NoteAttachmentService(
        opener: (_, _) async => throw StateError('open'),
      );
      expect(
        await throwing.open(photo),
        'Could not open this file. Please try again.',
      );
    },
  );

  testWidgets(
    'cards open documents and images through the system and keep image previews',
    (tester) async {
      final service = _AttachmentService();
      int? removed;
      Widget strip({bool editing = false}) => NoteAttachmentStrip(
        attachments: [pdf.toMap(), photo.toMap()],
        colors: _colors,
        onRemove: editing ? (index) => removed = index : null,
      );
      await tester.pumpWidget(
        _harness(
          service: service,
          child: Scaffold(body: strip()),
        ),
      );
      await tester.pump();
      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.byTooltip('Remove document.pdf'), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.text('document.pdf'));
      await tester.pump();
      expect(service.opened, [pdf.path]);
      await tester.tap(find.text('photo.png'));
      await tester.pumpAndSettle();
      expect(service.opened, [pdf.path, photo.path]);
      expect(find.byType(NoteAttachmentStrip), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(
        _harness(
          service: service,
          child: Scaffold(body: strip(editing: true)),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Remove document.pdf'));
      expect(removed, 0);
      expect(document.existsSync(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable files and opening failures remain attached', (
    tester,
  ) async {
    final service = _AttachmentService()
      ..available = false
      ..openError = 'This file is unavailable.';
    await tester.pumpWidget(
      _harness(
        service: service,
        child: Scaffold(
          body: NoteAttachmentStrip(
            attachments: [pdf.toMap()],
            colors: _colors,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Unavailable'), findsOneWidget);
    await tester.tap(find.text('document.pdf'));
    await tester.pump();
    expect(find.text('This file is unavailable.'), findsOneWidget);
    expect(find.text('document.pdf'), findsOneWidget);
  });

  testWidgets(
    'unreadable images keep a placeholder and report opening errors',
    (tester) async {
      await tester.runAsync(() async {
        image.writeAsStringSync('invalid image');
        await tester.pumpWidget(
          _harness(
            service: _AttachmentService()
              ..openError = 'No installed app can open this file.',
            child: Scaffold(
              body: NoteAttachmentStrip(
                attachments: [photo.toMap()],
                colors: _colors,
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(NoteAttachmentStrip));
        await precacheImage(
          ResizeImage(FileImage(image), width: 512),
          context,
          onError: (_, _) {},
        );
        await tester.pump();
        expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
        await tester.tap(find.text('photo.png'));
        await tester.pumpAndSettle();
        expect(
          find.text('No installed app can open this file.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel and duplicate-only selection do not dirty a saved note', (
    tester,
  ) async {
    final service = _AttachmentService();
    final repository = _NotesRepository();
    await tester.pumpWidget(
      _harness(
        service: service,
        repository: repository,
        child: EditNotePage(
          existingNote: NoteEntity(
            uuid: 'existing',
            attachments: [pdf.toMap()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final selection in [
      const NoteAttachmentSelection(),
      NoteAttachmentSelection(
        attachments: [
          NoteAttachment.fromPath('${directory.path}/./document.pdf'),
        ],
      ),
    ]) {
      service.selection = selection;
      await tester.tap(find.byTooltip('Edit note'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Attach files'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close editor'));
      await tester.pumpAndSettle();
      expect(find.text('Save your changes?'), findsNothing);
      expect(find.byTooltip('Edit note'), findsOneWidget);
    }
    expect(repository.saves, 0);
  });

  testWidgets('malformed entries are hidden without shifting removal indices', (
    tester,
  ) async {
    int? removed;
    await tester.pumpWidget(
      _harness(
        service: _AttachmentService(),
        child: Scaffold(
          body: NoteAttachmentStrip(
            attachments: [
              {'legacy': 'preserve'},
              pdf.toMap(),
            ],
            colors: _colors,
            onRemove: (index) => removed = index,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Remove document.pdf'));
    expect(removed, 1);
  });

  testWidgets('voice capture returns to the same unsaved note draft', (
    tester,
  ) async {
    final repository = _NotesRepository();
    await tester.pumpWidget(
      _harness(
        service: _AttachmentService(),
        repository: repository,
        child: const EditNotePage(),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'My draft');
    await tester.enterText(fields.last, 'Keep these words.');
    await tester.tap(find.byTooltip('Transcribe a voice note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<VoiceSessionPage>(find.byType(VoiceSessionPage)).mode,
      VoiceSessionMode.transcription,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceSessionPage), findsNothing);
    expect(tester.widget<TextField>(fields.first).controller!.text, 'My draft');
    expect(
      tester.widget<TextField>(fields.last).controller!.text,
      'Keep these words.',
    );
    expect(repository.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary devices can preview voice only in new notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        service: _AttachmentService(),
        role: SyncDeviceRole.secondary,
        child: EditNotePage(existingNote: NoteEntity(uuid: 'read-only')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit note'), findsNothing);
    expect(find.byTooltip('Transcribe a voice note'), findsNothing);
    await tester.pumpWidget(
      _harness(
        service: _AttachmentService(),
        role: SyncDeviceRole.secondary,
        child: const EditNotePage(key: ValueKey('new-note')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Transcribe a voice note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(VoiceSessionPage), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long filenames fit narrow cards with large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        service: _AttachmentService(),
        child: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: SizedBox(
              width: 190,
              child: NoteAttachmentStrip(
                attachments: [
                  NoteAttachment.fromPath(
                    '/tmp/a-very-long-filename-for-an-important-document.pdf',
                  ).toMap(),
                ],
                colors: _colors,
                onRemove: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'attachment-only notes save, reopen, and discard draft removals',
    (tester) async {
      final service = _AttachmentService()
        ..selection = NoteAttachmentSelection(attachments: [pdf, photo, pdf]);
      final repository = _NotesRepository();
      await tester.pumpWidget(
        _harness(
          service: service,
          repository: repository,
          child: const EditNotePage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Attach files'));
      await tester.pumpAndSettle();
      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.text('photo.png'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.saved!.attachments, [pdf.toMap(), photo.toMap()]);
      expect(repository.saved!.content, isEmpty);
      expect(find.byTooltip('Remove document.pdf'), findsNothing);

      // A new editor instance reads the persisted attachment maps.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _harness(
          service: service,
          repository: repository,
          child: EditNotePage(existingNote: repository.saved),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('document.pdf'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit note'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove document.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('document.pdf'), findsNothing);
      await tester.tap(find.byTooltip('Close editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('document.pdf'), findsOneWidget);
      expect(repository.saves, 1);
      expect(document.existsSync(), isTrue);
    },
  );

  testWidgets(
    'cancel, duplicates, and skipped files leave existing maps intact',
    (tester) async {
      final legacy = <String, dynamic>{'old-key': 'keep me'};
      final service = _AttachmentService();
      final repository = _NotesRepository();
      await tester.pumpWidget(
        _harness(
          service: service,
          repository: repository,
          child: EditNotePage(
            existingNote: NoteEntity(
              uuid: 'existing',
              attachments: [legacy, pdf.toMap()],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit note'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Attach files'));
      await tester.pumpAndSettle();
      expect(find.text('document.pdf'), findsOneWidget);
      service.selection = NoteAttachmentSelection(
        attachments: [pdf, photo, photo],
        skipped: 1,
      );
      await tester.tap(find.byTooltip('Attach files'));
      await tester.pumpAndSettle();
      expect(
        find.text('Some files could not be attached without a local path.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.saved!.attachments, [
        legacy,
        pdf.toMap(),
        photo.toMap(),
      ]);
    },
  );

  testWidgets(
    'picker failures offer retry and pending picks disable the button',
    (tester) async {
      final service = _AttachmentService()..failPick = true;
      await tester.pumpWidget(
        _harness(service: service, child: const EditNotePage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Attach files'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open your files. Please try again.'),
        findsOneWidget,
      );
      final pending = Completer<NoteAttachmentSelection>();
      service
        ..failPick = false
        ..pending = pending;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Attach files',
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete(NoteAttachmentSelection(attachments: [pdf]));
      await tester.pumpAndSettle();
      expect(find.text('document.pdf'), findsOneWidget);
      expect(service.picks, 2);
    },
  );

  testWidgets('late picker results are ignored after editor disposal', (
    tester,
  ) async {
    final pending = Completer<NoteAttachmentSelection>();
    final service = _AttachmentService()..pending = pending;
    await tester.pumpWidget(
      _harness(service: service, child: const EditNotePage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Attach files'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(NoteAttachmentSelection(attachments: [pdf]));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

const _colors = NoteColors(
  background: Color(0xfff4f0e8),
  foreground: Color(0xff33312c),
);

Widget _harness({
  required NoteAttachmentService service,
  required Widget child,
  NotesRepository? repository,
  SyncDeviceRole role = SyncDeviceRole.unknown,
}) => ProviderScope(
  overrides: [
    syncDeviceRoleProvider.overrideWithValue(role),
    noteAttachmentServiceProvider.overrideWithValue(service),
    if (repository != null)
      notesRepositoryProvider.overrideWithValue(repository),
  ],
  child: MaterialApp(home: child),
);

// Any attempt to read bytes fails: selection must only access paths.
final class _PickedFile extends PlatformFile {
  _PickedFile(this.path);
  @override
  final String? path;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Only paths should be read');
}

class _AttachmentService extends NoteAttachmentService {
  NoteAttachmentSelection selection = const NoteAttachmentSelection();
  Completer<NoteAttachmentSelection>? pending;
  bool failPick = false;
  bool available = true;
  String? openError;
  int picks = 0;
  final opened = <String>[];

  @override
  Future<NoteAttachmentSelection> pick() async {
    picks++;
    if (failPick) throw StateError('picker');
    return pending == null ? selection : await pending!.future;
  }

  @override
  Future<bool> isAvailable(NoteAttachment attachment) async => available;

  @override
  Future<String?> open(NoteAttachment attachment) async {
    opened.add(attachment.path);
    return openError;
  }
}

class _NotesRepository extends Fake implements NotesRepository {
  NoteEntity? saved;
  int saves = 0;

  @override
  NoteEntity saveNote({
    String? uuid,
    String? expectedVersionVectorJson,
    required String title,
    required String content,
    List<String> tags = const [],
    List<Map> attachmentPaths = const [],
    Map<String, dynamic>? background,
    bool preserveLocalDraft = false,
  }) {
    saves++;
    return saved = NoteEntity(
      uuid: uuid ?? 'saved',
      title: title,
      content: content,
      tags: List.of(tags),
      background: Map.of(background ?? {}),
      attachments: attachmentPaths
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }
}
