import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class TransparentVideoPlayer extends StatefulWidget {
  final String assetPath;

  /// Whether the video stores color above a grayscale alpha mask.
  /// Requires the Impeller renderer.
  final bool stackedAlpha;

  /// Pause without disposing the video, including while it is initializing.
  final bool playing;

  /// Shown while loading or when the renderer cannot display the video.
  final Widget? placeholder;

  const TransparentVideoPlayer({
    super.key,
    required this.assetPath,
    this.stackedAlpha = false,
    this.playing = true,
    this.placeholder,
  });

  @override
  State<TransparentVideoPlayer> createState() => _TransparentVideoPlayerState();
}

class _TransparentVideoPlayerState extends State<TransparentVideoPlayer> {
  late VideoPlayerController _controller;
  late Future<void> _initialization;
  ui.FragmentShader? _shader;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  @override
  void didUpdateWidget(covariant TransparentVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.stackedAlpha != widget.stackedAlpha) {
      _controller.dispose();
      _loadVideo();
    } else if (oldWidget.playing != widget.playing) {
      _updatePlayback();
    }
  }

  void _loadVideo() {
    _ready = false;
    _shader?.dispose();
    _shader = null;
    final controller = VideoPlayerController.asset(widget.assetPath);
    _controller = controller;
    _initialization = _initialize(controller);
  }

  Future<void> _initialize(VideoPlayerController controller) async {
    if (widget.stackedAlpha && !ui.ImageFilter.isShaderFilterSupported) {
      throw UnsupportedError('Stacked alpha video requires Impeller.');
    }

    await controller.initialize();
    if (!mounted || controller != _controller) return;

    if (widget.stackedAlpha) {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/stacked_alpha.frag',
      );
      if (!mounted || controller != _controller) return;
      _shader = program.fragmentShader();
    }

    await controller.setLooping(true);
    if (!mounted || controller != _controller) return;

    _ready = true;
    await _updatePlayback();
  }

  Future<void> _updatePlayback() async {
    if (!_ready || _controller.value.hasError) return;
    if (widget.playing) {
      await _controller.play();
    } else {
      await _controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.placeholder ??
              const Center(child: Text('Unable to play video.'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder ??
              const Center(child: CircularProgressIndicator());
        }
        return AspectRatio(
          aspectRatio:
              _controller.value.aspectRatio * (widget.stackedAlpha ? 2 : 1),
          child: _shader == null
              ? VideoPlayer(_controller)
              : ImageFiltered(
                  imageFilter: ui.ImageFilter.shader(_shader!),
                  child: VideoPlayer(_controller),
                ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _shader?.dispose();
    super.dispose();
  }
}
