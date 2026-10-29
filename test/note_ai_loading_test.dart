import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_loading.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';

Widget _page({
  bool reduced = true,
  bool active = true,
  bool dark = false,
  double scale = 1,
  String phase = 'running',
  VoidCallback? onCancel,
  VoidCallback? onRetry,
}) => MaterialApp(
  theme: dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduced,
      textScaler: TextScaler.linear(scale),
    ),
    child: TickerMode(enabled: active, child: child!),
  ),
  home: NoteAiScaffold(
    tool: NoteAiTool.writing,
    loading: NoteAiLoading(
      tool: NoteAiTool.writing,
      phase: phase,
      onCancel: onCancel,
      onRetry: onRetry,
    ),
    children: const [Text('Form')],
  ),
);

void main() {
  test('accepted work is loading even between polls; terminal and error phases are not', () {
    for (final phase in [
      'submitting',
      'restoring',
      'retrieving',
      'queued',
      'accepted',
      'running',
      'preparing',
      'saving',
    ]) {
      expect(noteAiIsLoading(phase, busy: false), isTrue, reason: phase);
    }
    for (final phase in [
      'idle',
      'completed',
      'failed',
      'cancelled',
      'expired',
      'interrupted',
      'error',
      'storageError',
    ]) {
      expect(noteAiIsLoading(phase, busy: true), isFalse, reason: phase);
    }
  });

  testWidgets(
    'loading reports its task phase and exposes the supplied controls',
    (tester) async {
      var stops = 0, retries = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _page(
          phase: 'queued',
          onCancel: () => stops++,
          onRetry: () => retries++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Waiting to begin…'), findsOneWidget);
      expect(find.text('Form'), findsNothing);
      expect(
        find.bySemanticsLabel('Waiting. Waiting to begin…'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Stop'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(stops, 1);
      expect(retries, 1);
      semantics.dispose();
    },
  );

  testWidgets(
    'motion stops when reduced or covered and disposes without a ticker',
    (tester) async {
      await tester.pumpWidget(_page(reduced: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(_page(reduced: false, active: false));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a small dark screen with large text can reach Stop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_page(dark: true, scale: 2, onCancel: () {}));
    await tester.pumpAndSettle();
    final stop = find.widgetWithText(TextButton, 'Stop');
    await tester.scrollUntilVisible(
      stop.hitTestable(),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.getSize(stop).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
