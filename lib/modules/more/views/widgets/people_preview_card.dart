import 'package:journal/common.dart';

/// A preview only. People has no destination until its page is introduced.
class PeoplePreviewCard extends StatelessWidget {
  const PeoplePreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = context.isDark
        ? const Color(0xFFE6B4A7)
        : const Color(0xFF9B6456);
    return Container(
      key: const ValueKey('more-people-preview'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: context.isDark ? .1 : .07),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMING SOON',
                  style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'People',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 23,
                    letterSpacing: -.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'A place for the people\nwho matter to you.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: 76,
              child: CustomPaint(painter: _PeopleArtwork(accent)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleArtwork extends CustomPainter {
  const _PeopleArtwork(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 76, size.height / 76);
    final stroke = Paint()
      ..color = ink.withValues(alpha: .75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final wash = Paint()..color = ink.withValues(alpha: .07);
    canvas.drawCircle(const Offset(39, 40), 35, wash);
    canvas.drawOval(const Rect.fromLTWH(37, 19, 16, 19), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(38, 44)
        ..quadraticBezierTo(62, 37, 62, 59)
        ..lineTo(48, 61),
      stroke,
    );
    canvas.drawOval(const Rect.fromLTWH(18, 26, 17, 20), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(11, 64)
        ..quadraticBezierTo(10, 49, 26, 49)
        ..quadraticBezierTo(43, 49, 43, 65)
        ..close(),
      wash,
    );
    canvas.drawPath(
      Path()
        ..moveTo(11, 64)
        ..quadraticBezierTo(10, 49, 26, 49)
        ..quadraticBezierTo(43, 49, 43, 65),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(59, 17)
        ..cubicTo(52, 12, 58, 6, 61, 11)
        ..cubicTo(65, 7, 70, 14, 59, 20),
      stroke..color = ink.withValues(alpha: .45),
    );
  }

  @override
  bool shouldRepaint(_PeopleArtwork oldDelegate) => oldDelegate.ink != ink;
}
