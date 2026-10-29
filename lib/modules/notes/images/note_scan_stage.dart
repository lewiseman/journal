import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';

/// Whether the scan screen may move: off for reduced motion and paused
/// tickers, so they get a calm, still view. Not tied to accessible
/// navigation: Android reports it whenever any accessibility service (a
/// password manager, an automation app) reads the screen, and the moving
/// parts are decorative and hidden from screen readers anyway.
bool noteScanAnimates(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context) &&
    TickerMode.valuesOf(context).enabled;

Duration noteScanMotion(BuildContext context, int milliseconds) =>
    noteScanAnimates(context)
    ? Duration(milliseconds: milliseconds)
    : Duration.zero;

/// The viewfinder behind the photo: a deep, ink-tinted surface in both
/// themes so the page and the light controls over it stand out.
Color noteScanViewfinder(BuildContext context) => Color.alphaBlend(
  NoteAiTool.scan.ink(context).withValues(alpha: .22),
  const Color(0xFF121615),
);

/// The page in one dark viewfinder through every step: [empty] before a page
/// is picked, then the page itself (a scan line sweeps it while it is read),
/// then a shorter frame once the text is back. [overlay] floats over the
/// bottom edge. The frame only resizes smoothly, so nothing below it jumps.
class NoteScanStage extends StatefulWidget {
  const NoteScanStage({
    super.key,
    required this.page,
    this.analyzing = false,
    this.compact = false,
    this.empty,
    this.overlay,
  });
  final String? page;
  final bool analyzing, compact;
  final Widget? empty, overlay;

  @override
  State<NoteScanStage> createState() => _NoteScanStageState();
}

class _NoteScanStageState extends State<NoteScanStage>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(NoteScanStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analyzing != widget.analyzing) _run();
  }

  /// Ticks only while a page is read and motion is allowed.
  void _run() {
    if (widget.analyzing && noteScanAnimates(context)) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final ink = NoteAiTool.scan.ink(context);
    final animate = noteScanAnimates(context);
    final shown = page != null || widget.empty != null;
    final height = !shown
        ? 0.0
        : page != null && widget.compact
        ? 190.0
        : 400.0;
    final Widget content = page != null
        ? _ScanPhoto(
            key: ValueKey(page),
            page: page,
            ink: ink,
            analyzing: widget.analyzing,
            animate: animate,
            sweep: _sweep,
            // Leaves the floating controls clear of the page's last lines.
            bottom: widget.overlay == null ? 14 : 74,
          )
        : widget.empty != null
        ? KeyedSubtree(key: const ValueKey('empty'), child: widget.empty!)
        : const SizedBox.shrink(key: ValueKey('none'));
    return AnimatedContainer(
      key: const ValueKey('note-scan-stage'),
      duration: noteScanMotion(context, 420),
      curve: Curves.easeOutCubic,
      height: height,
      margin: EdgeInsets.only(bottom: shown ? 16 : 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: noteScanViewfinder(context),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: noteScanMotion(context, 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: .96, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: content,
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: AnimatedSwitcher(
              duration: noteScanMotion(context, 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .35),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: widget.overlay == null
                  ? const SizedBox.shrink(key: ValueKey('no-overlay'))
                  : Center(key: widget.overlay!.key, child: widget.overlay),
            ),
          ),
        ],
      ),
    );
  }
}

/// The picked page at its own proportions, so the scan overlay covers the
/// photo itself rather than the letterbox around it.
class _ScanPhoto extends StatelessWidget {
  const _ScanPhoto({
    super.key,
    required this.page,
    required this.ink,
    required this.analyzing,
    required this.animate,
    required this.sweep,
    required this.bottom,
  });
  final String page;
  final Color ink;
  final bool analyzing, animate;
  final Animation<double> sweep;
  final double bottom;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: animate ? const Duration(milliseconds: 260) : Duration.zero,
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.fromLTRB(14, 14, 14, bottom),
    child: Center(
      child: AnimatedBuilder(
        animation: sweep,
        builder: (context, photo) {
          final glow = analyzing
              ? (animate ? .5 + .5 * math.sin(sweep.value * math.pi * 4) : .5)
              : 0.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Color.lerp(
                    ink,
                    Colors.white,
                    .35,
                  )!.withValues(alpha: analyzing ? .22 + .22 * glow : .0),
                  blurRadius: analyzing ? 14 + 12 * glow : 8,
                  spreadRadius: analyzing ? 1 + 2 * glow : 0,
                ),
              ],
            ),
            child: photo,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Image.file(
                File(page),
                fit: BoxFit.contain,
                cacheHeight: 780,
                frameBuilder: (_, image, frame, synchronous) => synchronous
                    ? image
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: animate
                            ? const Duration(milliseconds: 300)
                            : Duration.zero,
                        child: image,
                      ),
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'This page image is no longer available.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: analyzing ? 1 : 0,
                    duration: animate
                        ? const Duration(milliseconds: 420)
                        : Duration.zero,
                    curve: Curves.easeOut,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('note-scan-analyzing'),
                        painter: NoteScanPainter(
                          sweep,
                          ink: ink,
                          moving: analyzing && animate,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A soft veil over the page with a glowing line sweeping down and back up,
/// lighting each row of text as it passes, inside pulsing viewfinder
/// corners. Decorative only: it never suggests how far the reading has got.
/// When [moving] is false it paints a calm, still frame with no line.
class NoteScanPainter extends CustomPainter {
  NoteScanPainter(this.sweep, {required this.ink, required this.moving})
    : super(repaint: sweep);
  final Animation<double> sweep;
  final Color ink;
  final bool moving;

  static const _rows = [.62, .84, .71, .9, .55, .78, .66, .86, .5, .74];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = sweep.value;
    // A vivid take on the tool's ink, so the beam reads on white paper and
    // on dark photos alike.
    final beam = HSLColor.fromColor(ink)
        .withSaturation(.9)
        .withLightness(.6)
        .toColor();
    final light = Color.lerp(beam, Colors.white, .45)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Color.lerp(
          ink,
          Colors.black,
          .55,
        )!.withValues(alpha: moving ? .26 : .14),
    );

    // Ease in and out at each edge: the line slows as it turns.
    final y = (1 - math.cos(t * math.pi * 2)) / 2;
    final down = math.sin(t * math.pi * 2) >= 0;
    final lineY = y * size.height;
    if (moving) {
      final trail = size.height * .3;
      final band = Rect.fromLTRB(
        0,
        down ? lineY - trail : lineY,
        size.width,
        down ? lineY : lineY + trail,
      );
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: down ? Alignment.topCenter : Alignment.bottomCenter,
            end: down ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [beam.withValues(alpha: 0), beam.withValues(alpha: .45)],
          ).createShader(band),
      );
      for (final (i, length) in _rows.indexed) {
        final rowY = (i + 1) / (_rows.length + 1);
        final lit = (1 - (rowY - y).abs() / .12).clamp(0.0, 1.0);
        if (lit == 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width * .1,
              rowY * size.height - 3,
              size.width * .8 * length,
              6,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = light.withValues(alpha: .55 * lit),
        );
      }
      final glow = Paint()
        ..color = beam.withValues(alpha: .9)
        ..strokeWidth = 14
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawLine(Offset(0, lineY), Offset(size.width, lineY), glow);
      canvas.drawLine(
        Offset(0, lineY),
        Offset(size.width, lineY),
        Paint()
          ..shader = LinearGradient(
            colors: [
              light.withValues(alpha: .2),
              Colors.white,
              light.withValues(alpha: .2),
            ],
          ).createShader(Rect.fromLTWH(0, lineY - 2, size.width, 4))
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    final pulse = moving ? (1 + math.sin(t * math.pi * 4)) / 2 : .5;
    final inset = 10 + 2 * pulse;
    final arm = math.min(26.0, size.shortestSide * .18);
    final corner = Paint()
      ..color = Color.lerp(beam, Colors.white, .3 + .5 * pulse)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final (sx, sy) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      final x = sx == 0 ? inset : size.width - inset;
      final cy = sy == 0 ? inset : size.height - inset;
      final dx = sx == 0 ? arm : -arm;
      final dy = sy == 0 ? arm : -arm;
      canvas.drawPath(
        Path()
          ..moveTo(x, cy + dy)
          ..lineTo(x, cy)
          ..lineTo(x + dx, cy),
        corner,
      );
    }
  }

  @override
  bool shouldRepaint(NoteScanPainter oldDelegate) =>
      oldDelegate.sweep != sweep ||
      oldDelegate.ink != ink ||
      oldDelegate.moving != moving;
}

/// Cross-fades one step's controls into the next while the space they take
/// grows or shrinks smoothly. Children need distinct keys per step.
class NoteScanSteps extends StatelessWidget {
  const NoteScanSteps({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: noteScanMotion(context, 340),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      fit: StackFit.passthrough,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .04),
            end: Offset.zero,
          ).animate(animation),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
    child: child,
  );
}

/// Fades and settles the scan screen in once when it opens. Assistant tools
/// switch routes instantly: during an animated route change both pages would
/// attach to the sheet's one scroll controller.
class NoteScanEntrance extends StatelessWidget {
  const NoteScanEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: noteScanMotion(context, 300),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
    ),
  );
}
