import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shared geometry for clipping the content and painting both sides of paper.
class NotePaperShape extends CustomClipper<Path> {
  const NotePaperShape({required this.fold, required this.radius});

  final double fold;
  final double radius;

  double foldFor(Size size) =>
      math.min(fold, math.min(size.width, size.height) * .8);

  @override
  Path getClip(Size size) {
    final r = math.min(radius, math.min(size.width, size.height) / 2);
    final f = foldFor(size);
    if (f < .1) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)),
      );
    }
    final path = Path()
      ..moveTo(f, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, size.height - r)
      ..quadraticBezierTo(size.width, size.height, size.width - r, size.height)
      ..lineTo(r, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - r)
      ..lineTo(0, f)
      ..cubicTo(f * .12, f * .78, f * .78, f * .12, f, 0)
      ..close();
    return _atBottomRight(path, size);
  }

  Path curl(Size size) {
    final f = foldFor(size);
    final path = Path()
      ..moveTo(f, 0)
      ..cubicTo(f * .88, f * .16, f * .91, f * .38, f * .91, f * .61)
      ..cubicTo(f * .92, f * .85, f * .83, f * .93, f * .61, f * .91)
      ..cubicTo(f * .38, f * .91, f * .16, f * .88, 0, f)
      ..cubicTo(f * .12, f * .78, f * .78, f * .12, f, 0)
      ..close();
    return _atBottomRight(path, size);
  }

  Path _atBottomRight(Path path, Size size) => path.transform(
    (Matrix4.diagonal3Values(
      -1,
      -1,
      1,
    )..setTranslationRaw(size.width, size.height, 0)).storage,
  );

  @override
  bool shouldReclip(NotePaperShape oldClipper) =>
      fold != oldClipper.fold || radius != oldClipper.radius;
}

class NotePaperShadowPainter extends CustomPainter {
  const NotePaperShadowPainter(this.shape, this.folded);

  final NotePaperShape shape;
  final double folded;

  @override
  bool hitTest(Offset position) => false;

  @override
  void paint(Canvas canvas, Size size) {
    if (folded == 0 || size.isEmpty) return;
    final path = shape.getClip(size);
    canvas.drawShadow(
      path.shift(Offset(0, 5 * folded)),
      const Color(0xff392234).withValues(alpha: .3 * folded),
      12 * folded,
      false,
    );
    canvas.drawPath(
      path.shift(Offset(0, 2 * folded)),
      Paint()
        ..color = Colors.black.withValues(alpha: .07 * folded)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * folded),
    );
  }

  @override
  bool shouldRepaint(NotePaperShadowPainter oldDelegate) =>
      folded != oldDelegate.folded || shape.shouldReclip(oldDelegate.shape);
}

class NotePaperCurlPainter extends CustomPainter {
  const NotePaperCurlPainter(this.shape, this.color, this.folded);

  final NotePaperShape shape;
  final Color color;
  final double folded;

  @override
  void paint(Canvas canvas, Size size) {
    if (folded == 0 || size.isEmpty) return;
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.black
        : const Color(0xff382b32);
    final paper = shape.getClip(size);
    canvas.save();
    canvas.clipPath(paper);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * .8, size.height * .65),
          [
            Colors.white.withValues(alpha: .12 * folded),
            Colors.white.withValues(alpha: 0),
            ink.withValues(alpha: .025 * folded),
          ],
          [0, .5, 1],
        ),
    );
    final curl = shape.curl(size);
    final f = shape.foldFor(size);
    canvas.drawPath(
      curl.shift(Offset(-4 * folded, -7 * folded)),
      Paint()
        ..color = ink.withValues(alpha: .22 * folded)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * folded),
    );
    canvas.drawShadow(
      curl,
      ink.withValues(alpha: .25 * folded),
      4 * folded,
      true,
    );
    canvas.drawPath(
      curl,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width - f * .25, size.height - f * .25),
          Offset(size.width - f * .94, size.height - f * .94),
          [
            Color.lerp(color, ink, .12)!,
            Color.lerp(color, Colors.white, .70)!,
            Color.lerp(color, Colors.white, .40)!,
            Color.lerp(color, ink, .09)!,
          ],
          const [0, .35, .73, 1],
        ),
    );
    canvas.drawPath(
      curl,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = Colors.white.withValues(alpha: .5 * folded),
    );
    canvas.restore();
    canvas.drawPath(
      paper,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = Colors.white.withValues(alpha: .45 * folded),
    );
  }

  @override
  bool shouldRepaint(NotePaperCurlPainter oldDelegate) =>
      color != oldDelegate.color ||
      folded != oldDelegate.folded ||
      shape.shouldReclip(oldDelegate.shape);
}

/// The shared, solid-color surface of the note and its app bar.
class NotePaperSurface extends StatelessWidget {
  const NotePaperSurface({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: color, child: const SizedBox.expand());
}
