import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_curl.dart';
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

  final DiaryDay day;
  final DiaryDay previous;
  final DiaryDay Function() next;
  final DateTime today;
  final double collapse, headerHeight, turn;
  final int direction;
  final bool busy, blocked, reduced;
  final Animation<double> fade;
  final DiaryDay? fadingFrom;
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
      final bottom = 20 * (1 - collapse);
      final radius = 24 * (1 - collapse);
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
          .formatFullDate(day.date);

      final live = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: rect,
            child: DecoratedBox(
              key: const ValueKey('diary-active-paper'),
              decoration: BoxDecoration(
                color: paper.background,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: paper.foreground.withValues(
                    alpha: .06 * (1 - collapse),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.shadow.withValues(
                      alpha: .12 * (1 - collapse),
                    ),
                    blurRadius: 20 * (1 - collapse),
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            left: left,
            right: right,
            child: ClipPath(
              clipper: _SheetViewportClipper(
                top: rect.top,
                bottom: bottom,
                radius: radius,
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
                  SliverToBoxAdapter(child: DiaryDayContent(day: day)),
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
              onDateChanged(diaryDayAfter(day.date, -1)),
          if (day.date.isBefore(today))
            const CustomSemanticsAction(label: 'Next day'): () =>
                onDateChanged(diaryDayAfter(day.date, 1)),
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
                if (collapse < 1)
                  Positioned(
                    left: previewLeft,
                    top: rect.top + 16,
                    width: rect.width,
                    height: math.max(0, rect.height - 24),
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: .72 * (1 - collapse),
                          child: DiarySheet(
                            key: const ValueKey('diary-previous-preview'),
                            day: previous,
                          ),
                        ),
                      ),
                    ),
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
                          child: DiarySheet(
                            day: fadingFrom!,
                            radius: radius,
                            scrollOffset: fadingOffset,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showTurn) ...[
                  Positioned.fromRect(
                    rect: Rect.fromLTWH(
                      (direction > 0 ? previewLeft : w + 14) * (1 - turn) +
                          rect.left * turn,
                      rect.top + (direction > 0 ? 16 * (1 - turn) : 0),
                      rect.width,
                      rect.height - (direction > 0 ? 24 * (1 - turn) : 0),
                    ),
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: DiarySheet(
                          day: direction > 0 ? previous : next(),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: rect,
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: DiaryPaperCurl(
                          progress: turn,
                          direction: direction,
                          travel: w + rect.width * .4,
                          paper: paper.background,
                          child: DiarySheet(day: day),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SheetViewportClipper extends CustomClipper<Path> {
  const _SheetViewportClipper({
    required this.top,
    required this.bottom,
    required this.radius,
  });

  final double top, bottom, radius;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0, top, size.width, math.max(top, size.height - bottom)),
        Radius.circular(radius),
      ),
    );

  @override
  bool shouldReclip(_SheetViewportClipper oldClipper) =>
      top != oldClipper.top ||
      bottom != oldClipper.bottom ||
      radius != oldClipper.radius;
}
