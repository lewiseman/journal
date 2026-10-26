import 'dart:math' as math;

import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

class DiaryMemoryPalette {
  const DiaryMemoryPalette({
    required this.desk,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.tabs,
  });

  factory DiaryMemoryPalette.of(BuildContext context) {
    final colors = context.colors;
    return DiaryMemoryPalette(
      desk: colors.surface,
      paper: colors.surfaceContainerLowest,
      ink: colors.onSurface,
      muted: colors.onSurfaceVariant,
      tabs: [
        colors.primaryContainer,
        colors.surfaceContainer,
        colors.surfaceContainerHigh,
      ],
    );
  }

  final Color desk, paper, ink, muted;
  final List<Color> tabs;
}

enum DiaryInkSymbol {
  sun,
  heart,
  sprig,
  shuffle,
  check,
  zoom,
  add,
  close,
  arrow,
  pencil,
  album,
  landscape,
}

class DiaryPaperTicket extends StatelessWidget {
  const DiaryPaperTicket({
    super.key,
    required this.label,
    required this.onPressed,
    required this.symbol,
    this.tone = 0,
  });
  final String label;
  final VoidCallback? onPressed;
  final DiaryInkSymbol symbol;
  final int tone;

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    return DiaryInkAction(
      label: label,
      onPressed: onPressed,
      child: Opacity(
        opacity: onPressed == null ? .5 : 1,
        child: CustomPaint(
          painter: DiaryPaperStamp(
            paper: palette.tabs[tone],
            ink: palette.ink,
            shadowColor: context.colors.shadow,
            edgeScale: .3,
            variant: tone,
          ),
          foregroundPainter: _TicketPerforation(
            ink: palette.ink,
            reverse: Directionality.of(context) == TextDirection.rtl,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
            child: Row(
              children: [
                DiaryInkGlyph(symbol: symbol, color: palette.ink, size: 23),
                const SizedBox(width: 29),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      fontStyle: FontStyle.italic,
                      color: palette.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: DiaryInkGlyph(
                    symbol: DiaryInkSymbol.arrow,
                    color: palette.ink,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DiaryInkUnderline extends CustomPainter {
  const DiaryInkUnderline({required this.ink, this.dashed = false});
  final Color ink;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(3, size.height - 4)
      ..quadraticBezierTo(
        size.width * .45,
        size.height - 1.5,
        size.width - 3,
        size.height - 5,
      );
    if (!dashed) {
      canvas.drawPath(path, pen);
    } else {
      for (final metric in path.computeMetrics()) {
        for (var distance = 0.0; distance < metric.length; distance += 7) {
          canvas.drawPath(
            metric.extractPath(distance, math.min(distance + 3, metric.length)),
            pen,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(DiaryInkUnderline oldDelegate) =>
      ink != oldDelegate.ink || dashed != oldDelegate.dashed;
}

class _TicketPerforation extends CustomPainter {
  const _TicketPerforation({required this.ink, required this.reverse});
  final Color ink;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (reverse) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final pen = Paint()
      ..color = ink.withValues(alpha: .19)
      ..strokeWidth = .7;
    for (var y = 10.0; y < size.height - 8; y += 5) {
      canvas.drawLine(Offset(58, y), Offset(58, y + 2), pen);
    }
    final fold = Path()
      ..moveTo(size.width - 17, 4)
      ..lineTo(size.width - 4, 17)
      ..lineTo(size.width - 17, 17)
      ..close();
    canvas.drawPath(fold, Paint()..color = ink.withValues(alpha: .045));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TicketPerforation oldDelegate) =>
      ink != oldDelegate.ink || reverse != oldDelegate.reverse;
}

class DiaryInkGlyph extends StatelessWidget {
  const DiaryInkGlyph({
    super.key,
    required this.symbol,
    required this.color,
    this.size = 24,
  });
  final DiaryInkSymbol symbol;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: DiaryInkGlyphPainter(kind: symbol.index, ink: color),
      ),
    ),
  );
}

class DiaryInkGlyphPainter extends CustomPainter {
  const DiaryInkGlyphPainter({required this.kind, required this.ink});
  final int kind;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case 0:
        canvas.drawOval(const Rect.fromLTWH(7, 7, 10, 10), pen);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            Offset(12 + math.cos(a) * 8, 12 + math.sin(a) * 8),
            Offset(12 + math.cos(a) * 10.5, 12 + math.sin(a) * 10.5),
            pen,
          );
        }
      case 1:
        canvas.drawPath(
          Path()
            ..moveTo(12, 20)
            ..cubicTo(8, 16, 1, 12, 4, 7)
            ..cubicTo(6, 3, 10, 5, 12, 8)
            ..cubicTo(15, 3, 20, 4, 21, 8)
            ..cubicTo(23, 13, 15, 18, 12, 20),
          pen,
        );
      case 2:
        canvas.drawPath(
          Path()
            ..moveTo(9, 22)
            ..quadraticBezierTo(14, 12, 14, 2)
            ..moveTo(13, 12)
            ..cubicTo(4, 12, 4, 5, 7, 6)
            ..quadraticBezierTo(13, 7, 13, 12)
            ..moveTo(12, 17)
            ..cubicTo(23, 17, 22, 9, 19, 11)
            ..quadraticBezierTo(14, 12, 12, 17),
          pen,
        );
      case 3:
        canvas.drawPath(
          Path()
            ..moveTo(3, 7)
            ..quadraticBezierTo(10, 5, 13, 13)
            ..quadraticBezierTo(16, 19, 22, 17)
            ..moveTo(17, 3)
            ..lineTo(22, 6)
            ..lineTo(18, 10)
            ..moveTo(22, 6)
            ..quadraticBezierTo(17, 4, 13, 11)
            ..quadraticBezierTo(8, 19, 3, 17),
          pen,
        );
      case 4:
        canvas.drawPath(
          Path()
            ..moveTo(4, 12)
            ..lineTo(10, 18)
            ..quadraticBezierTo(16, 8, 22, 4),
          pen..strokeWidth = 1.5,
        );
      case 5:
        canvas.drawOval(const Rect.fromLTWH(4, 3, 12, 12), pen);
        canvas.drawPath(
          Path()
            ..moveTo(14, 14)
            ..lineTo(21, 21)
            ..moveTo(7, 9)
            ..lineTo(13, 9)
            ..moveTo(10, 6)
            ..lineTo(10, 12),
          pen,
        );
      case 6:
        canvas.drawPath(
          Path()
            ..moveTo(4, 12)
            ..quadraticBezierTo(12, 11, 21, 12)
            ..moveTo(12, 3)
            ..quadraticBezierTo(11, 12, 12, 21),
          pen,
        );
      case 7:
        canvas.drawPath(
          Path()
            ..moveTo(5, 5)
            ..quadraticBezierTo(12, 12, 20, 19)
            ..moveTo(19, 4)
            ..quadraticBezierTo(12, 12, 5, 20),
          pen,
        );
      case 8:
        canvas.drawPath(
          Path()
            ..moveTo(3, 12)
            ..quadraticBezierTo(12, 11, 22, 12)
            ..moveTo(15, 5)
            ..lineTo(22, 12)
            ..lineTo(15, 19),
          pen,
        );
      case 9:
        canvas.drawPath(
          Path()
            ..moveTo(4, 20)
            ..lineTo(6, 14)
            ..lineTo(17, 3)
            ..quadraticBezierTo(21, 2, 22, 7)
            ..lineTo(10, 18)
            ..close()
            ..moveTo(6, 14)
            ..lineTo(10, 18)
            ..moveTo(15, 5)
            ..lineTo(19, 9),
          pen,
        );
      case 10:
        canvas.drawPath(
          Path()
            ..moveTo(3, 7)
            ..lineTo(18, 4)
            ..lineTo(21, 18)
            ..lineTo(6, 21)
            ..close()
            ..moveTo(6, 4)
            ..lineTo(20, 2)
            ..lineTo(23, 16)
            ..moveTo(6, 16)
            ..lineTo(10, 10)
            ..lineTo(14, 14)
            ..lineTo(17, 10)
            ..lineTo(20, 14),
          pen,
        );
      default:
        canvas.drawPath(
          Path()
            ..moveTo(2, 20)
            ..lineTo(10, 8)
            ..lineTo(15, 15)
            ..lineTo(18, 11)
            ..lineTo(23, 20)
            ..close(),
          pen,
        );
        canvas.drawCircle(const Offset(18, 5), 2.5, pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DiaryInkGlyphPainter oldDelegate) =>
      kind != oldDelegate.kind || ink != oldDelegate.ink;
}
