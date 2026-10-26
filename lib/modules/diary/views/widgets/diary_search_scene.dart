import 'dart:math' as math;

import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_paper.dart';

/// A stationery still life with one finite paper-settling entrance.
class DiarySearchScene extends StatelessWidget {
  const DiarySearchScene({
    super.key,
    required this.reduced,
    required this.compact,
    this.searchProgress,
  });

  final bool reduced, compact;
  final double? searchProgress;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 340,
      height: compact ? 116 : 184,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 340,
          height: 184,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduced ? 1 : 0, end: 1),
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) {
              final scanning = searchProgress != null && !reduced;
              final phase = (searchProgress ?? 0) * math.pi * 2;
              final sage = NoteColorPreset.sage.resolveColors(context.colors);
              final sand = NoteColorPreset.sand.resolveColors(context.colors);
              final paper = NoteColorPreset.paper.resolveColors(context.colors);
              final ink = context.colors.primary;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _MemoryMarks(ink)),
                  ),
                  Positioned(
                    left: 35 - 10 * (1 - progress),
                    top: 53 + (scanning ? math.sin(phase) * 3 : 0),
                    width: 114,
                    height: 91,
                    child: Transform.rotate(
                      angle: -.17 - .1 * (1 - progress),
                      child: DiarySearchPaper(
                        color: sage.background,
                        padding: const EdgeInsets.all(16),
                        child: CustomPaint(
                          painter: _PaperMarks(sage.secondary, sun: true),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 184 + 12 * (1 - progress),
                    top: 25 + (scanning ? math.sin(phase + 1) * 3 : 0),
                    width: 109,
                    height: 95,
                    child: Transform.rotate(
                      angle: .13 + .08 * (1 - progress),
                      child: DiarySearchPaper(
                        color: sand.background,
                        variant: 1,
                        padding: const EdgeInsets.all(17),
                        child: CustomPaint(
                          painter: _PaperMarks(sand.secondary),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 87,
                    top:
                        60 +
                        12 * (1 - progress) +
                        (scanning ? math.cos(phase) * 2 : 0),
                    width: 177,
                    height: 109,
                    child: Transform.rotate(
                      angle: -.055 - .06 * (1 - progress),
                      child: DiarySearchPaper(
                        color: paper.background,
                        variant: 2,
                        padding: const EdgeInsets.fromLTRB(20, 17, 20, 15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'the little things',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: paper.foreground,
                              ),
                            ),
                            const SizedBox(height: 15),
                            Expanded(
                              child: SizedBox.expand(
                                child: CustomPaint(
                                  painter: _PaperMarks(paper.secondary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Transform.translate(
                      offset: scanning
                          ? Offset(
                              math.sin(phase) * 32,
                              math.cos(phase) * 9 - 4,
                            )
                          : Offset(20 * (1 - progress), -12 * (1 - progress)),
                      child: CustomPaint(
                        painter: _LookingGlass(
                          ink: ink,
                          surface: context.colors.surface,
                          dark: context.isDark,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _LookingGlass extends CustomPainter {
  const _LookingGlass({
    required this.ink,
    required this.surface,
    required this.dark,
  });
  final Color ink, surface;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(237, 83);
    const radius = 33.0;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final lens = Path()..addOval(bounds);
    canvas.drawShadow(lens, Colors.black.withValues(alpha: .22), 4, true);
    canvas.drawLine(
      const Offset(261, 108),
      const Offset(288, 139),
      Paint()
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            Color.lerp(ink, surface, .32)!,
            ink,
            Color.lerp(ink, Colors.black, .2)!,
          ],
        ).createShader(const Rect.fromLTWH(257, 105, 37, 40)),
    );
    canvas.drawLine(
      const Offset(266, 112),
      const Offset(287, 136),
      Paint()
        ..color = surface.withValues(alpha: .22)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.6, -.65),
          colors: [
            Colors.white.withValues(alpha: dark ? .09 : .4),
            ink.withValues(alpha: .035),
          ],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(ink, surface, .36)!,
            ink,
            Color.lerp(ink, Colors.black, .15)!,
          ],
        ).createShader(bounds),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      3.5,
      .9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: dark ? .28 : .8),
    );
  }

  @override
  bool shouldRepaint(_LookingGlass oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.surface != surface ||
      oldDelegate.dark != dark;
}

class _PaperMarks extends CustomPainter {
  const _PaperMarks(this.ink, {this.sun = false});
  final Color ink;
  final bool sun;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink.withValues(alpha: .25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    if (sun) {
      final center = Offset(size.width * .4, size.height * .45);
      canvas.drawCircle(center, 9, pen);
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(center + direction * 14, center + direction * 18, pen);
      }
      return;
    }
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(0, 2 + i * 11),
        Offset(size.width * [1, .86, .59][i], 1 + i * 11),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_PaperMarks oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.sun != sun;
}

class _MemoryMarks extends CustomPainter {
  const _MemoryMarks(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink.withValues(alpha: .35)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(52, 156)
        ..cubicTo(12, 159, 8, 134, 30, 128),
      pen,
    );
    for (final point in [const Offset(74, 30), const Offset(305, 69)]) {
      const radius = 4.0;
      final star = Path()
        ..moveTo(point.dx, point.dy - radius)
        ..quadraticBezierTo(point.dx, point.dy, point.dx + radius, point.dy)
        ..quadraticBezierTo(point.dx, point.dy, point.dx, point.dy + radius)
        ..quadraticBezierTo(point.dx, point.dy, point.dx - radius, point.dy)
        ..quadraticBezierTo(point.dx, point.dy, point.dx, point.dy - radius);
      canvas.drawPath(star, pen);
    }
  }

  @override
  bool shouldRepaint(_MemoryMarks oldDelegate) => oldDelegate.ink != ink;
}
