import 'package:flutter/services.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_paper.dart';
import 'package:journal/modules/diary/views/widgets/diary_search_scene.dart';

const diarySearchPrompts = [
  'When did I feel calm?',
  'That walk I wrote about',
  'A conversation worth keeping',
  'A quiet morning with coffee',
  'Making a little space',
  'The sound of rain',
];

const _otherPrompts = [
  'A different route on my walk',
  'A familiar album on a busy day',
  'A message that arrived at the right time',
  'A note I left myself',
  'Small intentions for the day',
  'An ordinary conversation',
];

class DiarySearchOpening extends StatelessWidget {
  const DiarySearchOpening({
    super.key,
    required this.onSearch,
    required this.reduced,
    this.compact = false,
  });

  final ValueChanged<String> onSearch;
  final bool reduced;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Center(
            child: SizedBox(
              height: compact ? 100 : 156,
              child: DiarySearchScene(reduced: reduced, compact: compact),
            ),
          ),
        ),
        DiarySearchPrompts(onSearch: onSearch, reduced: reduced),
        const SizedBox(height: 18),
      ],
    );
  }
}

class DiarySearchPrompts extends StatefulWidget {
  const DiarySearchPrompts({
    super.key,
    required this.onSearch,
    required this.reduced,
  });

  final ValueChanged<String> onSearch;
  final bool reduced;

  @override
  State<DiarySearchPrompts> createState() => _DiarySearchPromptsState();
}

class _DiarySearchPromptsState extends State<DiarySearchPrompts> {
  bool _other = false;

  void _moreIdeas() {
    HapticFeedback.selectionClick();
    setState(() => _other = !_other);
  }

  @override
  Widget build(BuildContext context) {
    final prompts = _other ? _otherPrompts : diarySearchPrompts;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Try asking',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('diary-search-more-ideas'),
              onPressed: _moreIdeas,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('More ideas'),
              style: TextButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontSize: 11),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        TweenAnimationBuilder<double>(
          key: ValueKey(_other),
          tween: Tween(begin: 0, end: 1),
          duration: widget.reduced
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
          child: Column(
            children: [
              for (var i = 0; i < prompts.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                Transform.rotate(
                  angle: widget.reduced
                      ? 0
                      : [-.018, .012, -.01, .014, -.012, .008][i],
                  child: _QuestionCard(
                    key: ValueKey('diary-search-prompt-$i'),
                    query: prompts[i],
                    index: i,
                    icon: (_other
                        ? const [
                            Icons.directions_walk_outlined,
                            Icons.headphones_outlined,
                            Icons.message_outlined,
                            Icons.edit_note_outlined,
                            Icons.checklist_rounded,
                            Icons.forum_outlined,
                          ]
                        : const [
                            Icons.wb_sunny_outlined,
                            Icons.route_outlined,
                            Icons.chat_bubble_outline_rounded,
                            Icons.coffee_outlined,
                            Icons.spa_outlined,
                            Icons.water_drop_outlined,
                          ])[i],
                    onTap: () => widget.onSearch(prompts[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.query,
    required this.index,
    required this.icon,
    required this.onTap,
  });

  final String query;
  final int index;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = [
      NoteColorPreset.lavender,
      NoteColorPreset.sage,
      NoteColorPreset.sand,
      NoteColorPreset.sky,
      NoteColorPreset.rose,
      NoteColorPreset.paper,
    ][index].resolveColors(context.colors);
    return DiarySearchPaper(
      color: paper.background,
      variant: index,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            Icon(icon, size: 23, color: paper.secondary),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                query,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: paper.foreground,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.north_east_rounded, size: 17, color: paper.secondary),
          ],
        ),
      ),
    );
  }
}
