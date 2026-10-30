import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'friend_avatar.dart';
import 'people_paper.dart';

/// An arrival notice receives sender metadata only, never a note's body.
class NoteArrivalBanner extends StatefulWidget {
  const NoteArrivalBanner({
    super.key,
    required this.name,
    required this.friendKey,
    required this.onOpen,
    required this.onDismiss,
  });

  final String name, friendKey;
  final VoidCallback onOpen, onDismiss;

  @override
  State<NoteArrivalBanner> createState() => _NoteArrivalBannerState();
}

class _NoteArrivalBannerState extends State<NoteArrivalBanner>
    with SingleTickerProviderStateMixin {
  late final _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _arrival.value = 1;
    } else if (!_started) {
      _arrival.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = PeoplePalette.of(context);
    final compact = MediaQuery.textScalerOf(context).scale(14) > 20;
    final paper = Color.alphaBlend(
      colors.primary.withValues(alpha: .035),
      palette.paper,
    );
    return AnimatedBuilder(
      animation: _arrival,
      builder: (context, child) => CustomPaint(
        painter: _ArrivalPaper(
          paper: paper,
          ink: colors.onSurface,
          accent: colors.primary,
          progress: _arrival.value,
        ),
        child: child,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 42, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!compact) ...[
                    _ArrivingEnvelope(
                      animation: _arrival,
                      name: widget.name,
                      friendKey: widget.friendKey,
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!compact) ...[
                          ExcludeSemantics(
                            child: Text(
                              'JUST ARRIVED',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          'A note from ${widget.name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          key: const ValueKey('people-arrival-open'),
                          onPressed: widget.onOpen,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 40),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Flexible(child: Text('Open Friends')),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded, size: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 9,
              right: 6,
              child: IconButton(
                key: const ValueKey('people-arrival-dismiss'),
                tooltip: 'Dismiss note alert',
                onPressed: widget.onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                style: IconButton.styleFrom(
                  foregroundColor: colors.onSurfaceVariant,
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrivingEnvelope extends StatelessWidget {
  const _ArrivingEnvelope({
    required this.animation,
    required this.name,
    required this.friendKey,
  });
  final Animation<double> animation;
  final String name, friendKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          final arrival = Curves.easeOutCubic.transform((t / .65).clamp(0, 1));
          final reveal = Curves.easeOutBack.transform(
            ((t - .15) / .7).clamp(0, 1),
          );
          final paperTop = 16 - 10 * reveal;
          return Transform.translate(
            offset: Offset(
              -18 * (1 - arrival),
              -9 * math.sin(math.pi * arrival),
            ),
            child: Transform.rotate(
              angle:
                  -.22 * (1 - arrival) +
                  .06 * math.sin(t * math.pi * 2) * (1 - t),
              child: SizedBox(
                width: 64,
                height: 76,
                child: CustomPaint(
                  painter: _EnvelopeSketch(
                    colors: colors,
                    paperTop: paperTop,
                    progress: t,
                  ),
                  foregroundPainter: _EnvelopeSketch(
                    colors: colors,
                    paperTop: paperTop,
                    progress: t,
                    front: true,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: paperTop + 5,
                        left: 20,
                        child: FriendAvatar(
                          friendKey: friendKey,
                          name: name,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EnvelopeSketch extends CustomPainter {
  const _EnvelopeSketch({
    required this.colors,
    required this.paperTop,
    required this.progress,
    this.front = false,
  });
  final ColorScheme colors;
  final double paperTop, progress;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    if (!front) {
      final sheet = RRect.fromRectAndRadius(
        Rect.fromLTWH(10, paperTop, 44, 52),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        sheet.shift(const Offset(0, 2)),
        Paint()..color = colors.onSurface.withValues(alpha: .08),
      );
      canvas.drawRRect(sheet, Paint()..color = colors.surfaceContainerLowest);
      final flecks = Paint()
        ..color = colors.primary.withValues(
          alpha: math.sin(math.pi * progress).abs() * .5,
        );
      for (var i = 0; i < 4; i++) {
        final angle = i * 1.7 - 2.6;
        final distance = 22 + 18 * progress;
        canvas.drawCircle(
          Offset(
            32 + math.cos(angle) * distance,
            30 + math.sin(angle) * distance,
          ),
          i.isEven ? 1.8 : 1.1,
          flecks,
        );
      }
      return;
    }
    final envelope = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2, 34, 60, 38),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      envelope.shift(const Offset(0, 3)),
      Paint()..color = colors.onSurface.withValues(alpha: .08),
    );
    canvas.drawRRect(envelope, Paint()..color = colors.primaryContainer);
    final seams = Paint()
      ..color = colors.primary.withValues(alpha: .3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9;
    canvas.drawPath(
      Path()
        ..moveTo(4, 36)
        ..lineTo(32, 54)
        ..lineTo(60, 36),
      seams,
    );
    canvas.drawPath(
      Path()
        ..moveTo(4, 70)
        ..lineTo(22, 52)
        ..moveTo(60, 70)
        ..lineTo(42, 52),
      seams,
    );
    canvas.save();
    canvas.translate(26, 48);
    WaxSealPainter(colors.primary).paint(canvas, const Size.square(12));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EnvelopeSketch oldDelegate) =>
      colors != oldDelegate.colors ||
      paperTop != oldDelegate.paperTop ||
      progress != oldDelegate.progress;
}

class _ArrivalPaper extends CustomPainter {
  const _ArrivalPaper({
    required this.paper,
    required this.ink,
    required this.accent,
    required this.progress,
  });
  final Color paper, ink, accent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const corner = 22.0;
    final path = Path()
      ..moveTo(corner, 0)
      ..lineTo(w - corner, 0)
      ..lineTo(w, corner)
      ..lineTo(w, h - corner)
      ..quadraticBezierTo(w, h, w - corner, h)
      ..lineTo(corner, h)
      ..quadraticBezierTo(0, h, 0, h - corner)
      ..lineTo(0, corner)
      ..quadraticBezierTo(0, 0, corner, 0)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: .25), 8, false);
    canvas.drawPath(path, Paint()..color = paper);
    canvas.drawPath(
      path,
      Paint()
        ..color = ink.withValues(alpha: .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - corner, 0)
        ..lineTo(w - corner, corner)
        ..lineTo(w, corner)
        ..close(),
      Paint()..color = accent.withValues(alpha: .13),
    );
    final random = math.Random(19);
    final fibre = Paint()
      ..color = ink.withValues(alpha: .035)
      ..strokeWidth = .6;
    for (var i = 0; i < 40; i++) {
      final x = 12 + random.nextDouble() * (w - 36);
      final y = 8 + random.nextDouble() * (h - 16);
      canvas.drawLine(Offset(x, y), Offset(x + 3, y - 1), fibre);
    }
    final trace = Curves.easeOutCubic.transform(
      ((progress - .25) / .75).clamp(0, 1),
    );
    final flourish = Path()
      ..moveTo(20, h - 8)
      ..cubicTo(w * .3, h - 12, w * .55, h - 4, w - 24, h - 8);
    final metric = flourish.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * trace),
      Paint()
        ..color = accent.withValues(alpha: .24)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArrivalPaper oldDelegate) =>
      paper != oldDelegate.paper ||
      ink != oldDelegate.ink ||
      accent != oldDelegate.accent ||
      progress != oldDelegate.progress;
}
