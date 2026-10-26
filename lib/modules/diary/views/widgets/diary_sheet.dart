import 'package:journal/common.dart' hide DiaryDayEntity;
import 'package:journal/modules/diary/models/diary_day_entity.dart';
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

  final DiaryDayEntity day;
  final double radius;
  final double scrollOffset;
  final DiaryPaperShape? shape;
  final bool shadow;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final outline =
        shape ??
        DiaryPaperShape.forDate(day.calendarDate, cornerRadius: radius);
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
              variant: day.calendarDate.weekday,
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

  final DiaryDayEntity day;

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

  (String, String?, String, bool)? _contentKey;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final key = (day.dateString, day.dayTitle, day.itemsJson, day.isDeleted);
    if (_content == null || _contentKey != key) {
      _content = _buildContent(context, day);
      _contentKey = key;
    }
    return _content!;
  }

  // Moving wrappers reuse their paragraphs until the entity or theme changes.
  Widget _buildContent(BuildContext context, DiaryDayEntity day) {
    final items = day.visibleItems.toList();
    final title = day.isDeleted ? '' : day.dayTitle?.trim() ?? '';
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
              'SAMPLE DAY  ·  ${TimeHelper.format(day.calendarDate, pattern: TimeFormat.shortWeekdayDate, toLocal: false)}',
              style: TextStyle(
                color: paper.secondary,
                fontSize: 10,
                letterSpacing: 1.1,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            if (title.isNotEmpty) ...[
              Text(
                title,
                style: TextStyle(
                  fontSize: 29,
                  height: 1.16,
                  letterSpacing: -.9,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 26),
            ],
            if (items.isEmpty)
              const Text('No diary entries for this day.')
            else ...[
              for (final item in items) ...[
                Text(item.content.trim(), key: ValueKey(item.itemUuid)),
                const SizedBox(height: 26),
              ],
              Text(
                'A day, held here.',
                key: ValueKey(
                  'diary-end-${day.calendarDate.toIso8601String()}',
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: paper.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
