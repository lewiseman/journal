import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// iOS: HEVC with alpha works natively via video_player
// Android: No native alpha video support. Use the stacked MP4
//   with a custom OpenGL shader or flutter_vap package.

class TransparentVideoPlayer extends StatefulWidget {
  final String hevcUrl;

  const TransparentVideoPlayer({
    super.key,
    required this.hevcUrl,
  });

  @override
  State<TransparentVideoPlayer> createState() => _TransparentVideoPlayerState();
}

class _TransparentVideoPlayerState extends State<TransparentVideoPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    // HEVC with alpha — works on iOS
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.hevcUrl))
      ..initialize().then((_) {
        _controller.setLooping(true);
        _controller.play();
        setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: VideoPlayer(_controller),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// Usage (iOS):
// TransparentVideoPlayer(hevcUrl: 'https://assets.masko.ai/your-collection/your-animation.mov')

// Android: Use the stacked MP4 with flutter_vap or a custom GL shader
// Stacked MP4 URL: https://assets.masko.ai/your-collection/your-animation-stacked.mp4