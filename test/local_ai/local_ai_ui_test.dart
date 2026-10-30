import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/modules/local_ai/core/ai_settings.dart';
import 'package:journal/modules/local_ai/core/engine_registry.dart';
import 'package:journal/modules/local_ai/ui/device_mode_selector.dart';
import 'package:journal/modules/local_ai/ui/device_task_card.dart';

import 'fake_engine.dart';

class UiSettings extends AiSettingsController {
  @override
  AiSettings build() => const AiSettings();
  @override
  Future<void> setMode(AiMode mode) async {
    state = AiSettings(mode: mode);
  }
}

class RemovedEngineSettings extends UiSettings {
  @override
  AiSettings build() => const AiSettings(mode: AiMode.device);
}

void main() {
  testWidgets('removing an engine requires an explicit provider choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onDeviceEngineProvider.overrideWithValue(null),
          aiSettingsProvider.overrideWith(RemovedEngineSettings.new),
        ],
        child: const MaterialApp(home: Scaffold(body: DeviceModeSelector())),
      ),
    );
    expect(find.text('On this phone'), findsNothing);
    expect(find.text('Use Companion'), findsOneWidget);
    await tester.tap(find.text('Use Companion'));
    await tester.pump();
    expect(find.text('Use Companion'), findsNothing);
  });
  testWidgets(
    'empty registry hides device setup without consulting native storage',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [onDeviceEngineProvider.overrideWithValue(null)],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(children: [DeviceModeSelector(), DeviceAiSection()]),
            ),
          ),
        ),
      );
      expect(find.text('On this phone'), findsNothing);
      expect(find.text('Manage models'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'provider selection works on a narrow screen with a replacement engine',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onDeviceEngineProvider.overrideWithValue(FakeOnDeviceEngine()),
            aiSettingsProvider.overrideWith(UiSettings.new),
          ],
          child: const MaterialApp(home: Scaffold(body: DeviceModeSelector())),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('ai-mode-device')));
      await tester.pumpAndSettle();
      expect(find.text('On this phone'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-use-device')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Keep Journal in the foreground'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
