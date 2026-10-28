import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:journal/modules/more/views/widgets/more_material.dart';

enum MoreEntryArtwork { swatches, computer }

/// Open, ruled entries rather than separate settings cards.
class MoreIndexEntry extends StatelessWidget {
  const MoreIndexEntry({
    super.key,
    required this.number,
    required this.title,
    required this.description,
    required this.artwork,
    required this.onTap,
    this.status,
    this.connected = false,
  });

  final String number, title, description;
  final MoreEntryArtwork artwork;
  final VoidCallback onTap;
  final String? status;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final palette = MorePalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showArtwork =
            constraints.maxWidth >= 310 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: palette.accent.withValues(alpha: .06),
            highlightColor: palette.accent.withValues(alpha: .04),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.rule)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 14),
                      child: Text(
                        number,
                        style: palette.label.copyWith(
                          color: palette.accent,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 20,
                              height: 1.2,
                              letterSpacing: -.6,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            description,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                          if (status != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 5,
                                    right: 6,
                                  ),
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: connected
                                          ? palette.accent
                                          : palette.muted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    status!,
                                    style: TextStyle(
                                      color: connected
                                          ? palette.accent
                                          : palette.muted,
                                      fontSize: 10,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showArtwork) ...[
                      const SizedBox(width: 12),
                      ExcludeSemantics(
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: CustomPaint(
                            painter: _EntryPainter(palette, artwork),
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(left: 10, top: 5),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 17,
                        color: palette.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EntryPainter extends CustomPainter {
  const _EntryPainter(this.palette, this.artwork);

  final MorePalette palette;
  final MoreEntryArtwork artwork;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final pen = Paint()
      ..color = palette.accent.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (artwork == MoreEntryArtwork.swatches) {
      final shades = [
        Color.lerp(palette.paper, const Color(0xffbc9b74), .50)!,
        Color.lerp(palette.paper, const Color(0xff89917b), .55)!,
        Color.lerp(palette.paper, palette.accent, .22)!,
      ];
      for (var i = 0; i < 3; i++) {
        canvas.save();
        canvas.translate(30, 52);
        canvas.rotate((i - 1) * math.pi / 8);
        final card = RRect.fromRectAndRadius(
          const Rect.fromLTWH(-11, -46, 25, 49),
          const Radius.circular(2),
        );
        canvas.drawRRect(
          card.shift(const Offset(1, 2)),
          Paint()..color = palette.ink.withValues(alpha: .07),
        );
        canvas.drawRRect(card, Paint()..color = shades[i]);
        canvas.drawRRect(card, pen..color = palette.ink.withValues(alpha: .2));
        canvas.drawLine(const Offset(-5, -9), const Offset(8, -9), pen);
        canvas.restore();
      }
      canvas.drawCircle(
        const Offset(30, 52),
        2,
        Paint()..color = palette.accent,
      );
    } else {
      final screen = RRect.fromRectAndRadius(
        const Rect.fromLTWH(7, 9, 49, 34),
        const Radius.circular(3),
      );
      canvas.drawRRect(screen, Paint()..color = palette.paper);
      canvas.drawRRect(screen, pen);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 14, 39, 24),
          const Radius.circular(1),
        ),
        Paint()..color = Color.lerp(palette.paper, palette.accent, .10)!,
      );
      final star = Path()
        ..moveTo(32, 18)
        ..quadraticBezierTo(32, 26, 40, 26)
        ..quadraticBezierTo(32, 26, 32, 34)
        ..quadraticBezierTo(32, 26, 24, 26)
        ..quadraticBezierTo(32, 26, 32, 18);
      canvas.drawPath(
        star,
        Paint()..color = palette.accent.withValues(alpha: .7),
      );
      canvas.drawLine(const Offset(28, 43), const Offset(27, 51), pen);
      canvas.drawLine(const Offset(36, 43), const Offset(37, 51), pen);
      canvas.drawLine(const Offset(22, 51), const Offset(42, 51), pen);
      canvas.drawLine(
        const Offset(12, 56),
        const Offset(52, 56),
        pen..color = palette.rule,
      );
    }
  }

  @override
  bool shouldRepaint(_EntryPainter oldDelegate) =>
      artwork != oldDelegate.artwork ||
      palette.accent != oldDelegate.palette.accent ||
      palette.paper != oldDelegate.palette.paper ||
      palette.ink != oldDelegate.palette.ink;
}
