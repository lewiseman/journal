import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'note_ai_widgets.dart';

/// Task phases come from the controller; the animation never estimates progress.
bool noteAiIsLoading(String phase, {required bool busy}) {
  if (const {
    'idle',
    'completed',
    'failed',
    'cancelled',
    'expired',
    'interrupted',
    'error',
    'storageError',
  }.contains(phase)) {
    return false;
  }
  return busy ||
      const {
        'submitting',
        'restoring',
        'retrieving',
        'accepted',
        'queued',
        'running',
        'preparing',
        'saving',
      }.contains(phase);
}

/// A shared, indeterminate loading view for every note AI tool.
/// Owns only its illustration's motion; task controls belong to the caller.
class NoteAiLoading extends StatefulWidget {
  const NoteAiLoading({
    super.key,
    required this.tool,
    required this.phase,
    this.onCancel,
    this.onRetry,
    this.cancelKey,
  });
  final NoteAiTool tool;
  final String phase;
  final VoidCallback? onCancel, onRetry;
  final Key? cancelKey;

  @override
  State<NoteAiLoading> createState() => _NoteAiLoadingState();
}

class _NoteAiLoadingState extends State<NoteAiLoading>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).unfocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = .45;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  String get _status => switch (widget.phase) {
    'queued' || 'accepted' => 'Waiting',
    'restoring' || 'retrieving' => 'Checking',
    'running' => 'Working',
    'preparing' => 'Preparing',
    'saving' => 'Saving',
    _ => 'Starting',
  };

  String get _title => switch (widget.phase) {
    'queued' || 'accepted' => 'Waiting to begin…',
    'restoring' || 'retrieving' => 'Checking your task…',
    'preparing' => 'Opening your preview…',
    'saving' => 'Saving your note…',
    _ => switch (widget.tool) {
      NoteAiTool.ideas => 'Finding ideas…',
      NoteAiTool.search => 'Searching notes…',
      NoteAiTool.thoughtSearch => 'Searching thoughts…',
      NoteAiTool.template => 'Building your template…',
      NoteAiTool.summary => 'Making your summary…',
      NoteAiTool.writing => 'Improving your note…',
      NoteAiTool.metadata => 'Finding titles & tags…',
      NoteAiTool.image => 'Reading your image…',
      NoteAiTool.scan => 'Reading your page…',
      NoteAiTool.background => 'Making your background…',
      NoteAiTool.presentation => 'Preparing your page…',
    },
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = widget.tool.ink(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                label: '$_status. $_title',
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      RepaintBoundary(
                        child: SizedBox(
                          width: 280,
                          height: 204,
                          child: AnimatedBuilder(
                            animation: _motion,
                            child: NoteAiArt(tool: widget.tool, size: 54),
                            builder: (context, stamp) => Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _NotebookPainter(
                                      _motion.value,
                                      ink,
                                      noteAiPaper(context),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 17,
                                  bottom: 22,
                                  child: Transform.rotate(
                                    angle: -.1,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: noteAiPaper(context),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: ink.withValues(alpha: .2),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(5),
                                        child: stamp,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: ink,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _status,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onCancel != null || widget.onRetry != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (widget.onRetry != null)
                      OutlinedButton.icon(
                        onPressed: widget.onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('Retry'),
                      ),
                    if (widget.onCancel != null)
                      TextButton.icon(
                        key: widget.cancelKey,
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.stop_rounded, size: 20),
                        label: const Text('Stop'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Looped ink strokes, a floating pencil, and layered paper. This is purely
/// decorative, with no countdown, percentage, or time-based task stages.
class _NotebookPainter extends CustomPainter {
  const _NotebookPainter(this.progress, this.ink, this.paper);
  final double progress;
  final Color ink, paper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 280, size.height / 204);
    final wave = math.sin(progress * math.pi * 2);
    final lift = 3 * wave;
    final outline = Paint()
      ..color = ink.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(
      const Rect.fromLTWH(43, 177, 180, 15),
      Paint()..color = ink.withValues(alpha: .055),
    );
    canvas.save();
    canvas.translate(140, 94 + lift);
    canvas.rotate(-.065);
    void page(double x, double y, double tint) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-72 + x, -76 + y, 144, 150),
        const Radius.circular(12),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = Color.alphaBlend(ink.withValues(alpha: tint), paper),
      );
      canvas.drawRRect(rect, outline);
    }

    page(10, 10, .045);
    page(5, 5, .02);
    page(0, 0, 0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-72, -76, 24, 150),
        const Radius.circular(12),
      ),
      Paint()..color = ink.withValues(alpha: .06),
    );
    canvas.drawLine(const Offset(-48, -73), const Offset(-48, 71), outline);
    for (var i = 0; i < 5; i++) {
      final y = -54.0 + i * 25;
      canvas.drawCircle(
        Offset(-59, y),
        2.2,
        Paint()..color = ink.withValues(alpha: .25),
      );
      canvas.drawArc(
        Rect.fromLTWH(-80, y - 4, 22, 8),
        -math.pi * .15,
        math.pi * 1.3,
        false,
        outline,
      );
    }
    final fold = 18 + 2 * wave;
    canvas.drawPath(
      Path()
        ..moveTo(72 - fold, -76)
        ..lineTo(72 - fold, -76 + fold)
        ..lineTo(72, -76 + fold)
        ..close(),
      Paint()..color = ink.withValues(alpha: .09),
    );
    canvas.drawPath(
      Path()
        ..moveTo(72 - fold, -76)
        ..lineTo(72 - fold, -76 + fold)
        ..lineTo(72, -76 + fold),
      outline,
    );
    final pen = Paint()
      ..color = ink
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final y = -41.0 + i * 18;
      final length = (i == 0
          ? 66.0
          : i == 4
          ? 46.0
          : 83.0);
      canvas.drawLine(
        Offset(-31, y),
        Offset(-31 + length, y),
        Paint()
          ..color = ink.withValues(alpha: .075)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      final pulse = (.55 + .45 * math.sin(progress * math.pi * 2 - i * .7))
          .clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(-31, y),
        Offset(-31 + length * pulse, y),
        pen..color = ink.withValues(alpha: .25 + .45 * pulse),
      );
    }
    canvas.save();
    canvas.translate(
      29 + wave * 15,
      14 + math.cos(progress * math.pi * 2) * 10,
    );
    canvas.rotate(.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, -43, 8, 50),
        const Radius.circular(2),
      ),
      Paint()..color = ink,
    );
    canvas.drawLine(
      const Offset(-1, -35),
      const Offset(-1, 0),
      Paint()
        ..color = paper.withValues(alpha: .7)
        ..strokeWidth = 1.1,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-4, 9)
        ..lineTo(0, 17)
        ..lineTo(4, 9)
        ..close(),
      Paint()..color = ink,
    );
    canvas.restore();
    canvas.restore();
    for (var i = 0; i < 3; i++) {
      final pulse =
          .3 + .7 * (math.sin(progress * math.pi * 2 - i * .8) + 1) / 2;
      canvas.drawCircle(
        Offset(119 + i * 13, 199),
        2 + pulse,
        Paint()..color = ink.withValues(alpha: .2 + pulse * .6),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NotebookPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.ink != ink ||
      oldDelegate.paper != paper;
}
