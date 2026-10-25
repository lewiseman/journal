import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

typedef _StampKey = ({
  Color paper,
  Color ink,
  Color shadow,
  int variant,
  bool raised,
});

const _tileSize = 96.0;
const _rasterScale = 2.0;
const _border = 20.0;
final _textures = <_StampKey, ui.Image>{};
int _textureBuilds = 0;

/// A reusable imitation of paper for UI chrome and non-active sheets.
///
/// A few small, theme-colored textures bake the rim, fibers and shadow once.
/// Resizing, fading and scrolling only stretch their nine-slice borders; they
/// never rebuild the active sheet's procedural outline or use a saveLayer.
class DiaryPaperStamp extends CustomPainter {
  const DiaryPaperStamp({
    required this.paper,
    required this.ink,
    this.shadowColor = const Color(0xff000000),
    this.shadow = true,
    this.variant = 0,
    this.edgeScale = 1,
    this.opacity = 1,
    this.flatten = 0,
  });

  final Color paper, ink, shadowColor;
  final bool shadow;
  final int variant;
  final double edgeScale, opacity, flatten;

  @visibleForTesting
  static int get debugTextureBuilds => _textureBuilds;

  @visibleForTesting
  static int get debugCachedTextures => _textures.length;

  @override
  void paint(Canvas canvas, Size size) => paintRect(canvas, Offset.zero & size);

  void paintRect(Canvas canvas, Rect rect) {
    final alpha = opacity.clamp(0.0, 1.0);
    if (rect.isEmpty || alpha == 0) return;
    final scale = math.min(
      edgeScale * (1 - flatten.clamp(0.0, 1.0)),
      rect.shortestSide / (_border * 2),
    );
    if (scale <= .01) {
      canvas.drawRect(rect, Paint()..color = paper.withValues(alpha: alpha));
      return;
    }
    final key = (
      paper: paper,
      ink: ink,
      shadow: shadowColor,
      variant: variant % 3,
      raised: shadow,
    );
    final image = _textures.remove(key) ?? _bake(key);
    _textures[key] = image;
    if (_textures.length > 12) {
      _textures.remove(_textures.keys.first)!.dispose();
    }
    final factor = scale / _rasterScale;
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(factor);
    canvas.drawImageNine(
      image,
      const Rect.fromLTRB(
        _border * _rasterScale,
        _border * _rasterScale,
        (_tileSize - _border) * _rasterScale,
        (_tileSize - _border) * _rasterScale,
      ),
      Rect.fromLTWH(0, 0, rect.width / factor, rect.height / factor),
      Paint()
        ..color = const Color(0xffffffff).withValues(alpha: alpha)
        ..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  static ui.Image _bake(_StampKey key) {
    assert(() {
      _textureBuilds++;
      return true;
    }());
    final random = math.Random(731 + key.variant * 137);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_rasterScale);
    final path = Path()..moveTo(10, 6);
    // The stock outline is deliberately small and fixed. It only needs to
    // suggest torn fibers at button size, not model a diary's changing edge.
    for (var side = 0; side < 4; side++) {
      for (var i = 0; i <= 18; i++) {
        final along = 10 + 76 * i / 18;
        final bump = random.nextDouble() * 3.2 - 1.6;
        final point = switch (side) {
          0 => Offset(along, 6 + bump),
          1 => Offset(90 - bump, along),
          2 => Offset(96 - along, 90 - bump),
          _ => Offset(6 + bump, 96 - along),
        };
        path.lineTo(point.dx, point.dy);
      }
      switch (side) {
        case 0:
          path.quadraticBezierTo(90, 6, 90, 10);
        case 1:
          path.quadraticBezierTo(90, 90, 86, 90);
        case 2:
          path.quadraticBezierTo(6, 90, 6, 86);
        case 3:
          path.quadraticBezierTo(6, 6, 10, 6);
      }
    }
    path.close();
    if (key.raised) {
      canvas.drawShadow(
        path.shift(const Offset(0, 2)),
        key.shadow.withValues(alpha: .2),
        4,
        true,
      );
    }
    canvas.drawPath(path, Paint()..color = key.paper.withValues(alpha: 1));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = key.ink.withValues(alpha: .07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    final metric = path.computeMetrics().single;
    final fibers = <Offset>[];
    for (var i = 0; i < 100; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / 100)!;
      final inward = Offset(-tangent.vector.dy, tangent.vector.dx);
      final start = tangent.position + inward * (random.nextDouble() * 4);
      fibers.addAll([
        start,
        start + tangent.vector * (1 + random.nextDouble() * 2) + inward * .4,
      ]);
    }
    canvas.drawPoints(
      ui.PointMode.lines,
      fibers,
      Paint()
        ..color = key.ink.withValues(alpha: .15)
        ..strokeWidth = .65
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (_tileSize * _rasterScale).toInt(),
      (_tileSize * _rasterScale).toInt(),
    );
    picture.dispose();
    return image;
  }

  @override
  bool shouldRepaint(DiaryPaperStamp oldDelegate) =>
      paper != oldDelegate.paper ||
      ink != oldDelegate.ink ||
      shadowColor != oldDelegate.shadowColor ||
      shadow != oldDelegate.shadow ||
      variant % 3 != oldDelegate.variant % 3 ||
      edgeScale != oldDelegate.edgeScale ||
      opacity != oldDelegate.opacity ||
      flatten != oldDelegate.flatten;
}
