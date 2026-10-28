import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';

/// The inside-cover material shared by More and its future detail pages.
/// Keep the selected font and accent; add warmth through the substrate only.
class MorePalette {
  MorePalette.of(BuildContext context) {
    final colors = context.colors;
    final dark = colors.brightness == Brightness.dark;
    ground = Color.lerp(
      colors.surface,
      dark ? const Color(0xff272720) : const Color(0xffeee8da),
      dark ? .28 : .62,
    )!;
    paper = Color.lerp(
      colors.surface,
      dark ? const Color(0xff34332c) : const Color(0xfffffcf3),
      .66,
    )!;
    ink = colors.onSurface;
    muted = Color.lerp(colors.onSurfaceVariant, ground, .12)!;
    accent = colors.primary;
    rule = ink.withValues(alpha: dark ? .20 : .16);
    cloth = Color.lerp(ground, accent, dark ? .10 : .06)!;
  }

  late final Color ground, paper, ink, muted, accent, rule, cloth;

  TextStyle get label => TextStyle(
    color: muted,
    fontSize: 10,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.7,
  );
}

class MoreSurface extends StatelessWidget {
  const MoreSurface({super.key, required this.child});

  static const contentWidth = 620.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = MorePalette.of(context);
    return ColoredBox(
      color: palette.ground,
      child: CustomPaint(painter: _CoverTexture(palette), child: child),
    );
  }
}

class _CoverTexture extends CustomPainter {
  const _CoverTexture(this.palette);

  final MorePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final thread = Paint()
      ..strokeWidth = .5
      ..color = palette.ink.withValues(alpha: .014);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thread);
    }
    thread.color = palette.ink.withValues(alpha: .009);
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thread);
    }
    // Align the seam with the content column, including inside pinned headers.
    final bindingStart = ((size.width - MoreSurface.contentWidth) / 2).clamp(
      0.0,
      double.infinity,
    );
    canvas.drawRect(
      Rect.fromLTWH(bindingStart, 0, 8, size.height),
      Paint()..color = palette.accent.withValues(alpha: .045),
    );
    thread.color = palette.accent.withValues(alpha: .16);
    for (double y = 6; y < size.height; y += 9) {
      canvas.drawLine(
        Offset(bindingStart + 13, y),
        Offset(bindingStart + 13, y + 3),
        thread,
      );
    }
  }

  @override
  bool shouldRepaint(_CoverTexture oldDelegate) =>
      palette.ground != oldDelegate.palette.ground ||
      palette.ink != oldDelegate.palette.ink ||
      palette.accent != oldDelegate.palette.accent;
}

/// A small printer's ornament, also suitable for detail-page mastheads.
class MoreOrnament extends StatelessWidget {
  const MoreOrnament({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _OrnamentPainter(MorePalette.of(context).accent),
      ),
    ),
  );
}

class _OrnamentPainter extends CustomPainter {
  const _OrnamentPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .38;
    final stroke = Paint()
      ..color = color.withValues(alpha: .75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9;
    for (var i = 0; i < 4; i++) {
      canvas.drawOval(
        Rect.fromLTWH(-radius, -radius * .35, radius, radius * .7),
        stroke,
      );
      canvas.rotate(1.57079632679);
    }
    canvas.drawCircle(Offset.zero, 1.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OrnamentPainter oldDelegate) =>
      color != oldDelegate.color;
}
