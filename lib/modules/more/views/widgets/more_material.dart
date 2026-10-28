import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';

/// Shared colors for More. The page keeps the app's surface color;
/// warmer materials belong to the account card and small illustrations.
class MorePalette {
  MorePalette.of(BuildContext context) {
    final colors = context.colors;
    final dark = colors.brightness == Brightness.dark;
    ground = colors.surface;
    paper = Color.lerp(
      colors.surface,
      dark ? const Color(0xff34332c) : const Color(0xfffffcf3),
      .66,
    )!;
    ink = colors.onSurface;
    muted = Color.lerp(colors.onSurfaceVariant, ground, .12)!;
    accent = colors.primary;
    rule = ink.withValues(alpha: dark ? .20 : .16);
    cloth = Color.lerp(paper, accent, dark ? .10 : .06)!;
  }

  late final Color ground, paper, ink, muted, accent, rule, cloth;
}

class MoreSurface extends StatelessWidget {
  const MoreSurface({super.key, required this.child});

  static const contentWidth = 620.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = MorePalette.of(context);
    return ColoredBox(color: palette.ground, child: child);
  }
}

/// Texture for a bounded account card, clipped by its enclosing material.
class MoreBookcloth extends StatelessWidget {
  const MoreBookcloth({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: CustomPaint(painter: _CoverTexture(MorePalette.of(context))),
    ),
  );
}

class _CoverTexture extends CustomPainter {
  const _CoverTexture(this.palette);

  final MorePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final thread = Paint()
      ..strokeWidth = .5
      ..color = palette.ink.withValues(alpha: .028);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thread);
    }
    thread.color = palette.ink.withValues(alpha: .018);
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thread);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 7, size.height),
      Paint()..color = palette.accent.withValues(alpha: .045),
    );
    thread.color = palette.accent.withValues(alpha: .16);
    for (double y = 6; y < size.height; y += 9) {
      canvas.drawLine(Offset(11, y), Offset(11, y + 3), thread);
    }
  }

  @override
  bool shouldRepaint(_CoverTexture oldDelegate) =>
      palette.ground != oldDelegate.palette.ground ||
      palette.ink != oldDelegate.palette.ink ||
      palette.accent != oldDelegate.palette.accent;
}
