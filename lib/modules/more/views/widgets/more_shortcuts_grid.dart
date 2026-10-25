import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';

/// Collection entry points, ready for navigation as their screens are added.
class MoreShortcutsGrid extends StatelessWidget {
  const MoreShortcutsGrid({
    super.key,
    this.onWatchlist,
    this.onBirthdays,
    this.onBucketList,
  });

  final VoidCallback? onWatchlist;
  final VoidCallback? onBirthdays;
  final VoidCallback? onBucketList;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -.35,
      height: 1.2,
    );
    final labelPainter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    var labelWidth = 0.0;
    var labelHeight = 0.0;
    for (final label in ['Watchlist', 'Birthdays', 'Bucket list']) {
      labelPainter.text = TextSpan(text: label, style: labelStyle);
      labelPainter.layout();
      labelWidth = math.max(labelWidth, labelPainter.width);
      labelHeight = math.max(labelHeight, labelPainter.height);
    }
    final minimumWidth = math.max(126.0, labelWidth + 32);
    labelPainter.dispose();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = constraints.maxWidth;
        final columns = width >= 520 && width >= minimumWidth * 3 + gap * 2
            ? 3
            : width >= minimumWidth * 2 + gap
            ? 2
            : 1;
        final cardWidth = (width - gap * (columns - 1)) / columns;
        final height = math.max(
          cardWidth / (columns == 1 ? 2.4 : 1.5),
          82 + labelHeight,
        );

        Widget card(
          _ShortcutKind kind,
          String label,
          Color accent,
          VoidCallback? onTap, {
          bool wide = false,
        }) => SizedBox(
          width: wide ? width : cardWidth,
          height: height,
          child: _ShortcutCard(
            kind: kind,
            label: label,
            labelStyle: labelStyle,
            accent: accent,
            onTap: onTap,
            wide:
                (wide || columns == 1) &&
                (wide ? width : cardWidth) - labelWidth >= 180,
          ),
        );

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            card(
              _ShortcutKind.watchlist,
              'Watchlist',
              dark ? const Color(0xFFC2B0F2) : const Color(0xFF6E50A6),
              onWatchlist,
            ),
            card(
              _ShortcutKind.birthdays,
              'Birthdays',
              dark ? const Color(0xFFF0B49E) : const Color(0xFFAD5943),
              onBirthdays,
            ),
            card(
              _ShortcutKind.bucketList,
              'Bucket list',
              dark ? const Color(0xFFA4CFBB) : const Color(0xFF417B64),
              onBucketList,
              wide: columns == 2,
            ),
          ],
        );
      },
    );
  }
}

enum _ShortcutKind { watchlist, birthdays, bucketList }

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.kind,
    required this.label,
    required this.labelStyle,
    required this.accent,
    required this.onTap,
    required this.wide,
  });

  final _ShortcutKind kind;
  final String label;
  final TextStyle labelStyle;
  final Color accent;
  final VoidCallback? onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = colors.brightness == Brightness.dark;
    final radius = BorderRadius.circular(22);
    final background = Color.alphaBlend(
      accent.withValues(alpha: dark ? .13 : .09),
      colors.surface,
    );

    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        key: ValueKey('more-${kind.name}'),
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: accent.withValues(alpha: dark ? .22 : .13)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: accent.withValues(alpha: .12),
          highlightColor: accent.withValues(alpha: .06),
          child: Stack(
            children: [
              PositionedDirectional(
                start: wide ? null : 6,
                end: wide ? 26 : null,
                top: wide ? -9 : -3,
                width: wide ? 146 : 90,
                height: wide ? 134 : 88,
                child: CustomPaint(
                  painter: _ShortcutArtwork(kind, accent, background),
                ),
              ),
              PositionedDirectional(
                top: 14,
                end: 14,
                child: Icon(
                  Icons.arrow_outward_rounded,
                  size: 17,
                  color: accent.withValues(alpha: .7),
                ),
              ),
              PositionedDirectional(
                start: 16,
                end: 16,
                bottom: 15,
                child: Text(
                  label,
                  style: labelStyle.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small, theme-aware line illustrations keep these cards light and crisp.
class _ShortcutArtwork extends CustomPainter {
  const _ShortcutArtwork(this.kind, this.ink, this.paper);

  final _ShortcutKind kind;
  final Color ink;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final wash = Paint()..color = ink.withValues(alpha: .09);
    final fill = Paint()..color = ink;
    canvas.drawCircle(const Offset(51, 50), 33, wash);

    switch (kind) {
      case _ShortcutKind.watchlist:
        canvas.save();
        canvas.translate(50, 50);
        canvas.rotate(-.14);
        final back = RRect.fromRectAndRadius(
          const Rect.fromLTWH(-23, -22, 45, 34),
          const Radius.circular(7),
        );
        canvas.drawRRect(back, wash);
        canvas.drawRRect(back, stroke..color = ink.withValues(alpha: .45));
        canvas.restore();
        final ticket = RRect.fromRectAndRadius(
          const Rect.fromLTWH(24, 37, 51, 35),
          const Radius.circular(7),
        );
        canvas.drawRRect(ticket, Paint()..color = paper);
        canvas.drawRRect(ticket, stroke..color = ink);
        canvas.drawLine(
          const Offset(35, 38),
          const Offset(35, 71),
          stroke..color = ink.withValues(alpha: .3),
        );
        for (final y in [44.0, 54.0, 64.0]) {
          canvas.drawCircle(Offset(29, y), 1.3, fill);
        }
        final play = Path()
          ..moveTo(49, 46)
          ..lineTo(49, 62)
          ..quadraticBezierTo(49, 64, 51, 63)
          ..lineTo(62, 56)
          ..quadraticBezierTo(64, 54, 62, 53)
          ..lineTo(51, 46)
          ..close();
        canvas.drawPath(play, fill);
        _spark(
          canvas,
          const Offset(79, 29),
          4,
          stroke..color = ink.withValues(alpha: .6),
        );
      case _ShortcutKind.birthdays:
        final cake = RRect.fromRectAndRadius(
          const Rect.fromLTWH(27, 49, 47, 25),
          const Radius.circular(6),
        );
        canvas.drawRRect(cake, Paint()..color = paper);
        canvas.drawRRect(cake, stroke);
        final icing = Path()
          ..moveTo(28, 55)
          ..quadraticBezierTo(34, 65, 40, 55)
          ..quadraticBezierTo(46, 65, 52, 55)
          ..quadraticBezierTo(58, 65, 64, 55)
          ..quadraticBezierTo(69, 63, 73, 55);
        canvas.drawPath(icing, stroke);
        canvas.drawLine(const Offset(23, 77), const Offset(78, 77), stroke);
        for (final x in [38.0, 51.0, 64.0]) {
          canvas.drawLine(Offset(x, 48), Offset(x, 39), stroke);
          final flame = Path()
            ..moveTo(x, 27)
            ..quadraticBezierTo(x - 7, 36, x, 36)
            ..quadraticBezierTo(x + 6, 35, x, 27);
          canvas.drawPath(flame, fill..color = ink.withValues(alpha: .7));
        }
        _spark(canvas, const Offset(25, 31), 3, stroke);
        canvas.drawCircle(
          const Offset(78, 42),
          2,
          wash..color = ink.withValues(alpha: .5),
        );
        canvas.drawLine(const Offset(72, 23), const Offset(75, 20), stroke);
      case _ShortcutKind.bucketList:
        final trail = Path()
          ..moveTo(18, 78)
          ..cubicTo(23, 60, 53, 85, 50, 65);
        final trailStroke = Paint()
          ..color = ink.withValues(alpha: .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round;
        for (final metric in trail.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 7) {
            canvas.drawPath(
              metric.extractPath(d, math.min(d + 3, metric.length)),
              trailStroke,
            );
          }
        }
        final mountains = Path()
          ..moveTo(29, 65)
          ..lineTo(48, 35)
          ..lineTo(66, 65)
          ..close();
        canvas.drawPath(mountains, Paint()..color = paper);
        canvas.drawPath(mountains, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(58, 51)
            ..lineTo(65, 42)
            ..lineTo(81, 65)
            ..lineTo(66, 65),
          stroke..color = ink.withValues(alpha: .55),
        );
        canvas.drawPath(
          Path()
            ..moveTo(41, 46)
            ..lineTo(48, 50)
            ..lineTo(54, 45),
          stroke..color = ink,
        );
        canvas.drawLine(const Offset(48, 35), const Offset(48, 20), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(49, 20)
            ..lineTo(63, 24)
            ..lineTo(49, 29)
            ..close(),
          fill,
        );
        canvas.drawCircle(const Offset(74, 29), 5, wash);
        _spark(
          canvas,
          const Offset(26, 39),
          3,
          stroke..color = ink.withValues(alpha: .55),
        );
    }
    canvas.restore();
  }

  void _spark(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      paint,
    );
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShortcutArtwork oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.ink != ink ||
      oldDelegate.paper != paper;
}
