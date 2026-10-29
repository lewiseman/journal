import 'dart:math' as math;

import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_paper.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_scene.dart';

/// Indeterminate activity, without invented progress percentages or stages.
class DiarySearchLoading extends StatefulWidget {
  const DiarySearchLoading({
    super.key,
    required this.query,
    required this.reduced,
    required this.compact,
  });

  final String query;
  final bool reduced, compact;

  @override
  State<DiarySearchLoading> createState() => _DiarySearchLoadingState();
}

class _DiarySearchLoadingState extends State<DiarySearchLoading>
    with SingleTickerProviderStateMixin {
  late final _scan = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduced) _scan.repeat();
  }

  @override
  void didUpdateWidget(DiarySearchLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduced == widget.reduced) return;
    if (widget.reduced) {
      _scan.stop();
      _scan.value = 0;
    } else {
      _scan.repeat();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(height: widget.compact ? 8 : 30),
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _scan,
          builder: (context, _) => SizedBox(
            height: widget.compact ? 136 : 210,
            child: DiarySearchScene(
              reduced: widget.reduced,
              compact: widget.compact,
              searchProgress: widget.reduced ? null : _scan.value,
            ),
          ),
        ),
      ),
      const SizedBox(height: 26),
      Semantics(
        liveRegion: true,
        child: Text(
          'Looking through\nyour journal…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 27,
            height: 1.25,
            letterSpacing: -.7,
            color: context.colors.onSurface,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Finding the moments behind your words.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          height: 1.6,
          color: context.colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 22),
      ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _scan,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.colors.primary.withValues(
                        alpha: widget.reduced
                            ? .5
                            : .25 +
                                  .55 *
                                      (math.sin(_scan.value * math.pi * 2 - i) +
                                          1) /
                                      2,
                      ),
                    ),
                    child: const SizedBox(width: 6, height: 6),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DiarySearchPaper(
          color: context.colors.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 19,
                color: context.colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.query,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                    color: context.colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
    ],
  );
}
