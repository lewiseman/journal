import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:journal/modules/voice/models/voice_session.dart';

/// Soft fields of color, with no video assets or full-screen blur passes.
class VoiceAmbientBackground extends StatefulWidget {
  const VoiceAmbientBackground({
    super.key,
    required this.mode,
    required this.phase,
    required this.reducedMotion,
    this.activity = VoiceAudioActivity.silent,
  });

  final VoiceSessionMode mode;
  final VoiceSessionPhase phase;
  final bool reducedMotion;
  final VoiceAudioActivity activity;

  @override
  State<VoiceAmbientBackground> createState() => _VoiceAmbientBackgroundState();
}

class _VoiceAmbientBackgroundState extends State<VoiceAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  double _cool = 0;
  double _gain = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(VoiceAmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMotion();
  }

  void _updateMotion() {
    if (widget.phase != VoiceSessionPhase.paused) {
      _gain = switch (widget.phase) {
        VoiceSessionPhase.thinking => .25,
        VoiceSessionPhase.speaking => 1.45,
        VoiceSessionPhase.completed => 0,
        _ => 1,
      };
      if (widget.mode == VoiceSessionMode.conversation) _gain *= 1.3;
    }
    _cool = switch (widget.phase) {
      VoiceSessionPhase.thinking => .65,
      VoiceSessionPhase.speaking => 1,
      VoiceSessionPhase.paused => _cool,
      _ => 0,
    };
    if (widget.reducedMotion ||
        widget.phase == VoiceSessionPhase.paused ||
        widget.phase == VoiceSessionPhase.completed ||
        !TickerMode.valuesOf(context).enabled) {
      _motion.stop();
      if (widget.reducedMotion) _motion.value = 0;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: TickerMode(
          enabled: widget.phase != VoiceSessionPhase.paused,
          child: TweenAnimationBuilder<_GlowResponse>(
            tween: _GlowResponseTween(
              end: _GlowResponse(
                cool: _cool,
                gain: _gain,
                level: widget.reducedMotion ? 0 : widget.activity.level,
                pitch: widget.reducedMotion ? .5 : widget.activity.pitch,
              ),
            ),
            duration:
                widget.reducedMotion ||
                    widget.phase == VoiceSessionPhase.completed
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, response, _) => CustomPaint(
              key: const ValueKey('voice-ambient-background'),
              painter: _AmbientPainter(
                motion: _motion,
                response: response,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GlowResponse {
  const _GlowResponse({
    required this.cool,
    required this.gain,
    required this.level,
    required this.pitch,
  });

  final double cool, gain, level, pitch;
}

class _GlowResponseTween extends Tween<_GlowResponse> {
  _GlowResponseTween({required _GlowResponse super.end});

  @override
  _GlowResponse lerp(double t) {
    double mix(double a, double b) => a + (b - a) * t;
    return _GlowResponse(
      cool: mix(begin!.cool, end!.cool),
      gain: mix(begin!.gain, end!.gain),
      level: mix(begin!.level, end!.level),
      pitch: mix(begin!.pitch, end!.pitch),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.motion,
    required this.response,
    required this.dark,
  }) : super(repaint: motion);

  final Animation<double> motion;
  final _GlowResponse response;
  final bool dark;

  Color _color(int warm, int cold) =>
      Color.lerp(Color(warm), Color(cold), response.cool)!;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final phase = motion.value * math.pi * 2;
    final drift = math.sin(phase);
    final sway = math.cos(phase);
    final pitch = response.pitch;
    // Layered frequencies create smooth, irregular syllables rather than a
    // mechanical pulse. Pitch steers their path; loudness expands the glow.
    final syllable =
        (.48 +
                .22 * math.sin(phase * 17) +
                .18 * math.sin(phase * 29 + 1.2) +
                .12 * math.sin(phase * 43 + pitch * 2))
            .clamp(.04, 1.0);
    final energy = response.level * response.gain * (.35 + syllable * .9);
    final pulse = syllable * response.level;
    final wanderX =
        .55 * math.sin(phase * 2 + pitch * 2) +
        .28 * math.sin(phase * 5 + 1.2) +
        .17 * math.sin(phase * 9 - .7);
    final wanderY =
        .65 * math.cos(phase * 3 - pitch * 3) + .35 * math.sin(phase * 7 + .5);
    canvas.drawRect(
      bounds,
      Paint()
        ..color = dark
            ? _color(0xFF241F27, 0xFF1B2433)
            : _color(0xFFFFF9EE, 0xFFEBF6F4),
    );

    void glow(Offset center, double rx, double ry, Color color) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(1, ry / rx);
      canvas.drawCircle(
        Offset.zero,
        rx,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [.05, 1],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx)),
      );
      canvas.restore();
    }

    final w = size.width;
    final h = size.height;
    final center = Offset(
      w * (.50 + drift * .06 + wanderX * .19 * energy),
      h * (.29 + sway * .035 + wanderY * .075 * energy),
    );
    glow(
      Offset(
        w * (.80 + drift * .1 - wanderX * .14 * energy),
        h * (.14 + sway * .025 + wanderY * .04 * energy),
      ),
      w * (.95 + energy * .12),
      h * (.56 + energy * .05),
      _color(0xFFF8C487, 0xFF9391EF).withValues(alpha: dark ? .25 : .82),
    );
    glow(
      Offset(
        w * (.15 + sway * .10 + wanderY * .17 * energy),
        h * (.38 + drift * .04 - wanderX * .06 * energy),
      ),
      w * (.82 + energy * .1),
      h * (.39 + energy * .06),
      _color(0xFFF9D5AD, 0xFFADDFF4).withValues(alpha: dark ? .22 : .85),
    );
    glow(
      center,
      w * (.42 + energy * .25),
      h * (.20 + energy * .08),
      _color(
        0xFFED91AC,
        0xFF8C8FEF,
      ).withValues(alpha: (dark ? .32 : .80) + (dark ? .12 : .10) * pulse),
    );
    glow(
      center +
          Offset(
            w * (.10 * math.cos(phase * 5 + pitch * 3) * energy - .04),
            h * (.035 * math.sin(phase * 7 + pitch) * energy - .04),
          ),
      w * (.15 + energy * .10),
      h * (.09 + energy * .045),
      _color(
        0xFFFFE9D9,
        0xFFDAFFFF,
      ).withValues(alpha: (dark ? .16 : .72) + (dark ? .16 : .22) * pulse),
    );
    glow(
      center +
          Offset(
            -w * wanderY * .22 * energy,
            h * (.09 + wanderX * .05 * energy),
          ),
      w * (.24 + energy * .16),
      h * (.10 + energy * .04),
      _color(
        0xFFF7AD8E,
        0xFF83DEDA,
      ).withValues(alpha: (dark ? .13 : .25) * energy.clamp(0, 1)),
    );
    glow(
      Offset(w * (.65 - drift * .13), h * .88),
      w,
      h * .5,
      _color(0xFFFAEDCB, 0xFFBAEDDB).withValues(alpha: dark ? .10 : .60),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.response != response ||
      oldDelegate.dark != dark ||
      oldDelegate.motion != motion;
}
