import 'dart:typed_data';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';

typedef DiaryContactPhoto = ({String path, Uint8List bytes, bool hasWords});

class DiaryPhotoContactSheet extends StatelessWidget {
  const DiaryPhotoContactSheet({
    super.key,
    required this.photos,
    required this.selected,
    required this.controller,
    required this.onSelect,
    required this.onReorder,
    required this.onAdd,
  });

  final List<DiaryContactPhoto> photos;
  final int selected;
  final ScrollController controller;
  final ValueChanged<int> onSelect;
  final ReorderCallback onReorder;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return CustomPaint(
      painter: _FilmStripPainter(
        base: context.colors.surfaceContainerHighest,
        holes: palette.desk,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: SizedBox(
          height: 78 + (MediaQuery.textScalerOf(context).scale(9) - 9),
          child: Row(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  key: const ValueKey('diary-photo-contact-sheet'),
                  scrollController: controller,
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  itemExtent: 74,
                  itemCount: photos.length,
                  onReorderItem: onReorder,
                  proxyDecorator: (child, index, animation) => AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (_, child) => Transform.rotate(
                      angle: reduced ? 0 : -.045 * animation.value,
                      child: Transform.scale(
                        scale: reduced ? 1 : 1 + .06 * animation.value,
                        child: child,
                      ),
                    ),
                  ),
                  itemBuilder: (context, index) =>
                      ReorderableDelayedDragStartListener(
                        key: ValueKey(photos[index].path),
                        index: index,
                        child: Center(
                          child: Semantics(
                            hint: 'Hold and drag to reorder',
                            child: DiaryPhotoThumbnail(
                              key: ValueKey('diary-photo-thumbnail-$index'),
                              bytes: photos[index].bytes,
                              label: 'Photo ${index + 1} of ${photos.length}',
                              selected: selected == index,
                              hasReflection: photos[index].hasWords,
                              number: index + 1,
                              onTap: () => onSelect(index),
                            ),
                          ),
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 6),
              DiaryInkAction(
                label: 'Add more photos',
                tooltip: 'Add more photos',
                onPressed: onAdd,
                child: SizedBox(
                  width: 48,
                  child: Center(
                    child: DiaryInkGlyph(
                      symbol: DiaryInkSymbol.add,
                      color: palette.ink.withValues(
                        alpha: onAdd == null ? .35 : .85,
                      ),
                      size: 25,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilmStripPainter extends CustomPainter {
  const _FilmStripPainter({required this.base, required this.holes});
  final Color base, holes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      Paint()..color = base,
    );
    final hole = Paint()..color = holes;
    for (var x = 9.0; x < size.width - 7; x += 14) {
      for (final y in [4.0, size.height - 8]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 6, 4),
            const Radius.circular(.7),
          ),
          hole,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FilmStripPainter oldDelegate) =>
      base != oldDelegate.base || holes != oldDelegate.holes;
}
