import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A loose sheet, rather than a page attached to a book's spine. Its trailing
/// edge rolls back as the whole sheet travels out of the diary viewport.
/// [child] is a static, non-composited presentation of the card's front.
class DiaryPaperCurl extends SingleChildRenderObjectWidget {
  const DiaryPaperCurl({
    super.key,
    required this.progress,
    required this.direction,
    required this.travel,
    required this.paper,
    required super.child,
  });

  final double progress;
  final int direction;
  final double travel;
  final Color paper;

  @override
  RenderDiaryCurl createRenderObject(BuildContext context) => RenderDiaryCurl(
    progress,
    direction,
    travel,
    paper,
    MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDiaryCurl renderObject,
  ) {
    renderObject.update(
      progress,
      direction,
      travel,
      paper,
      MediaQuery.devicePixelRatioOf(context),
    );
  }
}

class _RecordingContext extends PaintingContext {
  _RecordingContext(this.recordingCanvas, Rect bounds)
    : super(ContainerLayer(), bounds);

  final Canvas recordingCanvas;

  @override
  Canvas get canvas => recordingCanvas;
}

class RenderDiaryCurl extends RenderProxyBox {
  RenderDiaryCurl(
    this._progress,
    this._direction,
    this._travel,
    this._paper,
    this._pixelRatio,
  );

  double _progress;
  int _direction;
  double _travel;
  Color _paper;
  double _pixelRatio;
  ui.Image? _front;
  ui.ImageShader? _texture;
  ui.Image? _backImage;
  ui.ImageShader? _backTexture;

  void update(
    double progress,
    int direction,
    double travel,
    Color paper,
    double pixelRatio,
  ) {
    if (paper != _paper || pixelRatio != _pixelRatio) _discardFaces();
    _progress = progress;
    _direction = direction;
    _travel = travel;
    _paper = paper;
    _pixelRatio = pixelRatio;
    // Movement only changes the projection; the front texture is shared
    // by all strips and all frames of this turn.
    super.markNeedsPaint();
  }

  void _discardFaces() {
    _texture?.dispose();
    _texture = null;
    _front?.dispose();
    _front = null;
    _backTexture?.dispose();
    _backTexture = null;
    _backImage?.dispose();
    _backImage = null;
  }

  ui.ImageShader _createBackTexture() {
    // This material never records the child. A filtered front texture can
    // retain its widget alpha (and depends on backend filter support), whereas
    // the reverse of the sheet must be opaque even when its front has holes.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixelRatio);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)),
      Paint()..color = _paper.withValues(alpha: 1),
    );
    final picture = recorder.endRecording();
    _backImage = picture.toImageSync(
      (size.width * _pixelRatio).ceil(),
      (size.height * _pixelRatio).ceil(),
    );
    picture.dispose();
    return ui.ImageShader(
      _backImage!,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.high,
    );
  }

  @override
  void markNeedsPaint() {
    _discardFaces();
    super.markNeedsPaint();
  }

  @override
  void performLayout() {
    _discardFaces();
    super.performLayout();
  }

  @override
  void dispose() {
    _discardFaces();
    super.dispose();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  Rect get paintBounds => Rect.fromLTRB(
    -_travel - size.width,
    -size.height * .2,
    size.width * 2 + _travel,
    size.height * 1.2,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    assert(!child!.needsCompositing, 'Curl faces must be static card content.');
    if (_front == null) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(_pixelRatio);
      final recording = _RecordingContext(canvas, Offset.zero & size);
      recording.paintChild(child!, Offset.zero);
      final picture = recorder.endRecording();
      _front = picture.toImageSync(
        (size.width * _pixelRatio).ceil(),
        (size.height * _pixelRatio).ceil(),
      );
      picture.dispose();
      _texture = ui.ImageShader(
        _front!,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.high,
      );
    }

    final t = _progress.clamp(0.0, 1.0);
    final lift = math.sin(math.pi * t);
    // A wider roll and a little more lift make the fold visible early in the
    // drag, while both ends of the turn still settle into a flat sheet.
    double angleAt(double u) => lift * 3.6 * math.pow(1 - u, 1.7);
    final w = size.width;
    final h = size.height;
    const bands = 56;
    final strip = w / bands;
    final points = <({double x, double scale, double depth})>[];
    double x = 0;
    double z = 0;
    for (var i = 0; i <= bands; i++) {
      if (i > 0) {
        final u = (i - .5) / bands;
        final angle = angleAt(u);
        x += math.cos(angle) * strip;
        z += math.sin(angle) * strip;
      }
      points.add((
        x: (_direction > 0 ? x : w - x) + _direction * _travel * t,
        scale: 1,
        depth: z,
      ));
    }
    // The free trailing edge is above the sheet, not tucked underneath it.
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final depth = z - p.depth;
      points[i] = (x: p.x, scale: 1 + depth / (w * 5.5), depth: depth);
    }

    final silhouette = Path();
    for (var i = 0; i <= bands; i++) {
      final p = points[i];
      final top = h * (1 - p.scale) / 2;
      if (i == 0) {
        silhouette.moveTo(p.x, top);
      } else {
        silhouette.lineTo(p.x, top);
      }
    }
    for (final p in points.reversed) {
      silhouette.lineTo(p.x, h * (1 + p.scale) / 2);
    }
    silhouette.close();
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawShadow(
      silhouette,
      const Color(0xff211b28).withValues(alpha: .32 * lift),
      3 + 11 * lift,
      true,
    );

    // Far strips first: a rolled edge can overlap the face underneath it.
    final order = List.generate(bands, (i) => i)
      ..sort((a, b) => points[a].depth.compareTo(points[b].depth));
    for (final i in order) {
      final a = points[_direction > 0 ? i : i + 1];
      final b = points[_direction > 0 ? i + 1 : i];
      final sx = (_direction > 0 ? i : bands - i - 1) * strip;
      final dx = b.x - a.x;
      if (dx.abs() < .001) continue;
      final normal = math.cos(angleAt((i + .5) / bands));
      final back = normal < 0;
      Color shadeAt(int edge) => Color.lerp(
        const Color(0xffffffff),
        const Color(0xff35281e),
        (1 - math.cos(angleAt(edge / bands)).abs()) * .17 + lift * .025,
      )!;
      final ca = back
          ? const Color(0xffffffff)
          : shadeAt(_direction > 0 ? i : i + 1);
      final cb = back
          ? const Color(0xffffffff)
          : shadeAt(_direction > 0 ? i + 1 : i);
      final mesh = ui.Vertices(
        ui.VertexMode.triangles,
        [
          Offset(a.x, h * (1 - a.scale) / 2),
          Offset(b.x, h * (1 - b.scale) / 2),
          Offset(a.x, h * (1 + a.scale) / 2),
          Offset(b.x, h * (1 + b.scale) / 2),
        ],
        textureCoordinates: [
          Offset(sx * _pixelRatio, 0),
          Offset((sx + strip) * _pixelRatio, 0),
          Offset(sx * _pixelRatio, h * _pixelRatio),
          Offset((sx + strip) * _pixelRatio, h * _pixelRatio),
        ],
        colors: [ca, cb, ca, cb],
        indices: [0, 1, 2, 2, 1, 3],
      );
      final paint = Paint()
        ..shader = back ? (_backTexture ??= _createBackTexture()) : _texture;
      canvas.drawVertices(mesh, BlendMode.modulate, paint);
      mesh.dispose();
    }
    canvas.restore();
  }
}
