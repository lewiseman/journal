import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:journal/modules/notes/views/widgets/note_ai_widgets.dart';

import 'note_scan_stage.dart';

/// A frosted capsule that floats over the page or the viewfinder.
class NoteScanGlass extends StatelessWidget {
  const NoteScanGlass({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(32),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Padding(padding: const EdgeInsets.all(6), child: child),
      ),
    ),
  );
}

/// One round control in a [NoteScanGlass]; its tooltip is its name.
class NoteScanTool extends StatelessWidget {
  const NoteScanTool({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 22,
    style: IconButton.styleFrom(
      fixedSize: const Size(48, 48),
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: .12),
      disabledForegroundColor: Colors.white.withValues(alpha: .35),
      disabledBackgroundColor: Colors.white.withValues(alpha: .05),
    ),
    icon: Icon(icon),
  );
}

/// Round controls spaced evenly in one capsule.
class NoteScanToolbar extends StatelessWidget {
  const NoteScanToolbar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => NoteScanGlass(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          child,
        ],
      ],
    ),
  );
}

/// The empty viewfinder: a shutter to take a photo, or a photo to choose.
class NoteScanEmpty extends StatelessWidget {
  const NoteScanEmpty({
    super.key,
    required this.onCamera,
    required this.onGallery,
    this.cameraKey,
    this.galleryKey,
  });
  final VoidCallback? onCamera, onGallery;
  final Key? cameraKey, galleryKey;

  @override
  Widget build(BuildContext context) {
    final ink = NoteAiTool.scan.ink(context);
    final label = Theme.of(context).textTheme.labelLarge;
    return CustomPaint(
      painter: _CornersPainter(Colors.white.withValues(alpha: .5)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: 'Take photo',
              child: ExcludeSemantics(
                child: Material(
                  key: cameraKey,
                  color: Colors.white,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .35),
                      width: 6,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onCamera,
                    child: SizedBox.square(
                      dimension: 76,
                      child: Icon(
                        Icons.photo_camera_rounded,
                        color: ink,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Take photo',
              style: label?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            TextButton.icon(
              key: galleryKey,
              onPressed: onGallery,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: .14),
                disabledForegroundColor: Colors.white.withValues(alpha: .4),
                shape: const StadiumBorder(),
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text('Choose image'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Viewfinder corners, like a camera framing a page.
class _CornersPainter extends CustomPainter {
  const _CornersPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 22.0;
    final arm = math.min(34.0, size.shortestSide * .14);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final (sx, sy) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      final x = sx == 0 ? inset : size.width - inset;
      final y = sy == 0 ? inset : size.height - inset;
      final dx = sx == 0 ? arm : -arm;
      final dy = sy == 0 ? arm : -arm;
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy)
          ..lineTo(x, y)
          ..lineTo(x + dx, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CornersPainter oldDelegate) => oldDelegate.color != color;
}

/// A one-word status and a spoken description of a read in [phase].
(String, String) noteScanPhase(String phase) => switch (phase) {
  'queued' || 'accepted' => ('Waiting', 'Waiting to begin'),
  'restoring' || 'retrieving' => ('Checking', 'Checking your task'),
  'running' => ('Reading', 'Reading your page'),
  'saving' => ('Saving', 'Saving your note'),
  _ => ('Sending', 'Sending your page'),
};

/// Floats over the page while it is read: a breathing dot, what is
/// happening, and Stop. Announced once to screen readers.
class NoteScanReading extends StatefulWidget {
  const NoteScanReading({
    super.key,
    required this.phase,
    this.onStop,
    this.stopKey,
  });
  final String phase;
  final VoidCallback? onStop;
  final Key? stopKey;

  @override
  State<NoteScanReading> createState() => _NoteScanReadingState();
}

class _NoteScanReadingState extends State<NoteScanReading>
    with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(milliseconds: 1300),
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
    if (noteScanAnimates(context)) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (status, spoken) = noteScanPhase(widget.phase);
    final light = Color.lerp(NoteAiTool.scan.ink(context), Colors.white, .55)!;
    return NoteScanGlass(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 12),
          Semantics(
            liveRegion: true,
            label: '$spoken.',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  FadeTransition(
                    opacity: Tween(begin: .35, end: 1.0).animate(_breath),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: light,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: light.withValues(alpha: .7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: noteScanMotion(context, 220),
                    child: Text(
                      status,
                      key: ValueKey(status),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (widget.onStop != null)
            NoteScanTool(
              key: widget.stopKey,
              icon: Icons.stop_rounded,
              tooltip: 'Stop',
              onPressed: widget.onStop,
            )
          else
            const SizedBox(width: 4, height: 48),
        ],
      ),
    );
  }
}

enum NoteScanTone { info, good, caution, error }

(IconData, Color) noteScanTone(BuildContext context, NoteScanTone tone) {
  final theme = Theme.of(context);
  return switch (tone) {
    NoteScanTone.info => (
      Icons.info_outline_rounded,
      NoteAiTool.scan.ink(context),
    ),
    NoteScanTone.good => (Icons.verified_rounded, NoteAiTool.scan.ink(context)),
    NoteScanTone.caution => (
      Icons.flag_rounded,
      theme.brightness == Brightness.dark
          ? const Color(0xFFE8C07A)
          : const Color(0xFF8A5A00),
    ),
    NoteScanTone.error => (
      Icons.error_outline_rounded,
      theme.colorScheme.error,
    ),
  };
}

/// A compact rounded note for warnings and errors.
class NoteScanCallout extends StatelessWidget {
  const NoteScanCallout(this.text, {super.key, this.tone = NoteScanTone.info});
  final String text;
  final NoteScanTone tone;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = noteScanTone(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small tonal pill: an icon and a few words.
class NoteScanPill extends StatelessWidget {
  const NoteScanPill(this.label, {super.key, required this.tone});
  final String label;
  final NoteScanTone tone;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = noteScanTone(context, tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
