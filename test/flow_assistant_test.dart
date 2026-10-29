import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/assistant/qvac_assistant.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';
import 'package:journal/modules/flow/controllers/thoughts_providers.dart';
import 'package:journal/modules/flow/reflection/thought_reflection_controller.dart';
import 'package:journal/modules/flow/views/pages/flow_page.dart';
import 'package:journal/modules/flow/views/widgets/flow_assistant.dart';
import 'package:journal/modules/notes/controllers/notes_ctrl.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_store.dart';
import 'package:journal/modules/voice/voice.dart';
import 'package:journal/modules/recall/recall_question_contract.dart'
    show RecallKind;
import 'package:journal/modules/recall/recall_question_page.dart';
import 'package:journal/modules/root/controllers/sync_providers.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:sync_wise/sync_wise.dart';

import 'recall_question_test.dart' show QuestionConnection;
import 'note_summary_test.dart' as summary;
import 'support/sync_fixture.dart';

Future<summary.SummaryTransport> _mount(WidgetTester tester) async {
  final app = (await tester.runAsync(
    () => SyncFixture.create(MemoryDrive(), 'phone'),
  ))!;
  app.thoughts.saveThought(content: 'Worried about the move.');
  final store = summary.MemorySummaries();
  final wire = summary.SummaryTransport(store);
  final scope = ProviderContainer(
    overrides: [
      objectBoxProvider.overrideWithValue(app.db),
      syncStateStoreProvider.overrideWithValue(app.storage),
      notesRepositoryProvider.overrideWithValue(app.notes),
      thoughtsRepositoryProvider.overrideWithValue(app.thoughts),
      thoughtReflectionAvailableProvider.overrideWithValue(false),
      summaryStoreProvider.overrideWithValue(store),
      companionTransportProvider.overrideWithValue(wire),
      companionControllerProvider.overrideWith(QuestionConnection.new),
      accountResetProvider.overrideWith(summary.TestReset.new),
      syncDeviceRoleProvider.overrideWithValue(SyncDeviceRole.primary),
    ],
  );
  scope.read(noteSummaryProvider);
  await tester.runAsync(summary.settle);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final assistant = scope.read(qvacAssistantProvider);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [QvacAssistantObserver(assistant)],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: QvacAssistantHost(
            controller: assistant,
            navigatorKey: nav,
            child: child!,
          ),
        ),
        home: const QvacAssistantPage(
          label: 'Flow',
          root: true,
          child: Scaffold(body: FlowPage()),
        ),
      ),
    ),
  );
  await tester.runAsync(summary.settle);
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
    app.container.dispose();
  });
  return wire;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('qvac-assistant-button')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Flow has no search icon or mic; its sheet offers Voice and Flow AI search',
    (tester) async {
      final wire = await _mount(tester);
      expect(find.byIcon(Icons.search_rounded), findsNothing);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      await _openSheet(tester);
      expect(find.byType(FlowAssistant), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Flow AI search'), findsOneWidget);
      // Both actions sit side by side above the fold of the shorter sheet.
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('flow-assistant-voice')))
            .dy,
        tester
            .getTopLeft(find.byKey(const ValueKey('flow-assistant-search')))
            .dy,
      );
      await tester.tap(find.byKey(const ValueKey('flow-assistant-search')));
      await tester.pumpAndSettle();
      expect(find.byType(QvacAssistantSheet), findsNothing);
      final page = tester.widget<RecallQuestionPage>(
        find.byType(RecallQuestionPage),
      );
      expect(page.kind, RecallKind.thought);
      expect(
        find.byKey(const ValueKey('recall-question-field')),
        findsOneWidget,
      );
      expect(wire.posts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Voice closes the sheet and opens full-screen capture', (
    tester,
  ) async {
    await _mount(tester);
    await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('flow-assistant-voice')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(QvacAssistantSheet), findsNothing);
    final voice = tester.widget<VoiceSessionPage>(
      find.byType(VoiceSessionPage),
    );
    expect(voice.mode, VoiceSessionMode.transcription);
    expect(voice.target, 'flow');
    expect(find.byTooltip('Record'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceSessionPage), findsNothing);
    expect(find.byType(FlowPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
