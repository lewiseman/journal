import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_paper.dart';

/// A rigid front cover attached to the right edge of the left-hand page.
/// Negative Y rotation lifts it toward the viewer before it settles on the
/// right-hand page. Dimensions and the hinge stay fixed throughout the fold.
class BookFoldGeometry {
  const BookFoldGeometry({required this.leafSize, required this.progress});

  final Size leafSize;
  final double progress;

  // Finish the fold before positioning the closed book for naming. The
  // stationary cover and camera remain fixed while the front cover swings.
  double get foldProgress => progress >= .8
      ? 1
      : Curves.easeInOutCubic.transform((progress / .8).clamp(0.0, 1.0));
  double get settleProgress => progress >= 1
      ? 1
      : Curves.easeInOutCubic.transform(((progress - .8) / .2).clamp(0.0, 1.0));
  bool get outsideVisible => foldProgress > .5;
  double get angle => math.pi * foldProgress;
  double get lift => math.sin(angle);
  double get perspective => 1 / (leafSize.width * 10);
  double get recenter => -leafSize.width / 2 * settleProgress;

  Matrix4 get transform {
    final hinge = Offset(leafSize.width, leafSize.height / 2);
    final rotation = Matrix4.identity()..rotateY(-angle);
    return Matrix4.identity()
      ..translateByDouble(hinge.dx, hinge.dy, 0, 1)
      ..multiply(rotation)
      ..translateByDouble(-hinge.dx, -hinge.dy, 0, 1);
  }

  /// The outside is printed on the reverse side of the board, so its local
  /// orientation is reversed before applying the shared hinge transform.
  Matrix4 get outsideTransform => Matrix4.identity()
    ..translateByDouble(leafSize.width / 2, leafSize.height / 2, 0, 1)
    ..rotateY(math.pi)
    ..translateByDouble(-leafSize.width / 2, -leafSize.height / 2, 0, 1);

  Matrix4 get visibleFaceTransform =>
      outsideVisible ? (transform..multiply(outsideTransform)) : transform;
}

/// The cover's shadow is cast onto the stationary right-hand paper, and is
/// driven by the same rigid fold used to position the cover itself.
class BookFoldShadow extends CustomPainter {
  const BookFoldShadow({required this.fold});
  final BookFoldGeometry fold;

  @override
  void paint(Canvas canvas, Size size) {
    if (fold.lift < .001) return;
    final w = fold.leafSize.width, h = fold.leafSize.height;
    final height = w * fold.lift;
    final tip = w - w * math.cos(fold.angle) + height * .35;
    final drop = height * .10;
    final shadow = Path()
      ..moveTo(w, 4)
      ..lineTo(tip, 4 + drop)
      ..lineTo(tip, h + 4 + drop)
      ..lineTo(w, h + 4)
      ..close();
    canvas.save();
    canvas.clipPath(
      const PaperEdge(left: false).getClip(fold.leafSize).shift(Offset(w, 4)),
    );
    canvas.drawPath(
      shadow,
      Paint()
        ..color = Color.fromRGBO(37, 25, 18, .30 * fold.lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 + 6 * fold.lift),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BookFoldShadow oldDelegate) =>
      fold.progress != oldDelegate.fold.progress ||
      fold.leafSize != oldDelegate.fold.leafSize;
}

/// A visible board edge at the narrowest point of the fold. The front and
/// back faces meet at the same hinge instead of disappearing at ninety degrees.
class BookFoldEdge extends CustomPainter {
  const BookFoldEdge({required this.fold});
  final BookFoldGeometry fold;

  @override
  void paint(Canvas canvas, Size size) {
    if (fold.lift < .001) return;
    // This painter is inside the same 3D transform as the cover. Projecting
    // points into 2D here would discard their depth and detach the highlight.
    final x = fold.outsideVisible ? fold.leafSize.width - 1 : 1.0;
    final top = Offset(x, 9);
    final bottom = Offset(x, fold.leafSize.height - 2);
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..strokeWidth = 2 * math.pow(fold.lift, 8).toDouble()
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF9C86AC),
    );
  }

  @override
  bool shouldRepaint(BookFoldEdge oldDelegate) =>
      fold.progress != oldDelegate.fold.progress ||
      fold.leafSize != oldDelegate.fold.leafSize;
}
