import 'package:journal/common.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/widgets/diary_calendar.dart';
import 'package:journal/modules/diary/views/widgets/diary_header_control.dart';

/// A pinned header whose geometry follows the same scroll offset as the feed.
/// Keeping it inside the sliver layout avoids offset feedback as it contracts.
class DiaryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const DiaryHeaderDelegate({
    required this.topInset,
    required this.selectedDate,
    this.lastDate,
    this.enabled = true,
    required this.controlsHeight,
    required this.onDateChanged,
    required this.onSearch,
    required this.onPickDate,
    this.turn = kAlwaysDismissedAnimation,
    this.turnDirection = 1,
    this.turning = false,
    this.onDayDragStart,
    this.onDayDragUpdate,
    this.onDayDragEnd,
    this.onDayDragCancel,
  });

  final double topInset;
  final DateTime selectedDate;
  final DateTime? lastDate;
  final bool enabled;
  final double controlsHeight;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback? onSearch;
  final VoidCallback onPickDate;
  final Animation<double> turn;
  final int turnDirection;
  final bool turning;
  final VoidCallback? onDayDragStart, onDayDragCancel;
  final ValueChanged<double>? onDayDragUpdate, onDayDragEnd;

  @override
  double get maxExtent => topInset + controlsHeight + 118;

  @override
  double get minExtent => topInset + 82;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final expandedTop = 6 + controlsHeight / 2 - 24;
    final actionTop = topInset + expandedTop + (17 - expandedTop) * progress;
    final actionInset = 14 * (1 - progress);
    final foreground = AnimatedBuilder(
      animation: turn,
      builder: (context, _) {
        final offset = turning
            ? -turnDirection * turn.value.clamp(0.0, 1.0)
            : 0.0;
        final incoming = diaryDayAfter(selectedDate, -turnDirection);
        final displayDate =
            offset.abs() >= .5 &&
                !incoming.isAfter(diaryDate(lastDate ?? DateTime.now()))
            ? incoming
            : selectedDate;
        return ClipRect(
          child: Stack(
            children: [
              Column(
                children: [
                  SizedBox(height: topInset + 6),
                  SizedBox(height: controlsHeight * (1 - progress)),
                  SizedBox(height: 4 * (1 - progress)),
                  DiaryCalendar(
                    selectedDate: selectedDate,
                    lastDate: lastDate,
                    enabled: enabled,
                    onDateChanged: onDateChanged,
                    collapseProgress: progress,
                    dayOffset: offset,
                    onDayDragStart: onDayDragStart,
                    onDayDragUpdate: onDayDragUpdate,
                    onDayDragEnd: onDayDragEnd,
                    onDayDragCancel: onDayDragCancel,
                  ),
                ],
              ),
              Positioned(
                left: actionInset,
                top: actionTop,
                width: 88 + (48 - 88) * progress,
                height: 48,
                child: _action(
                  action: DiaryHeaderAction.date,
                  progress: progress,
                  onTap: onPickDate,
                  date: displayDate,
                ),
              ),
              Positioned(
                right: actionInset,
                top: actionTop,
                width: 76 + (48 - 76) * progress,
                height: 48,
                child: _action(
                  action: DiaryHeaderAction.search,
                  progress: progress,
                  onTap: onSearch,
                ),
              ),
            ],
          ),
        );
      },
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom:
              -_DiaryHeaderGradient.fadeExtent *
              Curves.easeOutCubic.transform(progress),
          child: IgnorePointer(child: _DiaryHeaderGradient(progress: progress)),
        ),
        foreground,
      ],
    );
  }

  Widget _action({
    required DiaryHeaderAction action,
    required double progress,
    required VoidCallback? onTap,
    DateTime? date,
  }) => DiaryHeaderControl(
    key: ValueKey(
      action == DiaryHeaderAction.date
          ? 'diary-date-control'
          : 'diary-search-control',
    ),
    collapseProgress: progress,
    action: action,
    date: date ?? selectedDate,
    onTap: enabled ? onTap : null,
  );

  @override
  bool shouldRebuild(DiaryHeaderDelegate oldDelegate) =>
      oldDelegate.topInset != topInset ||
      oldDelegate.selectedDate != selectedDate ||
      oldDelegate.lastDate != lastDate ||
      oldDelegate.enabled != enabled ||
      oldDelegate.turn != turn ||
      oldDelegate.turnDirection != turnDirection ||
      oldDelegate.turning != turning ||
      oldDelegate.onDayDragStart != onDayDragStart ||
      oldDelegate.onDayDragUpdate != onDayDragUpdate ||
      oldDelegate.onDayDragEnd != onDayDragEnd ||
      oldDelegate.onDayDragCancel != onDayDragCancel ||
      oldDelegate.controlsHeight != controlsHeight ||
      oldDelegate.onDateChanged != onDateChanged ||
      oldDelegate.onSearch != onSearch ||
      oldDelegate.onPickDate != onPickDate;
}

/// A tinted surface that blends into the diary below the pinned header.
class _DiaryHeaderGradient extends StatelessWidget {
  const _DiaryHeaderGradient({required this.progress});

  final double progress;
  static const fadeExtent = 56.0;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0) return const SizedBox.expand();

    final color = context.colors.surface;
    final visibility = Curves.easeOutCubic.transform(progress);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tailFraction = fadeExtent * visibility / constraints.maxHeight;
        final coreFraction = 1 - tailFraction;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [
                0,
                coreFraction * .65,
                coreFraction,
                coreFraction + tailFraction * .25,
                coreFraction + tailFraction * .5,
                coreFraction + tailFraction * .75,
                1,
              ],
              colors: [
                color.withValues(alpha: visibility),
                color.withValues(alpha: visibility),
                color.withValues(alpha: .98 * visibility),
                color.withValues(alpha: .84 * visibility),
                color.withValues(alpha: .50 * visibility),
                color.withValues(alpha: .16 * visibility),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        );
      },
    );
  }
}
