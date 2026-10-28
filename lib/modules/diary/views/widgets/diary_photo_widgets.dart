import 'dart:typed_data';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

/// A loose print with room for a caption written on its paper border.
class DiaryPhotoFrame extends StatelessWidget {
  const DiaryPhotoFrame({
    super.key,
    required this.bytes,
    required this.label,
    required this.height,
    this.trailing,
    this.caption,
    this.onTap,
  });
  final Uint8List bytes;
  final String label;
  final double height;
  final Widget? trailing, caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 10, 5, 5),
          child: CustomPaint(
            painter: DiaryPaperStamp(
              paper: palette.paper,
              ink: palette.ink,
              shadowColor: context.colors.shadow,
              edgeScale: .4,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DiaryInkAction(
                    label: label,
                    onPressed: onTap,
                    child: SizedBox(
                      width: double.infinity,
                      height: height,
                      child: DiaryPhotoImage(bytes: bytes),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: .7,
                              fontStyle: FontStyle.italic,
                              color: palette.muted,
                            ),
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  ?caption,
                ],
              ),
            ),
          ),
        ),
        ExcludeSemantics(
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -.07,
              child: Container(
                width: 68,
                height: 22,
                color: palette.tabs[0].withValues(alpha: .8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DiaryPhotoImage extends StatelessWidget {
  const DiaryPhotoImage({
    super.key,
    required this.bytes,
    this.fit = BoxFit.cover,
  });

  final Uint8List bytes;
  final BoxFit fit;

  /// Empty [bytes] mean the saved copy isn't on this device.
  @override
  Widget build(BuildContext context) => bytes.isEmpty
      ? const DiaryMissingPhoto()
      : Image.memory(
          bytes,
          fit: fit,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stack) => ColoredBox(
            color: context.colors.surfaceContainer,
            child: Center(
              child: Tooltip(
                message: 'This photo could not be displayed',
                child: Icon(
                  Icons.broken_image_outlined,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
}

/// Shown where a saved photo has no copy here, usually because another
/// device added it: sync shares the story's words, never the image.
class DiaryMissingPhoto extends StatelessWidget {
  const DiaryMissingPhoto({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Photo not on this device',
    child: ColoredBox(
      color: context.colors.surfaceContainer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icon = Icon(
            Icons.hide_image_outlined,
            color: context.colors.onSurfaceVariant,
          );
          // Small prints keep the icon; the tooltip still names the reason.
          if (constraints.maxHeight < 90 || constraints.maxWidth < 90) {
            return Center(
              child: Tooltip(message: 'Not on this device', child: icon),
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 6),
                Text(
                  'Not on this device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class DiaryPhotoThumbnail extends StatelessWidget {
  const DiaryPhotoThumbnail({
    super.key,
    required this.bytes,
    required this.label,
    required this.selected,
    required this.hasReflection,
    required this.onTap,
    this.number = 1,
  });
  final Uint8List bytes;
  final String label;
  final bool selected, hasReflection;
  final VoidCallback onTap;
  final int number;

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    return DiaryInkAction(
      label: hasReflection ? '$label, has reflections' : label,
      selected: selected,
      onPressed: onTap,
      child: SizedBox(
        width: 64,
        child: CustomPaint(
          painter: DiaryPaperStamp(
            paper: selected ? palette.paper : palette.tabs[2],
            ink: palette.ink,
            edgeScale: .18,
            shadow: false,
            variant: number,
          ),
          foregroundPainter: selected
              ? DiaryInkUnderline(ink: palette.ink)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 5, 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 54,
                  height: 40,
                  child: DiaryPhotoImage(bytes: bytes),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        number.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 9,
                          color: palette.ink,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    if (hasReflection)
                      DiaryInkGlyph(
                        symbol: DiaryInkSymbol.check,
                        color: palette.ink,
                        size: 12,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DiaryPhotoInvitation extends StatelessWidget {
  const DiaryPhotoInvitation({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    Widget print(bool front) => CustomPaint(
      painter: DiaryPaperStamp(
        paper: palette.paper,
        ink: palette.ink,
        shadowColor: context.colors.shadow,
        edgeScale: .3,
        variant: front ? 1 : 2,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 29),
        child: SizedBox(
          width: 125,
          height: 131,
          child: ColoredBox(
            color: palette.tabs[front ? 2 : 0],
            child: Center(
              child: DiaryInkGlyph(
                symbol: front ? DiaryInkSymbol.landscape : DiaryInkSymbol.sun,
                color: palette.ink.withValues(alpha: .5),
                size: front ? 60 : 40,
              ),
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        height: 220,
        width: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: const Offset(-28, -3),
              child: Transform.rotate(angle: -.16, child: print(false)),
            ),
            Transform.translate(
              offset: const Offset(25, 9),
              child: Transform.rotate(angle: .11, child: print(true)),
            ),
            PositionedDirectional(
              end: 9,
              top: 5,
              child: DiaryInkGlyph(
                symbol: DiaryInkSymbol.sprig,
                color: palette.ink.withValues(alpha: .6),
                size: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
