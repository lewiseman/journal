import 'package:journal/common.dart';
import 'package:journal/config/diary_typography.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';

/// A few miniature prints, with a pencilled count on their paper border.
/// Plain canvas drawing keeps the live control and curled face identical.
class DiaryPhotoAddAction extends StatelessWidget {
  const DiaryPhotoAddAction({
    super.key,
    required this.imageCount,
    required this.onPressed,
  });

  final int imageCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scaled = MediaQuery.textScalerOf(context).scale(18);
    final countHeight = scaled * 1.15;
    final width = 52.0 + (scaled - 18).clamp(0, 36);
    return Semantics(
      label: 'Add images',
      value: '$imageCount ${imageCount == 1 ? 'photo' : 'photos'}',
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        key: const ValueKey('diary-add-images'),
        tooltip: 'Add images',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(100, 64),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          foregroundColor: colors.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                painter: _PhotoPrints(
                  count: imageCount,
                  paper: colors.surfaceContainerLowest,
                  ink: colors.onSurfaceVariant,
                ),
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 32),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 12,
                          end: 9,
                          bottom: 4,
                        ),
                        child: SizedBox(
                          height: countHeight,
                          width: double.infinity,
                          child: imageCount == 0
                              ? const SizedBox.shrink()
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    imageCount > 999 ? '999+' : '$imageCount',
                                    key: const ValueKey('diary-image-count'),
                                    style: DiaryTypography.of(context).title
                                        .copyWith(
                                          fontSize: 18,
                                          height: 1.15,
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 15),
              DiaryInkGlyph(
                symbol: DiaryInkSymbol.add,
                color: colors.onSurfaceVariant,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPrints extends CustomPainter {
  const _PhotoPrints({
    required this.count,
    required this.paper,
    required this.ink,
  });
  final int count;
  final Color paper, ink;

  static final _landscape = Path()
    ..moveTo(4, 21)
    ..lineTo(15, 9)
    ..lineTo(24, 18)
    ..lineTo(32, 12)
    ..lineTo(43, 22);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(3, 5, size.width - 7, size.height - 7);
    final border = Paint()
      ..color = ink.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75;
    for (var layer = (count - 1).clamp(0, 2); layer > 0; layer--) {
      canvas.save();
      canvas.translate(frame.center.dx, frame.center.dy);
      canvas.rotate(-.075 * layer);
      final back = Rect.fromCenter(
        center: Offset(-2.0 * layer, -2.0 * layer),
        width: frame.width,
        height: frame.height,
      );
      canvas.drawRect(back, Paint()..color = paper);
      canvas.drawRect(back, border);
      canvas.restore();
    }
    canvas.drawRect(
      frame.shift(const Offset(1, 1.5)),
      Paint()..color = ink.withValues(alpha: .06),
    );
    canvas.drawRect(frame, Paint()..color = paper);
    canvas.drawRect(frame, border);
    final window = Rect.fromLTWH(
      frame.left + 5,
      frame.top + 5,
      frame.width - 10,
      21,
    );
    canvas.drawRect(window, Paint()..color = ink.withValues(alpha: .045));
    canvas.save();
    canvas.translate(window.left, window.top);
    canvas.scale(window.width / 48, window.height / 26);
    final pencil = Paint()
      ..color = ink.withValues(alpha: count == 0 ? .3 : .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_landscape, pencil);
    canvas.drawCircle(const Offset(35, 6), 2.5, pencil);
    canvas.restore();
    if (count == 0) {
      canvas.drawLine(
        Offset(frame.right - 17, frame.bottom - 9),
        Offset(frame.right - 6, frame.bottom - 10),
        border,
      );
    }
  }

  @override
  bool shouldRepaint(_PhotoPrints oldDelegate) =>
      count != oldDelegate.count ||
      paper != oldDelegate.paper ||
      ink != oldDelegate.ink;
}
