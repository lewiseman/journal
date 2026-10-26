import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:journal/common.dart' hide DiaryDayEntity;
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_sheet.dart';

/// All geometry uses the outer header's progress. The inner scrollable keeps
/// the same viewport and controller during a turn or a change of date.
class DiaryScene extends StatelessWidget {
  const DiaryScene({
    super.key,
    required this.day,
    required this.previous,
    required this.next,
    required this.today,
    required this.collapse,
    required this.headerHeight,
    this.collapseExtent = 80,
    required this.turn,
    required this.direction,
    required this.busy,
    required this.blocked,
    required this.reduced,
    required this.fade,
    required this.fadingFrom,
    required this.fadingOffset,
    required this.onCardWidth,
    required this.onDateChanged,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  final DiaryDayEntity day;
  final DiaryDayEntity previous;
  final DiaryDayEntity Function() next;
  final DateTime today;
  final double collapse, headerHeight, turn, collapseExtent;
  final int direction;
  final bool busy, blocked, reduced;
  final Animation<double> fade;
  final DiaryDayEntity? fadingFrom;
  final double fadingOffset;
  final ValueChanged<double> onCardWidth;
  final ValueChanged<DateTime> onDateChanged;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;
  final GestureDragCancelCallback? onDragCancel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final left = (w * .123).clamp(32.0, 64.0) * (1 - collapse);
      final right = 20 * (1 - collapse);
      final gap = 12 * (1 - collapse);
      final bottom = 40 * (1 - collapse);
      final shape = DiaryPaperShape.forDate(
        day.calendarDate,
        expansion: collapse,
      );
      final rect = Rect.fromLTRB(
        left,
        headerHeight + gap,
        w - right,
        math.max(headerHeight + gap, h - bottom),
      );
      onCardWidth(rect.width);
      final previewLeft = left - rect.width - 14 - collapse * w * .35;
      final showTurn = busy && turn > 0 && !blocked && !reduced;
      final paper = diaryPaperColors(context);
      final fullDate = MaterialLocalizations.of(context)
          .formatFullDate(day.calendarDate);
      final restLeft = (w * .123).clamp(32.0, 64.0);
      // The nested viewport grows as its header collapses. Keep captured faces
      // at their resting size so scrolling never invalidates their textures.
      final restRect = Rect.fromLTRB(
        restLeft,
        headerHeight + 12,
        w - 20,
        math.max(headerHeight + 12, h - collapseExtent * collapse - 40),
      );
      final showPreview = collapse < 1 && previewLeft + rect.width > 0;

      Widget face(DiaryDayEntity sheet, {required bool current}) {
        final incoming =
            !current &&
            showTurn &&
            (direction > 0
                ? sheet.calendarDate == previous.calendarDate
                : sheet.calendarDate.isAfter(day.calendarDate));
        final preview =
            !current &&
            sheet.calendarDate == previous.calendarDate &&
            !incoming;
        final x = current
            ? restRect.left + (blocked && busy ? -turn * rect.width : 0)
            : incoming
            ? (direction > 0 ? previewLeft : w + 14) * (1 - turn) +
                  rect.left * turn
            : previewLeft;
        final y = current
            ? restRect.top
            : rect.top +
                  (incoming ? (direction > 0 ? 16 * (1 - turn) : 0) : 16);
        final height = current
            ? restRect.height
            : math.max(
                0.0,
                rect.height -
                    (incoming ? (direction > 0 ? 24 * (1 - turn) : 0) : 24),
              );
        final opacity = current
            ? 1.0
            : incoming
            ? (direction > 0 ? .72 + .28 * turn : 1.0)
            : .72 * (1 - collapse);
        return Positioned.fromRect(
          key: ValueKey('diary-face-${sheet.calendarDate.toIso8601String()}'),
          rect: restRect,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(x - restRect.left, y - restRect.top),
                child: Transform.scale(
                  alignment: Alignment.topLeft,
                  scaleX: restRect.width > 0
                      ? (current ? 1 : rect.width / restRect.width)
                      : 1,
                  scaleY: restRect.height > 0 ? height / restRect.height : 1,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: DiaryPaperCurl(
                      progress: current && showTurn ? turn : 0,
                      direction: direction,
                      travel: w + restRect.width * .4,
                      paper: paper.background,
                      ink: paper.foreground,
                      shape: DiaryPaperShape.forDate(sheet.calendarDate),
                      flat: !(current && showTurn),
                      visible: current
                          ? showTurn
                          : incoming || (preview && showPreview),
                      warm:
                          collapse == 0 &&
                          !busy &&
                          !reduced &&
                          fadingFrom == null,
                      child: DiarySheet(
                        day: sheet,
                        minimumHeight: restRect.height,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final live = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: rect,
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('diary-active-paper'),
                isComplex: true,
                willChange: collapse > 0 && collapse < 1,
                painter: DiaryPaperPainter(
                  shape: shape,
                  paper: paper.background,
                  ink: paper.foreground,
                  shadow: true,
                  shadowColor: context.colors.shadow,
                ),
              ),
            ),
          ),
          Positioned.fill(
            left: left,
            right: right,
            child: ClipPath(
              clipper: DiaryPaperClipper(
                shape,
                viewport: Rect.fromLTWH(0, rect.top, rect.width, rect.height),
              ),
              child: CustomScrollView(
                key: const PageStorageKey('diary-content'),
                physics: busy
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                slivers: [
                  SliverOverlapInjector(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: gap)),
                  SliverToBoxAdapter(
                    child: DiaryDayContent(
                      day: day,
                      minimumHeight: rect.height,
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: bottom)),
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

      return Semantics(
        container: true,
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Previous day'): () =>
              onDateChanged(TimeHelper.addDays(day.calendarDate, -1)),
          if (day.calendarDate.isBefore(today))
            const CustomSemanticsAction(label: 'Next day'): () =>
                onDateChanged(TimeHelper.addDays(day.calendarDate, 1)),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragStart: onDragStart,
          onHorizontalDragUpdate: onDragUpdate,
          onHorizontalDragEnd: onDragEnd,
          onHorizontalDragCancel: onDragCancel,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  liveRegion: true,
                  label: 'Diary for $fullDate',
                  child: const SizedBox.shrink(),
                ),
                Visibility(
                  visible: !showTurn,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: Transform.translate(
                    offset: Offset(blocked && busy ? -turn * rect.width : 0, 0),
                    child: FadeTransition(opacity: fade, child: live),
                  ),
                ),
                if (fadingFrom != null && !showTurn)
                  Positioned.fromRect(
                    rect: rect,
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: FadeTransition(
                          opacity: ReverseAnimation(fade),
                          child: RepaintBoundary(
                            child: DiarySheet(
                              day: fadingFrom!,
                              shape: DiaryPaperShape.forDate(
                                fadingFrom!.calendarDate,
                                expansion: collapse,
                              ),
                              scrollOffset: fadingOffset,
                              minimumHeight: rect.height,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                face(previous, current: false),
                if (day.calendarDate.isBefore(today))
                  face(next(), current: false),
                face(day, current: true),
              ],
            ),
          ),
        ),
      );
    },
  );
}
