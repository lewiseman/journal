import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';
import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/diary/questions/daily_question_entity.dart';
import 'package:journal/modules/diary/questions/daily_question_prompt.dart';
import 'package:journal/modules/diary/questions/daily_question_store.dart';
import 'package:journal/modules/diary/views/pages/diary_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';
import 'package:journal/modules/diary/views/widgets/diary_scene.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/journal_account_reset_data.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

const today = '2026-10-27';

String output(String question, {String source = '', String evidence = ''}) =>
    jsonEncode({'question': question, 'source': source, 'evidence': evidence});

class QuestionConnection extends summary.TestConnection {
  QuestionConnection({this.modelStatus = 'ready', this.contract = 1});
  final String modelStatus;
  final int contract;
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
          'operations': [dailyQuestionOperation],
          'questionContract': contract,
        },
      ],
    },
  );
}

class OfflineConnection extends summary.TestConnection {
  @override
  CompanionState build() => CompanionState(
    phase: CompanionPhase.unavailable,
    computers: [summary.computer],
    selectedId: summary.computer.id,
  );
}

class MemoryPreference implements DailyQuestionPreference {
  MemoryPreference([this.enabled = true]);
  @override
  bool enabled;
  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

DailyQuestionSource selection(Map<String, List<String>> days) {
  var minute = 0;
  DiaryDayEntity day(String date, List<String> texts) => DiaryDayEntity(
    dateString: date,
    date: DateTime.utc(2026),
    itemsJson: jsonEncode([
      for (final (i, t) in texts.indexed)
        DiaryItem(
          itemUuid: '$date-$i',
          createdAt: DateTime.utc(2026, 1, 1, 8, minute++),
          content: t,
          deviceId: 'phone',
          updatedAt: DateTime.utc(2026),
        ).toJson(),
    ]),
  );
  return DailyQuestionSource.select(
    today: today,
    day: (date) => days[date] == null ? null : day(date, days[date]!),
  );
}

ProviderContainer questionContainer(
  SyncFixture app,
  SummaryStore store,
  summary.SummaryTransport wire, {
  DailyQuestionPreference? preference,
  CompanionController Function()? connection,
  DateTime Function()? clock,
  SyncDeviceRole role = SyncDeviceRole.primary,
}) => ProviderContainer(
  overrides: [
    objectBoxProvider.overrideWithValue(app.db),
    syncStateStoreProvider.overrideWithValue(app.storage),
    notesRepositoryProvider.overrideWithValue(app.notes),
    diaryRepositoryProvider.overrideWithValue(app.diary),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(
      connection ?? QuestionConnection.new,
    ),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(role),
    dailyQuestionPreferenceProvider.overrideWithValue(
      preference ?? MemoryPreference(),
    ),
    dailyQuestionClockProvider.overrideWithValue(
      clock ?? () => DateTime(2026, 10, 27, 9),
    ),
  ],
);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

Future<void> restored(ProviderContainer container) async {
  container.read(noteSummaryProvider);
  container.read(dailyQuestionProvider);
  for (var i = 0; i < 60; i++) {
    if (container.read(noteSummaryProvider).phase != 'restoring') return;
    await settle();
  }
}

/// Waits until today's question is current and the task slot is free.
Future<void> answered(ProviderContainer container) async {
  final controller = container.read(dailyQuestionProvider.notifier);
  for (var i = 0; i < 60; i++) {
    final s = container.read(noteSummaryProvider);
    if (controller.current(today) != null && s.handle == null && !s.busy) {
      return;
    }
    await settle();
  }
}

/// Waits until the controller has moved the result out of the task slot.
Future<void> consumed(ProviderContainer container) async {
  for (var i = 0; i < 60; i++) {
    final s = container.read(noteSummaryProvider);
    if (s.handle == null && !s.busy) return;
    await settle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selection is disclosed and bounded: today, then 7 earlier days, whole entries', () {
    final source = selection({
      today: ['Coffee first.', ''],
      '2026-10-26': ['Packing boxes for the move.', 'Called Mum.'],
      '2026-10-20': ['Seven days ago.'],
      '2026-10-19': ['Eight days ago is outside the window.'],
      '2026-10-25': ['x' * 1990],
    });
    expect(source.today.map((e) => e.text), ['Coffee first.']);
    expect(source.prior.map((e) => e.text), [
      'Called Mum.',
      'Packing boxes for the move.',
      'Seven days ago.',
    ]);
    final request = jsonDecode(source.request()) as Map<String, dynamic>;
    expect(request.keys.toSet(), {'today', 'prior', 'avoid'});
    expect((request['prior'] as List).map((e) => e['ago']), [1, 1, 7]);
    expect(source.request(), isNot(contains('2026-')));
    expect(utf8.encode(source.request()).length, lessThanOrEqualTo(2000));
    expect(source.priorDays, ['2026-10-26', '2026-10-20']);
    // Round trip of the protected local snapshot.
    expect(
      DailyQuestionSource.decode(source.encode()).request(),
      source.request(),
    );
    // No entries: nothing personal is sent, not even earlier questions.
    final noEntries = DailyQuestionSource.select(
      today: today,
      day: (_) => null,
      avoid: ['How was the move?'],
    );
    expect(noEntries.avoid, isEmpty);
    // No history at all still yields a valid, empty selection.
    final empty = selection({});
    expect(jsonDecode(empty.request()), {
      'today': [],
      'prior': [],
      'avoid': [],
    });
  });

  test('questions are grounded, non-repetitive and nonintrusive', () {
    final source = selection({
      '2026-10-26': ['Packing boxes for the move to the new flat.'],
      '2026-10-25': ['Interview at the bakery went well.'],
    });
    final grounded = DailyQuestion.parse(
      output(
        'How is the move to the new flat going?',
        source: 'p0',
        evidence: 'the move to the new flat',
      ),
      source,
    );
    expect(grounded.sourceItem, '2026-10-26-0');
    expect(grounded.ago, 1);
    expect(DailyQuestionPrompt.sourceLabel(grounded), contains('yesterday'));
    final general = DailyQuestion.parse(
      output('What is one small thing you noticed today?'),
      source,
    );
    expect(general.grounded, false);
    Matcher rejected(String reason) => throwsA(
      isA<DailyQuestionRejected>().having(
        (e) => e.message,
        'message',
        contains(reason),
      ),
    );
    // Evidence must be copied from the chosen entry.
    expect(
      () => DailyQuestion.parse(
        output('How was the wedding?', source: 'p0', evidence: 'the wedding'),
        source,
      ),
      rejected('not supported'),
    );
    // A general question cannot claim earlier events.
    expect(
      () => DailyQuestion.parse(
        output('How did it go after you said goodbye yesterday?'),
        source,
      ),
      rejected('could not point to'),
    );
    // "Yesterday" must match the source's day.
    expect(
      () => DailyQuestion.parse(
        output(
          'How was the interview yesterday?',
          source: 'p1',
          evidence: 'Interview at the bakery',
        ),
        source,
      ),
      rejected('timing'),
    );
    expect(
      () => DailyQuestion.parse(
        output('Is your depression better today?'),
        source,
      ),
      rejected('too personal'),
    );
    expect(
      () => DailyQuestion.parse(
        output('Why did you feel that way? Be honest?'),
        source,
      ),
      rejected('too personal'),
    );
    expect(
      () => DailyQuestion.parse(
        output('What is one small thing you noticed today?'),
        source,
        history: ['What small thing did you notice today?'],
      ),
      rejected('repeated'),
    );
    // An earlier day's event is never placed today.
    expect(
      () => DailyQuestion.parse(
        output(
          'What did you learn at the interview today?',
          source: 'p1',
          evidence: 'Interview at the bakery',
        ),
        source,
      ),
      rejected('timing'),
    );
    // Ordinary planning wording is not pressure.
    expect(
      DailyQuestion.parse(
        output(
          'What do you need to do before the move on Saturday?',
          source: 'p0',
          evidence: 'the move to the new flat',
        ),
        selection({
          '2026-10-26': ['The move to the new flat is on Saturday.'],
        }),
      ).grounded,
      true,
    );
    // Sharing only an opening such as "What's" is not a repeat.
    expect(
      DailyQuestion.parse(
        output("What's one thing you're curious about this week?"),
        source,
        history: ["What's the plan for Saturday?"],
      ).text,
      contains('curious'),
    );
    expect(
      () => DailyQuestion.parse(output('Write about your day.'), source),
      rejected('not return a question'),
    );
    for (final invalid in ['', '{}', '{"question":"Hi?"}', 'x' * 2000]) {
      expect(
        () => DailyQuestion.parse(invalid, source),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('store keeps one current question per day, bounded history and survives reopening', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final store = DailyQuestionStore(app.db.store);
    final base = DateTime(2026, 10, 27).millisecondsSinceEpoch;
    store.add(today, const DailyQuestion(text: 'First?'), now: base);
    store.add(today, const DailyQuestion(text: 'Second?'), now: base + 1);
    expect(store.current(today)!.question, 'Second?');
    expect(store.recent(), ['Second?', 'First?']);
    store.skip(store.current(today)!.id);
    expect(store.current(today), null);
    expect(store.recent(), contains('Second?'));
    for (var i = 0; i < 40; i++) {
      store.add(
        '2026-10-${(i % 9) + 10}',
        DailyQuestion(text: 'Q$i?'),
        now: base + 10 + i,
      );
    }
    expect(
      app.db.store.box<DailyQuestionEntity>().count(),
      DailyQuestionStore.keep,
    );
    // Older than 30 days is pruned on the next write.
    store.add(
      today,
      const DailyQuestion(text: 'Late?'),
      now: base + const Duration(days: 40).inMilliseconds,
    );
    expect(store.recent(), ['Late?']);
    final directory = app.db.store.directoryPath;
    app.db.close();
    final reopened = ObjectBox.fromStore(await openStore(directory: directory));
    addTearDown(reopened.close);
    expect(
      DailyQuestionStore(reopened.store).current(today)!.question,
      'Late?',
    );
    // Account reset removes the local question history.
    final support = await Directory.systemTemp.createTemp('j02-reset');
    addTearDown(() => support.delete(recursive: true));
    await JournalAccountResetData(
      db: reopened,
      supportDirectory: () async => support,
      clearCachedImages: () async {},
    ).clear();
    expect(DailyQuestionStore(reopened.store).recent(), isEmpty);
  });

  test('end to end: grounded follow-up, no history, repetition, deletion, date change', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final item = app.diary.addTimelineItem(
      dateString: '2026-10-25',
      content: 'Started planting the herb garden on the balcony.',
    );
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)
      ..output = output(
        'How are the herbs on the balcony doing?',
        source: 'p0',
        evidence: 'herb garden on the balcony',
      );
    var now = DateTime(2026, 10, 27, 9);
    final container = questionContainer(app, store, wire, clock: () => now);
    addTearDown(container.dispose);
    await restored(container);
    final controller = container.read(dailyQuestionProvider.notifier);
    // Connected and opted in: today's question is asked without a tap.
    await answered(container);
    final sent = wire.submitted.single;
    expect(sent['operation'], dailyQuestionOperation);
    final prompt = sent['prompt'] as String;
    expect(prompt, contains('herb garden'));
    expect(prompt, isNot(contains(item.itemUuid)));
    expect(prompt, isNot(contains('2026-10-25')));
    expect(jsonDecode(prompt)['prior'][0]['ago'], 2);
    final view = controller.current(today)!;
    expect(view.question.text, 'How are the herbs on the balcony doing?');
    expect(view.question.sourceItem, item.itemUuid);
    expect(
      DailyQuestionPrompt.sourceLabel(view.question),
      contains('2 days ago'),
    );
    // The task slot is free again and the question was acknowledged.
    expect(store.value, null);
    expect(container.read(noteSummaryProvider).handle, null);
    // Not shown on another civil day (for example after travelling).
    expect(controller.current('2026-10-28'), null);
    expect(controller.current('2026-10-26'), null);

    // Regenerating sends the previous question to avoid; a repeat is refused.
    await controller.regenerate(today, view);
    await consumed(container);
    final avoid = jsonDecode(wire.submitted.last['prompt'] as String)['avoid'];
    expect(avoid, ['How are the herbs on the balcony doing?']);
    // A refused replacement keeps today's question.
    expect(
      controller.current(today)!.question.text,
      'How are the herbs on the balcony doing?',
    );
    expect(container.read(dailyQuestionProvider).message, contains('repeated'));

    // A fresh question, then its source entry is deleted: it disappears.
    wire.output = output(
      'What would you like to plant next on the balcony?',
      source: 'p0',
      evidence: 'planting the herb garden',
    );
    await controller.request(today);
    await consumed(container);
    expect(controller.current(today), isNotNull);
    app.diary.deleteTimelineItem(
      dateString: '2026-10-25',
      itemUuid: item.itemUuid,
    );
    expect(controller.current(today), null);

    // With no history left, a general question still helps start writing.
    wire.output = output('What is on your mind as the day begins?');
    await controller.request(today);
    await consumed(container);
    expect(
      jsonDecode(wire.submitted.last['prompt'] as String)['prior'],
      isEmpty,
    );
    expect(controller.current(today)!.question.grounded, false);

    // The civil day changes while the computer works: the result is dropped
    // and the new day asks for its own question.
    wire.phase = 'running';
    wire.output = output('How did the evening go?');
    controller.skip(controller.current(today)!);
    await controller.request(today);
    final asked = wire.submitted.length;
    now = DateTime(2026, 10, 28, 0, 5);
    wire.phase = 'completed';
    await container.read(noteSummaryProvider.notifier).retry();
    await consumed(container);
    expect(controller.current(today), null);
    for (var i = 0; i < 60 && controller.current('2026-10-28') == null; i++) {
      await settle();
    }
    expect(wire.submitted, hasLength(asked + 1));
    expect(controller.current('2026-10-28'), isNotNull);
  });

  test('automatic questions: once per entries and connection, refreshed by new entries', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.diary.addTimelineItem(dateString: today, content: 'Coffee with Sam.');
    final store = summary.MemorySummaries();
    // An unusable answer is not retried in a loop.
    final wire = summary.SummaryTransport(store)..output = 'not a question';
    final container = questionContainer(app, store, wire);
    addTearDown(container.dispose);
    // Kept listened, as the app root does while questions are on.
    container.listen(dailyQuestionProvider, (_, _) {});
    await restored(container);
    final controller = container.read(dailyQuestionProvider.notifier);
    for (var i = 0; i < 20; i++) {
      await settle();
    }
    expect(wire.submitted, hasLength(1));
    expect(controller.current(today), null);
    controller.ensure();
    await settle();
    expect(wire.submitted, hasLength(1));

    // A new entry asks again.
    wire.output = output('What did you and Sam talk about?');
    app.diary.addTimelineItem(dateString: today, content: 'Sam called.');
    await answered(container);
    expect(wire.submitted, hasLength(2));
    final first = controller.current(today)!;
    expect(first.question.text, 'What did you and Sam talk about?');

    // An entry added while the computer works retires that answer too.
    wire.phase = 'running';
    wire.output = output('What made the afternoon feel calm?');
    app.diary.addTimelineItem(dateString: today, content: 'A calm afternoon.');
    for (var i = 0; i < 60 && wire.submitted.length < 3; i++) {
      await settle();
    }
    expect(controller.current(today), null);
    app.diary.addTimelineItem(dateString: today, content: 'Then rain.');
    wire.phase = 'completed';
    await container.read(noteSummaryProvider.notifier).retry();
    wire.output = output('How did the rain change your plans?');
    await answered(container);
    expect(wire.submitted, hasLength(4));
    expect(
      controller.current(today)!.question.text,
      'How did the rain change your plans?',
    );
  });

  test('opt-out, unavailable computer, old companion and missing model send nothing', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.diary.addTimelineItem(dateString: today, content: 'A quiet morning.');
    for (final (connection, expected) in [
      (OfflineConnection.new, 'Connect your trusted computer'),
      (() => QuestionConnection(contract: 0), 'Update the companion'),
      (
        () => QuestionConnection(modelStatus: 'needs_download'),
        'writing model on your computer',
      ),
    ]) {
      final store = summary.MemorySummaries();
      final wire = summary.SummaryTransport(store);
      final container = questionContainer(
        app,
        store,
        wire,
        connection: connection,
      );
      await restored(container);
      await container.read(dailyQuestionProvider.notifier).request(today);
      expect(wire.submitted, isEmpty);
      expect(container.read(dailyQuestionProvider).message, contains(expected));
      container.dispose();
    }
    // Opted out: requesting does nothing; turning off deletes history.
    final preference = MemoryPreference(false);
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)
      ..output = output('What made you smile?');
    final container = questionContainer(
      app,
      store,
      wire,
      preference: preference,
    );
    addTearDown(container.dispose);
    await restored(container);
    final controller = container.read(dailyQuestionProvider.notifier);
    await controller.request(today);
    expect(wire.submitted, isEmpty);
    await controller.setEnabled(true);
    await controller.request(today);
    await consumed(container);
    expect(controller.current(today), isNotNull);
    await controller.setEnabled(false);
    expect(preference.enabled, false);
    expect(controller.current(today), null);
    expect(app.db.store.box<DailyQuestionEntity>().count(), 0);
  });

  test('an unavailable computer still shows today’s cached question', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final item = app.diary.addTimelineItem(
      dateString: '2026-10-26',
      content: 'Started a pottery class.',
    );
    DailyQuestionStore(app.db.store).add(
      today,
      DailyQuestion(
        text: 'What did you make at pottery?',
        sourceDate: '2026-10-26',
        sourceItem: item.itemUuid,
        evidence: 'pottery class',
        ago: 1,
      ),
    );
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store);
    final container = questionContainer(
      app,
      store,
      wire,
      connection: OfflineConnection.new,
    );
    addTearDown(container.dispose);
    await restored(container);
    final controller = container.read(dailyQuestionProvider.notifier);
    expect(
      controller.current(today)!.question.text,
      'What did you make at pottery?',
    );
    // Asking for another fails plainly and sends nothing.
    await controller.request(today);
    expect(wire.submitted, isEmpty);
    expect(
      container.read(dailyQuestionProvider).message,
      contains('Connect your trusted computer'),
    );
  });

  test(
    'a secondary device can ask without changing synced diary data',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      app.diary.addTimelineItem(
        dateString: '2026-10-26',
        content: 'Long walk with the dog.',
      );
      final before = app.diary.getDay('2026-10-26')!.itemsJson;
      app.storage.setPrimary(
        const PrimaryDevice(
          deviceId: 'other',
          deviceName: 'Other',
          fileId: 'p',
        ),
      );
      final store = summary.MemorySummaries();
      final wire = summary.SummaryTransport(store)
        ..output = output(
          'Where did the walk with the dog take you?',
          source: 'p0',
          evidence: 'walk with the dog',
        );
      final container = questionContainer(
        app,
        store,
        wire,
        role: SyncDeviceRole.secondary,
      );
      addTearDown(container.dispose);
      await restored(container);
      await container.read(dailyQuestionProvider.notifier).request(today);
      await consumed(container);
      expect(
        container.read(dailyQuestionProvider.notifier).current(today),
        isNotNull,
      );
      expect(app.diary.getDay('2026-10-26')!.itemsJson, before);
      expect(app.diary.getDay(today), null);
    },
  );

  for (final populated in [false, true]) {
    testWidgets(
      'today keeps its question through a swipe and cancellation: entries=$populated',
      (tester) async {
        final app = (await tester.runAsync(
          () => SyncFixture.create(MemoryDrive(), 'phone'),
        ))!;
        if (populated) {
          app.diary.addTimelineItem(
            dateString: today,
            content: 'A quiet morning outside.',
          );
        }
        const text = 'What is one small thing you noticed today?';
        final store = summary.MemorySummaries();
        final wire = summary.SummaryTransport(store)..output = output(text);
        final container = questionContainer(app, store, wire);
        addTearDown(container.dispose);
        await tester.runAsync(() async {
          await restored(container);
          await answered(container);
        });
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: DiaryPage(clock: () => DateTime(2026, 10, 27)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final live = find.byKey(const PageStorageKey('diary-content'));
        final face = find.byKey(
          ValueKey('diary-face-${DateTime(2026, 10, 27).toIso8601String()}'),
        );
        Finder questionIn(Finder parent) =>
            find.descendant(of: parent, matching: find.text(text));
        void expectSameQuestion() {
          expect(questionIn(live), findsOneWidget);
          expect(questionIn(face), findsOneWidget);
          expect(
            tester.getRect(questionIn(face)),
            tester.getRect(questionIn(live)),
          );
        }

        expectSameQuestion();
        final faces = tester
            .renderObjectList<RenderDiaryCurl>(find.byType(DiaryPaperCurl))
            .toList();
        await tester.runAsync(() async {
          for (final face in faces) {
            await face.prepareTextures();
          }
        });
        await tester.pump();
        final center = tester
            .getRect(find.byKey(const ValueKey('diary-active-paper')))
            .center;
        final gesture = await tester.startGesture(center);
        await gesture.moveBy(const Offset(25, 0));
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump();
        final scene = tester.widget<DiaryScene>(find.byType(DiaryScene));
        expect(scene.turn, greaterThan(0));
        expect(scene.day.dateString, today);
        expect(questionIn(face), findsOneWidget);
        final curl = tester.widget<DiaryPaperCurl>(
          find.descendant(of: face, matching: find.byType(DiaryPaperCurl)),
        );
        expect(curl.visible, isTrue);
        expect(curl.flat, isFalse);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expectSameQuestion();
        await tester.dragFrom(center, const Offset(180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<DiaryScene>(find.byType(DiaryScene)).day.dateString,
          '2026-10-26',
        );
        expect(questionIn(live), findsNothing);
        await tester.dragFrom(center, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expectSameQuestion();
        expect(wire.submitted, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        app.container.dispose();
      },
    );
  }

  testWidgets(
    'prompt: blank lines until a question arrives automatically; a new entry replaces it',
    (tester) async {
      final app = (await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      ))!;
      app.diary.addTimelineItem(
        dateString: '2026-10-26',
        content: 'Booked tickets for the concert.',
      );
      final store = summary.MemorySummaries();
      final wire = summary.SummaryTransport(store)
        ..output = output(
          'What are you most looking forward to at the concert?',
          source: 'p0',
          evidence: 'tickets for the concert',
        );
      final preference = MemoryPreference(false);
      final container = questionContainer(
        app,
        store,
        wire,
        preference: preference,
      );
      addTearDown(container.dispose);
      final question = find.byKey(const ValueKey('diary-prompt-question'));
      Future<void> waitFor(bool Function() done) async {
        for (var i = 0; i < 40 && !done(); i++) {
          await tester.runAsync(settle);
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyQuestionPrompt(day: today, onWrite: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => restored(container));
      await tester.pumpAndSettle();
      expect(question, findsNothing);
      expect(wire.submitted, isEmpty);
      await tester.runAsync(
        () => container.read(dailyQuestionProvider.notifier).setEnabled(true),
      );
      final controller = container.read(dailyQuestionProvider.notifier);
      await waitFor(() => controller.current(today) != null);
      expect(
        find.text('What are you most looking forward to at the concert?'),
        findsOneWidget,
      );
      expect(wire.submitted, hasLength(1));
      // The page itself has no buttons or captions.
      expect(find.byType(TextButton), findsNothing);

      wire.output = output('What did you notice on your walk?');
      app.diary.addTimelineItem(dateString: today, content: 'A long walk.');
      await tester.pump();
      expect(controller.current(today), null);
      await waitFor(
        () =>
            controller.current(today)?.question.text ==
            'What did you notice on your walk?',
      );
      expect(find.text('What did you notice on your walk?'), findsOneWidget);
      expect(wire.submitted, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      app.container.dispose();
    },
  );
}
