import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/diary/history/diary_history_contract.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'diary_history_test.dart' as h;
import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

/// Holds acknowledgments until [gate] completes, like a slow network.
class SlowAckTransport extends summary.SummaryTransport {
  SlowAckTransport(super.store);
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>> request(
    Uri endpoint,
    String pin,
    String method,
    String route, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    if (route.endsWith('/ack') && gate != null) await gate!.future;
    // Like the companion, an unknown ID is not found.
    if (method == 'GET' &&
        route.startsWith('/v1/jobs/') &&
        job != null &&
        route.split('/')[3] != job!['id']) {
      throw const CompanionFailure('NOT_FOUND', 'Not found');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => NoteSummaryController.settleLimit = const Duration(seconds: 25),
  );

  Future<
    ({
      SyncFixture app,
      SlowAckTransport wire,
      summary.MemorySummaries store,
      DiaryHistorySelection selection,
    })
  >
  setUp() async {
    final app = await SyncFixture.create(MemoryDrive(), 'phone');
    app.diary.addTimelineItem(
      dateString: '2025-10-20',
      content: 'First pottery class.',
    );
    final store = summary.MemorySummaries();
    final wire = SlowAckTransport(store)
      ..output = h.answer('You wrote about pottery.', ['s0']);
    final selection = DiaryHistorySelection.select(
      question: 'pottery',
      today: h.today,
      days: app.diary.getAllDays(),
    );
    return (app: app, wire: wire, store: store, selection: selection);
  }

  test(
    'clear waits for an in-flight retrieval instead of being ignored',
    () async {
      final t = await setUp();
      final c = h.historyContainer(t.app, t.store, t.wire);
      addTearDown(c.dispose);
      await h.restored(c);
      final controller = c.read(noteSummaryProvider.notifier);
      await controller.startDiaryAnswer(t.selection);
      await h.finished(c);
      expect(c.read(noteSummaryProvider).phase, 'completed');
      // A retrieval is in flight when the user taps Clear.
      t.wire.pendingGet = Completer();
      unawaited(controller.retry());
      await h.settle();
      final clearing = controller.clear();
      await h.settle();
      expect(c.read(noteSummaryProvider).handle, isNotNull);
      final pending = t.wire.pendingGet!;
      t.wire.pendingGet = null;
      pending.complete({
        ...t.wire.job!,
        'state': 'completed',
        'text': t.wire.output,
      });
      await clearing;
      expect(c.read(noteSummaryProvider).handle, null);
      expect(t.store.value, null);
    },
  );

  test(
    'a start that stays busy past the limit reports it and sends nothing',
    () async {
      NoteSummaryController.settleLimit = const Duration(milliseconds: 100);
      final t = await setUp();
      final c = h.historyContainer(t.app, t.store, t.wire);
      addTearDown(c.dispose);
      await h.restored(c);
      final controller = c.read(noteSummaryProvider.notifier);
      await controller.startDiaryAnswer(t.selection);
      await h.finished(c);
      t.wire.pendingGet = Completer();
      unawaited(controller.retry());
      await h.settle();
      await controller.clear();
      expect(c.read(noteSummaryProvider).message, contains('Tap Clear again'));
      expect(c.read(noteSummaryProvider).handle, isNotNull);
      t.wire.pendingGet!.complete({
        ...t.wire.job!,
        'state': 'completed',
        'text': t.wire.output,
      });
      t.wire.pendingGet = null;
      await h.settle();
      await controller.clear();
      expect(c.read(noteSummaryProvider).handle, null);
    },
  );

  test(
    'clear frees the slot before a slow acknowledgment; a new task starts',
    () async {
      final t = await setUp();
      final c = h.historyContainer(t.app, t.store, t.wire);
      addTearDown(c.dispose);
      await h.restored(c);
      final controller = c.read(noteSummaryProvider.notifier);
      await controller.startDiaryAnswer(t.selection);
      await h.finished(c);
      t.wire.gate = Completer();
      final clearing = controller.clear();
      await h.settle();
      // The slot is free while the acknowledgment is still waiting.
      expect(c.read(noteSummaryProvider).handle, null);
      await controller.startDiaryAnswer(t.selection);
      expect(t.wire.posts, 2);
      t.wire.gate!.complete();
      await clearing;
      // The late acknowledgment does not wipe the new task.
      expect(c.read(noteSummaryProvider).handle, isNotNull);
    },
  );

  test('a start during startup restore waits for it, then sends', () async {
    final t = await setUp();
    t.store.pending = Completer();
    final c = h.historyContainer(t.app, t.store, t.wire);
    addTearDown(c.dispose);
    c.read(noteSummaryProvider);
    await h.settle();
    expect(c.read(noteSummaryProvider).phase, 'restoring');
    final starting = c
        .read(noteSummaryProvider.notifier)
        .startDiaryAnswer(t.selection);
    await h.settle();
    expect(t.wire.posts, 0);
    t.store.pending!.complete(null);
    t.store.pending = null;
    await starting;
    expect(t.wire.posts, 1);
  });

  test(
    'a start still busy after the limit says so and sends nothing',
    () async {
      NoteSummaryController.settleLimit = const Duration(milliseconds: 100);
      final t = await setUp();
      t.store.pending = Completer();
      final c = h.historyContainer(t.app, t.store, t.wire);
      addTearDown(c.dispose);
      c.read(noteSummaryProvider);
      await h.settle();
      await c.read(noteSummaryProvider.notifier).startDiaryAnswer(t.selection);
      expect(t.wire.posts, 0);
      expect(
        c.read(noteSummaryProvider).message,
        contains('Nothing new was sent'),
      );
      t.store.pending!.complete(null);
    },
  );
}
