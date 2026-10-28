import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/diary/suggestions/diary_suggestion_contract.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/journal_sync_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:sync_wise/sync_wise.dart';

import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

const day = '2026-10-26';

String output({
  String title = 'Morning walk and a slipped deadline',
  String mood = 'mixed',
  String moodEvidence = 'proud of the walk',
  List<List<String>> themes = const [
    ['work pressure', 'the deadline slipped'],
    ['time outdoors', 'walk by the river'],
  ],
}) => jsonEncode({
  'title': title,
  'mood': {'value': mood, 'evidence': moodEvidence},
  'themes': [
    for (final t in themes) {'label': t[0], 'evidence': t[1]},
  ],
});

class DiaryConnection extends summary.TestConnection {
  DiaryConnection({this.modelStatus = 'ready', this.contract = 1});
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
          'operations': [diarySuggestionOperation],
          'diaryContract': contract,
        },
      ],
    },
  );
}

ProviderContainer diaryContainer(
  SyncFixture app,
  SummaryStore store,
  summary.SummaryTransport wire, {
  DiaryConnection Function()? connection,
}) => ProviderContainer(
  overrides: [
    objectBoxProvider.overrideWithValue(app.db),
    syncStateStoreProvider.overrideWithValue(app.storage),
    notesRepositoryProvider.overrideWithValue(app.notes),
    diaryRepositoryProvider.overrideWithValue(app.diary),
    summaryStoreProvider.overrideWithValue(store),
    companionTransportProvider.overrideWithValue(wire),
    companionControllerProvider.overrideWith(connection ?? DiaryConnection.new),
    accountResetProvider.overrideWith(summary.TestReset.new),
    syncDeviceRoleProvider.overrideWithValue(
      app.storage.canEdit ? SyncDeviceRole.primary : SyncDeviceRole.secondary,
    ),
  ],
);

void makeSecondary(SyncFixture app) => app.storage.setPrimary(
  const PrimaryDevice(deviceId: 'other', deviceName: 'Other', fileId: 'p'),
);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

/// Waits for the controller's asynchronous restore so a request is not
/// ignored as "busy".
Future<void> restored(ProviderContainer container) async {
  container.read(noteSummaryProvider);
  for (var i = 0; i < 60; i++) {
    if (container.read(noteSummaryProvider).phase != 'restoring') return;
    await settle();
  }
}

Future<void> waitFor(ProviderContainer container, String phase) async {
  for (var i = 0; i < 60; i++) {
    if (container.read(noteSummaryProvider).phase == phase) return;
    await settle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DiarySuggestionSource source(List<String> texts) =>
      DiarySuggestionSource(day, [
        for (var i = 0; i < texts.length; i++)
          {'item_uuid': 'u$i', 'content': texts[i]},
      ]);

  test(
    'request sends only entry text under temporary IDs; never truncates',
    () {
      final request =
          jsonDecode(source(['Walk.', 'Deadline.']).request()) as Map;
      expect(request.keys, ['entries']);
      expect(request['entries'], [
        {'id': 'e0', 'text': 'Walk.'},
        {'id': 'e1', 'text': 'Deadline.'},
      ]);
      expect(jsonEncode(request), isNot(contains('u0')));
      expect(jsonEncode(request), isNot(contains(day)));
      expect(() => source(['x' * 1990]).request(), throwsFormatException);
      expect(
        () => source(List.filled(13, 'x')).request(),
        throwsFormatException,
      );
    },
  );

  test('sparse day yields an honest empty result rather than invention', () {
    final parsed = DiarySuggestions.parse(
      output(title: '', mood: 'unclear', moodEvidence: '', themes: []),
      source(['Lunch.']),
    );
    expect(parsed.empty, true);
    expect(parsed.dropped, 0);
    // A confident mood about a two-word entry is not supported by its words.
    final invented = DiarySuggestions.parse(
      output(
        title: 'A joyful afternoon',
        mood: 'happy',
        moodEvidence: 'so joyful',
        themes: [
          ['gratitude', 'grateful for everything'],
        ],
      ),
      source(['Lunch.']),
    );
    expect(invented.title, null);
    expect(invented.mood.mood, null);
    expect(invented.themes, isEmpty);
    expect(invented.dropped, 3);
  });

  test(
    'mixed emotions keep both grounded themes and suggest no single mood',
    () {
      final parsed = DiarySuggestions.parse(
        output(),
        source([
          'I was proud of the walk by the river this morning.',
          'Then the deadline slipped and I felt flat all evening.',
        ]),
      );
      expect(parsed.title, 'Morning walk and a slipped deadline');
      expect(parsed.mood.value, 'mixed');
      expect(parsed.mood.mood, null);
      expect(parsed.themes.map((t) => t.label), [
        'work pressure',
        'time outdoors',
      ]);
    },
  );

  test('diagnoses, sensitive inferences and invalid envelopes are refused', () {
    final src = source([
      'I felt low and could not sleep, the deadline slipped.',
    ]);
    final parsed = DiarySuggestions.parse(
      output(
        title: 'Signs of depression',
        mood: 'low',
        moodEvidence: '“I felt low”',
        themes: [
          ['insomnia disorder', 'could not sleep'],
          ['possible pregnancy', 'felt low'],
          ['work pressure', 'the deadline slipped'],
          ['Work pressure', 'the deadline slipped'],
        ].take(3).toList(),
      ),
      src,
    );
    expect(parsed.title, null);
    expect(parsed.mood.mood, DiaryCalendarMood.low);
    expect(parsed.themes.map((t) => t.label), ['work pressure']);
    expect(parsed.dropped, 3);
    for (final bad in [
      '',
      '{}',
      'not json',
      jsonEncode({...jsonDecode(output()) as Map, 'extra': true}),
      output(mood: 'depressed'),
      output(title: 'x' * 81),
      output(title: 'line\nbreak'),
      jsonEncode({
        ...jsonDecode(output()) as Map,
        'themes': List.filled(4, {'label': 'x', 'evidence': 'y'}),
      }),
      'x' * 2049,
    ]) {
      expect(
        () => DiarySuggestions.parse(bad, src),
        throwsA(anything),
        reason: bad.length > 60 ? bad.substring(0, 60) : bad,
      );
    }
  });

  test('accepted fields only; manual choices preserved; entries unchanged; stale, role and restart', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final item = app.diary.addTimelineItem(
      dateString: day,
      content: 'Proud of the walk by the river.',
    );
    app.diary.updateDayMetadata(
      dateString: day,
      dayMood: encodeDayMood(DiaryCalendarMood.calm),
    );
    final itemsBefore = app.diary.getDay(day)!.itemsJson;
    final snapshot = DiarySuggestionSource.fromDay(app.diary.getDay(day))!;
    app.diary.applyDaySuggestions(
      dateString: day,
      expectedSource: snapshot.encode(),
      dayTitle: 'River walk',
      dayThemes: encodeDayThemes(['time outdoors']),
    );
    var saved = app.diary.getDay(day)!;
    expect(saved.dayTitle, 'River walk');
    expect(saved.themes, ['time outdoors']);
    expect(decodeDayMood(saved.dayMood), DiaryCalendarMood.calm);
    expect(saved.itemsJson, itemsBefore);
    expect(saved.status, SyncStatus.pendingUpload);
    expect(app.storage.dirty('diary', day, 'metadata'), true);
    expect(DiaryCalendarDay.fromEntity(saved).mood, DiaryCalendarMood.calm);
    expect(saved.toSyncJson('phone')['day_themes'], '["time outdoors"]');
    expect(
      () => app.diary.applyDaySuggestions(
        dateString: day,
        expectedSource: snapshot.encode(),
      ),
      throwsStateError,
    );
    // Edited, added and deleted entries each invalidate the snapshot.
    app.diary.updateTimelineItem(
      dateString: day,
      itemUuid: item.itemUuid,
      content: 'Changed words.',
    );
    expect(
      () => app.diary.applyDaySuggestions(
        dateString: day,
        expectedSource: snapshot.encode(),
        dayTitle: 'Stale',
      ),
      throwsStateError,
    );
    final changed = DiarySuggestionSource.fromDay(app.diary.getDay(day))!;
    app.diary.addTimelineItem(dateString: day, content: 'Another.');
    expect(
      () => app.diary.applyDaySuggestions(
        dateString: day,
        expectedSource: changed.encode(),
        dayTitle: 'Stale',
      ),
      throwsStateError,
    );
    expect(app.diary.getDay(day)!.dayTitle, 'River walk');
    // Restart: reopen the same ObjectBox directory.
    final directory = app.db.store.directoryPath;
    app.db.close();
    final reopened = ObjectBox.fromStore(
      Store(getObjectBoxModel(), directory: directory),
    );
    addTearDown(reopened.close);
    final sync = SyncStateStore(
      storage: JournalSyncKeyValueStore(reopened.store),
      deviceId: 'phone',
      now: () => app.now,
    );
    final diary = DiaryRepository(
      db: reopened,
      device: TestDevice('phone'),
      sync: sync,
    );
    saved = diary.getDay(day)!;
    expect(saved.dayTitle, 'River walk');
    expect(saved.themes, ['time outdoors']);
    expect(decodeDayMood(saved.dayMood), DiaryCalendarMood.calm);
    sync.setPrimary(
      const PrimaryDevice(deviceId: 'other', deviceName: 'Other', fileId: 'p'),
    );
    expect(
      () => diary.applyDaySuggestions(
        dateString: day,
        expectedSource: DiarySuggestionSource.fromDay(saved)!.encode(),
        dayTitle: 'Secondary',
      ),
      throwsStateError,
    );
    expect(
      () => diary.updateDayMetadata(dateString: day, dayTitle: 'Secondary'),
      throwsStateError,
    );
    expect(diary.getDay(day)!.dayTitle, 'River walk');
  });

  test(
    'themes travel in sync documents and older documents stay unchanged',
    () {
      final plain = DiaryDayEntity(dateString: day);
      expect(plain.toSyncJson('phone').containsKey('day_themes'), false);
      final themed = DiaryDayEntity(
        dateString: day,
        dayThemes: encodeDayThemes(['rest', 'family']),
      );
      final remote = DiaryDayEntity.fromSyncJson(themed.toSyncJson('phone'));
      expect(remote.themes, ['rest', 'family']);
      expect(
        DiaryDayEntity(dateString: day, dayThemes: '{bad').themes,
        isEmpty,
      );
      expect(() => encodeDayThemes(['a', 'b', 'c', 'd']), throwsArgumentError);
      expect(() => encodeDayThemes(['x' * 41]), throwsArgumentError);
      expect(encodeDayThemes([' rest ', 'Rest', '']), '["rest"]');
    },
  );

  test('end to end: only the day is sent, stale results cannot save, accepted title persists', () async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    final item = app.diary.addTimelineItem(
      dateString: day,
      content: 'I was proud of the walk by the river this morning.',
    );
    app.diary.addTimelineItem(
      dateString: day,
      content: 'Then the deadline slipped and I felt flat all evening.',
    );
    app.diary.addTimelineItem(
      dateString: '2026-10-25',
      content: 'Unrelated private day.',
    );
    app.diary.updateDayMetadata(dateString: day, dayTitle: 'My own title');
    final store = summary.MemorySummaries();
    final wire = summary.SummaryTransport(store)
      ..output = output()
      ..phase = 'running';
    final container = diaryContainer(app, store, wire);
    addTearDown(container.dispose);
    final controller = container.read(noteSummaryProvider.notifier);
    await restored(container);
    await controller.startDiarySuggestion(day);
    final sent = wire.submitted.single;
    expect(sent['operation'], diarySuggestionOperation);
    final prompt = sent['prompt'] as String;
    expect(prompt, contains('proud of the walk'));
    expect(prompt, isNot(contains('Unrelated')));
    expect(prompt, isNot(contains('My own title')));
    expect(prompt, isNot(contains(item.itemUuid)));
    expect(prompt, isNot(contains(day)));
    expect(store.value!.localSource, isNot(contains('Unrelated')));
    // The source is edited while the computer is still generating.
    app.diary.updateTimelineItem(
      dateString: day,
      itemUuid: item.itemUuid,
      content: 'Rewritten while waiting.',
    );
    wire.phase = 'completed';
    await controller.retry();
    await settle();
    expect(container.read(noteSummaryProvider).phase, 'completed');
    expect(container.read(noteSummaryProvider).stale, true);
    expect(await controller.acceptDiarySuggestion(title: 'Stale title'), false);
    expect(app.diary.getDay(day)!.dayTitle, 'My own title');
    expect(
      app.diary.getDay(day)!.items.first.content,
      'Rewritten while waiting.',
    );
    await controller.clear();
    expect(store.value, null);

    // Fresh request against the current entries, then per-field acceptance.
    await controller.startDiarySuggestion(day);
    await waitFor(container, 'completed');
    expect(container.read(noteSummaryProvider).stale, false);
    final suggestions = controller.diarySuggestions()!;
    // The model's mood evidence no longer appears in the rewritten entry.
    expect(suggestions.mood.mood, null);
    expect(await controller.acceptDiarySuggestion(title: 'Edited by me'), true);
    final saved = app.diary.getDay(day)!;
    expect(saved.dayTitle, 'Edited by me');
    expect(saved.dayMood, null);
    expect(saved.dayThemes, null);
    expect(
      store.value,
      null,
      reason: 'accepted result is cleared and acknowledged',
    );
  });

  test(
    'unavailable model, old companion and secondary device send nothing',
    () async {
      final app = await SyncFixture.create(MemoryDrive(), 'phone');
      app.diary.addTimelineItem(dateString: day, content: 'A quiet day.');
      for (final connection in [
        () => DiaryConnection(modelStatus: 'needs_download'),
        () => DiaryConnection(contract: 0),
      ]) {
        final store = summary.MemorySummaries();
        final wire = summary.SummaryTransport(store);
        final container = diaryContainer(
          app,
          store,
          wire,
          connection: connection,
        );
        final controller = container.read(noteSummaryProvider.notifier);
        await restored(container);
        await controller.startDiarySuggestion(day);
        expect(wire.submitted, isEmpty);
        expect(store.value, null);
        expect(container.read(noteSummaryProvider).message, isNotNull);
        container.dispose();
      }
      makeSecondary(app);
      final store = summary.MemorySummaries();
      final wire = summary.SummaryTransport(store);
      final container = diaryContainer(app, store, wire);
      addTearDown(container.dispose);
      await restored(container);
      await container
          .read(noteSummaryProvider.notifier)
          .startDiarySuggestion(day);
      expect(wire.submitted, isEmpty);
      expect(
        container.read(noteSummaryProvider).message,
        contains('primary device'),
      );
    },
  );

  testWidgets(
    'review: mood disclaimer, edit then accept, reject, save; secondary is read-only',
    (tester) async {
      final app = (await tester.runAsync(
        () => SyncFixture.create(MemoryDrive(), 'phone'),
      ))!;
      app.diary.addTimelineItem(
        dateString: day,
        content: 'I felt calm after the walk by the river. Work was busy.',
      );
      final store = summary.MemorySummaries();
      final wire = summary.SummaryTransport(store)
        ..output = output(
          title: 'Walk by the river',
          mood: 'calm',
          moodEvidence: 'I felt calm',
          themes: [
            ['busy work', 'Work was busy'],
          ],
        );
      final container = diaryContainer(app, store, wire);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DiaryDetailsPage(dateString: day)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('diary-suggest')));
      for (
        var i = 0;
        i < 40 && container.read(noteSummaryProvider).phase != 'completed';
        i++
      ) {
        await tester.runAsync(settle);
        await tester.pump();
      }
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary-mood-disclaimer')),
        findsOneWidget,
      );
      // Nothing is written before an explicit save.
      expect(app.diary.getDay(day)!.dayTitle, null);
      // Title: edit, which also accepts the edited value.
      final title = find.byKey(const ValueKey('diary-review-title'));
      await tester.ensureVisible(title);
      await tester.tap(find.descendant(of: title, matching: find.text('Edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'River, then work');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      // Mood: accept. Themes: reject.
      final mood = find.byKey(const ValueKey('diary-review-mood'));
      await tester.ensureVisible(mood);
      await tester.tap(
        find.descendant(of: mood, matching: find.text('Accept')),
      );
      final rejectThemes = find.descendant(
        of: find.byKey(const ValueKey('diary-review-themes')),
        matching: find.text('Reject'),
      );
      await tester.ensureVisible(rejectThemes);
      await tester.pumpAndSettle();
      await tester.tap(rejectThemes);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('diary-suggest-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      final saved = app.diary.getDay(day)!;
      expect(saved.dayTitle, 'River, then work');
      expect(decodeDayMood(saved.dayMood), DiaryCalendarMood.calm);
      expect(saved.dayThemes, null);
      expect(
        find.byKey(const ValueKey('diary-details-current')),
        findsOneWidget,
      );
      expect(find.text('Title: River, then work'), findsOneWidget);

      // Manual override replaces the AI-chosen mood and adds a theme.
      await tester.tap(find.byKey(const ValueKey('diary-details-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('diary-manual-mood-tired')));
      await tester.enterText(
        find.byKey(const ValueKey('diary-manual-themes')),
        'rest',
      );
      await tester.tap(find.byKey(const ValueKey('diary-manual-save')));
      await tester.pumpAndSettle();
      expect(
        decodeDayMood(app.diary.getDay(day)!.dayMood),
        DiaryCalendarMood.tired,
      );
      expect(app.diary.getDay(day)!.themes, ['rest']);

      // Secondary devices can read details but cannot request or save.
      makeSecondary(app);
      final secondary = diaryContainer(app, summary.MemorySummaries(), wire);
      addTearDown(secondary.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: secondary,
          child: const MaterialApp(home: DiaryDetailsPage(dateString: day)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('diary-details-read-only')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('diary-details-edit')), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('diary-suggest')),
            )
            .onPressed,
        null,
      );
      await tester.pumpWidget(const SizedBox());
      // Cancels the debounced sync scheduled by the saves.
      app.container.dispose();
    },
  );
}
