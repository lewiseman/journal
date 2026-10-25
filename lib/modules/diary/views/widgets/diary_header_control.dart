import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';

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
              borderRadius: BorderRadius.circular(24),
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
    return Container(
      width: lerpDouble(isDate ? 88 : 70, 32, progress),
      height: lerpDouble(34, 32, progress),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(lerpDouble(22, 16, progress)!),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              context.colors.surfaceContainerLow.withValues(alpha: 0.667),
              context.colors.surfaceContainerLow.withValues(alpha: 0.933),
              progress,
            )!,
            Color.lerp(
              context.colors.surfaceContainerLow.withValues(alpha: 0.714),
              context.colors.surfaceContainerLow.withValues(alpha: 0.933),
              progress,
            )!,
          ],
        ),
        border: Border.all(
          color: Color.lerp(
            context.colors.primary.withValues(alpha: 0.800),
            context.colors.primary.withValues(alpha: 0.502),
            progress,
          )!,
          width: .8,
        ),
        boxShadow: [
          BoxShadow(
            color: Color.lerp(
              context.colors.primary.withValues(alpha: 0.400),
              context.colors.primary.withValues(alpha: 0.161),
              progress,
            )!,
            blurRadius: lerpDouble(13, 6, progress)!,
            spreadRadius: -1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: isDate
          ? _dateContent(progress, foreground)
          : Icon(
              Icons.search_rounded,
              size: lerpDouble(24, 19, progress),
              color: foreground,
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
