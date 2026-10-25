import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

const _calendarPinSize = 24.0;
const _calendarPinOverhang = 13.0;
const _calendarPinHorizontalOffset = 8.0;

/// Paper date tabs on a fine ink curve. The page owns their motion, so the
/// calendar follows a sheet's drag, cancellation and settling frame for frame.
class DiaryCalendar extends StatelessWidget {
  const DiaryCalendar({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.lastDate,
    this.enabled = true,
    this.collapseProgress = 0,
    this.dayOffset = 0,
    this.onDayDragStart,
    this.onDayDragUpdate,
    this.onDayDragEnd,
    this.onDayDragCancel,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final DateTime? lastDate;
  final bool enabled;
  final double collapseProgress;

  /// Fractional calendar days from [selectedDate], driven by the sheet turn.
  /// There is no second controller or delayed animation after a date commits.
  final double dayOffset;

  final VoidCallback? onDayDragStart, onDayDragCancel;

  /// Physical horizontal movement and velocity, normalized to one date tab.
  final ValueChanged<double>? onDayDragUpdate, onDayDragEnd;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool _available(DateTime date) =>
      !date.isBefore(DateTime(1)) &&
      !date.isAfter(diaryDate(lastDate ?? DateTime.now()));

  void _selectDay(int offset) {
    final date = diaryDayAfter(selectedDate, offset);
    if (enabled && offset != 0 && _available(date)) onDateChanged(date);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final textScaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.3);
    final collapse = collapseProgress.clamp(0.0, 1.0);
    final height = ui.lerpDouble(108, 76, collapse)!;
    final contentInset = 48 * collapse;
    return RepaintBoundary(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final compactDayWidth = (width - 96) / 5;
                final dayWidth = ui.lerpDouble(
                  width * .18,
                  compactDayWidth,
                  collapse,
                )!;
                final middleDay = dayOffset.round();
                final previous = diaryDayAfter(selectedDate, -1);
                final next = diaryDayAfter(selectedDate, 1);
                return Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: 'Diary calendar',
                  value: localizations.formatFullDate(selectedDate),
                  increasedValue: _available(next)
                      ? localizations.formatFullDate(next)
                      : null,
                  decreasedValue: _available(previous)
                      ? localizations.formatFullDate(previous)
                      : null,
                  onIncrease: enabled && _available(next)
                      ? () => _selectDay(1)
                      : null,
                  onDecrease: enabled && _available(previous)
                      ? () => _selectDay(-1)
                      : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: onDayDragStart == null
                        ? null
                        : (_) => onDayDragStart!(),
                    onHorizontalDragUpdate: onDayDragUpdate == null
                        ? null
                        : (details) =>
                              onDayDragUpdate!(details.delta.dx / dayWidth),
                    onHorizontalDragEnd: onDayDragEnd == null
                        ? null
                        : (details) => onDayDragEnd!(
                            (details.primaryVelocity ?? 0) / dayWidth,
                          ),
                    onHorizontalDragCancel: onDayDragCancel,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _CalendarThreadPainter(
                                colors: context.colors,
                                collapse: collapse,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: ClipRect(
                            clipper: _CalendarContentClipper(contentInset),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                for (
                                  var day = middleDay - 3;
                                  day <= middleDay + 3;
                                  day++
                                )
                                  _buildDay(
                                    context: context,
                                    day: day,
                                    width: width,
                                    height: height,
                                    collapse: collapse,
                                    compactDayWidth: compactDayWidth,
                                    textScaler: textScaler,
                                    localizations: localizations,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDay({
    required BuildContext context,
    required int day,
    required double width,
    required double height,
    required double collapse,
    required double compactDayWidth,
    required TextScaler textScaler,
    required MaterialLocalizations localizations,
  }) {
    final relativeDay = day - dayOffset;
    final distance = relativeDay.abs();
    final opacity = ((2.65 - distance) / .55).clamp(0.0, 1.0);
    final prominence = Curves.easeInOut.transform(
      (1 - distance).clamp(0.0, 1.0),
    );
    final lift = 8 * (1 - prominence) * (1 - collapse);
    final pinned = day == dayOffset.round();
    final expandedX =
        width / 2 +
        relativeDay.sign *
            width *
            (.195 * distance - .015 * distance * distance);
    final x = ui.lerpDouble(
      expandedX,
      width / 2 + relativeDay * compactDayWidth,
      collapse,
    )!;
    final expandedPointY = _CalendarThreadPainter.heightAt(expandedX, width);
    final centerY =
        ui.lerpDouble(
          ui.lerpDouble(expandedPointY + 24, 62, prominence),
          _CalendarThreadPainter.compactCenterY,
          collapse,
        )! -
        lift;
    final targetWidth = ui.lerpDouble(76, compactDayWidth, collapse)!;
    final date = diaryDayAfter(selectedDate, day);
    final available = _available(date);
    final canSelect = enabled && available;
    final inactiveInk = Color.lerp(
      context.colors.onSurfaceVariant,
      context.colors.surface,
      available ? .18 : .50,
    )!;
    final ink = Color.lerp(inactiveInk, context.colors.primary, prominence)!;
    final sway = math.sin(dayOffset.abs() * math.pi);
    final tilt =
        (relativeDay.sign * .035 * (1 - prominence) + dayOffset * .065 * sway) *
        (1 - collapse);
    return Positioned(
      key: ValueKey('diary-calendar-date-${date.toIso8601String()}'),
      left: x - targetWidth / 2,
      top: 0,
      width: targetWidth,
      height: height,
      child: IgnorePointer(
        ignoring: !canSelect || opacity < .3,
        child: Opacity(
          opacity: opacity,
          child: Semantics(
            excludeSemantics: true,
            hidden: opacity < .3,
            button: true,
            enabled: canSelect,
            selected: day == 0,
            label: localizations.formatFullDate(date),
            onTap: canSelect ? () => _selectDay(day) : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canSelect ? () => _selectDay(day) : null,
              child: Transform.rotate(
                angle: tilt,
                alignment: Alignment(0, centerY / height * 2 - 1),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DatePaperPainter(
                          colors: context.colors,
                          date: date,
                          centerY: centerY,
                          prominence: prominence,
                          collapse: collapse,
                          pinned: pinned,
                        ),
                      ),
                    ),
                    if (pinned && collapse < 1)
                      Positioned(
                        top:
                            centerY -
                            _DatePaperPainter.heightFor(prominence, collapse) /
                                2 -
                            _calendarPinOverhang,
                        left: _calendarPinHorizontalOffset,
                        right: -_calendarPinHorizontalOffset,
                        height: _calendarPinSize,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 1 - collapse,
                            child: Center(
                              child: Image.asset(
                                'assets/images/diary_calendar_pin.png',
                                key: const ValueKey('diary-calendar-pin'),
                                width: _calendarPinSize,
                                height: _calendarPinSize,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                                excludeFromSemantics: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    _dateLabel(
                      text: '${date.day}',
                      centerY:
                          ui.lerpDouble(
                            ui.lerpDouble(expandedPointY + 16, 50, prominence),
                            24,
                            collapse,
                          )! -
                          lift,
                      style: TextStyle(
                        color: ink,
                        fontSize: ui.lerpDouble(
                          ui.lerpDouble(13, 23, prominence),
                          ui.lerpDouble(12.5, 17, prominence),
                          collapse,
                        ),
                        fontWeight: FontWeight.lerp(
                          FontWeight.w400,
                          FontWeight.w600,
                          prominence,
                        ),
                        height: 1,
                      ),
                      textScaler: textScaler,
                    ),
                    _dateLabel(
                      text: _weekdays[date.weekday - 1],
                      centerY:
                          ui.lerpDouble(
                            ui.lerpDouble(expandedPointY + 33, 71, prominence),
                            42,
                            collapse,
                          )! -
                          lift,
                      style: TextStyle(
                        color: ink,
                        fontSize: ui.lerpDouble(
                          ui.lerpDouble(10.5, 11.5, prominence),
                          10,
                          collapse,
                        ),
                        height: 1,
                      ),
                      textScaler: textScaler,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateLabel({
    required String text,
    required double centerY,
    required TextStyle style,
    required TextScaler textScaler,
  }) => Positioned(
    top: centerY - 18,
    left: 0,
    right: 0,
    height: 36,
    child: Center(
      child: Text(text, style: style, textScaler: textScaler, maxLines: 1),
    ),
  );
}

class _CalendarContentClipper extends CustomClipper<Rect> {
  const _CalendarContentClipper(this.inset);
  final double inset;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(inset, 0, size.width - inset, size.height);

  @override
  bool shouldReclip(_CalendarContentClipper oldClipper) =>
      inset != oldClipper.inset;
}

class _CalendarThreadPainter extends CustomPainter {
  const _CalendarThreadPainter({required this.collapse, required this.colors});
  final ColorScheme colors;
  final double collapse;
  static const compactCenterY = 33.0;

  static double heightAt(double x, double width, {double collapse = 0}) {
    final inset = 48 * collapse;
    final fraction = (x - inset) / (width - 2 * inset);
    return ui.lerpDouble(-15, compactCenterY, collapse)! +
        268 * (1 - collapse) * fraction * (1 - fraction);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final inset = 48 * collapse;
    final edgeY = ui.lerpDouble(-15, compactCenterY, collapse)!;
    final path = Path()..moveTo(inset, edgeY);
    path.quadraticBezierTo(
      size.width / 2,
      ui.lerpDouble(119, compactCenterY, collapse)!,
      size.width - inset,
      edgeY,
    );
    canvas.drawPath(
      path.shift(Offset(0, .8 * (1 - collapse))),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = colors.onSurface.withValues(alpha: .045 * (1 - collapse)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75
        ..color = colors.primary.withValues(
          alpha: ui.lerpDouble(.32, .10, collapse)!,
        ),
    );
  }

  @override
  bool shouldRepaint(_CalendarThreadPainter oldDelegate) =>
      collapse != oldDelegate.collapse || colors != oldDelegate.colors;
}

class _DatePaperPainter extends CustomPainter {
  const _DatePaperPainter({
    required this.colors,
    required this.date,
    required this.centerY,
    required this.prominence,
    required this.collapse,
    required this.pinned,
  });

  final ColorScheme colors;
  final DateTime date;
  final double centerY, prominence, collapse;
  final bool pinned;

  static double heightFor(double prominence, double collapse) =>
      ui.lerpDouble(ui.lerpDouble(50, 80, prominence), 52, collapse)!;

  @override
  void paint(Canvas canvas, Size size) {
    final width = ui.lerpDouble(
      ui.lerpDouble(44, 64, prominence),
      math.min(46, size.width - 4),
      collapse,
    )!;
    final height = heightFor(prominence, collapse);
    final bounds = Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: width,
      height: height,
    );
    final visibility = 1 - collapse;
    if (visibility > 0) {
      DiaryPaperStamp(
        paper: colors.surface,
        ink: colors.onSurface,
        shadowColor: colors.shadow,
        variant: date.weekday,
        edgeScale: .35,
        opacity: visibility,
      ).paintRect(canvas, bounds);
      if (!pinned) {
        canvas.drawCircle(
          Offset(size.width / 2, bounds.top + 9),
          1.15,
          Paint()
            ..color = colors.onSurfaceVariant.withValues(
              alpha: .28 * visibility,
            ),
        );
      }
    }
    if (prominence > 0) {
      final y = ui.lerpDouble(centerY + 26, 54, collapse)!;
      canvas.drawLine(
        Offset(size.width / 2 - 6 * prominence, y),
        Offset(size.width / 2 + 6 * prominence, y - .5 * (1 - collapse)),
        Paint()
          ..color = colors.primary.withValues(alpha: .65 * prominence)
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DatePaperPainter oldDelegate) =>
      colors != oldDelegate.colors ||
      date != oldDelegate.date ||
      centerY != oldDelegate.centerY ||
      prominence != oldDelegate.prominence ||
      collapse != oldDelegate.collapse ||
      pinned != oldDelegate.pinned;
}
