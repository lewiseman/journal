import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:journal/modules/more/views/widgets/people_artwork.dart';

/// The shared Friends illustration on a quiet wash of the selected accent.
class PeopleHeaderArtwork extends StatelessWidget {
  const PeopleHeaderArtwork({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: .14),
                    colors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _CircleDetails(colors.primary)),
          ),
          Positioned.fill(
            child: Transform.rotate(
              angle: -.035,
              child: const PeopleEntryArtwork(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleDetails extends CustomPainter {
  const _CircleDetails(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .5;
    final stroke = Paint()
      ..color = color.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -.3,
      math.pi * .65,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .92),
      math.pi * .92,
      math.pi * .3,
      false,
      stroke,
    );
    final dot = Paint()..color = color.withValues(alpha: .32);
    canvas.drawCircle(Offset(size.width * .12, size.height * .16), 3, dot);
    canvas.drawCircle(Offset(size.width * .95, size.height * .66), 2, dot);
  }

  @override
  bool shouldRepaint(_CircleDetails oldDelegate) => color != oldDelegate.color;
}
