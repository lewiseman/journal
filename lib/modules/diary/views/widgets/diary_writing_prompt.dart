import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A writing invitation whose ruled lines follow the user's actual typography.
class DiaryWritingPrompt extends StatefulWidget {
  const DiaryWritingPrompt({super.key, required this.onTap});

  final VoidCallback onTap;

  static const question = 'What would you like to remember about today?';

  @override
  State<DiaryWritingPrompt> createState() => _DiaryWritingPromptState();
}

class _DiaryWritingPromptState extends State<DiaryWritingPrompt> {
  (double, TextStyle, TextScaler, TextDirection, Locale?)? _layoutKey;
  List<Path> _lines = const [];
  double _blankHeight = 0;

  void _layout(
    double width,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
    Locale? locale,
  ) {
    final key = (width, style, scaler, direction, locale);
    if (_layoutKey == key) return;
    final text = TextPainter(
      text: TextSpan(text: DiaryWritingPrompt.question, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      textHeightBehavior: const TextHeightBehavior(),
    )..layout(maxWidth: width);
    final metrics = text.computeLineMetrics();
    final lineHeight = text.preferredLineHeight;
    _lines = [
      for (final (index, line) in metrics.indexed)
        _stroke(
          line.left,
          math.min(width, line.left + line.width),
          line.baseline + line.descent - 2,
          index,
        ),
      for (var index = 0; index < 2; index++)
        _stroke(
          1 + index % 2,
          width - 1 - (index == 1 ? 3 : 0),
          text.height + lineHeight * (index + 1) - 2,
          metrics.length + index,
        ),
    ];
    _blankHeight = lineHeight * 2 + 4;
    _layoutKey = key;
    text.dispose();
  }

  // Bake a drifting centerline and uneven pen pressure into one filled shape.
  // The seed keeps the imperfections still across repaints and page turns.
  Path _stroke(double left, double right, double y, int index) {
    final width = math.max(0.0, right - left);
    final random = math.Random(104729 + index * 7919);
    final inset = math.min(1.5, width * .01);
    final start = left + random.nextDouble() * inset;
    final end = right - random.nextDouble() * inset;
    final phase = random.nextDouble() * math.pi * 2;
    final segments = (width / 22).round().clamp(6, 18);
    final upper = <Offset>[];
    final lower = <Offset>[];
    for (var point = 0; point <= segments; point++) {
      final t = point / segments;
      final drift =
          (math.sin(t * math.pi * 1.6 + phase) * 1.05 +
                  math.sin(t * math.pi * 4.3 + phase * .7) * .35 +
                  (random.nextDouble() - .5) * .65 -
                  .45)
              .clamp(-1.6, .6);
      final taper = .12 + .88 * (math.min(t, 1 - t) / .12).clamp(0.0, 1.0);
      final pressure = (.36 + random.nextDouble() * .36) * taper;
      final x = start + (end - start) * t;
      upper.add(Offset(x, y + drift - pressure));
      lower.add(Offset(x, y + drift + pressure));
    }
    final path = Path()..moveTo(upper.first.dx, upper.first.dy);
    void trace(List<Offset> edge) {
      for (var point = 1; point < edge.length - 1; point++) {
        final middle = Offset.lerp(edge[point], edge[point + 1], .5)!;
        path.quadraticBezierTo(
          edge[point].dx,
          edge[point].dy,
          middle.dx,
          middle.dy,
        );
      }
      path.lineTo(edge.last.dx, edge.last.dy);
    }

    trace(upper);
    path.lineTo(lower.last.dx, lower.last.dy);
    trace(lower.reversed.toList());
    return path..close();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyLarge!.copyWith(
      inherit: false,
      color: colors.onSurfaceVariant,
      fontSize: 18,
      height: 1.7,
      letterSpacing: -.2,
      fontWeight: MediaQuery.boldTextOf(context)
          ? FontWeight.bold
          : FontWeight.w400,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _layout(constraints.maxWidth, style, scaler, direction, locale);
        return Semantics(
          button: true,
          label: DiaryWritingPrompt.question,
          hint: 'Write a diary entry',
          onTap: widget.onTap,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('diary-writing-prompt'),
              onTap: widget.onTap,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(4),
              splashColor: colors.primary.withValues(alpha: .06),
              highlightColor: colors.primary.withValues(alpha: .03),
              child: CustomPaint(
                key: const ValueKey('diary-prompt-lines'),
                painter: _WritingLinesPainter(
                  lines: _lines,
                  color: colors.onSurfaceVariant.withValues(
                    alpha: colors.brightness == Brightness.dark ? .42 : .30,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DiaryWritingPrompt.question,
                      key: const ValueKey('diary-prompt-question'),
                      style: style,
                      textAlign: TextAlign.start,
                      textDirection: direction,
                      textScaler: scaler,
                      locale: locale,
                      textHeightBehavior: const TextHeightBehavior(),
                    ),
                    SizedBox(height: _blankHeight),
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

class _WritingLinesPainter extends CustomPainter {
  const _WritingLinesPainter({required this.lines, required this.color});

  final List<Path> lines;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()..color = color;
    for (final line in lines) {
      canvas.drawPath(line, pen);
    }
  }

  @override
  bool shouldRepaint(_WritingLinesPainter oldDelegate) =>
      lines != oldDelegate.lines || color != oldDelegate.color;
}
