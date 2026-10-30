import 'dart:math';

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';

import 'people_paper.dart';

/// A watercolour blob whose hue and wobble come from the friend's key, so
/// each person keeps the same little portrait on every screen.
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({
    super.key,
    required this.friendKey,
    required this.name,
    this.size = 56,
    this.hero = false,
  });
  final String friendKey, name;
  final double size;
  final bool hero;

  static int _seed(String key) {
    var value = 17;
    for (final unit in key.codeUnits.take(16)) {
      value = (value * 31 + unit) & 0x7fffffff;
    }
    return value;
  }

  static Color tint(BuildContext context, String key) {
    final seed = _seed(key);
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(
      1,
      hue,
      context.isDark ? .38 : .42,
      context.isDark ? .62 : .58,
    ).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final color = tint(context, friendKey);
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    Widget avatar = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BlobPainter(color, _seed(friendKey)),
        child: Center(
          child: Text(
            initial.toUpperCase(),
            textScaler: TextScaler.noScaling,
            style: peopleTitle(
              context,
              size: size * .52,
              color: PeoplePalette.of(context).ink,
            ),
          ),
        ),
      ),
    );
    if (hero) {
      avatar = Hero(tag: 'people-avatar-$friendKey', child: avatar);
    }
    return Semantics(label: name, excludeSemantics: true, child: avatar);
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter(this.color, this.seed);
  final Color color;
  final int seed;

  Path _blob(Size size, Random random, double inset) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - inset;
    final phases = List.generate(3, (_) => random.nextDouble() * pi * 2);
    final path = Path();
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final angle = i / steps * pi * 2;
      final wobble =
          1 +
          .06 * sin(angle * 2 + phases[0]) +
          .04 * sin(angle * 3 + phases[1]) +
          .025 * sin(angle * 5 + phases[2]);
      final point =
          center + Offset(cos(angle), sin(angle)) * radius * wobble * .94;
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    // Two offset washes overlap like a second pass of paint.
    canvas.drawPath(
      _blob(size, random, 0),
      Paint()..color = color.withValues(alpha: .38),
    );
    canvas.save();
    canvas.translate(size.width * .04, -size.height * .03);
    canvas.drawPath(
      _blob(size, random, size.shortestSide * .08),
      Paint()..color = color.withValues(alpha: .42),
    );
    canvas.restore();
    // A darker pigment edge, like a dried watercolour rim.
    canvas.drawPath(
      _blob(size, Random(seed), 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: .7),
    );
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.color != color || old.seed != seed;
}

/// A small red wax seal carrying a count, used as an unread badge.
class WaxBadge extends StatelessWidget {
  const WaxBadge({super.key, required this.count, this.size = 24});
  final int count;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: WaxSealPainter(PeoplePalette.of(context).wax),
      child: Center(
        child: Text(
          '$count',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .92),
            fontSize: size * .46,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// A scalloped wax seal. [crack] splits it in two for the opening animation.
class WaxSealPainter extends CustomPainter {
  const WaxSealPainter(this.color, {this.crack = 0});
  final Color color;
  final double crack;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final path = Path();
    const bumps = 11;
    for (var i = 0; i <= 88; i++) {
      final angle = i / 88 * pi * 2;
      final r = radius * (.9 + .07 * cos(angle * bumps));
      final point = center + Offset(cos(angle), sin(angle)) * r;
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
    final fill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.3, -.35),
        colors: [Color.lerp(color, Colors.white, .22)!, color],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * .08
      ..color = Colors.black.withValues(alpha: .14);

    if (crack == 0) {
      canvas.drawPath(path, fill);
      canvas.drawCircle(center, radius * .62, ring);
      return;
    }
    // Two halves drift apart and tilt as the seal breaks.
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(center.dx + side * crack * radius * .5, center.dy);
      canvas.rotate(side * crack * .5);
      canvas.translate(-center.dx, -center.dy);
      canvas.clipRect(
        side < 0
            ? Rect.fromLTRB(0, 0, center.dx, size.height)
            : Rect.fromLTRB(center.dx, 0, size.width, size.height),
      );
      canvas.drawPath(path, fill);
      canvas.drawCircle(center, radius * .62, ring);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(WaxSealPainter old) =>
      old.color != color || old.crack != crack;
}
