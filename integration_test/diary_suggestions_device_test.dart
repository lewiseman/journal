// Opt-in synthetic J01 device demonstration. Run online against an isolated
// companion fixture, stop the companion, then rerun with J01_RESTART=true to
// prove persistence after app restart and honest behavior while unavailable.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:journal/modules/diary/controllers/diary_providers.dart';
import 'package:journal/modules/diary/controllers/diary_repository.dart';
import 'package:journal/modules/diary/models/diary_calendar_day.dart';
import 'package:journal/modules/diary/suggestions/diary_details_page.dart';
import 'package:journal/modules/diary/suggestions/diary_suggestion_contract.dart';
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

const _phone = 'j01-synthetic-phone';
const _ordinary = '2026-10-21', _mixed = '2026-10-20', _sparse = '2026-10-22';

class _Device extends Fake implements DeviceIdentityService {
  @override
  String get deviceId => _phone;
  @override
  String get deviceName => 'J01 synthetic phone';
}

class _Reset extends AccountResetController {
  _Reset() : super((_) => throw UnimplementedError());
  @override
  AccountResetState build() {
    ready = Future.value();
    return const AccountResetState();
  }
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
  const restart = bool.fromEnvironment('J01_RESTART');
  testWidgets('J01 real suggestions or restart while unavailable', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final trust = ProtectedComputerStore(
      key: 'journal.companion.j01-demo.trust',
    );
    final protected = ProtectedSummaryStore(
      key: 'journal.companion.j01-demo.task',
    );
    final db = ObjectBox.fromStore(
      await openStore(directory: '${support.path}/j01-synthetic-objectbox'),
    );
    final sync = SyncStateStore(
      storage: MemorySyncKeyValueStore(),
      deviceId: _phone,
    );
    final notes = NotesRepository(db: db, device: _Device(), sync: sync);
    final diary = DiaryRepository(db: db, device: _Device(), sync: sync);
    final store = ObjectBoxSummaryStore(db.store, protected: protected);
    final wire = _Wire();
    if (!restart) {
      expect(fixture, isNotEmpty);
      final trusted = TrustedComputer.fromJson(
        jsonDecode(fixture) as Map<String, dynamic>,
      );
      await trust.save(ComputerRecords([trusted], trusted.id));
      await store.clearAll();
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
    }
    ProviderContainer scope(SyncDeviceRole role) => ProviderContainer(
      overrides: [
        objectBoxProvider.overrideWithValue(db),
        syncStateStoreProvider.overrideWithValue(sync),
        notesRepositoryProvider.overrideWithValue(notes),
        diaryRepositoryProvider.overrideWithValue(diary),
        accountResetProvider.overrideWith(_Reset.new),
        syncDeviceRoleProvider.overrideWithValue(role),
        companionStoreProvider.overrideWithValue(trust),
        summaryStoreProvider.overrideWithValue(store),
        companionTransportProvider.overrideWithValue(wire),
      ],
    );
    var container = scope(SyncDeviceRole.primary);
    addTearDown(() {
      container.dispose();
      wire.close();
      db.close();
    });
    Future<void> show(String date) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.indigo),
          // A fresh route per day, as navigation creates in the app.
          home: DiaryDetailsPage(key: ValueKey(date), dateString: date),
        ),
      ),
    );
    NoteSummaryState state() => container.read(noteSummaryProvider);
    var controller = container.read(noteSummaryProvider.notifier);
    Future<void> waitFor(bool Function() done, [int seconds = 150]) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('J01 timeout: ${state().phase} ${state().message}');
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    // The page is a lazy list: build off-screen controls before tapping.
    Future<void> reveal(Finder target) async {
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          target,
          150,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
      }
    }

    Future<void> tapKey(String key) async {
      final target = find.byKey(ValueKey(key));
      await reveal(target);
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> tapIn(String key, String label) async {
      final target = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.text(label),
      );
      await reveal(find.byKey(ValueKey(key)));
      await reveal(target);
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Map<String, dynamic> describe(DiarySuggestions? s) => {
      'title': s?.title,
      'mood': s?.mood.value,
      'savedMood': s?.mood.mood?.name,
      'themes': [for (final t in s?.themes ?? const []) t.label],
      'dropped': s?.dropped,
    };

    final report = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'physicalAndroid': Platform.isAndroid,
      'restartPhase': restart,
      'syntheticSourceAndTrust': true,
    };
    if (restart) {
      // Fresh process: details accepted and overridden earlier persist.
      final day = diary.getDay(_ordinary)!;
      expect(decodeDayMood(day.dayMood), DiaryCalendarMood.tired);
      expect(day.themes, ['rest']);
      expect(day.items.map((i) => i.content).toList(), [
        'Made pancakes with Sam before school.',
        'Quiet afternoon reading on the balcony. I felt calm.',
      ]);
      report['persistedAfterAppRestart'] = {
        'title': day.dayTitle,
        'mood': decodeDayMood(day.dayMood)?.name,
        'themes': day.themes,
      };
      await show(_ordinary);
      container.read(companionControllerProvider);
      await waitFor(() => !state().busy, 30);
      await tapKey('diary-suggest');
      await waitFor(() => !state().busy && state().message != null, 60);
      expect(state().handle, null);
      report['unavailableCompanionMessage'] = state().message;
      report['unavailableCompanionAcceptedWork'] = false;
      // Manual editing still works without the computer.
      await tapKey('diary-details-edit');
      await tester.enterText(
        find.byKey(const ValueKey('diary-manual-title')),
        'Edited offline',
      );
      await tapKey('diary-manual-save');
      expect(diary.getDay(_ordinary)!.dayTitle, 'Edited offline');
      report['manualEditWithoutComputer'] = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await store.clearAll();
      await trust.save(const ComputerRecords([], null));
      db.noteBox.removeAll();
      db.diaryBox.removeAll();
      report['isolatedDataAndTrustCleaned'] = true;
    } else {
      final ordinary = [
        diary.addTimelineItem(
          dateString: _ordinary,
          content: 'Made pancakes with Sam before school.',
        ),
        diary.addTimelineItem(
          dateString: _ordinary,
          content: 'Quiet afternoon reading on the balcony. I felt calm.',
        ),
      ];
      diary.addTimelineItem(
        dateString: _mixed,
        content: 'I was proud of the walk by the river this morning.',
      );
      diary.addTimelineItem(
        dateString: _mixed,
        content: 'Then the deadline slipped and I felt flat all evening.',
      );
      diary.addTimelineItem(dateString: _sparse, content: 'Lunch.');

      // Ordinary day through the real page: request, review, accept, save.
      await show(_ordinary);
      container.read(companionControllerProvider);
      await waitFor(
        () =>
            container.read(companionControllerProvider).phase ==
                CompanionPhase.connected &&
            !state().busy,
      );
      await tester.pump(const Duration(seconds: 1));
      await tapKey('diary-suggest');
      await waitFor(() => state().terminal);
      expect(state().phase, 'completed');
      await tester.pump(const Duration(seconds: 1));
      final sent = wire.submitted.single;
      final prompt = sent['prompt'] as String;
      expect(sent['operation'], diarySuggestionOperation);
      expect(prompt, contains('pancakes'));
      expect(prompt, isNot(contains(_ordinary)));
      expect(prompt, isNot(contains('proud of the walk')));
      for (final item in ordinary) {
        expect(prompt, isNot(contains(item.itemUuid)));
      }
      report['onlySelectedDayEntryTextSent'] = true;
      await reveal(find.byKey(const ValueKey('diary-mood-disclaimer')));
      expect(
        find.byKey(const ValueKey('diary-mood-disclaimer')),
        findsOneWidget,
      );
      final suggestions = controller.diarySuggestions();
      report['ordinary'] = describe(suggestions);
      expect(diary.getDay(_ordinary)!.dayTitle, null);
      if (suggestions?.title != null) {
        await tapIn('diary-review-title', 'Accept');
      }
      if (suggestions?.mood.mood != null) {
        await tapIn('diary-review-mood', 'Accept');
      }
      await tapKey('diary-suggest-save');
      await waitFor(() => state().handle == null, 20);
      await tester.pump(const Duration(seconds: 1));
      final saved = diary.getDay(_ordinary)!;
      expect(saved.dayTitle, suggestions?.title);
      expect(decodeDayMood(saved.dayMood), suggestions?.mood.mood);
      expect(saved.items.map((i) => i.content).toList(), [
        'Made pancakes with Sam before school.',
        'Quiet afternoon reading on the balcony. I felt calm.',
      ]);
      report['ordinaryAcceptedThroughUiAndEntriesUnchanged'] = true;

      // Mixed and sparse days: record grounded results, then reject all.
      for (final date in [_mixed, _sparse]) {
        await show(date);
        await tester.pump(const Duration(seconds: 1));
        await tapKey('diary-suggest');
        await waitFor(() => state().terminal);
        expect(state().phase, 'completed');
        await tester.pump(const Duration(seconds: 1));
        final result = controller.diarySuggestions();
        report[date == _mixed ? 'mixed' : 'sparse'] = describe(result);
        if (date == _sparse && result!.empty) {
          await reveal(find.byKey(const ValueKey('diary-suggest-empty')));
          expect(
            find.byKey(const ValueKey('diary-suggest-empty')),
            findsOneWidget,
          );
        }
        await tapKey('diary-suggest-clear');
        await waitFor(() => state().handle == null, 20);
        final day = diary.getDay(date)!;
        expect(day.dayTitle, null);
        expect(day.dayMood, null);
        expect(day.dayThemes, null);
      }
      report['mixedAndSparseRejectedWithoutWrites'] = true;

      // Editing an entry during generation makes the result unsavable.
      final title = diary.getDay(_ordinary)!.dayTitle;
      await show(_ordinary);
      await tester.pump(const Duration(seconds: 1));
      final phases = <String>[];
      final watch = container.listen(noteSummaryProvider, (_, next) {
        if (phases.isEmpty || phases.last != next.phase) phases.add(next.phase);
      });
      final posted = wire.submitted.length;
      await tapKey('diary-suggest');
      // Edit only once the computer has accepted the work.
      await waitFor(
        () =>
            wire.submitted.length > posted &&
            ['accepted', 'queued', 'running'].contains(state().phase),
      );
      diary.updateTimelineItem(
        dateString: _ordinary,
        itemUuid: ordinary.first.itemUuid,
        content: 'Made waffles with Sam before school.',
      );
      await waitFor(() => state().terminal);
      watch.close();
      report['editDuringGenerationPhases'] = phases;
      report['editDuringGenerationPosts'] = wire.submitted.length - posted;
      await tester.pump(const Duration(seconds: 1));
      expect(state().stale, true);
      await reveal(find.byKey(const ValueKey('diary-suggest-stale')));
      expect(find.byKey(const ValueKey('diary-suggest-stale')), findsOneWidget);
      expect(await controller.acceptDiarySuggestion(title: 'Stale'), false);
      expect(diary.getDay(_ordinary)!.dayTitle, title);
      await tapKey('diary-suggest-clear');
      await waitFor(() => state().handle == null, 20);
      diary.updateTimelineItem(
        dateString: _ordinary,
        itemUuid: ordinary.first.itemUuid,
        content: 'Made pancakes with Sam before school.',
      );
      report['editDuringGenerationRefused'] = true;

      // Manual override replaces the accepted mood and adds a theme.
      await show(_ordinary);
      await tester.pump(const Duration(seconds: 1));
      await tapKey('diary-details-edit');
      await tapKey('diary-manual-mood-tired');
      await tester.enterText(
        find.byKey(const ValueKey('diary-manual-themes')),
        'rest',
      );
      await tapKey('diary-manual-save');
      expect(
        decodeDayMood(diary.getDay(_ordinary)!.dayMood),
        DiaryCalendarMood.tired,
      );
      expect(diary.getDay(_ordinary)!.themes, ['rest']);
      expect(diary.getDay(_ordinary)!.dayTitle, title);
      report['manualOverride'] = true;

      // A secondary device can read details but sends nothing.
      sync.setPrimary(
        const PrimaryDevice(
          deviceId: 'other',
          deviceName: 'Other',
          fileId: 'test-only',
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      container = scope(SyncDeviceRole.secondary);
      controller = container.read(noteSummaryProvider.notifier);
      await show(_ordinary);
      container.read(companionControllerProvider);
      await waitFor(
        () =>
            container.read(companionControllerProvider).phase ==
                CompanionPhase.connected &&
            !state().busy,
        60,
      );
      await reveal(find.byKey(const ValueKey('diary-details-read-only')));
      expect(
        find.byKey(const ValueKey('diary-details-read-only')),
        findsOneWidget,
      );
      final before = wire.submitted.length;
      await controller.startDiarySuggestion(_ordinary);
      expect(wire.submitted.length, before);
      expect(state().message, contains('primary device'));
      report['secondaryReadOnlySentNothing'] = true;
      sync.setPrimary(
        const PrimaryDevice(
          deviceId: _phone,
          deviceName: 'J01',
          fileId: 'test-only',
        ),
      );
      report['realPinnedTlsAndQvacRequests'] = wire.submitted.length;
      report['readyForRestart'] = true;
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await File(
      '${support.path}/j01-device-${restart ? 'restart' : 'online'}.json',
    ).writeAsString(jsonEncode(report));
    debugPrint('J01_DEVICE_EVIDENCE ${jsonEncode(report)}');
    expect(tester.takeException(), null);
  });
}
