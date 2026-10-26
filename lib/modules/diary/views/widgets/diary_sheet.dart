import 'package:journal/common.dart' hide DiaryDayEntity;
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/views/pages/add_diary_photos_page.dart';
import 'package:journal/modules/diary/views/pages/add_diary_text_page.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_action.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_paper_stamp.dart';
import 'package:journal/modules/diary/views/widgets/diary_writing_prompt.dart';

/// Applies the cached device role without coupling paper previews to Riverpod.
class DiaryAccess extends InheritedWidget {
  const DiaryAccess({
    super.key,
    required this.canEdit,
    required this.today,
    required super.child,
  });
  final bool canEdit;
  final DateTime today;
  @override
  bool updateShouldNotify(DiaryAccess oldWidget) =>
      canEdit != oldWidget.canEdit || today != oldWidget.today;
}

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
    this.minimumHeight = 0,
  });

  final DiaryDayEntity day;
  final double radius;
  final double scrollOffset;
  final DiaryPaperShape? shape;
  final bool shadow;
  final bool detailed;

  // Use the fixed face bounds without a layout callback during page turns.
  final double minimumHeight;

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
        child: DiaryDayContent(day: day, minimumHeight: minimumHeight),
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
  const DiaryDayContent({super.key, required this.day, this.minimumHeight = 0})
    : assert(minimumHeight >= 0 && minimumHeight < double.infinity);

  final DiaryDayEntity day;

  /// Centers an empty invitation while leaving the cached prose independent
  /// of the changing paper viewport.
  final double minimumHeight;

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
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minimumHeight),
      child: _content,
    );
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
          mainAxisAlignment: items.isEmpty
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              key: const ValueKey('diary-day-heading'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TimeHelper.format(
                    day.calendarDate,
                    pattern: TimeFormat.shortWeekdayDate,
                    toLocal: false,
                  ),
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
              ],
            ),
            if (items.isNotEmpty) ...[
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
            Padding(
              padding: EdgeInsets.only(top: 20, bottom: items.isEmpty ? 20 : 0),
              child: _DiaryAddActions(date: day.calendarDate),
            ),
            // A zero-height footer balances the space around the invitation.
            if (items.isEmpty) const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class _DiaryAddActions extends StatelessWidget {
  const _DiaryAddActions({required this.date});

  final DateTime date;

  void _openText(BuildContext context) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    context.nav.push<void>(
      AddDiaryTextPage(date: date),
      transition: reduced ? NavTransition.none : NavTransition.platform,
    );
  }

  void _openVoice(BuildContext context) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    FocusScope.of(context).unfocus();
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    context.nav.push<void>(
      const VoiceSessionPage(
        mode: VoiceSessionMode.conversation,
        title: 'Your day, out loud',
      ),
      transition: reduced ? NavTransition.none : NavTransition.fade,
    );
  }

  void _openPhotos(BuildContext context) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    FocusScope.of(context).unfocus();
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    context.nav.push<void>(
      AddDiaryPhotosPage(date: date),
      transition: reduced ? NavTransition.none : NavTransition.platform,
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.dependOnInheritedWidgetOfExactType<DiaryAccess>();
    if (access != null && !access.canEdit && date != access.today) {
      return const Text(
        'This device can add diary entries for today. Older days are read-only.',
      );
    }
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        key: const ValueKey('diary-add-actions'),
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: DiaryWritingPrompt(onTap: () => _openText(context)),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final action in DiaryPaperAction.values)
                  DiaryPaperActionButton(
                    action: action,
                    onPressed: switch (action) {
                      DiaryPaperAction.voice => () => _openVoice(context),
                      DiaryPaperAction.image => () => _openPhotos(context),
                      DiaryPaperAction.more => _noop,
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // The additional menu will be connected in a later pass.
  static void _noop() {}
}
