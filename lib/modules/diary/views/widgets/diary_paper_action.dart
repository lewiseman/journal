import 'dart:math' as math;

import 'package:flutter/material.dart';

enum DiaryPaperAction {
  voice('Add voice entry'),
  image('Add image entry'),
  more('More diary actions');

  const DiaryPaperAction(this.tooltip);
  final String tooltip;
}

/// The voice drawing in its 48×48 box, shared with larger ink controls.
List<Path> get diaryVoiceInk => _PaperActionPainter._voice;

/// Small ink drawings on the existing paper, with a full-sized touch target.
class DiaryPaperActionButton extends StatelessWidget {
  const DiaryPaperActionButton({
    super.key,
    required this.action,
    required this.onPressed,
  });

  final DiaryPaperAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ink = colors.onSurfaceVariant;
    return IconButton(
      onPressed: onPressed,
      tooltip: action.tooltip,
      iconSize: 48,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        highlightColor: ink.withValues(alpha: .06),
        hoverColor: ink.withValues(alpha: .04),
        focusColor: ink.withValues(alpha: .10),
        shape: const CircleBorder(),
      ),
      icon: CustomPaint(
        size: const Size.square(48),
        painter: _PaperActionPainter(
          action: action,
          ink: ink,
          ring: ink.withValues(
            alpha: colors.brightness == Brightness.dark ? .28 : .20,
          ),
        ),
      ),
    );
  }
}

class _PaperActionPainter extends CustomPainter {
  const _PaperActionPainter({
    required this.action,
    required this.ink,
    required this.ring,
  });

  final DiaryPaperAction action;
  final Color ink, ring;

  // Only three tiny vector drawings are built. Painting never generates paths,
  // textures, random values or offscreen layers, including during page turns.
  static final _rings = [
    for (final action in DiaryPaperAction.values) _pencilRing(action.index),
  ];
  static final _voice = [
    Path()
      ..moveTo(21, 16.2)
      ..cubicTo(20.6, 18.8, 20.9, 22.9, 21, 24)
      ..cubicTo(21.2, 28.1, 27.8, 28, 27.5, 23.6)
      ..lineTo(27.3, 16.6)
      ..cubicTo(27.2, 12.8, 21.4, 12.5, 21, 16.2)
      ..close(),
    Path()
      ..moveTo(17.3, 22.4)
      ..cubicTo(16.8, 34.3, 32.1, 34.1, 31, 22.2),
    Path()
      ..moveTo(24.1, 31)
      ..lineTo(23.9, 35)
      ..moveTo(20.6, 35.1)
      ..quadraticBezierTo(23.9, 34.7, 27.4, 35),
  ];
  static final _image = [
    Path()
      ..moveTo(15.6, 16)
      ..lineTo(30.9, 14.5)
      ..quadraticBezierTo(32, 14.4, 32.1, 15.5)
      ..lineTo(33.8, 32)
      ..quadraticBezierTo(33.9, 33, 32.8, 33.1)
      ..lineTo(17.8, 34.6)
      ..quadraticBezierTo(16.6, 34.8, 16.5, 33.5)
      ..lineTo(15, 17.1)
      ..quadraticBezierTo(14.8, 16, 15.6, 16)
      ..close(),
    Path()
      ..moveTo(18.3, 27.9)
      ..lineTo(22.1, 22.3)
      ..lineTo(25.7, 26)
      ..lineTo(28, 23.9)
      ..lineTo(30.9, 26.8)
      ..moveTo(17, 30)
      ..quadraticBezierTo(24, 29.5, 33.3, 28.4),
    Path()
      ..moveTo(28.6, 19.2)
      ..cubicTo(28.9, 21.6, 25.5, 21.7, 25.5, 19.5)
      ..cubicTo(25.4, 17.5, 28.3, 17.3, 28.6, 19.2)
      ..close(),
  ];
  static final _more = [
    for (final (index, x) in [16.0, 24.0, 31.8].indexed)
      Path()
        ..moveTo(x - 1.5, 24 + (index == 1 ? .4 : -.2))
        ..cubicTo(x - 1.7, 21.8, x + 1.6, 21.7, x + 1.7, 23.8)
        ..cubicTo(x + 1.8, 26.1, x - 1.4, 26.3, x - 1.5, 24)
        ..close(),
  ];

  static Path _pencilRing(int variant) {
    final points = <Offset>[];
    for (var step = 0; step <= 28; step++) {
      final angle = -.5 + variant * .65 + step / 28 * math.pi * 1.89;
      final radius =
          21.2 +
          math.sin(angle * 3 + variant) * .65 +
          math.cos(angle * 5 - variant) * .3;
      points.add(
        Offset(
          24 + math.cos(angle) * radius,
          24 + math.sin(angle) * radius * .96,
        ),
      );
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var step = 1; step < points.length - 1; step++) {
      final middle = Offset.lerp(points[step], points[step + 1], .5)!;
      path.quadraticBezierTo(
        points[step].dx,
        points[step].dy,
        middle.dx,
        middle.dy,
      );
    }
    return path..lineTo(points.last.dx, points.last.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = .85
      ..color = ring;
    canvas.drawPath(_rings[action.index], pen);
    pen.color = ink;
    final drawing = switch (action) {
      DiaryPaperAction.voice => _voice,
      DiaryPaperAction.image => _image,
      DiaryPaperAction.more => _more,
    };
    for (final (index, path) in drawing.indexed) {
      pen.style = action == DiaryPaperAction.more
          ? PaintingStyle.fill
          : PaintingStyle.stroke;
      pen.strokeWidth = index.isEven ? 1.35 : 1.15;
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(_PaperActionPainter oldDelegate) =>
      action != oldDelegate.action ||
      ink != oldDelegate.ink ||
      ring != oldDelegate.ring;
}
