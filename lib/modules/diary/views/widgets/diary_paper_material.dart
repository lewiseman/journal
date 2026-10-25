import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

// Bounded caches retain geometry for the visible sheets, rather than building
// a texture or keeping a history of every day the reader has visited.
final _details = <int, _PaperDetail>{};
final _outlines = <({DiaryPaperShape shape, Size size}), _PaperOutline>{};

/// The material's single silhouette, shared by clips, paint and both curl faces.
@immutable
class DiaryPaperShape {
  const DiaryPaperShape({
    this.seed = 0,
    this.expansion = 0,
    this.cornerRadius = 6,
  });

  factory DiaryPaperShape.forDate(
    DateTime date, {
    double expansion = 0,
    double cornerRadius = 6,
  }) => DiaryPaperShape(
    seed:
        DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay,
    expansion: expansion,
    cornerRadius: cornerRadius,
  );

  final int seed;
  final double expansion;
  final double cornerRadius;

  double get detail => 1 - expansion.clamp(0.0, 1.0);

  _PaperDetail get _paperDetail {
    final cached = _details.remove(seed) ?? _PaperDetail(seed);
    _details[seed] = cached;
    if (_details.length > 8) _details.remove(_details.keys.first);
    return cached;
  }

  _PaperOutline _outline(Size size) {
    final key = (shape: this, size: size);
    final cached = _outlines.remove(key);
    if (cached != null) {
      _outlines[key] = cached;
      return cached;
    }
    final value = _makeOutline(size);
    _outlines[key] = value;
    if (_outlines.length > 12) _outlines.remove(_outlines.keys.first);
    return value;
  }

  _PaperOutline _makeOutline(Size size) {
    if (size.isEmpty) return _PaperOutline(const [], Path());
    if (detail == 0) {
      return _PaperOutline([
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ], Path()..addRect(Offset.zero & size));
    }
    final amount = detail * (size.shortestSide / 30).clamp(0.0, 1.0);
    final bounds = (Offset.zero & size).deflate(6 * amount);
    final radius = math.min(cornerRadius * detail, bounds.shortestSide / 3);
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(bounds, Radius.circular(radius)));
    final metric = base.computeMetrics().single;
    final grain = _paperDetail;
    // Fixed sample phases and continuous noise keep bumps from crawling when
    // the sheet changes size. The frequencies never depend on frame count.
    final points = List<Offset>.generate(768, (i) {
      final u = i / 768;
      final tangent = metric.getTangentForOffset(metric.length * u)!;
      final inward = Offset(-tangent.vector.dy, tangent.vector.dx);
      var displacement =
          _noise(grain.broad, u) * 2.8 +
          _noise(grain.fine, u) * 2 +
          _noise(grain.micro, u) * .8;
      for (final tear in grain.tears) {
        final notch = tear.profile(tangent.position, inward, bounds);
        // Leave a small, asymmetric bite in the edge. Ease the grain beneath
        // it so a nearby outward bump cannot hide the tear's tip.
        displacement = displacement * (1 - notch) + tear.depth * notch;
      }
      return tangent.position + inward * (amount * displacement);
    });
    return _PaperOutline(List.unmodifiable(points), pathFromOutline(points));
  }

  Path path(Size size) => _outline(size).path;
  List<Offset> outline(Size size) => _outline(size).points;

  static Path pathFromOutline(List<Offset> points) {
    if (points.isEmpty) return Path();
    final start = Offset.lerp(points.last, points.first, .5)!;
    final path = Path()..moveTo(start.dx, start.dy);
    for (var i = 0; i < points.length; i++) {
      final next = Offset.lerp(points[i], points[(i + 1) % points.length], .5)!;
      path.quadraticBezierTo(points[i].dx, points[i].dy, next.dx, next.dy);
    }
    return path..close();
  }

  @override
  bool operator ==(Object other) =>
      other is DiaryPaperShape &&
      seed == other.seed &&
      expansion == other.expansion &&
      cornerRadius == other.cornerRadius;

  @override
  int get hashCode => Object.hash(seed, expansion, cornerRadius);
}

double _noise(List<double> values, double u) {
  final position = u * values.length;
  final i = position.floor();
  final t = position - i;
  final smooth = t * t * (3 - 2 * t);
  return values[i % values.length] * (1 - smooth) +
      values[(i + 1) % values.length] * smooth;
}

class _PaperOutline {
  _PaperOutline(this.points, this.path);
  final List<Offset> points;
  final Path path;

  ({Offset point, Offset tangent}) at(double u) {
    final position = u * points.length;
    final i = position.floor() % points.length;
    final next = (i + 1) % points.length;
    final before = (i + points.length - 1) % points.length;
    final delta = points[next] - points[before];
    return (
      point: Offset.lerp(points[i], points[next], position - position.floor())!,
      tangent: delta / math.max(.001, delta.distance),
    );
  }
}

class _PaperTear {
  const _PaperTear({
    required this.edge,
    required this.position,
    required this.halfWidth,
    required this.depth,
    required this.lean,
  });

  final int edge;
  final double position, halfWidth, depth, lean;

  double profile(Offset point, Offset inward, Rect bounds) {
    final normal = switch (edge) {
      0 => const Offset(0, 1),
      1 => const Offset(-1, 0),
      2 => const Offset(0, -1),
      _ => const Offset(1, 0),
    };
    // Only the chosen straight edge is torn; corners stay softly rounded.
    if ((inward - normal).distanceSquared > .001) return 0;
    final horizontal = edge.isEven;
    final along = horizontal ? point.dx : point.dy;
    final center = horizontal
        ? bounds.left + bounds.width * position
        : bounds.top + bounds.height * position;
    final t = (along - center) / halfWidth;
    if (t <= -1 || t >= 1) return 0;
    final ramp = t < lean ? (t + 1) / (lean + 1) : (1 - t) / (1 - lean);
    return math.pow(ramp, 1.15).toDouble();
  }
}

class _PaperDetail {
  _PaperDetail(int seed) {
    final random = math.Random(seed);
    broad = List.generate(24, (_) => random.nextDouble() * 2 - 1);
    fine = List.generate(160, (_) => random.nextDouble() * 2 - 1);
    micro = List.generate(384, (_) => random.nextDouble() * 2 - 1);
    fibers = List.generate(
      520,
      (i) => (
        u: (i + random.nextDouble()) / 520,
        depth: math.pow(random.nextDouble(), 2).toDouble(),
        length: .6 + random.nextDouble() * 2.6,
        slant: random.nextDouble() * 1.4 - .7,
        tone: random.nextInt(5),
      ),
    );
    backGrain = List.generate(
      1024,
      (_) => (
        x: random.nextDouble(),
        y: random.nextDouble(),
        length: .6 + random.nextDouble() * 2.6,
        angle: random.nextDouble() * math.pi * 2,
        tone: random.nextInt(5),
      ),
    );
    // A separate stream preserves the existing fibers and edge grain. Each
    // day gets just one to three small tears, on different sides, away from
    // corners. Relative placement keeps them attached during sheet resizing.
    final tearRandom = math.Random(seed ^ 0x74656172);
    final count = 1 + tearRandom.nextInt(3);
    final edges = [0, 1, 2, 3]..shuffle(tearRandom);
    tears = List.generate(
      count,
      (i) => _PaperTear(
        edge: edges[i],
        position: .18 + tearRandom.nextDouble() * .64,
        halfWidth: 5.5 + tearRandom.nextDouble() * 3.5,
        depth: 14 + tearRandom.nextDouble() * 4,
        lean: tearRandom.nextDouble() * .5 - .25,
      ),
    );
  }

  late final List<double> broad, fine, micro;
  late final List<_PaperTear> tears;
  late final List<
    ({double u, double depth, double length, double slant, int tone})
  >
  fibers;
  late final List<({double x, double y, double length, double angle, int tone})>
  backGrain;
}

class DiaryPaperClipper extends CustomClipper<Path> {
  const DiaryPaperClipper(this.shape, {this.viewport});
  final DiaryPaperShape shape;
  final Rect? viewport;

  @override
  Path getClip(Size size) {
    final rect = viewport ?? Offset.zero & size;
    return shape.path(rect.size).shift(rect.topLeft);
  }

  @override
  bool shouldReclip(DiaryPaperClipper oldClipper) =>
      shape != oldClipper.shape || viewport != oldClipper.viewport;
}

/// Paints onto an opaque base; wear changes the material color, never its alpha.
/// This painter also builds the reverse texture without recording any widgets.
class DiaryPaperPainter extends CustomPainter {
  const DiaryPaperPainter({
    required this.shape,
    required this.paper,
    required this.ink,
    this.reverse = false,
    this.shadow = false,
    this.shadowColor = const Color(0xff000000),
  });

  final DiaryPaperShape shape;
  final Color paper, ink, shadowColor;
  final bool reverse, shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = shape.path(size);
    final detail = shape.detail;
    if (shadow && detail > 0) {
      canvas.drawShadow(
        path.shift(Offset(0, 3 * detail)),
        shadowColor.withValues(alpha: .22 * detail),
        6 * detail,
        true,
      );
      canvas.drawShadow(
        path,
        shadowColor.withValues(alpha: .12 * detail),
        1.2 * detail,
        true,
      );
    }
    canvas.drawPath(path, Paint()..color = paper.withValues(alpha: 1));
    if (detail == 0) return;

    final rim = reverse ? 12.0 : 8.0;
    final strength = detail * (reverse ? 1.5 : 1.0);
    final source = shape._paperDetail;
    final edge = shape._outline(size);
    if (edge.points.isEmpty) return;
    canvas.save();
    canvas.clipPath(path);
    if (reverse) _paintReverseBody(canvas, size, source, strength);
    // A soft, shallow rim with broken deposits, rather than a drawn border.
    canvas.drawPath(
      path,
      Paint()
        ..color = ink.withValues(alpha: .05 * strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim * 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final metric = path.computeMetrics().single;
    for (var i = 0; i < 48; i++) {
      final tone = (_noise(source.broad, i / 48) + 1) / 2;
      canvas.drawPath(
        metric.extractPath(
          metric.length * i / 48,
          metric.length * (i + .7) / 48,
        ),
        Paint()
          ..color = ink.withValues(alpha: (.018 + .045 * tone) * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = rim * (.8 + tone * .7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
      );
    }

    final fibers = List.generate(5, (_) => <Offset>[]);
    for (final fiber in source.fibers) {
      final sample = edge.at(fiber.u);
      final inward = Offset(-sample.tangent.dy, sample.tangent.dx);
      final start = sample.point + inward * (.4 + fiber.depth * rim * detail);
      final direction =
          sample.tangent * math.cos(fiber.slant) +
          inward * math.sin(fiber.slant);
      fibers[fiber.tone].addAll([start, start + direction * fiber.length]);
    }
    _paintFibers(canvas, fibers, strength);
    canvas.restore();
  }

  void _paintReverseBody(
    Canvas canvas,
    Size size,
    _PaperDetail source,
    double strength,
  ) {
    // The reverse carries the same worn fibers throughout, not just at its
    // perimeter. Fixed logical cells keep their density and positions stable
    // as the sheet is resized, and the curl caches this material once per turn.
    const cell = 6.0;
    final fibers = List.generate(5, (_) => <Offset>[]);
    for (var row = 0; row * cell < size.height; row++) {
      for (var column = 0; column * cell < size.width; column++) {
        final grain = source
            .backGrain[(row * 197 + column * 131) % source.backGrain.length];
        final start = Offset((column + grain.x) * cell, (row + grain.y) * cell);
        final direction = Offset(math.cos(grain.angle), math.sin(grain.angle));
        fibers[grain.tone].addAll([start, start + direction * grain.length]);
      }
    }

    // Broad, low-contrast variations give the fibers a worn paper bed without
    // changing the opaque base or introducing any of the front-side widgets.
    const patchCell = 32.0;
    for (var row = 0; row * patchCell < size.height; row++) {
      for (var column = 0; column * patchCell < size.width; column++) {
        final grain = source
            .backGrain[(row * 83 + column * 241) % source.backGrain.length];
        final center = Offset(
          (column + grain.x) * patchCell,
          (row + grain.y) * patchCell,
        );
        final radius = 18 + grain.y * 22;
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = ui.Gradient.radial(center, radius, [
              ink.withValues(alpha: (.012 + grain.x * .035) * strength),
              ink.withValues(alpha: 0),
            ]),
        );
      }
    }
    _paintFibers(canvas, fibers, strength);
  }

  void _paintFibers(Canvas canvas, List<List<Offset>> fibers, double strength) {
    for (var tone = 0; tone < fibers.length; tone++) {
      final highlight = tone == 4;
      canvas.drawPoints(
        ui.PointMode.lines,
        fibers[tone],
        Paint()
          ..color =
              (highlight
                      ? Color.lerp(paper, const Color(0xffffffff), .65)!
                      : ink)
                  .withValues(
                    alpha: (highlight ? .22 : .065 + tone * .028) * strength,
                  )
          ..strokeWidth = highlight ? .65 : .6 + tone * .12
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(DiaryPaperPainter oldDelegate) =>
      shape != oldDelegate.shape ||
      paper != oldDelegate.paper ||
      ink != oldDelegate.ink ||
      reverse != oldDelegate.reverse ||
      shadow != oldDelegate.shadow ||
      shadowColor != oldDelegate.shadowColor;
}
