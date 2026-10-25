import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

enum DiaryHeaderAction { date, search }

/// A single, persistent header action whose appearance follows the scroll.
///
/// The parent moves and sizes its 48-pixel touch target while this widget
/// changes only the smaller visual surface inside it.
class DiaryHeaderControl extends StatelessWidget {
  const DiaryHeaderControl({
    super.key,
    required this.collapseProgress,
    required this.action,
    required this.date,
    required this.onTap,
  });

  final double collapseProgress;
  final DiaryHeaderAction action;
  final DateTime date;
  final VoidCallback? onTap;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final progress = collapseProgress.clamp(0.0, 1.0);
    final isDate = action == DiaryHeaderAction.date;
    final tooltip = isDate ? 'Choose date' : 'Search diary';
    final label = isDate
        ? '$tooltip, ${MaterialLocalizations.of(context).formatMonthYear(date)}'
        : tooltip;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(lerpDouble(6, 16, progress)!),
              splashColor: context.colors.primary.withValues(alpha: 0.200),
              highlightColor: context.colors.primary.withValues(alpha: 0.102),
              child: Center(child: _surface(context, progress, isDate: isDate)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _surface(
    BuildContext context,
    double progress, {
    required bool isDate,
  }) {
    final foreground = Color.lerp(
      context.colors.onSurface,
      context.colors.onSurfaceVariant,
      progress,
    )!;
    return SizedBox(
      width: lerpDouble(isDate ? 88 : 70, 32, progress),
      height: lerpDouble(34, 32, progress),
      child: CustomPaint(
        painter: _HeaderPaperPainter(
          progress: progress,
          colors: context.colors,
        ),
        child: Center(
          child: isDate
              ? _dateContent(progress, foreground)
              : Icon(
                  Icons.search_rounded,
                  size: lerpDouble(24, 19, progress),
                  color: foreground,
                ),
        ),
      ),
    );
  }

  Widget _dateContent(double progress, Color foreground) {
    final textOpacity = (1 - progress / .4).clamp(0.0, 1.0);
    final iconOpacity = Curves.easeOutCubic.transform(
      ((progress - .3) / .5).clamp(0.0, 1.0),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        if (textOpacity > 0)
          Opacity(
            opacity: textOpacity,
            child: Transform.translate(
              offset: Offset(-5 * progress, 0),
              child: Transform.scale(
                scale: 1 - .12 * progress,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    '${_months[date.month - 1]} ${date.year}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Opacity(
          opacity: iconOpacity,
          child: Transform.scale(
            scale: .72 + .28 * progress,
            child: Icon(Icons.date_range_outlined, size: 19, color: foreground),
          ),
        ),
      ],
    );
  }
}

class _HeaderPaperPainter extends CustomPainter {
  const _HeaderPaperPainter({required this.progress, required this.colors});

  final double progress;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
        Paint()..color = colors.surfaceContainerLow.withValues(alpha: progress),
      );
    }
    if (progress == 1) return;
    DiaryPaperStamp(
      paper: colors.surface,
      ink: colors.onSurface,
      shadowColor: colors.shadow,
      edgeScale: .25,
      opacity: 1 - progress,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_HeaderPaperPainter oldDelegate) =>
      progress != oldDelegate.progress || colors != oldDelegate.colors;
}
