import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal/components/transparent_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  late _VideoPlatform platform;
  setUp(() {
    final original = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = original);
  });

  Future<void> mount(
    WidgetTester tester, {
    bool playing = true,
    String asset = 'mascot.mp4',
  }) => tester.pumpWidget(
    MaterialApp(
      home: TransparentVideoPlayer(
        assetPath: asset,
        playing: playing,
        placeholder: const Text('Mascot still'),
      ),
    ),
  );

  testWidgets('playback defaults on and toggles without recreating the video', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpAndSettle();
    expect(platform.playing, isTrue);
    expect(platform.created, 1);
    await mount(tester, playing: false);
    await tester.pumpAndSettle();
    expect(platform.playing, isFalse);
    expect(platform.created, 1);
    await mount(tester);
    await tester.pumpAndSettle();
    expect(platform.playing, isTrue);
    expect(platform.created, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(platform.disposed, 1);
  });

  testWidgets('initialization uses the latest playing value', (tester) async {
    platform.delayInitialization = true;
    await mount(tester);
    await tester.pump();
    expect(find.text('Mascot still'), findsOneWidget);
    await mount(tester, playing: false);
    platform.initializePlayer();
    await tester.pumpAndSettle();
    expect(platform.playCalls, 0);
    expect(platform.playing, isFalse);
    expect(find.byKey(const ValueKey('video-surface')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'paused startup and asset replacement preserve the desired state',
    (tester) async {
      await mount(tester, playing: false);
      await tester.pumpAndSettle();
      expect(platform.playCalls, 0);
      expect(platform.playing, isFalse);
      await mount(tester, playing: false, asset: 'another.mp4');
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(platform.created, 2);
      expect(platform.disposed, 1);
      expect(platform.playCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

class _VideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  bool delayInitialization = false;
  bool playing = false;
  int created = 0;
  int disposed = 0;
  int playCalls = 0;

  void initializePlayer() => streams[created]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(200, 200),
      duration: const Duration(seconds: 10),
    ),
  );

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    streams[++created] = StreamController<VideoEvent>();
    if (!delayInitialization) initializePlayer();
    return created;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposed++;
    await streams.remove(playerId)!.close();
  }

  @override
  Future<void> play(int playerId) async {
    playing = true;
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {
    playing = false;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool value,
  ) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox(key: ValueKey('video-surface'));
}
