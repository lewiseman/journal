import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:journal/common.dart';
import 'package:journal/modules/flow/views/widgets/flow_thought_card.dart';

/// Shared geometry keeps the cards and floating composer on the same timeline.
class FlowSceneLayout {
  FlowSceneLayout({
    required this.width,
    required this.height,
    required this.textScale,
    required this.composerHeight,
    required this.thoughtCount,
  });

  static const gutter = 24.0;
  static const gap = 14.0;
  static const bottom = 34.0;
  static const topInset = 20.0;

  final double width;
  final double height;
  final double textScale;
  final double composerHeight;
  final int thoughtCount;

  late final columns = width < 350 || textScale > 1.4 ? 1 : 2;
  late final composerTop = height - bottom - composerHeight;
  late final cardScale = textScale.clamp(1.0, 2.2);
  late final _previewSpace = math.max(68.0, composerTop - topInset - 138);
  late final _previewCapacity = columns == 2 && _previewSpace >= 320 ? 6 : 4;
  late final previewCount = math.min(thoughtCount, _previewCapacity);

  // Balanced column heights let the lazy grid continue below these same
  // cards, without gaps or duplicate previews.
  late final List<Rect> settled = () {
    final cardWidth = (width - gutter * 2 - gap * (columns - 1)) / columns;
    final cursors = List.filled(columns, topInset);
    return [
      for (var i = 0; i < previewCount; i++)
        (() {
          final column = i % columns;
          final cardHeight =
              [152.0, 190.0, 190.0, 152.0, 172.0, 172.0][i] * cardScale;
          final rect = Rect.fromLTWH(
            gutter + column * (cardWidth + gap),
            cursors[column],
            cardWidth,
            cardHeight,
          );
          cursors[column] += cardHeight + gap;
          return rect;
        })(),
    ];
  }();

  late final minExtent =
      (settled.isEmpty
          ? previewBottom
          : settled.map((rect) => rect.bottom).reduce(math.max)) +
      gap;
  late final maxExtent = math.max(height, minExtent + 220);
  late final collapseExtent = maxExtent - minExtent;

  late final List<Rect> scattered = () {
    final areaHeight = math.min(
      _previewSpace,
      _previewCapacity == 6 ? 340.0 : 228.0,
    );
    final cardWidth = math.min((width - gutter * 2) * .48, 220.0);
    // Keep the original small cards; extra room adds another pair of previews.
    final cardHeight = math.max(54.0, math.min(_previewSpace, 228.0) * .57);
    final travel = areaHeight - cardHeight;
    final positions = _previewCapacity == 6
        ? const [
            Offset(0, .01),
            Offset(1, .08),
            Offset(.08, .46),
            Offset(.94, .54),
            Offset(.02, .92),
            Offset(.98, 1),
          ]
        : const [
            Offset(0, .02),
            Offset(1, .2),
            Offset(.08, .88),
            Offset(.94, 1),
          ];
    return [
      for (final position in positions.take(previewCount))
        Rect.fromLTWH(
          gutter - 2 + position.dx * (width - gutter * 2 + 2 - cardWidth),
          topInset + travel * position.dy,
          cardWidth,
          cardHeight,
        ),
    ];
  }();

  late final previewBottom = scattered.isEmpty
      ? math.min(_previewSpace, 180.0)
      : scattered.map((rect) => rect.bottom).reduce(math.max);

  double progress(double offset, {required bool reduced}) {
    final value = (offset / collapseExtent).clamp(0.0, 1.0);
    return reduced ? value : Curves.easeInOutCubic.transform(value);
  }

  Rect cardRect(int index, double progress) =>
      Rect.lerp(scattered[index], settled[index], progress)!;

  double composerOverlap(double offset, double progress) {
    if (previewCount == 0) return 0;
    final headerShift = math.max(0.0, offset - collapseExtent);
    final cardsBottom =
        List.generate(
          previewCount,
          (i) => cardRect(i, progress).bottom,
        ).reduce(math.max) -
        headerShift;
    final olderThoughtsTop = maxExtent - offset;
    return math.max(
      0,
      math.max(cardsBottom - composerTop, composerTop - olderThoughtsTop),
    );
  }
}

class FlowOpening extends SliverPersistentHeaderDelegate {
  FlowOpening({
    required this.layout,
    required this.thoughts,
    required this.onOpen,
    required this.reduced,
    this.status,
  });

  final FlowSceneLayout layout;
  final List<ThoughtEntity> thoughts;
  final ValueChanged<ThoughtEntity> onOpen;
  final bool reduced;
  final Widget? status;

  @override
  double get minExtent => layout.minExtent;
  @override
  double get maxExtent => layout.maxExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = layout.progress(shrinkOffset, reduced: reduced);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (thoughts.isEmpty && status != null)
          Positioned(
            top: FlowSceneLayout.topInset,
            left: FlowSceneLayout.gutter,
            right: FlowSceneLayout.gutter,
            height: math.max(
              0,
              layout.previewBottom - FlowSceneLayout.topInset,
            ),
            child: Center(
              child: SingleChildScrollView(
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 15,
                    height: 1.5,
                  ),
                  child: status!,
                ),
              ),
            ),
          ),
        for (var i = 0; i < thoughts.length; i++)
          Positioned.fromRect(
            rect: layout.cardRect(i, progress),
            child: Transform.rotate(
              angle: reduced
                  ? 0
                  : lerpDouble(
                      [-.065, .07, -.035, .055, -.055, .04][i],
                      0,
                      progress,
                    )!,
              child: FlowThoughtCard(
                key: ValueKey('flow-thought-${thoughts[i].uuid}'),
                thought: thoughts[i],
                onTap: () => onOpen(thoughts[i]),
              ),
            ),
          ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant FlowOpening oldDelegate) => true;
}
