import 'package:journal/common.dart';
import 'package:journal/config/diary_typography.dart';
import 'package:journal/modules/diary/views/widgets/diary_memory_material.dart';
import 'package:journal/modules/diary/views/widgets/diary_photo_story_strip.dart';

/// One piece of writing on the sheet, shared by reading and curl snapshots.
class DiaryNotebookEntry extends StatelessWidget {
  const DiaryNotebookEntry({
    super.key,
    required this.item,
    this.onOpenPhotos,
    this.onOpenConversation,
  });

  final DiaryItem item;
  final VoidCallback? onOpenPhotos, onOpenConversation;

  @override
  Widget build(BuildContext context) {
    final typography = DiaryTypography.of(context);
    final ink = context.colors.onSurface;
    final content = item.content.trim();
    final conversation = item.aiConversation;
    final hasConversation = conversation?.turns.isNotEmpty ?? false;
    final excerpt = content.isNotEmpty || !hasConversation
        ? null
        : conversation!.turns
              .where((t) => t['speaker'] == 'user')
              .map((t) => t['text']?.trim() ?? '')
              .where((t) => t.isNotEmpty)
              .firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item.photos.isNotEmpty)
          DiaryPhotoStoryStrip(item: item, onOpen: onOpenPhotos),
        if (content.isNotEmpty)
          Text(
            content,
            key: ValueKey(item.itemUuid),
            style: typography.body.copyWith(color: ink),
          ),
        if (hasConversation) ...[
          if (content.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14),
              child: Text(
                excerpt ?? 'Conversation saved.',
                key: ValueKey('diary-conversation-excerpt-${item.itemUuid}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typography.body.copyWith(
                  color: ink,
                  fontSize: 16,
                  height: 1.6,
                ),
              ),
            ),
          _ConversationAnnotation(
            id: item.itemUuid,
            label: content.isEmpty
                ? 'Open conversation'
                : 'From a conversation',
            onOpen: onOpenConversation,
          ),
        ],
      ],
    );
  }
}

class _ConversationAnnotation extends StatelessWidget {
  const _ConversationAnnotation({
    required this.id,
    required this.label,
    this.onOpen,
  });
  final String id, label;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onOpen != null,
    label: label,
    onTap: onOpen,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('diary-conversation-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(8, 12),
                  painter: _NotebookMark(ink: context.colors.onSurfaceVariant),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: context.colors.onSurfaceVariant,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: DiaryInkGlyph(
                    symbol: DiaryInkSymbol.arrow,
                    color: context.colors.onSurfaceVariant,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A brief pencil mark between entries, rather than another container.
class DiaryEntryBreak extends StatelessWidget {
  const DiaryEntryBreak({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 23),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: CustomPaint(
        size: const Size(24, 3),
        painter: _NotebookMark(
          ink: context.colors.onSurfaceVariant,
          dash: true,
        ),
      ),
    ),
  );
}

class _NotebookMark extends CustomPainter {
  const _NotebookMark({required this.ink, this.dash = false});
  final Color ink;
  final bool dash;
  static final _dash = Path()
    ..moveTo(0, 1.8)
    ..quadraticBezierTo(12, .5, 23, 1.5);
  static final _quotes = Path()
    ..moveTo(2, 2)
    ..quadraticBezierTo(0, 5, 1, 7)
    ..moveTo(7, 1)
    ..quadraticBezierTo(5, 4, 6, 6);

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    dash ? _dash : _quotes,
    Paint()
      ..color = ink.withValues(alpha: dash ? .35 : .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85
      ..strokeCap = StrokeCap.round,
  );

  @override
  bool shouldRepaint(_NotebookMark oldDelegate) =>
      ink != oldDelegate.ink || dash != oldDelegate.dash;
}
