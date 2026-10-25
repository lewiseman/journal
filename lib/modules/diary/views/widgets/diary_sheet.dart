import 'package:intl/intl.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/models/diary_day.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';

NoteColors diaryPaperColors(BuildContext context) => NoteColors(
  background: context.colors.surface,
  foreground: context.colors.onSurface,
  secondary: context.colors.onSurfaceVariant,
);

/// The static face used for previews and curls has no scrollable or layers.
/// Its clipped overflow is exactly the beginning of the live reading view.
class DiarySheet extends StatelessWidget {
  const DiarySheet({
    super.key,
    required this.day,
    this.radius = 6,
    this.scrollOffset = 0,
    this.shape,
    this.shadow = false,
    this.detailed = true,
  });

  final DiaryDay day;
  final double radius;
  final double scrollOffset;
  final DiaryPaperShape? shape;
  final bool shadow;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final outline =
        shape ?? DiaryPaperShape.forDate(day.date, cornerRadius: radius);
    final paper = diaryPaperColors(context);
    final content = OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: Offset(0, -scrollOffset),
        child: DiaryDayContent(day: day),
      ),
    );
    return CustomPaint(
      painter: detailed
          ? DiaryPaperPainter(
              shape: outline,
              paper: paper.background,
              ink: paper.foreground,
              shadow: shadow,
              shadowColor: context.colors.shadow,
            )
          : DiaryPaperStamp(
              paper: paper.background,
              ink: paper.foreground,
              shadow: shadow,
              shadowColor: context.colors.shadow,
              variant: day.date.weekday,
              flatten: outline.expansion,
            ),
      child: detailed
          ? ClipPath(clipper: DiaryPaperClipper(outline), child: content)
          : ClipRect(
              clipper: _StampContentClipper(outline.detail),
              child: content,
            ),
    );
  }
}

class _StampContentClipper extends CustomClipper<Rect> {
  const _StampContentClipper(this.detail);
  final double detail;

  @override
  Rect getClip(Size size) => (Offset.zero & size).deflate(8 * detail);

  @override
  bool shouldReclip(_StampContentClipper oldClipper) =>
      detail != oldClipper.detail;
}

class DiaryDayContent extends StatefulWidget {
  const DiaryDayContent({super.key, required this.day});

  final DiaryDay day;

  @override
  State<DiaryDayContent> createState() => _DiaryDayContentState();
}

class _DiaryDayContentState extends State<DiaryDayContent> {
  Widget? _content;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content = null;
  }

  @override
  void didUpdateWidget(DiaryDayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day) _content = null;
  }

  @override
  Widget build(BuildContext context) =>
      _content ??= _buildContent(context, widget.day);

  // A turn rebuilds the moving wrappers, not every paragraph and checklist.
  // Inherited theme changes and a replacement day invalidate this small cache.
  Widget _buildContent(BuildContext context, DiaryDay day) {
    final paper = diaryPaperColors(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyLarge!
            .copyWith(color: paper.foreground, fontSize: 16, height: 1.65),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SAMPLE DAY  ·  ${DateFormat('EEE, d MMM y').format(day.date)}',
              style: TextStyle(
                color: paper.secondary,
                fontSize: 10,
                letterSpacing: 1.1,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              day.title,
              style: TextStyle(
                fontSize: 29,
                height: 1.16,
                letterSpacing: -.9,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 26),
            for (final item in day.items) ...[
              _DiaryItemView(item: item, paper: paper),
              const SizedBox(height: 26),
            ],
            Text(
              'A day, held here.',
              key: ValueKey('diary-end-${day.date.toIso8601String()}'),
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: paper.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaryItemView extends StatelessWidget {
  const _DiaryItemView({required this.item, required this.paper});

  final DiaryItem item;
  final NoteColors paper;

  @override
  Widget build(BuildContext context) {
    final heading = TextStyle(
      color: paper.secondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: .6,
    );
    switch (item.kind) {
      case DiaryItemKind.mood:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wb_sunny_outlined, color: paper.secondary, size: 23),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: heading),
                  Text(item.text, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        );
      case DiaryItemKind.note:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: paper.foreground.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(
                color: context.colors.primary.withValues(alpha: .35),
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: heading),
              const SizedBox(height: 6),
              Text(item.text, style: const TextStyle(fontSize: 15)),
            ],
          ),
        );
      case DiaryItemKind.checklist:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: heading),
            const SizedBox(height: 10),
            for (final task in item.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  label:
                      '${task.text}, ${task.done ? 'completed' : 'not completed'}',
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          task.done
                              ? Icons.check_circle_outline_rounded
                              : Icons.circle_outlined,
                          size: 19,
                          color: paper.secondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          task.text,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      case DiaryItemKind.reflection:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: heading),
            const SizedBox(height: 8),
            Text(item.text),
          ],
        );
    }
  }
}
