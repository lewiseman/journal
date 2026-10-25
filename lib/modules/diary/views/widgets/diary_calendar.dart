import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:journal/config/theme.dart';
import 'package:flutter/physics.dart';

/// A date carousel that follows the illuminated horizon above the diary.
///
/// Dates are calendar days rather than 24-hour intervals, so changing days also
/// works when a daylight-saving transition changes the length of a local day.
class DiaryCalendar extends StatefulWidget {
  const DiaryCalendar({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.lastDate,
    this.enabled = true,
    this.collapseProgress = 0,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final DateTime? lastDate;
  final bool enabled;

  /// Scroll-driven progress from the full horizon to the compact date strip.
  ///
  /// Geometry follows this value directly so reversing a scroll immediately
  /// reverses the morph, without a second animation trailing the user's hand.
  final double collapseProgress;

  @override
  State<DiaryCalendar> createState() => _DiaryCalendarState();
}

class _DiaryCalendarState extends State<DiaryCalendar>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 310,
    damping: 29,
  );
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late final DateTime _anchor;
  late final AnimationController _position;
  int _selectedDay = 0;
  bool _reduceMotion = false;
  double _dayWidth = 72;

  @override
  void initState() {
    super.initState();
    final today = _civilDate(widget.lastDate ?? DateTime.now());
    final selectedDate = _civilDate(widget.selectedDate);
    _anchor = selectedDate.isAfter(today) ? today : selectedDate;
    _position = AnimationController.unbounded(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduceMotion && !_reduceMotion) {
      _position.stop();
      _position.value = _selectedDay.toDouble();
    }
    _reduceMotion = reduceMotion;
  }

  @override
  void didUpdateWidget(DiaryCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedDay = math.min(_offsetFor(widget.selectedDate), _lastDay);
    if (selectedDay != _selectedDay) {
      _selectedDay = selectedDay;
      _settleOn(selectedDay);
    }
  }

  static DateTime _civilDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  int _offsetFor(DateTime date) => DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(_anchor.year, _anchor.month, _anchor.day)).inDays;

  DateTime _dateAt(int day) =>
      DateTime(_anchor.year, _anchor.month, _anchor.day + day);

  int get _lastDay => _offsetFor(widget.lastDate ?? DateTime.now());
  int get _firstDay => _offsetFor(DateTime(1));

  double get _visiblePosition => math.min(_position.value, _lastDay.toDouble());

  void _settleOn(int day, {double velocity = 0}) {
    _position.stop();
    if (_reduceMotion) {
      _position.value = day.toDouble();
      return;
    }
    _position.animateWith(
      SpringSimulation(
        _spring,
        _visiblePosition,
        day.toDouble(),
        (day == _lastDay ? math.min(velocity, 0.0) : velocity).clamp(
          -14.0,
          14.0,
        ),
        tolerance: const Tolerance(distance: 0.001, velocity: 0.001),
      ),
    );
  }

  void _selectDay(int day, {double velocity = 0}) {
    if (!widget.enabled) return;
    final target = day.clamp(_firstDay, _lastDay);
    if (_selectedDay != target) {
      // Selection belongs to the parent, which may still be turning a sheet.
      // Only didUpdateWidget commits it; a requested turn cannot leave the
      // calendar on a different date from the active diary.
      widget.onDateChanged(_dateAt(target));
    }
    // A parent may navigate away from the diary in its callback.
    if (mounted) _settleOn(target, velocity: velocity);
  }

  void _moveBy(int days) {
    _selectDay(_selectedDay + days, velocity: _position.velocity);
  }

  void _dragEnd(DragEndDetails details) {
    final velocity = -(details.primaryVelocity ?? 0) / _dayWidth;
    final nearestDay = _visiblePosition.round();
    // A flick carries momentum without skipping a long stretch of the diary.
    final target = (_visiblePosition + velocity * 0.13).round().clamp(
      nearestDay - 2,
      nearestDay + 2,
    );
    _selectDay(target, velocity: velocity);
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final textScaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.3);
    final collapse = widget.collapseProgress.clamp(0.0, 1.0);
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
                _dayWidth = ui.lerpDouble(
                  width * 0.18,
                  compactDayWidth,
                  collapse,
                )!;
                final orbRadius = ui.lerpDouble(
                  (width * 0.074).clamp(29.0, 32.0),
                  22,
                  collapse,
                )!;
                return Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: 'Diary calendar',
                  value: localizations.formatFullDate(_dateAt(_selectedDay)),
                  increasedValue: _selectedDay < _lastDay
                      ? localizations.formatFullDate(_dateAt(_selectedDay + 1))
                      : null,
                  decreasedValue: localizations.formatFullDate(
                    _dateAt(_selectedDay - 1),
                  ),
                  onIncrease: widget.enabled && _selectedDay < _lastDay
                      ? () => _moveBy(1)
                      : null,
                  onDecrease: widget.enabled && _selectedDay > _firstDay
                      ? () => _moveBy(-1)
                      : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _position.stop(),
                    onHorizontalDragUpdate: (details) {
                      _position.value = math.min(
                        _visiblePosition - details.delta.dx / _dayWidth,
                        _lastDay.toDouble(),
                      );
                    },
                    onHorizontalDragEnd: _dragEnd,
                    onHorizontalDragCancel: () => _settleOn(_selectedDay),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _HorizonPainter(
                                  colors: context.colors,
                                  collapse: collapse,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: ClipRect(
                            clipper: _CalendarContentClipper(contentInset),
                            child: AnimatedBuilder(
                              animation: _position,
                              builder: (context, _) {
                                final middleDay = _visiblePosition.round();
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    for (
                                      var day = middleDay - 3;
                                      day <= middleDay + 3;
                                      day++
                                    )
                                      _buildDay(
                                        day: day,
                                        width: width,
                                        height: height,
                                        collapse: collapse,
                                        compactDayWidth: compactDayWidth,
                                        orbRadius: orbRadius,
                                        textScaler: textScaler,
                                        localizations: localizations,
                                      ),
                                  ],
                                );
                              },
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
    required int day,
    required double width,
    required double height,
    required double collapse,
    required double compactDayWidth,
    required double orbRadius,
    required TextScaler textScaler,
    required MaterialLocalizations localizations,
  }) {
    final relativeDay = day - _visiblePosition;
    final distance = relativeDay.abs();
    final opacity = ((2.65 - distance) / 0.55).clamp(0.0, 1.0);
    final prominence = Curves.easeInOut.transform(
      (1 - distance).clamp(0.0, 1.0),
    );
    final direction = relativeDay.sign;
    // Neighbors sit a little wider than the outer days, as on an orbit.
    final expandedX =
        width / 2 +
        direction * width * (0.195 * distance - 0.015 * distance * distance);
    final x = ui.lerpDouble(
      expandedX,
      width / 2 + relativeDay * compactDayWidth,
      collapse,
    )!;
    final expandedPointY = _HorizonPainter.heightAt(expandedX, width);
    final pointY = _HorizonPainter.heightAt(x, width, collapse: collapse);
    final targetWidth = ui.lerpDouble(76, compactDayWidth, collapse)!;
    final date = _dateAt(day);
    final selected = day == _selectedDay;
    final available = day >= _firstDay && day <= _lastDay;
    final enabled = widget.enabled && available;
    return Positioned(
      key: ValueKey(day),
      left: x - targetWidth / 2,
      top: 0,
      width: targetWidth,
      height: height,
      child: IgnorePointer(
        ignoring: !enabled || opacity < 0.3,
        child: Opacity(
          opacity: opacity * (available ? 1 : .35),
          child: Semantics(
            excludeSemantics: true,
            hidden: opacity < 0.3,
            button: true,
            enabled: enabled,
            selected: selected,
            label: localizations.formatFullDate(date),
            onTap: enabled ? () => _selectDay(day) : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => _selectDay(day) : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DayOrbPainter(
                        colors: context.colors,
                        pointY: pointY,
                        prominence: prominence,
                        radius: orbRadius,
                        collapse: collapse,
                      ),
                    ),
                  ),
                  _dateLabel(
                    text: '${date.day}',
                    centerY: ui.lerpDouble(
                      ui.lerpDouble(expandedPointY + 16, 50, prominence),
                      24,
                      collapse,
                    )!,
                    style: TextStyle(
                      color: Color.lerp(
                        context.colors.onSurface,
                        context.colors.onPrimary,
                        prominence,
                      ),
                      fontSize: ui.lerpDouble(
                        ui.lerpDouble(12.5, 21, prominence),
                        ui.lerpDouble(12.5, 16, prominence),
                        collapse,
                      ),
                      fontWeight: prominence > 0.5
                          ? FontWeight.w600
                          : FontWeight.w400,
                      height: 1,
                    ),
                    textScaler: textScaler,
                  ),
                  _dateLabel(
                    text: _weekdays[date.weekday - 1],
                    centerY: ui.lerpDouble(
                      ui.lerpDouble(expandedPointY + 33, 71, prominence),
                      42,
                      collapse,
                    )!,
                    style: TextStyle(
                      color: Color.lerp(
                        context.colors.onSurfaceVariant,
                        context.colors.onPrimary,
                        prominence,
                      ),
                      fontSize: ui.lerpDouble(
                        ui.lerpDouble(11, 12, prominence),
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

class _HorizonPainter extends CustomPainter {
  const _HorizonPainter({required this.collapse, required this.colors});
  final ColorScheme colors;

  // Midway between the compact number (24) and weekday (42).
  static const compactCenterY = 33.0;

  final double collapse;

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
    if (collapse == 1) {
      path.lineTo(size.width - inset, edgeY);
    } else {
      path.quadraticBezierTo(
        size.width / 2,
        ui.lerpDouble(119, compactCenterY, collapse)!,
        size.width - inset,
        edgeY,
      );
    }
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..color = colors.glow(.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path, glow);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = colors.glow(.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          colors: [
            colors.primary.withValues(alpha: .25),
            colors.primary,
            colors.primary,
            colors.primary,
            colors.primary.withValues(alpha: .25),
          ],
          stops: [0, 0.16, 0.5, 0.84, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_HorizonPainter oldDelegate) =>
      collapse != oldDelegate.collapse || colors != oldDelegate.colors;
}

class _DayOrbPainter extends CustomPainter {
  const _DayOrbPainter({
    required this.colors,
    required this.pointY,
    required this.prominence,
    required this.radius,
    required this.collapse,
  });

  final ColorScheme colors;
  final double pointY;
  final double prominence;
  final double radius;
  final double collapse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      ui.lerpDouble(
        pointY,
        ui.lerpDouble(62, _HorizonPainter.compactCenterY, collapse),
        prominence,
      )!,
    );
    final orbRadius = ui.lerpDouble(3.1, radius, prominence)!;
    canvas.drawCircle(
      center,
      orbRadius + ui.lerpDouble(2, 5, prominence)!,
      Paint()
        ..color = colors.glow(ui.lerpDouble(.6, .65, prominence)!)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          ui.lerpDouble(4, ui.lerpDouble(12, 6, collapse), prominence)!,
        ),
    );
    if (prominence > 0.01) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(0, orbRadius * 0.72),
          width: orbRadius * 1.75,
          height: orbRadius * 0.7,
        ),
        Paint()
          ..color = colors.glow(prominence * .8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    final bounds = Rect.fromCircle(center: center, radius: orbRadius);
    canvas.drawCircle(
      center,
      orbRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.8),
          radius: 1.3,
          colors: [
            Color.lerp(colors.primary, colors.onPrimary, .08)!,
            colors.primary,
            colors.primary,
            Color.lerp(colors.primary, colors.onPrimary, .04)!,
          ],
          stops: const [0, 0.22, 0.6, 1],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      center,
      orbRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, colors.onPrimary, .18)!,
            colors.primary,
          ],
        ).createShader(bounds),
    );
    if (prominence > 0.01) {
      canvas.drawCircle(
        center,
        math.max(0, orbRadius - 1.7),
        Paint()
          ..color = colors.primary.withValues(alpha: prominence * 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else {
      canvas.drawCircle(center, 1.8, Paint()..color = colors.primary);
    }
  }

  @override
  bool shouldRepaint(_DayOrbPainter oldDelegate) =>
      pointY != oldDelegate.pointY ||
      prominence != oldDelegate.prominence ||
      radius != oldDelegate.radius ||
      collapse != oldDelegate.collapse ||
      colors != oldDelegate.colors;
}
