import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';

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
    this.shape = const DiaryPaperShape(),
    this.ink,
    this.visible = true,
    this.flat = false,
    this.warm = false,
  });

  final double progress;
  final int direction;
  final double travel;
  final Color paper;
  final DiaryPaperShape shape;
  final Color? ink;
  final bool visible, flat, warm;

  Color get _ink =>
      ink ??
      (paper.computeLuminance() < .3
          ? const Color(0xffeeeeee)
          : const Color(0xff222222));

  @override
  RenderDiaryCurl createRenderObject(BuildContext context) => RenderDiaryCurl(
    progress,
    direction,
    travel,
    paper,
    math.min(2, MediaQuery.devicePixelRatioOf(context)),
    shape,
    _ink,
    visible,
    flat,
    warm,
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
      math.min(2, MediaQuery.devicePixelRatioOf(context)),
      shape,
      _ink,
      visible,
      flat,
      warm,
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
    this._shape,
    this._ink,
    this._visible,
    this._flat,
    this._warm,
  );

  double _progress;
  int _direction;
  double _travel;
  Color _paper;
  double _pixelRatio;
  DiaryPaperShape _shape;
  Color _ink;
  bool _visible, _flat, _warm;
  bool _disposed = false, _warmScheduled = false;
  int _frontGeneration = 0, _backGeneration = 0;
  Future<void>? _preparingFront, _preparingBack;
  ui.Image? _front;
  ui.ImageShader? _texture;
  ui.Image? _backImage;
  ui.ImageShader? _backTexture;
  int _frontCaptures = 0, _backCaptures = 0, _meshDraws = 0;

  @visibleForTesting
  int get debugFrontCaptures => _frontCaptures;
  @visibleForTesting
  int get debugBackCaptures => _backCaptures;
  @visibleForTesting
  int get debugMeshDraws => _meshDraws;
  @visibleForTesting
  Size? get debugTextureSize => _front == null
      ? null
      : Size(_front!.width.toDouble(), _front!.height.toDouble());

  @override
  bool get isRepaintBoundary => true;

  @visibleForTesting
  bool get debugReady => _front != null && _backImage != null;

  void update(
    double progress,
    int direction,
    double travel,
    Color paper,
    double pixelRatio,
    DiaryPaperShape shape,
    Color ink,
    bool visible,
    bool flat,
    bool warm,
  ) {
    final changed =
        progress != _progress ||
        direction != _direction ||
        travel != _travel ||
        paper != _paper ||
        pixelRatio != _pixelRatio ||
        shape != _shape ||
        ink != _ink ||
        visible != _visible ||
        flat != _flat;
    if (paper != _paper ||
        pixelRatio != _pixelRatio ||
        shape != _shape ||
        ink != _ink) {
      _discardFaces();
    }
    _progress = progress;
    _direction = direction;
    _travel = travel;
    _paper = paper;
    _pixelRatio = pixelRatio;
    _shape = shape;
    _ink = ink;
    _visible = visible;
    _flat = flat;
    _warm = warm;
    if (warm) _scheduleWarm();
    // Movement only changes the projection; the front texture is shared
    // by all strips and all frames of this turn.
    if (changed) super.markNeedsPaint();
  }

  void _discardFaces() {
    _discardFront();
    _backGeneration++;
    _backTexture?.dispose();
    _backTexture = null;
    _backImage?.dispose();
    _backImage = null;
  }

  void _discardFront() {
    _frontGeneration++;
    _texture?.dispose();
    _texture = null;
    _front?.dispose();
    _front = null;
  }

  ui.Picture _recordBack() {
    // This material never records the child. A filtered front texture can
    // retain its widget alpha (and depends on backend filter support), whereas
    // the reverse of the sheet must be opaque even when its front has holes.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixelRatio);
    DiaryPaperPainter(
      shape: _shape,
      paper: _paper,
      ink: _ink,
      reverse: true,
    ).paint(canvas, size);
    assert(() {
      _backCaptures++;
      return true;
    }());
    return recorder.endRecording();
  }

  ui.Picture _recordFront() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixelRatio);
    canvas.clipPath(_shape.path(size));
    _RecordingContext(
      canvas,
      Offset.zero & size,
    ).paintChild(child!, Offset.zero);
    assert(() {
      _frontCaptures++;
      return true;
    }());
    return recorder.endRecording();
  }

  ui.ImageShader _shader(ui.Image image) => ui.ImageShader(
    image,
    TileMode.clamp,
    TileMode.clamp,
    Matrix4.identity().storage,
    filterQuality: FilterQuality.high,
  );

  ui.ImageShader _createBackTexture() {
    final picture = _recordBack();
    _backImage = picture.toImageSync(
      (size.width * _pixelRatio).ceil(),
      (size.height * _pixelRatio).ceil(),
    );
    picture.dispose();
    return _shader(_backImage!);
  }

  /// Prepare fixed-size neighboring faces between gestures, using asynchronous
  /// rasterization instead of allocating their images on the first drag frame.
  Future<void> prepareTextures() async {
    if (_disposed || !attached || child == null || !hasSize || size.isEmpty) {
      return;
    }
    final tasks = <Future<void>>[];
    if (_front == null) tasks.add(_preparingFront ??= _prepareFace(false));
    if (_backImage == null) tasks.add(_preparingBack ??= _prepareFace(true));
    await Future.wait(tasks);
  }

  Future<void> _prepareFace(bool back) async {
    final generation = back ? _backGeneration : _frontGeneration;
    final picture = back ? _recordBack() : _recordFront();
    try {
      final image = await picture.toImage(
        (size.width * _pixelRatio).ceil(),
        (size.height * _pixelRatio).ceil(),
      );
      if (_disposed ||
          generation != (back ? _backGeneration : _frontGeneration) ||
          (back ? _backImage != null : _front != null)) {
        image.dispose();
        return;
      }
      if (back) {
        _backImage = image;
        _backTexture = _shader(image);
      } else {
        _front = image;
        _texture = _shader(image);
      }
      if (_visible && (!back || !_flat)) super.markNeedsPaint();
    } finally {
      picture.dispose();
      if (back) {
        _preparingBack = null;
      } else {
        _preparingFront = null;
      }
      if (!_disposed && _warm) _scheduleWarm();
    }
  }

  void _scheduleWarm() {
    // Descendants can request repaint during their own independent layout.
    // Reading our size then violates RenderBox's layout contract, even when
    // hasSize is true. prepareTextures checks geometry after the frame instead.
    if (_disposed ||
        _warmScheduled ||
        !attached ||
        ((_front != null || _preparingFront != null) &&
            (_backImage != null || _preparingBack != null))) {
      return;
    }
    _warmScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _warmScheduled = false;
      if (!_disposed && _warm && attached) prepareTextures();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void markNeedsPaint() {
    // The reverse is independent of front widgets, including their alpha.
    _discardFront();
    super.markNeedsPaint();
    if (_warm) _scheduleWarm();
  }

  @override
  void performLayout() {
    final before = hasSize ? size : null;
    super.performLayout();
    if (before != size) {
      _discardFaces();
    } else {
      _discardFront();
    }
    if (_warm) _scheduleWarm();
  }

  @override
  void dispose() {
    _disposed = true;
    _discardFaces();
    super.dispose();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  Rect get paintBounds {
    if (!_visible) return Rect.zero;
    if (_flat) return (Offset.zero & size).inflate(16);
    return Rect.fromLTRB(
      -_travel - size.width,
      -size.height * .2,
      size.width * 2 + _travel,
      size.height * 1.2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_visible || child == null || size.isEmpty) return;
    assert(!child!.needsCompositing, 'Curl faces must be static card content.');
    if (_front == null) {
      final picture = _recordFront();
      _front = picture.toImageSync(
        (size.width * _pixelRatio).ceil(),
        (size.height * _pixelRatio).ceil(),
      );
      picture.dispose();
      _texture = _shader(_front!);
    }
    if (_flat) {
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      final path = _shape.path(size);
      canvas.drawShadow(
        path.shift(const Offset(0, 3)),
        const Color(0x38000000),
        6,
        true,
      );
      canvas.drawShadow(path, const Color(0x1f000000), 1.2, true);
      canvas.drawImageRect(
        _front!,
        Rect.fromLTWH(
          0,
          0,
          _front!.width.toDouble(),
          _front!.height.toDouble(),
        ),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.low,
      );
      canvas.restore();
      return;
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

    // Project the actual deckled outline, so the cast shadow never falls
    // back to a rectangular silhouette while the visible edge bends.
    final outline = _shape.outline(size).map((source) {
      final position =
          (_direction > 0 ? source.dx / w : 1 - source.dx / w) * bands;
      final index = position.floor().clamp(0, bands - 1);
      final fraction = (position - index).clamp(0.0, 1.0);
      final a = points[index];
      final b = points[index + 1];
      final scale = a.scale + (b.scale - a.scale) * fraction;
      return Offset(
        a.x + (b.x - a.x) * fraction,
        h / 2 + (source.dy - h / 2) * scale,
      );
    }).toList();
    final silhouette = DiaryPaperShape.pathFromOutline(outline);
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
    // Submit contiguous faces as meshes rather than issuing 56 separate GPU
    // draws. Keep the original depth order, including overlapping rolled edges.
    final positions = <Offset>[];
    final coordinates = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];
    bool? batchBack;
    assert(() {
      _meshDraws = 0;
      return true;
    }());
    void flush() {
      if (positions.isEmpty) return;
      final mesh = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: coordinates,
        colors: colors,
        indices: indices,
      );
      canvas.drawVertices(
        mesh,
        BlendMode.modulate,
        Paint()
          ..shader = batchBack!
              ? (_backTexture ??= _createBackTexture())
              : _texture,
      );
      mesh.dispose();
      assert(() {
        _meshDraws++;
        return true;
      }());
      positions.clear();
      coordinates.clear();
      colors.clear();
      indices.clear();
    }

    for (final i in order) {
      final a = points[_direction > 0 ? i : i + 1];
      final b = points[_direction > 0 ? i + 1 : i];
      final sx = (_direction > 0 ? i : bands - i - 1) * strip;
      final dx = b.x - a.x;
      if (dx.abs() < .001) continue;
      final normal = math.cos(angleAt((i + .5) / bands));
      final back = normal < 0;
      if (batchBack != null && back != batchBack) flush();
      batchBack = back;
      Color shadeAt(int edge) => Color.lerp(
        const Color(0xffffffff),
        const Color(0xff000000),
        (1 - math.cos(angleAt(edge / bands)).abs()) * .17 + lift * .025,
      )!;
      final ca = back
          ? const Color(0xffffffff)
          : shadeAt(_direction > 0 ? i : i + 1);
      final cb = back
          ? const Color(0xffffffff)
          : shadeAt(_direction > 0 ? i + 1 : i);
      final vertex = positions.length;
      positions.addAll([
        Offset(a.x, h * (1 - a.scale) / 2),
        Offset(b.x, h * (1 - b.scale) / 2),
        Offset(a.x, h * (1 + a.scale) / 2),
        Offset(b.x, h * (1 + b.scale) / 2),
      ]);
      coordinates.addAll([
        Offset(sx * _pixelRatio, 0),
        Offset((sx + strip) * _pixelRatio, 0),
        Offset(sx * _pixelRatio, h * _pixelRatio),
        Offset((sx + strip) * _pixelRatio, h * _pixelRatio),
      ]);
      colors.addAll([ca, cb, ca, cb]);
      indices.addAll([
        vertex,
        vertex + 1,
        vertex + 2,
        vertex + 2,
        vertex + 1,
        vertex + 3,
      ]);
    }
    flush();
    canvas.restore();
  }
}
