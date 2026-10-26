import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/voice/views/widgets/voice_ambient_background.dart';
import 'package:journal/modules/voice/voice.dart';

const _captureKey = ValueKey('voice-capture');
final _history = find.byKey(const ValueKey('voice-transcript-scroll'));

Future<void> _mount(
  WidgetTester tester, {
  required VoiceSessionController controller,
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  bool reduced = false,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  final base = dark ? AppThemeConfig.darkTheme : AppThemeConfig.lightTheme;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'VoiceTest'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: Directionality(textDirection: direction, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => VoiceSessionPage(
                      mode: controller.mode,
                      title: controller.mode == VoiceSessionMode.conversation
                          ? 'Your day, out loud'
                          : 'Voice note',
                      controller: controller,
                    ),
                  ),
                ),
                child: const Text('Open preview'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open preview'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('VOICE_CAPTURES')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/journal-voice-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<List<int>> _pixels(WidgetTester tester) => tester
    .runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData();
      final pixels = bytes!.buffer.asUint8List().toList();
      image.dispose();
      return pixels;
    })
    .then((value) => value!);

double _motionDifference(List<int> a, List<int> b) {
  var difference = 0;
  // Sample RGB evenly across the frame; skip alpha and avoid a huge matcher diff.
  for (var i = 0; i < a.length; i += 64) {
    difference +=
        (a[i] - b[i]).abs() +
        (a[i + 1] - b[i + 1]).abs() +
        (a[i + 2] - b[i + 2]).abs();
  }
  return difference / (a.length / 64 * 3);
}

const _user = VoiceSpeaker.user;
const _ai = VoiceSpeaker.assistant;
const _sample = [
  VoiceTranscriptTurn(
    speaker: _user,
    text: 'Today felt a little full. I kept moving from one thing to the next.',
  ),
  VoiceTranscriptTurn(
    speaker: _user,
    text: 'But on the way home I noticed the light through the trees, and slowed down.',
  ),
  VoiceTranscriptTurn(
    speaker: _ai,
    text:
        'That sounds like a small moment of calm. What made it feel different?',
  ),
];

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
      await (FontLoader('VoiceTest')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets('transcription finishes with user turns and can replay', (
    tester,
  ) async {
    final controller = PreviewVoiceSessionController(
      mode: VoiceSessionMode.transcription,
    );
    addTearDown(controller.dispose);
    final states = <VoiceSessionState>[];
    controller.addListener(() => states.add(controller.state));
    controller.start();
    await tester.pump(const Duration(seconds: 90));
    expect(controller.state.phase, VoiceSessionPhase.completed);
    expect(controller.state.turns, hasLength(6));
    expect(controller.state.turns.every((turn) => turn.isFinal), true);
    final voice = states.where((state) => state.activity.level > 0);
    expect(voice, isNotEmpty);
    expect(
      voice.map((state) => state.activity.level).toSet().length,
      greaterThan(3),
    );
    expect(
      voice.map((state) => state.activity.pitch).toSet().length,
      greaterThan(3),
    );
    expect(
      states.any(
        (state) =>
            state.turns.isNotEmpty &&
            state.phase == VoiceSessionPhase.listening &&
            state.activity.level == 0,
      ),
      true,
    );
    expect(controller.state.activity.level, 0);
    expect(
      states.every(
        (state) => state.turns.every((turn) => turn.speaker == _user),
      ),
      true,
    );
    final phases = states.map((state) => state.phase);
    expect(phases, isNot(contains(VoiceSessionPhase.thinking)));
    expect(phases, isNot(contains(VoiceSessionPhase.speaking)));
    controller.replay();
    expect(controller.state.turns, isEmpty);
    await tester.pump(const Duration(milliseconds: 850));
    expect(controller.state.turns.single.isFinal, false);
    controller.pause();
  });

  testWidgets('diary lets the user lead and reflects after two user turns', (
    tester,
  ) async {
    final controller = PreviewVoiceSessionController(
      mode: VoiceSessionMode.conversation,
    );
    addTearDown(controller.dispose);
    final states = <VoiceSessionState>[];
    controller.addListener(() => states.add(controller.state));
    controller.start();
    await tester.pump(const Duration(seconds: 90));
    final thinking = states.where(
      (state) => state.phase == VoiceSessionPhase.thinking,
    );
    expect(thinking.map((state) => state.turns.length), [2, 5]);
    expect(
      thinking.every(
        (state) =>
            state.turns.last.speaker == _user && state.turns.last.isFinal,
      ),
      true,
    );
    final speaking = states.where(
      (state) => state.phase == VoiceSessionPhase.speaking,
    );
    expect(speaking, isNotEmpty);
    expect(speaking.every((state) => state.turns.last.speaker == _ai), true);
    expect(controller.state.phase, VoiceSessionPhase.completed);
    expect(controller.state.turns.map((turn) => turn.speaker), [
      _user,
      _user,
      _ai,
      _user,
      _user,
      _ai,
    ]);
  });

  testWidgets('pause freezes partial text, resume continues, dispose cancels', (
    tester,
  ) async {
    final controller = PreviewVoiceSessionController(
      mode: VoiceSessionMode.transcription,
    );
    controller.start();
    await tester.pump(const Duration(seconds: 1));
    controller.pause();
    final paused = controller.state;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.state, same(paused));
    controller.resume();
    await tester.pump(const Duration(milliseconds: 340));
    expect(
      controller.state.turns.single.text.length,
      greaterThan(paused.turns.single.text.length),
    );
    var updates = 0;
    controller.addListener(() => updates++);
    controller.dispose();
    await tester.pump(const Duration(seconds: 90));
    expect(updates, 0);
  });

  testWidgets('reduced motion reveals complete turns without partial text', (
    tester,
  ) async {
    final controller = PreviewVoiceSessionController(
      mode: VoiceSessionMode.conversation,
    );
    addTearDown(controller.dispose);
    controller.setReducedMotion(true);
    final states = <VoiceSessionState>[];
    controller.addListener(() => states.add(controller.state));
    controller.start();
    await tester.pump(const Duration(seconds: 20));
    expect(controller.state.phase, VoiceSessionPhase.completed);
    expect(controller.state.turns, hasLength(6));
    expect(
      states.every((state) => state.turns.every((turn) => turn.isFinal)),
      true,
    );
  });

  testWidgets('lifecycle pauses playback and returning requires resume', (
    tester,
  ) async {
    final controller = PreviewVoiceSessionController(
      mode: VoiceSessionMode.transcription,
    );
    addTearDown(controller.dispose);
    await _mount(tester, controller: controller);
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.state.phase, VoiceSessionPhase.paused);
    final text = controller.state.turns.last.text;
    await tester.pump(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.state.phase, VoiceSessionPhase.paused);
    expect(controller.state.turns.last.text, text);
    await tester.tap(find.byTooltip('Resume'));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.state.turns.last.text.length, greaterThan(text.length));
    await tester.tap(find.byTooltip('Close voice preview'));
    await tester.pumpAndSettle();
    expect(controller.state.phase, VoiceSessionPhase.paused);
    expect(find.text('Open preview'), findsOneWidget);
  });

  testWidgets(
    'history stays still while reading and follows again at the end',
    (tester) async {
      final controller = _ManualController();
      addTearDown(controller.dispose);
      final turns = List.generate(10, (_) => _sample.first);
      controller.emit(VoiceSessionPhase.completed, turns);
      await _mount(tester, controller: controller, reduced: true);
      await tester.pump();
      final scroll = tester.widget<SingleChildScrollView>(_history).controller!;
      expect(scroll.offset, scroll.position.maxScrollExtent);
      await tester.drag(_history, const Offset(0, 200));
      await tester.pumpAndSettle();
      final readingOffset = scroll.offset;
      expect(readingOffset, lessThan(scroll.position.maxScrollExtent));
      turns.add(_sample.last);
      controller.emit(VoiceSessionPhase.completed, turns);
      await tester.pump();
      await tester.pump();
      expect(scroll.offset, readingOffset);
      await tester.drag(_history, const Offset(0, -1500));
      await tester.pumpAndSettle();
      turns.add(_sample.first);
      controller.emit(VoiceSessionPhase.completed, turns);
      await tester.pump();
      await tester.pump();
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(
        find.byKey(const ValueKey('voice-transcript-fade')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion offers replay and Done closes without returning text',
    (tester) async {
      final controller = _ManualController();
      addTearDown(controller.dispose);
      controller.emit(VoiceSessionPhase.completed, _sample);
      await _mount(tester, controller: controller, reduced: true);
      expect(find.text('Preview finished'), findsOneWidget);
      expect(find.text('Preview · sample text'), findsOneWidget);
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      expect(controller.state.turns, isEmpty);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(VoiceSessionPage), findsNothing);
      expect(find.text('Open preview'), findsOneWidget);
    },
  );

  for (final mode in VoiceSessionMode.values) {
    testWidgets('$mode glow reacts to audio and freezes when paused', (
      tester,
    ) async {
      final controller = _ManualController(mode: mode);
      addTearDown(controller.dispose);
      controller.emit(VoiceSessionPhase.listening, _sample.take(2).toList());
      await _mount(tester, controller: controller);
      final quiet = await _pixels(tester);
      await tester.pump(const Duration(milliseconds: 180));
      final quietMotion = _motionDifference(quiet, await _pixels(tester));
      final phase = mode == VoiceSessionMode.conversation
          ? VoiceSessionPhase.speaking
          : VoiceSessionPhase.listening;
      controller.emit(
        phase,
        _sample.take(2).toList(),
        activity: const VoiceAudioActivity(level: .95, pitch: .8),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final loud = await _pixels(tester);
      await tester.pump(const Duration(milliseconds: 180));
      final loudMotion = _motionDifference(loud, await _pixels(tester));
      expect(loudMotion, greaterThan(quietMotion * 2));
      if (const bool.fromEnvironment('VOICE_CAPTURES')) {
        for (var frame = 0; frame < 16; frame++) {
          await tester.pump(const Duration(milliseconds: 120));
          await _capture(tester, 'reactive-${mode.name}-$frame');
        }
      }
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      final paused = await _pixels(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_motionDifference(paused, await _pixels(tester)), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('reduced motion keeps the glow still despite changing audio', (
    tester,
  ) async {
    final controller = _ManualController();
    addTearDown(controller.dispose);
    controller.emit(VoiceSessionPhase.listening, _sample);
    await _mount(tester, controller: controller, reduced: true);
    final quiet = await _pixels(tester);
    controller.emit(
      VoiceSessionPhase.listening,
      _sample,
      activity: const VoiceAudioActivity(level: 1, pitch: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_motionDifference(quiet, await _pixels(tester)), 0);
  });

  for (final config in [
    (name: 'listening', size: const Size(390, 844), scale: 1.0, dark: false),
    (name: 'small', size: const Size(320, 568), scale: 2.0, dark: false),
    (name: 'landscape', size: const Size(844, 390), scale: 1.8, dark: false),
    (name: 'dark', size: const Size(390, 844), scale: 1.0, dark: true),
  ]) {
    testWidgets('${config.name} layout keeps text and controls accessible', (
      tester,
    ) async {
      final controller = _ManualController();
      addTearDown(controller.dispose);
      controller.emit(
        VoiceSessionPhase.listening,
        _sample.take(2).toList(),
        activity: const VoiceAudioActivity(level: .75, pitch: .4),
      );
      await _mount(
        tester,
        controller: controller,
        size: config.size,
        scale: config.scale,
        dark: config.dark,
        reduced: config.scale > 1,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Done').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Pause').hitTestable(), findsOneWidget);
      expect(find.text('Preview · sample text'), findsOneWidget);
      expect(
        tester.getBottomLeft(_history).dy,
        lessThan(tester.getTopLeft(find.byTooltip('Pause')).dy),
      );
      await _capture(tester, config.name);
      controller.emit(
        VoiceSessionPhase.speaking,
        _sample,
        activity: const VoiceAudioActivity(level: .9, pitch: .7),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      final scroll = tester.widget<SingleChildScrollView>(_history).controller!;
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, .5));
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('Speaking'), findsOneWidget);
      expect(
        tester
            .widget<VoiceAmbientBackground>(find.byType(VoiceAmbientBackground))
            .phase,
        VoiceSessionPhase.speaking,
      );
      await _capture(tester, '${config.name}-speaking');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _ManualController extends VoiceSessionController {
  _ManualController({this.mode = VoiceSessionMode.conversation});

  @override
  final VoiceSessionMode mode;

  @override
  VoiceSessionState state = VoiceSessionState(
    phase: VoiceSessionPhase.listening,
  );
  VoiceSessionPhase _resumePhase = VoiceSessionPhase.listening;

  void emit(
    VoiceSessionPhase phase,
    List<VoiceTranscriptTurn> turns, {
    VoiceAudioActivity activity = VoiceAudioActivity.silent,
  }) {
    state = VoiceSessionState(phase: phase, turns: turns, activity: activity);
    notifyListeners();
  }

  @override
  void start() {}

  @override
  void pause() {
    if (!state.isActive) return;
    _resumePhase = state.phase;
    emit(VoiceSessionPhase.paused, state.turns, activity: state.activity);
  }

  @override
  void resume() => emit(_resumePhase, state.turns, activity: state.activity);

  @override
  void replay() => emit(VoiceSessionPhase.listening, []);
}
