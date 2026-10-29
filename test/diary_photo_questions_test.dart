import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_photo_store.dart';
import 'package:journal/modules/diary/models/diary_photo.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_contract.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_controller.dart';
import 'package:journal/modules/diary/photo_questions/diary_photo_question_store.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';

import 'note_image_test.dart' show ImageTransport, png;
import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

String photoStatus = 'ready';

class PhotoConnection extends summary.TestConnection {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.connected,
    computers: [summary.computer],
    selectedId: summary.computer.id,
    status: {
      'recovery': 1,
      'capabilities': [
        {
          'id': 'vision',
          'status': photoStatus,
          'visionContract': 1,
          'photoContract': diaryPhotoQuestionContract,
          'operations': [diaryPhotoQuestionOperation],
        },
      ],
    },
  );
}

const questions = {
  'observations': 'A beach at sunset with a red umbrella.',
  'clear': true,
  'moment': ['What led you down to the beach that evening?'],
  'feeling': [
    'How did you feel as the sun went down?',
    'What did this evening mean to you?',
  ],
  'little': ['What could you hear near the red umbrella?'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DiaryPhotoQuestionStore cache;
  late SyncFixture app;
  late Uint8List photo;
  late String sha;

  setUp(() async {
    photoStatus = 'ready';
    dir = await Directory.systemTemp.createTemp('journal-i02-');
    cache = DiaryPhotoQuestionStore(supportDirectory: () async => dir);
    app = await SyncFixture.create(MemoryDrive(), 'phone');
    photo = await png(400, 300, Colors.orange);
    sha = await DiaryPhotoStore.digest(photo);
  });
  tearDown(() => dir.delete(recursive: true));

  ProviderContainer container(
    summary.MemorySummaries store,
    ImageTransport wire,
  ) {
    final c = ProviderContainer(
      overrides: [
        notesRepositoryProvider.overrideWithValue(app.notes),
        summaryStoreProvider.overrideWithValue(store),
        companionTransportProvider.overrideWithValue(wire),
        companionControllerProvider.overrideWith(PhotoConnection.new),
        accountResetProvider.overrideWith(summary.TestReset.new),
        diaryPhotoQuestionStoreProvider.overrideWithValue(cache),
      ],
    );
    // As the app does: the consumer is alive whether or not a page is open.
    c.listen(diaryPhotoQuestionProvider, (_, _) {});
    return c;
  }

  Future<void> ask(ProviderContainer c, {String caption = ''}) => c
      .read(diaryPhotoQuestionProvider.notifier)
      .request(
        date: '2026-10-27',
        photoSha: sha,
        photo: photo,
        caption: caption,
      );

  File uploadsDir() => File('${dir.path}/diary_photo_questions/uploads');

  test('results are grouped, bounded and keep observations apart', () {
    final parsed = DiaryPhotoQuestions.parse(jsonEncode(questions));
    expect(parsed.observations, 'A beach at sunset with a red umbrella.');
    expect(parsed.clear, true);
    expect(parsed.groups.map((g) => g.length), [1, 2, 1]);
    // A repeat across groups is shown once.
    final repeated = DiaryPhotoQuestions.parse(
      jsonEncode({
        ...questions,
        'little': ['how did you feel as the sun went down?', 'What else?'],
      }),
    );
    expect(repeated.groups[2], ['What else?']);
    for (final bad in [
      '{}',
      jsonEncode({...questions, 'moment': []}),
      jsonEncode({
        ...questions,
        'feeling': ['You felt calm.'],
      }),
      jsonEncode({...questions, 'clear': 'yes'}),
      jsonEncode({...questions, 'observations': ' '}),
      jsonEncode({
        ...questions,
        'little': ['${'x' * 160}?'],
      }),
      jsonEncode({...questions, 'extra': 1}),
    ]) {
      expect(
        () => DiaryPhotoQuestions.parse(bad),
        throwsFormatException,
        reason: bad,
      );
    }
    expect(
      () => DiaryPhotoQuestionSource.validateCaption('x' * 241),
      throwsFormatException,
    );
  });

  test(
    'the cache is local, expires after 30 days, and never keeps stray uploads',
    () async {
      final parsed = DiaryPhotoQuestions.parse(jsonEncode(questions));
      final then = DateTime(2026, 10, 1);
      await cache.write(sha, parsed, now: then);
      expect((await cache.read(sha, now: then))!.groups[0], parsed.groups[0]);
      await cache.writeUpload('task-0001', photo);
      await cache.writeUpload('task-0002', photo);
      await cache.prune(active: 'task-0002', now: DateTime(2026, 10, 20));
      expect(await cache.readUpload('task-0001'), isNull);
      expect(await cache.readUpload('task-0002'), photo);
      expect(await cache.read(sha, now: DateTime(2026, 10, 20)), isNotNull);
      expect(await cache.read(sha, now: DateTime(2026, 11, 1)), isNull);
      expect(
        File('${dir.path}/diary_photo_questions/$sha.json').existsSync(),
        false,
        reason: 'expired results are deleted, not just hidden',
      );
      expect(() => cache.write('../x', parsed), throwsArgumentError);
      // Account reset removes the whole folder.
      await cache.write(sha, parsed);
      await JournalAccountResetData(
        db: app.db,
        supportDirectory: () async => dir,
        clearCachedImages: () async {},
      ).clear();
      expect(
        Directory('${dir.path}/diary_photo_questions').existsSync(),
        false,
      );
    },
  );

  test('sends only the re-encoded photo and caption, caches the result and frees the slot', () async {
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)..output = jsonEncode(questions);
    final c = container(store, wire);
    addTearDown(c.dispose);
    c.read(noteSummaryProvider);
    await summary.settle();
    await ask(c, caption: 'Last swim of summer');
    await summary.settle();
    expect(wire.routes, contains('POST /v1/image-jobs'));
    final sent = wire.submitted.single;
    expect(sent['operation'], diaryPhotoQuestionOperation);
    expect(jsonDecode(sent['prompt'] as String), {
      'caption': 'Last swim of summer',
    });
    expect(sent.keys.toSet(), {'id', 'operation', 'prompt', 'expires'});
    expect(base64Decode(wire.images.single).sublist(0, 4), [
      0x89,
      0x50,
      0x4e,
      0x47,
    ], reason: 'PNG re-encode drops EXIF and appended data');
    final state = c.read(diaryPhotoQuestionProvider);
    expect(state.questions[sha]!.groups[1], questions['feeling']);
    expect(state.messages, isEmpty);
    expect(c.read(noteSummaryProvider).handle, isNull, reason: 'slot freed');
    expect(store.value, isNull);
    expect((await cache.read(sha))!.observations, contains('red umbrella'));
    expect(
      uploadsDir().parent.existsSync() &&
          Directory(uploadsDir().path).listSync().isEmpty,
      true,
      reason: 'the upload copy is deleted with its task',
    );
  });

  test(
    'an unavailable vision model sends nothing and keeps the usual questions',
    () async {
      photoStatus = 'needs_download';
      final store = summary.MemorySummaries();
      final wire = ImageTransport(store)..output = jsonEncode(questions);
      final c = container(store, wire);
      addTearDown(c.dispose);
      c.read(noteSummaryProvider);
      await summary.settle();
      await ask(c);
      expect(wire.submitted, isEmpty);
      expect(store.value, isNull);
      expect(
        c.read(diaryPhotoQuestionProvider).messages[sha],
        contains('Qwen3-VL'),
      );
      expect(c.read(diaryPhotoQuestionProvider).questions, isEmpty);
      expect(
        Directory('${dir.path}/diary_photo_questions').existsSync(),
        false,
      );
    },
  );

  test('a lost acceptance is retrieved after a restart without sending the photo twice', () async {
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)
      ..output = jsonEncode(questions)
      ..phase = 'running'
      ..lostAck = true;
    var c = container(store, wire);
    c.read(noteSummaryProvider);
    await summary.settle();
    await ask(c);
    expect(wire.posts, 1);
    expect(store.value!.isDiaryPhoto, true);
    expect(store.value!.noteId, sha);
    // The app is closed before learning the job was accepted.
    c.dispose();
    wire.phase = 'completed';
    c = container(store, wire);
    addTearDown(c.dispose);
    c.read(noteSummaryProvider);
    for (var i = 0; i < 10 && store.value != null; i++) {
      await summary.settle();
    }
    expect(wire.posts, 1, reason: 'GET found the accepted job');
    expect(wire.images, hasLength(1));
    expect(c.read(diaryPhotoQuestionProvider).questions[sha], isNotNull);
    expect(store.value, isNull);
  });

  test(
    'a resend refuses an upload that changed or vanished, and says why',
    () async {
      final store = summary.MemorySummaries();
      final wire = ImageTransport(store)
        ..output = jsonEncode(questions)
        ..offline = true;
      final c = container(store, wire);
      addTearDown(c.dispose);
      c.read(noteSummaryProvider);
      await summary.settle();
      await ask(c);
      final handle = store.value!;
      expect(handle.accepted, false);
      expect(
        DiaryPhotoQuestionController.asking(c.read(noteSummaryProvider), sha),
        true,
      );
      await cache.writeUpload(handle.id, await png(10, 10, Colors.blue));
      wire.offline = false;
      await c.read(noteSummaryProvider.notifier).retry();
      await summary.settle();
      expect(wire.submitted, isEmpty, reason: 'never send a different photo');
      expect(c.read(noteSummaryProvider).handle, isNull);
      expect(
        c.read(diaryPhotoQuestionProvider).messages[sha],
        contains('no longer on this phone'),
      );
    },
  );

  test(
    'a failed or cancelled job leaves a reason and frees the slot',
    () async {
      final store = summary.MemorySummaries();
      final wire = ImageTransport(store)
        ..output = ''
        ..phase = 'failed';
      final c = container(store, wire);
      addTearDown(c.dispose);
      c.read(noteSummaryProvider);
      await summary.settle();
      await ask(c);
      await summary.settle();
      expect(c.read(noteSummaryProvider).handle, isNull);
      expect(c.read(diaryPhotoQuestionProvider).questions, isEmpty);
      expect(
        c.read(diaryPhotoQuestionProvider).messages[sha],
        contains('usual questions are still here'),
      );
      // Asking again clears the old reason.
      wire
        ..phase = 'completed'
        ..output = jsonEncode(questions);
      await ask(c);
      await summary.settle();
      expect(c.read(diaryPhotoQuestionProvider).messages, isEmpty);
      expect(c.read(diaryPhotoQuestionProvider).questions[sha], isNotNull);
    },
  );

  test(
    'another open task is named instead of silently doing nothing',
    () async {
      final store = summary.MemorySummaries();
      final wire = ImageTransport(store)
        ..output = jsonEncode(questions)
        ..phase = 'running';
      final c = container(store, wire);
      addTearDown(c.dispose);
      c.read(noteSummaryProvider);
      await summary.settle();
      final other = await png(20, 20, Colors.green);
      final otherSha = await DiaryPhotoStore.digest(other);
      await c
          .read(diaryPhotoQuestionProvider.notifier)
          .request(date: '2026-10-27', photoSha: otherSha, photo: other);
      await ask(c);
      expect(wire.posts, 1);
      expect(
        c.read(diaryPhotoQuestionProvider).messages[sha],
        contains('Another AI request is still open'),
      );
    },
  );

  test('saved reflections keep group, origin and the chosen observation apart from the words', () {
    const photo = DiaryPhoto(
      id: 'p1',
      path: 'diary_photos/p1.jpg',
      caption: 'Last swim.',
      seen: 'A beach at sunset.',
      reflections: [
        DiaryPhotoReflection(
          question: 'How did you feel as the sun went down?',
          answer: 'Calm, finally.',
          group: 'feeling',
          fromPhoto: true,
        ),
        DiaryPhotoReflection(question: 'Old?', answer: 'Legacy answer.'),
      ],
    );
    final round = DiaryPhoto.fromJson(
      jsonDecode(jsonEncode(photo.toJson())) as Map<String, dynamic>,
    );
    expect(round.seen, 'A beach at sunset.');
    expect(round.reflections.first.group, 'feeling');
    expect(round.reflections.first.fromPhoto, true);
    expect(round.reflections.last.group, '');
    expect(round.reflections.last.fromPhoto, false);
    expect(
      DiaryPhoto.composeContent([round]),
      'Last swim.\n\nCalm, finally.\n\nLegacy answer.',
      reason: 'the computer’s description never becomes the person’s words',
    );
    expect(
      const DiaryPhoto(id: 'p', path: 'diary_photos/p.jpg').toJson().keys,
      ['id', 'path'],
      reason: 'older records stay byte-identical',
    );
  });

  test(
    'Generate questions asks about each photo in turn and caches every result',
    () async {
      final store = summary.MemorySummaries();
      final wire = ImageTransport(store)..output = jsonEncode(questions);
      final c = container(store, wire);
      addTearDown(c.dispose);
      c.read(noteSummaryProvider);
      await summary.settle();
      final second = await png(30, 20, Colors.teal);
      final secondSha = await DiaryPhotoStore.digest(second);
      final controller = c.read(diaryPhotoQuestionProvider.notifier);
      await controller.generate(
        date: '2026-10-27',
        photos: [
          (photoSha: sha, photo: photo, caption: 'First'),
          (photoSha: secondSha, photo: second, caption: ''),
          (photoSha: 'f' * 64, photo: Uint8List(0), caption: ''),
        ],
      );
      for (var i = 0; i < 10 && wire.submitted.length < 2; i++) {
        await summary.settle();
      }
      await summary.settle();
      expect(
        wire.submitted,
        hasLength(2),
        reason: 'a missing photo is skipped',
      );
      expect(jsonDecode(wire.submitted.first['prompt'] as String), {
        'caption': 'First',
      });
      final state = c.read(diaryPhotoQuestionProvider);
      expect(state.questions.keys, containsAll([sha, secondSha]));
      expect(state.queued, isEmpty);
      expect(store.value, isNull);
      // Asking again for photos that already have questions sends nothing.
      await controller.generate(
        date: '2026-10-27',
        photos: [(photoSha: sha, photo: photo, caption: '')],
      );
      expect(wire.submitted, hasLength(2));
    },
  );

  test('Generate questions without a vision model says why for every photo and sends nothing', () async {
    photoStatus = 'needs_download';
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)..output = jsonEncode(questions);
    final c = container(store, wire);
    addTearDown(c.dispose);
    c.read(noteSummaryProvider);
    await summary.settle();
    final second = await png(30, 20, Colors.teal);
    final secondSha = await DiaryPhotoStore.digest(second);
    await c
        .read(diaryPhotoQuestionProvider.notifier)
        .generate(
          date: '2026-10-27',
          photos: [
            (photoSha: sha, photo: photo, caption: ''),
            (photoSha: secondSha, photo: second, caption: ''),
          ],
        );
    final state = c.read(diaryPhotoQuestionProvider);
    expect(wire.submitted, isEmpty);
    expect(state.queued, isEmpty);
    expect(state.messages[sha], contains('Qwen3-VL'));
    expect(state.messages[secondSha], contains('Qwen3-VL'));
  });

  test(
    'stopping drops waiting photos and cancels the one in progress',
    () async {
      final store = summary.MemorySummaries();
      final wire = ImageTransport(store)
        ..output = jsonEncode(questions)
        ..phase = 'running';
      final c = container(store, wire);
      addTearDown(c.dispose);
      c.read(noteSummaryProvider);
      await summary.settle();
      final second = await png(30, 20, Colors.teal);
      final secondSha = await DiaryPhotoStore.digest(second);
      final controller = c.read(diaryPhotoQuestionProvider.notifier);
      await controller.generate(
        date: '2026-10-27',
        photos: [
          (photoSha: sha, photo: photo, caption: ''),
          (photoSha: secondSha, photo: second, caption: ''),
        ],
      );
      expect(c.read(diaryPhotoQuestionProvider).queued, [secondSha]);
      await controller.stop();
      for (var i = 0; i < 10 && store.value != null; i++) {
        await summary.settle();
      }
      expect(c.read(diaryPhotoQuestionProvider).queued, isEmpty);
      expect(wire.submitted, hasLength(1), reason: 'the second was never sent');
      expect(
        c.read(diaryPhotoQuestionProvider).messages[sha],
        contains('Stopped'),
      );
      expect(c.read(noteSummaryProvider).handle, isNull);
    },
  );

  test('shuffle sends what was shown, returns one new question for that group, and leaves the cached set alone', () async {
    final store = summary.MemorySummaries();
    final wire = ImageTransport(store)..output = jsonEncode(questions);
    final c = container(store, wire);
    addTearDown(c.dispose);
    c.read(noteSummaryProvider);
    await summary.settle();
    final controller = c.read(diaryPhotoQuestionProvider.notifier);
    final sent = await controller.another(
      date: '2026-10-27',
      photoSha: sha,
      photo: photo,
      group: 1,
      shown: ['How did you feel as the sun went down?'],
      caption: 'Beach',
    );
    expect(sent, true);
    await summary.settle();
    expect(jsonDecode(wire.submitted.single['prompt'] as String), {
      'caption': 'Beach',
      'avoid': ['How did you feel as the sun went down?'],
    });
    final state = c.read(diaryPhotoQuestionProvider);
    expect(state.fresh[sha]!.group, 1);
    expect(
      state.fresh[sha]!.question,
      'What did this evening mean to you?',
      reason: 'the shown question is skipped',
    );
    expect(state.shuffling, isEmpty);
    expect(state.questions, isEmpty);
    expect(await cache.read(sha), isNull);
    expect(store.value, isNull);
    // Only repeats come back: say so, add nothing.
    wire.output = jsonEncode({
      ...questions,
      'little': ['What could you hear near the red umbrella?'],
    });
    await controller.another(
      date: '2026-10-27',
      photoSha: sha,
      photo: photo,
      group: 2,
      shown: ['What could you hear near the red umbrella?'],
    );
    await summary.settle();
    expect(
      c.read(diaryPhotoQuestionProvider).messages[sha],
      contains('didn’t come up with a different question'),
    );
    expect(c.read(diaryPhotoQuestionProvider).fresh[sha]!.group, 1);
    expect(wire.submitted, hasLength(2));
  });
}
