import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/local_ai/core/ai_settings.dart';
import 'package:journal/modules/local_ai/core/engine_registry.dart';
import 'package:journal/modules/local_ai/core/on_device_engine.dart';
import 'package:journal/modules/local_ai/models/model_catalog.dart';
import 'package:journal/modules/local_ai/models/model_storage.dart';
import 'package:journal/modules/local_ai/ui/device_models_page.dart';

import 'local_ai/fake_engine.dart';

import 'package:journal/modules/recall/recall_indexer.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart';
import 'package:journal/modules/notes/summary/summary_history_page.dart';
import 'package:journal/modules/voice/views/pages/reply_voice_page.dart';
import 'package:journal/modules/settings/companion/companion_detail_pages.dart';
import 'package:journal/modules/settings/companion/companion_controller.dart';
import 'package:journal/modules/settings/companion/companion_discovery.dart';
import 'package:journal/modules/settings/companion/companion_guide_voice.dart';
import 'package:journal/modules/settings/companion/companion_page.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class _Connection extends CompanionController {
  @override
  CompanionState build() => const CompanionState(phase: CompanionPhase.idle);
  int scans = 0, pairs = 0, retries = 0, cancels = 0, forgets = 0;
  String? pairedId;
  bool? resume;
  void update(CompanionState value) => state = value;
  @override
  Future<void> discover() async {
    scans++;
    state = state.copyWith(
      discovered: [
        DiscoveredComputer(
          name: 'Nearby Mac',
          id: 'nearby',
          version: '1',
          pin: 'a' * 64,
          endpoints: [Uri.parse('https://192.168.1.2:1234')],
        ),
      ],
    );
  }

  @override
  Future<void> pair(String raw, String phoneName, {String? expectedId}) async {
    pairs++;
    pairedId = PairingCode.parse(raw).id;
    state = const CompanionState(
      phase: CompanionPhase.pairing,
      busy: true,
      verification: 'a1b2c3d4e5f6',
    );
  }

  @override
  Future<void> reconnect() async => retries++;
  @override
  Future<void> disconnect({bool resume = false}) async => this.resume = resume;
  @override
  void cancelPairing() {
    cancels++;
    state = const CompanionState(phase: CompanionPhase.idle);
  }

  @override
  Future<void> forget(String id) async => forgets++;
}

class _PageAiSettings extends AiSettingsController {
  _PageAiSettings(this.initial);
  final AiSettings initial;
  @override
  AiSettings build() => initial;
  @override
  Future<void> setMode(AiMode mode) async => state = AiSettings(
    mode: mode,
    assignments: state.assignments,
    overrides: state.overrides,
  );
  @override
  Future<void> setOverride(AiTask task, AiMode mode) async =>
      state = AiSettings(
        mode: state.mode,
        assignments: state.assignments,
        overrides: {...state.overrides, task: mode},
      );
}

const _phoneModels = [
  CatalogModel(
    id: 'writing-test',
    name: 'Qwen2.5 · 0.5B Instruct',
    task: AiTask.writing,
    format: 'gguf',
    repository: 'Qwen/test',
    revision: '',
    file: 'writing.gguf',
    bytes: 491400032,
    sha256: '',
    minRamBytes: 4294967296,
    license: 'Apache 2.0',
  ),
  CatalogModel(
    id: 'image-test',
    name: 'Stable Diffusion · 2.1',
    task: AiTask.image,
    format: 'gguf',
    repository: 'Qwen/test',
    revision: '',
    file: 'image.gguf',
    bytes: 2322705024,
    sha256: '',
    minRamBytes: 8589934592,
    license: 'CreativeML Open RAIL++-M',
  ),
];

class _Voice implements CompanionGuideVoice {
  final spoken = <String>[];
  int stops = 0;
  bool fail = false;
  Completer<void>? playing;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    if (fail) throw StateError('No installed voice');
    playing = Completer<void>();
    await playing!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (playing?.isCompleted == false) playing!.complete();
  }
}

class _Recall extends RecallIndexer {
  @override
  RecallIndexState build() => const RecallIndexState(enabled: {});
}

class _IdleSummary extends NoteSummaryController {
  @override
  NoteSummaryState build() => const NoteSummaryState();
}

class _Camera extends MobileScannerPlatform {
  bool denied = false;
  final captures = StreamController<BarcodeCapture?>.broadcast();
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop({bool force = false}) async {}
  @override
  Future<void> dispose() async {}
}

TrustedComputer _computer({bool enabled = true}) => TrustedComputer(
  id: 'desktop',
  name: 'My computer',
  pin: 'a' * 64,
  endpoint: Uri.parse('https://192.168.1.2:1234'),
  seed: '',
  publicKey: '',
  deviceId: '',
  enabled: enabled,
);
CompanionState _connected() => CompanionState(
  phase: CompanionPhase.connected,
  selectedId: 'desktop',
  computers: [_computer()],
  status: const {
    'capabilities': [
      {
        'id': 'text',
        'status': 'unloaded',
        'reason': 'Load a writing model on your computer.',
      },
      {
        'id': 'vision',
        'status': 'ready',
        'reason': 'The image model is ready.',
      },
      {
        'id': 'embedding',
        'status': 'ready',
        'reason': 'Search by meaning is ready.',
      },
      {
        'id': 'speech',
        'status': 'unavailable',
        'reason': 'Read replies on screen.',
      },
    ],
  },
);
String _code({bool expired = false}) => jsonEncode({
  'v': 1,
  'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'name': 'My computer',
  'pin': 'a' * 64,
  'secret': 'b' * 43,
  'endpoints': ['https://192.168.1.2:1234'],
  'expires': DateTime.now().millisecondsSinceEpoch + (expired ? -1000 : 120000),
});

const _captureKey = ValueKey('companion-capture');
Finder _key(String name) => find.byKey(ValueKey(name));

Future<({_Connection connection, _Voice voice})> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  bool reduced = false,
  CompanionState? initial,
  AiSettings? aiSettings,
  Set<String> installed = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final voice = _Voice();
  final scope = ProviderContainer.test(
    overrides: [
      onDeviceEngineProvider.overrideWithValue(
        aiSettings == null ? null : FakeOnDeviceEngine(),
      ),
      if (aiSettings != null) ...[
        aiSettingsProvider.overrideWith(() => _PageAiSettings(aiSettings)),
        modelCatalogProvider.overrideWith((ref) async => _phoneModels),
        installedModelsProvider.overrideWith((ref) async => installed),
        partialModelsProvider.overrideWith((ref) async => const {}),
        deviceResourcesProvider.overrideWith(
          (ref) async => const DeviceResources(
            freeBytes: 4100000000,
            ramBytes: 12884901888,
            wifi: true,
          ),
        ),
      ],
      companionControllerProvider.overrideWith(_Connection.new),
      companionGuideVoiceProvider.overrideWithValue(voice),
      recallIndexerProvider.overrideWith(_Recall.new),
      noteSummaryProvider.overrideWith(_IdleSummary.new),
      summaryHistoryProvider.overrideWith((ref) async => const []),
    ],
  );
  final connection =
      scope.read(companionControllerProvider.notifier) as _Connection;
  if (initial != null) connection.update(initial);
  final baseTheme = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'CompanionTest'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            child: child!,
          ),
          home: const CompanionPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/more_local_qvac.png'),
      tester.element(find.byType(CompanionPage)),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
  });
  return (connection: connection, voice: voice);
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('COMPANION_CAPTURES')) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    _key('companion-capture'),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-companion-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File.fromUri(
      File(Platform.resolvedExecutable).uri
          .resolve('../../material_fonts/Roboto-Regular.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader('CompanionTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets(
    'phone mode leads with models and keeps companion setup folded away',
    (tester) async {
      final app = await _mount(
        tester,
        aiSettings: const AiSettings(mode: AiMode.device),
      );
      expect(find.text('Your offline setup'), findsOneWidget);
      expect(find.text('Let’s connect your computer'), findsNothing);
      expect(
        find.textContaining('Search by meaning, voice & scans still need'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<AiMode>), findsNothing);
      await _capture(tester, 'local-ai-phone');
      await tester.ensureVisible(_key('ai-alternative-companion'));
      await tester.tap(find.text('Companion extras'));
      await tester.pumpAndSettle();
      expect(find.text('Let’s connect your computer'), findsOneWidget);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(CompanionPage)),
      );
      expect(scope.read(aiSettingsProvider).mode, AiMode.device);
      expect(app.connection.pairs, 0);
      expect(app.connection.scans, 0);
    },
  );

  testWidgets(
    'changing the main provider preserves model choices and task exceptions',
    (tester) async {
      final app = await _mount(
        tester,
        aiSettings: const AiSettings(
          mode: AiMode.device,
          assignments: {AiTask.writing: 'writing-test'},
          overrides: {AiTask.image: AiMode.companion},
        ),
        installed: {'writing-test'},
      );
      await _capture(tester, 'local-ai-ready');
      await tester.tap(_key('ai-mode-companion'));
      await tester.pumpAndSettle();
      expect(find.text('Your offline setup'), findsNothing);
      expect(find.text('Let’s connect your computer'), findsOneWidget);
      expect(find.text('1 custom task choice'), findsOneWidget);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(CompanionPage)),
      );
      expect(
        scope.read(aiSettingsProvider).assignments[AiTask.writing],
        'writing-test',
      );
      expect(
        scope.read(aiSettingsProvider).overrides[AiTask.image],
        AiMode.companion,
      );
      expect(app.connection.retries, 0);
      await _capture(tester, 'local-ai-companion');
      await tester.ensureVisible(_key('ai-mode-device'));
      await tester.tap(_key('ai-mode-device'));
      await tester.pumpAndSettle();
      expect(find.text('Your offline setup'), findsOneWidget);
      expect(find.text('Qwen2.5 · 0.5B Instruct'), findsOneWidget);
    },
  );

  testWidgets('Auto shows the relevant setup as the companion comes online', (
    tester,
  ) async {
    final app = await _mount(
      tester,
      aiSettings: const AiSettings(mode: AiMode.auto),
    );
    expect(find.text('Your offline setup'), findsOneWidget);
    expect(find.textContaining('Your computer is offline.'), findsOneWidget);
    await _capture(tester, 'local-ai-auto-away');
    app.connection.update(_connected());
    await tester.pumpAndSettle();
    expect(find.text('Your offline setup'), findsNothing);
    expect(find.text('You’re connected!'), findsOneWidget);
    expect(
      find.textContaining('Your computer is connected. Auto'),
      findsOneWidget,
    );
    await _capture(tester, 'local-ai-auto-connected');
  });

  testWidgets(
    'task exceptions are editable under Advanced without changing the overall mode',
    (tester) async {
      await _mount(tester, aiSettings: const AiSettings(mode: AiMode.device));
      await tester.ensureVisible(_key('ai-task-preferences'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      final writing = find.byType(DropdownButtonFormField<AiMode>).first;
      await tester.ensureVisible(writing);
      await tester.tap(writing);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Companion').last);
      await tester.pumpAndSettle();
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(CompanionPage)),
      );
      expect(scope.read(aiSettingsProvider).mode, AiMode.device);
      expect(
        scope.read(aiSettingsProvider).overrides[AiTask.writing],
        AiMode.companion,
      );
      expect(find.text('1 custom task choice'), findsOneWidget);
    },
  );

  testWidgets('getting an image model opens a focused catalog', (tester) async {
    await _mount(tester, aiSettings: const AiSettings(mode: AiMode.device));
    await tester.ensureVisible(_key('device-get-model-image'));
    await tester.tap(_key('device-get-model-image'));
    await tester.pumpAndSettle();
    expect(find.text('Image models'), findsOneWidget);
    expect(find.text('Stable Diffusion · 2.1'), findsOneWidget);
    expect(find.text('Qwen2.5 · 0.5B Instruct'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [
    (name: 'dark', size: const Size(390, 844), scale: 1.0, dark: true),
    (name: 'large-text', size: const Size(320, 740), scale: 2.0, dark: false),
    (name: 'landscape', size: const Size(844, 390), scale: 1.0, dark: false),
  ]) {
    testWidgets(
      'phone setup fits ${layout.name} and keeps advanced controls reachable',
      (tester) async {
        await _mount(
          tester,
          aiSettings: const AiSettings(mode: AiMode.device),
          size: layout.size,
          scale: layout.scale,
          dark: layout.dark,
          reduced: true,
          installed: {'writing-test'},
        );
        await _capture(tester, 'local-ai-phone-${layout.name}');
        await tester.ensureVisible(_key('ai-task-preferences'));
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Device engine: Fake engine'));
        expect(find.byType(DropdownButtonFormField<AiMode>), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'visual steps are explorable without claiming trust or starting a connection',
    (tester) async {
      final app = await _mount(tester);
      await _capture(tester, 'wifi');
      expect(find.text('You’re connected!'), findsNothing);
      await tester.tap(_key('companion-guide-next'));
      await tester.pumpAndSettle();
      expect(_key('companion-scan'), findsOneWidget);
      await _capture(tester, 'scan');
      await tester.tap(_key('companion-step-2'));
      await tester.pumpAndSettle();
      expect(
        find.text('Compare the phone code. Then approve on your computer.'),
        findsOneWidget,
      );
      expect(_key('companion-phone-code'), findsNothing);
      expect(find.text('You’re connected!'), findsNothing);
      expect(app.connection.pairs, 0);
      expect(app.connection.scans, 0);
      expect(app.voice.spoken, isEmpty);
      await tester.tap(_key('companion-step-0'));
      await tester.pumpAndSettle();
      expect(_key('companion-guide-next'), findsOneWidget);
    },
  );

  testWidgets(
    'QVAC speaks the current step and stops when a step or route changes',
    (tester) async {
      final app = await _mount(tester);
      await tester.tap(_key('companion-guide-mascot'));
      await tester.pumpAndSettle();
      expect(app.voice.spoken.single, contains('same private Wi-Fi'));
      expect(find.text('Stop'), findsOneWidget);
      await tester.tap(_key('companion-step-1'));
      await tester.pumpAndSettle();
      expect(find.text('Listen'), findsOneWidget);
      await tester.tap(_key('companion-guide-listen'));
      await tester.pumpAndSettle();
      expect(app.voice.spoken.last, contains('Point the camera'));
      final stopped = app.voice.stops;
      await tester.tap(_key('companion-paste'));
      await tester.pumpAndSettle();
      expect(app.voice.stops, greaterThan(stopped));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Listen'), findsOneWidget);
    },
  );

  testWidgets(
    'spoken help stops in the background and handles a missing voice',
    (tester) async {
      final app = await _mount(tester);
      await tester.tap(_key('companion-guide-listen'));
      await tester.pumpAndSettle();
      final stops = app.voice.stops;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(app.voice.stops, greaterThan(stops));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      app.voice.fail = true;
      await tester.tap(_key('companion-guide-listen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Voice is unavailable.'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);
    },
  );

  testWidgets(
    'paste validates codes and requires identity confirmation before pairing',
    (tester) async {
      final app = await _mount(tester);
      await tester.tap(_key('companion-paste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _code(expired: true));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Create a fresh QR'), findsOneWidget);
      expect(app.connection.pairs, 0);
      await tester.tap(_key('companion-paste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _code());
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Is this your computer?'), findsOneWidget);
      expect(find.text('a' * 64), findsOneWidget);
      expect(app.connection.pairs, 0);
      await tester.tap(_key('companion-confirm-identity'));
      await tester.pumpAndSettle();
      expect(app.connection.pairs, 1);
      expect(app.connection.pairedId, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(find.text('a1b2 c3d4 e5f6'), findsOneWidget);
      expect(find.text('You’re connected!'), findsNothing);
      await _capture(tester, 'approve');
      await tester.tap(find.text('Cancel pairing'));
      await tester.pumpAndSettle();
      expect(app.connection.cancels, 1);
      expect(_key('companion-phone-code'), findsNothing);
      expect(_key('companion-scan'), findsOneWidget);
    },
  );

  testWidgets(
    'camera denial offers a direct paste fallback with no trust change',
    (tester) async {
      final original = MobileScannerPlatform.instance;
      final camera = _Camera()..denied = true;
      MobileScannerPlatform.instance = camera;
      addTearDown(() async {
        MobileScannerPlatform.instance = original;
        MobileScannerController.resetPlatformSessionOwner();
        await camera.captures.close();
      });
      final app = await _mount(tester);
      await tester.tap(_key('companion-guide-next'));
      await tester.pumpAndSettle();
      await tester.tap(_key('companion-scan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Camera unavailable.'), findsOneWidget);
      await tester.tap(find.text('Use a code instead'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(app.connection.pairs, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scanning one QR still requires identity confirmation', (
    tester,
  ) async {
    final original = MobileScannerPlatform.instance;
    final camera = _Camera();
    MobileScannerPlatform.instance = camera;
    addTearDown(() async {
      MobileScannerPlatform.instance = original;
      MobileScannerController.resetPlatformSessionOwner();
      await camera.captures.close();
    });
    final app = await _mount(tester);
    await tester.tap(_key('companion-guide-next'));
    await tester.pumpAndSettle();
    await tester.tap(_key('companion-scan'));
    await tester.pumpAndSettle();
    final capture = BarcodeCapture(
      barcodes: [Barcode(rawValue: _code(), format: BarcodeFormat.qrCode)],
    );
    camera.captures.add(capture);
    camera.captures.add(capture);
    await tester.pumpAndSettle();
    expect(find.text('Is this your computer?'), findsOneWidget);
    expect(app.connection.pairs, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CompanionScannerPage), findsNothing);
    expect(app.connection.pairs, 0);
  });

  testWidgets(
    'phone speech is lazy, cancels during setup and reports engine failure',
    (tester) async {
      const channel = MethodChannel('flutter_tts');
      final calls = <MethodCall>[];
      final setup = Completer<int>();
      var failSpeech = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'awaitSpeakCompletion') return setup.future;
        if (call.method == 'speak' && failSpeech) return 0;
        return 1;
      });
      final scope = ProviderContainer.test();
      final voice = scope.read(companionGuideVoiceProvider);
      expect(calls, isEmpty);
      final cancelled = voice.speak('First step');
      await tester.pump();
      await voice.stop();
      setup.complete(1);
      await cancelled;
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
      await voice.speak('Second step');
      expect(
        calls.where((call) => call.method == 'speak').single.arguments,
        'Second step',
      );
      failSpeech = true;
      await expectLater(voice.speak('Third step'), throwsStateError);
      scope.dispose();
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );

  testWidgets(
    'only the live connected phase celebrates and shows model readiness',
    (tester) async {
      final app = await _mount(
        tester,
        initial: const CompanionState(
          phase: CompanionPhase.pairing,
          verification: '123456abcdef',
          busy: true,
        ),
      );
      expect(find.text('You’re connected!'), findsNothing);
      app.connection.update(_connected());
      await tester.pumpAndSettle();
      expect(find.text('You’re connected!'), findsOneWidget);
      expect(find.text('Connected · identity verified'), findsOneWidget);
      expect(find.text('Load model'), findsOneWidget);
      expect(_key('companion-phone-code'), findsNothing);
      await _capture(tester, 'connected');
      await tester.ensureVisible(_key('companion-computers'));
      await tester.tap(_key('companion-computers'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionDevicesPage), findsOneWidget);
      await _capture(tester, 'computers');
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      expect(app.connection.resume, false);
      app.connection.update(
        CompanionState(
          phase: CompanionPhase.trusted,
          selectedId: 'desktop',
          computers: [_computer(enabled: false)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reconnect'));
      await tester.tap(find.text('Reconnect'));
      expect(app.connection.resume, true);
      await tester.ensureVisible(find.text('Forget computer'));
      await tester.tap(find.text('Forget computer'));
      await tester.pumpAndSettle();
      expect(app.connection.forgets, 0);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(app.connection.forgets, 0);
    },
  );

  testWidgets('nearby discovery and advanced settings remain reachable', (
    tester,
  ) async {
    final app = await _mount(tester);
    await tester.tap(_key('companion-discover'));
    await tester.pumpAndSettle();
    expect(app.connection.scans, 1);
    expect(find.text('Scan to verify'), findsOneWidget);
    expect(app.connection.pairs, 0);
    expect(find.byType(CompanionDevicesPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('companion-preferences'));
    await tester.tap(_key('companion-preferences'));
    await tester.pumpAndSettle();
    expect(_key('daily-questions-toggle'), findsOneWidget);
    expect(_key('recall-settings'), findsOneWidget);
    expect(find.byType(CompanionPreferencesPage), findsOneWidget);
    await _capture(tester, 'preferences');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard shortcuts open voice, past work, help and connection details',
    (tester) async {
      const channel = MethodChannel('flutter_tts');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => 1,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _mount(tester, initial: _connected());
      await tester.ensureVisible(_key('companion-reply-voice'));
      await _capture(tester, 'dashboard');
      await tester.tap(_key('companion-reply-voice'));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyVoicePage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-ai-task-history'));
      await tester.tap(_key('companion-ai-task-history'));
      await tester.pumpAndSettle();
      expect(find.byType(SummaryHistoryPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-help'));
      await tester.tap(_key('companion-help'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionHelpPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-connection-details'));
      await tester.tap(_key('companion-connection-details'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionPrivacyPage), findsOneWidget);
      await tester.ensureVisible(find.text('Computer identity'));
      await tester.tap(find.text('Computer identity'));
      await tester.pumpAndSettle();
      expect(find.text('a' * 64), findsOneWidget);
    },
  );

  testWidgets(
    'pairing from Computers keeps the verification guide on that page',
    (tester) async {
      final app = await _mount(tester, initial: _connected());
      await tester.ensureVisible(_key('companion-computers'));
      await tester.tap(_key('companion-computers'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-paste'));
      await tester.tap(_key('companion-paste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _code());
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(_key('companion-confirm-identity'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionDevicesPage), findsOneWidget);
      expect(_key('companion-phone-code'), findsOneWidget);
      expect(find.text('a1b2 c3d4 e5f6'), findsOneWidget);
      expect(app.connection.pairs, 1);
      await tester.ensureVisible(find.text('Cancel pairing'));
      await tester.tap(find.text('Cancel pairing'));
      await tester.pumpAndSettle();
      expect(app.connection.cancels, 1);
      expect(_key('companion-phone-code'), findsNothing);
    },
  );

  testWidgets(
    'AI strip keeps every capability reachable and explains its real readiness',
    (tester) async {
      await _mount(tester, initial: _connected());
      await tester.ensureVisible(_key('companion-capability-text'));
      await tester.tap(_key('companion-capability-text'));
      await tester.pumpAndSettle();
      expect(find.text('Writing · Load model'), findsOneWidget);
      expect(
        find.text('Load a writing model on your computer.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-capability-speech'));
      await tester.tap(_key('companion-capability-speech'));
      await tester.pumpAndSettle();
      expect(find.text('Computer voice · Unavailable'), findsOneWidget);
      expect(find.text('Read replies on screen.'), findsOneWidget);
    },
  );

  for (final layout in [
    (
      name: 'dark',
      size: const Size(390, 844),
      scale: 1.0,
      dark: true,
      reduced: false,
    ),
    (
      name: 'large-text',
      size: const Size(320, 740),
      scale: 2.0,
      dark: false,
      reduced: true,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      scale: 1.0,
      dark: false,
      reduced: false,
    ),
    (
      name: 'wide',
      size: const Size(1100, 900),
      scale: 1.0,
      dark: false,
      reduced: false,
    ),
  ]) {
    testWidgets('companion interactions fit ${layout.name}', (tester) async {
      final app = await _mount(
        tester,
        size: layout.size,
        scale: layout.scale,
        dark: layout.dark,
        reduced: layout.reduced,
      );
      await _capture(tester, layout.name);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_key('companion-step-1'));
      await tester.tap(_key('companion-step-1'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-scan'));
      expect(_key('companion-scan').hitTestable(), findsOneWidget);
      app.connection.update(
        const CompanionState(
          phase: CompanionPhase.pairing,
          busy: true,
          verification: '123456abcdef',
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel pairing'));
      await tester.tap(find.text('Cancel pairing'));
      await tester.pumpAndSettle();
      app.connection.update(_connected());
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-preferences'));
      await _capture(tester, 'dashboard-${layout.name}');
      await tester.ensureVisible(_key('companion-computers'));
      await tester.tap(_key('companion-computers'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Forget computer'));
      await _capture(tester, 'computers-${layout.name}');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-preferences'));
      await tester.tap(_key('companion-preferences'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('recall-settings'));
      await _capture(tester, 'preferences-${layout.name}');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-help'));
      await tester.tap(_key('companion-help'));
      await tester.pumpAndSettle();
      await _capture(tester, 'help-${layout.name}');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('companion-connection-details'));
      await tester.tap(_key('companion-connection-details'));
      await tester.pumpAndSettle();
      await _capture(tester, 'privacy-${layout.name}');
      expect(tester.takeException(), isNull);
    });
  }
}
