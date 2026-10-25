import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

void _paintMaterial(
  Canvas canvas,
  ui.Image image,
  Rect target, {
  Rect? source,
}) {
  canvas.drawImageRect(
    image,
    source ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    target,
    Paint()..filterQuality = FilterQuality.medium,
  );
}

/// Both sides of a flexible sheet. Each strip chooses its face from the local
/// surface normal, so the back is revealed gradually around the curl.
class BentBookPage extends MultiChildRenderObjectWidget {
  BentBookPage({
    super.key,
    required this.progress,
    required this.reverse,
    required Widget front,
    required Widget back,
  }) : super(children: [front, back]);

  final double progress;
  final bool reverse;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBentBookPaper(progress, reverse);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBentBookPaper renderObject,
  ) {
    renderObject
      ..progress = progress
      ..reverse = reverse;
  }
}

class _BookFaceParentData extends ContainerBoxParentData<RenderBox> {}

// Record the image-based faces once per frame and replay the short display
// lists through the strips. The decoded artwork is shared by both leaves.
class _PaperFaceContext extends PaintingContext {
  _PaperFaceContext(this._canvas, Rect bounds)
    : super(ContainerLayer(), bounds);
  final Canvas _canvas;

  @override
  Canvas get canvas => _canvas;
}

class RenderBentBookPaper extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BookFaceParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BookFaceParentData> {
  RenderBentBookPaper(this._progress, this._reverse);
  double _progress;
  bool _reverse;

  set progress(double value) {
    if (value != _progress) {
      _progress = value;
      markNeedsPaint();
    }
  }

  set reverse(bool value) {
    if (value != _reverse) {
      _reverse = value;
      markNeedsPaint();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BookFaceParentData) {
      child.parentData = _BookFaceParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    firstChild?.layout(BoxConstraints.tight(size));
    lastChild?.layout(BoxConstraints.tight(size));
  }

  // Gestures belong to the enclosing book; decorative faces are not controls.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  Rect get paintBounds => Rect.fromLTRB(
    -size.width - 40,
    -size.height * .25,
    size.width * 2 + 40,
    size.height * 1.25,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null || lastChild == null) return;
    ui.Picture? recordFace(RenderBox face) {
      // Fall back to normal child painting if a future face needs compositing.
      if (face.needsCompositing) return null;
      final recorder = ui.PictureRecorder();
      final recording = _PaperFaceContext(Canvas(recorder), Offset.zero & size);
      recording.paintChild(face, Offset.zero);
      return recorder.endRecording();
    }

    final frontPicture = recordFace(firstChild!);
    final backPicture = recordFace(lastChild!);
    const bands = 64;
    final w = size.width;
    final h = size.height;
    final t = _progress.clamp(0.0, 1.0);
    final lift = math.sin(math.pi * t);
    final bend = 1.25 * lift;
    final sign = _reverse ? -1.0 : 1.0;
    final origin = _reverse ? w : 0.0;
    final points = <Offset>[];
    final depths = <double>[];
    double x = 0, z = 0;
    for (var i = 0; i <= bands; i++) {
      if (i > 0) {
        final u = (i - .5) / bands;
        // The spine stays pinned; the free edge leads the turn.
        final angle = math.pi * t + bend * (u - .5);
        x += math.cos(angle) * w / bands;
        z += math.sin(angle) * w / bands;
      }
      final perspective = 1 / (1 - z / (w * 6));
      points.add(Offset(origin + sign * x * perspective, perspective));
      depths.add(z);
    }
    // Project the lifted surface onto the flat receiving pages. Keeping the
    // light direction fixed makes forward and reverse turns feel consistent.
    final silhouette = Path();
    for (var i = 0; i <= bands; i++) {
      final p = points[i];
      final y = depths[i] * .15 + 2 * lift;
      final sx = origin + (p.dx - origin) / p.dy + depths[i] * .26 + 3 * lift;
      if (i == 0) {
        silhouette.moveTo(sx, y);
      } else {
        silhouette.lineTo(sx, y);
      }
    }
    for (var i = bands; i >= 0; i--) {
      final p = points[i];
      silhouette.lineTo(
        origin + (p.dx - origin) / p.dy + depths[i] * .26 + 3 * lift,
        h + depths[i] * .15 + 2 * lift,
      );
    }
    silhouette.close();
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final receivingPages = Path()
      ..addPath(
        const PaperEdge(left: true).getClip(size),
        Offset(_reverse ? 0 : -w, 0),
      )
      ..addPath(
        const PaperEdge(left: false).getClip(size),
        Offset(_reverse ? w : 0, 0),
      );
    canvas.clipPath(receivingPages);
    canvas.drawPath(
      silhouette,
      Paint()
        ..color = Color.fromRGBO(37, 25, 18, .26 * lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 + 7 * lift),
    );
    final hingeShadow = Rect.fromLTWH(origin - 6, 0, 12, h);
    canvas.drawRect(
      hingeShadow,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0x00251912),
            Color.fromRGBO(37, 25, 18, .18 * lift),
            const Color(0x00251912),
          ],
        ).createShader(hingeShadow),
    );
    canvas.restore();

    final order = List.generate(bands, (i) => i)
      ..sort((a, b) => depths[a].compareTo(depths[b]));
    for (final i in order) {
      final a = points[i];
      final b = points[i + 1];
      final normal = math.cos(math.pi * t + bend * ((i + .5) / bands - .5));
      final back = normal < 0;
      final face = back ? lastChild! : firstChild!;
      final picture = back ? backPicture : frontPicture;
      final sourceReversed = back != _reverse;
      final sx = (sourceReversed ? bands - i - 1 : i) * w / bands;
      final sourceWidth = w / bands;
      final dx = sourceReversed ? a.dx - b.dx : b.dx - a.dx;
      if (dx.abs() < .001) continue;
      final start = sourceReversed ? b.dx : a.dx;
      final sy = (a.dy + b.dy) / 2;
      final transform = Matrix4.identity()
        ..setEntry(0, 0, dx / sourceWidth)
        ..setEntry(1, 1, sy)
        ..setEntry(0, 3, start - sx * dx / sourceWidth)
        ..setEntry(1, 3, h * (1 - sy) / 2);
      context.pushTransform(needsCompositing, offset, transform, (
        context,
        offset,
      ) {
        context.pushClipRect(
          needsCompositing,
          offset,
          Rect.fromLTWH(sx - .08, -1, sourceWidth + .16, h + 2),
          (context, offset) {
            if (picture != null) {
              context.canvas
                ..save()
                ..translate(offset.dx, offset.dy)
                ..drawPicture(picture)
                ..restore();
            } else {
              context.paintChild(face, offset);
            }
            final shade = ((1 - normal.abs()) * .20 + lift * .025);
            context.canvas.drawRect(
              Rect.fromLTWH(
                offset.dx + sx - .08,
                offset.dy,
                sourceWidth + .16,
                h,
              ),
              Paint()
                ..isAntiAlias = false
                ..color = Color.fromRGBO(67, 48, 27, shade),
            );
          },
          clipBehavior: Clip.hardEdge,
        );
      });
    }
    // Highlight only the actual free edge, inset from the clipped page's
    // corners. Outlining the rectangular source would leave floating lines
    // above the bowed paper silhouette during a turn.
    if (lift > .001) {
      final edge = points.last;
      final top = h * .5 * (1 - edge.dy) + 10 * edge.dy;
      final bottom = h * .5 * (1 + edge.dy) - 5 * edge.dy;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawLine(
        Offset(edge.dx + .3, top),
        Offset(edge.dx + .3, bottom),
        Paint()
          ..strokeWidth = .7
          ..color = Color.fromRGBO(139, 115, 79, .55 * lift),
      );
      canvas.drawLine(
        Offset(edge.dx - .3, top),
        Offset(edge.dx - .3, bottom),
        Paint()
          ..strokeWidth = .5
          ..color = Color.fromRGBO(255, 248, 225, .65 * lift),
      );
      canvas.restore();
    }
    frontPicture?.dispose();
    backPicture?.dispose();
  }
}

/// Slightly bowed edges with different contours on either side of the gutter.
class PaperEdge extends CustomClipper<Path> {
  const PaperEdge({required this.left});
  final bool left;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(1, 10)
      ..quadraticBezierTo(1, 7, 5, 6)
      ..cubicTo(w * .28, -1, w * .64, 0, w, 12)
      ..cubicTo(w - 3.5, h * .3, w - 3.5, h * .7, w - 2, h - 9)
      ..cubicTo(w * .72, h - 1, w * .29, h - 7, 6, h - 1)
      ..quadraticBezierTo(2, h, 2, h - 5)
      ..quadraticBezierTo(-1, h * .82, 1.5, h * .65)
      ..quadraticBezierTo(-1, h * .44, 1, h * .24)
      ..close();
    if (!left) {
      return path.transform(
        (Matrix4.identity()
              ..translateByDouble(w, 0, 0, 1)
              ..scaleByDouble(-1, 1, 1, 1))
            .storage,
      );
    }
    return path;
  }

  @override
  bool shouldReclip(PaperEdge oldClipper) => left != oldClipper.left;
}

/// A thin rigid board with separate end-grain, bevel and contact shadows.
class CoverBevel extends CustomPainter {
  const CoverBevel();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final face = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      face.shift(const Offset(1.5, 5)),
      Paint()
        ..color = const Color(0x50302440)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(
      face.shift(const Offset(1.5, 4)),
      Paint()..color = const Color(0xFF5C486B),
    );
    canvas.drawRRect(
      face.shift(const Offset(.5, 2)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE1D1E9), Color(0xFFA28AAE), Color(0xFF756082)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      face.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE2D4E8),
    );
  }

  @override
  bool shouldRepaint(CoverBevel oldDelegate) => false;
}

/// Both boards are cut from this one case. Only the outer corners are round;
/// clipping at the shared spine does not add a second rim or restart lighting.
class BookCaseGeometry {
  const BookCaseGeometry(this.leafSize);
  final Size leafSize;

  Rect get bounds =>
      Rect.fromLTRB(-3, 3, leafSize.width * 2 + 3, leafSize.height + 14);
  Rect halfClip(bool left) => Rect.fromLTRB(
    left ? -64 : leafSize.width,
    -64,
    left ? leafSize.width : leafSize.width * 2 + 64,
    leafSize.height + 64,
  );

  /// The open case continues through the hinge. As the front folds over it,
  /// the hidden half withdraws and exposes the back board's rounded spine
  /// corners. Keep the outer edge, height and lighting anchored throughout.
  RRect backOutline(double closing) => RRect.fromRectAndRadius(
    Rect.fromLTRB(
      ui.lerpDouble(bounds.left, leafSize.width, closing.clamp(0.0, 1.0))!,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ),
    const Radius.circular(10),
  );
}

void _paintBookBoard(Canvas canvas, Rect rect, {RRect? outline}) {
  final board =
      outline ?? RRect.fromRectAndRadius(rect, const Radius.circular(10));
  canvas.drawRRect(
    board.shift(const Offset(4, 13)),
    Paint()
      ..color = const Color(0x4807041B)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
  );
  canvas.drawRRect(
    board.shift(const Offset(1, 5)),
    Paint()
      ..color = const Color(0x900E0922)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
  canvas.drawRRect(
    board.shift(const Offset(1.5, 4)),
    Paint()..color = const Color(0xFF4E3B60),
  );
  canvas.drawRRect(
    board.shift(const Offset(.5, 1.5)),
    Paint()..color = const Color(0xFFB49AC4),
  );
  canvas.drawRRect(
    board,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFC4ADD2), Color(0xFF947BA4), Color(0xFF5B466F)],
        stops: [0, .48, 1],
      ).createShader(rect),
  );
  canvas.drawRRect(
    board.deflate(.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..color = const Color(0xB0E4D0ED),
  );
}

void _paintLeafStack(
  Canvas canvas,
  Size size,
  bool left,
  double depth,
  ui.Image? paperTexture,
) {
  final w = size.width, h = size.height;
  canvas.save();
  canvas.clipRect(
    Rect.fromLTRB(left ? -64 : 5, -64, left ? w - 5 : w + 64, h + depth + 64),
  );
  final shape = PaperEdge(left: left).getClip(Size(w, h));
  final side = left ? -1.5 : 1.5;
  final block = shape.shift(Offset(side, depth));
  canvas.drawShadow(block, const Color(0x701E1525), 3, true);
  canvas.drawPath(block, Paint()..color = const Color(0xFFC6B596));
  // A few contours retain the bowed shape; the image supplies the fine
  // fibers and irregular cuts that would be expensive to draw separately.
  for (var i = 7; i >= 0; i--) {
    final t = i / 7;
    canvas.drawPath(
      shape.shift(Offset(side * t, depth * t)),
      Paint()
        ..color = Color.lerp(
          const Color(0xFFF3E8CF),
          const Color(0xFFC6B596),
          t,
        )!,
    );
  }
  canvas.save();
  canvas.clipPath(block);
  final edgeRect = Rect.fromLTWH(-3, h - 15, w + 6, depth + 17);
  if (paperTexture case final texture?) {
    _paintMaterial(
      canvas,
      texture,
      edgeRect,
      source: Rect.fromLTWH(
        0,
        texture.height * .2,
        texture.width.toDouble(),
        144,
      ),
    );
    // The fore-edge's layers run vertically as the page block turns the
    // corner. Rotate the same small texture rather than load another one.
    canvas.save();
    final outer = left ? 0.0 : w;
    canvas.clipRect(Rect.fromLTWH(outer - 3, 0, 6, h + depth));
    canvas.translate(outer - 3, h + depth);
    canvas.rotate(-math.pi / 2);
    _paintMaterial(
      canvas,
      texture,
      Rect.fromLTWH(0, 0, h + depth, 6),
      source: Rect.fromLTWH(
        0,
        texture.height * .2,
        texture.width.toDouble(),
        30,
      ),
    );
    canvas.restore();
  }
  canvas.drawRect(
    edgeRect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00786549), Color(0x00786549), Color(0x50745C39)],
        stops: [0, .6, 1],
      ).createShader(edgeRect),
  );
  canvas.restore();
  canvas.drawPath(
    shape.shift(const Offset(0, 1)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x6056442D),
  );
  canvas.restore();
}

void _paintBookSpine(
  Canvas canvas,
  Rect gutter,
  ui.Image? bindingTexture, {
  double openness = 1,
}) {
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(gutter, const Radius.circular(3)));
  canvas.drawRect(gutter, Paint()..color = const Color(0xFF7C6788));
  if (bindingTexture case final texture?) {
    _paintMaterial(canvas, texture, gutter);
  }
  canvas.drawRect(
    gutter,
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x801B1025), Color(0x004B3B32), Color(0xA01B1025)],
        stops: [0, .48, 1],
      ).createShader(gutter),
  );
  canvas.restore();
  // End caps catch the light where the sewn cloth emerges from the pages.
  final cap = 1 + 3 * openness;
  for (final y in [gutter.top + 1, gutter.bottom - 4]) {
    canvas.drawLine(
      Offset(gutter.center.dx - cap, y),
      Offset(gutter.center.dx + cap, y),
      Paint()
        ..color = Color.fromRGBO(223, 208, 178, .63 * openness)
        ..strokeWidth = .8,
    );
  }
}

/// One solid half of the book. Its board and paper edges move as one object.
class BookLeafStack extends CustomPainter {
  const BookLeafStack({
    required this.left,
    required this.depth,
    this.paperTexture,
    this.bindingTexture,
    this.board = false,
  });
  final bool left, board;
  final double depth;
  final ui.Image? paperTexture, bindingTexture;

  @override
  void paint(Canvas canvas, Size size) {
    if (board) {
      final caseGeometry = BookCaseGeometry(size);
      canvas.save();
      canvas.clipRect(caseGeometry.halfClip(true), doAntiAlias: false);
      _paintBookBoard(canvas, caseGeometry.bounds);
      _paintBookSpine(
        canvas,
        Rect.fromLTWH(size.width - 5, 6, 10, size.height + 4),
        bindingTexture,
      );
      canvas.restore();
    }
    _paintLeafStack(canvas, size, left, depth, paperTexture);
  }

  @override
  bool shouldRepaint(BookLeafStack oldDelegate) =>
      left != oldDelegate.left ||
      depth != oldDelegate.depth ||
      board != oldDelegate.board ||
      paperTexture != oldDelegate.paperTexture ||
      bindingTexture != oldDelegate.bindingTexture;
}

/// The back cover shares the continuous open case, then exposes its rounded
/// spine corners as the front closes. Its position and lighting stay fixed.
class BookBoards extends CustomPainter {
  const BookBoards({this.closing = 0});
  final double closing;

  @override
  void paint(Canvas canvas, Size size) {
    final caseGeometry = BookCaseGeometry(
      Size(size.width / 2, size.height - 20),
    );
    canvas.save();
    canvas.translate(0, 4);
    canvas.clipRect(caseGeometry.halfClip(false), doAntiAlias: false);
    _paintBookBoard(
      canvas,
      caseGeometry.bounds,
      outline: caseGeometry.backOutline(closing),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BookBoards oldDelegate) => closing != oldDelegate.closing;
}

class BookBinding extends CustomPainter {
  const BookBinding({
    required this.progress,
    this.closing = 0,
    this.showLeft = true,
    this.paperTexture,
    this.bindingTexture,
  });
  final double progress, closing;
  final bool showLeft;
  final ui.Image? paperTexture, bindingTexture;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 2, h = size.height - 20;
    canvas.save();
    // The binding and page edges must fit inside the same curved back board;
    // otherwise the cloth leaves a straight tab below the rounded corner.
    if (closing > 0) {
      canvas.clipRRect(
        BookCaseGeometry(Size(w, h))
            .backOutline(closing)
            .shift(const Offset(0, 4)),
      );
    }
    for (final left in [true, false]) {
      if (left && !showLeft) continue;
      final depth = left ? 9 + 7 * progress : 9 + 7 * (1 - progress);
      canvas.save();
      canvas.translate(left ? 0 : w, 4);
      _paintLeafStack(canvas, Size(w, h), left, depth, paperTexture);
      canvas.restore();
    }
    _paintBookSpine(
      canvas,
      Rect.fromLTWH(w - 5 + 3.5 * closing, 10, 10 - 7 * closing, h + 4),
      bindingTexture,
      openness: 1 - closing,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BookBinding oldDelegate) =>
      progress != oldDelegate.progress ||
      closing != oldDelegate.closing ||
      showLeft != oldDelegate.showLeft ||
      paperTexture != oldDelegate.paperTexture ||
      bindingTexture != oldDelegate.bindingTexture;
}

/// Light catches the raised shoulder, then falls into the sewn gutter. This is
/// painted over the printed contents so they share the paper's curved surface.
class PaperLighting extends CustomPainter {
  const PaperLighting({required this.left});
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipPath(PaperEdge(left: left).getClip(size));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: const [
            Color(0x11715A3C),
            Color(0x00FFFFFF),
            Color(0x08FFFFFF),
            Color(0x24FFFFFF),
            Color(0x002C1D10),
            Color(0x482C1D10),
          ],
          stops: const [0, .08, .68, .86, .94, 1],
        ).createShader(rect),
    );
    final edge = PaperEdge(left: left).getClip(size);
    canvas.drawPath(
      edge.shift(const Offset(0, .5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65
        ..color = const Color(0xA6FFFBEF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PaperLighting oldDelegate) => left != oldDelegate.left;
}
