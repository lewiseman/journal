import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';

/// Uneven ink strokes drifting inward from the collection's upper edges.
class NotesTopArtwork extends StatefulWidget {
  const NotesTopArtwork({super.key});

  @override
  State<NotesTopArtwork> createState() => _NotesTopArtworkState();
}

class _NotesTopArtworkState extends State<NotesTopArtwork>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 0;
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
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _NotesArtworkPainter(context.colors, _motion),
          ),
        ),
      ),
    ),
  );
}

class _NotesArtworkPainter extends CustomPainter {
  _NotesArtworkPainter(this.colors, this.motion) : super(repaint: motion);

  final ColorScheme colors;
  final AnimationController motion;
  Size? _fieldSize;
  List<_InkStroke> _strokes = const [];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final scale = (size.width / 440).clamp(.8, 1.4);
    final dark = colors.brightness == Brightness.dark;
    final seconds =
        (motion.lastElapsedDuration?.inMicroseconds ?? 0) /
        Duration.microsecondsPerSecond;
    final phase = seconds * math.pi * 2 / 24;
    if (_fieldSize != size) {
      _fieldSize = size;
      _strokes = _createStrokes(size, scale);
    }

    canvas.save();
    canvas.clipRect(bounds);

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.9, -.95),
          radius: 1.05,
          colors: [
            colors.primary.withValues(alpha: dark ? .09 : .07),
            colors.primary.withValues(alpha: .02),
            colors.primary.withValues(alpha: 0),
          ],
          stops: const [0, .6, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.95, -.75),
          radius: .7,
          colors: [
            colors.primary.withValues(alpha: dark ? .045 : .025),
            colors.primary.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );

    for (final stroke in _strokes) {
      final drift =
          stroke.normal * (math.sin(phase + stroke.phase) * stroke.drift);
      canvas.save();
      canvas.translate(drift.dx, drift.dy);
      canvas.drawPath(stroke.path, stroke.paint);
      canvas.restore();
    }

    if (motion.isAnimating) {
      _drawGlints(canvas, seconds, phase, scale);
    }
    canvas.restore();
  }

  List<_InkStroke> _createStrokes(Size size, double scale) {
    final strokes = <_InkStroke>[];
    final topCount = (size.width / 32).round().clamp(10, 24);
    Offset point(double x, double y) => Offset(size.width * x, size.height * y);

    // Fixed seeds keep each stroke's imperfections stable across repaints.
    for (var i = 0; i < topCount; i++) {
      final random = math.Random(1709 + i * 97);
      final position = (i + .5) / topCount;
      strokes.add(
        _createStroke(
          point(
            .04 + .92 * position + (random.nextDouble() - .5) * .24 / topCount,
            -.045,
          ),
          point(
            .25 + .5 * position + (random.nextDouble() - .5) * .01,
            .55 + random.nextDouble() * .3,
          ),
          random,
          size,
          scale,
        ),
      );
    }
    for (var side = 0; side < 2; side++) {
      for (var i = 0; i < 4; i++) {
        final random = math.Random(3301 + side * 701 + i * 97);
        final left = side == 0;
        final targetX = .25 + i * .045 + random.nextDouble() * .008;
        strokes.add(
          _createStroke(
            point(
              left ? -.025 : 1.025,
              .045 + i * .06 + (random.nextDouble() - .5) * .014,
            ),
            point(
              left ? targetX : 1 - targetX,
              .58 + i * .065 + random.nextDouble() * .045,
            ),
            random,
            size,
            scale,
          ),
        );
      }
    }
    return strokes;
  }

  _InkStroke _createStroke(
    Offset start,
    Offset end,
    math.Random random,
    Size size,
    double scale,
  ) {
    final direction = end - start;
    final normal = Offset(-direction.dy, direction.dx) / direction.distance;
    final extent = math.min(size.width, size.height);
    final bend = (random.nextDouble() - .5) * extent * .08;
    final wobble = (random.nextDouble() - .5) * extent * .024;
    final middle = start + direction * .5 + normal * bend;
    final tangent = direction * .17 + normal * wobble;
    final firstControl =
        start + direction * .16 + normal * (bend * .3 - wobble);
    final lastControl = end - direction * .18 - normal * (bend * .25 + wobble);
    final beforeMiddle = middle - tangent;
    final afterMiddle = middle + tangent;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        firstControl.dx,
        firstControl.dy,
        beforeMiddle.dx,
        beforeMiddle.dy,
        middle.dx,
        middle.dy,
      )
      ..cubicTo(
        afterMiddle.dx,
        afterMiddle.dy,
        lastControl.dx,
        lastControl.dy,
        end.dx,
        end.dy,
      );
    final dark = colors.brightness == Brightness.dark;
    final opacity =
        (dark ? .16 : .12) + random.nextDouble() * (dark ? .14 : .11);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (.55 + random.nextDouble() * .35) * scale
      ..shader = ui.Gradient.linear(
        start,
        end,
        [
          colors.primary.withValues(alpha: opacity),
          colors.primary.withValues(alpha: opacity * .55),
          colors.primary.withValues(alpha: 0),
        ],
        const [0, .42, 1],
      );
    return _InkStroke(
      path: path,
      metric: path.computeMetrics().first,
      paint: paint,
      normal: normal,
      phase: random.nextDouble() * math.pi * 2,
      drift: (.8 + random.nextDouble() * .5) * scale,
    );
  }

  void _drawGlints(Canvas canvas, double seconds, double phase, double scale) {
    const interval = .6;
    const startJitter = 1.0;
    const minDuration = 3.5;
    const maxDuration = 5.5;
    final currentSlot = (seconds / interval).floor();
    final lookBackSlots = ((maxDuration + startJitter) / interval).ceil();
    // Keep every overlapping glint alive, including those with delayed starts.
    for (
      var slot = math.max(0, currentSlot - lookBackSlots);
      slot <= currentSlot;
      slot++
    ) {
      final random = math.Random(8017 + slot * 7919);
      if (random.nextDouble() >= .65) continue;
      final delay = random.nextDouble() * startJitter;
      final duration =
          minDuration + random.nextDouble() * (maxDuration - minDuration);
      final progress = (seconds - slot * interval - delay) / duration;
      if (progress <= 0 || progress >= 1) continue;

      final stroke = _strokes[random.nextInt(_strokes.length)];
      final length = (18 + random.nextDouble() * 14) * scale;
      final fade = progress < .42
          ? 1 - progress / .42 * .45
          : .55 * (1 - (progress - .42) / .58);
      final opacity = math.sin(progress * math.pi) * .55 * fade;
      final distance = stroke.metric.length * progress;
      final from = math.max(0.0, distance - length);
      final start = stroke.metric.getTangentForOffset(from)!.position;
      final end = stroke.metric.getTangentForOffset(distance)!.position;
      final tail = stroke.metric.extractPath(from, distance);
      final drift =
          stroke.normal * (math.sin(phase + stroke.phase) * stroke.drift);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3 * scale
        ..shader = ui.Gradient.linear(start, end, [
          colors.primary.withValues(alpha: 0),
          colors.primary.withValues(alpha: opacity * .08),
        ]);
      canvas.save();
      canvas.translate(drift.dx, drift.dy);
      canvas.drawPath(tail, paint);
      paint
        ..strokeWidth = 1.05 * scale
        ..shader = ui.Gradient.linear(start, end, [
          colors.primary.withValues(alpha: 0),
          colors.primary.withValues(alpha: opacity),
        ]);
      canvas.drawPath(tail, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _NotesArtworkPainter oldDelegate) =>
      colors != oldDelegate.colors || motion != oldDelegate.motion;
}

class _InkStroke {
  const _InkStroke({
    required this.path,
    required this.metric,
    required this.paint,
    required this.normal,
    required this.phase,
    required this.drift,
  });

  final Path path;
  final ui.PathMetric metric;
  final Paint paint;
  final Offset normal;
  final double phase;
  final double drift;
}
