import 'dart:typed_data';

import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_ink_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_widgets.dart';

typedef DiaryPhotoStory = ({
  Uint8List bytes,
  String caption,
  List<({String question, String answer})> reflections,
});

class DiaryPhotoEntryBook extends StatefulWidget {
  const DiaryPhotoEntryBook({
    super.key,
    required this.stories,
    required this.onEnlarge,
    this.onEditPhotos,
    this.onReflect,
  });
  final List<DiaryPhotoStory> stories;
  final ValueChanged<int> onEnlarge;

  /// Null on a read-only device: the story can be read but not changed.
  final ValueChanged<int>? onReflect;
  final VoidCallback? onEditPhotos;

  @override
  State<DiaryPhotoEntryBook> createState() => _DiaryPhotoEntryBookState();
}

class _DiaryPhotoEntryBookState extends State<DiaryPhotoEntryBook> {
  final _showPrompts = <int>{};

  @override
  Widget build(BuildContext context) {
    final palette = DiaryMemoryPalette.of(context);
    final reflections = widget.stories.fold(
      0,
      (sum, story) => sum + story.reflections.length,
    );
    final summary =
        '${widget.stories.length} ${widget.stories.length == 1 ? 'photo' : 'photos'}${reflections > 0 ? ' · $reflections ${reflections == 1 ? 'reflection' : 'reflections'}' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                summary,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: palette.muted,
                ),
              ),
            ),
            if (widget.onEditPhotos != null)
              DiaryInkAction(
                label: 'Edit photos',
                onPressed: widget.onEditPhotos,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  child: Row(
                    children: [
                      DiaryInkGlyph(
                        symbol: DiaryInkSymbol.album,
                        color: palette.muted,
                        size: 16,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Edit photos',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: const Offset(3, 5),
                child: Transform.rotate(
                  angle: .008,
                  child: CustomPaint(
                    painter: DiaryPaperStamp(
                      paper: palette.tabs[0],
                      ink: palette.ink,
                      shadow: false,
                      edgeScale: .5,
                      variant: 2,
                    ),
                  ),
                ),
              ),
            ),
            CustomPaint(
              painter: DiaryPaperStamp(
                paper: palette.paper,
                ink: palette.ink,
                shadowColor: context.colors.shadow,
                edgeScale: .65,
                variant: 1,
              ),
              foregroundPainter: _AlbumMarginPainter(ink: palette.ink),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(23, 24, 17, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, story) in widget.stories.indexed) ...[
                      _moment(index, story, palette),
                      if (index < widget.stories.length - 1) ...[
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 25,
                          child: CustomPaint(
                            painter: _MemoryStitchPainter(ink: palette.muted),
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: DiaryInkGlyph(
                        symbol: DiaryInkSymbol.sprig,
                        color: palette.muted.withValues(alpha: .45),
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _moment(int index, DiaryPhotoStory story, DiaryMemoryPalette palette) {
    final prompts = _showPrompts.contains(index);
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Transform.rotate(
            angle: index.isEven ? -.025 : .022,
            child: LayoutBuilder(
              builder: (_, constraints) => DiaryPhotoFrame(
                bytes: story.bytes,
                label: 'MOMENT ${(index + 1).toString().padLeft(2, '0')}',
                height: (constraints.maxWidth * .62).clamp(130.0, 260.0),
                onTap: () => widget.onEnlarge(index),
              ),
            ),
          ),
        ),
        if (story.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 17, 9, 7),
            child: Text(
              story.caption,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                height: 1.6,
                color: palette.ink,
              ),
            ),
          ),
        if (story.reflections.isNotEmpty) ...[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DiaryInkAction(
              key: ValueKey('diary-entry-prompts-$index'),
              label:
                  '${prompts ? 'Hide' : 'Show'} prompts for photo ${index + 1}',
              selected: prompts,
              onPressed: () => setState(() {
                if (prompts) {
                  _showPrompts.remove(index);
                } else {
                  _showPrompts.add(index);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DiaryInkGlyph(
                      symbol: DiaryInkSymbol.pencil,
                      color: palette.muted,
                      size: 14,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      prompts ? 'Hide prompts' : 'Show prompts',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final reflection in story.reflections)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 2, 9, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSize(
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    alignment: AlignmentDirectional.topStart,
                    child: prompts
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Text(
                              reflection.question,
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                height: 1.5,
                                color: palette.muted,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Text(
                    reflection.answer,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.85,
                      color: palette.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (widget.onReflect != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DiaryInkAction(
              label: story.reflections.isEmpty
                  ? 'Find a few words'
                  : 'Revisit this moment',
              onPressed: () => widget.onReflect!(index),
              child: CustomPaint(
                foregroundPainter: DiaryInkUnderline(
                  ink: palette.muted,
                  dashed: true,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 13,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DiaryInkGlyph(
                        symbol: story.reflections.isEmpty
                            ? DiaryInkSymbol.add
                            : DiaryInkSymbol.pencil,
                        color: palette.muted,
                        size: 16,
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          story.reflections.isEmpty
                              ? 'Find a few words'
                              : 'Revisit this moment',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: palette.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlbumMarginPainter extends CustomPainter {
  const _AlbumMarginPainter({required this.ink});
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink.withValues(alpha: .06)
      ..strokeWidth = .6;
    canvas.drawLine(const Offset(16, 18), Offset(16, size.height - 18), pen);
    final hole = Paint()..color = ink.withValues(alpha: .12);
    for (var y = 32.0; y < size.height - 20; y += 84) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(10, y), width: 2, height: 3),
        hole,
      );
    }
  }

  @override
  bool shouldRepaint(_AlbumMarginPainter oldDelegate) => ink != oldDelegate.ink;
}

class _MemoryStitchPainter extends CustomPainter {
  const _MemoryStitchPainter({required this.ink});
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..strokeCap = StrokeCap.round;
    for (var x = 9.0; x < size.width - 8; x += 8) {
      if ((x - size.width / 2).abs() > 20) {
        canvas.drawLine(Offset(x, 12), Offset(x + 3, 12.5), pen);
      }
    }
    canvas.save();
    canvas.translate(size.width / 2 - 10, 2);
    DiaryInkGlyphPainter(
      kind: DiaryInkSymbol.sprig.index,
      ink: ink.withValues(alpha: .5),
    ).paint(canvas, const Size(20, 20));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MemoryStitchPainter oldDelegate) =>
      ink != oldDelegate.ink;
}
