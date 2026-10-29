import 'dart:math' as math;

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:journal/common.dart';

import 'note_image_provider.dart';
import 'note_markdown_preview.dart';

class NoteCard extends StatelessWidget {
  const new({
    super.key,
    required this.note,
    required this.onTap,
    required this.index,
  });
  final NoteEntity note;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final art = NoteArtSelection.fromBackground(note.background);
    final colors = art.color.resolveColors(theme.colorScheme);
    final title = note.title.trim();
    final shape = _FoldedPaperBorder(
      side: BorderSide(color: colors.foreground.withValues(alpha: .09)),
    );
    final previewTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(
        bodyColor: colors.foreground,
        displayColor: colors.foreground,
      ),
    );
    // Tiles read as a uniform, compact excerpt: emphasis and headings use the
    // body style and blocks sit flush. Lists and tasks keep their markers.
    final body = previewTheme.textTheme.bodyMedium;
    const plain = TextStyle(
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
    );
    final markdownStyle = MarkdownStyleSheet.fromTheme(previewTheme).copyWith(
      p: body,
      h1: body,
      h2: body,
      h3: body,
      h4: body,
      h5: body,
      h6: body,
      strong: plain,
      em: plain,
      del: plain,
      a: plain.copyWith(color: colors.foreground),
      code: body?.copyWith(backgroundColor: Colors.transparent),
      blockquote: body,
      listBullet: body,
      tableHead: plain,
      tableBody: body,
      blockSpacing: 0,
      pPadding: EdgeInsets.zero,
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      h4Padding: EdgeInsets.zero,
      h5Padding: EdgeInsets.zero,
      h6Padding: EdgeInsets.zero,
      blockquotePadding: EdgeInsets.zero,
      blockquoteDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      tablePadding: EdgeInsets.zero,
      tableCellsPadding: EdgeInsets.zero,
      tableBorder: TableBorder.all(
        color: colors.foreground.withValues(alpha: .15),
      ),
    );

    return Material(
      color: colors.background,
      elevation: 1,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: .18),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (art.imageUrl case final imageUrl?)
            Positioned.fill(
              child: _NoteCardImage(
                image: noteImageProvider(imageUrl, art.imageSource),
                paperColor: colors.background,
              ),
            ),
          // Keep ink above the image and its wash so feedback stays visible.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: shape,
              splashColor: colors.foreground.withValues(alpha: .12),
              highlightColor: colors.foreground.withValues(alpha: .04),
              child: CustomPaint(
                painter: _PaperDetailsPainter(
                  inkColor: colors.foreground,
                  paperColor: colors.background,
                  shape: shape,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        // Leave the folded corner clear, even for long titles.
                        padding: const EdgeInsets.only(right: 14),
                        child: Text(
                          title.isEmpty ? 'Untitled note' : title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.foreground,
                            fontSize: 17,
                            height: 1.25,
                            letterSpacing: -.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (note.content.trim().isNotEmpty) ...[
                        const SizedBox(height: 9),
                        NoteMarkdownPreview(
                          data: note.content,
                          maxLines: switch (index % 3) {
                            0 => 7,
                            1 => 9,
                            _ => 6,
                          },
                          styleSheet: markdownStyle,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCardImage extends StatelessWidget {
  const _NoteCardImage({required this.image, required this.paperColor});

  final ImageProvider image;
  final Color paperColor;

  @override
  Widget build(BuildContext context) {
    final dark =
        ThemeData.estimateBrightnessForColor(paperColor) == Brightness.dark;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: ResizeImage.resizeIfNeeded(720, null, image),
              fit: BoxFit.cover,
              // A missing local file or failed download leaves colored paper.
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    paperColor.withValues(alpha: .94),
                    paperColor.withValues(alpha: .88),
                    paperColor.withValues(alpha: dark ? .82 : .72),
                  ],
                  stops: const [0, .5, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One outline controls the paper, image, border, shadow, and ink clipping.
class _FoldedPaperBorder extends OutlinedBorder {
  const _FoldedPaperBorder({super.side, this.fold = 26, this.radius = 14});

  final double fold;
  final double radius;

  double foldFor(Size size) => math.min(fold, size.shortestSide / 2);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = math.min(radius, rect.shortestSide / 2);
    final f = foldFor(rect.size);
    return Path()
      ..moveTo(rect.left + r, rect.top)
      ..lineTo(rect.right - f, rect.top)
      ..lineTo(rect.right, rect.top + f)
      ..lineTo(rect.right, rect.bottom - r)
      ..quadraticBezierTo(rect.right, rect.bottom, rect.right - r, rect.bottom)
      ..lineTo(rect.left + r, rect.bottom)
      ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - r)
      ..lineTo(rect.left, rect.top + r)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + r, rect.top)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inset = side.strokeInset;
    return copyWith(
      fold: math.max(0, fold - inset * (2 - math.sqrt2)),
      radius: math.max(0, radius - inset),
    ).getOuterPath(rect.deflate(inset), textDirection: textDirection);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty || side.style == BorderStyle.none) return;
    // Fill the border inward, keeping its edge inside the clipped paper.
    final border = getOuterPath(rect, textDirection: textDirection)
      ..fillType = PathFillType.evenOdd
      ..addPath(getInnerPath(rect, textDirection: textDirection), Offset.zero);
    canvas.drawPath(border, Paint()..color = side.color);
  }

  @override
  _FoldedPaperBorder copyWith({
    BorderSide? side,
    double? fold,
    double? radius,
  }) => _FoldedPaperBorder(
    side: side ?? this.side,
    fold: fold ?? this.fold,
    radius: radius ?? this.radius,
  );

  @override
  ShapeBorder scale(double t) => _FoldedPaperBorder(
    side: side.scale(t),
    fold: fold * t,
    radius: radius * t,
  );

  @override
  bool operator ==(Object other) =>
      other is _FoldedPaperBorder &&
      other.side == side &&
      other.fold == fold &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(side, fold, radius);
}

class _PaperDetailsPainter extends CustomPainter {
  const _PaperDetailsPainter({
    required this.inkColor,
    required this.paperColor,
    required this.shape,
  });

  final Color inkColor;
  final Color paperColor;
  final _FoldedPaperBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final f = shape.foldFor(size);
    final corner = math.min(5.0, f / 4);
    final fold = Path()
      ..moveTo(size.width - f, 0)
      ..lineTo(size.width - f, f - corner)
      ..quadraticBezierTo(size.width - f, f, size.width - f + corner, f)
      ..lineTo(size.width, f)
      ..close();
    canvas.drawShadow(fold, inkColor.withValues(alpha: .22), 3, false);
    canvas.drawPath(
      fold,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color.lerp(paperColor, inkColor, .04)!,
            Color.lerp(paperColor, Colors.white, .16)!,
            Color.lerp(paperColor, inkColor, .13)!,
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromLTWH(size.width - f, 0, f, f)),
    );
  }

  @override
  bool shouldRepaint(_PaperDetailsPainter oldDelegate) =>
      inkColor != oldDelegate.inkColor ||
      paperColor != oldDelegate.paperColor ||
      shape != oldDelegate.shape;
}
