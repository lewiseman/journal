// Opt-in synthetic J02 device demonstration. Run online against an isolated
// companion fixture, stop the companion, then rerun with J02_RESTART=true to
// prove the cached question after app restart and honest unavailability.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/questions/daily_question_controller.dart';
import 'package:journal/modules/diary/questions/daily_question_entity.dart';
import 'package:journal/modules/diary/questions/daily_question_prompt.dart';
import 'package:journal/modules/diary/views/widgets/diary_writing_prompt.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/controllers/notes_repository.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:journal/modules/settings/companion/companion_store.dart';
import 'package:journal/objectbox/objectbox.dart';
import 'package:journal/objectbox/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sync_wise/sync_wise.dart';

const _phone = 'j02-synthetic-phone';

class _Device extends Fake implements DeviceIdentityService {
  @override
  String get deviceId => _phone;
  @override
  String get deviceName => 'J02 synthetic phone';
}

class _Reset extends AccountResetController {
  _Reset() : super((_) => throw UnimplementedError());
  @override
  AccountResetState build() {
    ready = Future.value();
    return const AccountResetState();
  }
}

class _Preference implements DailyQuestionPreference {
  @override
  bool enabled = true;
  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

/// Real pinned transport that records what the phone submits.
class _Wire implements CompanionTransport {
  final inner = PinnedCompanionTransport();
  final submitted = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    if (method == 'POST' && route == '/v1/jobs' && body != null) {
      submitted.add(body);
    }
    return inner.request(
      endpoint,
      pin,
      method,
      route,
      body: body,
      headers: headers,
    );
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixture = String.fromEnvironment('RECOVERY_TRUSTED_COMPUTER');
  const restart = bool.fromEnvironment('J02_RESTART');
  testWidgets('J02 real questions or restart while unavailable', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final trust = ProtectedComputerStore(
      key: 'journal.companion.j02-demo.trust',
    );
    final protected = ProtectedSummaryStore(
      key: 'journal.companion.j02-demo.task',
    );
    final db = ObjectBox.fromStore(
      await openStore(directory: '${support.path}/j02-synthetic-objectbox'),
    );
    final sync = SyncStateStore(
      storage: MemorySyncKeyValueStore(),
      deviceId: _phone,
    );
    final notes = NotesRepository(db: db, device: _Device(), sync: sync);
    final diary = DiaryRepository(db: db, device: _Device(), sync: sync);
    final store = ObjectBoxSummaryStore(db.store, protected: protected);
    final wire = _Wire();
    final preference = _Preference();
    var now = DateTime.now();
    final today = DiaryRepository.formatDateKey(now);
    final yesterday = DiaryRepository.formatDateKey(
      DateTime(now.year, now.month, now.day - 1),
    );
    if (!restart) {
      expect(fixture, isNotEmpty);
      final trusted = TrustedComputer.fromJson(
        jsonDecode(fixture) as Map<String, dynamic>,
      );
      await trust.save(ComputerRecords([trusted], trusted.id));
      await store.clearAll();
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
      db.store.box<DailyQuestionEntity>().removeAll();
    }
    final container = ProviderContainer(
      overrides: [
        objectBoxProvider.overrideWithValue(db),
        syncStateStoreProvider.overrideWithValue(sync),
        notesRepositoryProvider.overrideWithValue(notes),
        diaryRepositoryProvider.overrideWithValue(diary),
        accountResetProvider.overrideWith(_Reset.new),
        syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
        companionStoreProvider.overrideWithValue(trust),
        summaryStoreProvider.overrideWithValue(store),
        companionTransportProvider.overrideWithValue(wire),
        dailyQuestionPreferenceProvider.overrideWithValue(preference),
        dailyQuestionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(() {
      container.dispose();
      wire.close();
      db.close();
    });
    Future<void> show(String day) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.indigo),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: DailyQuestionPrompt(
                key: ValueKey(day),
                day: day,
                onWrite: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final controller = container.read(dailyQuestionProvider.notifier);
    // Raw model output for each completed task, to explain rejections.
    final raw = <String>[];
    container.listen(noteSummaryProvider, (_, next) {
      if (next.handle?.isDailyQuestion == true &&
          next.phase == 'completed' &&
          next.text != null &&
          (raw.isEmpty || raw.last != next.text)) {
        raw.add(next.text!);
      }
    });
    NoteSummaryState task() => container.read(noteSummaryProvider);
    Future<void> waitFor(bool Function() done, [int seconds = 150]) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('J02 timeout: ${task().phase} ${task().message}');
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> tapKey(String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Asks through the real page and waits for the slot to be released.
    Future<Map<String, dynamic>> ask(String key) async {
      final posts = wire.submitted.length;
      await tapKey(key);
      await waitFor(
        () =>
            wire.submitted.length > posts &&
            task().handle == null &&
            !task().busy,
      );
      await tester.pump(const Duration(seconds: 1));
      final view = controller.current(today);
      return {
        'question': view?.question.text,
        'grounded': view?.question.grounded,
        'ago': view?.question.ago,
        'sourceLabel': view == null
            ? null
            : DailyQuestionPrompt.sourceLabel(view.question),
        'notShownBecause': view == null
            ? container.read(dailyQuestionProvider).message
            : null,
        'sent': jsonDecode(wire.submitted.last['prompt'] as String),
        'raw': raw.isEmpty ? null : jsonDecode(raw.last),
      };
    }

    final report = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'physicalAndroid': Platform.isAndroid,
      'restartPhase': restart,
      'syntheticSourceAndTrust': true,
    };
    if (restart) {
      final cached = controller.current(today);
      expect(cached, isNotNull);
      await show(today);
      container.read(companionControllerProvider);
      await waitFor(() => !task().busy, 30);
      expect(find.text(cached!.question.text), findsOneWidget);
      report['cachedQuestionShownAfterRestart'] = cached.question.text;
      await tapKey('daily-question-another');
      await waitFor(
        () =>
            !task().busy &&
            container.read(dailyQuestionProvider).message != null,
        60,
      );
      expect(wire.submitted, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      // A failed replacement never takes away today's question.
      expect(find.text(cached.question.text), findsOneWidget);
      report['cachedQuestionKeptWhenReplacementFailed'] = true;
      report['unavailableComputerMessage'] = container
          .read(dailyQuestionProvider)
          .message;
      expect(
        find.byKey(const ValueKey('diary-writing-prompt')),
        findsOneWidget,
      );
      report['writingStillAvailable'] = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await store.clearAll();
      await trust.save(const ComputerRecords([], null));
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
      db.store.box<DailyQuestionEntity>().removeAll();
      report['isolatedDataAndTrustCleaned'] = true;
    } else {
      final source = diary.addTimelineItem(
        dateString: yesterday,
        content:
            'Packed the last boxes. The move to the new flat is on Saturday.',
      );
      await show(today);
      container.read(companionControllerProvider);
      container.read(dailyQuestionProvider);
      await waitFor(
        () =>
            container.read(companionControllerProvider).phase ==
                CompanionPhase.connected &&
            !task().busy,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('daily-question-disclosure')),
        findsOneWidget,
      );
      report['disclosure'] =
          (tester
                  .widget<Text>(
                    find.byKey(const ValueKey('daily-question-disclosure')),
                  )
                  .data)
              .toString();

      // Grounded follow-up on yesterday's entry.
      final first = await ask('daily-question-ask');
      report['groundedAsk'] = first;
      final prompt = wire.submitted.last['prompt'] as String;
      expect(prompt, isNot(contains(source.itemUuid)));
      expect(prompt, isNot(contains(yesterday)));
      expect(prompt, isNot(contains(today)));
      report['onlyDisclosedSelectionSent'] = true;

      // Another: the previous question goes to the avoid list.
      final view = controller.current(today);
      if (view != null) {
        final second = await ask('daily-question-another');
        expect((second['sent'] as Map)['avoid'], contains(view.question.text));
        report['anotherQuestion'] = second;
      }

      // Source deletion hides a grounded question.
      final grounded = controller.current(today);
      if (grounded?.question.grounded == true) {
        diary.deleteTimelineItem(
          dateString: grounded!.question.sourceDate!,
          itemUuid: grounded.question.sourceItem!,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(controller.current(today), null);
        expect(find.text(DiaryWritingPrompt.question), findsOneWidget);
        report['sourceDeletionHidQuestion'] = true;
      }

      // No history left: a general question still helps start writing.
      db.diaryBox.removeAll();
      await show(today);
      await tester.pump(const Duration(seconds: 1));
      if (controller.current(today) != null) {
        await tapKey('daily-question-skip');
      }
      final general = await ask('daily-question-ask');
      expect((general['sent'] as Map)['prior'], isEmpty);
      report['noHistoryAsk'] = general;

      // A later civil day (for example after travelling) shows no stale question.
      now = now.add(const Duration(days: 1));
      final tomorrow = DiaryRepository.formatDateKey(now);
      await show(tomorrow);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.current(tomorrow), null);
      expect(find.text(DiaryWritingPrompt.question), findsOneWidget);
      report['dateChangeShowsNoStaleQuestion'] = true;
      now = now.subtract(const Duration(days: 1));

      // Opt-out deletes history and returns to the plain prompt only.
      await controller.setEnabled(false);
      await show(today);
      await tester.pump(const Duration(seconds: 1));
      expect(db.store.box<DailyQuestionEntity>().count(), 0);
      expect(find.byKey(const ValueKey('daily-question-ask')), findsNothing);
      final before = wire.submitted.length;
      await controller.request(today);
      expect(wire.submitted.length, before);
      report['optOutDeletedHistoryAndSentNothing'] = true;

      // Re-enable and leave one cached question for the restart phase.
      await controller.setEnabled(true);
      diary.addTimelineItem(
        dateString: yesterday,
        content: 'Started a pottery class with Ana.',
      );
      await show(today);
      await tester.pump(const Duration(seconds: 1));
      var last = await ask('daily-question-ask');
      for (var i = 0; i < 2 && last['question'] == null; i++) {
        last = await ask('daily-question-ask');
      }
      expect(controller.current(today), isNotNull);
      report['cachedForRestart'] = last['question'];
      report['realPinnedTlsAndQvacRequests'] = wire.submitted.length;
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await File(
      '${support.path}/j02-device-${restart ? 'restart' : 'online'}.json',
    ).writeAsString(jsonEncode(report));
    debugPrint('J02_DEVICE_EVIDENCE ${jsonEncode(report)}');
    expect(tester.takeException(), null);
  });
}
