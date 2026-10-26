import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_paper.dart';

const diarySearchPrompts = [
  'When did I feel calm?',
  'That walk I wrote about',
  'A conversation worth keeping',
];

class DiarySearchOpening extends StatelessWidget {
  const DiarySearchOpening({
    super.key,
    required this.onSearch,
    required this.reduced,
  });

  final ValueChanged<String> onSearch;
  final bool reduced;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text(
        'Find a moment.',
        style: TextStyle(
          fontSize: 37,
          height: 1.12,
          fontWeight: FontWeight.w500,
          letterSpacing: -1.4,
          color: context.colors.onSurface,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'A feeling, a person, a day.\nStart with what you remember.',
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: context.colors.onSurfaceVariant,
        ),
      ),
      const Center(child: _MemoryIllustration()),
      Text(
        'TRY A QUESTION',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.7,
          fontWeight: FontWeight.w600,
          color: context.colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      DiarySearchPrompts(onSearch: onSearch, reduced: reduced),
      const SizedBox(height: 18),
    ],
  );
}

class DiarySearchPrompts extends StatelessWidget {
  const DiarySearchPrompts({
    super.key,
    required this.onSearch,
    required this.reduced,
  });

  final ValueChanged<String> onSearch;
  final bool reduced;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < diarySearchPrompts.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        Transform.rotate(
          angle: reduced ? 0 : [-.018, .012, -.01][i],
          child: Builder(
            builder: (context) {
              final paper = [
                NoteColorPreset.lavender,
                NoteColorPreset.sage,
                NoteColorPreset.sand,
              ][i].resolveColors(context.colors);
              return DiarySearchPaper(
                key: ValueKey('diary-search-prompt-$i'),
                color: paper.background,
                variant: i,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 17,
                ),
                onTap: () => onSearch(diarySearchPrompts[i]),
                child: Row(
                  children: [
                    Icon(
                      [
                        Icons.wb_sunny_outlined,
                        Icons.route_outlined,
                        Icons.chat_bubble_outline_rounded,
                      ][i],
                      size: 20,
                      color: paper.secondary,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        diarySearchPrompts[i],
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: paper.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.north_east_rounded,
                      size: 17,
                      color: paper.secondary,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ],
  );
}

class _MemoryIllustration extends StatelessWidget {
  const _MemoryIllustration();

  @override
  Widget build(BuildContext context) {
    final sage = NoteColorPreset.sage.resolveColors(context.colors);
    final sand = NoteColorPreset.sand.resolveColors(context.colors);
    return ExcludeSemantics(
      child: SizedBox(
        width: 270,
        height: 166,
        child: Stack(
          children: [
            Positioned(
              left: 28,
              top: 42,
              width: 110,
              height: 76,
              child: Transform.rotate(
                angle: -.17,
                child: DiarySearchPaper(
                  color: sage.background,
                  padding: EdgeInsets.zero,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              left: 116,
              top: 30,
              width: 112,
              height: 80,
              child: Transform.rotate(
                angle: .12,
                child: DiarySearchPaper(
                  color: sand.background,
                  variant: 1,
                  padding: EdgeInsets.zero,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              left: 66,
              top: 62,
              width: 126,
              height: 80,
              child: Transform.rotate(
                angle: -.035,
                child: DiarySearchPaper(
                  variant: 2,
                  padding: const EdgeInsets.all(18),
                  child: CustomPaint(
                    painter: _SearchInk(
                      ink: context.colors.primary,
                      lines: true,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _SearchInk(ink: context.colors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchInk extends CustomPainter {
  const _SearchInk({required this.ink, this.lines = false});

  final Color ink;
  final bool lines;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink.withValues(alpha: lines ? .25 : .8)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = lines ? 2 : 3.5;
    if (lines) {
      for (var i = 0; i < 3; i++) {
        canvas.drawLine(
          Offset(0, 6 + i * 13),
          Offset(size.width * [1, .75, .5][i], 5 + i * 13),
          pen,
        );
      }
      return;
    }
    const center = Offset(166, 75);
    canvas.drawCircle(center, 29, Paint()..color = ink.withValues(alpha: .055));
    canvas.drawCircle(center, 29, pen);
    canvas.drawLine(
      const Offset(187, 97),
      const Offset(213, 124),
      pen..strokeWidth = 8,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 21),
      3.4,
      .8,
      false,
      pen
        ..strokeWidth = 2
        ..color = ink.withValues(alpha: .35),
    );
    pen
      ..strokeWidth = 1.5
      ..color = ink.withValues(alpha: .5);
    final trail = Path()
      ..moveTo(47, 131)
      ..cubicTo(15, 136, 13, 110, 29, 105);
    canvas.drawPath(trail, pen);
    for (final point in [const Offset(226, 42), const Offset(40, 29)]) {
      final radius = point.dx > 200 ? 6.0 : 3.5;
      canvas.drawLine(
        point - Offset(radius, 0),
        point + Offset(radius, 0),
        pen,
      );
      canvas.drawLine(
        point - Offset(0, radius),
        point + Offset(0, radius),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_SearchInk oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.lines != lines;
}
